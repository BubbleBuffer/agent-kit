// The Context pane's meter (`.cx-meter` in the mockup): "48.6k of 128k
// tokens", the percent, a bar stacked from the fixed opening, the compacted
// memory and the live messages with a tick at the apply cap, and a legend
// that names every segment with its size, so colour never carries it alone.
//
// It is the header's `ContextMeter` grown up: the same fill idea, with
// segments. A figure the host did not record is left out, never shown as 0.

import 'package:agent_kit_core/agent_kit_core.dart' show ContextView;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'context_support.dart';

/// One coloured part of the bar.
@immutable
class ContextSegment {
  const ContextSegment(this.label, this.tokens, this.color);

  /// `Fixed`, `Compacted`, `Live`.
  final String label;
  final int tokens;
  final Color color;
}

/// The segments of [view], in served order, for the theme's roles. A group
/// whose block sizes are unknown is left out.
List<ContextSegment> contextSegments(BbTheme theme, ContextView view) => [
  if (view.openingTokens case final n? when n > 0)
    ContextSegment('Fixed', n, theme.ctxOpening),
  if (view.memoryTokens case final n? when n > 0)
    ContextSegment('Compacted', n, theme.ctxSummary),
  if (view.liveTokens case final n? when n > 0)
    ContextSegment('Live', n, theme.ctxLive),
];

/// The meter for [view].
class ContextMeterBar extends StatelessWidget {
  const ContextMeterBar({super.key, required this.view});

  final ContextView view;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final segments = contextSegments(t, view);
    final total = view.totalTokens;
    final window = view.window;
    final percent = total == null || window <= 0
        ? null
        : (total * 100 / window).round();
    final cap = view.applyCap;
    final known = segments.fold<int>(0, (a, s) => a + s.tokens);
    final label = StringBuffer();
    if (total != null) label.write('${ctxTokens(total)} of ');
    label.write('${ctxLimit(window)} tokens');
    for (final s in segments) {
      label.write(', ${s.label.toLowerCase()} ${ctxTokens(s.tokens)}');
    }
    if (cap > 0) label.write('. Compaction applies near ${ctxLimit(cap)}.');

    final head = ts(t.typeScale.ui, t.muted, weight: 400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (total != null) ...[
              Text(
                ctxTokens(total),
                style: tabular(ts(const TypeSpec(18, 22, 700), t.ink)),
              ),
              const SizedBox(width: 6),
            ],
            Text('${total != null ? 'of ' : ''}${ctxLimit(window)} tokens',
                style: head),
            const Spacer(),
            if (percent != null)
              Text(
                '$percent%',
                style: tabular(ts(t.typeScale.uiSmall, t.faint)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          container: true,
          image: true,
          label: label.toString(),
          excludeSemantics: true,
          child: SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final scale = window <= 0 ? 1.0 : w / window;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.seam,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: known * scale,
                            child: Row(
                              children: [
                                for (var i = 0; i < segments.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 1),
                                  Expanded(
                                    flex: segments[i].tokens,
                                    child: ColoredBox(
                                      color: segments[i].color,
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (cap > 0 && cap <= window)
                      Positioned(
                        left: cap * scale - 1,
                        top: -3,
                        bottom: -3,
                        width: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: t.ink,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in segments) _Legend(s),
            if (cap > 0)
              Text(
                'Compacts near ${ctxLimit(cap)}',
                key: const ValueKey('context-cap-label'),
                style: ts(t.typeScale.uiSmall, t.faint, weight: 400),
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.segment);

  final ContextSegment segment;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: segment.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${segment.label} ${ctxTokens(segment.tokens)}',
          style: ts(t.typeScale.uiSmall, t.muted, weight: 400),
        ),
      ],
    );
  }
}
