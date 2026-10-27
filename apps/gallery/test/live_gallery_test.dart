import 'package:agent_kit_gallery/gallery.dart';
import 'package:agent_kit_gallery/src/live_gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no live settings uses the existing gallery', (tester) async {
    late Widget selected;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          selected = const GalleryLaunch().build(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(selected, isA<GalleryApp>());
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
