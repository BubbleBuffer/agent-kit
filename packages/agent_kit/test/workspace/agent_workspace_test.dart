// AgentWorkspace: the divider-collapse threshold, restoring from an edge tab,
// docking into each zone, the size-class switch and the pane chrome.

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';
import 'sample_layout.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.id, this.log);

  final String id;
  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add(widget.id);
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('pane ${widget.id}'));
}

class _Rig {
  _Rig(this.controller) {
    host = Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => AgentWorkspace(
            controller: controller,
            kinds: kinds,
            paneBuilder: (context, tab) => _Probe(tab.id, inits),
            onClose: () => closed++,
          ),
        ),
      ],
    );
  }

  final WorkspaceController controller;
  final inits = <String>[];
  int closed = 0;
  late final Widget host;

  Future<void> pump(WidgetTester tester, Size size) =>
      pumpKit(tester, host, size: size);
}

const _wide = Size(1208, 700);

Future<_Rig> _open(
  WidgetTester tester, {
  Size size = _wide,
  WorkspaceLayout? layout,
}) async {
  final rig = _Rig(WorkspaceController(layout ?? sampleLayout()));
  await rig.pump(tester, size);
  return rig;
}

Finder _key(String k) => find.byKey(ValueKey(k));

bool _isAdd(Widget w) =>
    w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('wp-add-');

void main() {
  group('divider', () {
    testWidgets('stops at the minimum, previews, then collapses past it', (
      tester,
    ) async {
      final rig = await _open(tester);
      final c = rig.controller;
      final before = c.layout;
      // The pair shares 1200 px; the right side may go down to 200, so the
      // snap starts 24 px past the pointer position 1000 (plus the grab
      // offset of 4 inside the divider).
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-divider-root-0')),
      );
      await g.moveTo(const Offset(1014, 350));
      await tester.pump();
      expect(_key('wp-snap-hint'), findsNothing);
      expect(tester.getSize(_key('wp-leaf-t')).width, closeTo(200, .5));

      await g.moveTo(const Offset(1040, 350));
      await tester.pump();
      expect(_key('wp-snap-hint'), findsOneWidget);
      expect(find.text('Release to hide Terminal · File'), findsOneWidget);
      // The pane itself never goes below the minimum.
      expect(tester.getSize(_key('wp-leaf-t')).width, closeTo(200, .5));

      await g.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(_key('wp-snap-hint'), findsNothing);
      expect(c.layout.node('right')!.collapsed, isTrue);
      // Collapsed at the size it had before the drag.
      expect(
        (c.layout.root! as WorkspaceSplit).weights,
        (before.root! as WorkspaceSplit).weights,
      );
      expect(tester.getSize(_key('wp-edge-right')).width, 28);
    });

    testWidgets('the other side collapses the same way', (tester) async {
      final rig = await _open(tester);
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-divider-root-0')),
      );
      await g.moveTo(const Offset(190, 350));
      await tester.pump();
      expect(_key('wp-snap-hint'), findsNothing);
      expect(tester.getSize(_key('wp-leaf-b')).width, closeTo(200, .5));
      await g.moveTo(const Offset(150, 350));
      await tester.pump();
      expect(find.text('Release to hide Browser'), findsOneWidget);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(rig.controller.layout.leaf('b')!.collapsed, isTrue);
    });

    testWidgets('a drag inside the limits resizes without collapsing', (
      tester,
    ) async {
      final rig = await _open(tester);
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-divider-root-0')),
      );
      await g.moveTo(const Offset(404, 350));
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.getSize(_key('wp-leaf-b')).width, closeTo(400, .5));
      expect(rig.controller.layout.leaf('b')!.collapsed, isFalse);
    });

    testWidgets('double-clicking evens the split', (tester) async {
      final rig = await _open(tester);
      rig.controller.resize('root', 0, 0.3);
      await tester.pump();
      final div = _key('wp-divider-root-0');
      await tester.tap(div);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(div);
      await tester.pump();
      final w = (rig.controller.layout.root! as WorkspaceSplit).weights;
      expect(w[0], closeTo(w[1], 1e-9));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('arrow keys nudge a focused divider', (tester) async {
      final rig = await _open(tester);
      await tester.tap(_key('wp-divider-root-0'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final w = (rig.controller.layout.root! as WorkspaceSplit).weights;
      expect(w[0] / (w[0] + w[1]), closeTo(616 / 1200, 1e-6));
    });
  });

  group('edge tab', () {
    testWidgets('restores the pane at its previous size', (tester) async {
      final rig = await _open(tester);
      rig.controller.resize('root', 0, 0.3);
      await tester.pump();
      final width = tester.getSize(_key('wp-leaf-b')).width;
      expect(width, closeTo(360, .5));

      rig.controller.collapse('b');
      await tester.pump();
      expect(_key('wp-leaf-b'), findsNothing);
      expect(tester.getSize(_key('wp-edge-b')).width, 28);

      await tester.tap(_key('wp-edge-b'));
      await tester.pump();
      expect(rig.controller.layout.leaf('b')!.collapsed, isFalse);
      expect(tester.getSize(_key('wp-leaf-b')).width, closeTo(width, .5));
    });

    testWidgets('a collapsed pane keeps its state', (tester) async {
      final rig = await _open(tester);
      rig.controller.collapse('b');
      await tester.pump();
      rig.controller.restore('b');
      await tester.pump();
      expect(rig.inits.where((i) => i == 'browser'), hasLength(1));
    });

    testWidgets('a column collapses to a horizontal tab', (tester) async {
      final rig = await _open(tester);
      rig.controller.collapse('f');
      await tester.pump();
      final size = tester.getSize(_key('wp-edge-f'));
      expect(size.height, 28);
      expect(size.width, closeTo(600, .5));
    });

    testWidgets('an edge tab of an auto-folded pane unfolds it', (
      tester,
    ) async {
      // Five panes in a row, room for four at their minimum.
      final layout = WorkspaceLayout(
        root: WorkspaceSplit(
          id: 'root',
          axis: SplitAxis.row,
          weights: const [1, 2, 3, 4, 5],
          children: [
            for (final id in ['x', 'y', 'z', 'u', 'v'])
              WorkspaceLeaf(
                id: id,
                tabs: [WorkspaceTab(id: 'tab-$id', kind: 'browser')],
              ),
          ],
        ),
        front: 'tab-x',
      );
      final rig = await _open(
        tester,
        size: const Size(1000, 600),
        layout: layout,
      );
      expect(_key('wp-edge-x'), findsOneWidget);
      expect(_key('wp-leaf-x'), findsNothing);
      await tester.tap(_key('wp-edge-x'));
      await tester.pump();
      expect(_key('wp-leaf-x'), findsOneWidget);
      expect(_key('wp-edge-x'), findsNothing);
      // Another pane took its place as the folded one.
      expect(_key('wp-edge-y'), findsOneWidget);
      expect(rig.controller.layout.leaf('x')!.collapsed, isFalse);
    });

    testWidgets('a pane folds by itself when there is no room', (tester) async {
      final rig = await _open(tester, size: const Size(1000, 200));
      expect(_key('wp-edge-f'), findsOneWidget);
      expect(rig.controller.layout.leaf('f')!.collapsed, isFalse);
      await rig.pump(tester, const Size(1000, 700));
      expect(_key('wp-edge-f'), findsNothing);
      expect(_key('wp-leaf-f'), findsOneWidget);
    });
  });

  group('dock by drag', () {
    // The browser pane is at x 0 to 600, y 0 to 700.
    const spots = {
      DockZone.left: Offset(60, 350),
      DockZone.right: Offset(540, 350),
      DockZone.top: Offset(300, 60),
      DockZone.bottom: Offset(300, 640),
      DockZone.center: Offset(300, 350),
    };
    const captions = {
      DockZone.left: 'Dock left',
      DockZone.right: 'Dock right',
      DockZone.top: 'Dock above',
      DockZone.bottom: 'Dock below',
      DockZone.center: 'Add as tab',
    };

    Future<TestGesture> lift(WidgetTester tester) async {
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-tab-file')),
      );
      await g.moveBy(const Offset(-10, 0));
      return g;
    }

    for (final zone in DockZone.values) {
      testWidgets('into the ${zone.name} zone of a pane', (tester) async {
        final rig = await _open(tester);
        final expected = sampleLayout().dock(
          'file',
          DockTarget.pane('b', zone),
        );
        final g = await lift(tester);
        await g.moveTo(spots[zone]!);
        await tester.pump();
        expect(_key('wp-dock-preview'), findsOneWidget);
        expect(find.text(captions[zone]!), findsOneWidget);
        expect(_key('wp-dock-ghost'), findsOneWidget);
        await g.up();
        await tester.pump();
        expect(_key('wp-dock-preview'), findsNothing);
        expect(rig.controller.layout, expected);
        // The pane moved without losing its state.
        expect(rig.inits.where((i) => i == 'file'), hasLength(1));
      });
    }

    const edges = {
      DockSide.left: Offset(5, 350),
      DockSide.right: Offset(1203, 350),
      DockSide.top: Offset(600, 5),
      DockSide.bottom: Offset(600, 695),
    };
    for (final side in DockSide.values) {
      testWidgets('onto the ${side.name} outer edge', (tester) async {
        final rig = await _open(tester);
        final expected = sampleLayout().dock('file', DockTarget.outer(side));
        final g = await lift(tester);
        await g.moveTo(edges[side]!);
        await tester.pump();
        expect(find.textContaining('Full '), findsOneWidget);
        await g.up();
        await tester.pump();
        expect(rig.controller.layout, expected);
      });
    }

    testWidgets('a short move is a click, not a drag', (tester) async {
      final rig = await _open(tester);
      final g = await tester.startGesture(
        tester.getCenter(_key('wp-tab-file')),
      );
      await g.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(_key('wp-dock-ghost'), findsNothing);
      await g.up();
      await tester.pump();
      expect(shape(rig.controller.layout), shape(sampleLayout()));
    });

    testWidgets('Escape cancels the drag', (tester) async {
      final rig = await _open(tester);
      final g = await lift(tester);
      await g.moveTo(spots[DockZone.left]!);
      await tester.pump();
      expect(_key('wp-dock-preview'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_key('wp-dock-preview'), findsNothing);
      await g.up();
      await tester.pump();
      expect(rig.controller.layout, sampleLayout());
    });

    testWidgets('dropping a lone pane on itself shows no target', (
      tester,
    ) async {
      final rig = await _open(tester);
      final g = await lift(tester);
      // The file pane is at the bottom right.
      await g.moveTo(const Offset(900, 600));
      await tester.pump();
      expect(_key('wp-dock-preview'), findsNothing);
      await g.up();
      await tester.pump();
      expect(rig.controller.layout, sampleLayout());
    });
  });

  group('size class', () {
    testWidgets(
      'expanded is the tree, medium one tabbed column, compact a sheet',
      (tester) async {
        final rig = _Rig(WorkspaceController(sampleLayout()));
        await rig.pump(tester, const Size(1200, 700));
        expect(_key('wp-divider-root-0'), findsOneWidget);
        expect(_key('wp-ws-tabs'), findsNothing);
        expect(find.text('pane browser'), findsOneWidget);
        expect(find.text('pane terminal'), findsOneWidget);

        await rig.pump(tester, const Size(800, 600));
        expect(_key('wp-divider-root-0'), findsNothing);
        expect(_key('wp-ws-tabs'), findsOneWidget);
        expect(_key('wp-sheet-close'), findsNothing);
        expect(find.text('pane browser'), findsOneWidget);
        expect(find.text('pane terminal'), findsNothing);

        await tester.tap(_key('wp-ws-tab-terminal'));
        await tester.pump();
        expect(rig.controller.layout.front, 'terminal');
        expect(find.text('pane terminal'), findsOneWidget);
        expect(find.text('pane browser'), findsNothing);

        await rig.pump(tester, const Size(390, 700));
        expect(_key('wp-ws-tabs'), findsOneWidget);
        expect(_key('wp-sheet-close'), findsOneWidget);
        expect(find.text('pane terminal'), findsOneWidget);
        await tester.tap(_key('wp-sheet-close'));
        expect(rig.closed, 1);

        await rig.pump(tester, const Size(1200, 700));
        expect(_key('wp-divider-root-0'), findsOneWidget);
        expect(_key('wp-sheet-close'), findsNothing);
      },
    );

    testWidgets('the class follows the container, not the window', (
      tester,
    ) async {
      final c = WorkspaceController(sampleLayout());
      await pumpKit(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 700,
            height: 500,
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => AgentWorkspace(
                    controller: c,
                    kinds: kinds,
                    paneBuilder: (context, tab) => Text('pane ${tab.id}'),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: const Size(1600, 800),
      );
      expect(_key('wp-ws-tabs'), findsOneWidget);
      expect(_key('wp-divider-root-0'), findsNothing);
    });
  });

  group('pane chrome', () {
    testWidgets('the + menu lists the host kinds and adds a pane', (
      tester,
    ) async {
      final rig = await _open(tester);
      await tester.tap(_key('wp-add-f'));
      await tester.pump();
      expect(_key('wp-menu'), findsOneWidget);
      for (final k in kinds) {
        expect(_key('wp-menu-${k.id}'), findsOneWidget);
      }
      await tester.tap(_key('wp-menu-activity'));
      await tester.pump();
      expect(_key('wp-menu'), findsNothing);
      final added = rig.controller.layout.leaves.last;
      expect(added.activeTab.kind, 'activity');
      expect(rig.controller.layout.leaves.length, 4);
      expect(find.text('pane ${added.active}'), findsOneWidget);
    });

    testWidgets('only the last pane that can split shows +', (tester) async {
      await _open(tester);
      expect(find.byWidgetPredicate(_isAdd), findsOneWidget);
      expect(_key('wp-add-f'), findsOneWidget);
    });

    testWidgets('+ moves to the pane that still has room', (tester) async {
      // 500 high: the file pane (about 210) cannot hold two panes below one
      // another; the terminal above it (about 280) can.
      await _open(tester, size: const Size(1208, 500));
      expect(find.byWidgetPredicate(_isAdd), findsOneWidget);
      expect(_key('wp-add-t'), findsOneWidget);
    });

    testWidgets('a tap outside closes the menu', (tester) async {
      await _open(tester);
      await tester.tap(_key('wp-add-f'));
      await tester.pump();
      expect(_key('wp-menu'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(_key('wp-menu'), findsNothing);
    });

    testWidgets('maximise fills the area and restores', (tester) async {
      final rig = await _open(tester);
      await tester.tap(_key('wp-max-t'));
      await tester.pump();
      expect(rig.controller.layout.maximised, 't');
      expect(tester.getSize(_key('wp-leaf-t')), _wide);
      expect(_key('wp-divider-root-0'), findsNothing);
      await tester.tap(_key('wp-max-t'));
      await tester.pump();
      expect(rig.controller.layout.maximised, isNull);
      expect(_key('wp-divider-root-0'), findsOneWidget);
    });

    testWidgets('close removes the pane', (tester) async {
      final rig = await _open(tester);
      await tester.tap(_key('wp-close-f'));
      await tester.pump();
      expect(shape(rig.controller.layout), ['browser', 'terminal']);
      expect(_key('wp-leaf-f'), findsNothing);
    });

    testWidgets('tabs of a group switch the pane that shows', (tester) async {
      final rig = await _open(
        tester,
        layout: sampleLayout().addTab(leafId: 'b', kind: 'file'),
      );
      final id = rig.controller.layout.leaf('b')!.active;
      expect(find.text('pane $id'), findsOneWidget);
      expect(find.text('pane browser'), findsNothing);
      await tester.tap(_key('wp-tab-browser'));
      await tester.pump();
      expect(find.text('pane browser'), findsOneWidget);
      expect(rig.controller.layout.leaf('b')!.active, 'browser');
    });

    testWidgets('an empty workspace offers the + menu', (tester) async {
      final rig = await _open(tester, layout: const WorkspaceLayout.empty());
      expect(find.text('No panes open'), findsOneWidget);
      await tester.tap(_key('wp-add-empty'));
      await tester.pump();
      await tester.tap(_key('wp-menu-terminal'));
      await tester.pump();
      expect(rig.controller.layout.tabs.single.kind, 'terminal');
    });
  });
}
