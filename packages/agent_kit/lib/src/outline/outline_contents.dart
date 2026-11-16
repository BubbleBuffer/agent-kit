// The outline's contents sheet and the menu of a chapter or a section. The
// host decides what a tap on either does.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/kit_tokens.dart';
import '../theme/theme.dart';
import 'decision_line.dart';
import 'outline_chapter_widgets.dart';
import 'outline_controller.dart';
import 'outline_model.dart';

/// The contents: every chapter with its decision and sections, and the place
/// the reader is. On a phone it is a bottom sheet (70 % of the screen); on
/// desktop a centred panel. A tap closes the contents and calls [onChapter] or
/// [onSection].
Future<void> showOutlineContents(
  BuildContext context, {
  required Outline outline,
  required OutlineWhere where,
  required ValueChanged<OutlineChapter> onChapter,
  required void Function(OutlineChapter chapter, OutlineSection section)
  onSection,
}) => showPickerSheet<void>(
  context,
  (ctx) => _contents(
    ctx,
    outline: outline,
    where: where,
    onChapter: (chapter) {
      Navigator.of(ctx).pop();
      onChapter(chapter);
    },
    onSection: (chapter, section) {
      Navigator.of(ctx).pop();
      onSection(chapter, section);
    },
  ),
  desktopWidth: KitSizes.contents.width,
  desktopHeight: KitSizes.contents.height,
  shrink: false,
  sheetHeightFactor: KitSizes.contents.sheetShare,
);

PickerSheet _contents(
  BuildContext context, {
  required Outline outline,
  required OutlineWhere where,
  required ValueChanged<OutlineChapter> onChapter,
  required void Function(OutlineChapter chapter, OutlineSection section)
  onSection,
}) {
  final t = context.bb;
  final c = t.colors;
  final ty = t.typeScale;
  final count = outline.chapters.length;
  return PickerSheet(
    key: const ValueKey('outline-contents'),
    listHeight: null,
    listPadding: const EdgeInsets.only(bottom: Space.md),
    listKey: const ValueKey('outline-contents-scroll'),
    header: SheetHeader(
      'Contents · $count ${count == 1 ? 'chapter' : 'chapters'}',
    ),
    list: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (ci, chapter) in outline.chapters.indexed) ...[
          MarkedRow(
            key: ValueKey('outline-contents-chapter-${chapter.id}'),
            onTap: () => onChapter(chapter),
            label: chapter.title,
            colour: outlineColor(context, ci),
            dot: true,
            small: true,
            oneLine: true,
            labelStyle: ts(ty.ui, c.textPrimary, weight: Weight.semibold),
            padding: const EdgeInsets.fromLTRB(
              Layout.gutter,
              Space.sm,
              Layout.gutter,
              Space.xxs,
            ),
            trailing: where.chapterId == chapter.id && where.sectionId == null
                ? const _HereTag()
                : null,
            detail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (chapter.when.isNotEmpty) chapter.when,
                    outlineCountLine(chapter),
                  ].join(' · '),
                  style: ts(ty.uiSmall, c.textTertiary),
                ),
                if (chapter.decision != null) ...[
                  const Gap(Space.hair),
                  DecisionLine(
                    chapter.decision!,
                    peek: true,
                    color: c.textSecondary,
                  ),
                ] else if (chapter.gist != null) ...[
                  const Gap(Space.hair),
                  Text(
                    chapter.gist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(ty.uiSmall, c.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          for (final (si, section) in chapter.sections.indexed)
            MarkedRow(
              key: ValueKey('outline-contents-section-${section.id}'),
              onTap: () => onSection(chapter, section),
              label: section.title,
              colour: outlineColor(context, si + 1),
              small: true,
              oneLine: true,
              labelStyle: ts(
                ty.uiSmall,
                c.textPrimary,
                weight: where.sectionId == section.id
                    ? Weight.semibold
                    : Weight.regular,
              ),
              padding: const EdgeInsets.fromLTRB(
                Layout.gutter + Space.lg,
                Space.xs,
                Layout.gutter,
                Space.xs,
              ),
              trailing: where.sectionId == section.id ? const _HereTag() : null,
            ),
        ],
      ],
    ),
  );
}

class _HereTag extends StatelessWidget {
  const _HereTag();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Space.sm),
    child: Text(
      "you're here",
      style: ts(context.bb.typeScale.uiSmall, context.bb.colors.accentText),
    ),
  );
}

/// The menu of a chapter or a section: the host's [actions] as sheet rows.
/// Each row closes the sheet first.
Future<void> showOutlineMenu(
  BuildContext context, {
  required List<OutlineAction> actions,
}) => showSheet<void>(
  context,
  (ctx) => SheetSurface(
    children: [
      for (final (i, action) in actions.indexed)
        SheetItem(
          key: ValueKey('outline-menu-action-$i'),
          label: action.label,
          icon: action.icon,
          onTap: () {
            Navigator.of(ctx).pop();
            action.onSelected();
          },
        ),
    ],
  ),
);
