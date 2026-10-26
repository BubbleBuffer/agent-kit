// Shared by the composer tests: a theme scope with a Navigator (the pick menus
// are popovers), animations off, a fixed width, and the form factor that width
// implies (as a phone window would give it); and the fixtures.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show
        Approval,
        DiffHunk,
        DiffLine,
        DiffOp,
        FileDiff,
        KitChoice,
        KitRef,
        Question,
        QueuedInput,
        ToolKind;
import 'package:bb_ui/tokens.dart' show FormFactor;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] at [width] x [height], left-aligned with a 16 px margin.
Future<void> pumpComposer(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 640,
  double height = 700,
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
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: width - 32, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The clock of the fixtures: 12 minutes after the approval was requested.
final fixtureNow = DateTime.utc(2026, 10, 26, 12, 12);

/// An edit approval waiting 12 minutes, +8 -3.
final fixtureApproval = Approval(
  id: 'ap1',
  tool: 'edit',
  kind: ToolKind.edit,
  target: 'crates/bubblepaw-host/src/usage/mod.rs',
  requestedAt: fixtureNow.subtract(const Duration(minutes: 12)),
  diff: FileDiff(
    path: 'crates/bubblepaw-host/src/usage/mod.rs',
    hunks: [
      DiffHunk(
        oldStart: 40,
        newStart: 40,
        lines: [
          for (var i = 0; i < 3; i++) DiffLine(DiffOp.del, 'old $i'),
          for (var i = 0; i < 8; i++) DiffLine(DiffOp.add, 'new $i'),
        ],
      ),
    ],
  ),
);

final fixtureQueued = QueuedInput(
  id: 'q1',
  text: 'Dim the bar while stale, don’t hide it',
  queuedAt: fixtureNow.subtract(const Duration(minutes: 2)),
);

final fixtureQuestion = Question(
  id: 'qs1',
  text: 'Should a stale figure show its age?',
  requestedAt: fixtureNow.subtract(const Duration(minutes: 3)),
  options: const ['Only on hover', 'Always'],
);

const fixtureModels = [
  KitChoice(id: 'flash', label: 'deepseek-v4.1-flash'),
  KitChoice(id: 'sol', label: 'gpt-6.1-sol'),
];

const fixtureWorkspaces = [
  KitChoice(id: 'base', label: 'BubblePaw-base'),
  KitChoice(id: 'kit', label: 'agent-kit'),
];

const fixtureChip = KitRef(kind: 'page', id: 'p1', label: 'Approval expiry');

const fixtureMentions = StaticMentionSource([
  KitRef(kind: 'file', id: 'f1', label: 'usage/mod.rs'),
  KitRef(kind: 'file', id: 'f2', label: 'usage/quota.rs'),
  KitRef(kind: 'page', id: 'p1', label: 'Approval expiry'),
]);
