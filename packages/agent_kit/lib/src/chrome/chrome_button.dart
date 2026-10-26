// A square icon button for the chrome (rail header, chat header). Not
// exported from the barrel.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'chrome_icons.dart';

/// [child] with a tooltip, when there is an Overlay to draw it in (a bare
/// preview or a golden without a Navigator has none).
Widget chromeTooltip(
  BuildContext context,
  String label,
  Widget child, {
  String? shortcut,
}) => Overlay.maybeOf(context) == null
    ? child
    : AppTooltip(label: label, shortcut: shortcut, child: child);

/// A [size] square button with a [glyph]; hover tints it with [hoverColor]
/// (the theme's hover by default) and [selected] with the pressed colour.
class ChromeIconButton extends StatelessWidget {
  const ChromeIconButton(
    this.glyph, {
    super.key,
    required this.label,
    required this.onTap,
    this.size = 32,
    this.glyphSize = 18,
    this.color,
    this.hoverColor,
    this.selected = false,
    this.toggled,
    this.shortcut,
  });

  final LucideGlyph glyph;

  /// The semantics label and the tooltip.
  final String label;
  final VoidCallback? onTap;
  final double size, glyphSize;
  final Color? color, hoverColor;
  final bool selected;

  /// Set for a toggle button: its pressed state, for semantics.
  final bool? toggled;

  /// A keyboard hint for the tooltip, such as `Ctrl+B`.
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final button = Semantics(
      button: true,
      toggled: toggled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        selected: selected,
        selectedColor: theme.pressed,
        hoverBackground: hoverColor ?? theme.hover,
        pressedBackground: theme.pressed,
        lift: 0,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: ChromeIcon(
              glyph,
              size: glyphSize,
              color: color ?? theme.colors.iconSecondary,
            ),
          ),
        ),
      ),
    );
    return chromeTooltip(context, label, button, shortcut: shortcut);
  }
}
