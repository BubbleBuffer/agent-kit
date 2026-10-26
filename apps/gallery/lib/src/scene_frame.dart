// Draws one scene at a given width, in a theme. The gallery's viewport and the
// golden tests both use it, so a screenshot is exactly what the gallery shows.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/tokens.dart';
import 'package:flutter/widgets.dart';

import 'gallery_controller.dart';
import 'scenes.dart';

/// [scene] constrained to [width] (or less, when the space is narrower),
/// with the form factor the width implies, as a phone window would give it.
class SceneFrame extends StatelessWidget {
  const SceneFrame({
    super.key,
    required this.scene,
    required this.controller,
    required this.width,
    required this.brightness,
    this.tall = false,
  });

  final GalleryScene scene;
  final GalleryController controller;
  final double width;
  final Brightness brightness;

  /// Lay the Components sheet out at full height (for a whole-sheet golden).
  final bool tall;

  @override
  Widget build(BuildContext context) => BbThemeScope(
    brightness: brightness,
    formFactor: FormFactor.forWidth(width),
    child: Builder(
      builder: (context) {
        final t = context.bb;
        return ColoredBox(
          color: t.surface2,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = width < constraints.maxWidth
                  ? width
                  : constraints.maxWidth;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: w,
                  child: buildScene(scene, controller, tall: tall),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
