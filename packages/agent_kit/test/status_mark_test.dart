import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus, WorkState;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('every status shows its label in both variants', (tester) async {
    await pumpKit(
      tester,
      Column(
        children: [
          for (final s in ChatStatus.values) ...[
            StatusMark(s),
            StatusMark.pill(s),
          ],
        ],
      ),
    );
    for (final s in ChatStatus.values) {
      expect(
        find.textContaining(statusLabel(s), findRichText: true),
        findsWidgets,
        reason: '$s',
      );
    }
  });

  testWidgets('a custom label and a detail replace the default', (
    tester,
  ) async {
    await pumpKit(
      tester,
      const StatusMark(ChatStatus.running, label: 'Busy', detail: '3 agents'),
    );
    expect(find.textContaining('Busy', findRichText: true), findsOneWidget);
    expect(find.textContaining('3 agents', findRichText: true), findsOneWidget);
    expect(find.text('Running'), findsNothing);
  });

  test('work states map to statuses', () {
    expect(statusOfWork(WorkState.running), ChatStatus.running);
    expect(statusOfWork(WorkState.done), ChatStatus.done);
    expect(statusOfWork(WorkState.failed), ChatStatus.failed);
    expect(statusOfWork(WorkState.cancelled), ChatStatus.idle);
  });

  testWidgets('the running mark breathes, and stops when motion is reduced', (
    tester,
  ) async {
    Widget app(bool reduced) => WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: const BbThemeScope(
          brightness: Brightness.light,
          child: StatusMark(ChatStatus.running),
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
