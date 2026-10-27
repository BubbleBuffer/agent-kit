// The outline as the kit draws it: chapters and their sections over the
// transcript. Plain immutable view models; a host maps its own outline to
// them. Anchor ids (`first` and `last`) name entries of the transcript's
// ordered anchor list, usually message ids: a chapter or section covers the
// anchors from its first to its last, inclusive.

import 'package:flutter/foundation.dart';

import 'outline_names.dart';

/// A section inside a chapter.
@immutable
class OutlineSection {
  const OutlineSection({
    required this.id,
    required String title,
    required this.first,
    required this.last,
    this.chapterName,
  }) : rawTitle = title;

  /// Stable across rebuilds; keys and the contents use it.
  final String id;

  /// The title as stored.
  final String rawTitle;

  /// The chapter's name, which a title may repeat as a prefix. Set by
  /// [OutlineChapter] when it is left null.
  final String? chapterName;

  /// The first and last anchor ids of the section, inclusive.
  final String first, last;

  /// The title shown: [rawTitle] without the chapter's name as a prefix.
  String get title =>
      outlineNameGist(rawTitle, '', chapterName: chapterName).name;

  OutlineSection _within(String chapterName) => this.chapterName != null
      ? this
      : OutlineSection(
          id: id,
          title: rawTitle,
          first: first,
          last: last,
          chapterName: chapterName,
        );
}

/// A chapter: a card when closed, a heading while open.
@immutable
class OutlineChapter {
  OutlineChapter({
    required this.id,
    required String title,
    required this.first,
    required this.last,
    this.decisions = const [],
    this.summary = '',
    this.startedAt,
    this.endedAt,
    this.ongoing = false,
    this.messageCount = 0,
    List<OutlineSection> sections = const [],
  }) : rawTitle = title,
       sections = List.unmodifiable([
         for (final s in sections)
           s._within(outlineNameGist(title, summary).name),
       ]);

  /// Stable across rebuilds; keys and the contents use it.
  final String id;

  /// The title as stored.
  final String rawTitle;

  /// The title shown: the name part of a "Name: sentence" title.
  String get title => outlineNameGist(rawTitle, summary).name;

  /// The first and last anchor ids of the chapter, inclusive.
  final String first, last;
  final List<String> decisions;
  final String summary;

  /// When the chapter started and ended. [endedAt] is ignored while
  /// [ongoing].
  final DateTime? startedAt, endedAt;

  /// An open chapter: it stays unfolded as a heading and cannot fold.
  final bool ongoing;

  /// How many messages the chapter holds, tool results left out. Shown on the
  /// card and in the contents.
  final int messageCount;
  final List<OutlineSection> sections;

  /// A date range for people, such as "Sep 28 – 30" or "since Oct 6". Empty
  /// when there is no start.
  String get when => outlineWhen(startedAt, ongoing ? null : endedAt);

  /// Closed chapters start as a card with their messages hidden.
  bool get foldedByDefault => !ongoing;

  /// The first non-blank decision, the one line a card shows.
  String? get decision => outlineDecision(decisions);

  /// The line a card shows when there is no decision: the summary's first
  /// sentence, or null when there is no summary.
  String? get gist {
    final gist = outlineNameGist(rawTitle, summary).gist;
    return gist.isEmpty ? null : gist;
  }
}

/// The chapters of one chat, in order.
@immutable
class Outline {
  const Outline(this.chapters);

  static const empty = Outline([]);

  final List<OutlineChapter> chapters;
  bool get isEmpty => chapters.isEmpty;
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

/// "Sep 28 – 30" within a month, "Sep 28 – Oct 2" across two, "since Oct 6"
/// while open ([endedAt] null). Empty when there is no start. Times are shown
/// in the local zone.
@visibleForTesting
String outlineWhen(DateTime? startedAt, DateTime? endedAt) {
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
