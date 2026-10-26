// Golden screenshots of the question prompt at 390 and 1000, light and dark:
// each kind alone, then the mixed request at step 2, the five-question request
// and the answered lines. Re-render with
// `flutter test --tags golden --update-goldens` (or the CI dispatch).

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show Question, QuestionAnswer, QuestionState;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Widget _gap(Widget w) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

Widget _column(List<Widget> children, double width) => Align(
  alignment: Alignment.topLeft,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width > 800 ? 720 : width),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);

QuestionPrompt _prompt(
  Question q, {
  int step = 0,
  Map<String, QuestionAnswer> answers = const {},
}) => QuestionPrompt(
  question: q,
  now: fixtureNow,
  captureKeys: false,
  initialStep: step,
  initialAnswers: answers,
  onAnswer: (_) {},
);

/// The three kinds, each alone, with an answer picked to show the selected
/// look.
Widget _kinds(double width) => _column([
  _gap(
    _prompt(
      fixtureQuestion,
      answers: {'age': QuestionAnswer(choices: const ['Only on hover'])},
    ),
  ),
  _gap(
    _prompt(
      fixturePickAnyRequest,
      answers: {
        'views': QuestionAnswer(
          choices: const ['Web quota bar', 'Desktop tray'],
          text: 'Hub dashboard',
        ),
      },
    ),
  ),
  _prompt(fixtureTextRequest),
], width);

final _answered = Question(
  id: 'qs4',
  requestedAt: fixtureMixed.requestedAt,
  items: fixtureMixed.items,
  state: QuestionState.answered,
  answers: {
    'age': QuestionAnswer(choices: const ['Only on hover']),
    'views': QuestionAnswer(
      choices: const ['Web quota bar', 'Desktop tray'],
      text: 'Hub dashboard',
    ),
    'label': QuestionAnswer(skipped: true),
  },
);

/// The mixed request at step 2, the five-question request at step 4 and the
/// answered lines.
Widget _requests(double width) => _column([
  _gap(
    _prompt(
      fixtureMixed,
      step: 1,
      answers: {
        'age': QuestionAnswer(choices: const ['Only on hover']),
        'views': QuestionAnswer(choices: const ['Web quota bar']),
      },
    ),
  ),
  _gap(
    _prompt(
      fixtureFive,
      step: 3,
      answers: {
        'age': QuestionAnswer(choices: const ['Always']),
        'views': QuestionAnswer(choices: const ['Desktop tray']),
        'label': QuestionAnswer(skipped: true),
        'wait': QuestionAnswer(choices: const ['After 5 seconds']),
      },
    ),
  ),
  QuestionAnswerLines(question: _answered),
], width);

void main() {
  const sheets = <String, (Widget Function(double), double)>{
    'kinds': (_kinds, 1200),
    'requests': (_requests, 1300),
  };
  for (final width in [390.0, 1000.0]) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: (build, height)) in sheets.entries) {
        testWidgets('question $name, ${width.toInt()} ${brightness.name}', (
          tester,
        ) async {
          await pumpComposer(
            tester,
            build(width - 32),
            brightness: brightness,
            width: width,
            height: width < 600 ? height + 500 : height,
          );
          await expectLater(
            find.byType(WidgetsApp),
            matchesGoldenFile(
              '../goldens/question_${name}_${width.toInt()}_${brightness.name}.png',
            ),
          );
        });
      }
    }
  }
}
