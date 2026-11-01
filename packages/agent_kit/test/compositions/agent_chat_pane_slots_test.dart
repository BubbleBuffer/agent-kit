// AgentChatPane slots: the header can be turned off or replaced, the
// transcript can be drawn by the host, the metrics move the dock, and a
// controller the host owns survives the pane.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compositions_harness.dart';

Widget _pane(
  ScriptedBackend backend,
  ManualClock clock, {
  bool showHeader = true,
  Widget Function(BuildContext, ChatSnapshot)? headerBuilder,
  Widget Function(BuildContext, ChatSnapshot, PaneTranscriptSlot)?
  transcriptBuilder,
  PaneMetrics metrics = const PaneMetrics(),
  TranscriptController? controller,
}) => AgentChatPane(
  backend: backend,
  chatId: quotaChatId,
  now: clock.now(),
  showHeader: showHeader,
  headerBuilder: headerBuilder,
  transcriptBuilder: transcriptBuilder,
  metrics: metrics,
  transcriptController: controller,
);

void main() {
  testWidgets('the header is drawn by default and can be turned off', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _pane(s.backend, s.clock));
    expect(find.byType(ChatHeader), findsOneWidget);

    await pumpApp(tester, _pane(s.backend, s.clock, showHeader: false));
    expect(find.byType(ChatHeader), findsNothing);
  });

  testWidgets('headerBuilder replaces the header and gets the snapshot', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(
      tester,
      _pane(
        s.backend,
        s.clock,
        headerBuilder: (context, snap) =>
            Text('host header ${snap.title}', textDirection: TextDirection.ltr),
      ),
    );
    expect(find.textContaining('host header'), findsOneWidget);
    expect(find.byType(ChatHeader), findsNothing);
  });

  testWidgets('transcriptBuilder replaces the list and gets the wiring', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    PaneTranscriptSlot? seen;
    await pumpApp(
      tester,
      _pane(
        s.backend,
        s.clock,
        transcriptBuilder: (context, snap, slot) {
          seen = slot;
          return const Text('host transcript', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(find.text('host transcript'), findsOneWidget);
    expect(find.byType(TranscriptList), findsNothing);
    expect(seen!.contentWidth, 720);
    expect(seen!.layout, TurnLayout.chronological);
    // The dock stays the pane's.
    expect(find.byType(AgentComposer), findsOneWidget);
  });

  testWidgets('metrics reach the list and the dock', (tester) async {
    final s = await playedBackend(tester);
    await pumpApp(
      tester,
      _pane(
        s.backend,
        s.clock,
        metrics: const PaneMetrics(
          gutter: 12,
          rowGap: 20,
          dockGutter: 32,
          dockPadding: EdgeInsets.zero,
        ),
      ),
    );
    final list = tester.widget<TranscriptList>(find.byType(TranscriptList));
    expect(list.gutter, 12);
    expect(list.rowGap, 20);
    final dock = tester.getSize(find.byType(AgentComposer));
    expect(dock.width, lessThanOrEqualTo(720));
  });

  testWidgets('a host-owned controller is not disposed with the pane', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    final controller = TranscriptController();
    await pumpApp(tester, _pane(s.backend, s.clock, controller: controller));
    await tester.pumpWidget(const SizedBox());
    // Still usable: adding a listener would throw if it were disposed.
    controller.addListener(() {});
    controller.dispose();
  });
}
