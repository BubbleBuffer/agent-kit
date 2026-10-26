// Golden screenshots of the composer group at 390 and 1000, light and dark.
// Re-render with `flutter test --tags golden --update-goldens` (or the CI
// dispatch).

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Widget _gap(Widget w) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

Widget _sheet() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _gap(
        ApprovalBar(
          approval: fixtureApproval,
          now: fixtureNow,
          captureKeys: false,
          onReview: () {},
          onDecide: (_) {},
        ),
      ),
      _gap(
        ApprovalBar(
          approval: fixtureApproval,
          now: fixtureNow,
          captureKeys: false,
          initiallyDenying: true,
          onDecide: (_) {},
        ),
      ),
      _gap(
        QuestionPrompt(
          question: fixtureTextRequest,
          now: fixtureNow,
          captureKeys: false,
          onAnswer: (_) {},
        ),
      ),
      _gap(
        QueuedRow(
          input: fixtureQueued,
          onSendNow: (_) {},
          onEdit: (_, _) {},
          onRemove: (_) {},
        ),
      ),
      _gap(
        QueuedRow(
          input: fixtureQueued,
          initiallyEditing: true,
          onEdit: (_, _) {},
        ),
      ),
      _gap(AgentComposer(onSubmit: (_) {})),
      AgentComposer(
        running: true,
        refs: const [fixtureChip],
        models: fixtureModels,
        modelId: 'flash',
        workspaces: fixtureWorkspaces,
        workspaceId: 'base',
        onSubmit: (_) {},
      ),
    ],
  );
}

void main() {
  for (final width in [390.0, 1000.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('composer group, ${width.toInt()} ${brightness.name}', (
        tester,
      ) async {
        await pumpComposer(
          tester,
          _sheet(),
          brightness: brightness,
          width: width,
          height: 1100,
        );
        await expectLater(
          find.byType(WidgetsApp),
          matchesGoldenFile(
            '../goldens/composer_${width.toInt()}_${brightness.name}.png',
          ),
        );
      });
    }
  }
}
