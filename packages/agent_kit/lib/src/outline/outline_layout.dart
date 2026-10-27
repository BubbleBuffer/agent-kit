// The outline laid over the transcript: chapters and their sections as rows
// between the chat's items. A closed chapter folds to one card and its items
// leave the rows, so a long chat builds only what is shown. Anchor ids anchor
// everything: a chapter or section covers the anchors from its first to its
// last id, and a grouped turn answers for each anchor it holds.
//
// Pure Dart on purpose: the widgets live in the other files of this folder.

import 'dart:math';

import 'outline_model.dart';

/// One line of the transcript: a chat item, a chapter's card or heading, or a
/// section's divider. [chapter] and [section] are indexes into the outline
/// (-1 when outside), which is what the where-am-I strip reads.
sealed class OutlineRow {
  const OutlineRow(this.key, {required this.chapter, required this.section});

  /// Stable across rebuilds; scroll targets and widget keys use it.
  final String key;
  final int chapter;
  final int section;
}

/// A transcript item, named by the host's item id.
class ItemRow extends OutlineRow {
  const ItemRow(
    super.key,
    this.itemId, {
    required super.chapter,
    required super.section,
  });
  final String itemId;
}

class ChapterRow extends OutlineRow {
  const ChapterRow(super.key, {required super.chapter, required this.folded})
    : super(section: -1);

  /// True when the chapter's messages are hidden (the card shows alone), false
  /// when they show under it or the chapter is open.
  final bool folded;
}

class SectionRow extends OutlineRow {
  const SectionRow(super.key, {required super.chapter, required super.section});
}

/// Where a jump to a span lands: the item that holds its first anchor, and
/// the chapter that item sits in (-1 when none).
class OutlineTarget {
  const OutlineTarget(this.itemId, this.chapter);
  final String itemId;
  final int chapter;
}

/// Each anchor's segment: the chapter and section it sits in, as a key the
/// transcript splits grouped turns by. Anchors outside every chapter share one
/// segment. Empty when [outline] is empty, so the transcript is unsplit.
Map<String, String> outlineSegments(Outline outline, List<String> anchorIds) {
  if (outline.isEmpty) return const {};
  final pos = <String, int>{
    for (var i = 0; i < anchorIds.length; i++) anchorIds[i]: i,
  };
  final chapters = outline.chapters;
  final chapterSpans = [for (final c in chapters) _span(pos, c.first, c.last)];
  final sectionSpans = [
    for (final c in chapters)
      [for (final s in c.sections) _span(pos, s.first, s.last)],
  ];
  return {
    for (var p = 0; p < anchorIds.length; p++)
      anchorIds[p]: () {
        final ch = _chapterAt(chapterSpans, p);
        final sec = _sectionAt(sectionSpans, ch, p);
        return ch < 0 ? '-' : '$ch.$sec';
      }(),
  };
}

/// The transcript's rows for one outline and fold state.
class OutlineLayout {
  OutlineLayout._(
    this.rows,
    this._rowOf,
    this._itemChapter,
    this._anchorIds,
    this._pos,
    this._anchorOf,
  );

  final List<OutlineRow> rows;
  final Map<String, int> _rowOf;
  final Map<String, int> _itemChapter;
  final List<String> _anchorIds;
  final Map<String, int> _pos;
  final Map<String, String> _anchorOf;

  /// Builds the rows. [itemIds] are the transcript items in order, [anchorIds]
  /// the anchors (usually message ids) in order, and [anchorOf] maps each
  /// anchor id to the item that shows it. [folded] says whether a chapter's
  /// messages are hidden right now.
  factory OutlineLayout.build({
    required Outline outline,
    required List<String> itemIds,
    required List<String> anchorIds,
    required Map<String, String> anchorOf,
    required bool Function(OutlineChapter chapter) folded,
  }) {
    final pos = <String, int>{
      for (var i = 0; i < anchorIds.length; i++) anchorIds[i]: i,
    };
    final chapters = outline.chapters;
    final chapterSpans = [
      for (final c in chapters) _span(pos, c.first, c.last),
    ];
    final sectionSpans = [
      for (final c in chapters)
        [for (final s in c.sections) _span(pos, s.first, s.last)],
    ];

    // Each item's first and last anchor position. Items that show no anchor
    // (run notes, approvals, the live reply) take the position of the item
    // before them, so they stay with their context.
    final lo = <String, int>{}, hi = <String, int>{};
    anchorOf.forEach((anchor, item) {
      final p = pos[anchor];
      if (p == null) return;
      final l = lo[item];
      if (l == null || p < l) lo[item] = p;
      final h = hi[item];
      if (h == null || p > h) hi[item] = p;
    });

    final rows = <OutlineRow>[];
    final itemChapter = <String, int>{};
    var prev = -1;
    var curChapter = -1, curSection = -1;
    for (final id in itemIds) {
      // An item that the transcript placed before an earlier one stays after
      // it, so the rows never return to a chapter or section they left.
      final l = max(lo[id] ?? prev, prev);
      final h = max(hi[id] ?? l, l);
      prev = l;
      final ch = l < 0 ? -1 : _chapterAt(chapterSpans, l);
      final sec = _sectionAt(sectionSpans, ch, l);
      itemChapter[id] = ch;
      if (ch != curChapter) {
        curChapter = ch;
        curSection = -1;
        if (ch >= 0) {
          final c = chapters[ch];
          rows.add(ChapterRow('chap:${c.id}', chapter: ch, folded: folded(c)));
        }
      }
      // An item is hidden only when every anchor it holds is inside a folded
      // chapter. A turn that runs into the next chapter stays visible.
      final span = ch >= 0 ? chapterSpans[ch] : null;
      final hidden =
          span != null && folded(chapters[ch]) && l >= span.$1 && h <= span.$2;
      if (hidden) continue;
      if (ch >= 0 && !folded(chapters[ch]) && sec >= 0 && sec != curSection) {
        rows.add(
          SectionRow(
            'sec:${chapters[ch].sections[sec].id}',
            chapter: ch,
            section: sec,
          ),
        );
      }
      curSection = sec;
      rows.add(ItemRow('item:$id', id, chapter: ch, section: sec));
    }

    final rowOf = <String, int>{
      for (var i = 0; i < rows.length; i++) rows[i].key: i,
    };
    return OutlineLayout._(rows, rowOf, itemChapter, anchorIds, pos, anchorOf);
  }

  /// The row index for a row key, or null when that row is not shown.
  int? rowIndex(String key) => _rowOf[key];

  static String itemKey(String itemId) => 'item:$itemId';

  /// First anchor carried by an item, for preserving a plain chat's place.
  String? firstAnchorFor(String itemId) => _firstByItem[itemId];

  late final Map<String, String> _firstByItem = () {
    final first = <String, String>{};
    for (final id in _anchorIds) {
      final item = _anchorOf[id];
      if (item != null) first.putIfAbsent(item, () => id);
    }
    return first;
  }();

  /// The jump target for the span [first]..[last]: the item of its first
  /// anchor that is shown in the transcript (an anchor with no shown item is
  /// skipped), or null when no anchor in the span is shown.
  OutlineTarget? target(String first, String last) {
    final span = _span(_pos, first, last);
    if (span == null) return null;
    for (var p = span.$1; p <= span.$2; p++) {
      final item = _anchorOf[_anchorIds[p]];
      if (item != null && _itemChapter.containsKey(item)) {
        return OutlineTarget(item, _itemChapter[item]!);
      }
    }
    return null;
  }

  /// The row keys of the items that hold anchors in the span, for flashing
  /// the target after a jump.
  Set<String> spanKeys(String first, String last) {
    final span = _span(_pos, first, last);
    if (span == null) return {};
    return {
      for (var p = span.$1; p <= span.$2; p++)
        if (_anchorOf[_anchorIds[p]] case final item?) itemKey(item),
    };
  }

  /// The chapter an item sits in (-1 when none), for hidden items too.
  int chapterOfItem(String itemId) => _itemChapter[itemId] ?? -1;
}

/// The first and last anchors' positions, ordered, or null when neither id is
/// known.
(int, int)? _span(Map<String, int> pos, String first, String last) {
  final a = pos[first] ?? pos[last], b = pos[last] ?? pos[first];
  if (a == null || b == null) return null;
  return a <= b ? (a, b) : (b, a);
}

/// The index of the chapter whose span holds position [p], or -1.
int _chapterAt(List<(int, int)?> spans, int p) {
  for (var i = 0; i < spans.length; i++) {
    final s = spans[i];
    if (s != null && p >= s.$1 && p <= s.$2) return i;
  }
  return -1;
}

/// The index of section [ch]'s span that holds position [p], or -1.
int _sectionAt(List<List<(int, int)?>> sectionSpans, int ch, int p) {
  if (ch < 0) return -1;
  final spans = sectionSpans[ch];
  for (var j = 0; j < spans.length; j++) {
    final s = spans[j];
    if (s != null && p >= s.$1 && p <= s.$2) return j;
  }
  return -1;
}
