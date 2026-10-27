// The kit's one way to draw a Lucide glyph: the stroke weight is picked for the
// size so the visual stroke is 1.5 px. Each caller keeps its own contract
// (default colour, semantics, hit area); only the drawing is shared.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// The visual stroke of the kit's icons, in logical pixels.
const double kKitIconStroke = 1.5;

/// [glyph] at [size] in [color], at the kit's stroke. Draws nothing else: no
/// semantics, padding or hit area.
Widget kitIcon(
  LucideGlyph glyph, {
  required double size,
  required Color color,
}) => LucideIcon(
  lucideWeight(glyph, size, kKitIconStroke),
  size: size,
  color: color,
);

/// A Lucide glyph at [size], hidden from semantics (the button around it
/// speaks). [color] defaults to the secondary icon colour.
class KitIcon extends StatelessWidget {
  const KitIcon(this.glyph, {super.key, this.size = 14, this.color});

  final LucideGlyph glyph;
  final double size;

  /// Defaults to the secondary icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: kitIcon(
      glyph,
      size: size,
      color: color ?? context.bb.colors.iconSecondary,
    ),
  );
}
