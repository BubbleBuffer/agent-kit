import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:test/test.dart';

const _askedAt = '2026-10-26T09:01:00.000Z';

Json _question(String id, String childId, {List<String>? options}) => {
  'id': id,
  'childId': childId,
  'text': 'Which path should I read?',
  'options': ?options,
  'askedAt': _askedAt,
};

/// A chat with a finished run and two running children, `k1` and `k2`.
ChatSnapshot _crew() => reduceAll(ChatSnapshot.empty('c1'), [
  for (final (i, j) in <Json>[
    {'kind': 'run.started', 'runId': 'r1'},
    {'kind': 'child.spawned', 'childId': 'k1', 'task': 'Survey Codex'},
    {'kind': 'child.spawned', 'childId': 'k2', 'task': 'Trace reconnect'},
    {'kind': 'run.finished', 'runId': 'r1', 'outcome': 'completed'},
  ].indexed)
    KitEvent.fromJson({...j, 'seq': i + 1, 'chat': 'c1'}),
]);

ChatSnapshot _apply(ChatSnapshot s, Json event) =>
    reduce(s, KitEvent.fromJson({...event, 'seq': s.seq + 1, 'chat': 'c1'}));

void main() {
  group('ChildQuestion', () {
    test('round-trips, with options and without', () {
      final q = ChildQuestion(
        id: 'cq1',
        childId: 'k1',
        text: 'Which?',
        options: const ['a', 'b'],
        askedAt: DateTime.utc(2026),
      );
      expect(ChildQuestion.fromJson(q.toJson()), q);
      final bare = ChildQuestion(
        id: 'cq2',
        childId: 'k1',
        text: 'Why?',
        askedAt: DateTime.utc(2026),
      );
      expect(bare.toJson().containsKey('options'), isFalse);
      expect(bare.toJson().containsKey('answer'), isFalse);
      expect(ChildQuestion.fromJson(bare.toJson()), bare);
      expect(bare.isPending, isTrue);
    });

    test('an answered question keeps who answered', () {
      final q = ChildQuestion(
        id: 'cq1',
        childId: 'k1',
        text: 'Which?',
        askedAt: DateTime.utc(2026),
      ).resolve(
        ChildQuestionState.answered,
        answer: 'Both',
        at: DateTime.utc(2026, 1, 1, 0, 1),
        by: AnsweredBy.user,
      );
      final back = ChildQuestion.fromJson(q.toJson());
      expect(back.state, ChildQuestionState.answered);
      expect(back.answeredBy, AnsweredBy.user);
      expect(back.answer, 'Both');
      expect(back.isPending, isFalse);
    });

    test('an unknown state reads as pending', () {
      final j = {
        ..._question('cq1', 'k1'),
        'state': 'sideways',
        'answeredBy': 'robot',
      };
      final q = ChildQuestion.fromJson(j);
      expect(q.state, ChildQuestionState.pending);
      expect(q.answeredBy, isNull);
    });
  });

  group('WorkState', () {
    test('only the ended states are ended', () {
      expect(
        WorkState.values.where((s) => s.isEnded),
        unorderedEquals([
          WorkState.done,
          WorkState.failed,
          WorkState.cancelled,
          WorkState.timedOut,
        ]),
      );
    });

    test('the new states round-trip on a child', () {
      for (final state in [
        WorkState.waitingForAnswer,
        WorkState.idle,
        WorkState.timedOut,
      ]) {
        final c = ChildAgent(id: 'k', task: 't', state: state);
        expect(ChildAgent.fromJson(c.toJson()).state, state);
      }
    });
  });

  group('reducer', () {
    test('a question puts the child in waitingForAnswer and adds a row', () {
      final s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1', options: ['App server', 'CLI']),
      });
      final child = s.children.firstWhere((c) => c.id == 'k1');
      expect(child.state, WorkState.waitingForAnswer);
      expect(child.pendingQuestion?.id, 'cq1');
      expect(child.pendingQuestion?.options, ['App server', 'CLI']);
      final item = s.items.whereType<ChildQuestionItem>().single;
      expect(item.id, 'childq:cq1');
      expect(item.task, 'Survey Codex');
      expect(item.question.isPending, isTrue);
      expect(item.at, DateTime.parse(_askedAt));
      expect(s.pendingChildQuestions.map((q) => q.id), ['cq1']);
      expect(ChatSnapshot.fromJson(s.toJson()), s);
    });

    test('a child question never makes the chat "need you"', () {
      var s = _crew();
      expect(s.status, ChatStatus.running);
      s = _apply(s, {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      s = _apply(s, {
        'kind': 'child.question.asked',
        'question': _question('cq2', 'k2'),
      });
      expect(s.pendingChildQuestions, hasLength(2));
      // Not the user's: no pending question, no approval, no "needs you".
      expect(s.pendingQuestions, isEmpty);
      expect(s.pendingApprovals, isEmpty);
      expect(s.status, isNot(ChatStatus.needsYou));
      // Both children wait on the parent, and the run is over: done.
      expect(s.status, ChatStatus.done);
      expect(ChatSummary.of(s).status, ChatStatus.done);
      expect(ChatSummary.of(s).runningChildren, 0);
      // A real user question on top still does.
      s = _apply(s, {
        'kind': 'question.asked',
        'question': {
          'id': 'q1',
          'requestedAt': _askedAt,
          'items': [
            {'id': 'a', 'header': 'A', 'text': 'A?', 'kind': 'text'},
          ],
        },
      });
      expect(s.status, ChatStatus.needsYou);
      expect(s.pendingChildQuestions, hasLength(2));
    });

    test('the parent answers: the child runs again, the row is answered', () {
      var s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      s = _apply(s, {
        'kind': 'child.question.resolved',
        'childId': 'k1',
        'questionId': 'cq1',
        'answer': 'App server only.',
        'answeredBy': 'parent',
        'at': '2026-10-26T09:01:30.000Z',
      });
      final child = s.children.firstWhere((c) => c.id == 'k1');
      expect(child.state, WorkState.running);
      expect(child.pendingQuestion, isNull);
      final q = s.items.whereType<ChildQuestionItem>().single.question;
      expect(q.state, ChildQuestionState.answered);
      expect(q.answer, 'App server only.');
      expect(q.answeredBy, AnsweredBy.parent);
      expect(q.answeredAt, DateTime.utc(2026, 10, 26, 9, 1, 30));
      expect(s.pendingChildQuestions, isEmpty);
    });

    test('an answer without a who is the parent\'s', () {
      var s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      s = _apply(s, {
        'kind': 'child.question.resolved',
        'childId': 'k1',
        'questionId': 'cq1',
        'answer': 'ok',
      });
      expect(
        s.items.whereType<ChildQuestionItem>().single.question.answeredBy,
        AnsweredBy.parent,
      );
    });

    test('a second answer, or one for the wrong question, changes nothing', () {
      var s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      final wrong = _apply(s, {
        'kind': 'child.question.resolved',
        'childId': 'k1',
        'questionId': 'nope',
        'answer': 'x',
      });
      expect(wrong.children, s.children);
      expect(wrong.items, s.items);
      s = _apply(s, {
        'kind': 'child.question.resolved',
        'childId': 'k1',
        'questionId': 'cq1',
        'answer': 'first',
      });
      final again = _apply(s, {
        'kind': 'child.question.resolved',
        'childId': 'k1',
        'questionId': 'cq1',
        'answer': 'second',
        'answeredBy': 'user',
      });
      expect(
        again.items.whereType<ChildQuestionItem>().single.question.answer,
        'first',
      );
    });

    test('a question of an unknown or ended child is ignored', () {
      var s = _crew();
      final unknown = _apply(s, {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'ghost'),
      });
      expect(unknown.items, s.items);
      s = _apply(s, {'kind': 'child.finished', 'childId': 'k1'});
      final ended = _apply(s, {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      expect(ended.items.whereType<ChildQuestionItem>(), isEmpty);
    });

    test('the child ending cancels its pending question', () {
      var s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      s = _apply(s, {
        'kind': 'child.finished',
        'childId': 'k1',
        'state': 'cancelled',
        'at': '2026-10-26T09:02:00.000Z',
      });
      final child = s.children.firstWhere((c) => c.id == 'k1');
      expect(child.state, WorkState.cancelled);
      expect(child.pendingQuestion, isNull);
      final q = s.items.whereType<ChildQuestionItem>().single.question;
      expect(q.state, ChildQuestionState.cancelled);
      expect(q.answer, isNull);
    });

    test('progress never revives a waiting child; idle and timeout work', () {
      var s = _apply(_crew(), {
        'kind': 'child.question.asked',
        'question': _question('cq1', 'k1'),
      });
      s = _apply(s, {
        'kind': 'child.progress',
        'childId': 'k1',
        'activity': 'read ws.ts',
        'state': 'running',
      });
      var k1 = s.children.firstWhere((c) => c.id == 'k1');
      expect(k1.state, WorkState.waitingForAnswer);
      expect(k1.activity, 'read ws.ts');
      s = _apply(s, {
        'kind': 'child.progress',
        'childId': 'k2',
        'state': 'idle',
      });
      expect(
        s.children.firstWhere((c) => c.id == 'k2').state,
        WorkState.idle,
      );
      s = _apply(s, {
        'kind': 'child.finished',
        'childId': 'k2',
        'state': 'timedOut',
      });
      expect(
        s.children.firstWhere((c) => c.id == 'k2').state,
        WorkState.timedOut,
      );
      // A timeout leaves a return line, like a failure.
      expect(s.items.whereType<ChildResult>().single.state, WorkState.timedOut);
      k1 = s.children.firstWhere((c) => c.id == 'k1');
      expect(k1.state, WorkState.waitingForAnswer);
    });
  });

  group('answerChildQuestion on the fake backend', () {
    late ScriptedBackend backend;
    late String chat;

    ChatSnapshot state() => backend.stateOf(chat)!;

    setUp(() async {
      backend = ScriptedBackend(clock: ManualClock());
      chat = (await backend.createChat(title: 'T')).id;
      await backend.send(chat, 'go');
      backend.emit(chat, {
        'kind': 'child.spawned',
        'childId': 'k1',
        'task': 'Survey Codex',
      });
      backend.emit(chat, {
        'kind': 'child.question.asked',
        'question': {
          'id': 'cq1',
          'childId': 'k1',
          'text': 'Which path?',
          'options': ['App server', 'CLI'],
        },
      });
    });

    test('the user answers in the parent\'s place', () async {
      expect(state().pendingChildQuestions, hasLength(1));
      await backend.answerChildQuestion(chat, 'k1', 'cq1', 'The app server.');
      final q = state().items.whereType<ChildQuestionItem>().single.question;
      expect(q.state, ChildQuestionState.answered);
      expect(q.answer, 'The app server.');
      expect(q.answeredBy, AnsweredBy.user);
      expect(q.answeredAt, isNotNull);
      expect(state().children.single.state, WorkState.running);
      expect(backend.commands.last.name, 'answerChildQuestion');
      expect(backend.commands.last.args, [chat, 'k1', 'cq1', 'The app server.']);
    });

    test('asking stamps the time when the script gives none', () {
      expect(state().pendingChildQuestions.single.askedAt, isNotNull);
    });

    test('a second answer conflicts; unknown ids and empty text fail', () async {
      await expectLater(
        backend.answerChildQuestion(chat, 'k1', 'nope', 'x'),
        throwsA(isA<KitNotFound>()),
      );
      await expectLater(
        backend.answerChildQuestion(chat, 'k1', 'cq1', '  '),
        throwsA(isA<KitInvalid>()),
      );
      await backend.answerChildQuestion(chat, 'k1', 'cq1', 'once');
      await expectLater(
        backend.answerChildQuestion(chat, 'k1', 'cq1', 'twice'),
        throwsA(isA<KitConflict>()),
      );
    });

    test('without the capability it is unsupported', () async {
      final limited = ScriptedBackend(
        clock: ManualClock(),
        capabilities: KitCapabilities(const [KitCapability.children]),
      );
      final id = (await limited.createChat()).id;
      await expectLater(
        limited.answerChildQuestion(id, 'k1', 'cq1', 'x'),
        throwsA(
          isA<KitUnsupported>().having(
            (e) => e.capability,
            'capability',
            KitCapability.answerChildQuestion,
          ),
        ),
      );
    });
  });

  group('the quota scenario', () {
    test('one child asks and is answered, another keeps asking', () async {
      final clock = ManualClock();
      final backend = ScriptedBackend(
        scripts: [quotaReconnectScript()],
        clock: clock,
      );
      final done = backend.play();
      await clock.runAll();
      await done;
      final s = backend.stateOf(quotaChatId)!;

      final answered = s.items
          .whereType<ChildQuestionItem>()
          .firstWhere((i) => i.question.id == 'cq1');
      expect(answered.task, 'Survey quota handling in Codex');
      expect(answered.question.state, ChildQuestionState.answered);
      expect(answered.question.answeredBy, AnsweredBy.parent);
      expect(answered.question.options, ['App server', 'CLI', 'Both']);

      final pending = s.pendingChildQuestions.single;
      expect(pending.id, 'cq2');
      expect(pending.childId, 'c7e4');
      final waiting = s.children.firstWhere((c) => c.id == 'c7e4');
      expect(waiting.state, WorkState.waitingForAnswer);
      expect(
        clock.now().difference(pending.askedAt),
        const Duration(seconds: 40),
      );

      // The user's approval is the only thing that needs them.
      expect(s.status, ChatStatus.needsYou);
      expect(s.pendingApprovals, hasLength(1));
      expect(s.pendingQuestions, isEmpty);

      // The LCM history: the marker, the view and the numbers.
      final marker = s.item('cm1')! as CompactionItem;
      expect(marker.state, CompactionState.done);
      expect(marker.episodesSummarized, 3);
      expect((marker.tokensBefore, marker.tokensAfter), (41000, 9000));
      expect(s.items.indexWhere((i) => i.id == 'cm1'), greaterThan(0));
      expect(s.context, quotaContextView());
    });
  });
}
