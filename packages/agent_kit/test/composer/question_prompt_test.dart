import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show Question;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Widget _prompt(Question q, List<String> answers) =>
    QuestionPrompt(question: q, now: fixtureNow, onAnswer: answers.add);

void main() {
  testWidgets('shows the pill, the age, the text and the options', (
    tester,
  ) async {
    await pumpComposer(tester, _prompt(fixtureQuestion, []));
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('waiting 3m'), findsOneWidget);
    expect(find.text('Should a stale figure show its age?'), findsOneWidget);
    expect(find.text('Only on hover'), findsOneWidget);
    expect(find.text('Always'), findsOneWidget);
  });

  testWidgets('an option answers', (tester) async {
    final answers = <String>[];
    await pumpComposer(tester, _prompt(fixtureQuestion, answers));
    await tester.tap(find.text('Always'));
    await tester.pump();
    expect(answers, ['Always']);
  });

  testWidgets('a typed answer is sent; Answer is off while empty', (
    tester,
  ) async {
    final answers = <String>[];
    await pumpComposer(tester, _prompt(fixtureQuestion, answers));
    await tester.tap(find.text('Answer'));
    await tester.pump();
    expect(answers, isEmpty);
    await tester.enterText(find.byType(EditableText), '  Only in the tooltip ');
    await tester.pump();
    await tester.tap(find.text('Answer'));
    await tester.pump();
    expect(answers, ['Only in the tooltip']);
  });

  testWidgets('a free-text-only question has no option buttons', (
    tester,
  ) async {
    final q = Question(
      id: 'qs2',
      text: 'Which branch?',
      requestedAt: fixtureNow,
    );
    await pumpComposer(tester, _prompt(q, []), width: 390);
    expect(find.text('Type an answer'), findsOneWidget);
    expect(find.text('Always'), findsNothing);
  });
}
