// The gallery runs on the scripted backend and its toolbar drives the scene,
// the theme and the width.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the scripted chat ends waiting for the user', (tester) async {
    final controller = GalleryController();
    addTearDown(controller.dispose);
    await tester.runAsync(controller.start);
    final snapshot = controller.snapshot!;
    expect(snapshot.title, 'Quota bar flickers on reconnect');
    expect(snapshot.status, ChatStatus.needsYou);
    expect(snapshot.approvals, isNotEmpty);
  });

  testWidgets('the toolbar switches scene, theme and width', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GalleryController();
    addTearDown(controller.dispose);
    await tester.runAsync(controller.start);
    await tester.pumpWidget(GalleryApp(controller: controller));

    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(controller.scene, GalleryScene.workbench);
    expect(controller.width, 1440);
    expect(find.text('Quota bar flickers on reconnect'), findsWidgets);

    await tester.tap(find.text('C · Phone'));
    await tester.pump();
    expect(controller.scene, GalleryScene.phone);
    expect(controller.width, 390);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(controller.brightness, Brightness.dark);

    controller.width = 5000;
    expect(controller.width, maxGalleryWidth);
    controller.width = 10;
    expect(controller.width, minGalleryWidth);
  });
}
