// The chat header (`.hdr` in the mockup's app.css): a neutral session tile,
// the title, the status pill, the branch, the context meter, the workspace
// layout toggle and the session menu. Narrow widths drop the tile, the branch
// and the meter's label together, as the mockup does when compact; the title
// and branch truncate before that.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary, Usage;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'chrome_button.dart';
import 'chrome_format.dart';
import 'chrome_icons.dart';
import 'rail_layout.dart';

/// One entry of the session menu.
@immutable
class ChromeMenuItem {
  const ChromeMenuItem(
    this.label,
    this.onTap, {
    this.glyph,
    this.danger = false,
    this.separatorBefore = false,
  });

  final String label;
  final VoidCallback onTap;
  final LucideGlyph? glyph;
  final bool danger;
  final bool separatorBefore;
}

/// The chat header. [chat] gives the title and the status; [branch] and
/// [worktree] (the branch's tooltip) come from the snapshot's workspace and
/// [usage] feeds the context meter.
///
/// [onToggleWorkspace] adds the layout toggle (pressed while
/// [workspaceShown]); [menuItems] fill the session menu. Inside a
/// `RailLayout` the header also shows a `RailShowButton` at its left.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.chat,
    this.branch,
    this.worktree,
    this.usage,
    this.statusDetail,
    this.workspaceShown = false,
    this.onToggleWorkspace,
    this.menuItems = const [],
    this.hideEmptyMenu = false,
  });

  final ChatSummary chat;
  final String? branch;
  final String? worktree;
  final Usage? usage;

  /// Text after the pill's label ("Running · 3 agents").
  final String? statusDetail;
  final bool workspaceShown;
  final VoidCallback? onToggleWorkspace;
  final List<ChromeMenuItem> menuItems;

  /// Leaves the ⋯ button out when there are no [menuItems], instead of
  /// drawing it disabled.
  final bool hideEmptyMenu;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final touch = theme.formFactor == FormFactor.mobile;
    final button = touch ? 40.0 : 32.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.hasBoundedWidth &&
            constraints.maxWidth < theme.sizeMedium;
        final gap = narrow ? 6.0 : 8.0;
        final fraction = usage?.contextFraction;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colors.borderSubtle),
            ),
          ),
          child: SizedBox(
            height: narrow ? 52 : Layout.topbarHeight,
            child: Padding(
              padding: narrow
                  ? const EdgeInsets.symmetric(horizontal: 8)
                  : const EdgeInsets.fromLTRB(16, 0, 10, 0),
              child: Row(
                children: [
                  RailShowButton(gap: gap, size: button),
                  Expanded(
                    child: Row(
                      children: [
                        if (!narrow) ...[const _Tile(), SizedBox(width: gap)],
                        Flexible(
                          child: Text(
                            chat.title,
                            style: ts(
                              theme.typeScale.ui,
                              theme.ink,
                              weight: 700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: gap),
                        StatusMark.pill(chat.status, detail: statusDetail),
                        if (!narrow && branch != null) ...[
                          SizedBox(width: gap),
                          Flexible(
                            child: _Branch(branch: branch!, worktree: worktree),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (fraction != null)
                    ContextMeter(
                      fraction: fraction,
                      contextTokens: usage?.contextTokens,
                      contextLimit: usage?.contextLimit,
                      showLabel: !narrow,
                    ),
                  if (onToggleWorkspace != null)
                    ChromeIconButton(
                      glyphLayoutPanelLeft,
                      key: const ValueKey('header-workspace'),
                      label: 'Workspace',
                      size: button,
                      selected: workspaceShown,
                      toggled: workspaceShown,
                      onTap: onToggleWorkspace,
                    ),
                  if (!hideEmptyMenu || menuItems.isNotEmpty)
                    Builder(
                      builder: (buttonContext) => ChromeIconButton(
                        glyphEllipsis,
                        key: const ValueKey('header-menu'),
                        label: 'Session menu',
                        size: button,
                        glyphSize: 20,
                        onTap: menuItems.isEmpty
                            ? null
                            : () => _openMenu(buttonContext),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openMenu(BuildContext buttonContext) {
    showPopover<void>(
      buttonContext,
      globalRectOf(buttonContext),
      (menuContext) => MenuList(
        width: 220,
        children: [
          for (final item in menuItems) ...[
            if (item.separatorBefore) const MenuSeparator(),
            MenuItem(
              label: item.label,
              danger: item.danger,
              leading: item.glyph == null
                  ? null
                  : ChromeIcon(
                      item.glyph!,
                      size: 18,
                      color: item.danger
                          ? menuContext.colors.inlineCodeText
                          : menuContext.colors.iconPrimary,
                    ),
              onTap: () {
                Navigator.of(menuContext).pop();
                item.onTap();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The neutral session icon: surface, seam border, ink glyph.
class _Tile extends StatelessWidget {
  const _Tile();

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ExcludeSemantics(
      child: SizedBox(
        width: 22,
        height: 22,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.seam),
          ),
          child: Center(
            child: ChromeIcon(glyphMessageSquare, size: 14, color: theme.ink),
          ),
        ),
      ),
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.branch, this.worktree});

  final String branch;
  final String? worktree;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return chromeTooltip(
      context,
      worktree ?? branch,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChromeIcon(glyphGitBranch, size: 14, color: theme.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              branch,
              style: ts(const TypeSpec(12, 16, 400), theme.muted, mono: true),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The context meter: "38% context" and a thin bar. [showLabel] false leaves
/// the bar alone (narrow headers). The tooltip says "Context: 38% of 128k"
/// when the token figures are known.
class ContextMeter extends StatelessWidget {
  const ContextMeter({
    super.key,
    required this.fraction,
    this.contextTokens,
    this.contextLimit,
    this.showLabel = true,
  });

  /// The fill, 0 to 1 (`Usage.contextFraction`).
  final double fraction;
  final int? contextTokens;
  final int? contextLimit;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final percent = (fraction * 100).round();
    final tip = contextLimit == null
        ? 'Context: $percent%'
        : 'Context: $percent% of ${formatTokens(contextLimit!)}';
    return chromeTooltip(
      context,
      tip,
      Semantics(
        label: '$percent% context used',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel) ...[
                Text(
                  '$percent% context',
                  style: ts(theme.typeScale.uiSmall, theme.faint),
                  maxLines: 1,
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 40,
                height: 2,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: theme.seam,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: ColoredBox(color: theme.threadStrong),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
