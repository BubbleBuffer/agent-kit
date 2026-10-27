// Golden screenshots of the Context pane at 680 and 420 px (the Now tab with
// and without a summary open, History, Compactions) and the compaction marker
// states, light and dark. `flutter test --tags golden --update-goldens` (or
// the CI dispatch) re-renders them.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chrome/chrome_harness.dart';

final _now = DateTime.utc(2025, 12, 29, 14);

Future<HistoryPage> _history(int first, int last) async => HistoryPage(
  firstSeq: first,
  lastSeq: last,
  messages: [
    for (var s = first; s <= last; s++)
      HistoryMessage(
        seq: s,
        role: s % 7 == 0
            ? HistoryRole.user
            : s % 3 == 0
            ? HistoryRole.tool
            : HistoryRole.agent,
        preview: s % 3 == 0
            ? 'read usage/mod.rs'
            : 'Keeping the last figure on disconnect, behind an Option.',
        tokens: 40 + s,
      ),
  ],
);

Widget _pane({ContextTab tab = ContextTab.now, String? summary}) {
  final d = quotaContextDetails();
  return Builder(
    builder: (context) => ColoredBox(
      color: context.bb.surface,
      child: ContextPane(
        view: quotaContextView(),
        details: d,
        loadHistory: _history,
        loadSummary: (id) async => d.summary(id)!,
        now: _now,
        initialTab: tab,
        initialSummaryId: summary,
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;
    for (final width in [680, 420, 390]) {
      final size = Size(width.toDouble(), 900);
      // 390 is the phone sheet: the list, and an episode summary open as in
      // the mockup's compact detail shot.
      final cases = <String, Widget>{
        'now': _pane(),
        'summary': _pane(summary: width == 390 ? 'sum-e3' : 'sum-ch1'),
        if (width != 390) ...{
          'history': _pane(tab: ContextTab.history),
          'compactions': _pane(tab: ContextTab.compactions),
        },
      };
      for (final entry in cases.entries) {
        testWidgets('${entry.key}, $width, $name', (tester) async {
          await pumpChrome(
            tester,
            entry.value,
            brightness: brightness,
            size: size,
          );
          await _settle(tester);
          await expectLater(
            find.byType(ContextPane),
            matchesGoldenFile(
              '../goldens/context_${entry.key}_${width}_$name.png',
            ),
          );
        });
      }
    }
    for (final width in [1000, 390]) {
      testWidgets('marker states, $width, $name', (tester) async {
        await pumpChrome(
          tester,
          Align(
            alignment: Alignment.topCenter,
            child: Builder(
              builder: (context) => ColoredBox(
                color: context.bb.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CompactionMarker(
                      const CompactionItem(
                        id: 'a',
                        episodesSummarized: 3,
                        tokensBefore: 41000,
                        tokensAfter: 9000,
                      ),
                      onView: () {},
                    ),
                    CompactionMarker(
                      const CompactionItem(
                        id: 'b',
                        state: CompactionState.running,
                        detail: 'summarizing episode 4 · 24k',
                      ),
                      onView: () {},
                    ),
                    CompactionMarker(
                      const CompactionItem(
                        id: 'c',
                        state: CompactionState.failed,
                      ),
                      onView: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
          brightness: brightness,
          size: Size(width.toDouble(), 160),
        );
        await _settle(tester);
        await expectLater(
          find.byType(Column).first,
          matchesGoldenFile('../goldens/context_marker_${width}_$name.png'),
        );
      });
    }
  }
}
