// Golden screenshots of AgentWorkspace: the tree, a collapsed pane, a dock
// drag, a divider snap, the + menu, and the medium and compact layouts, in
// light and dark. Run `flutter test --tags golden --update-goldens` (or the CI
// dispatch) to re-render; CI compares against the committed PNGs.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart' show TypeSpec, ts;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

WorkspaceLayout _layout() => WorkspaceLayout(
  root: WorkspaceSplit(
    id: 'root',
    axis: SplitAxis.row,
    children: [
      WorkspaceLeaf(
        id: 'browser-pane',
        tabs: const [
          WorkspaceTab(id: 'browser', kind: 'browser', title: 'localhost:5173'),
        ],
      ),
      WorkspaceSplit(
        id: 'right',
        axis: SplitAxis.column,
        weights: const [1.15, 0.85],
        children: [
          WorkspaceLeaf(
            id: 'terminal-pane',
            tabs: const [
              WorkspaceTab(id: 'cargo', kind: 'terminal', title: 'cargo test'),
              WorkspaceTab(id: 'dev', kind: 'terminal', title: 'dev server'),
            ],
          ),
          WorkspaceLeaf(
            id: 'file-pane',
            tabs: const [
              WorkspaceTab(id: 'usage', kind: 'file', title: 'usage/mod.rs'),
            ],
          ),
        ],
      ),
    ],
  ),
  front: 'browser',
);

const _lines = {
  'browser': [
    'http://localhost:5173/usage',
    '',
    'This week  62%',
    'Stale, last update 14s ago',
  ],
  'terminal': [
    r'$ cargo test -p bubblepaw-host usage',
    'running 14 tests',
    'test usage::tests::reset ... ok',
    'test usage::tests::snapshot ... FAILED',
  ],
  'file': [
    'impl UsageState {',
    '    pub fn is_stale(&self) -> bool {',
    '        self.stale_since.is_some()',
    '    }',
  ],
  'activity': ['Still running', 'Survey quota handling'],
};

Widget _pane(BuildContext context, WorkspaceTab tab) {
  final t = context.bb;
  return ColoredBox(
    color: tab.kind == 'terminal' ? t.surface2 : t.surface,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _lines[tab.kind] ?? const <String>[])
            Text(
              line.isEmpty ? ' ' : line,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: ts(const TypeSpec(12, 18, 400), t.muted, mono: true),
            ),
        ],
      ),
    ),
  );
}

Widget _scene(WorkspaceController c, {bool sheet = false}) => Builder(
  builder: (context) => ColoredBox(
    color: context.bb.canvas,
    child: Padding(
      padding: EdgeInsets.all(sheet ? 0 : 12),
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => AgentWorkspace(
              controller: c,
              kinds: WorkspaceKind.standard,
              paneBuilder: _pane,
              onClose: () {},
            ),
          ),
        ],
      ),
    ),
  ),
);

Finder _key(String k) => find.byKey(ValueKey(k));

Future<void> _shot(WidgetTester tester, String name, Brightness b) =>
    expectLater(
      find.byType(WidgetsApp),
      matchesGoldenFile('../goldens/workspace_${name}_${b.name}.png'),
    );

void main() {
  // The workspace is 1000 px wide inside the 12 px margin of the window.
  const wide = Size(1024, 584);

  for (final b in Brightness.values) {
    testWidgets('tree, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout());
      await pumpKit(tester, _scene(c), brightness: b, size: wide);
      await _shot(tester, 'tree_1000', b);
    });

    testWidgets('collapsed browser, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout().collapse('browser-pane'));
      await pumpKit(tester, _scene(c), brightness: b, size: wide);
      await _shot(tester, 'collapsed_1000', b);
    });

    testWidgets('dock drag, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout());
      await pumpKit(tester, _scene(c), brightness: b, size: wide);
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-tab-usage')),
      );
      await g.moveBy(const Offset(-12, 0));
      final r = tester.getRect(_key('wp-leaf-terminal-pane'));
      await g.moveTo(Offset(r.right - r.width * .08, r.center.dy));
      await tester.pump();
      await _shot(tester, 'dock_1000', b);
      await g.up();
    });

    testWidgets('divider snap, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout());
      await pumpKit(tester, _scene(c), brightness: b, size: wide);
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-divider-root-0')),
      );
      await g.moveTo(const Offset(1000, 300));
      await tester.pump();
      await _shot(tester, 'snap_1000', b);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('add menu, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout());
      await pumpKit(tester, _scene(c), brightness: b, size: wide);
      await tester.tap(_key('wp-add-file-pane'));
      await tester.pump();
      await _shot(tester, 'menu_1000', b);
    });

    testWidgets('medium, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout());
      await pumpKit(
        tester,
        _scene(c),
        brightness: b,
        size: const Size(724, 400),
      );
      await _shot(tester, 'medium_700', b);
    });

    testWidgets('compact, ${b.name}', (tester) async {
      final c = WorkspaceController(_layout().activate('usage'));
      await pumpKit(
        tester,
        _scene(c, sheet: true),
        brightness: b,
        size: const Size(390, 520),
      );
      await _shot(tester, 'compact_390', b);
    });
  }
}
