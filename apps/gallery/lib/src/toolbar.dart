// The gallery's toolbar: scene switcher, light/dark toggle, width slider and
// the clock controls of the scripted backend.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import 'gallery_controller.dart';
import 'scenes.dart';

class GalleryToolbar extends StatelessWidget {
  const GalleryToolbar({super.key, required this.controller});

  final GalleryController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.seam)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.md,
          vertical: t.spacing.sm,
        ),
        child: Wrap(
          spacing: t.spacing.lg,
          runSpacing: t.spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Agent kit gallery', style: ts(t.type.ui, t.ink, weight: 700)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final scene in GalleryScene.values)
                  _SceneTab(
                    label: '${scene.tag} · ${scene.label}',
                    selected: scene == controller.scene,
                    onTap: () => controller.selectScene(scene),
                  ),
              ],
            ),
            TextBtn(
              controller.brightness == Brightness.light ? 'Dark' : 'Light',
              onTap: controller.toggleBrightness,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Width', style: ts(t.type.uiSmall, t.muted)),
                SizedBox(width: t.spacing.sm),
                WidthSlider(
                  value: controller.width,
                  min: minGalleryWidth,
                  max: maxGalleryWidth,
                  onChanged: (v) => controller.width = v,
                ),
                SizedBox(width: t.spacing.sm),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${controller.width.round()} px',
                    style: ts(
                      const TypeSpec(12, 16, 400),
                      t.ink,
                      mono: true,
                    ),
                  ),
                ),
              ],
            ),
            if (controller.steppable)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextBtn(
                    '+10 s',
                    onTap: () => controller.advance(const Duration(seconds: 10)),
                  ),
                  TextBtn('Play', onTap: controller.playToEnd),
                  TextBtn('Replay', onTap: controller.replay),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SceneTab extends StatelessWidget {
  const _SceneTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      button: true,
      selected: selected,
      child: Hover(
        onTap: onTap,
        selected: selected,
        selectedColor: t.pressed,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 28,
          child: Center(
            child: Text(
              label,
              style: ts(
                t.type.ui,
                selected ? t.ink : t.muted,
                weight: selected ? 700 : 500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal slider (no Material): drag or tap the track.
class WidthSlider extends StatelessWidget {
  const WidthSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      slider: true,
      label: 'Width',
      value: '${value.round()} px',
      child: SizedBox(
        width: 200,
        height: 28,
        child: LayoutBuilder(
          builder: (context, constraints) {
            double at(double dx) =>
                min + (max - min) * (dx / constraints.maxWidth).clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onChanged(at(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition.dx)),
              child: CustomPaint(
                painter: _SliderPainter(
                  fraction: ((value - min) / (max - min)).clamp(0.0, 1.0),
                  track: t.seam,
                  fill: t.accent,
                  thumb: t.ink,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.thumb,
  });

  final double fraction;
  final Color track, fill, thumb;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final y = size.height / 2;
    final x = inset + (size.width - 2 * inset) * fraction;
    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), line..color = track);
    canvas.drawLine(Offset(inset, y), Offset(x, y), line..color = fill);
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.thumb != thumb;
}
