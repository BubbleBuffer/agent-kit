// The cards of compacted history: a closed chapter (a folding card over its
// episodes), the open chapter (a plain group header), an episode (a header
// line, title, gist, an action log and the original messages) and a legacy
// summary, plus the hairline where full messages begin. The host lays them in
// a list (`TranscriptList.entries`) and keeps the fold state in a
// `HistoryController`. The look follows the scratch-skin mockup's scene H and
// the outline's chapter card.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../context/context_support.dart' show glyphCtxMessage;
import '../outline/outline_chapter_widgets.dart' show outlineColor;
import '../theme/theme.dart';
import '../transcript/transcript_support.dart';
import 'history_controller.dart';
import 'history_model.dart';

/// Builds the original messages of [episode] for its card (the host's
/// ordinary message views).
typedef HistoryMessagesBuilder = Widget Function(
  BuildContext context,
  HistoryEpisode episode,
);

const _glyphReply = (
  LucideIcons.reply300,
  LucideIcons.reply,
  LucideIcons.reply500,
);

/// Action rows an episode shows before "+N more".
const historyActionsShown = 6;

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// "58 messages · 2 episodes"; the parts that are null are left out.
String historyChapterCounts(HistoryChapter chapter) => [
  if (chapter.messageCount != null) _plural(chapter.messageCount!, 'message'),
  if (chapter.episodeCount != null) _plural(chapter.episodeCount!, 'episode'),
].join(' · ');

// ---------------------------------------------------------------- chapter

/// A closed chapter: a card whose face is the summary, so it reads alone.
/// Opening it lists its episode cards. A part of a split chapter is a card with
/// the same title; only the last part shows the counts.
class HistoryChapterCard extends StatelessWidget {
  const HistoryChapterCard({
    super.key,
    required this.chapter,
    required this.controller,
    this.messagesBuilder,
  });

  final HistoryChapter chapter;
  final HistoryController controller;
  final HistoryMessagesBuilder? messagesBuilder;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    final ty = t.typeScale;
    final key = chapter.key;
    final summary = chapter.summary;
    final hasSummary = summary != null && summary.isNotEmpty;
    final counts = historyChapterCounts(chapter);
    final when = historyWhen(chapter.startedAt, chapter.endedAt);
    final label = [
      'Chapter',
      if (when.isNotEmpty) when,
      if (chapter.closed) 'closed',
    ].join(' · ');
    final summaryText = hasSummary
        ? Text(summary, style: ts(ty.body, c.textPrimary))
        : null;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final open = controller.chapterOpen(key);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FoldableStackCard(
            faceKey: ValueKey('history-chapter-$key-face'),
            edge: outlineColor(context, chapter.colorIndex),
            label: label,
            title: chapter.title,
            stacked: !open,
            open: open,
            onOpenChanged: (v) => controller.setChapterOpen(key, v),
            peek: summaryText,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?summaryText,
                if (chapter.episodes.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(top: hasSummary ? 14 : 0),
                    padding: const EdgeInsets.only(top: 14),
                    decoration: hasSummary
                        ? BoxDecoration(
                            border: Border(
                              top: BorderSide(color: c.borderSubtle),
                            ),
                          )
                        : null,
                    child: _EpisodeList(
                      episodes: chapter.episodes,
                      controller: controller,
                      messagesBuilder: messagesBuilder,
                    ),
                  ),
              ],
            ),
            footer: (open) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(counts, style: ts(ty.uiSmall, c.textSecondary)),
                  ),
                  if (chapter.episodes.isNotEmpty)
                    FooterAction(
                      key: ValueKey('history-chapter-$key-toggle'),
                      label: open ? 'Hide episodes' : 'Show episodes',
                      onTap: () => controller.toggleChapter(key),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The open chapter: it has no title or summary yet (they are written when it
/// closes), so it is a plain group header over its episode cards, always
/// listed.
class HistoryCurrentChapter extends StatelessWidget {
  const HistoryCurrentChapter({
    super.key,
    required this.chapter,
    required this.controller,
    this.messagesBuilder,
  });

  final HistoryChapter chapter;
  final HistoryController controller;
  final HistoryMessagesBuilder? messagesBuilder;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final ty = t.typeScale;
    final when = historyWhen(chapter.startedAt, null);
    final sep = TextSpan(text: ' · ', style: ts(ty.uiSmall, t.faint));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text.rich(
            key: ValueKey('history-current-${chapter.key}'),
            TextSpan(
              style: ts(ty.uiSmall, t.muted),
              children: [
                TextSpan(
                  text: 'Current chapter',
                  style: ts(ty.uiSmall, t.ink, weight: 700),
                ),
                if (when.isNotEmpty) ...[sep, TextSpan(text: when)],
                sep,
                TextSpan(text: _plural(chapter.episodes.length, 'episode')),
              ],
            ),
          ),
        ),
        _EpisodeList(
          episodes: chapter.episodes,
          controller: controller,
          messagesBuilder: messagesBuilder,
        ),
      ],
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.episodes,
    required this.controller,
    required this.messagesBuilder,
  });

  final List<HistoryEpisode> episodes;
  final HistoryController controller;
  final HistoryMessagesBuilder? messagesBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, e) in episodes.indexed) ...[
        if (i > 0) const SizedBox(height: 10),
        HistoryEpisodeCard(
          episode: e,
          controller: controller,
          messagesBuilder: messagesBuilder,
        ),
      ],
    ],
  );
}

// ----------------------------------------------------------------- legacy

/// A summary from before chapters and episodes: the title (when there is
/// one), the summary, the times and the message count. Nothing opens.
class HistoryLegacyCard extends StatelessWidget {
  const HistoryLegacyCard({super.key, required this.legacy});

  final HistoryLegacy legacy;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    final ty = t.typeScale;
    final when = historyWhen(legacy.startedAt, legacy.endedAt);
    final title = legacy.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.bgElevated,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.border),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(
                  color: outlineColor(context, legacy.colorIndex),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        'Chapter',
                        if (when.isNotEmpty) when,
                        'closed',
                      ].join(' · '),
                      style: ts(ty.uiSmall, c.textTertiary),
                    ),
                    if (title != null && title.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(title, style: tsDisplay(ty.h3, c.textPrimary)),
                    ],
                    const SizedBox(height: 3),
                    Text(legacy.summary, style: ts(ty.body, c.textPrimary)),
                    const SizedBox(height: 10),
                    Text(
                      _plural(legacy.messageCount, 'message'),
                      style: ts(ty.uiSmall, c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- boundary

/// The hairline where full messages begin: "Full messages from here ·
/// message N". The number is left out at compact widths.
class HistoryBoundary extends StatelessWidget {
  const HistoryBoundary({super.key, required this.messageNumber});

  /// One-based number of the first message shown in full.
  final int messageNumber;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final ty = t.typeScale;
    final compact = sizeClassOf(context).isCompact;
    Widget rule() => Expanded(
      child: SizedBox(height: 1, child: ColoredBox(color: t.thread)),
    );
    return Semantics(
      container: true,
      label: 'Full messages start here, from message $messageNumber',
      child: ExcludeSemantics(
        child: Row(
          children: [
            rule(),
            const SizedBox(width: 8),
            glyphIcon(glyphArrowDown, size: 14, color: t.colors.iconSecondary),
            const SizedBox(width: 8),
            Text(
              'Full messages from here',
              style: ts(ty.uiSmall, t.ink, weight: 600),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text('message $messageNumber', style: ts(ty.uiSmall, t.faint)),
            ],
            const SizedBox(width: 8),
            rule(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- episode

/// An episode: a mono header line, the title and a one-line gist. It opens
/// into its action log, and from there into the original messages. An episode
/// without actions goes straight from its card to the messages.
class HistoryEpisodeCard extends StatelessWidget {
  const HistoryEpisodeCard({
    super.key,
    required this.episode,
    required this.controller,
    this.messagesBuilder,
  });

  final HistoryEpisode episode;
  final HistoryController controller;
  final HistoryMessagesBuilder? messagesBuilder;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    final ty = t.typeScale;
    final compact = sizeClassOf(context).isCompact;
    final id = episode.id;
    final clock = historyClock(episode.startedAt, episode.endedAt);
    final gist = episode.gist;
    final hasActions = episode.hasActions;
    final canMessages = messagesBuilder != null;
    final sep = TextSpan(text: ' · ', style: monoStyle(ty.uiSmall, t.faint));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.episodeView(id);
        final open = view != HistoryEpisodeView.closed;
        final counts = [
          _plural(episode.actionCount, 'action'),
          if (episode.flaggedCount > 0) '${episode.flaggedCount} flagged',
          if (episode.errorCount > 0) _plural(episode.errorCount, 'error'),
        ].join(' · ');
        void toggle() => controller.setEpisodeView(
          id,
          open
              ? HistoryEpisodeView.closed
              : hasActions
              ? HistoryEpisodeView.log
              : HistoryEpisodeView.messages,
        );
        void show(HistoryEpisodeView v) => controller.setEpisodeView(id, v);
        Widget? footer;
        if (hasActions && view == HistoryEpisodeView.log && canMessages) {
          footer = KitTextButton(
            'Show messages',
            key: ValueKey('history-episode-$id-messages'),
            onTap: () => show(HistoryEpisodeView.messages),
          );
        } else if (hasActions && view == HistoryEpisodeView.messages) {
          footer = KitTextButton(
            'Show action log',
            key: ValueKey('history-episode-$id-log'),
            onTap: () => show(HistoryEpisodeView.log),
          );
        } else if (!hasActions && !open && canMessages) {
          footer = KitTextButton(
            'Show messages',
            key: ValueKey('history-episode-$id-messages'),
            onTap: () => show(HistoryEpisodeView.messages),
          );
        }
        return Semantics(
          container: true,
          label: 'Episode, $clock',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.borderSubtle),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                0,
                compact ? 10 : 12,
                6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Hover(
                    key: ValueKey('history-episode-$id-header'),
                    onTap: toggle,
                    lift: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: isTouch(context) ? 40 : 34,
                      ),
                      child: Row(
                        children: [
                          DisclosureChevron(open: open, size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: monoStyle(ty.uiSmall, t.muted),
                                children: [
                                  TextSpan(
                                    text: 'Episode',
                                    style: monoStyle(ty.uiSmall, t.ink),
                                  ),
                                  if (clock.isNotEmpty) ...[
                                    sep,
                                    TextSpan(text: clock),
                                  ],
                                  sep,
                                  TextSpan(
                                    text: _plural(
                                      episode.messageCount,
                                      'message',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (hasActions && !compact) ...[
                            const SizedBox(width: 8),
                            Text(
                              counts,
                              maxLines: 1,
                              style: monoStyle(ty.uiSmall, t.faint),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode.title,
                          style: ts(ty.ui, t.ink, weight: 700),
                        ),
                        if (gist != null && gist.isNotEmpty)
                          Text(gist, style: ts(ty.ui, t.muted, weight: 400)),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                  if (view == HistoryEpisodeView.log)
                    _ActionLog(episode: episode, controller: controller),
                  if (view == HistoryEpisodeView.messages &&
                      messagesBuilder != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: messagesBuilder!(context, episode),
                    ),
                  if (footer != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.only(top: 4),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.borderSubtle)),
                      ),
                      child: footer,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionLog extends StatelessWidget {
  const _ActionLog({required this.episode, required this.controller});

  final HistoryEpisode episode;
  final HistoryController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final all = episode.actions;
    final more = controller.moreShown(episode.id);
    final shown = more ? all : all.take(historyActionsShown).toList();
    final rest = all.length - shown.length;
    final compact = sizeClassOf(context).isCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: ValueKey('history-episode-${episode.id}-log-rows'),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.colors.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final a in shown) _ActionRow(a, compact: compact)],
          ),
        ),
        if (rest > 0)
          Padding(
            padding: EdgeInsets.only(left: compact ? 38 : 46, top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: KitTextButton(
                '+$rest more',
                key: ValueKey('history-episode-${episode.id}-more'),
                onTap: () => controller.showMore(episode.id),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.action, {required this.compact});

  final HistoryAction action;
  final bool compact;

  Color _tone(BbTheme t, HistoryMarkerTone tone) => switch (tone) {
    HistoryMarkerTone.added || HistoryMarkerTone.ok => t.constructiveInk,
    HistoryMarkerTone.removed => t.dangerInk,
    HistoryMarkerTone.neutral => t.muted,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final ty = t.typeScale;
    final marker = action.marker;
    final point = action.point;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: t.seam),
      ),
      child: Text(
        action.target,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(ty.uiSmall, t.ink),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 46 : 54,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  action.verb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(ty.uiSmall, t.muted),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 220 : 520,
                        ),
                        child: chip,
                      ),
                      if (marker != null && marker.isNotEmpty)
                        Text.rich(
                          TextSpan(
                            children: [
                              for (final (text, tone) in historyMarkerRuns(
                                marker,
                              ))
                                TextSpan(
                                  text: text,
                                  style: ts(
                                    ty.uiSmall,
                                    _tone(t, tone),
                                    weight: 600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (point != null) _PointLine(point),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointLine extends StatelessWidget {
  const _PointLine(this.point);

  final HistoryPoint point;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final ty = t.typeScale;
    final error = point.kind == HistoryPointKind.error;
    final ink = error ? t.dangerInk : t.ink;
    final word = switch (point.kind) {
      HistoryPointKind.decision => 'decision',
      HistoryPointKind.correction => 'user correction',
      HistoryPointKind.error => 'error',
      HistoryPointKind.question => 'open question',
    };
    final Widget icon = switch (point.kind) {
      HistoryPointKind.decision => Icon20(Ico.star, size: 12, color: ink),
      HistoryPointKind.correction => glyphIcon(
        _glyphReply,
        size: 12,
        color: ink,
      ),
      HistoryPointKind.error => glyphIcon(glyphCircleX, size: 12, color: ink),
      HistoryPointKind.question => glyphIcon(
        glyphCtxMessage,
        size: 12,
        color: ink,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: 5),
          Text(word, style: ts(ty.uiSmall, ink, weight: 700)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              point.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(ty.uiSmall, t.muted),
            ),
          ),
        ],
      ),
    );
  }
}
