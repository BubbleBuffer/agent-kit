import 'package:agent_kit_gallery/gallery.dart';
import 'package:agent_kit_gallery/src/live_gallery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no live settings uses the existing gallery', (tester) async {
    await tester.pumpWidget(const GalleryLaunch());
    expect(find.byType(GalleryApp), findsOneWidget);
    await tester.pumpWidget(const GalleryLaunch(binaryPath: 'unused'));
    await tester.pump();
  });

  testWidgets('partial live settings explains the missing configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const GalleryLaunch(binaryPath: 'unused'));
    expect(find.text('Live gallery needs all three settings'), findsOneWidget);
    expect(find.textContaining('BP_WORKSPACE'), findsOneWidget);
    expect(find.byType(GalleryApp), findsNothing);
  });
}
