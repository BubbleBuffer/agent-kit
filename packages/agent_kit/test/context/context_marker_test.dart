// The compaction marker (running, done, failed), its View button, and the
// way the header meter and the marker open the Context pane in a workbench.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compositions/compositions_harness.dart';
import '../harness.dart';
import '../workspace/sample_layout.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('CompactionMarker', () {
    testWidgets('done: title, figures and View', (tester) async {
      var viewed = 0;
      await pumpKit(
        tester,
        CompactionMarker(
          const CompactionItem(
            id: 'm',
            episodesSummarized: 3,
            tokensBefore: 41000,
            tokensAfter: 9000,
          ),
          onView: () => viewed++,
        ),
        size: const Size(700, 100),
      );
      expect(find.textContaining('Context compacted'), findsOneWidget);
      expect(find.textContaining('41k → 9k'), findsOneWidget);
      await tester.tap(find.text('View'));
      expect(viewed, 1);
    });

    testWidgets('running: no View, shows the detail', (tester) async {
      await pumpKit(
        tester,
        CompactionMarker(
          const CompactionItem(
            id: 'm',
            state: CompactionState.running,
            detail: 'summarizing episode 4 · 24k',
          ),
          onView: () {},
        ),
        size: const Size(700, 100),
      );
      expect(find.text('View'), findsNothing);
      expect(find.textContaining('Compacting context'), findsOneWidget);
    });

    testWidgets('failed: says so and that nothing changed', (tester) async {
      await pumpKit(
        tester,
        const CompactionMarker(
          CompactionItem(id: 'm', state: CompactionState.failed),
        ),
        size: const Size(700, 100),
      );
      expect(find.textContaining('Compaction failed'), findsOneWidget);
      expect(find.textContaining('unchanged'), findsOneWidget);
    });
  });

  group('AgentWorkbench', () {
    testWidgets('the marker\'s View opens the Context pane', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(
        tester,
        AgentWorkbench(
          backend: s.backend,
          initialChatId: quotaChatId,
          workspaceName: 'BubblePaw-base',
          initials: 'BC',
          now: s.clock.now(),
          workspaceController: WorkspaceController(sampleLayout()),
          workspaceKinds: kinds,
          workspacePaneBuilder: (context, tab) => Text('pane ${tab.id}'),
        ),
        width: 1400,
        height: 3000,
      );
      await _settle(tester);
      expect(find.text('Compactions'), findsNothing);
      await tester.tap(find.text('View').first);
      await _settle(tester);
      expect(find.text('Compactions'), findsWidgets);
    });

    testWidgets('the header meter opens the Context pane', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(
        tester,
        AgentWorkbench(
          backend: s.backend,
          initialChatId: quotaChatId,
          workspaceName: 'BubblePaw-base',
          initials: 'BC',
          now: s.clock.now(),
          workspaceController: WorkspaceController(sampleLayout()),
          workspaceKinds: kinds,
          workspacePaneBuilder: (context, tab) => Text('pane ${tab.id}'),
        ),
        width: 1400,
        height: 900,
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('header-context')));
      await _settle(tester);
      expect(find.text('Compactions'), findsWidgets);
    });
  });
}
