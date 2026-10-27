// The outline's chapter parts in the transcript: a closed chapter's folding
// card, the heading of an open chapter and section dividers with their menu
// button. The host lays them out (see outline_layout.dart) and supplies what
// its own actions do; the kit renders them and never knows what they are.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'decision_line.dart';
import 'outline_model.dart';

/// An action a host adds to the outline: a row in a chapter or section menu,
/// or a button on an open card. The kit shows [label] (and [icon] in a menu)
/// and calls [onSelected]; it never knows what the action does.
@immutable
class OutlineAction {
  const OutlineAction({
    required this.label,
    required this.onSelected,
    this.icon,
  });
  final String label;
  final Ico? icon;
  final VoidCallback onSelected;
}

/// The chapter's colour: a small patch, as spaces use. Chapters and sections
/// take colours in turn so neighbours differ.
Color outlineColor(BuildContext context, int index) {
  final c = context.bb.colors;
  return spaceColor(
        spaceColorNames[index % spaceColorNames.length],
        c.dark ? Brightness.dark : Brightness.light,
      ) ??
      c.accent;
}

/// A closed chapter: one folding card, with the decision (or a gist line) on
/// its face. Opening it shows the summary, decision and sections; the foot
/// holds the count, the host's [actions] (while open) and the message toggle.
/// The card stays above its messages when they are shown.
class OutlineChapterCard extends StatelessWidget {
  const OutlineChapterCard({
    super.key,
    required this.chapter,
    required this.color,
    required this.messagesShown,
    required this.onToggleMessages,
    required this.onOpenSection,
    this.actions = const [],
    this.open,
    this.onOpenChanged,
  });
  final OutlineChapter chapter;
  final Color color;
  final bool messagesShown;
  final VoidCallback onToggleMessages;
  final ValueChanged<OutlineSection> onOpenSection;

  /// Host actions, shown in the foot while the card is open.
  final List<OutlineAction> actions;
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    final ty = t.typeScale;
    final decision = chapter.decision;
    final gist = chapter.gist;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FoldableStackCard(
        faceKey: ValueKey('outline-card-face-${chapter.id}'),
        edge: color,
        label: _chapterLabel(chapter, closed: true),
        title: chapter.title,
        titleMaxLines: 1,
        stacked: true,
        open: open,
        onOpenChanged: onOpenChanged,
        peek: decision != null
            ? DecisionLine(decision, peek: true, color: c.textSecondary)
            : gist == null
            ? null
            : Text(
                gist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                key: ValueKey('outline-card-gist-${chapter.id}'),
                style: ts(ty.uiSmall, c.textSecondary),
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chapter.summary.isNotEmpty)
              Text(chapter.summary, style: ts(ty.body, c.textPrimary)),
            if (decision != null) ...[
              const SizedBox(height: 8),
              DecisionLine(decision),
            ],
            if (chapter.sections.isNotEmpty) ...[
              const SizedBox(height: 4),
              MarkedList(
                rows: [
                  for (final (i, s) in chapter.sections.indexed)
                    MarkedRow(
                      key: ValueKey('outline-card-section-${s.id}'),
                      onTap: () => onOpenSection(s),
                      label: s.title,
                      colour: outlineColor(context, i + 1),
                    ),
                ],
              ),
            ],
          ],
        ),
        footer: (open) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  outlineCountLine(chapter),
                  style: ts(ty.uiSmall, c.textTertiary),
                ),
              ),
              if (open)
                for (final (i, action) in actions.indexed) ...[
                  FooterAction(
                    key: ValueKey('outline-card-action-${chapter.id}-$i'),
                    label: action.label,
                    onTap: action.onSelected,
                  ),
                  const SizedBox(width: 6),
                ],
              FooterAction(
                key: ValueKey('outline-card-show-${chapter.id}'),
                label: messagesShown ? 'Hide messages' : 'Show messages',
                onTap: onToggleMessages,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The heading of a chapter whose messages show: an open chapter, or a closed
/// one that was unfolded. [closed] adds a quiet "Chapter closed · Fold"
/// action that calls [onFold]. [onMenu] opens the host's menu; the button is
/// left out without it.
class OutlineChapterHeading extends StatelessWidget {
  const OutlineChapterHeading({
    super.key,
    required this.chapter,
    required this.color,
    this.onMenu,
    this.closed = false,
    this.onFold,
  });
  final OutlineChapter chapter;
  final Color color;
  final VoidCallback? onMenu;
  final bool closed;
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (closed)
                Hover(
                  key: ValueKey('outline-chapter-fold-${chapter.id}'),
                  onTap: onFold,
                  child: Text(
                    'Chapter closed · Fold',
                    style: ts(t.typeScale.uiSmall, c.textTertiary),
                  ),
                )
              else
                Text(
                  _chapterLabel(chapter, closed: false),
                  style: ts(t.typeScale.uiSmall, c.textTertiary),
                ),
              Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tsDisplay(t.typeScale.h2, c.textPrimary),
              ),
            ],
          ),
        ),
        if (onMenu != null)
          OutlineMoreButton(
            key: ValueKey('outline-chapter-menu-${chapter.id}'),
            onTap: onMenu!,
          ),
      ],
    );
  }
}

/// A section's dashed divider in the transcript, with its menu. [onMenu]
/// opens the host's menu; the button is left out without it.
class OutlineSectionDivider extends StatelessWidget {
  const OutlineSectionDivider({
    super.key,
    required this.section,
    required this.color,
    this.onMenu,
  });
  final OutlineSection section;
  final Color color;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    return Row(
      children: [
        Container(
          width: 4,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            section.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(t.typeScale.uiSmall, c.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CustomPaint(
            size: const Size(double.infinity, 1),
            painter: _DashedLinePainter(c.borderSubtle),
          ),
        ),
        if (onMenu != null)
          OutlineMoreButton(
            key: ValueKey('outline-section-menu-${section.id}'),
            onTap: onMenu!,
          ),
      ],
    );
  }
}

/// The "More" button of a chapter heading or a section divider.
class OutlineMoreButton extends StatelessWidget {
  const OutlineMoreButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'More',
    child: AppTooltip(
      label: 'More',
      child: Hover(
        onTap: onTap,
        radius: Radii.md,
        padding: const EdgeInsets.all(4),
        child: Icon20(
          Ico.more,
          size: 16,
          color: context.bb.colors.iconTertiary,
        ),
      ),
    ),
  );
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 4, 0.5), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

String _sectionCount(OutlineChapter chapter) {
  final n = chapter.sections.length;
  return '$n ${n == 1 ? 'section' : 'sections'}';
}

String _messageCount(OutlineChapter chapter) {
  final n = chapter.messageCount;
  return '$n ${n == 1 ? 'message' : 'messages'}';
}

/// "12 messages · 3 sections" under a card and in the contents.
String outlineCountLine(OutlineChapter chapter) =>
    '${_messageCount(chapter)} · ${_sectionCount(chapter)}';

String _chapterLabel(OutlineChapter chapter, {required bool closed}) {
  final parts = [
    'Chapter',
    if (chapter.when.isNotEmpty) chapter.when,
    if (chapter.ongoing) 'ongoing' else if (closed) 'closed',
  ];
  return parts.join(' · ');
}
