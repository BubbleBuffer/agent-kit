// The History tab of the Context pane: the original messages with the
// chapters and episodes laid over them (`.hb` in the mockup). The list is
// windowed: an episode asks the host for its first two messages and its last
// one only when it is built, and folds the rest into one line.
// Not exported from the barrel.

import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/kit_tokens.dart';
import '../theme/theme.dart';
import '../transcript/transcript_support.dart';
import 'context_parts.dart';
import 'context_support.dart';

/// Loads original messages `first` to `last` (inclusive).
typedef HistoryLoader = Future<HistoryPage> Function(int first, int last);

/// How many messages an episode shows before it folds the middle.
const _headCount = 2;
const _foldAfter = 5;

class _Entry {
  const _Entry(this.id, this.builder);

  final String? id;
  final Widget Function(BuildContext context) builder;
}

/// The History tab.
class ContextHistory extends StatefulWidget {
  const ContextHistory({
    super.key,
    required this.view,
    required this.details,
    required this.loadHistory,
    required this.keyFor,
    required this.flashId,
    required this.flashToken,
    required this.targetId,
    required this.targetToken,
    required this.onGoSummary,
    required this.controller,
  });

  final ContextView view;
  final ContextDetails details;

  /// Null when the host cannot load messages: the episodes show no rows.
  final HistoryLoader? loadHistory;
  final GlobalKey Function(String id) keyFor;
  final String? flashId;
  final int flashToken;

  /// The `ep:<id>` to bring into view when [targetToken] changes.
  final String? targetId;
  final int targetToken;
  final ValueChanged<String> onGoSummary;
  final ScrollController controller;

  @override
  State<ContextHistory> createState() => _ContextHistoryState();
}

class _ContextHistoryState extends State<ContextHistory> {
  List<_Entry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _jumpLater();
  }

  @override
  void didUpdateWidget(ContextHistory old) {
    super.didUpdateWidget(old);
    if (old.targetToken != widget.targetToken) _jumpLater();
  }

  void _jumpLater() {
    final target = widget.targetId;
    if (target == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _entries.indexWhere((e) => e.id == target);
      if (index < 0) return;
      final key = widget.keyFor(target);
      if (key.currentContext == null && widget.controller.hasClients) {
        // Not built yet: land near it, then let it settle.
        final p = widget.controller.position;
        final guess =
            (index / math.max(1, _entries.length - 1)) * p.maxScrollExtent;
        widget.controller.jumpTo(guess.clamp(0.0, p.maxScrollExtent));
      }
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (!mounted || ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: .08,
          duration: BbTheme.reducedMotion(context)
              ? Duration.zero
              : context.bb.motion.standard,
          curve: context.bb.motion.ease,
        );
      });
    });
  }

  List<_Entry> _build() {
    final d = widget.details;
    final view = widget.view;
    final entries = <_Entry>[
      _Entry(
        null,
        (_) => const CxNote(
          'Nothing here is changed or deleted. Dimmed messages are replaced by a summary in what the '
          'model sees.',
        ),
      ),
    ];
    final chapters = [...d.chapters]
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    var lastSeq = 0;
    for (final c in chapters) {
      entries.add(_Entry('ch:${c.id}', (_) => _ChapterBand(c)));
      final eps = [...d.episodes.where((e) => e.chapterId == c.id)]
        ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
      for (final e in eps) {
        lastSeq = math.max(lastSeq, e.lastSeq);
        entries.add(
          _Entry(
            'ep:${e.id}',
            (context) => KeyedSubtree(
              key: widget.keyFor('ep:${e.id}'),
              child: CxFlash(
                active: widget.flashId == 'ep:${e.id}',
                token: widget.flashToken,
                child: _EpisodeBlock(
                  episode: e,
                  state: episodeState(e.id, d, view),
                  replacedBy: replacedBy(e.id, d),
                  details: d,
                  loader: widget.loadHistory,
                  onGoSummary: widget.onGoSummary,
                ),
              ),
            ),
          ),
        );
      }
    }
    final raw = view.ofKind(ContextBlockKind.rawSuffix).lastOrNull;
    final tailLast = raw?.lastSeq;
    if (tailLast != null && tailLast > lastSeq) {
      final first = lastSeq + 1;
      entries.add(
        _Entry(
          'ep:tail',
          (_) => _EpisodeBlock.tail(
            tailFirst: first,
            tailLast: tailLast,
            loader: widget.loadHistory,
          ),
        ),
      );
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    _entries = _build();
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.xxs,
        Space.md,
        Space.xl,
      ),
      itemCount: _entries.length,
      itemBuilder: (context, i) => _entries[i].builder(context),
    );
  }
}

class _ChapterBand extends StatelessWidget {
  const _ChapterBand(this.chapter);

  final ContextChapter chapter;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = chapter;
    final open = c.status == ContextStatus.open || c.lastSeq == null;
    final range = open
        ? 'open · from message ${c.firstSeq}'
        : 'messages ${seqRange(c.firstSeq, c.lastSeq!)}';
    return Semantics(
      container: true,
      header: true,
      label: 'Chapter ${c.ordinal}${open ? ', open' : ''}. ${c.title}',
      child: Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xxs,
            vertical: Space.xs,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.hair,
            children: [
              CxTag('Chapter ${c.ordinal}'),
              Text(
                c.title,
                style: ts(t.typeScale.ui, t.ink, weight: Weight.bold),
              ),
              Text(
                range,
                style: ts(t.typeScale.uiSmall, t.faint, weight: Weight.regular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeBlock extends StatelessWidget {
  const _EpisodeBlock({
    required this.episode,
    required this.state,
    required this.replacedBy,
    required this.details,
    required this.loader,
    required this.onGoSummary,
  }) : tailFirst = null,
       tailLast = null,
       isTail = false;

  const _EpisodeBlock.tail({
    required int this.tailFirst,
    required int this.tailLast,
    required this.loader,
  }) : episode = null,
       state = ContextState.live,
       replacedBy = null,
       details = null,
       onGoSummary = null,
       isTail = true;

  final ContextEpisode? episode;
  final ContextState state;
  final ContextSummary? replacedBy;
  final ContextDetails? details;
  final HistoryLoader? loader;
  final ValueChanged<String>? onGoSummary;
  final int? tailFirst, tailLast;
  final bool isTail;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final e = episode;
    final first = isTail ? tailFirst! : e!.firstSeq;
    final last = isTail ? tailLast! : e!.lastSeq;
    final gone = state == ContextState.replaced;
    final stateText = switch (state) {
      ContextState.replaced =>
        replacedBy != null && replacedBy!.kind == ContextSummaryKind.chapter
            ? 'Replaced by the Chapter '
                  '${details?.chapter(replacedBy!.chapterId ?? '')?.ordinal ?? ''}'
                  ' summary'
            : 'Replaced by its own summary',
      ContextState.ready => 'Sent as written · summary ready, not in view yet',
      ContextState.live => 'Sent as written',
    };
    final sumId = replacedBy?.id ?? e?.summaryId;
    final tag = isTail ? 'Now' : episodeTag(e!);
    final title = isTail ? 'Not summarized yet' : e!.title;
    final tokens = isTail ? null : ctxTokens(e!.sourceTokens);
    final gutter = state == ContextState.live ? t.ctxLive : t.ctxSummary;
    return Semantics(
      container: true,
      label: '$tag $title. $stateText. Messages ${seqRange(first, last)}.',
      child: Padding(
        padding: const EdgeInsets.only(top: Space.xs, left: Space.xxs),
        child: CustomPaint(
          foregroundPainter: state == ContextState.ready
              ? DashedPainter(
                  color: gutter,
                  width: 3,
                  dash: 5,
                  gap: 3,
                  leftOnly: true,
                )
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: state == ContextState.ready
                  ? Border(
                      left: BorderSide(
                        width: Stroke.seam,
                        color: t.surface.withValues(alpha: 0),
                      ),
                    )
                  : Border(
                      left: BorderSide(width: Stroke.seam, color: gutter),
                    ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.sm,
                Space.xs,
                0,
                Space.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CxTag(tag),
                      const Gap(Space.sm),
                      Expanded(
                        child: Text(
                          title,
                          style: ts(
                            t.typeScale.ui,
                            t.ink,
                            weight: Weight.semibold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: ControlSize.sm.height,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: Space.md,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                stateText,
                                style: ts(
                                  t.typeScale.uiSmall,
                                  t.muted,
                                  weight: Weight.regular,
                                ),
                              ),
                              Text(
                                [seqRange(first, last), ?tokens].join(' · '),
                                style: tabular(
                                  ts(
                                    t.typeScale.uiSmall,
                                    t.faint,
                                    weight: Weight.regular,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sumId != null && onGoSummary != null)
                          KitTextButton(
                            'Summary',
                            glyph: glyphLayers,
                            color: t.ink,
                            onTap: () => onGoSummary!(sumId),
                          ),
                      ],
                    ),
                  ),
                  if (loader != null)
                    _Messages(
                      first: first,
                      last: last,
                      loader: loader!,
                      dim: gone,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first two messages, a fold and the last one (or all of a short run).
class _Messages extends StatefulWidget {
  const _Messages({
    required this.first,
    required this.last,
    required this.loader,
    required this.dim,
  });

  final int first, last;
  final HistoryLoader loader;
  final bool dim;

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  late Future<List<HistoryPage>> _pages = _load();

  bool get _short => widget.last - widget.first + 1 <= _foldAfter;

  Future<List<HistoryPage>> _load() => _short
      ? Future.wait([widget.loader(widget.first, widget.last)])
      : Future.wait([
          widget.loader(widget.first, widget.first + _headCount - 1),
          widget.loader(widget.last, widget.last),
        ]);

  @override
  void didUpdateWidget(_Messages old) {
    super.didUpdateWidget(old);
    if (old.first != widget.first ||
        old.last != widget.last ||
        old.loader != widget.loader) {
      _pages = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return FutureBuilder<List<HistoryPage>>(
      future: _pages,
      builder: (context, snap) {
        final pages = snap.data;
        if (pages == null) {
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: ControlSize.xs.height),
            child: snap.hasError
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'The messages could not be loaded.',
                      style: ts(
                        t.typeScale.uiSmall,
                        t.faint,
                        weight: Weight.regular,
                      ),
                    ),
                  )
                : null,
          );
        }
        final rows = <Widget>[
          for (final m in pages.first.messages) _MessageRow(m, dim: widget.dim),
        ];
        if (!_short) {
          final hidden = widget.last - widget.first + 1 - _headCount - 1;
          if (hidden > 0) {
            rows.add(_Fold(hidden));
          }
          for (final m in pages.last.messages) {
            rows.add(_MessageRow(m, dim: widget.dim));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

class _Fold extends StatelessWidget {
  const _Fold(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.hair,
        Space.xxs,
        Space.hair,
      ),
      child: Row(
        children: [
          glyphIcon(
            glyphCtxEllipsis,
            size: IconSize.xs.px,
            color: t.colors.iconTertiary,
          ),
          const Gap(Space.xs),
          Text(
            '$count more messages',
            style: ts(t.typeScale.uiSmall, t.faint, weight: Weight.regular),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.message, {required this.dim});

  final HistoryMessage message;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final who = switch (message.role) {
      HistoryRole.user => 'You',
      HistoryRole.agent => 'Agent',
      HistoryRole.tool => 'tool',
    };
    final mono = monoStyle(t.typeScale.caption, t.faint);
    return Opacity(
      opacity: dim ? Alpha.muted : KitAlpha.opaque,
      child: Semantics(
        label: '${message.seq}, $who: ${message.preview}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            Space.hair,
            Space.xxs,
            Space.hair,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: KitSizes.historySeqColumn,
                child: Text(
                  '${message.seq}',
                  textAlign: TextAlign.right,
                  style: mono,
                ),
              ),
              const Gap(Space.xs),
              SizedBox(
                width: KitSizes.historyRoleColumn,
                child: Text(
                  who,
                  style: ts(t.typeScale.uiSmall, t.muted, weight: Weight.bold),
                ),
              ),
              const Gap(Space.xs),
              Expanded(
                child: Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(
                    t.typeScale.ui,
                    t.ink,
                    weight: dim ? Weight.regular : Weight.medium,
                  ),
                ),
              ),
              if (message.tokens != null) ...[
                const Gap(Space.xs),
                Text(ctxTokens(message.tokens!), style: mono),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
