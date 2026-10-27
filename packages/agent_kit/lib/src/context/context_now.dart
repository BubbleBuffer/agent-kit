// The Now tab of the Context pane: the serving view as a stack of rows in the
// order the model receives them (`.cxr` in the mockup), and the summary
// detail (`.cxd`). Not exported from the barrel.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import '../transcript/markdown.dart';
import '../transcript/transcript_support.dart';
import 'context_parts.dart';
import 'context_support.dart';

/// One row of the stack. A row with [onTap] is a summary and a button
/// (selected when [selected], dashed when its summary is not in the view yet).
class ContextRow extends StatefulWidget {
  const ContextRow({
    super.key,
    required this.glyph,
    required this.name,
    this.sub,
    this.tokens,
    this.from,
    this.onTap,
    this.selected = false,
    this.dashed = false,
    this.flash = false,
    this.flashToken = 0,
  });

  final LucideGlyph glyph;
  final String name;
  final String? sub;

  /// `6.1k`; null when the host does not record the block's size.
  final String? tokens;

  /// `31.5k`, what a summary replaced.
  final String? from;
  final VoidCallback? onTap;
  final bool selected, dashed, flash;
  final int flashToken;

  @override
  State<ContextRow> createState() => _ContextRowState();
}

class _ContextRowState extends State<ContextRow> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final button = widget.onTap != null;
    final radius = t.radii.field;
    final border = widget.dashed
        ? null
        : Border.all(
            color: widget.selected ? t.seam : t.surface.withValues(alpha: 0),
          );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: glyphIcon(
              widget.glyph,
              size: 16,
              color: button ? t.colors.iconPrimary : t.colors.iconSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.name,
                  style: ts(t.typeScale.ui, t.ink, weight: 600),
                ),
                if (widget.sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      widget.sub!,
                      style: ts(t.typeScale.uiSmall, t.muted, weight: 400),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (widget.tokens != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.tokens!,
                  style: tabular(ts(t.typeScale.ui, t.ink, weight: 700)),
                ),
                if (widget.from != null)
                  Text(
                    'from ${widget.from}',
                    style: tabular(ts(t.typeScale.uiSmall, t.faint)),
                  ),
              ],
            ),
          if (button)
            SizedBox(
              width: 18,
              child: Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: _hover || _focused || widget.selected ? 1 : 0,
                  child: glyphIcon(
                    glyphChevronRight,
                    size: 14,
                    color: t.colors.iconTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final box = CustomPaint(
      foregroundPainter: widget.dashed
          ? DashedPainter(color: t.thread, radius: radius)
          : null,
      child: body,
    );
    Widget row = button
        ? Semantics(
            button: true,
            selected: widget.selected,
            label: [
              widget.name,
              if (widget.sub != null) widget.sub!,
              if (widget.tokens != null) '${widget.tokens} tokens',
              if (widget.from != null) 'from ${widget.from}',
            ].join(', '),
            excludeSemantics: true,
            onTap: widget.onTap,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (v) => setState(() => _focused = v),
              child: Hover(
                onTap: widget.onTap,
                borderRadius: radius,
                selected: widget.selected,
                selectedColor: t.colors.bgSelectedBlock,
                hoverBackground: t.hover,
                pressedBackground: t.pressed,
                border: border,
                lift: 0,
                onHoverChanged: (v) => setState(() => _hover = v),
                child: box,
              ),
            ),
          )
        : Semantics(
            container: true,
            label: [
              widget.name,
              if (widget.sub != null) widget.sub!,
              if (widget.tokens != null) '${widget.tokens} tokens',
            ].join(', '),
            excludeSemantics: true,
            child: box,
          );
    row = CxFlash(
      active: widget.flash,
      token: widget.flashToken,
      radius: radius,
      child: row,
    );
    return Padding(padding: const EdgeInsets.only(top: 2), child: row);
  }
}

/// What the model is sent, top to bottom. [selected] is the summary id of the
/// open detail; [keyFor] gives the key of a summary's row so a jump can
/// scroll to it.
class ContextNow extends StatelessWidget {
  const ContextNow({
    super.key,
    required this.view,
    required this.details,
    required this.selected,
    required this.onSelect,
    required this.keyFor,
    required this.flashId,
    required this.flashToken,
  });

  final ContextView view;
  final ContextDetails? details;
  final String? selected;
  final ValueChanged<String> onSelect;
  final GlobalKey Function(String id) keyFor;
  final String? flashId;
  final int flashToken;

  @override
  Widget build(BuildContext context) {
    final opening = view.ofKind(ContextBlockKind.opening).toList();
    final memory = [
      for (final b in view.blocks)
        if (b.kind != ContextBlockKind.opening &&
            b.kind != ContextBlockKind.rawSuffix)
          b,
    ];
    final live = view.ofKind(ContextBlockKind.rawSuffix).toList();
    final pending = <ContextSummary>[];
    final pendingEpisodes = <String, ContextEpisode>{};
    final d = details;
    if (d != null) {
      for (final id in view.pendingEpisodeIds) {
        final ep = d.episode(id);
        final sum = ep?.summaryId == null ? null : d.summary(ep!.summaryId!);
        if (ep != null && sum != null) {
          pending.add(sum);
          pendingEpisodes[sum.id] = ep;
        }
      }
    }
    final memorySource = _sumFrom(memory, d);
    final after = sizeAfterNextCompaction(view, d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CxNote(
          'What the model is sent, top to bottom. Your original messages are '
          'all still stored.',
        ),
        if (opening.isNotEmpty) ...[
          CxGroup(
            'Fixed',
            view.openingTokens == null ? null : ctxTokens(view.openingTokens!),
          ),
          for (final b in opening) _plain(b, 'Sent every time'),
        ],
        if (memory.isNotEmpty) ...[
          CxGroup(
            'Compacted memory',
            view.memoryTokens == null
                ? null
                : memorySource == null
                ? ctxTokens(view.memoryTokens!)
                : '${ctxTokens(view.memoryTokens!)}, from '
                      '${ctxTokens(memorySource)}',
          ),
          for (final b in memory)
            if (b.summaryId != null && d?.summary(b.summaryId!) != null)
              _summaryRow(d!.summary(b.summaryId!)!, d, b)
            else
              _plain(b, _blockLine(b)),
        ],
        if (live.isNotEmpty) ...[
          CxGroup(
            'Live messages',
            view.liveTokens == null ? null : ctxTokens(view.liveTokens!),
          ),
          for (final b in live) _plain(b, _blockLine(b)),
        ],
        if (pending.isNotEmpty) ...[
          CxGroup(
            'Ready, not in view yet',
            'applies near ${ctxLimit(view.applyCap)}',
          ),
          for (final s in pending)
            _summaryRow(s, d!, null, episode: pendingEpisodes[s.id]),
          if (after != null)
            CxNote(
              'After the next compaction the view is about '
              '${ctxTokens(after)}.',
              top: 12,
            ),
        ],
      ],
    );
  }

  int? _sumFrom(List<ContextBlock> memory, ContextDetails? d) {
    if (d == null) return null;
    var total = 0;
    var any = false;
    for (final b in memory) {
      final s = b.summaryId == null ? null : d.summary(b.summaryId!);
      if (s == null) continue;
      total += s.sourceTokens;
      any = true;
    }
    return any ? total : null;
  }

  String? _blockLine(ContextBlock b) {
    final range = b.firstSeq != null && b.lastSeq != null
        ? (b.firstSeq == b.lastSeq
              ? 'message ${b.firstSeq}'
              : 'messages ${seqRange(b.firstSeq!, b.lastSeq!)}')
        : null;
    final count = b.messageCount != null && b.messageCount! > 1
        ? messagesText(b.messageCount!)
        : null;
    final parts = switch (b.kind) {
      ContextBlockKind.memoryIndex => [
        if (details case final d?)
          if (d.chapters.where((c) => c.status == ContextStatus.closed).length
              case final n when n > 0)
            '$n closed chapter${n == 1 ? '' : 's'}, newest first',
      ],
      ContextBlockKind.anchors => ['The first and the latest', ?range],
      ContextBlockKind.rawSuffix => [
        ?(range == null ? null : _cap(range)),
        ?count,
      ],
      _ => [?range],
    };
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _plain(ContextBlock b, String? sub) => ContextRow(
    glyph: switch (b.kind) {
      ContextBlockKind.opening => glyphFileText,
      ContextBlockKind.memoryIndex => glyphListChecks,
      ContextBlockKind.anchors => glyphAtSign,
      ContextBlockKind.rawSuffix => glyphCtxMessage,
      _ => glyphLayers,
    },
    name: blockTitle(b),
    sub: sub,
    tokens: b.tokens == null ? null : ctxTokens(b.tokens!),
  );

  Widget _summaryRow(
    ContextSummary s,
    ContextDetails d,
    ContextBlock? block, {
    ContextEpisode? episode,
  }) {
    final pendingRow = block == null;
    final ep = episode;
    final kind = s.kind == ContextSummaryKind.chapter
        ? 'Chapter ${d.chapter(s.chapterId ?? '')?.ordinal ?? ''} summary'
              .replaceAll('  ', ' ')
        : 'Episode ${ep?.ordinal ?? _episodeOrdinal(s, d) ?? ''} summary'
              .replaceAll('  ', ' ');
    final range = 'messages ${seqRange(s.firstSeq, s.lastSeq)}';
    return KeyedSubtree(
      key: keyFor(s.id),
      child: ContextRow(
        glyph: pendingRow ? glyphHourglass : glyphLayers,
        name: s.title,
        sub: '$kind · $range',
        tokens: ctxTokens(block?.tokens ?? s.summaryTokens),
        from: ctxTokens(s.sourceTokens),
        selected: selected == s.id,
        dashed: pendingRow,
        onTap: () => onSelect(s.id),
        flash: flashId == s.id,
        flashToken: flashToken,
      ),
    );
  }

  int? _episodeOrdinal(ContextSummary s, ContextDetails d) {
    for (final id in s.episodeIds) {
      final e = d.episode(id);
      if (e != null) return e.ordinal;
    }
    return null;
  }
}

/// The detail of one summary (`.cxd`).
class ContextDetail extends StatelessWidget {
  const ContextDetail({
    super.key,
    required this.summary,
    required this.details,
    required this.now,
    required this.renderer,
    required this.loading,
    required this.onGoEpisode,
    this.onBack,
  });

  final ContextSummary summary;
  final ContextDetails details;
  final DateTime now;
  final MarkdownRenderer renderer;

  /// The full text is being loaded.
  final bool loading;

  /// Back to the list (only when the detail replaces it).
  final VoidCallback? onBack;

  /// Open History at this episode.
  final ValueChanged<String> onGoEpisode;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final s = summary;
    final chapter = s.kind == ContextSummaryKind.chapter;
    final episodes = [for (final id in s.episodeIds) ?details.episode(id)];
    final ordinals = episodes.map(episodeTag).join(', ');
    final done = t.statusStyle(ChatStatus.done).ink;
    final fact = ts(t.typeScale.ui, t.ink, weight: 400);
    final label = ts(t.typeScale.uiSmall, t.faint, weight: 400);
    final kindText = s.closed
        ? 'Closed chapter, written once and frozen'
        : s.applied
        ? 'Part of the open chapter'
        : 'Part of the open chapter, applies at the next compaction';
    final facts = <(String, String)>[
      (
        'Covers',
        'Messages ${seqRange(s.firstSeq, s.lastSeq)} · '
            '${messagesText(s.messageCount)}',
      ),
      if (ordinals.isNotEmpty) ('Episodes', ordinals),
      ('Written', [whenText(s.createdAt, now), ?s.model].join(' · ')),
      ('Kind', kindText),
    ];
    final pct = s.sourceTokens <= 0
        ? 0
        : (s.savedTokens * 100 / s.sourceTokens).round();
    final ratio = s.sourceTokens <= 0
        ? 0.0
        : (s.summaryTokens / s.sourceTokens).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _BackButton(onBack!),
                ),
              glyphIcon(glyphLayers, size: 14, color: t.colors.iconSecondary),
              const SizedBox(width: 6),
              Text(
                (chapter ? 'Chapter summary' : 'Episode summary').toUpperCase(),
                style: ts(
                  t.typeScale.uiSmall,
                  t.muted,
                  weight: 700,
                ).copyWith(letterSpacing: .5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              s.title,
              style: ts(
                const TypeSpec(18, 24, 640),
                t.ink,
              ).copyWith(letterSpacing: -.18),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              glyphIcon(
                s.applied ? glyphCheck : glyphHourglass,
                size: 14,
                color: s.applied ? done : t.muted,
              ),
              const SizedBox(width: 6),
              Text(
                s.applied ? "In the model's view" : 'Ready, not in view yet',
                style: ts(t.typeScale.uiSmall, t.muted, weight: 600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (k, v) in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(k, style: label),
                    ),
                  ),
                  Expanded(child: Text(v, style: fact)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: t.radii.field,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TokenBar('Original', s.sourceTokens, 1, t.ctxOpening),
                  const SizedBox(height: 6),
                  _TokenBar('Summary', s.summaryTokens, ratio, t.ctxSummary),
                  const SizedBox(height: 6),
                  Text(
                    'Saves ${ctxTokens(s.savedTokens)} · $pct%',
                    style: tabular(ts(t.typeScale.uiSmall, done, weight: 600)),
                  ),
                ],
              ),
            ),
          ),
          if (s.text.isNotEmpty || loading) ...[
            const _H('Summary'),
            if (s.text.isEmpty)
              Text(
                'Loading the summary…',
                style: ts(t.typeScale.ui, t.faint, weight: 400),
              )
            else
              renderer.build(context, s.text),
            const SizedBox(height: 10),
            Text(
              'Summaries are lossy. The originals are unchanged, and the '
              'agent can search them.',
              style: ts(t.typeScale.uiSmall, t.muted, weight: 400),
            ),
          ],
          if (episodes.isNotEmpty) ...[
            const _H('Replaces'),
            for (final e in episodes)
              _Covered(e, onTap: () => onGoEpisode(e.id)),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: KitTextButton(
                  'Show the original messages',
                  glyph: glyphHistory,
                  color: t.ink,
                  onTap: () => onGoEpisode(episodes.first.id),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: ts(
          t.typeScale.uiSmall,
          t.faint,
          weight: 700,
        ).copyWith(letterSpacing: .5),
      ),
    );
  }
}

class _TokenBar extends StatelessWidget {
  const _TokenBar(this.label, this.tokens, this.fraction, this.color);

  final String label;
  final int tokens;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: ts(t.typeScale.uiSmall, t.muted)),
        ),
        Expanded(
          child: SizedBox(
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.seam,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction <= 0 ? 0.005 : fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            ctxTokens(tokens),
            textAlign: TextAlign.right,
            style: tabular(ts(t.typeScale.uiSmall, t.ink, weight: 600)),
          ),
        ),
      ],
    );
  }
}

class _Covered extends StatelessWidget {
  const _Covered(this.episode, {required this.onTap});

  final ContextEpisode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final small = ts(const TypeSpec(13, 18, 500), t.muted, weight: 400);
    return Semantics(
      button: true,
      label:
          '${episodeTag(episode)} ${episode.title}, messages '
          '${seqRange(episode.firstSeq, episode.lastSeq)}. Show in history.',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        radius: t.radii.md,
        hoverBackground: t.hover,
        pressedBackground: t.pressed,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            CxTag(episodeTag(episode)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                episode.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(const TypeSpec(13, 18, 500), t.ink, weight: 400),
              ),
            ),
            const SizedBox(width: 8),
            Text(seqRange(episode.firstSeq, episode.lastSeq), style: small),
            const SizedBox(width: 8),
            Text(ctxTokens(episode.sourceTokens), style: tabular(small)),
            const SizedBox(width: 6),
            glyphIcon(
              glyphChevronRight,
              size: 14,
              color: t.colors.iconTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton(this.onTap);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      button: true,
      label: 'Back to the list',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: t.radii.ctl,
        hoverBackground: t.hover,
        pressedBackground: t.pressed,
        lift: 0,
        child: SizedBox(
          width: isTouch(context) ? 40 : 28,
          height: isTouch(context) ? 40 : 28,
          child: Center(
            child: glyphIcon(
              glyphChevronLeft,
              size: 18,
              color: t.colors.iconSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
