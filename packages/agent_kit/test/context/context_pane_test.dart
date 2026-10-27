// ContextPane: the tabs' keyboard model, the summary detail (beside the list
// when wide, replacing it when narrow, Esc back), forward and reverse links,
// and optional fields that stay out of the way.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/context/context_history.dart';
import 'package:agent_kit/src/context/context_now.dart';
import 'package:agent_kit/src/context/context_timeline.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

final _now = DateTime.utc(2025, 12, 29, 14);

Future<HistoryPage> _history(int first, int last) async => HistoryPage(
  firstSeq: first,
  lastSeq: last,
  messages: [
    for (var s = first; s <= last; s++)
      HistoryMessage(seq: s, role: HistoryRole.agent, preview: 'message $s'),
  ],
);

Widget _pane({
  ContextView? view,
  ContextDetails? details,
  ContextTab tab = ContextTab.now,
  ContextPaneController? controller,
}) {
  final d = details ?? quotaContextDetails();
  return ContextPane(
    view: view ?? quotaContextView(),
    details: d,
    loadHistory: _history,
    loadSummary: (id) async => d.summary(id)!,
    now: _now,
    initialTab: tab,
    controller: controller,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  const wide = Size(900, 800);
  const narrow = Size(420, 800);

  group('tabs', () {
    testWidgets('arrow keys, Home and End move and select', (tester) async {
      await pumpKit(tester, _pane(), size: wide);
      await _settle(tester);
      expect(find.byType(ContextNow), findsOneWidget);

      await tester.tap(find.text('Now'));
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.byType(ContextHistory), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.byType(ContextTimeline), findsOneWidget);

      // Wraps around.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.byType(ContextNow), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await _settle(tester);
      expect(find.byType(ContextTimeline), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await _settle(tester);
      expect(find.byType(ContextNow), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(find.byType(ContextTimeline), findsOneWidget);
    });
  });

  group('summary detail', () {
    testWidgets('wide: the detail sits beside the list', (tester) async {
      await pumpKit(tester, _pane(), size: wide);
      await _settle(tester);
      await tester.tap(find.text('Draft the stale-figure fix').first);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsOneWidget);
      // The list is still there.
      expect(find.text('Compacted memory'), findsOneWidget);
    });

    testWidgets('narrow: opens over the list, Back and Esc return', (
      tester,
    ) async {
      await pumpKit(tester, _pane(), size: narrow);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsNothing);

      await tester.tap(find.text('Draft the stale-figure fix').first);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsOneWidget);
      expect(find.text('Compacted memory'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Back to the list'));
      await _settle(tester);
      expect(find.byType(ContextDetail), findsNothing);
      expect(find.text('Compacted memory'), findsOneWidget);

      await tester.tap(find.text('Draft the stale-figure fix').first);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsNothing);
    });
  });

  group('links', () {
    testWidgets('forward: a timeline event opens its summary on Now', (
      tester,
    ) async {
      await pumpKit(tester, _pane(tab: ContextTab.compactions), size: wide);
      await _settle(tester);
      expect(find.byType(ContextTimeline), findsOneWidget);

      await tester.tap(find.text('Summary').first);
      await _settle(tester);
      expect(find.byType(ContextNow), findsOneWidget);
      expect(find.byType(ContextDetail), findsOneWidget);
    });

    testWidgets('reverse: the detail shows the original messages', (
      tester,
    ) async {
      await pumpKit(tester, _pane(), size: wide);
      await _settle(tester);
      await tester.tap(find.text('Draft the stale-figure fix').first);
      await _settle(tester);

      await tester.tap(find.text('Show the original messages'));
      await _settle(tester);
      expect(find.byType(ContextHistory), findsOneWidget);
      expect(find.byType(ContextNow), findsNothing);
    });

    testWidgets('the controller brings Now forward on a summary', (
      tester,
    ) async {
      final controller = ContextPaneController();
      await pumpKit(
        tester,
        _pane(tab: ContextTab.compactions, controller: controller),
        size: wide,
      );
      await _settle(tester);
      controller.showNow(summaryId: 'sum-e3');
      await _settle(tester);
      expect(find.byType(ContextNow), findsOneWidget);
      expect(find.byType(ContextDetail), findsOneWidget);
    });
  });

  group('optional fields', () {
    testWidgets('a view without block sizes shows no token figures', (
      tester,
    ) async {
      final view = ContextView(
        window: 128000,
        applyCap: 84000,
        responseReserve: 44000,
        blocks: const [
          ContextBlock(kind: ContextBlockKind.opening),
          ContextBlock(kind: ContextBlockKind.rawSuffix),
        ],
      );
      await pumpKit(tester, ContextMeterBar(view: view), size: wide);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('a summary without a model leaves the model out', (
      tester,
    ) async {
      final base = quotaContextDetails();
      final s = base.summary('sum-e4')!;
      final bare = ContextSummary(
        id: s.id,
        kind: s.kind,
        title: s.title,
        text: s.text,
        firstSeq: s.firstSeq,
        lastSeq: s.lastSeq,
        messageCount: s.messageCount,
        episodeIds: s.episodeIds,
        chapterId: s.chapterId,
        sourceTokens: s.sourceTokens,
        summaryTokens: s.summaryTokens,
        createdAt: s.createdAt,
      );
      final details = ContextDetails(
        chapters: base.chapters,
        episodes: base.episodes,
        summaries: [
          for (final x in base.summaries)
            if (x.id == bare.id) bare else x,
        ],
        events: base.events,
      );
      await pumpKit(tester, _pane(details: details), size: wide);
      await _settle(tester);
      await tester.tap(find.text('Draft the stale-figure fix').first);
      await _settle(tester);
      expect(find.byType(ContextDetail), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without details the pane still builds', (tester) async {
      await pumpKit(
        tester,
        ContextPane(view: quotaContextView(), now: _now),
        size: wide,
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
