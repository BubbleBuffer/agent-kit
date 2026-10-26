import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show Question, QuestionAnswer;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

typedef _Sent = List<Map<String, QuestionAnswer>>;

Widget _prompt(
  Question q,
  _Sent sent, {
  bool Function()? composerEmpty,
  bool captureKeys = true,
}) => QuestionPrompt(
  question: q,
  now: fixtureNow,
  onAnswer: sent.add,
  composerEmpty: composerEmpty,
  captureKeys: captureKeys,
);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
}

void main() {
  testWidgets('shows the pill, the age, the question and the option rows', (
    tester,
  ) async {
    await pumpComposer(tester, _prompt(fixtureQuestion, []), width: 1000);
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('waiting 3m'), findsOneWidget);
    expect(
      find.text('Should a stale quota figure show its age?'),
      findsOneWidget,
    );
    expect(find.text('Pick one'), findsOneWidget);
    expect(find.text('Only on hover'), findsOneWidget);
    expect(
      find.text('The bar dims; hovering shows the last update.'),
      findsOneWidget,
    );
    expect(find.text('Always'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
    expect(find.text('Something else…'), findsOneWidget);
    // Number keys 1 to 4 (three options and Other), Skip and Answer.
    for (final n in ['1', '2', '3', '4']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    // One question: no tabs, no count.
    expect(find.text('Stale figure'), findsNothing);
    expect(find.textContaining(' of '), findsNothing);
  });

  testWidgets('the number keys hide at compact width', (tester) async {
    await pumpComposer(tester, _prompt(fixtureQuestion, []), width: 390);
    expect(find.text('Always'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('semantics: labels, a group and the Answer button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpComposer(tester, _prompt(fixtureQuestion, []));
    expect(
      find.bySemanticsLabel(RegExp('Question from the agent')),
      findsWidgets,
    );
    expect(find.bySemanticsLabel(RegExp('Pick one')), findsWidgets);
    expect(
      find.bySemanticsLabel(
        RegExp('Always. A small age label sits next to the figure.'),
      ),
      findsWidgets,
    );
    expect(find.bySemanticsLabel(RegExp('Other answer')), findsWidgets);
    handle.dispose();
  });

  group('pick one', () {
    testWidgets('selection is exclusive, and Answer waits for one', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _tap(tester, 'Answer');
      expect(sent, isEmpty);
      await _tap(tester, 'Only on hover');
      await _tap(tester, 'Always');
      expect(sent, isEmpty, reason: 'a click does not send');
      await _tap(tester, 'Answer');
      expect(sent, hasLength(1));
      expect(sent.single.keys, ['age']);
      expect(sent.single['age']!.choices, ['Always']);
      expect(sent.single['age']!.text, isNull);
      expect(sent.single['age']!.skipped, isFalse);
    });

    testWidgets('typing into Other selects it and drops the option', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _tap(tester, 'Always');
      await _type(tester, '  Both ');
      await _tap(tester, 'Answer');
      final a = sent.single['age']!;
      expect(a.choices, isEmpty);
      expect(a.text, 'Both');
    });

    testWidgets('choosing an option clears the Other text', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _type(tester, 'Both');
      await _tap(tester, 'Never');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await _tap(tester, 'Answer');
      expect(sent.single['age']!.choices, ['Never']);
      expect(sent.single['age']!.text, isNull);
    });
  });

  group('pick any', () {
    testWidgets('clicks toggle, and Answer sends whatever is ticked', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixturePickAnyRequest, sent));
      expect(find.text('Pick any'), findsOneWidget);
      await _tap(tester, 'CLI status line');
      await _tap(tester, 'Web quota bar');
      await _tap(tester, 'CLI status line');
      await _tap(tester, 'Desktop tray');
      await _tap(tester, 'Answer');
      expect(sent.single['views']!.choices, ['Web quota bar', 'Desktop tray']);
    });

    testWidgets('none ticked is a valid answer', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixturePickAnyRequest, sent));
      await _tap(tester, 'Answer');
      expect(sent.single['views']!.choices, isEmpty);
      expect(sent.single['views']!.skipped, isFalse);
    });

    testWidgets('Other text rides along with the ticks', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixturePickAnyRequest, sent));
      await _tap(tester, 'Desktop tray');
      await _type(tester, 'Hub dashboard');
      await _tap(tester, 'Answer');
      expect(sent.single['views']!.choices, ['Desktop tray']);
      expect(sent.single['views']!.text, 'Hub dashboard');
    });
  });

  group('text only', () {
    testWidgets('Answer is disabled while empty, then sends the text', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureTextRequest, sent));
      expect(find.text('Type an answer…'), findsOneWidget);
      expect(find.text('Pick one'), findsNothing);
      await _tap(tester, 'Answer');
      expect(sent, isEmpty);
      await _type(tester, '   ');
      await _tap(tester, 'Answer');
      expect(sent, isEmpty, reason: 'blank counts as empty');
      await _type(tester, '  Last known figure ');
      await _tap(tester, 'Answer');
      expect(sent.single['label']!.text, 'Last known figure');
      expect(sent.single['label']!.choices, isEmpty);
    });
  });

  group('several questions', () {
    testWidgets('tabs and "N of M"; Back, Next and drafts', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureMixed, sent));
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Stale figure'), findsOneWidget);
      expect(find.text('Views'), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Back'), findsNothing, reason: 'nothing before step 1');
      expect(find.text('Next'), findsOneWidget);

      // Next needs an answer on a pick-one step.
      await _tap(tester, 'Next');
      expect(find.text('1 of 3'), findsOneWidget);
      await _tap(tester, 'Always');
      await _tap(tester, 'Next');
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Pick any'), findsOneWidget);
      await _tap(tester, 'CLI status line');

      // Back keeps the first draft, and Next keeps the second.
      await _tap(tester, 'Back');
      expect(find.text('1 of 3'), findsOneWidget);
      await _tap(tester, 'Next');
      await _tap(tester, 'Next');
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Answer'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(sent, isEmpty);

      await _type(tester, 'Updated 14s ago');
      await _tap(tester, 'Answer');
      expect(sent, hasLength(1));
      expect(sent.single.keys, ['age', 'views', 'label']);
      expect(sent.single['age']!.choices, ['Always']);
      expect(sent.single['views']!.choices, ['CLI status line']);
      expect(sent.single['label']!.text, 'Updated 14s ago');
    });

    testWidgets('a tab jumps to its question', (tester) async {
      await pumpComposer(tester, _prompt(fixtureMixed, []));
      await _tap(tester, 'Label');
      expect(find.text('3 of 3'), findsOneWidget);
      await _tap(tester, 'Stale figure');
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('Answer returns to a question left open', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureMixed, sent));
      await _tap(tester, 'Label');
      await _type(tester, 'Hi');
      await _tap(tester, 'Answer');
      expect(sent, isEmpty);
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('the five-question request has five tabs', (tester) async {
      await pumpComposer(tester, _prompt(fixtureFive, []), width: 390);
      expect(find.text('1 of 5'), findsOneWidget);
      for (final h in ['Stale figure', 'Views', 'Label', 'Reconnect']) {
        expect(find.text(h), findsOneWidget);
      }
      expect(find.text('Tests to add'), findsOneWidget);
    });
  });

  group('Skip', () {
    testWidgets('on a single question sends it skipped', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _tap(tester, 'Always');
      await _tap(tester, 'Skip');
      final a = sent.single['age']!;
      expect(a.skipped, isTrue);
      expect(a.choices, isEmpty);
      expect(a.text, isNull);
    });

    testWidgets('moves on, and the last Skip sends every item', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureMixed, sent));
      await _tap(tester, 'Always');
      await _tap(tester, 'Next');
      await _tap(tester, 'Skip');
      expect(find.text('3 of 3'), findsOneWidget);
      expect(sent, isEmpty);
      await _tap(tester, 'Skip');
      expect(sent, hasLength(1));
      expect(sent.single.keys, ['age', 'views', 'label']);
      expect(sent.single['age']!.skipped, isFalse);
      expect(sent.single['views']!.skipped, isTrue);
      expect(sent.single['label']!.skipped, isTrue);
    });
  });

  group('keys', () {
    testWidgets('number keys select, Enter sends', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _key(tester, LogicalKeyboardKey.digit2);
      await _key(tester, LogicalKeyboardKey.digit3);
      expect(sent, isEmpty);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(sent.single['age']!.choices, ['Never']);
    });

    testWidgets('number keys toggle pick-any options', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixturePickAnyRequest, sent));
      await _key(tester, LogicalKeyboardKey.digit1);
      await _key(tester, LogicalKeyboardKey.digit3);
      await _key(tester, LogicalKeyboardKey.digit1);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(sent.single['views']!.choices, ['CLI status line']);
    });

    testWidgets('Enter moves to Next, and does nothing without an answer', (
      tester,
    ) async {
      await pumpComposer(tester, _prompt(fixtureMixed, []));
      await _tap(tester, 'Always');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('2 of 3'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('3 of 3'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('3 of 3'), findsOneWidget, reason: 'empty text');
    });

    testWidgets('the Other number focuses its field; digits then type', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(tester, _prompt(fixtureQuestion, sent));
      await _key(tester, LogicalKeyboardKey.digit4);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await _key(tester, LogicalKeyboardKey.digit1);
      expect(find.text('Only on hover'), findsOneWidget);
      await _type(tester, '7 seconds');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(sent.single['age']!.text, '7 seconds');
    });

    testWidgets('a focused, non-empty composer keeps its digits', (
      tester,
    ) async {
      final sent = <Map<String, QuestionAnswer>>[];
      final controller = TextEditingController(text: 'x');
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpComposer(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _prompt(
              fixtureQuestion,
              sent,
              composerEmpty: () => controller.text.isEmpty,
            ),
            EditableText(
              controller: controller,
              focusNode: focus,
              style: const TextStyle(fontSize: 14),
              cursorColor: const Color(0xFF000000),
              backgroundCursorColor: const Color(0xFF000000),
            ),
          ],
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.digit2);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(sent, isEmpty);
    });

    testWidgets('captureKeys off ignores the number keys', (tester) async {
      final sent = <Map<String, QuestionAnswer>>[];
      await pumpComposer(
        tester,
        _prompt(fixtureQuestion, sent, captureKeys: false),
      );
      await _key(tester, LogicalKeyboardKey.digit2);
      await _tap(tester, 'Answer');
      expect(sent, isEmpty, reason: 'nothing was selected');
    });
  });
}
