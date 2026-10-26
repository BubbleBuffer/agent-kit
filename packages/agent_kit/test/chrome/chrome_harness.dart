// A harness for the chrome tests: like test/harness.dart, but the theme sits
// above a real Navigator, so tooltips (an Overlay) and the session menu (a
// popover route) work.

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpChrome(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = const Size(480, 320),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, _) => builder(context),
          ),
      home: child,
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: BbThemeScope(brightness: brightness, child: navigator!),
      ),
    ),
  );
}
