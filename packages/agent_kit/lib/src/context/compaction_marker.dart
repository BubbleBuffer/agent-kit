// The compaction marker (`.mk` in the mockup): one quiet line in the
// assistant turn at the point a compaction was applied. A fold glyph, a bold
// title, a muted detail, a hairline and a "View" text button. No pill and no
// accent: it is not a request.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import '../transcript/transcript_support.dart';
import 'context_support.dart';

/// The line for [item]. [onView] opens the Context pane on Now; without it
/// the button is left out. Compact widths drop "3 episodes summarized" and
/// the hairline; `41k → 9k` stays.
class CompactionMarker extends StatelessWidget {
  const CompactionMarker(this.item, {super.key, this.onView});

  final CompactionItem item;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final compact = sizeClassOf(context).isCompact;
    final running = item.state == CompactionState.running;
    final failed = item.state == CompactionState.failed;
    final title = running
        ? 'Compacting context…'
        : failed
        ? 'Compaction failed'
        : 'Context compacted';
    final n = item.episodesSummarized;
    final sizes = item.tokensBefore != null && item.tokensAfter != null
        ? '${_k(item.tokensBefore!)} → ${_k(item.tokensAfter!)}'
        : null;
    final parts = running
        ? [?item.detail]
        : failed
        ? [item.detail ?? 'the previous context is unchanged']
        : [
            if (!compact && n != null)
              n == 1 ? '1 episode summarized' : '$n episodes summarized',
            ?sizes,
          ];
    final style = ts(t.typeScale.uiSmall, t.muted, weight: 400);
    final label = [title, ...parts].join(', ');
    final Widget lead = failed
        ? glyphIcon(
            glyphCircleX,
            size: 14,
            color: t.statusStyle(ChatStatus.failed).ink,
          )
        : glyphIcon(glyphFoldVertical, size: 14, color: t.colors.iconSecondary);
    return Semantics(
      container: true,
      liveRegion: running,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (!running) ...[
                SizedBox(width: 18, child: Center(child: lead)),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: running
                    ? StatusMark(
                        ChatStatus.running,
                        label: title,
                        detail: item.detail,
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: title,
                              style: TextStyle(
                                color: failed
                                    ? t.statusStyle(ChatStatus.failed).ink
                                    : t.ink,
                                fontWeight: fw(700),
                              ),
                            ),
                            for (final p in parts) TextSpan(text: ' · $p'),
                          ],
                        ),
                        style: style,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (!compact)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ColoredBox(
                      color: t.colors.borderSubtle,
                      child: const SizedBox(height: 1),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (onView != null && !running)
                KitTextButton('View', color: t.ink, onTap: onView),
            ],
          ),
        ),
      ),
    );
  }

  static String _k(int n) => n >= 1000 ? '${(n / 1000).round()}k' : '$n';
}
