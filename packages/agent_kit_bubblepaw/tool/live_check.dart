// LIVE-MODEL ACCEPTANCE SCRIPT. Makes billable/provider-backed calls; NOT run in CI.
// Approves EVERY approval request in its new session. See README before running.
import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_bubblepaw/src/transport.dart';
import 'package:agent_kit_core/agent_kit_core.dart';

import 'live_check_support.dart';

const _steering =
    'Steering acceptance: after both exec commands finish, include '
    'STEERING_ACCEPTED in your final reply. Continue the original task.';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  var stage = 'options';
  Directory? temporary;
  RedactedWireTrace? trace;
  StdioBubblePawTransport? transport;
  BubblePawBackend? backend;
  StreamSubscription<KitEvent>? subscription;
  try {
    final options = LiveCheckOptions.parse(arguments);
    temporary = await Directory.systemTemp.createTemp('bubblepaw-live-');
    final workspace = await Directory(
      options.workspace ?? '${temporary.path}/workspace',
    ).create(recursive: true);
    final data = await Directory(
      options.dataDirectory ?? '${temporary.path}/data',
    ).create(recursive: true);
    if (!await data.list().isEmpty) {
      throw const LiveCheckFailure('data directory must be empty');
    }
    if (options.trace != null) {
      trace = await RedactedWireTrace.open(options.trace!);
    }
    stage = 'child startup';
    final process = await Process.start(options.binary, [
      '--workspace',
      workspace.absolute.path,
      '--data-dir',
      data.absolute.path,
      '--config',
      options.config,
      ...options.hostArguments,
      '--set',
      "agent.execution_mode='native'",
      '--set',
      "approvals.tools.exec='ask'",
      '--no-auto-summarize',
      'stdio',
    ]);
    // This script owns this exact process handle. The internal framing/lifecycle
    // implementation remains production code; only the byte pipes are teed.
    transport = StdioBubblePawTransport.forTesting(
      stdout: trace?.tap('stdout', process.stdout) ?? process.stdout,
      stdin: trace == null
          ? process.stdin
          : WireTeeSink(process.stdin, trace, 'stdin'),
      stderr: trace?.tap('stderr', process.stderr) ?? process.stderr,
      exitCode: process.exitCode,
      terminate: () {
        process.kill(ProcessSignal.sigkill);
      },
    );
    stage = 'protocol handshake';
    final connected = await BubblePawBackend.connect(
      transport,
      workspaceDirectory: workspace.absolute.path,
    );
    backend = connected;
    if (!connected.features.containsAll({'approvals', 'steer'})) {
      throw const LiveCheckFailure('host lacks approvals or steering');
    }
    final chat = await connected.createChat(title: 'Live adapter acceptance');
    final initial = await connected.loadChat(chat.id);
    final acceptance = LiveAcceptance(
      approve: (id) =>
          connected.decideApproval(chat.id, id, ApprovalDecision.approve),
      steer: () => connected.steer(chat.id, _steering),
    );
    subscription = connected
        .events(chat.id, after: initial.seq)
        .listen(
          acceptance.onEvent,
          onError: (Object _, StackTrace _) => acceptance.fail(),
          onDone: acceptance.closed,
        );
    stage = 'live run (approval, exec, steering, run.finished)';
    stdout.writeln(
      'Live acceptance started; every requested approval is approved.',
    );
    final clock = Stopwatch()..start();
    Future<T> within<T>(Future<T> operation) =>
        operation.timeout(options.timeout - clock.elapsed);
    final first = Platform.isWindows
        ? "Start-Sleep -Seconds 3; Write-Output 'EXEC_ONE'"
        : "sleep 3; printf 'EXEC_ONE\\n'";
    final second = Platform.isWindows
        ? "Write-Output 'EXEC_TWO'"
        : "printf 'EXEC_TWO\\n'";
    final sent = await within(
      connected.send(
        chat.id,
        'This is a live adapter acceptance check. Use only the exec tool in the '
        'current workspace. Do not read or change files, inspect the environment, '
        'access the network, or start background tasks. First call exec with command '
        '${_quoted(first)}, yieldMs 5000, timeoutMs 15000. Wait for completion '
        '(use wait if needed), then make a SECOND, separate exec call with '
        'command ${_quoted(second)}, yieldMs 5000, timeoutMs 15000. This must '
        'be two tool calls, not one combined command. The harness will approve '
        'each request and send steering while the first command runs. After '
        'both finish, briefly confirm both markers and any steering instruction.',
      ),
    );
    if (sent.delivery != SendDelivery.started || sent.runId == null) {
      throw const LiveCheckFailure('run was not started');
    }
    final finished = await within(acceptance.finished);
    await within(acceptance.settled);
    acceptance.verify(finished, sent.runId!);
    stage = 'canonical completion';
    final snapshot = await within(connected.loadChat(chat.id));
    if (!snapshot.items.whereType<UserMessage>().any(
      (m) => m.text == _steering,
    )) {
      throw const LiveCheckFailure('steering did not enter canonical history');
    }
    if (!snapshot.items.whereType<AssistantMessage>().any(
      (m) => !m.streaming && m.markdown.contains('STEERING_ACCEPTED'),
    )) {
      throw const LiveCheckFailure(
        'final assistant did not acknowledge steering',
      );
    }
    stdout.writeln(
      'PASS: ${acceptance.approvals} approvals answered, '
      '${acceptance.completedExecs} exec calls completed, steering delivered, '
      '${acceptance.usageUpdates} usage updates, ${acceptance.gaps} gaps, '
      'KIT run.finished completed and canonical reply verified.',
    );
  } on Object catch (error) {
    final reason = error is LiveCheckFailure ? ': ${error.message}' : '';
    // Exceptions may embed config, credentials, provider text or local paths.
    stderr.writeln('FAIL during $stage$reason. Details withheld for privacy.');
    exitCode = 1;
  } finally {
    await _cleanup(() async {
      await subscription?.cancel();
    });
    await _cleanup(() async {
      await backend?.dispose();
    });
    await _cleanup(() async {
      await transport?.dispose();
    });
    try {
      await trace?.close();
    } on Object {
      stderr.writeln('FAIL: redacted trace could not be completed.');
      exitCode = 1;
    }
    try {
      await temporary?.delete(recursive: true);
    } on Object {
      stderr.writeln('Temporary acceptance directories could not be removed.');
      exitCode = 1;
    }
  }
}

Future<void> _cleanup(Future<void> Function() action) async {
  try {
    await action();
  } on Object {
    stderr.writeln('FAIL: acceptance child cleanup did not complete.');
    exitCode = 1;
  }
}

String _quoted(String value) => '"${value.replaceAll('"', '\\"')}"';

const _usage = '''
Live model acceptance; NOT run in CI. Automatically approves every request.
dart run tool/live_check.dart --binary <bubblepaw> --config <private.toml>
  [--trace <new-redacted.jsonl>] [--timeout-seconds <180>]
  [--workspace <directory>] [--data-dir <empty-directory>]
  [-- <additional host arguments, such as --model MODEL>]
Workspace/data default to disposable temporary directories. Uses the private
config for provider authentication. Never put secrets in host arguments.
''';
