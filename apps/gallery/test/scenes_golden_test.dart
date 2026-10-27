// Golden screenshots of the gallery scenes (A 1440 and 1000, C 390, D 1600 and 1000, the Components sheet whole), light and
// dark, with the scripted chat played to its end on a manual clock. CI
// compares them with the committed PNGs (goldens/) and uploads them as the
// `gallery-shots` artifact. Re-render with
// `flutter test --tags golden --update-goldens` or the CI dispatch.

@Tags(['golden'])
library;

import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widths and window heights shot for each scene.
const _shots = <GalleryScene, List<(int, double)>>{
  GalleryScene.workbench: [(1440, 900), (1000, 800)],
  GalleryScene.scratchPane: [(1440, 900)],
  GalleryScene.phone: [(390, 844)],
  GalleryScene.workspace: [(1600, 900), (1000, 800)],
  GalleryScene.context: [(1440, 900), (390, 844)],
  GalleryScene.components: [(1000, 800)],
};

void main() {
  for (final MapEntry(key: scene, value: sizes) in _shots.entries) {
    for (final (width, height) in sizes) {
      for (final brightness in Brightness.values) {
        final name = '${scene.slug}_${width}_${brightness.name}';
        testWidgets('scene $name', (tester) async {
          final controller = GalleryController();
          addTearDown(controller.dispose);
          await tester.runAsync(controller.start);
          final tall = scene == GalleryScene.components;
          // The Components sheet is shot whole: measure it in a tall window,
          // then shrink the window to it.
          tester.view.physicalSize = Size(
            width.toDouble(),
            tall ? 30000 : height,
          );
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            WidgetsApp(
              color: const Color(0xFF000000),
              debugShowCheckedModeBanner: false,
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: SceneFrame(
                  scene: scene,
                  controller: controller,
                  width: width.toDouble(),
                  brightness: brightness,
                  tall: tall,
                ),
              ),
            ),
          );
          // Let the chat list and the feeds load.
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await expectLater(
            tall
                ? find
                      .descendant(
                        of: find.byType(ComponentsScene),
                        matching: find.byType(RepaintBoundary),
                      )
                      .first
                : find.byType(WidgetsApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
