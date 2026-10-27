import 'dart:async';
import 'dart:convert';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

import '../tool/live_check_support.dart';

void main() {
  test(
    'missing terminal usage remains bounded and fails on stream closure',
    () async {
      final acceptance = await _diagnosticFixture(usage: false);
      const terminal = RunFinished(
        seq: 100,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        runId: 'SYNTHETIC_PRIVATE_RUN',
      );
      await expectLater(
        acceptance
            .verifyAfterUsage(terminal, terminal.runId)
            .timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final pending = expectLater(
        acceptance.verifyAfterUsage(terminal, terminal.runId),
        throwsA(isA<LiveCheckFailure>()),
      );
      acceptance.closed();
      await pending;
      expect(acceptance.usageUpdates, 0);
      expect(
        acceptance
            .diagnostics(expectedRunId: terminal.runId)
            .singleWhere((check) => check.name == 'usage')
            .passed,
        isFalse,
      );
    },
  );

  test('wire capture tees real chunks in line order and redacts all content', () async {
    final lines = <String>[];
    final trace = RedactedWireTrace(lines.add);
    final wire = utf8.encode(
      '${jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'approval_requested',
          'sequence': 13,
          'session_id': 'synthetic-private-session',
          'approval': {
            'id': 'synthetic-private-approval',
            'tool': 'exec',
            'arguments': {'command': 'echo SYNTHETIC_SECRET_MARKER', 'SYNTHETIC_PRIVATE_KEY_NAME': 123456789},
            'path': '/synthetic/private/path',
            'unknown_SYNTHETIC_SECRET_FIELD': 'SYNTHETIC_SECRET_VALUE',
          },
        },
      })}\n',
    );
    final source = Stream<List<int>>.fromIterable([
      wire.sublist(0, 9),
      wire.sublist(9),
    ]);
    final observed = await trace
        .tap('stdout', source)
        .expand((b) => b)
        .toList();
    expect(observed, wire);
    trace.add(
      'stdin',
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'approval.decide',
          'params': {'approval_id': 'synthetic-private-approval', 'decision': 'approve', 'text': 'SYNTHETIC_SECRET_TEXT'},
        })}\n',
      ),
    );
    trace.add('stderr', utf8.encode('SYNTHETIC_SECRET_STDERR\n'));
    await trace.close();
    expect(lines, hasLength(3));
    final entries = lines
        .map((line) => jsonDecode(line) as Map<String, Object?>)
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
    trace.add(
      'stdout',
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'method': 'SYNTHETIC_SECRET_METHOD',
          'params': {
            'type': 'SYNTHETIC_SECRET_TYPE',
            'exitCode': 123456789,
            'content': {'id': 'SYNTHETIC_SECRET_CONTENT', 'seq': 987654321},
          },
        })}\n',
      ),
    );
    await trace.close();
    expect(lines.single, isNot(contains('SYNTHETIC_SECRET')));
    expect(lines.single, isNot(contains('123456789')));
    expect(lines.single, isNot(contains('987654321')));
  });

  test(
    'every distinct approval is answered, including after steering',
    () async {
      final decisions = <String>[];
      var steering = 0;
      final acceptance = LiveAcceptance(
        approve: (id) async {
          decisions.add(id);
        },
        steer: () async {
          steering++;
          return 'steering-input';
        },
      );
      ApprovalRequested approval(int seq, String id) => ApprovalRequested(
        seq: seq,
        chat: 'chat',
        approval: Approval(
          id: id,
          tool: 'exec',
          requestedAt: DateTime.utc(2026),
        ),
      );
      acceptance.onEvent(approval(1, 'approval-one'));
      acceptance.onEvent(approval(2, 'approval-one'));
      acceptance.onEvent(
        const ToolStarted(
          seq: 3,
          chat: 'chat',
          callId: 'call-one',
          name: 'exec',
        ),
      );
      await acceptance.settled;
      acceptance.onEvent(approval(4, 'approval-two'));
      acceptance.onEvent(
        const ToolFinished(
          seq: 5,
          chat: 'chat',
          callId: 'call-one',
          state: WorkState.done,
          output: ToolOutput(text: '{"exitCode":0}'),
        ),
      );
      acceptance.onEvent(
        const ToolStarted(
          seq: 6,
          chat: 'chat',
          callId: 'call-two',
          name: 'exec',
        ),
      );
      acceptance.onEvent(
        const ToolFinished(
          seq: 7,
          chat: 'chat',
          callId: 'call-two',
          state: WorkState.done,
          exitCode: 0,
        ),
      );
      acceptance.onEvent(
        const UsageUpdated(
          seq: 8,
          chat: 'chat',
          usage: Usage(inputTokens: 20, outputTokens: 10),
        ),
      );
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
      expect(
        () => acceptance.verify(terminal, 'run'),
        throwsA(isA<LiveCheckFailure>()),
      );
    },
  );

  test(
    'a failed approval rejects acceptance instead of leaving a silent wait',
    () async {
      final acceptance = LiveAcceptance(
        approve: (_) async {
          throw StateError('SYNTHETIC_SECRET_ERROR');
        },
        steer: () async => 'unused',
      );
      final failed = expectLater(
        acceptance.finished,
        throwsA(isA<LiveCheckFailure>()),
      );
      acceptance.onEvent(
        ApprovalRequested(
          seq: 1,
          chat: 'chat',
          approval: Approval(
            id: 'approval',
            tool: 'exec',
            requestedAt: DateTime.utc(2026),
          ),
        ),
      );
      await failed;
      await acceptance.settled;
    },
  );

  test('script requires explicit binary/config and a bounded timeout', () {
    expect(() => LiveCheckOptions.parse([]), throwsA(isA<LiveCheckFailure>()));
    expect(
      () => LiveCheckOptions.parse([
        '--binary',
        'host',
        '--config',
        'config',
        '--timeout-seconds',
        '0',
      ]),
      throwsA(isA<LiveCheckFailure>()),
    );
    final options = LiveCheckOptions.parse([
      '--binary',
      'host',
      '--config',
      'config',
      '--',
      '--model',
      'model',
    ]);
    expect(options.timeout, const Duration(seconds: 180));
    expect(options.hostArguments, ['--model', 'model']);
  });

  test(
    'diagnostics identify independent failures and retain strict thresholds',
    () async {
      Future<void> check(
        Future<LiveAcceptance> fixture,
        Set<String> failed, {
        String expectedRunId = 'SYNTHETIC_PRIVATE_RUN',
      }) async {
        final acceptance = await fixture;
        final checks = acceptance.diagnostics(expectedRunId: expectedRunId);
        expect(checks, hasLength(8));
        expect(
          checks
              .where((check) => !check.passed)
              .map((check) => check.name)
              .toSet(),
          failed,
        );
        final report = checks.join('\n');
        expect(report, isNot(contains('SYNTHETIC_PRIVATE')));
        expect(report, isNot(contains('STEERING_ACCEPTED')));
        expect(report.split('\n'), everyElement(matches(r'^(PASS|FAIL): ')));
        const terminal = RunFinished(
          seq: 100,
          chat: 'SYNTHETIC_PRIVATE_CHAT',
          runId: 'SYNTHETIC_PRIVATE_RUN',
        );
        if (failed.isEmpty) {
          acceptance.verify(terminal, expectedRunId);
        } else {
          expect(
            () => acceptance.verify(terminal, expectedRunId),
            throwsA(isA<LiveCheckFailure>()),
          );
        }
      }

      await check(_diagnosticFixture(), {});
      await check(_diagnosticFixture(approvals: 1), {'approvals'});
      await check(_diagnosticFixture(successfulExecs: 1), {'exec finishes'});
      await check(_diagnosticFixture(usage: false), {'usage'});
      await check(_diagnosticFixture(gap: true), {'gaps'});
      await check(_diagnosticFixture(health: false), {'command/event health'});
      await check(_diagnosticFixture(), {
        'completion',
      }, expectedRunId: 'other-private-run');
      await check(_diagnosticFixture(failSteering: true), {
        'steering',
        'command/event health',
      });
      await check(_diagnosticFixture(execStarts: 1), {
        'exec starts',
        'exec finishes',
      });
    },
  );

  test(
    'diagnostics distinguish missing completion from failed completion',
    () async {
      final missing = await _diagnosticFixture(completion: false);
      final missingLine = missing
          .diagnostics(expectedRunId: 'SYNTHETIC_PRIVATE_RUN')
          .singleWhere((check) => check.name == 'completion');
      expect(missingLine.passed, isFalse);
      expect(
        missingLine.toString(),
        contains('events=0; matched=0; completed=0'),
      );
      final failed = await _diagnosticFixture(outcome: RunOutcome.failed);
      final failedLine = failed
          .diagnostics(expectedRunId: 'SYNTHETIC_PRIVATE_RUN')
          .singleWhere((check) => check.name == 'completion');
      expect(failedLine.passed, isFalse);
      expect(
        failedLine.toString(),
        contains('events=1; matched=1; completed=0'),
      );
    },
  );

  test(
    'canonical diagnostics report both history checks without content or IDs',
    () {
      const steering = 'SYNTHETIC_PRIVATE_STEERING';
      final missing = canonicalDiagnostics(null, steeringText: steering);
      expect(missing.every((check) => !check.passed), isTrue);
      final snapshot = ChatSnapshot(
        chatId: 'SYNTHETIC_PRIVATE_CHAT',
        items: [
          UserMessage(id: 'SYNTHETIC_PRIVATE_USER', text: steering),
          const AssistantMessage(
            id: 'SYNTHETIC_PRIVATE_ASSISTANT',
            markdown: 'SYNTHETIC_PRIVATE_CONTENT STEERING_ACCEPTED',
            streaming: true,
          ),
        ],
      );
      final checks = canonicalDiagnostics(snapshot, steeringText: steering);
      expect(checks.map((check) => check.passed), [true, true, false]);
      expect(checks.join('\n'), isNot(contains('SYNTHETIC_PRIVATE')));
      expect(checks.join('\n'), isNot(contains('STEERING_ACCEPTED')));
      final complete = ChatSnapshot(
        chatId: 'SYNTHETIC_PRIVATE_CHAT',
        items: [
          snapshot.items.first,
          const AssistantMessage(
            id: 'SYNTHETIC_PRIVATE_FINAL',
            markdown: 'SYNTHETIC_PRIVATE_CONTENT STEERING_ACCEPTED',
          ),
        ],
      );
      expect(
        canonicalDiagnostics(
          complete,
          steeringText: steering,
        ).every((check) => check.passed),
        isTrue,
      );
    },
  );
}

Future<LiveAcceptance> _diagnosticFixture({
  int approvals = 2,
  int execStarts = 2,
  int successfulExecs = 2,
  bool failSteering = false,
  bool usage = true,
  bool gap = false,
  bool health = true,
  bool completion = true,
  RunOutcome outcome = RunOutcome.completed,
}) async {
  final acceptance = LiveAcceptance(
    approve: (_) async {},
    steer: () async {
      if (failSteering) throw StateError('SYNTHETIC_PRIVATE_ERROR');
      return 'SYNTHETIC_PRIVATE_STEERING_ID';
    },
  );
  var seq = 0;
  for (var i = 0; i < approvals; i++) {
    acceptance.onEvent(
      ApprovalRequested(
        seq: ++seq,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        approval: Approval(
          id: 'SYNTHETIC_PRIVATE_APPROVAL_$i',
          tool: 'exec',
          requestedAt: DateTime.utc(2026),
        ),
      ),
    );
  }
  for (var i = 0; i < execStarts; i++) {
    acceptance.onEvent(
      ToolStarted(
        seq: ++seq,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        callId: 'SYNTHETIC_PRIVATE_CALL_$i',
        name: 'exec',
        arguments: '{"command":"SYNTHETIC_PRIVATE_COMMAND"}',
      ),
    );
    acceptance.onEvent(
      ToolFinished(
        seq: ++seq,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        callId: 'SYNTHETIC_PRIVATE_CALL_$i',
        state: WorkState.done,
        exitCode: i < successfulExecs ? 0 : 1,
        output: const ToolOutput(text: 'SYNTHETIC_PRIVATE_OUTPUT'),
      ),
    );
  }
  if (usage) {
    acceptance.onEvent(
      UsageUpdated(
        seq: ++seq,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        usage: const Usage(inputTokens: 20, outputTokens: 10),
      ),
    );
  }
  if (gap) {
    acceptance.onEvent(GapEvent(seq: ++seq, chat: 'SYNTHETIC_PRIVATE_CHAT'));
  }
  if (completion) {
    acceptance.onEvent(
      RunFinished(
        seq: ++seq,
        chat: 'SYNTHETIC_PRIVATE_CHAT',
        runId: 'SYNTHETIC_PRIVATE_RUN',
        outcome: outcome,
      ),
    );
  }
  if (!health) acceptance.fail();
  await acceptance.settled;
  return acceptance;
}
