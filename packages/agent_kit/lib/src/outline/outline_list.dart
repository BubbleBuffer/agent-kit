// The outlined transcript as a list: the rows of an [OutlineController]'s
// layout, each wrapped for its flash and collapse. A chat item is the host's
// widget; a chapter's card or heading and a section's divider are the kit's.
// The host decides what its own actions do and passes them in.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import 'anchored_list.dart';
import 'outline_chapter_widgets.dart';
import 'outline_contents.dart';
import 'outline_controller.dart';
import 'outline_fold.dart';
import 'outline_layout.dart';
import 'outline_location.dart';
import 'outline_model.dart';

/// The chapter and section colours the strip and rows use: one per chapter,
/// by chapter id.
Map<String, Color> outlineStripColors(
  BuildContext context,
  Outline outline,
) => {
  for (final (i, c) in outline.chapters.indexed) c.id: outlineColor(context, i),
};

extension OutlineControllerContents on OutlineController {
  /// Opens the contents sheet; a tap there shows the chapter or section.
  Future<void> showContents(BuildContext context) => showOutlineContents(
    context,
    outline: outline,
    where: where.value,
    onChapter: openChapter,
    onSection: (chapter, section) => openSection(section),
  );
}

/// The rows of [controller]'s layout in an [AnchoredList]. Rebuild it
/// whenever the controller's state changes (its `update` is the host's
/// `setState`) and after each [OutlineController.sync].
class OutlineList extends StatelessWidget {
  const OutlineList({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.chapterActions,
    this.sectionActions,
    this.cardActions,
    this.padding = EdgeInsets.zero,
    this.contentWidth = Layout.contentWidth,
    this.initialIndex,
    this.initialY = 0,
    this.initialGlobalY,
  });

  final OutlineController controller;

  /// The widget of a chat item. The kit keys nothing inside it.
  final Widget Function(BuildContext context, ItemRow row) itemBuilder;

  /// The host's menu entries of a chapter heading, of a section divider and
  /// the buttons on an open chapter card. A null or empty list leaves out the
  /// menu button (or the card's buttons).
  final List<OutlineAction> Function(OutlineChapter chapter)? chapterActions;
  final List<OutlineAction> Function(
    OutlineChapter chapter,
    OutlineSection section,
  )?
  sectionActions;
  final List<OutlineAction> Function(OutlineChapter chapter)? cardActions;

  final EdgeInsets padding;

  /// The content column's largest width; rows are centred in it.
  final double contentWidth;

  /// Where the list starts, as [AnchoredList] reads them.
  final int? initialIndex;
  final double initialY;
  final double? initialGlobalY;

  @override
  Widget build(BuildContext context) {
    final layout = controller.layout;
    if (layout == null) return const SizedBox.shrink();
    final fold = controller.fold;
    return AnchoredList(
      controller: controller.list,
      itemCount: layout.rows.length,
      padding: padding,
      onVisibleRangeChanged: controller.onVisible,
      keyOf: (i) => i < fold.stableKeys.length ? fold.stableKeys[i] : null,
      indexOf: fold.indexOfKey,
      initialIndex: initialIndex,
      initialY: initialY,
      initialGlobalY: initialGlobalY,
      itemBuilder: (context, i) => _rowView(context, layout.rows[i]),
    );
  }

  /// The row widget for [row]: the chat item, a chapter's card or heading, or
  /// a section divider.
  Widget _rowView(BuildContext context, OutlineRow row) {
    final outline = controller.outline;
    final fold = controller.fold;
    final Widget child = switch (row) {
      final ItemRow item => itemBuilder(context, item),
      ChapterRow(:final folded) => _chapterRow(
        context,
        outline.chapters[row.chapter],
        row.chapter,
        folded,
      ),
      final SectionRow section => _sectionRow(context, section, outline),
    };
    final view = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: controller.flashKeys.contains(row.key)
              ? OutlineFlash(token: controller.flashToken, child: child)
              : child,
        ),
      ),
    );
    if (row is! ItemRow) return view;
    // A collapsing chapter's messages shrink to nothing. Every item row keeps
    // this wrapper, at full size when not collapsing, so the row's subtree does
    // not change shape when a collapse starts.
    final chapter = row.chapter >= 0 && row.chapter < outline.chapters.length
        ? outline.chapters[row.chapter].first
        : null;
    final Animation<double> collapse =
        (chapter == null ? null : fold.collapsing[chapter]) ??
        OutlineFoldState.full;
    return SizeTransition(
      sizeFactor: collapse,
      alignment: Alignment.topCenter,
      child: view,
    );
  }

  Widget _sectionRow(BuildContext context, SectionRow row, Outline outline) {
    final chapter = outline.chapters[row.chapter];
    final section = chapter.sections[row.section];
    final actions = sectionActions?.call(chapter, section) ?? const [];
    return OutlineSectionDivider(
      key: ValueKey('outline-section-${row.key}'),
      section: section,
      color: outlineColor(context, row.section + 1),
      onMenu: actions.isEmpty
          ? null
          : () => showOutlineMenu(context, actions: actions),
    );
  }

  Widget _chapterRow(
    BuildContext context,
    OutlineChapter chapter,
    int index,
    bool folded,
  ) {
    final fold = controller.fold;
    final color = outlineColor(context, index);
    final actions = chapterActions?.call(chapter) ?? const [];
    VoidCallback? menu() => actions.isEmpty
        ? null
        : () => showOutlineMenu(context, actions: actions);
    if (chapter.ongoing) {
      return OutlineChapterHeading(
        key: ValueKey('outline-chapter-${chapter.id}'),
        chapter: chapter,
        color: color,
        onMenu: menu(),
      );
    }
    if (fold.deferred.contains(chapter.first)) {
      return OutlineChapterHeading(
        key: ValueKey('outline-chapter-${chapter.id}'),
        chapter: chapter,
        color: color,
        onMenu: menu(),
        closed: true,
        onFold: () => fold.foldNow(chapter.first),
      );
    }
    final shown = !folded && !fold.collapsing.containsKey(chapter.first);
    return OutlineChapterCard(
      key: ValueKey('outline-chapter-${chapter.id}'),
      chapter: chapter,
      color: color,
      messagesShown: shown,
      onToggleMessages: () => controller.toggleMessages(chapter, !shown),
      actions: cardActions?.call(chapter) ?? const [],
      onOpenSection: controller.openSection,
      open: fold.expanded[chapter.first] ?? false,
      onOpenChanged: (open) =>
          controller.update(() => fold.expanded[chapter.first] = open),
    );
  }
}
