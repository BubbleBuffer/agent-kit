// The outline scene builds with its closed chapters, an open one, and works
// like a host: a card unfolds its messages, the strip opens the contents.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the outline scene shows chapters, and a card unfolds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondary) => builder(context),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: BbThemeScope(brightness: Brightness.light, child: child!),
        ),
        home: const OutlineScene(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_key('outline-chapter-c-quota'), findsOneWidget);
    expect(_key('outline-chapter-c-backoff'), findsOneWidget);
    // The open chapter is a heading with its messages under it.
    expect(_key('outline-chapter-c-notes'), findsOneWidget);
    expect(find.textContaining('Drafting'), findsOneWidget);
    // The first card starts open, on its sections.
    expect(find.text('Find the cause'), findsOneWidget);
    expect(find.textContaining('Can it keep showing'), findsNothing);

    await tester.tap(_key('outline-card-show-c-quota'));
    await tester.pump();
    expect(find.textContaining('Can it keep showing'), findsOneWidget);

    await tester.tap(_key('outline-where'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contents · 3 chapters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
