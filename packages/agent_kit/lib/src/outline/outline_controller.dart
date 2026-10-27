// Where the reader is in an outlined transcript and how it moves: the list's
// scroll position, the fold state, the chapter and section at the top, and the
// jumps to a span, a chapter or a section. The host owns one per chat and
// feeds it the outline on every build with [OutlineController.sync].

import 'package:flutter/widgets.dart';

import 'anchored_list.dart';
import 'outline_fold.dart';
import 'outline_layout.dart';
import 'outline_model.dart';

/// Where the reader is: the chapter and section titles and ids at the top of
/// the transcript, or nulls above the first chapter.
typedef OutlineWhere = ({
  String? chapter,
  String? section,
  String? chapterId,
  String? sectionId,
});

class OutlineController {
  /// [vsync] drives the collapse animations, [mounted] says whether the host
  /// is still on screen and [update] is the host's `setState`.
  OutlineController({
    required TickerProvider vsync,
    required this.mounted,
    required this.update,
  }) {
    fold = OutlineFoldState(
      vsync: vsync,
      mounted: mounted,
      update: update,
      pinTop: () => list.pinTop(),
    );
  }

  final bool Function() mounted;
  final void Function(VoidCallback) update;

  /// What the reader has folded, opened and collapsed.
  late final OutlineFoldState fold;

  /// The outlined transcript, laid out by row index with anchors. Give it to
  /// the [AnchoredList] that shows [OutlineLayout.rows].
  final list = AnchoredListController();

  /// Where the reader is, for the where-am-I strip.
  final where = ValueNotifier<OutlineWhere>((
    chapter: null,
    section: null,
    chapterId: null,
    sectionId: null,
  ));

  /// The outline and layout of the last [sync]. Jumps and the strip read them.
  Outline outline = Outline.empty;
  OutlineLayout? layout;

  /// The rows a jump flashes, and which jump it was.
  Set<String> flashKeys = {};
  int flashToken = 0;

  /// Bumped by every navigation (a jump, a chapter opened or a fold by
  /// hand), so a position restore the host queued earlier can tell that it was
  /// overtaken.
  int positionRestore = 0;

  /// The row index at the top of the transcript, as the list reports it, and
  /// the first and last visible rows.
  int? _top;
  (int, int)? visibleRange;

  void dispose() {
    fold.dispose();
    list.dispose();
    where.dispose();
  }

  /// Forgets the place in the last chat: another chat is open.
  void reset() {
    fold.reset();
    flashKeys = {};
    _top = null;
    visibleRange = null;
    positionRestore++;
  }

  /// Lays out [outline] for this build and keys the rows. Call it from the
  /// host's `build`, before the list reads [layout]. [itemIds] are the
  /// transcript items in order, [anchorIds] the anchors in order and
  /// [anchorOf] maps each anchor id to the item that shows it. [topAnchorId]
  /// is the anchor at the top of the reader's view, when the host measures
  /// one: a chapter that closes around it stays open under its heading.
  OutlineLayout sync({
    required Outline outline,
    required List<String> itemIds,
    required List<String> anchorIds,
    required Map<String, String> anchorOf,
    String? topAnchorId,
  }) {
    fold.closeFolds(outline, chaptersInView(), anchorIds, topAnchorId);
    this.outline = outline;
    final built = OutlineLayout.build(
      outline: outline,
      itemIds: itemIds,
      anchorIds: anchorIds,
      anchorOf: anchorOf,
      folded: fold.hidden,
    );
    layout = built;
    fold.rekey(built, outline);
    if (!outline.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted()) refreshWhere();
      });
    }
    return built;
  }

  /// Shows or hides a chapter's messages from its card, and keeps the card in
  /// view.
  Future<void> toggleMessages(OutlineChapter chapter, bool shown) async {
    positionRestore++;
    update(() => fold.show(chapter, shown));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted()) return;
    final index = layout?.rowIndex('chap:${chapter.id}');
    if (index != null) list.jumpToIndex(index);
  }

  /// Shows the span from [first] to [last]. A hidden chapter is shown first,
  /// then the list jumps by row index to the span's first shown row (the
  /// section's divider when [sectionKey] names one) and flashes the span.
  Future<void> jump(String first, String last, {String? sectionKey}) async {
    positionRestore++;
    var layout = this.layout;
    var target = layout?.target(first, last);
    if (layout == null || target == null) return;
    if (target.chapter >= 0 && fold.hidden(outline.chapters[target.chapter])) {
      final hidden = outline.chapters[target.chapter];
      update(() => fold.show(hidden, true));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted()) return;
      layout = this.layout;
      target = layout?.target(first, last);
      if (layout == null || target == null) return;
    }
    final index =
        (sectionKey == null ? null : layout.rowIndex(sectionKey)) ??
        layout.rowIndex(OutlineLayout.itemKey(target.itemId));
    if (index == null) return;
    update(() {
      flashKeys = layout!.spanKeys(first, last);
      flashToken++;
    });
    list.jumpToIndex(index);
  }

  /// Jumps to a section from the contents or its card.
  Future<void> openSection(OutlineSection section) =>
      jump(section.first, section.last, sectionKey: 'sec:${section.id}');

  /// Shows a chapter from the contents: a closed chapter's messages are shown
  /// under its card, and the list jumps to the card or heading.
  Future<void> openChapter(OutlineChapter chapter) async {
    positionRestore++;
    final key = 'chap:${chapter.id}';
    if (fold.hidden(chapter)) {
      update(() => fold.show(chapter, true));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted()) return;
    }
    final index = layout?.rowIndex(key);
    if (index == null) return;
    update(() {
      flashKeys = {key};
      flashToken++;
    });
    list.jumpToIndex(index);
  }

  /// Called by the list when the visible rows change: reads the chapter and
  /// section at the top into the where-am-I strip and folds deferred chapters
  /// the reader has left.
  void onVisible(int first, int last) {
    _top = first;
    visibleRange = (first, last);
    refreshWhere();
    fold.foldAwayFromDeferred(chaptersInView);
  }

  void refreshWhere() {
    final layout = this.layout;
    final top = _top;
    final OutlineRow? row =
        layout != null && top != null && top < layout.rows.length
        ? layout.rows[top]
        : null;
    final chapter = row == null || row.chapter < 0
        ? null
        : outline.chapters[row.chapter];
    final section = chapter == null || row!.section < 0
        ? null
        : chapter.sections[row.section];
    final next = (
      chapter: chapter?.title,
      section: section?.title,
      chapterId: chapter?.id,
      sectionId: section?.id,
    );
    if (where.value != next) where.value = next;
  }

  /// The first anchor ids of the chapters with a row on screen, in the last
  /// layout.
  Set<String> chaptersInView() {
    final layout = this.layout, range = visibleRange;
    if (layout == null || range == null || layout.rows.isEmpty) return {};
    final last = range.$2 < layout.rows.length
        ? range.$2
        : layout.rows.length - 1;
    final out = <String>{};
    for (var i = range.$1; i <= last; i++) {
      final ch = layout.rows[i].chapter;
      if (ch >= 0 && ch < outline.chapters.length) {
        out.add(outline.chapters[ch].first);
      }
    }
    return out;
  }
}
