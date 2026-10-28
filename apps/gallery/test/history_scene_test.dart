// The compacted-history scene builds with its cards, opens on the boundary,
// and the cards fold like a host's would.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the history scene shows cards over the boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: BbThemeScope(brightness: Brightness.light, child: child!),
        ),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondary) => builder(context),
        ),
        home: const HistoryScene(),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Full messages from here'), findsOneWidget);
    expect(find.text('message 132'), findsOneWidget);
    // The folded chapter, the opened one with its episodes, the split pair.
    expect(find.text('How usage figures flow'), findsOneWidget);
    expect(find.text('Sketch the quota bar'), findsOneWidget);
    expect(find.text('Backoff and retries'), findsNWidgets(2));
    // The folded chapter's face already lists its sections.
    expect(find.text('Find the cause'), findsOneWidget);
    expect(find.text('The reset is in on_close.'), findsNothing);
    expect(
      find.text('Sketch the quota bar states'),
      findsOneWidget,
      reason: 'the v2 episode of the opened chapter',
    );
    // The live end shows in full.
    expect(find.textContaining('Now dim the bar'), findsOneWidget);

    await tester.tap(_key('history-chapter-c1-toggle'));
    await tester.pump();
    expect(find.text('Find the cause'), findsNWidgets(2));
    expect(find.text('The reset is in on_close.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
