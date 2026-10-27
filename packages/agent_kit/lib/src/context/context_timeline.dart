// The Compactions tab of the Context pane: events over time, newest first
// (`.evt` in the mockup). Gathering and applying are separate: "Context
// compacted" changed the model's view, "Summary written" and "Chapter closed"
// are the source of an apply and never alter the view by themselves.
// Not exported from the barrel.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

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
        const SizedBox(height: 8),
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
        if (eps.isEmpty)
          return 'Replaced messages ${seqRange(event.firstSeq, event.lastSeq)}';
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
    final small = ts(const TypeSpec(13, 18, 500), t.ink, weight: 400);
    final done = t.statusStyle(ChatStatus.done).ink;

    final before = applied ? (e.inputBefore ?? e.tokensBefore) : e.tokensBefore;
    final after = applied ? (e.inputAfter ?? e.tokensAfter) : e.tokensAfter;
    final inputKnown = applied && e.inputBefore != null && e.inputAfter != null;
    final saved = before - after;
    final pct = before <= 0 ? 0 : (saved * 100 / before).round();
    final scale = applied && inputKnown
        ? view.window.toDouble()
        : before * 1.08;
    final saveText = applied
        ? 'saved ${ctxTokens(saved)} · −$pct%'
        : 'would save ${ctxTokens(saved)}';
    final label = applied && inputKnown ? 'Input' : 'Covered';
    final name = applied
        ? ts(t.typeScale.ui, t.ink, weight: 700).copyWith(fontSize: 15)
        : ts(t.typeScale.ui, t.muted, weight: 600);

    return Semantics(
      container: true,
      label:
          '${clockText(e.at)}, $_title. ${why == null ? '' : 'Why: $why. '}'
          '$_what. $label ${ctxTokens(before)} to ${ctxTokens(after)}, '
          '$saveText.',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 44,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  clockText(e.at),
                  textAlign: TextAlign.right,
                  style: monoStyle(const TypeSpec(12, 20, 400), t.faint),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!last)
                    Positioned(
                      left: 6.5,
                      top: 18,
                      bottom: 0,
                      width: 1,
                      child: ColoredBox(color: t.seam),
                    ),
                  Positioned(
                    left: applied ? 2 : 3,
                    top: applied ? 5 : 6,
                    width: applied ? 10 : 8,
                    height: applied ? 10 : 8,
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
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 22),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 12,
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
                                  style: TextStyle(
                                    color: t.ink,
                                    fontWeight: fw(700),
                                  ),
                                ),
                              ],
                            ),
                            style: tabular(small.copyWith(color: t.muted)),
                          ),
                          Text(
                            saveText,
                            style: small.copyWith(
                              color: applied ? done : t.muted,
                              fontWeight: fw(applied ? 600 : 500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: applied ? 420 : 260,
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
      height: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colors.borderSubtle,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f.clamp(0.004, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
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
              const SizedBox(height: 3),
              bar(b, t.ctxSummary),
            ],
          ),
          if (cap != null)
            Positioned.fill(
              top: -2,
              bottom: -2,
              child: Align(
                alignment: Alignment(cap!.clamp(0.0, 1.0) * 2 - 1, 0),
                child: SizedBox(
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.ink,
                      borderRadius: BorderRadius.circular(1),
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
      ..strokeWidth = 1.5;
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
