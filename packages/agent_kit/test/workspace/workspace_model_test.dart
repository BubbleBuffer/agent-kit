// The workspace model: every operation, the JSON round trip and the geometry.

import 'dart:ui';

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sample_layout.dart';

WorkspaceSplit rootSplit(WorkspaceLayout l) => l.root! as WorkspaceSplit;

void main() {
  group('add and split', () {
    test('the first pane becomes the root', () {
      final l = const WorkspaceLayout.empty().addPane(kind: 'browser');
      expect(l.root, isA<WorkspaceLeaf>());
      expect(l.tabs.single.kind, 'browser');
      expect(l.front, l.tabs.single.id);
    });

    test('a new pane docks right of the pane in a row', () {
      final l = sampleLayout().addPane(kind: 'activity', besideLeaf: 'b');
      expect(l.leaves.length, 4);
      expect(l.leaves[1].activeTab.kind, 'activity');
      expect(rootSplit(l).children.length, 3);
      expect(l.front, l.leaves[1].active);
    });

    test('a new pane docks below the pane in a column', () {
      final l = sampleLayout().addPane(kind: 'activity', besideLeaf: 'f');
      final right = rootSplit(l).children[1] as WorkspaceSplit;
      expect(right.axis, SplitAxis.column);
      expect(right.children.length, 3);
      expect((right.children[2] as WorkspaceLeaf).activeTab.kind, 'activity');
    });

    test('split wraps a pane in a perpendicular split', () {
      final l = sampleLayout().split(
        leafId: 'b',
        side: DockSide.bottom,
        kind: 'terminal',
      );
      final first = rootSplit(l).children.first as WorkspaceSplit;
      expect(first.axis, SplitAxis.column);
      expect(first.children.length, 2);
      expect((first.children.first as WorkspaceLeaf).id, 'b');
    });

    test('addTab adds to the group and shows the tab', () {
      final l = sampleLayout().addTab(leafId: 'b', kind: 'file', title: 'x.rs');
      final leaf = l.leaf('b')!;
      expect(leaf.tabs.length, 2);
      expect(leaf.activeTab.title, 'x.rs');
      expect(l.front, leaf.active);
    });
  });

  group('close', () {
    test('closing a tab unwraps the emptied split', () {
      final l = sampleLayout().closeTab('file');
      expect(shape(l), ['browser', 'terminal']);
      final s = rootSplit(l);
      expect(s.axis, SplitAxis.row);
      expect(s.children.every((c) => c is WorkspaceLeaf), isTrue);
      expect(s.weights.length, 2);
    });

    test('closing a tab of a group keeps the pane and picks a neighbour', () {
      final two = sampleLayout().addTab(leafId: 'b', kind: 'file');
      final id = two.leaf('b')!.active;
      final l = two.closeTab(id);
      expect(l.leaf('b')!.tabs.map((t) => t.id), ['browser']);
      expect(l.leaf('b')!.active, 'browser');
    });

    test('closing the last pane empties the layout', () {
      var l = sampleLayout();
      for (final id in ['browser', 'terminal', 'file']) {
        l = l.closeTab(id);
      }
      expect(l.isEmpty, isTrue);
      expect(l.front, isNull);
    });

    test('closing the maximised pane clears the maximise', () {
      final l = sampleLayout().maximise('f').closeLeaf('f');
      expect(l.maximised, isNull);
    });
  });

  group('dock', () {
    test('left and right insert beside the target in a same-axis split', () {
      final left = sampleLayout().dock(
        'file',
        const DockTarget.pane('b', DockZone.left),
      );
      expect(shape(left), ['file', 'browser', 'terminal']);
      final right = sampleLayout().dock(
        'file',
        const DockTarget.pane('b', DockZone.right),
      );
      expect(shape(right), ['browser', 'file', 'terminal']);
      expect(rootSplit(right).axis, SplitAxis.row);
    });

    test('top and bottom wrap the target in a column', () {
      final top = sampleLayout().dock(
        'file',
        const DockTarget.pane('b', DockZone.top),
      );
      expect(
        (rootSplit(top).children.first as WorkspaceSplit).axis,
        SplitAxis.column,
      );
      expect(shape(top), ['file', 'browser', 'terminal']);
      final bottom = sampleLayout().dock(
        'file',
        const DockTarget.pane('b', DockZone.bottom),
      );
      expect(shape(bottom), ['browser', 'file', 'terminal']);
      expect(
        (rootSplit(bottom).children.first as WorkspaceSplit).axis,
        SplitAxis.column,
      );
    });

    test('the centre adds the tab to the group', () {
      final l = sampleLayout().dock(
        'file',
        const DockTarget.pane('b', DockZone.center),
      );
      expect(shape(l), ['browser+file', 'terminal']);
      expect(l.leaf('b')!.active, 'file');
      expect(l.front, 'file');
    });

    test('the outer edge makes a full-height or full-width split', () {
      final left = sampleLayout().dock(
        'file',
        const DockTarget.outer(DockSide.left),
      );
      expect(shape(left), ['file', 'browser', 'terminal']);
      expect(rootSplit(left).children.length, 3);
      final bottom = sampleLayout().dock(
        'file',
        const DockTarget.outer(DockSide.bottom),
      );
      final root = rootSplit(bottom);
      expect(root.axis, SplitAxis.column);
      expect(root.children.length, 2);
      expect(root.weights, [2, 1]);
      expect(shape(bottom), ['browser', 'terminal', 'file']);
    });

    test('a lone pane dropped on itself changes nothing', () {
      final l = sampleLayout();
      expect(
        identical(l.dock('file', const DockTarget.pane('f', DockZone.left)), l),
        isTrue,
      );
    });

    test('a tab of a group can tear out beside its own pane', () {
      final grouped = sampleLayout().addTab(leafId: 'b', kind: 'file');
      final id = grouped.leaf('b')!.active;
      final l = grouped.dock(id, const DockTarget.pane('b', DockZone.right));
      expect(shape(l), ['browser', id, 'terminal', 'file']);
    });

    test('docking onto a collapsed pane opens it', () {
      final l = sampleLayout()
          .collapse('b')
          .dock('file', const DockTarget.pane('b', DockZone.center));
      expect(l.leaf('b')!.collapsed, isFalse);
    });
  });

  group('resize, even, collapse, maximise', () {
    test('resize moves weight between two siblings', () {
      final l = sampleLayout().resize('root', 0, 0.25);
      final w = rootSplit(l).weights;
      expect(w[0] / (w[0] + w[1]), closeTo(0.25, 1e-9));
      expect(w[0] + w[1], closeTo(2, 1e-9));
    });

    test('evenSplit averages a pair', () {
      final l = sampleLayout().resize('root', 0, 0.2).evenSplit('root', 0);
      final w = rootSplit(l).weights;
      expect(w[0], w[1]);
    });

    test('collapse keeps the weights; restore brings the size back', () {
      final start = sampleLayout().resize('root', 0, 0.3);
      final collapsed = start.collapse('b');
      expect(collapsed.leaf('b')!.collapsed, isTrue);
      expect(rootSplit(collapsed).weights, rootSplit(start).weights);
      expect(collapsed.restore('b'), start);
    });

    test('the last open sibling cannot collapse', () {
      final l = sampleLayout().collapse('b');
      expect(identical(l.collapse('right'), l), isTrue);
      expect(l.toggleCollapse('b').leaf('b')!.collapsed, isFalse);
    });

    test('a collapsed node can be a split', () {
      final l = sampleLayout().collapse('right');
      expect((l.node('right')! as WorkspaceSplit).collapsed, isTrue);
    });

    test('maximise and toggle', () {
      final l = sampleLayout().maximise('t');
      expect(l.maximised, 't');
      expect(l.toggleMaximise('t').maximised, isNull);
      expect(l.toggleMaximise('b').maximised, 'b');
      expect(l.unmaximise().maximised, isNull);
      expect(identical(l.maximise('zzz'), l), isTrue);
    });

    test(
      'activate shows a tab, makes it front and opens collapsed parents',
      () {
        final l = sampleLayout()
            .addTab(leafId: 'b', kind: 'file')
            .collapse('b')
            .activate('browser');
        expect(l.leaf('b')!.active, 'browser');
        expect(l.front, 'browser');
        expect(l.leaf('b')!.collapsed, isFalse);
      },
    );
  });

  group('unfold', () {
    test('restores a node the user folded', () {
      final l = sampleLayout().collapse('b');
      expect(l.unfold('b', {'t', 'f'}).leaf('b')!.collapsed, isFalse);
    });

    test(
      'an auto-folded node takes the weight of the smallest visible one',
      () {
        final l = sampleLayout();
        final root = l.root! as WorkspaceSplit;
        expect(root.weights, [1, 1]);
        final next = l.unfold('b', {'right', 't', 'f'}).root! as WorkspaceSplit;
        expect(next.weights[0], greaterThan(next.weights[1]));
        expect(l.unfold('b', <String>{}), l);
      },
    );
  });

  group('JSON', () {
    test('the layout survives a round trip, with collapse and maximise', () {
      final l = sampleLayout()
          .addTab(leafId: 'b', kind: 'file', title: 'usage/mod.rs')
          .resize('root', 0, 0.4)
          .collapse('t')
          .maximise('b');
      final back = WorkspaceLayout.fromJson(l.toJson());
      expect(back, l);
      expect(back.toJson(), l.toJson());
    });

    test('a controller encodes and decodes', () {
      final c = WorkspaceController(sampleLayout());
      final other = WorkspaceController()..decode(c.encode());
      expect(other.layout, c.layout);
    });

    test('a malformed document throws a FormatException', () {
      expect(
        () => WorkspaceLayout.fromJson({
          'root': {'type': 'blob', 'id': 'x'},
        }),
        throwsFormatException,
      );
      expect(
        () => WorkspaceLayout.fromJson({
          'root': {'type': 'leaf', 'id': 'x', 'tabs': <Object?>[]},
        }),
        throwsFormatException,
      );
    });
  });

  group('controller', () {
    test('operations notify; no-ops do not', () {
      final c = WorkspaceController(sampleLayout());
      var n = 0;
      c.addListener(() => n++);
      c.collapse('b');
      expect(n, 1);
      c.collapse('b');
      expect(n, 1);
      c.restore('b');
      c.toggleMaximise('t');
      c.resize('root', 0, 0.3);
      c.evenSplit('root', 0);
      c.closeTab('file');
      c.dock('terminal', const DockTarget.pane('b', DockZone.center));
      expect(n, 7);
      expect(shape(c.layout), ['browser+terminal']);
    });
  });

  group('geometry', () {
    const m = WorkspaceMetrics();

    test('weights share the room; dividers take their gap', () {
      final g = layoutWorkspace(sampleLayout().root, const Size(1008, 600), m);
      expect(g.leaves['b']!.width, closeTo(500, .01));
      expect(g.leaves['t']!.width, closeTo(500, .01));
      expect(g.dividers.length, 2);
      expect(g.dividers.first.rect.width, 8);
    });

    test('a pane never renders below its minimum', () {
      final l = sampleLayout().resize('root', 0, 0.02);
      final g = layoutWorkspace(l.root, const Size(1008, 600), m);
      expect(g.leaves['b']!.width, closeTo(200, .01));
      expect(g.leaves['t']!.width, closeTo(800, .01));
    });

    test('when the minimums do not fit, the smallest folds to an edge tab', () {
      final l = sampleLayout().resize('root', 0, 0.3);
      final g = layoutWorkspace(l.root, const Size(400, 600), m);
      expect(g.leaves.containsKey('b'), isFalse);
      final tab = g.edgeTab('b')!;
      expect(tab.auto, isTrue);
      expect(tab.rect.width, 28);
      expect(g.leaves['t']!.width, closeTo(400 - 28 - 8, .01));
    });

    test('a column folds by height', () {
      final g = layoutWorkspace(sampleLayout().root, const Size(1008, 200), m);
      expect(g.edgeTab('f')!.rect.height, 28);
      expect(g.leaves['t']!.height, closeTo(200 - 28 - 8, .01));
    });

    test('a collapsed node keeps the edge tab width; its divider is off', () {
      final l = sampleLayout().collapse('b');
      final g = layoutWorkspace(l.root, const Size(1008, 600), m);
      expect(g.edgeTab('b')!.auto, isFalse);
      expect(g.edgeTab('b')!.rect.width, 28);
      expect(g.dividers.first.enabled, isFalse);
      expect(g.nodes['right']!.width, closeTo(1008 - 28 - 8, .01));
    });
  });
}
