// Harness for the transcript tests: a theme scope with the form factor the
// width implies (a phone window under 768 px), animations off, and a size
// class builder so widgets lay out by the width given here.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart' show FormFactor;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpTranscript(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 800,
  double height = 600,
  bool sheet = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: BbThemeScope(
          brightness: brightness,
          formFactor: FormFactor.forWidth(width),
          child: Builder(
            builder: (context) => ColoredBox(
              color: sheet ? context.bb.surface : const Color(0x00000000),
              child: SizedBox(
                width: width,
                height: height,
                child: SizeClassBuilder(builder: (context, _) => child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A scroll position of the first scrollable (the list's).
ScrollPosition listPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;
