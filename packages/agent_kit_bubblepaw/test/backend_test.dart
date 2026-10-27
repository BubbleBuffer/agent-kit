import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_bubblepaw/src/transport.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

import '../tool/live_check_support.dart';

void main() {
  test('attempt 5 preserves queued paragraphs across refresh replay', () async {
    final captured = File('test/fixtures/transport/attempt-5-events.jsonl')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Json)
        .toList();
    final source = [
      for (final entry in captured)
        (entry['record']! as Json)['params']! as Json,
    ];
    expect(
      source
          .where((event) => event['durable'] == true)
          .map((e) => e['sequence']),
      List.generate(15, (index) => index + 1),
    );
    expect(source, hasLength(47));
    final peer = _BackendPeer();
    var available = 0;
    var barrier = 0;
    var firstRefreshReads = 0;
    final firstRefreshRead = Completer<void>();
    final approvals = source
        .where((event) => event['type'] == 'approval_requested')
        .map((event) => event['approval']! as Json)
        .toList();
    final finalText =
        source.singleWhere((event) => event['type'] == 'run_finished')['text']!
            as String;
    peer.handler = (method, params) {
      if (method == 'events.after') {
        if (params['after'] == 1 && ++firstRefreshReads == 2) {
          firstRefreshRead.complete();
        }
        return {
          'events': [
            for (final event in source)
              if (event['durable'] == true &&
                  (event['sequence']! as int) > (params['after']! as int) &&
                  (event['sequence']! as int) <= available)
                event,
          ],
          'last_seq': available,
          'resync': false,
        };
      }
      if (method == 'session.state') {
        return {
          ...peer.state(seq: barrier),
          'session': {'id': 'id_1', 'title': 'Synthetic replay'},
          'runs': [
            if (barrier > 0)
              {
                'id': 'id_2',
                'model': 'synthetic-model',
                'status': barrier < 14 ? 'running' : 'completed',
              },
          ],
          'streaming_text': barrier >= 8
              ? 'Planning the first command.\n\nPlanning the second command.'
              : barrier >= 2
              ? 'Planning the first command.'
              : '',
          'inputs': [
            if (barrier == 6)
              {
                'id': 'id_5',
                'text': 'Keep the summary brief.',
                'kind': 'steer',
                'state': 'pending',
              },
          ],
          'usage': _sessionUsage(barrier * 10, barrier),
        };
      }
      if (method == 'approval.list') return approvals;
      if (method == 'run.steer') return {'id': 'id_5'};
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final initial = await backend.loadChat('id_1');
    final acceptance = LiveAcceptance(
      approve: (id) =>
          backend.decideApproval('id_1', id, ApprovalDecision.approve),
      steer: () => backend.steer('id_1', 'Keep the summary brief.'),
    );
    final observed = <KitEvent>[];
    final observations = StreamController<KitEvent>.broadcast();
    addTearDown(observations.close);
    final subscription = backend.events('id_1', after: initial.seq).listen((
      event,
    ) {
      observed.add(event);
      observations.add(event);
      acceptance.onEvent(event);
    }, onError: (Object _, StackTrace _) => acceptance.fail());
    addTearDown(subscription.cancel);
    Future<KitEvent> seen(bool Function(KitEvent) matches) {
      for (final event in observed) {
        if (matches(event)) return Future.value(event);
      }
      return observations.stream.firstWhere(matches);
    }

    void release(int first, int last, {required int seq, int? snapshot}) {
      available = seq;
      barrier = snapshot ?? seq;
      for (final entry in captured) {
        final order = entry['order']! as int;
        if (order >= first && order <= last) {
          peer.notify(entry['record']! as Json);
        }
      }
    }

    await peer.waitFor((call) => call.method == 'events.after');
    release(12, 18, seq: 1);
    await seen((event) => event is UsageUpdated);
    await firstRefreshRead.future;
    // Original orders 24..35: paragraph(2) is already buffered when the
    // telemetry refresh's snapshot(2) reads the retained approval(3).
    release(24, 30, seq: 3, snapshot: 2);
    await seen((event) => event is ApprovalRequested);
    await acceptance.settled;
    release(40, 43, seq: 6);
    await seen((event) => event is QueueAdded);
    await acceptance.settled;
    // Original order 62 caused the false gap: paragraph(2) had been dropped,
    // leaving the first request's visible text unconfirmed at this boundary.
    release(61, 73, seq: 7);
    await seen((event) => event is ToolFinished);
    release(74, 76, seq: 9);
    await seen(
      (event) => event is ApprovalRequested && event.approval.id == 'id_7',
    );
    await acceptance.settled;
    release(89, 114, seq: 12);
    await seen((event) => event is ToolFinished && event.callId == 'id_6');
    release(115, 118, seq: 15);
    final terminal = await acceptance.finished;
    await acceptance.settled;
    // Drain queued completion/settlement refreshes without a timer.
    final drained = seen((event) => event is RunWaiting);
    peer.notify({
      'method': 'event',
      'params': {..._waitEvent(16), 'session_id': 'id_1', 'run_id': 'id_2'},
    });
    await drained;
    expect(observed.whereType<GapEvent>(), isEmpty);
    await acceptance.verifyAfterUsage(terminal, 'id_2');
    expect(observed.whereType<ToolStarted>(), hasLength(2));
    expect(observed.whereType<ToolFinished>(), hasLength(2));
    expect(observed.whereType<ApprovalRequested>(), hasLength(2));
    expect(observed.whereType<ApprovalResolved>(), hasLength(2));
    expect(observed.whereType<RunFinished>(), hasLength(1));
    expect(
      observed.whereType<AssistantMessageCompleted>().single.markdown,
      finalText,
    );
    final deltas = observed.whereType<MessageDelta>().toList();
    expect(deltas.map((event) => event.text).join(), finalText);
    var length = 0;
    for (final delta in deltas) {
      expect(delta.offset, length);
      length += delta.text.length;
    }
  });

  test(
    'initial replay cannot drain notifications across a queued host gap',
    () async {
      final peer = _BackendPeer()..features = ['sessions', 'events'];
      final firstReplay = Completer<Object?>();
      var replayCount = 0;
      peer.handler = (method, params) {
        if (method == 'events.after') {
          if (++replayCount == 1) return firstReplay.future;
          return _page([]);
        }
        if (method == 'session.state') return peer.state(seq: 1);
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      addTearDown(() {
        if (!firstReplay.isCompleted) firstReplay.complete(_page([]));
      });
      final events = <KitEvent>[];
      final delivered = Completer<void>();
      final subscription = backend.events('s1', after: 0).listen((event) {
        events.add(event);
        if (event is MessageDelta && !delivered.isCompleted) {
          delivered.complete();
        }
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((call) => call.method == 'events.after');
      peer.notify({
        'method': 'events.gap',
        'params': {'skipped': 1},
      });
      peer.notify({
        'method': 'event',
        'params': {
          'sequence': 1,
          'durable': false,
          'session_id': 's1',
          'run_id': 'r1',
          'type': 'text_delta',
          'text': 'After the explicit gap',
        },
      });
      firstReplay.complete(
        _page([
          {
            'sequence': 1,
            'durable': true,
            'session_id': 's1',
            'run_id': 'r1',
            'type': 'run_started',
          },
        ]),
      );
      await delivered.future;
      expect(events.whereType<GapEvent>(), hasLength(1));
      expect(events.whereType<MessageDelta>(), hasLength(1));
      expect(
        events.indexWhere((event) => event is GapEvent),
        lessThan(events.indexWhere((event) => event is MessageDelta)),
      );
    },
  );

  test('attempt 3 durable replay waits for terminal session usage', () async {
    final captured = (await File(
      'test/fixtures/transport/attempt-3-trace.jsonl',
    ).readAsLines()).map((line) => jsonDecode(line) as Json).toList();
    final source = <Json>[];
    final approvals = <Json>[];
    // Replay the recorded durable notifications through real stdio framing.
    // The capture removed payloads, so only ordering/IDs/statuses are evidence.
    // Text is omitted; tool details and usage below are explicitly synthetic.
    for (final entry in captured) {
      if (entry['direction'] != 'stdout') continue;
      final record = entry['record'];
      if (record is! Json || record['method'] != 'event') continue;
      final event = Map<String, Object?>.of(record['params']! as Json);
      if (event['durable'] != true) continue;
      event.remove('text');
      event.remove('error');
      event.remove('usage');
      event.remove('model');
      if (event['type'] == 'approval_requested') {
        final approval = Map<String, Object?>.of(event['approval']! as Json)
          ..remove('arguments');
        event['approval'] = approval;
        approvals.add(approval);
      }
      if (event['type'] == 'tool_started') {
        event['call'] = {
          'id': approvals.last['call_id'],
          'name': approvals.last['tool'],
        };
      }
      if (event['type'] == 'tool_finished') {
        event['result'] = {
          'content': '{"exitCode":0}',
          'is_error': false,
          'pending': false,
        };
      }
      source.add(event);
    }
    expect(
      source.map((event) => event['sequence']),
      List.generate(15, (index) => index + 1),
    );
    final releaseUsage = Completer<void>();
    final usageRequested = Completer<void>();
    addTearDown(() {
      if (!releaseUsage.isCompleted) releaseUsage.complete();
    });
    final peer = _BackendPeer();
    peer.handler = (method, params) async {
      if (method == 'events.after') {
        return {
          'events': params['after'] == 0 ? source : <Json>[],
          'last_seq': 15,
          'resync': false,
        };
      }
      if (method == 'session.state') {
        if (!usageRequested.isCompleted) usageRequested.complete();
        await releaseUsage.future;
        return {
          ...peer.state(seq: 15),
          'session': {'id': 'id_1', 'title': 'Synthetic replay'},
          'usage': _sessionUsage(150, 30),
        };
      }
      if (method == 'approval.list') return approvals;
      if (method == 'approval.decide') return <String, Object?>{};
      if (method == 'run.steer') return {'id': 'id_5'};
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final acceptance = LiveAcceptance(
      approve: (id) =>
          backend.decideApproval('id_1', id, ApprovalDecision.approve),
      steer: () => backend.steer('id_1', 'Synthetic steering'),
    );
    final events = <KitEvent>[];
    final subscription = backend.events('id_1', after: 0).listen((event) {
      events.add(event);
      acceptance.onEvent(event);
    }, onError: (Object _, StackTrace _) => acceptance.fail());
    addTearDown(subscription.cancel);
    final terminal = await acceptance.finished;
    await acceptance.settled;
    await usageRequested.future;
    // This is the pre-fix script's exact verification point: everything except
    // usage has passed, while the terminal refresh is still in flight.
    expect(acceptance.approvals, 2);
    expect(events.whereType<ToolStarted>(), hasLength(2));
    expect(events.whereType<ToolFinished>(), hasLength(2));
    expect(acceptance.completedExecs, 2);
    expect(acceptance.gaps, 0);
    expect(acceptance.usageUpdates, 0);
    expect(terminal.outcome, RunOutcome.completed);
    expect(
      () => acceptance.verify(terminal, 'id_2'),
      throwsA(isA<LiveCheckFailure>()),
    );
    final verified = expectLater(
      acceptance.verifyAfterUsage(terminal, 'id_2'),
      completes,
    );
    releaseUsage.complete();
    await verified;
    expect(events.whereType<UsageUpdated>(), hasLength(1));
    expect(acceptance.gaps, 0);
    expect(
      acceptance
          .diagnostics(expectedRunId: 'id_2')
          .every((check) => check.passed),
      isTrue,
    );
  });

  test(
    'initializes the pinned protocol and negotiates honest capabilities',
    () async {
      final peer = _BackendPeer();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      expect(peer.calls.single.method, 'initialize');
      expect(backend.features, containsAll(['sessions', 'events', 'question']));
      expect(backend.capabilities.has(KitCapability.questions), isTrue);
      expect(backend.capabilities.has(KitCapability.steer), isTrue);
      expect(backend.capabilities.has(KitCapability.plan), isTrue);
      expect(backend.capabilities.has(KitCapability.rewind), isTrue);
      for (final capability in [
        KitCapability.children,
        KitCapability.jobs,
        KitCapability.context,
        KitCapability.worktrees,
        KitCapability.models,
        KitCapability.profiles,
        KitCapability.queueEdit,
        KitCapability.archive,
        KitCapability.fork,
      ]) {
        expect(backend.capabilities.has(capability), isFalse);
      }
    },
  );

  test(
    'version mismatch retains both versions and shuts down the owned peer',
    () async {
      final peer = _BackendPeer()..version = '9.9';
      addTearDown(() => peer.close());
      await expectLater(
        peer.connect(),
        throwsA(
          isA<BubblePawProtocolMismatch>()
              .having(
                (error) => error.expectedVersion,
                'expected version',
                '0.1',
              )
              .having((error) => error.actualVersion, 'actual version', '9.9'),
        ),
      );
      expect(peer.calls.map((call) => call.method), ['initialize', 'shutdown']);
      expect(peer.inputClosed, isTrue);
    },
  );

  test('missing required features fails handshake and shuts down', () async {
    final peer = _BackendPeer()..features = ['sessions'];
    addTearDown(() => peer.close());
    await expectLater(
      peer.connect(),
      throwsA(
        isA<BubblePawException>().having(
          (error) => error.code,
          'code',
          'missingFeatures',
        ),
      ),
    );
    expect(peer.calls.last.method, 'shutdown');
  });

  test('unsupported features reject before issuing host commands', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    await expectLater(
      backend.steer('s1', 'hello'),
      throwsA(isA<KitUnsupported>()),
    );
    await expectLater(
      backend.followup('s1', 'hello'),
      throwsA(isA<KitInvalid>()),
    );
    await expectLater(
      backend.answerQuestion('s1', 'q1', {
        'answer': QuestionAnswer(text: 'hello'),
      }),
      throwsA(isA<KitUnsupported>()),
    );
    await expectLater(
      backend.rewind('s1', 'm1'),
      throwsA(isA<KitUnsupported>()),
    );
    await expectLater(
      backend.decideApproval('s1', 'a1', ApprovalDecision.approve),
      throwsA(isA<KitInvalid>()),
    );
    await expectLater(
      backend.editQueued('s1', 'i1', 'hello'),
      throwsA(isA<KitUnsupported>()),
    );
    await expectLater(backend.listModels(), throwsA(isA<KitUnsupported>()));
    expect(peer.calls.map((call) => call.method), ['initialize']);
  });

  test('send starts a run and only a busy failure queues follow-up', () async {
    final peer = _BackendPeer();
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    peer.handler = (method, params) => switch (method) {
      'run.start' => {'id': 'r1'},
      _ => peer.defaultResponse(method, params),
    };
    final started = await backend.send('s1', 'start');
    expect(started.delivery, SendDelivery.started);
    expect(started.runId, 'r1');

    peer.handler = (method, params) => switch (method) {
      'run.start' => const _RpcFailure(
        'Session already has an active run r1; steer or follow up instead',
      ),
      'run.follow_up' => {'id': 'i1'},
      _ => peer.defaultResponse(method, params),
    };
    final queued = await backend.send('s1', 'next');
    expect(queued.delivery, SendDelivery.queued);
    expect(queued.inputId, 'i1');
    expect(peer.calls.last.method, 'run.follow_up');
    expect(peer.calls.last.params, {'session_id': 's1', 'text': 'next'});

    final before = peer.calls.length;
    peer.handler = (method, params) => const _RpcFailure('Unknown session: s1');
    await expectLater(
      backend.send('s1', 'missing'),
      throwsA(isA<KitNotFound>()),
    );
    expect(peer.calls.skip(before).map((call) => call.method), ['run.start']);
  });

  test(
    'send rejects blank text and reserved slash commands before RPC',
    () async {
      final peer = _BackendPeer();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      for (final text in ['   ', '/rename Changed', '/rewind m1', '/compact']) {
        await expectLater(backend.send('s1', text), throwsA(isA<KitInvalid>()));
      }
      expect(peer.calls.map((call) => call.method), ['initialize']);
    },
  );

  test(
    'maps one host question to one answer key and forwards label or text',
    () async {
      final peer = _BackendPeer()..question = _question();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final snapshot = await backend.loadChat('s1');
      final question = snapshot.questions.single;
      expect(question.id, 'q1');
      expect(question.items.single.id, 'answer');
      expect(question.items.single.options.map((option) => option.label), [
        'First',
        'Second',
      ]);
      expect(question.items.single.allowOther, isTrue);
      await backend.answerQuestion('s1', 'q1', {
        'answer': QuestionAnswer(choices: ['Second']),
      });
      expect(peer.calls.last.params, {
        'session_id': 's1',
        'question_id': 'q1',
        'text': 'Second',
      });
      await backend.answerQuestion('s1', 'q1', {
        'answer': QuestionAnswer(text: 'A custom answer'),
      });
      expect(peer.calls.last.params['text'], 'A custom answer');
    },
  );

  test(
    'rejects ambiguous, skipped, empty, unknown and multiple question answers',
    () async {
      final peer = _BackendPeer()..question = _question();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      for (final answers in <Map<String, QuestionAnswer>>[
        {},
        {'wrong': QuestionAnswer(text: 'answer')},
        {'answer': QuestionAnswer(text: '   ')},
        {'answer': QuestionAnswer(skipped: true)},
        {
          'answer': QuestionAnswer(choices: ['First', 'Second']),
        },
        {
          'answer': QuestionAnswer(choices: ['First'], text: 'also text'),
        },
        {
          'answer': QuestionAnswer(choices: ['Unknown']),
        },
        {
          'answer': QuestionAnswer(text: 'one'),
          'extra': QuestionAnswer(text: 'two'),
        },
      ]) {
        await expectLater(
          backend.answerQuestion('s1', 'q1', answers),
          throwsA(isA<KitInvalid>()),
        );
      }
      expect(
        peer.calls.where((call) => call.method == 'question.answer'),
        isEmpty,
      );
      await expectLater(
        backend.answerQuestion('s1', 'missing', {
          'answer': QuestionAnswer(text: 'answer'),
        }),
        throwsA(isA<KitNotFound>()),
      );
      peer.question = _question()..['status'] = 'answered';
      await expectLater(
        backend.answerQuestion('s1', 'q1', {
          'answer': QuestionAnswer(text: 'again'),
        }),
        throwsA(isA<KitConflict>()),
      );
    },
  );

  test(
    'list caps at 64, filters case-insensitively and rejects cursors',
    () async {
      final peer = _BackendPeer();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      peer.handler = (method, params) => method == 'session.list'
          ? [
              for (var index = 0; index < 80; index++)
                {
                  'id': 's$index',
                  'title': index.isEven ? 'Cat $index' : 'Dog $index',
                  'updated_at': DateTime.utc(
                    2026,
                    1,
                    1,
                  ).add(Duration(minutes: index)).toIso8601String(),
                },
            ]
          : peer.defaultResponse(method, params);
      final all = await backend.listChats();
      expect(all.chats.length, 64);
      expect(all.chats.first.id, 's79');
      expect(all.nextCursor, isNull);
      final cats = await backend.listChats(query: 'cAt');
      expect(cats.chats.length, 40);
      expect(cats.chats.every((chat) => chat.title.startsWith('Cat ')), isTrue);
      final before = peer.calls.length;
      await expectLater(
        backend.listChats(cursor: 'unsupported'),
        throwsA(isA<KitInvalid>()),
      );
      expect(peer.calls.length, before);
    },
  );

  test(
    'JSONL handshake, gap recovery and crash use production stdio framing',
    () async {
      // This checked-in exchange is synthetic, with no real host data or paths.
      final records = (await File(
        'test/fixtures/transport/backend-exchange.jsonl',
      ).readAsLines()).map((line) => jsonDecode(line) as Json).toList();
      final peer = _BackendPeer();
      var replays = 0;
      peer.handler = (method, params) => switch (method) {
        'initialize' => records[0]['result'],
        'session.state' => records[3]['result'],
        'events.after' =>
          ++replays == 1 ? records[1]['result'] : records[4]['result'],
        _ => peer.defaultResponse(method, params),
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final events = <KitEvent>[];
      final recovered = Completer<void>();
      final crash = Completer<Object>();
      final done = Completer<void>();
      backend
          .events('s1', after: 0)
          .listen(
            (event) {
              events.add(event);
              if (event is RunWaiting && !recovered.isCompleted) {
                recovered.complete();
              }
            },
            onError: (Object error) {
              if (!crash.isCompleted) crash.complete(error);
            },
            onDone: done.complete,
          );
      await peer.waitFor((call) => call.method == 'events.after');
      peer.notify(records[2]);
      await recovered.future;
      expect(events.whereType<GapEvent>(), hasLength(1));
      expect(peer.calls.map((call) => call.method), [
        'initialize',
        'events.after',
        'session.state',
        'events.after',
        'events.after',
      ]);
      // The old cursor is replayed before adopting the snapshot barrier.
      expect(peer.calls[3].params['after'], 0);
      expect(peer.calls.last.params['after'], 40);
      peer.stderr.add(utf8.encode('credential=synthetic-private-value\n'));
      await peer.exit(23);
      expect(
        await crash.future,
        isA<BubblePawHostExited>()
            .having((error) => error.exitCode, 'exit code', 23)
            .having(
              (error) => error.stderrTail,
              'safe tail',
              allOf(isNotEmpty, isNot(contains('synthetic-private-value'))),
            ),
      );
      await done.future;
    },
  );

  test(
    'retention resync retries available history before adopting a fresh cursor',
    () async {
      final peer = _BackendPeer()..features = ['sessions', 'events'];
      peer.handler = (method, params) => switch (method) {
        'events.after' =>
          params['after'] == 0
              ? {'events': <Json>[], 'last_seq': 20, 'resync': true}
              : {
                  'events': [_waitEvent(21)],
                  'last_seq': 21,
                  'resync': false,
                },
        'session.state' => peer.state(seq: 20),
        _ => peer.defaultResponse(method, params),
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final event = await backend
          .events('s1', after: 0)
          .firstWhere((event) => event is RunWaiting);
      expect(event.seq, 21 * 16);
      expect(peer.calls.map((call) => call.method), [
        'initialize',
        'events.after',
        'session.state',
        'events.after',
        'events.after',
      ]);
      expect(peer.calls.last.params['after'], 20);
    },
  );

  test('two subscribers independently project the same host event', () async {
    final peer = _BackendPeer();
    final ready = Completer<void>();
    var replayRequests = 0;
    peer.handler = (method, params) {
      if (method == 'events.after' && ++replayRequests == 2) ready.complete();
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final first = backend
        .events('s1', after: 0)
        .firstWhere((event) => event is RunWaiting);
    final second = backend
        .events('s1', after: 0)
        .firstWhere((event) => event is RunWaiting);
    await ready.future;
    peer.notify({'jsonrpc': '2.0', 'method': 'event', 'params': _waitEvent(1)});
    final results = await Future.wait([first, second]);
    expect(results.map((event) => event.seq), [16, 16]);
  });

  test('a gap replays unseen tools despite a newer snapshot and queued duplicates', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    final snapshotRequested = Completer<void>();
    final releaseSnapshot = Completer<void>();
    final tools = _recoveryTools();
    var replayCount = 0;
    var loads = 0;
    peer.handler = (method, params) async {
      if (method == 'session.state') {
        if (++loads > 1) {
          snapshotRequested.complete();
          await releaseSnapshot.future;
          return peer.state(seq: 12);
        }
        return peer.state(seq: 5);
      }
      if (method == 'events.after') {
        if (++replayCount == 1) return _page([]);
        return _page([
          for (final event in tools)
            if ((event['sequence']! as int) > (params['after']! as int)) event,
        ]);
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final initial = await backend.loadChat('s1');
    final events = <KitEvent>[];
    final done = Completer<void>();
    final subscription = backend.events('s1', after: initial.seq).listen((
      event,
    ) {
      events.add(event);
      if (event is RunWaiting && !done.isCompleted) done.complete();
    });
    addTearDown(subscription.cancel);
    await peer.waitFor((call) => call.method == 'events.after');
    peer.notify({
      'method': 'events.gap',
      'params': {'after': 5, 'skipped': 2},
    });
    await snapshotRequested.future;
    // Source notifications can arrive while session.state is in flight. Both
    // these tool events are also replayed, and must be delivered exactly once.
    for (final event in tools) {
      peer.notify({'method': 'event', 'params': event});
    }
    peer.notify({'method': 'event', 'params': _waitEvent(13)});
    releaseSnapshot.complete();
    await done.future;
    expect(events.whereType<ToolStarted>().map((event) => event.callId), [
      'call-1',
    ]);
    expect(events.whereType<ToolFinished>().map((event) => event.callId), [
      'call-1',
    ]);
    expect(events.whereType<GapEvent>(), hasLength(1));
    expect(
      peer.calls
          .where((call) => call.method == 'events.after')
          .map((call) => call.params['after']),
      [5, 5, 12],
    );
  });

  test('steer refresh preserves unseen tools and publishes queue without a gap', () async {
    final peer = _BackendPeer();
    final events = <KitEvent>[];
    final done = Completer<void>();
    final drained = Completer<void>();
    var accepted = false;
    var replayCount = 0;
    final source = [
      {
        'sequence': 6,
        'durable': true,
        'session_id': 's1',
        'run_id': 'r1',
        'type': 'steering_accepted',
        'text': 'Keep going',
      },
      _recoveryTools().first,
    ];
    peer.handler = (method, params) {
      if (method == 'run.steer') {
        accepted = true;
        // The commit precedes the RPC response, but a notification can lag it.
        return {'id': 'input-1'};
      }
      if (method == 'session.state') {
        return {
          ...peer.state(seq: accepted ? 9 : 5),
          'inputs': [
            if (accepted)
              {
                'id': 'input-1',
                'text': 'Keep going',
                'kind': 'steer',
                'state': 'pending',
              },
          ],
        };
      }
      if (method == 'events.after') {
        if (++replayCount == 1) return _page([]);
        return _page([
          for (final event in source)
            if ((event['sequence']! as int) > (params['after']! as int)) event,
        ]);
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final initial = await backend.loadChat('s1');
    final subscription = backend.events('s1', after: initial.seq).listen((
      event,
    ) {
      events.add(event);
      if (event is QueueAdded && !done.isCompleted) done.complete();
      if (event is RunWaiting && !drained.isCompleted) drained.complete();
    });
    addTearDown(subscription.cancel);
    await peer.waitFor((call) => call.method == 'events.after');
    expect(await backend.steer('s1', 'Keep going'), 'input-1');
    await done.future;
    peer.notify({'method': 'event', 'params': source.last});
    // A subsequent durable marker drains the queued duplicate deterministically.
    peer.notify({'method': 'event', 'params': _waitEvent(13)});
    await drained.future;
    expect(events.whereType<ToolStarted>(), hasLength(1));
    expect(events.whereType<QueueAdded>().single.input.id, 'input-1');
    expect(events.whereType<GapEvent>(), isEmpty);
  });

  test('completion replaces usage with session totals without fake gaps or double counting', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    final finished = Completer<void>();
    final drained = Completer<void>();
    final events = <KitEvent>[];
    var totals = 100;
    var context = 40;
    final completion = <String, Object?>{
      'sequence': 8,
      'durable': true,
      'session_id': 's1',
      'run_id': 'r1',
      'type': 'run_finished',
      'status': 'completed',
      'text': 'Finished',
      'usage': {'input_tokens': 50, 'output_tokens': 10},
    };
    peer.handler = (method, params) {
      if (method == 'session.state') {
        return {
          ...peer.state(seq: totals == 100 ? 5 : 8),
          'usage': _sessionUsage(totals, context),
        };
      }
      if (method == 'events.after' && totals == 150) {
        return _page((params['after']! as int) < 8 ? [completion] : []);
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    var snapshot = await backend.loadChat('s1');
    final subscription = backend.events('s1', after: snapshot.seq).listen((
      event,
    ) {
      events.add(event);
      snapshot = reduce(snapshot, event);
      if (event is UsageUpdated && !finished.isCompleted) finished.complete();
      if (event is RunWaiting && !drained.isCompleted) drained.complete();
    });
    addTearDown(subscription.cancel);
    await peer.waitFor((call) => call.method == 'events.after');
    totals = 150;
    context = 30;
    peer.notify({
      'method': 'event',
      'params': {
        'sequence': 7,
        'durable': true,
        'session_id': 's1',
        'run_id': 'r1',
        'type': 'host_state_changed',
        'key': 'usage.last_request',
        'value': {
          'model': 'example',
          'input_tokens': 30,
          'observed_at': '2026-01-01T00:00:00Z',
        },
      },
    });
    peer.notify({'method': 'event', 'params': completion});
    await finished.future;
    // A marker behind completion verifies that queued duplicates and refreshes
    // have drained, without timer-based test assumptions.
    peer.notify({'method': 'event', 'params': completion});
    peer.notify({'method': 'event', 'params': _waitEvent(9)});
    await drained.future;
    expect(events.whereType<RunFinished>(), hasLength(1));
    expect(events.whereType<GapEvent>(), isEmpty);
    expect(events.whereType<UsageUpdated>(), hasLength(1));
    expect(snapshot.usage?.inputTokens, 150);
    expect(snapshot.usage?.contextTokens, 30);
    expect(snapshot.usage?.outputTokens, 15);
  });

  test('gap recovery emits changed snapshot usage once after retained tools', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    var loads = 0;
    var replays = 0;
    peer.handler = (method, params) {
      if (method == 'session.state') {
        final initial = ++loads == 1;
        return {
          ...peer.state(seq: initial ? 5 : 12),
          'usage': _sessionUsage(initial ? 100 : 150, 30),
        };
      }
      if (method == 'events.after') {
        if (++replays == 1) return _page([]);
        return _page([
          for (final event in _recoveryTools())
            if ((event['sequence']! as int) > (params['after']! as int)) event,
        ]);
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final snapshot = await backend.loadChat('s1');
    final changed = Completer<void>();
    final drained = Completer<void>();
    final events = <KitEvent>[];
    final subscription = backend.events('s1', after: snapshot.seq).listen((
      event,
    ) {
      events.add(event);
      if (event is UsageUpdated && !changed.isCompleted) changed.complete();
      if (event is RunWaiting && !drained.isCompleted) drained.complete();
    });
    addTearDown(subscription.cancel);
    await peer.waitFor((call) => call.method == 'events.after');
    peer.notify({
      'method': 'events.gap',
      'params': {'after': 5, 'skipped': 2},
    });
    await changed.future;
    // Repeat the same canonical totals, then drain both recoveries through a
    // later live event. Repeated snapshots cannot add or re-emit those totals.
    peer.notify({
      'method': 'events.gap',
      'params': {'after': 12, 'skipped': 1},
    });
    peer.notify({'method': 'event', 'params': _waitEvent(13)});
    await drained.future;
    expect(events.whereType<GapEvent>(), hasLength(2));
    expect(events.whereType<UsageUpdated>(), hasLength(1));
    expect(events.whereType<UsageUpdated>().single.usage.inputTokens, 150);
    expect(
      events.where((event) => event is! GapEvent).map((event) => event.seq),
      [144, 192, 193, 208],
    );
  });

  test('retention resync delivers retained tools and arrivals during snapshot load', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    final snapshotRequested = Completer<void>();
    final releaseSnapshot = Completer<void>();
    final source = <Json>[_recoveryTools().first];
    var loads = 0;
    peer.handler = (method, params) async {
      if (method == 'session.state') {
        if (++loads == 1) return peer.state(seq: 5);
        snapshotRequested.complete();
        await releaseSnapshot.future;
        return peer.state(seq: 12);
      }
      if (method == 'events.after') {
        final after = params['after']! as int;
        return {
          ..._page(
            source
                .where((event) => (event['sequence']! as int) > after)
                .toList(),
          ),
          'resync': after < 9,
        };
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final snapshot = await backend.loadChat('s1');
    final events = <KitEvent>[];
    final done = Completer<void>();
    final subscription = backend.events('s1', after: snapshot.seq).listen((
      event,
    ) {
      events.add(event);
      if (event is RunWaiting && !done.isCompleted) done.complete();
    });
    addTearDown(subscription.cancel);
    await snapshotRequested.future;
    final result = _recoveryTools().last;
    source.addAll([result, _waitEvent(14)]);
    // Both replay and the live notification carry this post-retention result.
    peer.notify({'method': 'event', 'params': result});
    peer.notify({'method': 'event', 'params': _waitEvent(14)});
    releaseSnapshot.complete();
    await done.future;
    expect(events.whereType<ToolStarted>(), hasLength(1));
    expect(events.whereType<ToolFinished>(), hasLength(1));
    expect(events.whereType<RunWaiting>(), hasLength(1));
    expect(events.whereType<GapEvent>(), hasLength(1));
    expect(
      peer.calls
          .where((call) => call.method == 'events.after')
          .map((call) => call.params['after']),
      [5, 9, 12],
    );
  });

  test(
    'snapshot diffs precede durable replay beyond their source barrier',
    () async {
      final peer = _BackendPeer()..features = ['sessions', 'events'];
      final done = Completer<void>();
      var changed = false;
      var replayCount = 0;
      final tools = _recoveryTools();
      peer.handler = (method, params) {
        if (method == 'session.rename') {
          changed = true;
          return {};
        }
        if (method == 'session.state') {
          return {
            ...peer.state(seq: changed ? 9 : 5),
            'session': {
              'id': 's1',
              'title': changed ? 'Changed' : 'Synthetic chat',
            },
          };
        }
        if (method == 'events.after') {
          if (++replayCount == 1) return _page([]);
          return _page([
            for (final event in tools)
              if ((event['sequence']! as int) > (params['after']! as int))
                event,
          ]);
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      var snapshot = await backend.loadChat('s1');
      final events = <KitEvent>[];
      final subscription = backend.events('s1', after: snapshot.seq).listen((
        event,
      ) {
        events.add(event);
        snapshot = reduce(snapshot, event);
        if (event is ToolFinished && !done.isCompleted) done.complete();
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((call) => call.method == 'events.after');
      await backend.rename('s1', 'Changed');
      await done.future;
      expect(events.map((event) => event.runtimeType), [
        ToolStarted,
        ChatRenamed,
        ToolFinished,
      ]);
      expect(events.map((event) => event.seq), orderedEquals([144, 145, 192]));
      expect(snapshot.title, 'Changed');
    },
  );

  test('gap recovery pages through every missing durable event before adopting state', () async {
    final peer = _BackendPeer()..features = ['sessions', 'events'];
    var replayCount = 0;
    var loads = 0;
    final source = <Json>[
      for (var sequence = 6; sequence <= 1005; sequence++) _waitEvent(sequence),
      {..._recoveryTools().first, 'sequence': 1006},
    ];
    peer.handler = (method, params) {
      if (method == 'session.state') {
        return peer.state(seq: ++loads == 1 ? 5 : 1006);
      }
      if (method == 'events.after') {
        if (++replayCount == 1) return _page([]);
        return _page(
          source
              .where(
                (event) =>
                    (event['sequence']! as int) > (params['after']! as int),
              )
              .take(1000)
              .toList(),
        );
      }
      return peer.defaultResponse(method, params);
    };
    final backend = await peer.connect();
    addTearDown(() => peer.close(backend));
    final snapshot = await backend.loadChat('s1');
    final tool = Completer<void>();
    final drained = Completer<void>();
    final events = <KitEvent>[];
    final subscription = backend.events('s1', after: snapshot.seq).listen((
      event,
    ) {
      events.add(event);
      if (event is ToolStarted && !tool.isCompleted) tool.complete();
      if (event is RunWaiting &&
          event.seq == 1007 * 16 &&
          !drained.isCompleted) {
        drained.complete();
      }
    });
    addTearDown(subscription.cancel);
    await peer.waitFor((call) => call.method == 'events.after');
    peer.notify({
      'method': 'events.gap',
      'params': {'after': 5, 'skipped': 1001},
    });
    await tool.future;
    peer.notify({'method': 'event', 'params': _waitEvent(1007)});
    await drained.future;
    expect(events.whereType<ToolStarted>(), hasLength(1));
    expect(events.whereType<RunWaiting>(), hasLength(1001));
    expect(events.whereType<GapEvent>(), hasLength(1));
    expect(
      peer.calls
          .where((call) => call.method == 'events.after')
          .map((call) => call.params['after']),
      [5, 5, 1005, 1006],
    );
  });

  test(
    'a metadata mutation at a fully loaded cursor explicitly resyncs',
    () async {
      final peer = _BackendPeer()..features = ['sessions', 'events'];
      var changed = false;
      peer.handler = (method, params) {
        if (method == 'session.rename') {
          changed = true;
          return {};
        }
        if (method == 'session.state') {
          return {
            ...peer.state(seq: 5),
            'session': {
              'id': 's1',
              'title': changed ? 'Changed' : 'Synthetic chat',
            },
          };
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final snapshot = await backend.loadChat('s1');
      final gap = backend
          .events('s1', after: snapshot.seq)
          .firstWhere((event) => event is GapEvent);
      await peer.waitFor((call) => call.method == 'events.after');
      await backend.rename('s1', 'Changed');
      expect(await gap, isA<GapEvent>());
      expect((await backend.loadChat('s1')).title, 'Changed');
    },
  );

  test(
    'an unrepresentable snapshot diff resyncs only after replay delivery',
    () async {
      final peer = _BackendPeer()..features = ['sessions', 'events'];
      var accepted = false;
      var replayCount = 0;
      peer.handler = (method, params) {
        if (method == 'session.rename') {
          accepted = true;
          return {};
        }
        if (method == 'session.state') {
          return {
            ...peer.state(seq: accepted ? 9 : 5),
            'inputs': [
              if (accepted)
                for (var index = 0; index < 20; index++)
                  {
                    'id': 'i$index',
                    'text': 'Queued $index',
                    'kind': 'follow_up',
                    'state': 'pending',
                  },
            ],
          };
        }
        if (method == 'events.after') {
          if (++replayCount == 1) return _page([]);
          return _page(
            (params['after']! as int) < 9 ? [_recoveryTools().first] : [],
          );
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final snapshot = await backend.loadChat('s1');
      final events = <KitEvent>[];
      final gap = Completer<void>();
      final subscription = backend.events('s1', after: snapshot.seq).listen((
        event,
      ) {
        events.add(event);
        if (event is GapEvent && !gap.isCompleted) gap.complete();
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((call) => call.method == 'events.after');
      await backend.rename('s1', 'Changed');
      await gap.future;
      expect(events.map((event) => event.runtimeType), [ToolStarted, GapEvent]);
    },
  );

  for (final useCoreMethod in [false, true]) {
    final method = useCoreMethod ? 'rewind' : 'rewindToNewChat';
    test('$method announces the new chat and preserves the source', () async {
      final peer = _BackendPeer()..features = ['sessions', 'events', 'rewind'];
      final selectedMessage = <String, Object?>{
        'id': 'm1',
        'role': 'user',
        'content': 'Keep this canonical message',
      };
      final sourceState = <String, Object?>{
        ...peer.state(seq: 8),
        'messages': [
          selectedMessage,
          {'id': 'm2', 'role': 'assistant', 'content': 'Later source message'},
        ],
      };
      final newState = <String, Object?>{
        ...peer.state(seq: 9),
        'session': {
          'id': 's2',
          'title': 'Rewound chat',
          'parent_session_id': 's1',
        },
        'messages': [selectedMessage],
      };
      peer.handler = (method, params) => switch (method) {
        'session.rewind' => {'session_id': 's2'},
        'session.state' =>
          params['session_id'] == 's2' ? newState : sourceState,
        _ => peer.defaultResponse(method, params),
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final sourceBefore = await backend.loadChat('s1');
      final sourceEvents = <KitEvent>[];
      final listener = backend
          .events('s1', after: sourceBefore.seq)
          .listen(sourceEvents.add);
      addTearDown(listener.cancel);
      await peer.waitFor((call) => call.method == 'events.after');
      final firstAction = peer.calls.length;
      final created = backend.createdChats.first;
      if (useCoreMethod) {
        await backend.rewind('s1', 'm1');
      } else {
        final summary = await backend.rewindToNewChat('s1', 'm1');
        expect(summary.id, 's2');
        expect(summary.title, 'Rewound chat');
        expect(summary.parentId, 's1');
      }
      final emitted = await created;
      expect(emitted.id, 's2');
      expect(emitted.title, 'Rewound chat');
      expect(emitted.parentId, 's1');
      final actionCalls = peer.calls.skip(firstAction).toList();
      expect(actionCalls.map((call) => call.method), [
        'session.rewind',
        'session.state',
      ]);
      expect(actionCalls.first.params, {
        'session_id': 's1',
        'message_id': 'm1',
      });
      expect(actionCalls.last.params, {'session_id': 's2'});
      final sourceAfter = await backend.loadChat('s1');
      expect(sourceAfter.toJson(), sourceBefore.toJson());
      expect(sourceEvents, isEmpty);
    });
  }

  test(
    'a paused created-chat listener does not prevent backend disposal',
    () async {
      final peer = _BackendPeer();
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final listener = backend.createdChats.listen((_) {});
      listener.pause();
      await backend.dispose();
      await listener.cancel();
      expect(peer.calls.last.method, 'shutdown');
    },
  );

  test(
    'replays more than one thousand events without losing the second page',
    () async {
      final peer = _BackendPeer();
      peer.handler = (method, params) => method == 'events.after'
          ? {
              'events': params['after'] == 0
                  ? [
                      for (var sequence = 1; sequence <= 1000; sequence++)
                        _waitEvent(sequence),
                    ]
                  : [_waitEvent(1001)],
              'last_seq': 1001,
              'resync': false,
            }
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final events = await backend.events('s1', after: 0).take(1001).toList();
      expect(events.length, 1001);
      expect(events.last.seq, 1001 * 16);
      expect(
        peer.calls
            .where((call) => call.method == 'events.after')
            .map((call) => call.params['after']),
        [0, 1000],
      );
    },
  );
}

// Source-backed synthetic durable ordering: runtime.rs commits steering before
// subsequent tool boundaries; runner usage.rs publishes last-request telemetry
// before runtime.rs commits run_finished. Global cursors need not be contiguous.
List<Json> _recoveryTools() => (File(
  'test/fixtures/transport/durable-tools.jsonl',
).readAsLinesSync()).map((line) => jsonDecode(line) as Json).toList();

Json _page(List<Json> events) => {
  'events': events,
  'last_seq': 12,
  'resync': false,
};

Json _sessionUsage(int input, int context) => {
  'context': {'last_request_input_tokens': context, 'window_tokens': 1000},
  'own': {
    'tokens': {
      'input_tokens': input,
      'output_tokens': 15,
      'cache_read_tokens': 5,
    },
  },
  'total': {
    'tokens': {'input_tokens': input + 1000, 'output_tokens': 999},
  },
};

Json _question() => {
  'id': 'q1',
  'text': 'Which choice?',
  'options': ['First', 'Second'],
  'status': 'pending',
};

Json _waitEvent(int sequence) => {
  'sequence': sequence,
  'durable': true,
  'session_id': 's1',
  'run_id': 'r1',
  'type': 'run_waiting_for_quota',
  'wait': {'reason': 'Synthetic wait'},
};

class _Call {
  _Call(this.method, this.params);
  final String method;
  final Json params;
}

class _RpcFailure {
  const _RpcFailure(this.message);
  final String message;
}

class _BackendPeer {
  _BackendPeer() {
    _inputSubscription = input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _receive,
          onDone: () {
            inputClosed = true;
          },
        );
  }

  final input = StreamController<List<int>>();
  final output = StreamController<List<int>>();
  final stderr = StreamController<List<int>>();
  final _exitCode = Completer<int>();
  final _calls = StreamController<_Call>.broadcast();
  late final StreamSubscription<String> _inputSubscription;
  final calls = <_Call>[];
  String version = '0.1';
  List<String> features = [
    'sessions',
    'events',
    'steer',
    'follow_up',
    'approvals',
    'question',
    'todo',
    'rewind',
  ];
  Json? question;
  FutureOr<Object?> Function(String method, Json params)? handler;
  bool inputClosed = false;
  Future<void>? _exiting;

  Future<BubblePawBackend> connect() => BubblePawBackend.connect(
    StdioBubblePawTransport.forTesting(
      stdout: output.stream,
      stdin: input.sink,
      stderr: stderr.stream,
      exitCode: _exitCode.future,
      terminate: () {
        unawaited(exit(-9));
      },
      requestTimeout: const Duration(seconds: 2),
      shutdownTimeout: const Duration(milliseconds: 50),
    ),
    workspaceDirectory: '/workspace/synthetic',
  );

  Json state({int seq = 0}) => {
    'session': {'id': 's1', 'title': 'Synthetic chat'},
    'seq': seq,
    'messages': [],
    'runs': [],
    'inputs': [],
    'question': question,
    'todo': [],
  };

  Object? defaultResponse(String method, Json params) => switch (method) {
    'initialize' => {'protocol_version': version, 'features': features},
    'session.state' => state(),
    'approval.list' => <Json>[],
    'events.after' => {'events': <Json>[], 'last_seq': 0, 'resync': false},
    _ => <String, Object?>{},
  };

  Future<void> _receive(String line) async {
    final request = jsonDecode(line) as Json;
    final method = request['method']! as String;
    final params = request['params']! as Json;
    final call = _Call(method, params);
    calls.add(call);
    _calls.add(call);
    if (method == 'shutdown') {
      notify({
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': {'stopped': true},
      });
      unawaited(exit(0));
      return;
    }
    final response =
        await (handler?.call(method, params) ??
            defaultResponse(method, params));
    notify({
      'jsonrpc': '2.0',
      'id': request['id'],
      if (response is _RpcFailure)
        'error': {'code': -32000, 'message': response.message}
      else
        'result': response,
    });
  }

  void notify(Json record) =>
      output.add(utf8.encode('${jsonEncode({'jsonrpc': '2.0', ...record})}\n'));

  Future<_Call> waitFor(bool Function(_Call call) predicate) {
    for (final call in calls) {
      if (predicate(call)) return Future<_Call>.value(call);
    }
    return _calls.stream.firstWhere(predicate);
  }

  Future<void> exit(int code) => _exiting ??= _finishExit(code);

  Future<void> _finishExit(int code) async {
    _exitCode.complete(code);
    await Future.wait([output.close(), stderr.close()]);
  }

  Future<void> close([BubblePawBackend? backend]) async {
    await backend?.dispose();
    await exit(0);
    await input.close();
    await _inputSubscription.cancel();
    await _calls.close();
  }
}
