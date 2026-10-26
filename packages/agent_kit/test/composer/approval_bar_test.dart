import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show Approval, ApprovalChoice, ApprovalDecision, ToolKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Widget _bar(
  List<ApprovalDecision> decisions, {
  Approval? approval,
  VoidCallback? onReview,
  bool Function()? composerEmpty,
  bool captureKeys = true,
}) => ApprovalBar(
  approval: approval ?? fixtureApproval,
  now: fixtureNow,
  onDecide: decisions.add,
  onReview: onReview,
  composerEmpty: composerEmpty,
  captureKeys: captureKeys,
);

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('shows the pill, the age, the action and the counts', (
    tester,
  ) async {
    await pumpComposer(tester, _bar([], onReview: () {}));
    expect(find.text('Needs approval'), findsOneWidget);
    expect(find.text('waiting 12m'), findsOneWidget);
    expect(find.text('edit'), findsOneWidget);
    expect(find.text('…/usage/mod.rs'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('−3'), findsOneWidget);
    expect(find.text('Review diff'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('For session'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
  });

  testWidgets('the age counts up from requestedAt and is not a countdown', (
    tester,
  ) async {
    final later = ApprovalBar(
      approval: fixtureApproval,
      now: fixtureNow.add(const Duration(minutes: 53)),
      onDecide: (_) {},
    );
    await pumpComposer(tester, later);
    expect(find.text('waiting 1h 5m'), findsOneWidget);
    expect(find.textContaining('expires'), findsNothing);
  });

  testWidgets('Review diff needs a handler and a diff', (tester) async {
    await pumpComposer(tester, _bar([]));
    expect(find.text('Review diff'), findsNothing);

    var reviews = 0;
    await pumpComposer(tester, _bar([], onReview: () => reviews++));
    await tester.tap(find.text('Review diff'));
    expect(reviews, 1);

    final noDiff = Approval(
      id: 'ap2',
      tool: 'bash',
      kind: ToolKind.exec,
      target: 'cargo test -p bubblepaw-host usage',
      requestedAt: fixtureNow.subtract(const Duration(minutes: 1)),
    );
    await pumpComposer(tester, _bar([], approval: noDiff, onReview: () {}));
    expect(find.text('Review diff'), findsNothing);
    expect(find.text('cargo test -p bubblepaw-host usage'), findsOneWidget);
  });

  testWidgets('the buttons decide', (tester) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Approve'));
    await tester.tap(find.text('For session'));
    await tester.pump();
    expect(decisions.map((d) => d.choice), [
      ApprovalChoice.approve,
      ApprovalChoice.approveForSession,
    ]);
  });

  testWidgets('the keys 1, 2 and 3 fire the actions', (tester) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await _key(tester, LogicalKeyboardKey.digit1);
    await _key(tester, LogicalKeyboardKey.digit2);
    expect(decisions.map((d) => d.choice), [
      ApprovalChoice.approve,
      ApprovalChoice.approveForSession,
    ]);
    await _key(tester, LogicalKeyboardKey.digit3);
    expect(find.text('Reason for the agent (optional)'), findsOneWidget);
    expect(decisions, hasLength(2));
  });

  testWidgets('the keys are off when the bar does not capture them', (
    tester,
  ) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions, captureKeys: false));
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(decisions, isEmpty);
  });

  testWidgets('Deny opens a reason field; Deny sends it', (tester) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect(find.text('Deny edit'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'wrong file');
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(decisions.single.choice, ApprovalChoice.deny);
    expect(decisions.single.reason, 'wrong file');
  });

  testWidgets('an empty reason sends a bare denial', (tester) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(decisions.single.choice, ApprovalChoice.deny);
    expect(decisions.single.reason, isNull);
  });

  testWidgets('Enter in the reason field denies', (tester) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'no');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(decisions.single.reason, 'no');
  });

  testWidgets('Esc in the reason field goes back to the three buttons', (
    tester,
  ) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'x');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(decisions, isEmpty);
  });

  testWidgets('keys 1-3 are quiet while typing in the reason field', (
    tester,
  ) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(tester, _bar(decisions));
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'a');
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(decisions, isEmpty);
  });

  testWidgets('1 fires from a focused composer only when it is empty', (
    tester,
  ) async {
    final decisions = <ApprovalDecision>[];
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpComposer(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bar(decisions, composerEmpty: () => controller.text.isEmpty),
          AgentComposer(controller: controller, onSubmit: (_) {}),
        ],
      ),
    );
    await tester.enterText(find.byType(EditableText), 'abc');
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(decisions, isEmpty);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(decisions.single.choice, ApprovalChoice.approve);
  });

  testWidgets('without composerEmpty a focused composer keeps its digits', (
    tester,
  ) async {
    final decisions = <ApprovalDecision>[];
    await pumpComposer(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bar(decisions),
          AgentComposer(onSubmit: (_) {}),
        ],
      ),
    );
    await tester.enterText(find.byType(EditableText), '');
    await _key(tester, LogicalKeyboardKey.digit2);
    expect(decisions, isEmpty);
  });

  testWidgets('the approval bar stacks its buttons when compact', (
    tester,
  ) async {
    await pumpComposer(tester, _bar([]), width: 390);
    final approve = tester.getRect(find.text('Approve'));
    final deny = tester.getRect(find.text('Deny'));
    expect(deny.top, approve.top); // three across
    expect(find.text('1'), findsNothing); // no key hints on a phone

    await pumpComposer(tester, _bar([]), width: 1000);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  for (final width in [600.0, 640.0, 700.0, 800.0, 1000.0]) {
    testWidgets('the bar follows its width, $width px', (tester) async {
      await pumpComposer(tester, _bar([]), width: width);
      expect(tester.takeException(), isNull);
      final approve = tester.getRect(find.text('Approve'));
      final deny = tester.getRect(find.text('Deny'));
      final bar = tester.getRect(find.byType(ApprovalBar));
      expect(deny.right, lessThanOrEqualTo(bar.right));
      expect(deny.top, approve.top);
    });
  }

  testWidgets('narrow, the actions go under the request, right-aligned', (
    tester,
  ) async {
    await pumpComposer(tester, _bar([]), width: 500);
    final bar = tester.getRect(find.byType(ApprovalBar));
    final approve = tester.getRect(find.text('Approve'));
    final deny = tester.getRect(find.text('Deny'));
    final pill = tester.getRect(find.text('Needs approval'));
    expect(approve.top, greaterThan(pill.bottom));
    expect(deny.right, lessThan(bar.right));
    expect(deny.right, greaterThan(bar.right - 24));
  });

  testWidgets('wide, the actions sit on the request row', (tester) async {
    await pumpComposer(tester, _bar([]), width: 1000);
    final approve = tester.getRect(find.text('Approve'));
    final pill = tester.getRect(find.text('Needs approval'));
    expect(approve.top, lessThan(pill.bottom + 40));
    expect(approve.left, greaterThan(500));
  });
}
