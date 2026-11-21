// The Compactions tab of the Context pane: events over time, newest first
// (`.evt` in the mockup). Gathering and applying are separate: "Context
// compacted" changed the model's view, "Summary written" and "Chapter closed"
// are the source of an apply and never alter the view by themselves.
// Not exported from the barrel.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/kit_tokens.dart';
import '../theme/theme.dart';
import '../transcript/transcript_support.dart';
import 'context_parts.dart';
import 'context_support.dart';

/// The timeline.
class ContextTimeline extends StatelessWidget {
  const ContextTimeline({
    super.key,
    required this.view,
    required this.details,
    required this.onGoSummary,
  });

  final ContextView view;
  final ContextDetails details;
  final ValueChanged<String> onGoSummary;

  @override
  Widget build(BuildContext context) {
    final events = [...details.events]..sort((a, b) => b.at.compareTo(a.at));
    if (events.isEmpty) {
      return const CxNote('Nothing has been compacted in this chat yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CxNote(
          'Summaries are written in the background. The model only sees them '
          'once a compaction is applied.',
        ),
        const Gap(Space.sm),
        for (var i = 0; i < events.length; i++)
          _EventRow(
            events[i],
            view: view,
            details: details,
            last: i == events.length - 1,
            onGoSummary: onGoSummary,
          ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(
    this.event, {
    required this.view,
    required this.details,
    required this.last,
    required this.onGoSummary,
  });

  final ContextEvent event;
  final ContextView view;
  final ContextDetails details;
  final bool last;
  final ValueChanged<String> onGoSummary;

  String get _title {
    switch (event.kind) {
      case ContextEventKind.applied:
        return 'Context compacted';
      case ContextEventKind.episodeWritten:
        final e = event.episodeIds.isEmpty
            ? null
            : details.episode(event.episodeIds.first);
        return e == null
            ? 'Summary written'
            : 'Summary written · Episode ${e.ordinal}';
      case ContextEventKind.chapterClosed:
        final s = event.summaryId == null
            ? null
            : details.summary(event.summaryId!);
        final c = s?.chapterId == null ? null : details.chapter(s!.chapterId!);
        return c == null ? 'Chapter closed' : 'Chapter ${c.ordinal} closed';
    }
  }

  String get _what {
    final range = 'Messages ${seqRange(event.firstSeq, event.lastSeq)}';
    switch (event.kind) {
      case ContextEventKind.applied:
        final eps = [for (final id in event.episodeIds) ?details.episode(id)];
        if (eps.isEmpty) {
          return 'Replaced messages ${seqRange(event.firstSeq, event.lastSeq)}';
        }
        final tags = eps.length == 1
            ? episodeTag(eps.first)
            : '${episodeTag(eps.first)}–${episodeTag(eps.last)}';
        return 'Replaced ${eps.length == 1 ? '1 episode' : '${eps.length} episodes'} '
            '($tags), messages ${seqRange(event.firstSeq, event.lastSeq)}';
      case ContextEventKind.episodeWritten:
        final pending = event.episodeIds.any(view.pendingEpisodeIds.contains);
        return pending ? '$range. Not in view yet.' : range;
      case ContextEventKind.chapterClosed:
        final eps = [for (final id in event.episodeIds) ?details.episode(id)];
        if (eps.isEmpty) return range;
        final tags = eps.length == 1
            ? episodeTag(eps.first)
            : '${episodeTag(eps.first)}–${episodeTag(eps.last)}';
        return 'Episodes $tags, ${range.toLowerCase()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final e = event;
    final applied = e.kind == ContextEventKind.applied;
    final ready =
        e.kind == ContextEventKind.episodeWritten &&
        e.episodeIds.any(view.pendingEpisodeIds.contains);
    final why = triggerWhy(e);
    final small = ts(t.typeScale.ui, t.ink, weight: Weight.regular);
    final done = t.statusStyle(ChatStatus.done).ink;

    final before = applied ? (e.inputBefore ?? e.tokensBefore) : e.tokensBefore;
    final after = applied ? (e.inputAfter ?? e.tokensAfter) : e.tokensAfter;
    // A host may not record the sizes; then the row shows no sizes or bars.
    final sized = before != null && after != null;
    final inputKnown =
        applied &&
        e.inputBefore != null &&
        e.inputAfter != null &&
        view.window != null;
    final saved = sized ? before - after : 0;
    final pct = !sized || before <= 0 ? 0 : (saved * 100 / before).round();
    final scale = inputKnown ? view.window!.toDouble() : (before ?? 1) * 1.08;
    final saveText = applied
        ? 'saved ${ctxTokens(saved)} · −$pct%'
        : 'would save ${ctxTokens(saved)}';
    final label = applied && inputKnown ? 'Input' : 'Covered';
    final name = applied
        ? ts(t.typeScale.title, t.ink, weight: Weight.strong)
        : ts(t.typeScale.ui, t.muted, weight: Weight.strong);
    final dot = applied ? KitTimeline.dotApplied : Sizes.dot;

    return Semantics(
      container: true,
      label:
          '${clockText(e.at)}, $_title. ${why == null ? '' : 'Why: $why. '}'
          '$_what.'
          '${sized ? ' $label ${ctxTokens(before)} to ${ctxTokens(after)}, $saveText.' : ''}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: KitTimeline.timeColumn,
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xxs),
                child: Text(
                  clockText(e.at),
                  textAlign: TextAlign.right,
                  style: monoStyle(t.typeScale.codeSmall, t.faint),
                ),
              ),
            ),
            const Gap(Space.sm),
            SizedBox(
              width: KitTimeline.rail,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!last)
                    Positioned(
                      left: (KitTimeline.rail - Stroke.hair) / 2,
                      top: KitTimeline.lineTop,
                      bottom: 0,
                      width: Stroke.hair,
                      child: ColoredBox(color: t.seam),
                    ),
                  Positioned(
                    left: (KitTimeline.rail - dot) / 2,
                    top: KitTimeline.dotCenter - dot / 2,
                    width: dot,
                    height: dot,
                    child: CustomPaint(
                      painter: _DotPainter(
                        filled: applied,
                        dashed: ready,
                        color: applied ? t.ink : t.threadStrong,
                        fill: t.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(Space.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: ControlSize.xs.height,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(_title, style: name)),
                          if (e.summaryId != null)
                            KitTextButton(
                              'Summary',
                              glyph: glyphLayers,
                              color: t.ink,
                              onTap: () => onGoSummary(e.summaryId!),
                            ),
                        ],
                      ),
                    ),
                    if (why != null) Text('Why: $why', style: small),
                    Text(_what, style: small.copyWith(color: t.muted)),
                    if (sized)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xxs),
                        child: Wrap(
                          spacing: Space.md,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$label ',
                                    style: TextStyle(color: t.faint),
                                  ),
                                  TextSpan(text: '${ctxTokens(before)} → '),
                                  TextSpan(
                                    text: ctxTokens(after),
                                    style: tabular(
                                      ts(
                                        t.typeScale.ui,
                                        t.ink,
                                        weight: Weight.strong,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              style: tabular(small.copyWith(color: t.muted)),
                            ),
                            Text(
                              saveText,
                              style: ts(
                                t.typeScale.ui,
                                applied ? done : t.muted,
                                weight: applied ? Weight.strong : Weight.strong,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (sized)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xxs),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: applied
                                ? KitTimeline.barsApplied
                                : KitTimeline.barsPending,
                          ),
                          child: _EventBars(
                            a: before / scale,
                            b: after / scale,
                            cap: applied && inputKnown && view.applyCap > 0
                                ? view.applyCap / scale
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventBars extends StatelessWidget {
  const _EventBars({required this.a, required this.b, this.cap});

  final double a, b;
  final double? cap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    Widget bar(double f, Color c) => SizedBox(
      height: KitSizes.shareBar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colors.borderSubtle,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f.clamp(0.004, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bar(a, t.ctxOpening),
              const Gap(Space.xxs),
              bar(b, t.ctxSummary),
            ],
          ),
          if (cap != null)
            Positioned.fill(
              top: -Space.hair,
              bottom: -Space.hair,
              child: Align(
                alignment: Alignment(cap!.clamp(0.0, 1.0) * 2 - 1, 0),
                child: SizedBox(
                  width: Stroke.bold,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.ink,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter({
    required this.filled,
    required this.dashed,
    required this.color,
    required this.fill,
  });

  final bool filled, dashed;
  final Color color, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (filled) {
      canvas.drawCircle(c, r, Paint()..color = color);
      return;
    }
    canvas.drawCircle(c, r - .75, Paint()..color = fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = Stroke.regular;
    if (!dashed) {
      canvas.drawCircle(c, r - .75, stroke);
      return;
    }
    final oval = Rect.fromCircle(center: c, radius: r - .75);
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(oval, i * 1.0472, .52, false, stroke);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.filled != filled ||
      old.dashed != dashed ||
      old.color != color ||
      old.fill != fill;
}
