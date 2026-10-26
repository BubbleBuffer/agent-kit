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
        QuestionItem,
        QuestionKind,
        QuestionOption,
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

/// Pick one, with descriptions and an Other row.
final fixturePickOne = QuestionItem(
  id: 'age',
  header: 'Stale figure',
  text: 'Should a stale quota figure show its age?',
  options: const [
    QuestionOption(
      label: 'Only on hover',
      description: 'The bar dims; hovering shows the last update.',
    ),
    QuestionOption(
      label: 'Always',
      description: 'A small age label sits next to the figure.',
    ),
    QuestionOption(
      label: 'Never',
      description: 'Dimming alone marks it stale.',
    ),
  ],
  allowOther: true,
);

/// Pick any, with an Other row.
final fixturePickAny = QuestionItem(
  id: 'views',
  header: 'Views',
  text: 'Which views should keep the last known figure?',
  kind: QuestionKind.pickAny,
  options: const [
    QuestionOption(label: 'Web quota bar'),
    QuestionOption(label: 'Desktop tray'),
    QuestionOption(label: 'CLI status line'),
  ],
  allowOther: true,
);

/// Text only.
final fixtureText = QuestionItem(
  id: 'label',
  header: 'Label',
  text:
      'What should the stale label say? I’ll use it in the tooltip and the '
      'screen-reader text.',
  kind: QuestionKind.text,
);

Question _request(String id, List<QuestionItem> items, Duration waited) =>
    Question(
      id: id,
      requestedAt: fixtureNow.subtract(waited),
      items: items,
    );

/// One pick-one question, waiting 3 minutes.
final fixtureQuestion = _request('qs1', [
  fixturePickOne,
], const Duration(minutes: 3));

/// One pick-any question, waiting 1 minute.
final fixturePickAnyRequest = _request('qs2', [
  fixturePickAny,
], const Duration(minutes: 1));

/// One text-only question, waiting 40 seconds.
final fixtureTextRequest = _request('qs3', [
  fixtureText,
], const Duration(seconds: 40));

/// The mixed request: pick one, pick any, text; waiting 6 minutes.
final fixtureMixed = _request('qs4', [
  fixturePickOne,
  fixturePickAny,
  fixtureText,
], const Duration(minutes: 6));

/// Five questions (the most a request holds), waiting 9 minutes.
final fixtureFive = _request('qs5', [
  fixturePickOne,
  fixturePickAny,
  fixtureText,
  QuestionItem(
    id: 'wait',
    header: 'Reconnect',
    text: 'How long should the bar wait before marking the figure stale?',
    options: const [
      QuestionOption(label: 'Right away'),
      QuestionOption(
        label: 'After 5 seconds',
        description: 'Short blips stay invisible.',
      ),
      QuestionOption(label: 'After 30 seconds'),
    ],
  ),
  QuestionItem(
    id: 'tests',
    header: 'Tests to add',
    text: 'Which tests should I add?',
    kind: QuestionKind.pickAny,
    options: const [
      QuestionOption(label: 'Reconnect keeps the figure'),
      QuestionOption(label: 'Stale clears on update'),
    ],
  ),
], const Duration(minutes: 9));

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
