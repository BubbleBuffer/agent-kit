import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:test/test.dart';

void main() {
  group('write capabilities', () {
    test('round-trip by name and none includes no write authority', () {
      final writes = KitCapabilities(const [
        KitCapability.send,
        KitCapability.cancel,
        KitCapability.approve,
        KitCapability.createChat,
      ]);
      expect(KitCapabilities.fromJson(writes.toJson()), writes);
      for (final capability in writes.values) {
        expect(KitCapabilities.none().has(capability), isFalse);
        expect(KitCapabilities.all().has(capability), isTrue);
      }
    });

    test('missing command capabilities fail before changing state', () async {
      final backend = ScriptedBackend(
        scripts: [ChatScript(chatId: 'c', title: 'Observed chat')],
        capabilities: KitCapabilities.none(),
      );
      final before = backend.stateOf('c');
      final commands = <(KitCapability, Future<void> Function())>[
        (
          KitCapability.createChat,
          () async {
            await backend.createChat();
          },
        ),
        (
          KitCapability.send,
          () async {
            await backend.send('c', 'hello');
          },
        ),
        (
          KitCapability.send,
          () async {
            await backend.followup('c', 'hello');
          },
        ),
        (KitCapability.cancel, () => backend.cancel('c')),
        (
          KitCapability.approve,
          () => backend.decideApproval('c', 'a', ApprovalDecision.approve),
        ),
        (
          KitCapability.steer,
          () async {
            await backend.steer('c', 'hello');
          },
        ),
        (
          KitCapability.sendQueuedNow,
          () => backend.sendQueuedNow('c', 'input'),
        ),
        (
          KitCapability.queueEdit,
          () => backend.editQueued('c', 'input', 'edited'),
        ),
        (KitCapability.queueEdit, () => backend.removeQueued('c', 'input')),
        (KitCapability.resume, () => backend.resume('c')),
        (
          KitCapability.questions,
          () => backend.answerQuestion('c', 'question', {}),
        ),
        (
          KitCapability.answerChildQuestion,
          () => backend.answerChildQuestion('c', 'child', 'question', 'answer'),
        ),
        (KitCapability.rename, () => backend.rename('c', 'Renamed')),
        (KitCapability.archive, () => backend.archive('c')),
        (
          KitCapability.fork,
          () async {
            await backend.fork('c');
          },
        ),
        (KitCapability.rewind, () => backend.rewind('c', 'item')),
        (KitCapability.children, () => backend.cancelChild('c', 'child')),
        (KitCapability.jobs, () => backend.cancelJob('c', 'job')),
        (KitCapability.editUndo, () => backend.undoEdit('c', 'edit')),
        (
          KitCapability.models,
          () async {
            await backend.listModels();
          },
        ),
        (KitCapability.models, () => backend.setModel('c', 'model')),
        (
          KitCapability.providers,
          () async {
            await backend.listProviders();
          },
        ),
        (
          KitCapability.defaultModel,
          () async {
            await backend.setDefaultModel('p/m');
          },
        ),
        (
          KitCapability.profiles,
          () async {
            await backend.listProfiles();
          },
        ),
        (KitCapability.profiles, () => backend.setProfile('c', 'profile')),
        (
          KitCapability.context,
          () async {
            await backend.loadContext('c');
          },
        ),
        (
          KitCapability.context,
          () async {
            await backend.loadHistoryRange('c', 1, 2);
          },
        ),
        (
          KitCapability.context,
          () async {
            await backend.loadSummary('c', 'summary');
          },
        ),
      ];
      for (final (capability, command) in commands) {
        await expectLater(
          command(),
          throwsA(
            isA<KitUnsupported>().having(
              (error) => error.capability,
              'capability',
              capability,
            ),
          ),
        );
        expect(backend.stateOf('c'), before);
      }
      expect((await backend.listChats()).chats, hasLength(1));
      expect((await backend.loadChat('c')).title, 'Observed chat');
    });
  });

  group('BackendConstraints', () {
    test('defaults preserve the existing input contract', () {
      final AgentBackend legacy = _LegacyBackend();
      expect(legacy.constraints, BackendConstraints());
      expect(legacy.constraints.acceptsReferences, isTrue);
      expect(legacy.constraints.followUpWhileRunning, isTrue);
      expect(
        legacy.constraints.supportedQuestionKinds,
        QuestionKind.values.toSet(),
      );
      expect(BackendConstraints.fromJson({}), BackendConstraints.defaults);
    });

    test('custom kinds are copied, immutable and serialize by name', () {
      final kinds = {QuestionKind.text};
      final constraints = BackendConstraints(
        acceptsReferences: false,
        supportedQuestionKinds: kinds,
        followUpWhileRunning: false,
      );
      kinds.add(QuestionKind.pickAny);
      expect(constraints.supportedQuestionKinds, {QuestionKind.text});
      expect(
        () => constraints.supportedQuestionKinds.add(QuestionKind.pickOne),
        throwsUnsupportedError,
      );
      expect(BackendConstraints.fromJson(constraints.toJson()), constraints);
      expect(
        BackendConstraints.fromJson({
          'supportedQuestionKinds': ['text', 'futureKind'],
        }).supportedQuestionKinds,
        {QuestionKind.text},
      );
      final AgentBackend backend = ScriptedBackend(constraints: constraints);
      expect(backend.constraints, constraints);
    });

    test('a running turn cannot queue a disallowed follow-up', () async {
      final backend = ScriptedBackend(
        constraints: BackendConstraints(followUpWhileRunning: false),
      );
      final chat = (await backend.createChat()).id;
      await backend.send(chat, 'first');
      await expectLater(backend.send(chat, 'second'), throwsA(isA<KitBusy>()));
      await expectLater(
        backend.followup(chat, 'second'),
        throwsA(isA<KitBusy>()),
      );
      expect(backend.stateOf(chat)!.queue, isEmpty);
      expect(
        backend.stateOf(chat)!.items.whereType<UserMessage>(),
        hasLength(1),
      );
    });

    test('unsupported references do not silently disappear', () async {
      final backend = ScriptedBackend(
        constraints: BackendConstraints(acceptsReferences: false),
      );
      final chat = (await backend.createChat()).id;
      const refs = [KitRef(kind: 'file', id: 'a', label: 'a')];
      await expectLater(
        backend.send(chat, 'hello', refs: refs),
        throwsA(isA<KitInvalid>()),
      );
      await expectLater(
        backend.followup(chat, 'hello', refs: refs),
        throwsA(isA<KitInvalid>()),
      );
      await expectLater(
        backend.steer(chat, 'hello', refs: refs),
        throwsA(isA<KitInvalid>()),
      );
      expect(backend.stateOf(chat)!.items, isEmpty);
      expect(backend.stateOf(chat)!.queue, isEmpty);
    });

    test('unsupported question kinds remain pending', () async {
      final backend = ScriptedBackend(
        constraints: BackendConstraints(
          supportedQuestionKinds: {QuestionKind.text},
        ),
      );
      final chat = (await backend.createChat()).id;
      backend.emit(chat, {
        'kind': 'question.asked',
        'question': {
          'id': 'q',
          'items': [
            {
              'id': 'i',
              'header': 'Choice',
              'text': 'Choose one',
              'kind': 'pickOne',
              'options': [
                {'label': 'A'},
              ],
            },
          ],
        },
      });
      await expectLater(
        backend.answerQuestion(chat, 'q', {
          'i': QuestionAnswer(choices: ['A']),
        }),
        throwsA(isA<KitInvalid>()),
      );
      expect(backend.stateOf(chat)!.questions.single.isPending, isTrue);
    });
  });

  test(
    'ChatFeed follows a reader with no write port, including a gap',
    () async {
      final source = ScriptedBackend(
        scripts: [ChatScript(chatId: 'c', title: 'Before')],
        capabilities: KitCapabilities.none(),
      );
      final reader = _ReadOnlyReader(source);
      expect(reader, isNot(isA<AgentBackend>()));
      final feed = ChatFeed(reader, 'c');
      expect(feed.reader, same(reader));
      expect(() => feed.backend, throwsStateError);
      addTearDown(feed.close);
      await feed.start();
      source.emit('c', {'kind': 'chat.renamed', 'title': 'Live'});
      await _flush();
      expect(feed.snapshot!.title, 'Live');
      source.disconnect('c');
      source.emit('c', {'kind': 'chat.renamed', 'title': 'Replayed'});
      source.reconnect('c');
      await _flush();
      expect(feed.snapshot!.title, 'Replayed');
      expect(feed.snapshot!.stale, isFalse);
    },
  );

  test(
    'ChatFeed keeps the existing backend accessor for write ports',
    () async {
      final backend = ScriptedBackend();
      final chat = (await backend.createChat()).id;
      final feed = ChatFeed(backend, chat);
      addTearDown(feed.close);
      expect(feed.backend, same(backend));
      expect(feed.reader, same(backend));
      await feed.backend.send(chat, 'hello');
      await feed.start();
      expect(
        feed.snapshot!.items.whereType<UserMessage>().single.text,
        'hello',
      );
    },
  );
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Older implementers need not add a constraints member.
final class _LegacyBackend implements AgentBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ReadOnlyReader implements ChatReader {
  _ReadOnlyReader(this._source);

  final ScriptedBackend _source;

  @override
  KitCapabilities get capabilities => _source.capabilities;

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) =>
      _source.listChats(cursor: cursor, query: query);

  @override
  Future<ChatSnapshot> loadChat(String chatId) => _source.loadChat(chatId);

  @override
  Stream<KitEvent> events(String chatId, {required int after}) =>
      _source.events(chatId, after: after);

  @override
  Future<ContextDetails> loadContext(String chatId) =>
      _source.loadContext(chatId);

  @override
  Future<ContextSummary> loadSummary(String chatId, String summaryId) =>
      _source.loadSummary(chatId, summaryId);

  @override
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  ) => _source.loadHistoryRange(chatId, firstSeq, lastSeq);
}
