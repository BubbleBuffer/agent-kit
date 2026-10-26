// AgentWorkbench: the rail lists the backend's chats, a row opens its chat,
// the rail hides and shows, the workspace toggles, and the crew shows as a
// ledger or a strip by the width it is given.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workspace/sample_layout.dart';
import 'compositions_harness.dart';

Widget _bench(
  ScriptedBackend backend,
  ManualClock clock, {
  WorkspaceController? workspace,
  bool workspaceShown = false,
}) => AgentWorkbench(
  backend: backend,
  initialChatId: quotaChatId,
  workspaceName: 'BubblePaw-base',
  initials: 'BC',
  now: clock.now(),
  modelUsage: const [ModelUsage('deepseek-v4.1-flash', 120000)],
  workspaceController: workspace,
  workspaceKinds: kinds,
  workspacePaneBuilder: workspace == null
      ? null
      : (context, tab) => Center(child: Text('pane ${tab.id}')),
  initialWorkspaceShown: workspaceShown,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('the rail lists the backend chats and a row opens its chat', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _bench(s.backend, s.clock), width: 1200, height: 800);
    await _settle(tester);
    expect(find.byKey(const ValueKey('rail-row-$quotaChatId')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-row-idle')), findsOneWidget);
    expect(find.text('Needs approval'), findsOneWidget);

    // ignore: avoid_print
    print('DIAG ${tester.getRect(find.byType(ListView).first)} ${tester.getRect(find.byKey(const ValueKey('rail-row-idle')))} ${find.byType(ListView).evaluate().length}');
    await tester.tap(find.byKey(const ValueKey('rail-row-idle')));
    await _settle(tester);
    expect(find.text('Needs approval'), findsNothing);
    // The open chat's title is in the header as well as in the rail.
    expect(find.text('Idle chat'), findsNWidgets(2));
  });

  testWidgets('the rail hides and shows', (tester) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _bench(s.backend, s.clock), width: 1200, height: 800);
    await _settle(tester);
    expect(find.byKey(const ValueKey('rail-row-idle')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rail-hide')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('rail-row-idle')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rail-show')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('rail-row-idle')), findsOneWidget);
  });

  testWidgets('new chat creates one through the backend and opens it', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _bench(s.backend, s.clock), width: 1200, height: 800);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('rail-new-chat')));
    await _settle(tester);
    expect(commandNames(s.backend), contains('createChat'));
    expect(find.text('New chat'), findsWidgets);
  });

  group('crew', () {
    testWidgets('expanded, with no workspace: a ledger, no strip', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      await pumpApp(
        tester,
        _bench(s.backend, s.clock),
        width: 1440,
        height: 900,
      );
      await _settle(tester);
      expect(find.byType(CrewLedger), findsOneWidget);
      expect(find.byType(CrewStrip), findsNothing);
      expect(find.byType(UsageByModel), findsOneWidget);
    });

    testWidgets('medium: a strip, no ledger', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(
        tester,
        _bench(s.backend, s.clock),
        width: 820,
        height: 800,
      );
      await _settle(tester);
      expect(find.byType(CrewLedger), findsNothing);
      expect(find.byType(CrewStrip), findsOneWidget);
    });
  });

  group('workspace', () {
    testWidgets('the header toggle opens it beside the chat; the ledger folds '
        'into the strip', (tester) async {
      final s = await playedBackend(tester);
      final ws = WorkspaceController(sampleLayout());
      await pumpApp(
        tester,
        _bench(s.backend, s.clock, workspace: ws),
        width: 1600,
        height: 900,
      );
      await _settle(tester);
      expect(find.byType(AgentWorkspace), findsNothing);
      expect(find.byType(CrewLedger), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('header-workspace')));
      await _settle(tester);
      expect(find.byType(AgentWorkspace), findsOneWidget);
      expect(find.byType(CrewLedger), findsNothing);
      expect(find.byType(CrewStrip), findsOneWidget);
      // The chat takes 44% of the area beside the rail, at most 584 px.
      final chat = tester.getSize(find.byType(AgentChatPane));
      expect(chat.width, closeTo(584 - 24, 1));

      await tester.tap(find.byKey(const ValueKey('header-workspace')));
      await _settle(tester);
      expect(find.byType(AgentWorkspace), findsNothing);
      expect(find.byType(CrewLedger), findsOneWidget);
    });

    testWidgets('compact: a sheet over the chat', (tester) async {
      final s = await playedBackend(tester);
      final ws = WorkspaceController(sampleLayout());
      await pumpApp(
        tester,
        _bench(s.backend, s.clock, workspace: ws),
        width: 390,
        height: 800,
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('header-workspace')));
      await _settle(tester);
      expect(find.byType(AgentWorkspace), findsOneWidget);
      expect(find.byType(AgentChatPane), findsOneWidget);
    });
  });
}
