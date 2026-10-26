import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show Question, QuestionAnswer, QuestionState;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Question _answered(Map<String, QuestionAnswer> answers) => Question(
  id: 'qs4',
  requestedAt: fixtureMixed.requestedAt,
  items: fixtureMixed.items,
  state: QuestionState.answered,
  answers: answers,
);

/// The one line of text whose plain text is [text].
Finder _line(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == text,
);

void main() {
  testWidgets('one line per question: answer, skipped', (tester) async {
    final q = _answered({
      'age': QuestionAnswer(choices: const ['Only on hover']),
      'views': QuestionAnswer(
        choices: const ['Web quota bar', 'Desktop tray'],
        text: 'Hub dashboard',
      ),
      'label': QuestionAnswer(skipped: true),
    });
    await pumpComposer(tester, QuestionAnswerLines(question: q));
    expect(
      _line('Should a stale quota figure show its age? Only on hover'),
      findsOneWidget,
    );
    expect(
      _line(
        'Which views should keep the last known figure? '
        'Web quota bar, Desktop tray, Hub dashboard',
      ),
      findsOneWidget,
    );
    expect(
      _line(
        'What should the stale label say? I’ll use it in the tooltip and the screen-reader text. Skipped',
      ),
      findsOneWidget,
    );
  });

  test('answerSummary joins choices and typed text', () {
    final item = fixtureMixed.items[1];
    expect(
      answerSummary(item, QuestionAnswer(choices: const ['A'], text: 'B')),
      'A, B',
    );
    expect(answerSummary(item, QuestionAnswer()), 'None');
    expect(answerSummary(item, QuestionAnswer(skipped: true)), isNull);
    expect(answerSummary(item, null), isNull);
  });
}
