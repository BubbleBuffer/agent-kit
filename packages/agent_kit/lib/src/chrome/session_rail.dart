// The session rail: project switcher, search, grouped session rows and the
// settings footer (`.rail*` and `.rr-*` in the mockup's app.css). It follows
// the theme: light in light mode, dark in dark mode (NOTES.md, departure 2).
// Showing and hiding it is RailLayout's job; the rail only draws itself.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'chrome_button.dart';
import 'chrome_format.dart';
import 'chrome_icons.dart';
import 'rail_model.dart';

/// The rail, as wide as its parent makes it (240 px beside the sheet, the
/// full width as a sliding screen).
///
/// [groups] are the rows (see `groupSessions`); [detailFor] gives the text
/// after a row's status label, `railDetail` by default. Inside a
/// `RailLayout` the hide button hides the rail and, in compact, picking a
/// row closes the sliding screen; outside one, pass [onHide].
class SessionRail extends StatelessWidget {
  const SessionRail({
    super.key,
    required this.workspaceName,
    required this.groups,
    this.selectedId,
    this.detailFor,
    this.now,
    this.initials = '',
    this.onSelect,
    this.onNewChat,
    this.onSearch,
    this.onSwitchWorkspace,
    this.onSettings,
    this.onHide,
  });

  /// The project switcher's label.
  final String workspaceName;
  final List<SessionGroup> groups;

  /// The id of the open chat; its row is selected.
  final String? selectedId;

  /// The text after a row's status label, such as `edit approval`.
  final String? Function(ChatSummary chat)? detailFor;

  /// The clock for ages; the real time by default.
  final DateTime? now;

  /// The avatar's letters.
  final String initials;

  final ValueChanged<ChatSummary>? onSelect;
  final VoidCallback? onNewChat;
  final VoidCallback? onSearch;
  final VoidCallback? onSwitchWorkspace;
  final VoidCallback? onSettings;

  /// Overrides what the hide button does.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final scope = RailScope.maybeOf(context);
    final clock = now ?? DateTime.now();
    final hide =
        onHide ??
        (scope == null ? null : () => scope.controller.hide(scope.sizeClass));
    void select(ChatSummary chat) {
      onSelect?.call(chat);
      if (scope != null && scope.sizeClass.isCompact) {
        scope.controller.open = false;
      }
    }

    return Semantics(
      container: true,
      label: 'Sessions',
      child: ColoredBox(
        color: theme.rail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _WorkspaceButton(
                      name: workspaceName,
                      onTap: onSwitchWorkspace,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ChromeIconButton(
                    glyphSquarePen,
                    key: const ValueKey('rail-new-chat'),
                    label: 'New session',
                    onTap: onNewChat,
                    color: theme.railInk,
                    hoverColor: theme.railHover,
                  ),
                  const SizedBox(width: 2),
                  ChromeIconButton(
                    glyphPanelLeftClose,
                    key: const ValueKey('rail-hide'),
                    label: 'Hide sidebar',
                    shortcut: 'Ctrl+B',
                    onTap: hide,
                    color: theme.railInk,
                    hoverColor: theme.railHover,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _SearchRow(onTap: onSearch),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final group in groups) ...[
                    _GroupLabel(group.label),
                    for (final chat in group.chats)
                      SessionRow(
                        key: ValueKey('rail-row-${chat.id}'),
                        chat: chat,
                        detail: detailFor != null
                            ? detailFor!(chat)
                            : railDetail(chat, clock),
                        selected: chat.id == selectedId,
                        onTap: () => select(chat),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.railLine)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(child: _SettingsLink(onTap: onSettings)),
                      const SizedBox(width: 8),
                      _Avatar(initials: initials),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the rail: the title and a status meta line, with Scratch's
/// pressed colour and an edge bar when [selected].
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.chat,
    this.detail,
    this.selected = false,
    this.onTap,
  });

  final ChatSummary chat;

  /// The text after the status label, such as `3 agents`.
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final title = ts(
      theme.typeScale.ui,
      theme.railInk.withValues(alpha: selected ? 1 : .86),
      weight: selected ? 700 : 500,
    );
    return Semantics(
      selected: selected,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Hover(
              onTap: onTap,
              borderRadius: theme.radii.ctl,
              selected: selected,
              selectedColor: theme.railSelected,
              hoverBackground: theme.railHover,
              pressedBackground: theme.railSelected,
              lift: 0,
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chat.title,
                    style: title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  StatusMark(chat.status, detail: detail),
                ],
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.railInk,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 30,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: ts(const TypeSpec(12, 16, 700), theme.railMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceButton extends StatelessWidget {
  const _WorkspaceButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: 'Switch project, $name',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('rail-workspace'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              ChromeIcon(glyphFolderPen, color: theme.railInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: ts(theme.typeScale.ui, theme.railInk, weight: 700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ChromeIcon(glyphChevronDown, size: 14, color: theme.railMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final showKey = theme.formFactor != FormFactor.mobile;
    return Semantics(
      button: true,
      label: 'Search',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('rail-search'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              ChromeIcon(glyphSearch, color: theme.railMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search',
                  style: ts(theme.typeScale.ui, theme.railMuted, weight: 500),
                  maxLines: 1,
                ),
              ),
              if (showKey)
                Text(
                  'Ctrl K',
                  style: ts(
                    const TypeSpec(11, 16, 400),
                    theme.railMuted.withValues(alpha: .85),
                    mono: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: 'Settings',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('rail-settings'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              ChromeIcon(glyphSettings, color: theme.railMuted),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: ts(theme.typeScale.ui, theme.railMuted, weight: 500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final letters = theme.brightness == Brightness.light
        ? theme.colors.bgPrimary
        : theme.colors.textPrimary;
    return ExcludeSemantics(
      child: SizedBox(
        width: 28,
        height: 28,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: spaceColor('moss', theme.brightness) ?? theme.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initials,
              style: ts(const TypeSpec(11, 11, 700), letters),
            ),
          ),
        ),
      ),
    );
  }
}
