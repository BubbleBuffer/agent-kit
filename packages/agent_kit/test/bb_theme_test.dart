// BbTheme's roles carry the approved mockup's values (theme.css, NOTES.md).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('light roles are the mockup token mapping', () {
    final t = BbTheme.light();
    expect(t.canvas, const Color(0xFFECE6DB));
    expect(t.surface, const Color(0xFFFFFAF1));
    expect(t.surface2, const Color(0xFFF3EFE7));
    expect(t.ink, const Color(0xFF282A2F));
    expect(t.muted, const Color(0xFF625C55));
    expect(t.seam, const Color(0xFFE4DCCF));
    expect(t.accent, const Color(0xFFDE945F));
    expect(t.constructive, const Color(0xFFCAD8CD));
    expect(t.information, const Color(0xFFCBD5DF));
    expect(t.attention, const Color(0xFFF0D29C));
    expect(t.danger, const Color(0xFFE5B1AA));
    expect(t.constructiveInk, const Color(0xFF397748));
    expect(t.dangerInk, const Color(0xFFAD4B4B));
    expect(t.attentionInk, const Color(0xFF874016));
    // The light rail is built from light tokens.
    expect(t.rail, const Color(0xFFF3EFE7));
  });

  test('dark roles are the mockup token mapping', () {
    final t = BbTheme.dark();
    expect(t.canvas, const Color(0xFF222428));
    expect(t.surface, const Color(0xFF30333A));
    expect(t.ink, const Color(0xFFF3EFE7));
    expect(t.accent, const Color(0xFFF0A064));
    expect(t.attentionInk, const Color(0xFFF0D29C));
    expect(t.constructiveInk, const Color(0xFF93BD9B));
    expect(t.dangerInk, const Color(0xFFE0A3A3));
    expect(t.rail, const Color(0xFF141618));
    expect(t.railLine, const Color(0xFF2B2E33));
  });

  test('status roles follow the status table', () {
    final t = BbTheme.light();
    final needs = t.statusStyle(ChatStatus.needsYou);
    expect(needs.fill, t.attention);
    expect(needs.ink, t.attentionInk);
    expect(needs.mark, t.accent);
    expect(needs.line, isNotNull);
    expect(t.statusStyle(ChatStatus.running).mark, t.ink);
    expect(t.statusStyle(ChatStatus.running).ink, t.muted);
    expect(t.statusStyle(ChatStatus.failed).ink, t.dangerInk);
    expect(t.statusStyle(ChatStatus.done).ink, t.constructiveInk);
    expect(t.statusStyle(ChatStatus.idle).ink, t.muted);
    for (final s in ChatStatus.values) {
      expect(t.status.containsKey(s), isTrue, reason: '$s has a style');
      // Only "needs you" fills a pill.
      expect(t.statusStyle(s).fill == null, s != ChatStatus.needsYou);
    }
  });

  test('size thresholds and pane tokens match theme.css', () {
    final t = BbTheme.light();
    expect(t.sizeMedium, 600);
    expect(t.sizeExpanded, 1000);
    expect(t.layout.paneMinWidth, 200);
    expect(t.layout.paneMinHeight, 120);
    expect(t.layout.edgeTab, 28);
    expect(t.motion.breathe, const Duration(milliseconds: 2400));
  });

  testWidgets('BbThemeScope gives BbTheme and the bb_ui AppTheme', (
    tester,
  ) async {
    late BbTheme theme;
    await pumpKit(
      tester,
      Builder(
        builder: (context) {
          theme = context.bb;
          return const SizedBox();
        },
      ),
      brightness: Brightness.dark,
    );
    expect(theme.brightness, Brightness.dark);
    expect(theme.canvas, BbTheme.dark().canvas);
  });
}
