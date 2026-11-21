// Every gallery scene at every width class and at larger text sizes, with no
// overflow and no layout error. Nothing is compared with PNGs.

import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widths from a small phone to a wide desktop window, across both size class
/// boundaries.
const widths = [320.0, 390.0, 600.0, 840.0, 1000.0, 1600.0];

/// System text sizes: default, a common larger setting, and the largest the
/// kit is asked to follow.
const textScales = [1.0, 1.3];

const _height = 1200.0;

void main() {
  for (final scene in GalleryScene.values) {
    for (final width in widths) {
      for (final scale in textScales) {
        testWidgets('${scene.slug} at ${width.toInt()} px, text x$scale', (
          tester,
        ) async {
          final controller = GalleryController();
          addTearDown(controller.dispose);
          await tester.runAsync(controller.start);
          tester.view.physicalSize = Size(width, _height);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final text = details.toString();
            final at = RegExp(r'(lib/[a-z_/]+\.dart:\d+)')
                .firstMatch(text)
                ?.group(1);
            errors.add(
              '${details.exceptionAsString().split('\n').first}'
              '${at == null ? '' : ' at $at'}',
            );
          };
          addTearDown(() => FlutterError.onError = previous);

          await tester.pumpWidget(
            WidgetsApp(
              color: const Color(0xFF000000),
              debugShowCheckedModeBanner: false,
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: SceneFrame(
                  scene: scene,
                  controller: controller,
                  width: width,
                  brightness: Brightness.light,
                ),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          FlutterError.onError = previous;
          expect(errors, isEmpty, reason: errors.toSet().join('\n'));
        });
      }
    }
  }
}
