import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:test/test.dart';

QuestionItem _item(
  String id, {
  QuestionKind kind = QuestionKind.pickOne,
  List<QuestionOption> options = const [QuestionOption(label: 'A')],
  bool allowOther = false,
}) => QuestionItem(
  id: id,
  header: id,
  text: 'Question $id?',
  kind: kind,
  options: options,
  allowOther: allowOther,
);

Question _request(List<QuestionItem> items) =>
    Question(id: 'q', requestedAt: DateTime.utc(2026, 10, 26, 9), items: items);

void main() {
  group('Question model', () {
    test('every kind round-trips through JSON', () {
      final q = Question(
        id: 'q1',
        requestedAt: DateTime.utc(2026, 10, 26, 9),
        items: [
          QuestionItem(
            id: 'one',
            header: 'One',
            text: 'Pick **one**.',
            options: const [
              QuestionOption(label: 'A', description: 'The first.'),
              QuestionOption(label: 'B'),
            ],
            allowOther: true,
          ),
          _item(
            'any',
            kind: QuestionKind.pickAny,
            options: const [
              QuestionOption(label: 'X'),
              QuestionOption(label: 'Y'),
            ],
            allowOther: true,
          ),
          _item('text', kind: QuestionKind.text, options: const []),
        ],
        state: QuestionState.answered,
        answers: {
          'one': QuestionAnswer(choices: const ['A']),
          'any': QuestionAnswer(choices: const ['X', 'Y'], text: 'Z'),
          'text': QuestionAnswer(skipped: true),
        },
      );
      final back = Question.fromJson(q.toJson());
      expect(back, q);
      expect(back.items.map((i) => i.kind), QuestionKind.values);
      expect(back.items.first.options.first.description, 'The first.');
      expect(back.answers!['any']!.text, 'Z');
      expect(back.answers!['text']!.skipped, isTrue);
    });

    test('a pending request has no answers', () {
      final q = Question.fromJson(_request([_item('a')]).toJson());
      expect(q.isPending, isTrue);
      expect(q.answers, isNull);
    });

    test('0 and 6 items are rejected, 1 and 5 are fine', () {
      expect(() => _request([]), throwsArgumentError);
      expect(
        () => _request([for (var i = 0; i < 6; i++) _item('i$i')]),
        throwsArgumentError,
      );
      expect(_request([_item('a')]).items, hasLength(1));
      expect(
        _request([for (var i = 0; i < maxQuestionItems; i++) _item('i$i')]),
        isA<Question>(),
      );
    });

    test('fromJson validates too', () {
      final json = _request([_item('a')]).toJson();
      json['items'] = <Object?>[];
      expect(() => Question.fromJson(json), throwsArgumentError);
      json['items'] = [for (var i = 0; i < 6; i++) _item('i$i').toJson()];
      expect(() => Question.fromJson(json), throwsArgumentError);
    });

    test('a pick item needs options or Other', () {
      expect(
        () => _request([_item('a', options: const [])]),
        throwsArgumentError,
      );
      expect(
        () => _request([
          _item('a', kind: QuestionKind.pickAny, options: const []),
        ]),
        throwsArgumentError,
      );
      expect(
        _request([_item('a', options: const [], allowOther: true)]),
        isA<Question>(),
      );
      expect(
        _request([_item('t', kind: QuestionKind.text, options: const [])]),
        isA<Question>(),
      );
    });
  });

  group('question scenario', () {
    late ManualClock clock;
    late ScriptedBackend backend;

    setUp(() async {
      clock = ManualClock();
      backend = ScriptedBackend(scripts: [mixedQuestionScript()], clock: clock);
      final done = backend.play();
      await clock.runAll();
      await done;
    });

    test('ends waiting on a mixed request', () {
      final s = backend.stateOf(questionChatId)!;
      expect(s.status, ChatStatus.needsYou);
      final q = s.pendingQuestions.single;
      expect(q.items.map((i) => i.kind), QuestionKind.values);
      expect(q.items.first.options.every((o) => o.description != null), isTrue);
      expect(q.items.first.allowOther, isTrue);
    });

    test('answerQuestion resolves it; every item needs an entry', () async {
      expect(
        () => backend.answerQuestion(questionChatId, mixedQuestionId, {
          'age': QuestionAnswer(choices: const ['Always']),
        }),
        throwsA(isA<KitInvalid>()),
      );
      final answers = {
        'age': QuestionAnswer(choices: const ['Always']),
        'views': QuestionAnswer(choices: const ['Desktop tray'], text: 'Hub'),
        'label': QuestionAnswer(skipped: true),
      };
      await backend.answerQuestion(questionChatId, mixedQuestionId, answers);
      final s = backend.stateOf(questionChatId)!;
      expect(s.status, ChatStatus.running);
      final q = s.questions.single;
      expect(q.state, QuestionState.answered);
      expect(q.answers, answers);
      expect(
        () => backend.answerQuestion(questionChatId, mixedQuestionId, answers),
        throwsA(isA<KitConflict>()),
      );
    });
  });
}
