// Small pieces the context widgets share: glyphs, number and time text, and
// the words for a block, an episode and an event. Not exported from the
// barrel.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const glyphLayers = (
  LucideIcons.layers300,
  LucideIcons.layers,
  LucideIcons.layers500,
);
const glyphHistory = (
  LucideIcons.history300,
  LucideIcons.history,
  LucideIcons.history500,
);
const glyphClock = (
  LucideIcons.clock300,
  LucideIcons.clock,
  LucideIcons.clock500,
);
const glyphHourglass = (
  LucideIcons.hourglass300,
  LucideIcons.hourglass,
  LucideIcons.hourglass500,
);
const glyphChevronLeft = (
  LucideIcons.chevronLeft300,
  LucideIcons.chevronLeft,
  LucideIcons.chevronLeft500,
);
const glyphFoldVertical = (
  LucideIcons.foldVertical300,
  LucideIcons.foldVertical,
  LucideIcons.foldVertical500,
);
const glyphAtSign = (
  LucideIcons.atSign300,
  LucideIcons.atSign,
  LucideIcons.atSign500,
);
const glyphCtxMessage = (
  LucideIcons.messageSquare300,
  LucideIcons.messageSquare,
  LucideIcons.messageSquare500,
);
const glyphCtxEllipsis = (
  LucideIcons.ellipsis300,
  LucideIcons.ellipsis,
  LucideIcons.ellipsis500,
);

/// A token count with one decimal from 1000 up, as the context pane shows
/// them: `6.1k`, `9.0k`, `48.6k`; `812` below. A hundred thousand and more
/// drop the decimal (`128k`).
String ctxTokens(int n) {
  if (n >= 100000) return '${(n / 1000).round()}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// A window or a cap: whole thousands without a decimal (`128k`, `84k`),
/// otherwise as [ctxTokens].
String ctxLimit(int n) =>
    n >= 1000 && n % 1000 == 0 ? '${n ~/ 1000}k' : ctxTokens(n);

/// `31–58` (an en dash), or `31` for one message.
String seqRange(int first, int last) =>
    first == last ? '$first' : '$first–$last';

/// `2 messages`, `1 message`.
String messagesText(int n) => n == 1 ? '1 message' : '$n messages';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `12:48`.
String clockText(DateTime at) {
  final t = at.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// `Today 11:41`, or `Dec 28 11:41` when [at] is not on [now]'s day.
String whenText(DateTime at, DateTime now) {
  final a = at.toLocal(), n = now.toLocal();
  final same = a.year == n.year && a.month == n.month && a.day == n.day;
  return same
      ? 'Today ${clockText(at)}'
      : '${_months[a.month - 1]} ${a.day} ${clockText(at)}';
}

/// A text style with tabular figures, for token columns.
TextStyle tabular(TextStyle s) =>
    s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// The default row title of a [kind] when the host gave none.
String blockTitle(ContextBlock b) =>
    b.title ??
    switch (b.kind) {
      ContextBlockKind.opening => 'Instructions, tools and your first request',
      ContextBlockKind.memoryIndex => 'Chapter index',
      ContextBlockKind.anchors => 'Your requests, word for word',
      ContextBlockKind.chapterSummary => 'Chapter summary',
      ContextBlockKind.episodeSummary => 'Episode summary',
      ContextBlockKind.rawSuffix => 'Recent messages, as written',
    };

/// The word for why a compaction event happened, when the host gave only
/// the enum.
String? triggerWhy(ContextEvent e) {
  final text = e.triggerText;
  if (text != null && text.isNotEmpty) return text;
  return switch (e.trigger) {
    null || ContextTrigger.unknown => null,
    ContextTrigger.pressure => 'the input neared the apply cap',
    ContextTrigger.emergency => 'a short episode was gathered early',
    ContextTrigger.sourceSize => 'the episode reached the source size',
    ContextTrigger.subjectChange => 'the subject changed',
    ContextTrigger.manual => 'you asked for it',
  };
}

/// Where a summary or an episode sits in what the model sees.
enum ContextState {
  /// Replaced by a summary that is in the view.
  replaced,

  /// A summary is ready but the episode is still sent as written.
  ready,

  /// Sent as written, no summary yet.
  live,
}

/// How [details] and [view] place episode [id].
ContextState episodeState(String id, ContextDetails details, ContextView view) {
  if (details.summaries.any((s) => s.applied && s.episodeIds.contains(id))) {
    return ContextState.replaced;
  }
  if (view.pendingEpisodeIds.contains(id)) return ContextState.ready;
  return ContextState.live;
}

/// The applied summary that replaced episode [id], or null.
ContextSummary? replacedBy(String id, ContextDetails details) {
  for (final s in details.summaries) {
    if (s.applied && s.episodeIds.contains(id)) return s;
  }
  return null;
}

/// `E3` for an episode.
String episodeTag(ContextEpisode e) => 'E${e.ordinal}';

/// The tokens the next compaction would save, and the size the view would
/// have after it, from the ready summaries; null without [details] or the
/// view's total.
int? sizeAfterNextCompaction(ContextView view, ContextDetails? details) {
  final total = view.totalTokens;
  if (total == null || details == null || view.pendingEpisodeIds.isEmpty) {
    return null;
  }
  var size = total;
  for (final id in view.pendingEpisodeIds) {
    final ep = details.episode(id);
    final sum = ep?.summaryId == null ? null : details.summary(ep!.summaryId!);
    if (ep == null || sum == null) return null;
    size += sum.summaryTokens - sum.sourceTokens;
  }
  return size;
}
