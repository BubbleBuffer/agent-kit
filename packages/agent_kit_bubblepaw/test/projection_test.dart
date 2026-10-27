import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_bubblepaw/src/projection.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

// Synthetic recordings use the exact pinned stdio wire shapes, with public
// example content. They are not recordings of a user's conversation.
List<Map<String, Object?>> fixture(String name) =>
    File('test/fixtures/projection/$name.jsonl')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map(
          (line) =>
              Map<String, Object?>.of(jsonDecode(line) as Map<String, Object?>),
        )
        .toList();

Map<String, Object?> state({
  int seq = 0,
  String status = 'running',
  String streaming = '',
}) => {
  'session': {'id': 'session-a', 'title': 'Example', 'parent_session_id': null},
  'seq': seq,
  'messages': <Object?>[],
  'runs': [
    {
      'id': 'run-a',
      'model': 'example-model',
      'status': status,
      'started_at': '2026-01-02T03:00:00Z',
      'ended_at': null,
      'error': null,
    },
  ],
  'inputs': <Object?>[],
  'todo': <Object?>[],
  'question': null,
  'streaming_text': streaming,
};

Map<String, Object?> wire(
  String type,
  int sequence, {
  bool durable = true,
  Map<String, Object?> fields = const {},
}) => {
  'sequence': sequence,
  'durable': durable,
  'session_id': 'session-a',
  'run_id': 'run-a',
  'created_at': '2026-01-02T03:00:00Z',
  'type': type,
  ...fields,
};

void main() {
  test('provider telemetry does not interrupt the live reply with a gap', () {
    final projection = BubblePawProjection();
    var snapshot = projection.snapshot(state(), workspaceDirectory: '/example');
    snapshot = reduceAll(snapshot, projection.event(wire('run_started', 1)));
    expect(
      projection.event(
        wire(
          'host_state_changed',
          2,
          fields: {'key': 'usage.last_request', 'value': <String, Object?>{}},
        ),
      ),
      isEmpty,
    );
    final delta = projection.event(
      wire('text_delta', 2, durable: false, fields: {'text': 'Reply'}),
    );
    snapshot = reduceAll(snapshot, delta);
    expect(
      snapshot.items.whereType<AssistantMessage>().single.markdown,
      'Reply',
    );
    expect(snapshot.stale, isFalse);
    final finished = projection.event(
      wire('run_finished', 3, fields: {'status': 'completed', 'text': 'Reply'}),
    );
    expect(finished.whereType<RunFinished>(), hasLength(1));
  });

  test('canonical snapshot projects messages, tool outcomes, queue, plan and pending approvals', () {
    final projection = BubblePawProjection();
    final snapshot = projection.snapshot(
      fixture('snapshot').single,
      workspaceDirectory: '/example/workspace',
    );
    expect(snapshot.chatId, 'session-a');
    expect(snapshot.title, 'Example session');
    expect(snapshot.workspace?.name, 'workspace');
    expect(snapshot.seq, 15 * 16 + 15);
    expect(BubblePawProjection.hostSequence(snapshot.seq), 15);
    expect(snapshot.status, ChatStatus.needsYou);
    expect(snapshot.run?.outcome, RunOutcome.completed);
    expect(snapshot.items.whereType<UserMessage>().single.id, 'message-user');
    expect(snapshot.items.whereType<AssistantMessage>().map((m) => m.id), [
      'message-call',
      'message-final',
    ]);
    final tool =
        snapshot.items.whereType<ActivityGroup>().single.rows.single as ToolRow;
    expect(tool.id, 'call-a');
    expect(tool.state, WorkState.done);
    expect(tool.output?.text, '4');
    expect(tool.kind, ToolKind.other);
    expect(snapshot.queue.single.id, 'input-followup');
    expect(snapshot.queue.single.mode, QueueMode.followup);
    expect(snapshot.planDone, 2);
    expect(snapshot.pendingApprovals.single.id, 'approval-restored');
    expect(
      snapshot.usage?.inputTokens,
      100,
    ); // own, not descendant-inclusive total
    expect(snapshot.usage?.contextTokens, 100);
    expect(snapshot.context, isNull);
    expect(snapshot.children, isEmpty);
    expect(snapshot.jobs, isEmpty);
  });

  test('all main host events reduce without losing terminal subevents', () {
    final projection = BubblePawProjection();
    var snapshot = projection.snapshot(state(), workspaceDirectory: '/example');
    final events = <KitEvent>[];
    for (final record in fixture('events')) {
      final projected = projection.event(record);
      events.addAll(projected);
      snapshot = reduceAll(snapshot, projected);
      final params = record['params'];
      final source = params is Map<String, Object?> ? params : record;
      if (source['type'] == 'run_waiting_for_quota') {
        expect(snapshot.run?.isWaiting, isTrue);
        expect(snapshot.run?.waitingUntil, DateTime.utc(2026, 1, 2, 4));
      }
      if (source['type'] == 'run_quota_resumed') {
        expect(snapshot.run?.isWaiting, isFalse);
      }
    }
    expect(snapshot.run?.outcome, RunOutcome.completed);
    expect(snapshot.status, ChatStatus.done);
    expect(
      snapshot.items.whereType<AssistantMessage>().single.markdown,
      'The result is 4.',
    );
    expect(
      snapshot.items.whereType<AssistantMessage>().single.streaming,
      isFalse,
    );
    expect(
      snapshot.items
          .whereType<ActivityGroup>()
          .single
          .rows
          .whereType<ToolRow>()
          .single
          .output
          ?.text,
      '4',
    );
    expect(snapshot.approvals.single.state, ApprovalState.approvedForSession);
    expect(snapshot.questions.single.state, QuestionState.answered);
    expect(snapshot.questions.single.answers?['answer']?.text, 'Short');
    expect(snapshot.planDone, 2);
    expect(
      snapshot.queue,
      isEmpty,
    ); // notifications omit queue IDs: reload required
    expect(snapshot.stale, isTrue);
    final completed = events.whereType<AssistantMessageCompleted>().single;
    final finished = events.whereType<RunFinished>().single;
    expect(finished.seq, greaterThan(completed.seq));
    expect(identical(reduceAll(snapshot, events), snapshot), isTrue);
    expect(fixture('events').expand(projection.event), isEmpty);
  });

  test('delta batches and paragraphs overlap without duplicated text', () {
    final projection = BubblePawProjection();
    var snapshot = projection.snapshot(state(), workspaceDirectory: '/example');
    final records = fixture('transient');
    final emitted = <MessageDelta>[];
    for (final record in records) {
      final events = projection.event(record);
      emitted.addAll(events.whereType<MessageDelta>());
      snapshot = reduceAll(snapshot, events);
    }
    expect(
      snapshot.items.whereType<AssistantMessage>().single.markdown,
      'First 🐾\n\nSecond\n\nThird',
    );
    expect(emitted.map((e) => e.offset), [
      0,
      'First 🐾'.length,
      'First 🐾\n\nSecond'.length,
    ]);
    expect(projection.event(records[1]), isEmpty);
    expect(identical(reduceAll(snapshot, emitted), snapshot), isTrue);
  });

  test('retry and mismatching paragraph request refresh instead of appending corrupt text', () {
    final projection = BubblePawProjection();
    projection.snapshot(state(), workspaceDirectory: '/example');
    final records = fixture('retry');
    projection.event(records[0]);
    expect(projection.event(records[1]).single, isA<MessageDelta>());
    expect(projection.event(records[2]).single, isA<GapEvent>());
    expect(projection.event(records[3]), isEmpty);
    projection.reset();
    projection.event(records[0]);
    projection.event(records[1]);
    expect(
      projection
          .event(
            wire(
              'paragraph',
              1,
              durable: false,
              fields: {'text': 'Different reply'},
            ),
          )
          .single,
      isA<GapEvent>(),
    );
  });

  test('resnapshot drops provisional IDs and blocks ambiguous same-cursor live fragments', () {
    final projection = BubblePawProjection();
    var snapshot = projection.snapshot(
      state(seq: 1, streaming: 'Already visible'),
      workspaceDirectory: '/example',
    );
    expect(
      snapshot.items.whereType<AssistantMessage>().single.streaming,
      isTrue,
    );
    expect(
      projection.event(
        wire(
          'paragraph',
          1,
          durable: false,
          fields: {'text': 'Already visible'},
        ),
      ),
      isEmpty,
    );
    final canonical = fixture('snapshot').single;
    snapshot = projection.snapshot(canonical, workspaceDirectory: '/example');
    expect(snapshot.stale, isFalse);
    expect(
      snapshot.items.any((item) => item.id.startsWith('bubblepaw:reply:')),
      isFalse,
    );
    expect(
      projection.event(
        wire(
          'run_finished',
          14,
          fields: {'status': 'completed', 'text': 'Late duplicate'},
        ),
      ),
      isEmpty,
    );
  });

  test('pending root question supports text and suggestions; child questions stay outside user answers', () {
    final projection = BubblePawProjection();
    final root = state();
    root['question'] = {
      'id': 'question-a',
      'status': 'pending',
      'text': 'Choose?',
      'options': ['One', 'Two'],
      'parent_session_id': null,
    };
    var snapshot = projection.snapshot(root, workspaceDirectory: '/example');
    expect(snapshot.status, ChatStatus.needsYou);
    expect(snapshot.questions.single.items.single.allowOther, isTrue);
    expect(snapshot.questions.single.items.single.options.map((o) => o.label), [
      'One',
      'Two',
    ]);
    expect(snapshot.questions.single.items.single.id, 'answer');
    root['session'] = {'id': 'session-a', 'parent_session_id': 'parent-a'};
    snapshot = projection.snapshot(root, workspaceDirectory: '/example');
    expect(snapshot.questions, isEmpty);
    final text = projection.question({
      'id': 'text-question',
      'text': 'Explain',
      'status': 'pending',
    });
    expect(text.items.single.kind, QuestionKind.text);
  });

  test(
    'transport gap reaches all known chats and nested tools request refresh',
    () {
      final projection = BubblePawProjection();
      projection.snapshot(state(), workspaceDirectory: '/example');
      projection.snapshot({
        ...state(),
        'session': {'id': 'session-b'},
      }, workspaceDirectory: '/example');
      final gaps = projection.event({
        'jsonrpc': '2.0',
        'method': 'events.gap',
        'params': {'after': 0, 'skipped': 3},
      });
      expect(gaps.map((e) => e.chat), ['session-a', 'session-b']);
      expect(gaps.whereType<GapEvent>().every((e) => e.skipped == 3), isTrue);
      expect(
        projection
            .event(
              wire(
                'tool_started',
                1,
                durable: false,
                fields: {
                  'call': {
                    'id': 'nested',
                    'name': 'read',
                    'arguments': <String, Object?>{},
                  },
                },
              ),
            )
            .single,
        isA<GapEvent>(),
      );
    },
  );

  test('terminal failures, interruptions, pending tool results and unknown events remain honest', () {
    for (final status in ['failed', 'cancelled', 'interrupted']) {
      final projection = BubblePawProjection();
      var snapshot = projection.snapshot(
        state(),
        workspaceDirectory: '/example',
      );
      snapshot = reduceAll(
        snapshot,
        projection.event(
          wire(
            'run_finished',
            1,
            fields: {'status': status, 'error': 'Example error'},
          ),
        ),
      );
      expect(snapshot.run?.outcome?.name, status);
      expect(snapshot.run?.error, 'The BubblePaw run ended before completing.');
    }
    final projection = BubblePawProjection();
    var snapshot = projection.snapshot(state(), workspaceDirectory: '/example');
    snapshot = reduceAll(
      snapshot,
      projection.event(
        wire(
          'tool_started',
          1,
          fields: {
            'call': {
              'id': 'call-a',
              'name': 'js',
              'arguments': <String, Object?>{},
            },
          },
        ),
      ),
    );
    snapshot = reduceAll(
      snapshot,
      projection.event(
        wire(
          'tool_finished',
          2,
          fields: {
            'call_id': 'call-a',
            'result': {'content': 'Still owned by host', 'pending': true},
          },
        ),
      ),
    );
    expect(
      snapshot.items
          .whereType<ActivityGroup>()
          .single
          .rows
          .whereType<ToolRow>()
          .single
          .state,
      WorkState.running,
    );
    expect(projection.event(wire('future_event', 3)), isEmpty);
  });

  test(
    'explicit text outputs survive events, replay and canonical reload once',
    () {
      final projection = BubblePawProjection();
      var snapshot = projection.snapshot(
        state(),
        workspaceDirectory: '/example',
      );
      final records = fixture('outputs');
      final projected = records.expand(projection.event).toList();
      expect(projected.single, isA<SystemLineAdded>());
      snapshot = reduceAll(snapshot, projected);
      expect(snapshot.items.whereType<SystemLine>().single.id, 'output-text');
      expect(
        snapshot.items.whereType<SystemLine>().single.text,
        'Published **result**',
      );
      expect(identical(reduceAll(snapshot, projected), snapshot), isTrue);
      expect(records.expand(projection.event), isEmpty);

      final input = fixture('snapshot').single;
      final output = records.first['record'] as Map<String, Object?>;
      input['outputs'] = [output, output, records.last['record']];
      snapshot = projection.snapshot(input, workspaceDirectory: '/example');
      expect(snapshot.items.whereType<SystemLine>().single.id, 'output-text');
      expect(
        snapshot.items.map((item) => item.id).toList().indexOf('output-text'),
        1,
      );
      expect(
        snapshot.items.any((item) => item.id == 'output-execution'),
        isFalse,
      );
    },
  );

  test('snapshot errors never expose the host provider cause chain', () {
    final input = fixture('snapshot').single;
    final run = (input['runs'] as List<Object?>).single as Map<String, Object?>;
    run['status'] = 'failed';
    run['error'] = 'Example provider response body';
    final snapshot = BubblePawProjection().snapshot(
      input,
      workspaceDirectory: '/example',
    );
    expect(snapshot.run?.error, 'The BubblePaw run ended before completing.');
    expect(
      jsonEncode(snapshot.toJson()),
      isNot(contains('Example provider response body')),
    );
  });

  test(
    'native cursor mapping accepts host recovery epochs without precision loss',
    () {
      final projection = BubblePawProjection();
      const epoch = 1840000000000000;
      final snapshot = projection.snapshot(
        state(seq: epoch),
        workspaceDirectory: '/example',
      );
      expect(BubblePawProjection.hostSequence(snapshot.seq), epoch);
      final events = projection.event(
        wire(
          'run_finished',
          epoch + 1,
          fields: {'status': 'completed', 'text': 'Done'},
        ),
      );
      expect(events[1].seq, greaterThan(events[0].seq));
      expect(BubblePawProjection.hostSequence(events[1].seq), epoch + 1);
      expect(
        () =>
            projection.snapshot(state(seq: -1), workspaceDirectory: '/example'),
        throwsFormatException,
      );
    },
  );
}
