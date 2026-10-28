// Compacted history as the kit draws it: closed chapters, the open chapter's
// episodes and legacy summaries, as plain immutable view models. A host maps
// its own history to them (no backend or bridge type is imported here).
// A chapter carries its decisions and sections when the host has them; both
// stay empty for a chapter summarized without them.

import 'package:flutter/foundation.dart';

/// Why an action row carries a second line.
enum HistoryPointKind { decision, correction, error, question }

/// The second line of an action row: a marker, its kind and the reason.
@immutable
class HistoryPoint {
  const HistoryPoint({required this.kind, required this.reason});

  final HistoryPointKind kind;

  /// A few words, quoting the user for a correction.
  final String reason;
}

/// One row of an episode's action log.
@immutable
class HistoryAction {
  const HistoryAction({
    required this.verb,
    required this.target,
    this.marker,
    this.point,
  });

  /// Past tense, such as Read, Edited, Created, Deleted, Ran, Asked.
  final String verb;

  /// A file path, page, command or quoted question; shown as a chip.
  final String target;

  /// The change next to the chip: `+12 −3`, `created`, `deleted`,
  /// `failed · 2 tests`, `passed · 14`. Its colour follows the words.
  final String? marker;

  final HistoryPoint? point;
}

/// An episode card: a structured log of what happened, over the original
/// messages.
@immutable
class HistoryEpisode {
  const HistoryEpisode({
    required this.id,
    required this.title,
    this.gist,
    this.startedAt,
    this.endedAt,
    this.messageCount = 0,
    this.actions = const [],
    int? actionCount,
    this.flaggedCount = 0,
    this.errorCount = 0,
    // ignore: prefer_initializing_formals
  }) : _actionCount = actionCount;

  /// Stable across rebuilds; fold state keys on it.
  final String id;
  final String title;

  /// One clause under the title; null or empty leaves it out.
  final String? gist;
  final DateTime? startedAt, endedAt;
  final int messageCount;
  final List<HistoryAction> actions;

  /// Counts for the header line (rows, rows with a point of interest, rows
  /// that are errors).
  final int flaggedCount, errorCount;
  final int? _actionCount;

  /// The rows counted for the header line: [actions] unless given.
  int get actionCount => _actionCount ?? actions.length;

  /// False for an episode summarized without an action log: its card has no
  /// action counts and goes straight to the messages.
  bool get hasActions => actions.isNotEmpty;
}

/// A named stretch of a chapter: a name (data, not a label) and the one-based
/// ordinals of its first and last episode.
@immutable
class HistorySection {
  const HistorySection({
    required this.name,
    this.firstEpisode,
    this.lastEpisode,
  });

  final String name;
  final int? firstEpisode, lastEpisode;
}

/// A chapter, or one part of a split chapter. A closed chapter is a card; an
/// open one is a plain group header over its episodes.
@immutable
class HistoryChapter {
  const HistoryChapter({
    required this.id,
    required this.title,
    this.summary,
    this.startedAt,
    this.endedAt,
    this.closed = true,
    this.part = 1,
    this.parts = 1,
    this.messageCount,
    this.episodeCount,
    this.episodes = const [],
    this.decisions = const [],
    this.sections = const [],
    this.colorIndex = 0,
  });

  /// Stable across rebuilds; shared by the parts of a split chapter.
  final String id;
  final String title;
  final String? summary;
  final DateTime? startedAt, endedAt;
  final bool closed;

  /// One-based part number and the number of parts. Each part is a card with
  /// the same title.
  final int part, parts;

  /// The whole chapter's totals; null on a part that is not the last, which
  /// shows no footer counts.
  final int? messageCount, episodeCount;
  final List<HistoryEpisode> episodes;

  /// One line each, shown under the summary; empty leaves the rows out. Set on
  /// the last part of a split chapter only.
  final List<String> decisions;

  /// The sections, a coloured bar and a name each; empty leaves the row out.
  /// Set on the last part of a split chapter only.
  final List<HistorySection> sections;

  /// Picks the card's edge colour (see `outlineColor`).
  final int colorIndex;

  /// Keys the fold state: one per card.
  String get key => parts > 1 ? '$id#$part' : id;
}

/// A summary from before chapters and episodes: a title when there is one, the
/// summary, the times and the message count. Nothing opens inside it.
@immutable
class HistoryLegacy {
  const HistoryLegacy({
    required this.id,
    required this.summary,
    this.title,
    this.startedAt,
    this.endedAt,
    this.messageCount = 0,
    this.colorIndex = 0,
  });

  final String id;
  final String? title;
  final String summary;
  final DateTime? startedAt, endedAt;
  final int messageCount;
  final int colorIndex;
}

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

/// "Oct 26 – 27" within a month, "Oct 26 – Nov 2" across two, "Oct 26" for
/// one day, "since Oct 26" while [endedAt] is null. Empty without a start.
/// Local time.
String historyWhen(DateTime? startedAt, DateTime? endedAt) {
  final start = startedAt?.toLocal();
  if (start == null) return '';
  final from = '${_months[start.month - 1]} ${start.day}';
  final end = endedAt?.toLocal();
  if (end == null) return 'since $from';
  if (end.year == start.year &&
      end.month == start.month &&
      end.day == start.day) {
    return from;
  }
  if (end.year == start.year && end.month == start.month) {
    return '$from – ${end.day}';
  }
  return '$from – ${_months[end.month - 1]} ${end.day}';
}

/// "13:41–13:56" in local time; one time when the ends match, empty without
/// a start.
String historyClock(DateTime? startedAt, DateTime? endedAt) {
  String hm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  if (startedAt == null) return '';
  final a = hm(startedAt);
  if (endedAt == null) return a;
  final b = hm(endedAt);
  return a == b ? a : '$a–$b';
}

/// How a marker's words are coloured.
enum HistoryMarkerTone { neutral, added, removed, ok }

/// A marker split into runs of one tone. `+12` and `created` are added, `−3`
/// and `deleted` removed, `failed` removed to the end, `passed` ok to the end;
/// the rest is neutral.
List<(String, HistoryMarkerTone)> historyMarkerRuns(String marker) {
  final out = <(String, HistoryMarkerTone)>[];
  HistoryMarkerTone? sticky;
  for (final word in marker.split(' ')) {
    if (word.isEmpty) continue;
    var tone = sticky ?? HistoryMarkerTone.neutral;
    if (sticky == null) {
      if (word.startsWith('+') || word == 'created') {
        tone = HistoryMarkerTone.added;
      } else if (word.startsWith('−') ||
          word.startsWith('-') ||
          word == 'deleted') {
        tone = HistoryMarkerTone.removed;
      } else if (word == 'failed') {
        tone = sticky = HistoryMarkerTone.removed;
      } else if (word == 'passed') {
        tone = sticky = HistoryMarkerTone.ok;
      }
    }
    if (out.isNotEmpty && out.last.$2 == tone) {
      out[out.length - 1] = ('${out.last.$1} $word', tone);
    } else {
      out.add((out.isEmpty ? word : ' $word', tone));
    }
  }
  return out;
}
