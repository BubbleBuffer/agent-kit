// The composer's pick buttons (model, workspace): a muted label with a
// chevron (`.select`) that opens a menu of KitChoices under or above it.

import 'package:agent_kit_core/agent_kit_core.dart' show KitChoice;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'composer_parts.dart';

/// A pick button: shows the selected choice's label (truncated first when
/// the bar is tight) and opens a menu of [choices]. The menu is a popover
/// from `bb_ui`, so a Navigator must sit above the composer.
class ComposerPick extends StatelessWidget {
  const ComposerPick({
    super.key,
    required this.title,
    required this.choices,
    required this.onSelected,
    this.selectedId,
    this.placeholder,
  });

  /// What the pick chooses ("Model", "Workspace"): the menu header and the
  /// semantics label.
  final String title;

  /// What can be picked.
  final List<KitChoice> choices;

  /// The id of the current choice.
  final String? selectedId;

  /// Shown when [selectedId] matches nothing.
  final String? placeholder;

  /// Called with the picked choice.
  final ValueChanged<KitChoice> onSelected;

  KitChoice? get _selected {
    for (final c in choices) {
      if (c.id == selectedId) return c;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final anchor = globalRectOf(context);
    final picked = await showPopover<KitChoice>(
      context,
      anchor,
      (menu) => MenuList(
        width: 260,
        header: title,
        children: [
          for (final c in choices)
            MenuItem(
              label: c.label,
              selected: c.id == selectedId,
              trailing: c.detail == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        c.detail!,
                        maxLines: 1,
                        style: ts(
                          menu.bb.typeScale.uiSmall,
                          menu.bb.faint,
                          weight: 400,
                        ),
                      ),
                    ),
              onTap: () => Navigator.of(menu).pop(c),
            ),
        ],
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final current = _selected;
    final text = current?.label ?? placeholder ?? title;
    final h = isTouch(t) ? 40.0 : 28.0;
    return Builder(
      builder: (context) => Semantics(
        button: true,
        label: '$title: $text',
        excludeSemantics: true,
        onTap: choices.isEmpty ? null : () => _open(context),
        child: Hover(
          onTap: choices.isEmpty ? null : () => _open(context),
          borderRadius: BorderRadius.circular(t.radii.md),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: h,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ts(t.typeScale.ui, t.muted),
                  ),
                ),
                const SizedBox(width: 4),
                const KitIcon(ComposerGlyphs.chevronDown),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
