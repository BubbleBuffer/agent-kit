import 'dart:convert';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

import '../tool/live_check_support.dart';

void main() {
  test('wire capture tees real chunks in line order and redacts all content', () async {
    final lines = <String>[];
    final trace = RedactedWireTrace(lines.add);
    final wire = utf8.encode('${jsonEncode({
      'jsonrpc': '2.0', 'method': 'event', 'params': {
        'type': 'approval_requested', 'sequence': 13,
        'session_id': 'synthetic-private-session',
        'approval': {'id': 'synthetic-private-approval', 'tool': 'exec',
          'arguments': {'command': 'echo SYNTHETIC_SECRET_MARKER',
            'SYNTHETIC_PRIVATE_KEY_NAME': 123456789},
          'path': '/synthetic/private/path',
          'unknown_SYNTHETIC_SECRET_FIELD': 'SYNTHETIC_SECRET_VALUE'},
      },
    })}\n');
    final source = Stream<List<int>>.fromIterable([
      wire.sublist(0, 9), wire.sublist(9),
    ]);
    final observed = await trace.tap('stdout', source).expand((b) => b).toList();
    expect(observed, wire);
    trace.add('stdin', utf8.encode('${jsonEncode({
      'jsonrpc': '2.0', 'id': 1, 'method': 'approval.decide', 'params': {
        'approval_id': 'synthetic-private-approval', 'decision': 'approve',
        'text': 'SYNTHETIC_SECRET_TEXT',
      },
    })}\n'));
    trace.add('stderr', utf8.encode('SYNTHETIC_SECRET_STDERR\n'));
    await trace.close();
    expect(lines, hasLength(3));
    final entries = lines.map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
    expect(entries.map((e) => e['order']), [1, 2, 3]);
    expect(entries.map((e) => e['direction']), ['stdout', 'stdin', 'stderr']);
    final captured = lines.join();
    expect(captured, contains('approval_requested'));
    expect(captured, contains('approval.decide'));
    expect(captured, contains('"decision":"approve"'));
    expect(captured, contains('"sequence":13'));
    expect(captured, isNot(contains('SYNTHETIC_')));
    expect(captured, isNot(contains('synthetic-private')));
    expect(captured, isNot(contains('/synthetic/private')));
    expect(captured, isNot(contains('123456789')));
    final notification = entries[0]['record']! as Map<String, Object?>;
    final params = notification['params']! as Map<String, Object?>;
    final approval = params['approval']! as Map<String, Object?>;
    final request = entries[1]['record']! as Map<String, Object?>;
    final decision = request['params']! as Map<String, Object?>;
    expect(approval['id'], decision['approval_id']);
  });

  test('malformed and incomplete wire lines never escape redaction', () async {
    final lines = <String>[];
    final trace = RedactedWireTrace(lines.add);
    trace.add('stdout', utf8.encode('SYNTHETIC_SECRET_NOT_JSON\n'));
    trace.add('stdout', utf8.encode('{"text":"SYNTHETIC_SECRET_PARTIAL"}'));
    await trace.close();
    expect(lines, hasLength(2));
    expect(lines.join(), isNot(contains('SYNTHETIC_SECRET')));
    expect(jsonDecode(lines.last), containsPair('complete', false));
  });

  test('unknown protocol strings and numbers are redacted', () async {
    final lines = <String>[];
    final trace = RedactedWireTrace(lines.add);
    trace.add('stdout', utf8.encode('${jsonEncode({
      'jsonrpc': '2.0', 'method': 'SYNTHETIC_SECRET_METHOD',
      'params': {'type': 'SYNTHETIC_SECRET_TYPE', 'exitCode': 123456789,
        'content': {'id': 'SYNTHETIC_SECRET_CONTENT', 'seq': 987654321}},
    })}\n'));
    await trace.close();
    expect(lines.single, isNot(contains('SYNTHETIC_SECRET')));
    expect(lines.single, isNot(contains('123456789')));
    expect(lines.single, isNot(contains('987654321')));
  });

  test('every distinct approval is answered, including after steering', () async {
    final decisions = <String>[];
    var steering = 0;
    final acceptance = LiveAcceptance(
      approve: (id) async { decisions.add(id); },
      steer: () async { steering++; return 'steering-input'; },
    );
    ApprovalRequested approval(int seq, String id) => ApprovalRequested(
      seq: seq, chat: 'chat', approval: Approval(
        id: id, tool: 'exec', requestedAt: DateTime.utc(2026),
      ),
    );
    acceptance.onEvent(approval(1, 'approval-one'));
    acceptance.onEvent(approval(2, 'approval-one'));
    acceptance.onEvent(const ToolStarted(
      seq: 3, chat: 'chat', callId: 'call-one', name: 'exec',
    ));
    await acceptance.settled;
    acceptance.onEvent(approval(4, 'approval-two'));
    acceptance.onEvent(const ToolFinished(
      seq: 5, chat: 'chat', callId: 'call-one', state: WorkState.done,
      output: ToolOutput(text: '{"exitCode":0}'),
    ));
    acceptance.onEvent(const ToolStarted(
      seq: 6, chat: 'chat', callId: 'call-two', name: 'exec',
    ));
    acceptance.onEvent(const ToolFinished(
      seq: 7, chat: 'chat', callId: 'call-two', state: WorkState.done, exitCode: 0,
    ));
    acceptance.onEvent(const UsageUpdated(
      seq: 8, chat: 'chat', usage: Usage(inputTokens: 20, outputTokens: 10),
    ));
    const terminal = RunFinished(seq: 9, chat: 'chat', runId: 'run');
    acceptance.onEvent(terminal);
    expect(await acceptance.finished, terminal);
    await acceptance.settled;
    acceptance.verify(terminal, 'run');
    expect(decisions, ['approval-one', 'approval-two']);
    expect(steering, 1);
    expect(acceptance.completedExecs, 2);
    expect(acceptance.usageUpdates, 1);
    acceptance.onEvent(const GapEvent(seq: 10, chat: 'chat'));
    expect(() => acceptance.verify(terminal, 'run'),
      throwsA(isA<LiveCheckFailure>()));
  });

  test('a failed approval rejects acceptance instead of leaving a silent wait', () async {
    final acceptance = LiveAcceptance(
      approve: (_) async { throw StateError('SYNTHETIC_SECRET_ERROR'); },
      steer: () async => 'unused',
    );
    final failed = expectLater(acceptance.finished, throwsA(isA<LiveCheckFailure>()));
    acceptance.onEvent(ApprovalRequested(
      seq: 1, chat: 'chat', approval: Approval(
        id: 'approval', tool: 'exec', requestedAt: DateTime.utc(2026),
      ),
    ));
    await failed;
    await acceptance.settled;
  });

  test('script requires explicit binary/config and a bounded timeout', () {
    expect(() => LiveCheckOptions.parse([]), throwsA(isA<LiveCheckFailure>()));
    expect(() => LiveCheckOptions.parse([
      '--binary', 'host', '--config', 'config', '--timeout-seconds', '0',
    ]), throwsA(isA<LiveCheckFailure>()));
    final options = LiveCheckOptions.parse([
      '--binary', 'host', '--config', 'config', '--', '--model', 'model',
    ]);
    expect(options.timeout, const Duration(seconds: 180));
    expect(options.hostArguments, ['--model', 'model']);
  });
}
