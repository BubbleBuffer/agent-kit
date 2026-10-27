// Golden screenshots of the child question row in each state (pending,
// composing, no answer capability, answered by the agent, answered by you,
// cancelled) at 1000 and 390 px, light and dark.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chrome/chrome_harness.dart';

final _asked = DateTime.utc(2025, 12, 29, 10);
final _now = _asked.add(const Duration(seconds: 40));

ChildQuestionItem _item({
  ChildQuestionState state = ChildQuestionState.pending,
  String? answer,
  AnsweredBy? by,
}) => ChildQuestionItem(
  id: 'childq:cq2',
  task: 'Trace socket reconnect in the web client',
  question: ChildQuestion(
    id: 'cq2',
    childId: 'c7e4',
    text:
        'Is the reconnect handled in web/src/ws.ts, or in the shared '
        'client?',
    options: const ['ws.ts', 'Shared client'],
    askedAt: _asked,
    state: state,
    answer: answer,
    answeredAt: answer == null ? null : _asked.add(const Duration(seconds: 9)),
    answeredBy: by,
  ),
);

Widget _rows() => Builder(
  builder: (context) => ColoredBox(
    color: context.bb.surface,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChildQuestionRow(
            _item(),
            now: _now,
            onOpenChild: (_) {},
            onAnswer: (_, _, _) {},
          ),
          const SizedBox(height: 12),
          ChildQuestionRow(
            _item(),
            now: _now,
            onOpenChild: (_) {},
            onAnswer: (_, _, _) {},
            initialComposing: true,
          ),
          const SizedBox(height: 12),
          ChildQuestionRow(_item(), now: _now, onOpenChild: (_) {}),
          const SizedBox(height: 12),
          ChildQuestionRow(
            _item(
              state: ChildQuestionState.answered,
              answer: 'App server only. The CLI path is a thin wrapper.',
              by: AnsweredBy.parent,
            ),
            now: _now,
            onOpenChild: (_) {},
          ),
          const SizedBox(height: 12),
          ChildQuestionRow(
            _item(
              state: ChildQuestionState.answered,
              answer: 'Shared client, see web/src/net.ts.',
              by: AnsweredBy.user,
            ),
            now: _now,
            onOpenChild: (_) {},
          ),
          const SizedBox(height: 12),
          ChildQuestionRow(
            _item(state: ChildQuestionState.cancelled),
            now: _now,
          ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [1000, 390]) {
      testWidgets('child question rows, $width, ${brightness.name}', (
        tester,
      ) async {
        await pumpChrome(
          tester,
          Align(alignment: Alignment.topCenter, child: _rows()),
          brightness: brightness,
          size: Size(width.toDouble(), 1500),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await expectLater(
          find.byType(Column).first,
          matchesGoldenFile(
            '../goldens/child_question_${width}_${brightness.name}.png',
          ),
        );
      });
    }
  }
}
