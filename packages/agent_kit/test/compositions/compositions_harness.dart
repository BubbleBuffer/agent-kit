// Shared by the composition tests: a theme scope with a Navigator (menus are
// popovers), animations off, the form factor the width implies, and a backend
// that has played the mockups' scenarios.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bb_ui/tokens.dart' show FormFactor;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] filling [width] x [height].
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 800,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
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
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: BbThemeScope(
          brightness: brightness,
          formFactor: FormFactor.forWidth(width),
          child: navigator!,
        ),
      ),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.bb.surface,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

const testModels = [
  KitChoice(id: 'deepseek-v4.1-flash', label: 'deepseek-v4.1-flash'),
  KitChoice(id: 'gpt-6.1-sol', label: 'gpt-6.1-sol'),
];

const testProfiles = [
  KitChoice(id: 'workspace', label: 'workspace'),
  KitChoice(id: 'readonly', label: 'read-only'),
];

/// A scripted backend with the quota chat played to its end (waiting for
/// approval, one message queued), the question chat, and an idle chat.
Future<({ScriptedBackend backend, ManualClock clock})> playedBackend(
  WidgetTester tester, {
  KitCapabilities? capabilities,
}) async {
  final clock = ManualClock();
  final backend = ScriptedBackend(
    scripts: [quotaReconnectScript(), mixedQuestionScript()],
    clock: clock,
    capabilities: capabilities,
    models: testModels,
    profiles: testProfiles,
  );
  await tester.runAsync(() async {
    unawaited(backend.play());
    await clock.advance(Duration.zero);
    await clock.runAll(limit: const Duration(minutes: 30));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  backend.emit('idle', {'kind': 'chat.renamed', 'title': 'Idle chat'});
  backend.commands.clear();
  return (backend: backend, clock: clock);
}

/// The commands the backend received, by name.
List<String> commandNames(ScriptedBackend backend) => [
  for (final c in backend.commands) c.name,
];

/// The arguments of the last [name] command.
List<Object?> lastArgs(ScriptedBackend backend, String name) =>
    backend.commands.lastWhere((c) => c.name == name).args;
