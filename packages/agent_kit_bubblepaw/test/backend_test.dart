import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_bubblepaw/src/transport.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

void main() {
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
      peer.handler = (method, params) => switch (method) {
        'initialize' => records[0]['result'],
        'session.state' => records[3]['result'],
        'events.after' =>
          params['after'] == 40 ? records[4]['result'] : records[1]['result'],
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
              if (event is RunWaiting && !recovered.isCompleted)
                recovered.complete();
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
      ]);
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
    'resync reloads state before replaying from its fresh durable cursor',
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
  Object? Function(String method, Json params)? handler;
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

  void _receive(String line) {
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
        handler?.call(method, params) ?? defaultResponse(method, params);
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
      output.add(utf8.encode('${jsonEncode(record)}\n'));

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
