// BubblePaw-Core v0.3.0: context reads, history.range, child questions.
// A part of backend_test.dart so that it shares its fake stdio peer.
part of 'backend_test.dart';

const _v030 = [
  'sessions',
  'events',
  'question',
  'question.answer_child',
  'child_events',
  'context',
];

Json _ctxStructure() => {
  'episodes': [
    {
      'id': 'ep1',
      'ordinal': 1,
      'chapter_id': 'ch1',
      'first_message_id': 'm1',
      'last_message_id': 'm3',
      'title': 'Set up',
      'status': 'written',
      'source_tokens': 1200,
      'summary_tokens': 150,
    },
    {
      'id': 'ep2',
      'ordinal': 2,
      'chapter_id': 'ch2',
      'first_message_id': 'm4',
      'last_message_id': 'm6',
      'title': 'Build',
      'status': 'written',
      'source_tokens': 900,
      'summary_tokens': 100,
    },
  ],
  'chapters': [
    {
      'id': 'ch1',
      'ordinal': 1,
      'first_episode_ordinal': 1,
      'last_episode_ordinal': 1,
      'first_message_id': 'm1',
      'last_message_id': 'm3',
      'title': null,
      'status': 'closed',
      'source_tokens': 1200,
      'summary_tokens': 80,
    },
    {
      'id': 'ch2',
      'ordinal': 2,
      'first_episode_ordinal': 2,
      'last_episode_ordinal': 2,
      'first_message_id': 'm4',
      'last_message_id': 'm6',
      'title': 'Open work',
      'status': 'open',
      'source_tokens': 900,
      'summary_tokens': 0,
    },
  ],
  'legacy_chapters': <Json>[],
  'summary_tokens_estimated': true,
};

List<Json> _ctxEvents({int applied = 1}) => [
  {
    'id': 'f1',
    'kind': 'episode_written',
    'created_at': '2026-10-27T10:00:00Z',
    'trigger': 'source_size',
    'trigger_text': 'episode reached the source size',
    'first_message_id': 'm1',
    'last_message_id': 'm3',
    'episode_ids': ['ep1'],
    'summary_id': 'ep1',
    'tokens_before': 1200,
    'tokens_after': 150,
    'input_before': null,
    'input_after': null,
  },
  for (var i = 0; i < applied; i++)
    {
      'id': 'f${i + 2}',
      'kind': 'applied',
      'created_at': '2026-10-27T11:0$i:00Z',
      'trigger': 'pressure',
      'trigger_text': 'input reached 80k',
      'first_message_id': 'm1',
      'last_message_id': 'm3',
      'episode_ids': ['ep1'],
      'summary_id': 'ep1',
      'tokens_before': null,
      'tokens_after': 150,
      'input_before': 80000,
      'input_after': 30000,
    },
];

Json _ctxView({int threshold = 84000}) => {
  'session_id': 's1',
  'frontier': 30,
  'prefix': <Json>[],
  'threshold': threshold,
  'budget': 70000,
  'tokens': 30000,
  'blocks': [
    {'kind': 'opening', 'tokens': 5000},
    {'kind': 'memory_index', 'tokens': 300},
    {'kind': 'anchors', 'tokens': 200},
    {
      'kind': 'episode_summary',
      'tokens': 150,
      'id': 'ep1',
      'first_message_id': 'm1',
      'last_message_id': 'm3',
    },
    {
      'kind': 'raw_suffix',
      'tokens': 4000,
      'first_message_id': 'm4',
      'last_message_id': 'm6',
    },
  ],
};

const _ctxSeqs = {'m1': 10, 'm2': 12, 'm3': 15, 'm4': 20, 'm5': 24, 'm6': 30};

Json _historyRow(String id, String role, String content, {int? tokens}) => {
  'seq': _ctxSeqs[id],
  'message': {'id': id, 'role': role, 'content': content},
  'tokens': tokens ?? 10,
  'source': 'reported',
};

Object? _contextHost(_BackendPeer peer, String method, Json params) {
  switch (method) {
    case 'context.structure':
      return _ctxStructure();
    case 'context.events':
      return {'events': _ctxEvents()};
    case 'context.view':
      return {'view': _ctxView()};
    case 'history.range':
      final id = params['first_message_id'];
      if (id is String) {
        return {
          'messages': [_historyRow(id, 'user', 'x')],
          'next_seq': null,
        };
      }
      return peer.defaultResponse(method, params);
    case 'context.summary':
      return {
        'kind': params['kind'],
        'id': params['id'],
        'summary': 'The summary of ${params['id']}.',
      };
    case 'session.state':
      return {...peer.state(seq: 3), 'usage': _sessionUsage(100, 50)};
  }
  return peer.defaultResponse(method, params);
}

Json _childState(
  String id, {
  String run = 'completed',
  Json? question,
  String task = 'Check the logs',
}) => {
  'session': {'id': id, 'title': 'Child', 'parent_session_id': 's1'},
  'seq': 4,
  'messages': [
    {'id': 'c-u', 'role': 'user', 'content': task},
    {
      'id': 'c-a',
      'role': 'assistant',
      'content': 'Found two errors.',
      'tool_calls': [
        {'id': 't1', 'name': 'exec', 'arguments': <String, Object?>{}},
      ],
    },
  ],
  'runs': [
    {
      'id': 'cr1',
      'status': run,
      'started_at': '2026-10-27T12:00:00Z',
      'ended_at': run == 'running' ? null : '2026-10-27T12:05:00Z',
    },
  ],
  'inputs': <Json>[],
  'question': question,
  'todo': <Json>[],
};

Json _childQuestion({String status = 'pending', String? answer, String? by}) =>
    {
      'id': 'cq1',
      'text': 'Which colour?',
      'options': ['Blue', 'Green'],
      'status': status,
      'asked_at': '2026-10-27T12:01:00Z',
      'answer': ?answer,
      'answered_by': ?by,
    };

Json _parentEvent(int sequence, Json body) => {
  'sequence': sequence,
  'durable': true,
  'session_id': 's1',
  'run_id': 'cr1',
  'created_at': '2026-10-27T12:00:00Z',
  ...body,
};

void _contextAndChildTests() {
  group('BubblePaw-Core v0.3.0 features', () {
    test(
      'every capability stays off unless its feature is advertised',
      () async {
        final peer = _BackendPeer()..features = ['sessions', 'events'];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        expect(backend.capabilities.has(KitCapability.context), isFalse);
        expect(
          backend.capabilities.has(KitCapability.answerChildQuestion),
          isFalse,
        );
        await expectLater(
          backend.loadContext('s1'),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.loadHistoryRange('s1', 1, 5),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.loadSummary('s1', 'episode:ep1'),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.answerChildQuestion('s1', 'c1', 'q1', 'Green'),
          throwsA(isA<KitUnsupported>()),
        );
        expect(peer.calls.map((c) => c.method), ['initialize']);
      },
    );

    test(
      'a loaded chat has no context or children without the features',
      () async {
        final peer = _BackendPeer()..features = ['sessions', 'events'];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final snapshot = await backend.loadChat('s1');
        expect(snapshot.context, isNull);
        expect(snapshot.children, isEmpty);
        expect(peer.calls.map((c) => c.method), [
          'initialize',
          'session.state',
        ]);
      },
    );

    test(
      'child_events alone enables neither context nor child answers',
      () async {
        final peer = _BackendPeer()
          ..features = ['sessions', 'events', 'child_events'];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        expect(backend.capabilities.has(KitCapability.context), isFalse);
        expect(
          backend.capabilities.has(KitCapability.answerChildQuestion),
          isFalse,
        );
      },
    );

    test(
      'context and question.answer_child each enable their own capability',
      () async {
        final peer = _BackendPeer()
          ..features = ['sessions', 'events', 'context'];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        expect(backend.capabilities.has(KitCapability.context), isTrue);
        expect(
          backend.capabilities.has(KitCapability.answerChildQuestion),
          isFalse,
        );
        final other = _BackendPeer()
          ..features = ['sessions', 'events', 'question.answer_child'];
        final second = await other.connect();
        addTearDown(() => other.close(second));
        expect(second.capabilities.has(KitCapability.context), isFalse);
        expect(
          second.capabilities.has(KitCapability.answerChildQuestion),
          isTrue,
        );
        await expectLater(
          second.loadContext('s1'),
          throwsA(isA<KitUnsupported>()),
        );
      },
    );

    test(
      'loadContext maps structure, facts and the view, resolving IDs once',
      () async {
        final peer = _BackendPeer()..features = _v030;
        peer.handler = (method, params) => _contextHost(peer, method, params);
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final details = await backend.loadContext('s1');
        expect(
          [for (final e in details.episodes) (e.id, e.firstSeq, e.lastSeq)],
          [('ep1', 10, 15), ('ep2', 20, 30)],
        );
        expect(details.episodes.first.summaryId, 'episode:ep1');
        expect(details.episodes.first.sourceTokens, 1200);
        expect(details.episodes.first.chapterId, 'ch1');
        expect(details.chapters.map((c) => c.id), ['ch1', 'ch2']);
        final closed = details.chapter('ch1')!;
        expect(closed.title, 'Chapter 1');
        expect(closed.status, ContextStatus.closed);
        expect(closed.lastSeq, 15);
        expect(closed.summaryId, 'chapter:ch1');
        final open = details.chapter('ch2')!;
        expect(open.status, ContextStatus.open);
        expect(open.lastSeq, isNull);
        expect(open.sourceTokens, isNull);
        expect(open.summaryId, isNull);
        expect(details.summaries.map((s) => s.id), [
          'episode:ep1',
          'episode:ep2',
          'chapter:ch1',
        ]);
        final summary = details.summary('episode:ep1')!;
        expect(summary.text, isEmpty);
        expect(summary.summaryTokens, 150);
        expect(summary.sourceTokens, 1200);
        expect(summary.applied, isTrue);
        expect(summary.createdAt, DateTime.utc(2026, 10, 27, 10));
        expect(details.summary('episode:ep2')!.applied, isFalse);
        expect(details.summary('chapter:ch1')!.closed, isTrue);
        expect(details.events.map((e) => e.id), ['f1', 'f2']);
        final applied = details.events.last;
        expect(applied.kind, ContextEventKind.applied);
        expect(applied.trigger, ContextTrigger.pressure);
        expect(applied.triggerText, 'input reached 80k');
        // The host did not record the size: the value stays absent.
        expect(applied.tokensBefore, isNull);
        expect(applied.tokensAfter, 150);
        expect(applied.inputBefore, 80000);
        expect(applied.summaryId, 'episode:ep1');
        expect(details.events.first.trigger, ContextTrigger.sourceSize);
        final resolved = peer.calls
            .where((c) => c.method == 'history.range')
            .map((c) => c.params['first_message_id'])
            .toList();
        expect(resolved.toSet(), hasLength(resolved.length));
        expect(resolved.toSet(), {'m1', 'm3', 'm4', 'm6'});
        await backend.loadContext('s1');
        expect(
          peer.calls.where((c) => c.method == 'history.range'),
          hasLength(4),
          reason: 'a message keeps its sequence',
        );
      },
    );

    test('loadHistoryRange pages by host sequence and maps rows', () async {
      final peer = _BackendPeer()..features = _v030;
      peer.handler = (method, params) {
        if (method != 'history.range') {
          return peer.defaultResponse(method, params);
        }
        if (params['first_seq'] == 10) {
          return {
            'messages': [
              _historyRow('m1', 'user', 'Please   build\nthe app', tokens: 7),
              {
                'seq': 12,
                'message': {
                  'id': 'm2',
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {'id': 't', 'name': 'exec'},
                  ],
                },
                'tokens': 3,
                'source': 'estimated',
              },
            ],
            'next_seq': 15,
          };
        }
        return {
          'messages': [
            _historyRow('m3', 'tool', 'ok'),
            {
              'seq': 16,
              'message': {'id': 'm9', 'role': 'system', 'content': 'x' * 400},
              'tokens': 99,
              'source': 'reported',
            },
          ],
          'next_seq': null,
        };
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final page = await backend.loadHistoryRange('s1', 10, 20);
      expect((page.firstSeq, page.lastSeq), (10, 20));
      expect(page.messages.map((m) => m.seq), [10, 12, 15, 16]);
      expect(page.messages.map((m) => m.role), [
        HistoryRole.user,
        HistoryRole.agent,
        HistoryRole.tool,
        HistoryRole.agent,
      ]);
      expect(page.messages[0].preview, 'Please build the app');
      expect(page.messages[0].tokens, 7);
      expect(page.messages[1].preview, 'Tool call: exec');
      expect(page.messages[3].preview.length, 160);
      final calls = peer.calls.where((c) => c.method == 'history.range');
      expect(calls.map((c) => (c.params['first_seq'], c.params['last_seq'])), [
        (10, 20),
        (15, 20),
      ]);
      await expectLater(
        backend.loadHistoryRange('s1', 5, 2),
        throwsA(isA<KitInvalid>()),
      );
    });

    test('loadSummary returns the whole text and maps unknown ids', () async {
      final peer = _BackendPeer()..features = _v030;
      peer.handler = (method, params) => _contextHost(peer, method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final summary = await backend.loadSummary('s1', 'chapter:ch1');
      expect(summary.text, 'The summary of ch1.');
      expect(summary.kind, ContextSummaryKind.chapter);
      expect(summary.closed, isTrue);
      final read = peer.calls.singleWhere((c) => c.method == 'context.summary');
      expect(read.params, {'session_id': 's1', 'kind': 'chapter', 'id': 'ch1'});
      await expectLater(
        backend.loadSummary('s1', 'episode:nope'),
        throwsA(isA<KitNotFound>()),
      );
      await expectLater(
        backend.loadSummary('s1', 'bare'),
        throwsA(isA<KitNotFound>()),
      );
    });

    test(
      'loadChat carries the serving view, window and compaction markers',
      () async {
        final peer = _BackendPeer()..features = _v030;
        peer.handler = (method, params) => _contextHost(peer, method, params);
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final snapshot = await backend.loadChat('s1');
        final context = snapshot.context!;
        // The usage window (1000) is below the cap: no window is reported.
        expect(
          (context.window, context.applyCap, context.responseReserve),
          (null, 84000, null),
        );
        expect(context.appliedAt, DateTime.utc(2026, 10, 27, 11));
        expect(context.blocks.map((b) => b.kind), [
          ContextBlockKind.opening,
          ContextBlockKind.memoryIndex,
          ContextBlockKind.anchors,
          ContextBlockKind.episodeSummary,
          ContextBlockKind.rawSuffix,
        ]);
        expect(context.blocks[3].summaryId, 'episode:ep1');
        expect(
          (context.blocks[3].firstSeq, context.blocks[3].lastSeq),
          (10, 15),
        );
        expect(context.totalTokens, 9650);
        final marker = snapshot.items.whereType<CompactionItem>().single;
        expect(marker.eventId, 'f2');
        expect(marker.episodesSummarized, 1);
        expect(marker.tokensAfter, 150);
        expect(marker.state, CompactionState.done);
      },
    );

    test('a window above the cap yields the response reserve', () async {
      final peer = _BackendPeer()..features = _v030;
      peer.handler = (method, params) {
        if (method == 'session.state') {
          return {
            ...peer.state(seq: 3),
            'usage': {
              'context': {
                'last_request_input_tokens': 5,
                'window_tokens': 100000,
              },
            },
          };
        }
        return _contextHost(peer, method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final context = (await backend.loadChat('s1')).context!;
      expect(
        (context.window, context.applyCap, context.responseReserve),
        (100000, 84000, 16000),
      );
    });

    test('a null view leaves the snapshot context empty', () async {
      final peer = _BackendPeer()..features = _v030;
      peer.handler = (method, params) => method == 'context.view'
          ? {'view': null}
          : _contextHost(peer, method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      expect((await backend.loadChat('s1')).context, isNull);
    });

    test('context_compaction publishes the marker and the new view', () async {
      final peer = _BackendPeer()..features = _v030;
      var applied = 1;
      var seq = 5;
      peer.handler = (method, params) {
        if (method == 'context.events') {
          return {'events': _ctxEvents(applied: applied)};
        }
        if (method == 'context.view') {
          return {'view': _ctxView(threshold: applied > 1 ? 60000 : 84000)};
        }
        if (method == 'session.state') return peer.state(seq: seq);
        if (method == 'events.after') return _page([]);
        return _contextHost(peer, method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final initial = await backend.loadChat('s1');
      expect(initial.items.whereType<CompactionItem>(), hasLength(1));
      final events = <KitEvent>[];
      final done = Completer<void>();
      final subscription = backend.events('s1', after: initial.seq).listen((e) {
        events.add(e);
        if (e is ContextChanged && !done.isCompleted) done.complete();
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((c) => c.method == 'events.after');
      applied = 2;
      seq = 6;
      peer.notify({
        'method': 'event',
        'params': {
          'sequence': 6,
          'durable': true,
          'session_id': 's1',
          'run_id': '',
          'created_at': '2026-10-27T11:01:00Z',
          'type': 'context_compaction',
          'event_id': 'f3',
          'kind': 'applied',
          'trigger': 'pressure',
        },
      });
      await done.future;
      final marker = events.whereType<CompactionUpdated>().single;
      expect(marker.eventId, 'f3');
      expect(marker.itemId, 'bubblepaw:compaction:f3');
      expect(marker.tokensAfter, 150);
      expect(marker.detail, 'input reached 80k');
      expect(events.whereType<ContextChanged>().single.context.applyCap, 60000);
      expect(events.whereType<GapEvent>(), isEmpty);
    });

    test('answerChildQuestion sends the parent, child and question', () async {
      final peer = _BackendPeer()..features = _v030;
      peer.handler = (method, params) => method == 'question.answer_child'
          ? {'answered': true}
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      await backend.answerChildQuestion(
        's1',
        'c1',
        'cq1',
        'Green with stripes',
      );
      final call = peer.calls.singleWhere(
        (c) => c.method == 'question.answer_child',
      );
      expect(call.params, {
        'parent': 's1',
        'child': 'c1',
        'question_id': 'cq1',
        'text': 'Green with stripes',
      });
      await expectLater(
        backend.answerChildQuestion('s1', 'c1', 'cq1', '  '),
        throwsA(isA<KitInvalid>()),
      );
      expect(
        peer.calls.where((c) => c.method == 'question.answer_child'),
        hasLength(1),
      );
    });

    test('child answer failures map to kit errors', () async {
      final peer = _BackendPeer()..features = _v030;
      var message = 'pending child question not found';
      peer.handler = (method, params) => method == 'question.answer_child'
          ? _RpcFailure(message)
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      await expectLater(
        backend.answerChildQuestion('s1', 'c1', 'q', 'x'),
        throwsA(isA<KitNotFound>()),
      );
      message = 'question was already answered or cancelled';
      await expectLater(
        backend.answerChildQuestion('s1', 'c1', 'q', 'x'),
        throwsA(isA<KitConflict>()),
      );
      message = 'answer must be nonempty and at most 16 KiB';
      await expectLater(
        backend.answerChildQuestion('s1', 'c1', 'q', 'x'),
        throwsA(isA<KitInvalid>()),
      );
    });

    test(
      'loadChat lists direct children from their own session state',
      () async {
        final peer = _BackendPeer()..features = _v030;
        peer.handler = (method, params) {
          if (method == 'session.list') {
            return [
              {'id': 's1', 'title': 'Parent'},
              {'id': 'c1', 'title': 'Child', 'parent_session_id': 's1'},
              {'id': 'c2', 'title': 'Other', 'parent_session_id': 'elsewhere'},
              {'id': 'c3', 'title': 'Asking', 'parent_session_id': 's1'},
            ];
          }
          if (method == 'session.state') {
            return switch (params['session_id']) {
              'c1' => _childState('c1'),
              'c3' => _childState(
                'c3',
                run: 'running',
                question: _childQuestion(),
                task: 'Pick a colour',
              ),
              _ => peer.state(seq: 3),
            };
          }
          return _contextHost(peer, method, params);
        };
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final snapshot = await backend.loadChat('s1');
        expect(snapshot.children.map((c) => c.id), ['c1', 'c3']);
        final done = snapshot.children.first;
        expect(done.state, WorkState.done);
        expect(done.task, 'Check the logs');
        expect(done.result, 'Found two errors.');
        expect(done.toolCalls, 1);
        expect(done.endedAt, DateTime.utc(2026, 10, 27, 12, 5));
        final asking = snapshot.children.last;
        expect(asking.state, WorkState.waitingForAnswer);
        final question = asking.pendingQuestion!;
        expect(question.id, 'cq1');
        expect(question.childId, 'c3');
        expect(question.options, ['Blue', 'Green']);
        expect(question.askedAt, DateTime.utc(2026, 10, 27, 12, 1));
        expect(snapshot.pendingChildQuestions.map((q) => q.id), ['cq1']);
      },
    );

    test(
      'child events publish the crew, its question and the answer',
      () async {
        final peer = _BackendPeer()..features = _v030;
        var seq = 5;
        var childState = _childState('c1', run: 'running');
        var listed = false;
        peer.handler = (method, params) {
          if (method == 'session.list') {
            return [
              {'id': 's1', 'title': 'Parent'},
              if (listed)
                {'id': 'c1', 'title': 'Child', 'parent_session_id': 's1'},
            ];
          }
          if (method == 'session.state') {
            return params['session_id'] == 'c1'
                ? childState
                : peer.state(seq: seq);
          }
          if (method == 'events.after') return _page([]);
          return _contextHost(peer, method, params);
        };
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final initial = await backend.loadChat('s1');
        expect(initial.children, isEmpty);
        final events = <KitEvent>[];
        final observed = StreamController<KitEvent>.broadcast();
        addTearDown(observed.close);
        final subscription = backend.events('s1', after: initial.seq).listen((
          e,
        ) {
          events.add(e);
          observed.add(e);
        });
        addTearDown(subscription.cancel);
        await peer.waitFor((c) => c.method == 'events.after');
        Future<void> deliver(Json event, bool Function(KitEvent) until) {
          final seen = observed.stream.firstWhere(until);
          peer.notify({'method': 'event', 'params': event});
          return seen;
        }

        listed = true;
        seq = 6;
        await deliver(
          _parentEvent(6, {
            'type': 'child_run_state_changed',
            'child_session_id': 'c1',
            'state': 'running',
          }),
          (e) => e is ChildSpawned,
        );
        final spawned = events.whereType<ChildSpawned>().single;
        expect((spawned.childId, spawned.task), ('c1', 'Check the logs'));

        childState = _childState(
          'c1',
          run: 'running',
          question: _childQuestion(),
        );
        seq = 7;
        await deliver(
          _parentEvent(7, {
            'type': 'host_state_changed',
            'key': 'child_question',
            'value': {
              'child_session_id': 'c1',
              'id': 'cq1',
              'parent_session_id': 's1',
              'status': 'pending',
              'text': 'Which colour?',
              'options': ['Blue', 'Green'],
              'asked_at': '2026-10-27T12:01:00Z',
              'run_id': 'cr1',
            },
          }),
          (e) => e is ChildQuestionAsked,
        );
        final asked = events.whereType<ChildQuestionAsked>().single.question;
        expect((asked.id, asked.childId), ('cq1', 'c1'));
        expect(asked.text, 'Which colour?');

        childState = _childState(
          'c1',
          run: 'running',
          question: _childQuestion(
            status: 'answered',
            answer: 'Green',
            by: 'user',
          ),
        );
        seq = 8;
        await deliver(
          _parentEvent(8, {
            'type': 'host_state_changed',
            'key': 'child_question_answer',
            'value': {
              'child_session_id': 'c1',
              'id': 'cq1',
              'status': 'answered',
              'answer': 'Green',
              'answered_by': 'user',
            },
          }),
          (e) => e is ChildQuestionResolved,
        );
        final resolved = events.whereType<ChildQuestionResolved>().single;
        expect(resolved.state, ChildQuestionState.answered);
        expect(
          (resolved.answer, resolved.answeredBy),
          ('Green', AnsweredBy.user),
        );

        childState = _childState('c1');
        seq = 9;
        await deliver(
          _parentEvent(9, {
            'type': 'child_run_state_changed',
            'child_session_id': 'c1',
            'state': 'completed',
          }),
          (e) => e is ChildFinished,
        );
        final finished = events.whereType<ChildFinished>().single;
        expect(finished.state, WorkState.done);
        expect(finished.result, 'Found two errors.');
        expect(events.whereType<GapEvent>(), isEmpty);
        final fresh = await backend.loadChat('s1');
        expect(fresh.children.single.state, WorkState.done);
      },
    );

    test('a cancelled question resolves as cancelled', () async {
      final peer = _BackendPeer()..features = _v030;
      var seq = 5;
      var childState = _childState(
        'c1',
        run: 'running',
        question: _childQuestion(),
      );
      peer.handler = (method, params) {
        if (method == 'session.list') {
          return [
            {'id': 'c1', 'title': 'Child', 'parent_session_id': 's1'},
          ];
        }
        if (method == 'session.state') {
          return params['session_id'] == 'c1'
              ? childState
              : peer.state(seq: seq);
        }
        if (method == 'events.after') return _page([]);
        return _contextHost(peer, method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final initial = await backend.loadChat('s1');
      expect(initial.children.single.state, WorkState.waitingForAnswer);
      final seen = Completer<ChildQuestionResolved>();
      final subscription = backend.events('s1', after: initial.seq).listen((e) {
        if (e is ChildQuestionResolved) seen.complete(e);
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((c) => c.method == 'events.after');
      childState = _childState(
        'c1',
        run: 'running',
        question: _childQuestion(status: 'cancelled'),
      );
      seq = 6;
      peer.notify({
        'method': 'event',
        'params': _parentEvent(6, {
          'type': 'host_state_changed',
          'key': 'child_question',
          'value': {
            'child_session_id': 'c1',
            'id': 'cq1',
            'status': 'cancelled',
          },
        }),
      });
      final resolved = await seen.future;
      expect(resolved.state, ChildQuestionState.cancelled);
      expect(resolved.questionId, 'cq1');
    });
  });
}
