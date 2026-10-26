// One golden screenshot per gallery scene, at 1440, 1000 and 390 px, light and
// dark, with the scripted chat played to its end on a manual clock. CI
// compares them with the committed PNGs (goldens/) and uploads them as the
// `gallery-shots` artifact. Re-render with
// `flutter test --tags golden --update-goldens` or the CI dispatch.

@Tags(['golden'])
library;

import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Named widths and the window height shot at each.
const _shots = <(int, double)>[(1440, 900), (1000, 800), (390, 844)];

void main() {
  for (final scene in GalleryScene.values) {
    for (final (width, height) in _shots) {
      for (final brightness in Brightness.values) {
        final name = '${scene.slug}_${width}_${brightness.name}';
        testWidgets('scene $name', (tester) async {
          final controller = GalleryController();
          addTearDown(controller.dispose);
          await tester.runAsync(controller.start);
          tester.view.physicalSize = Size(width.toDouble(), height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            WidgetsApp(
              color: const Color(0xFF000000),
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: SceneFrame(
                  scene: scene,
                  snapshot: controller.snapshot,
                  width: width.toDouble(),
                  brightness: brightness,
                ),
              ),
            ),
          );
          await expectLater(
            find.byType(WidgetsApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
