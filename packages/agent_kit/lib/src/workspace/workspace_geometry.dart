// Lays the split tree out in a rectangle: pure maths, no widgets.
//
// Panes never render below their minimum. When a split cannot hold all its
// open children at their minimums, the smallest folds to an edge tab (an
// "auto" collapse that is derived on every layout and so reverses by itself
// when there is room again). Children below their minimum otherwise take
// room from larger siblings.

import 'dart:ui';

import 'workspace_model.dart';

/// Sizes the geometry needs (from `KitLayout`).
class WorkspaceMetrics {
  const WorkspaceMetrics({
    this.minWidth = 200,
    this.minHeight = 120,
    this.edgeTab = 28,
    this.divider = 8,
  });

  final double minWidth;
  final double minHeight;

  /// Thickness of a collapsed node's edge tab.
  final double edgeTab;

  /// Thickness of the gap (and drag handle) between siblings.
  final double divider;

  double minAlong(SplitAxis axis) => axis.isRow ? minWidth : minHeight;
}

/// A drag handle between two siblings of a split.
class DividerSpec {
  const DividerSpec({
    required this.splitId,
    required this.index,
    required this.axis,
    required this.rect,
    required this.enabled,
    required this.prevId,
    required this.nextId,
    required this.pairStart,
    required this.pairExtent,
    required this.prevMin,
    required this.nextMin,
  });

  final String splitId;

  /// The divider sits between children [index] and [index] + 1.
  final int index;

  /// The axis of the split (a row has vertical dividers).
  final SplitAxis axis;
  final Rect rect;

  /// False next to a collapsed sibling.
  final bool enabled;
  final String prevId, nextId;

  /// Where the two siblings start along the axis, and how much room they
  /// share, in the geometry's coordinates.
  final double pairStart, pairExtent;

  /// The smallest size either may have along the axis.
  final double prevMin, nextMin;
}

/// A collapsed node: its slim tab.
class EdgeTabSpec {
  const EdgeTabSpec({
    required this.nodeId,
    required this.rect,
    required this.axis,
    required this.auto,
  });

  final String nodeId;
  final Rect rect;

  /// The axis of the parent split: a row has vertical tabs.
  final SplitAxis axis;

  /// Folded because there is no room, not by the user.
  final bool auto;
}

/// The result of [layoutWorkspace].
class WorkspaceGeometry {
  const WorkspaceGeometry({
    required this.bounds,
    required this.nodes,
    required this.leaves,
    required this.dividers,
    required this.edgeTabs,
  });

  final Rect bounds;

  /// The rectangle of every open node (leaves and splits).
  final Map<String, Rect> nodes;

  /// The rectangle of every open leaf.
  final Map<String, Rect> leaves;
  final List<DividerSpec> dividers;
  final List<EdgeTabSpec> edgeTabs;

  EdgeTabSpec? edgeTab(String nodeId) {
    for (final e in edgeTabs) {
      if (e.nodeId == nodeId) return e;
    }
    return null;
  }
}

/// The smallest size [node] may have along [axis].
double minAlong(
  WorkspaceNode node,
  SplitAxis axis,
  WorkspaceMetrics m, {
  Set<String> autoCollapsed = const {},
}) {
  switch (node) {
    case WorkspaceLeaf():
      return m.minAlong(axis);
    case WorkspaceSplit():
      final open = [
        for (final c in node.children)
          if (!c.collapsed && !autoCollapsed.contains(c.id)) c,
      ];
      final shut = node.children.length - open.length;
      if (node.axis == axis) {
        var sum = (node.children.length - 1) * m.divider + shut * m.edgeTab;
        for (final c in open) {
          sum += minAlong(c, axis, m, autoCollapsed: autoCollapsed);
        }
        return sum;
      }
      var most = 0.0;
      for (final c in open) {
        final v = minAlong(c, axis, m, autoCollapsed: autoCollapsed);
        if (v > most) most = v;
      }
      return most;
  }
}

/// Lays [root] out in [size].
WorkspaceGeometry layoutWorkspace(
  WorkspaceNode? root,
  Size size,
  WorkspaceMetrics m,
) {
  final bounds = Offset.zero & size;
  final nodes = <String, Rect>{};
  final leaves = <String, Rect>{};
  final dividers = <DividerSpec>[];
  final edgeTabs = <EdgeTabSpec>[];

  void place(WorkspaceNode any, Rect rect) {
    nodes[any.id] = rect;
    if (any is WorkspaceLeaf) {
      leaves[any.id] = rect;
      return;
    }
    final node = any as WorkspaceSplit;
    final axis = node.axis;
    final isRow = axis.isRow;
    final n = node.children.length;
    final extent = isRow ? rect.width : rect.height;
    final gaps = (n - 1) * m.divider;
    final shut = <String>{
      for (final c in node.children)
        if (c.collapsed) c.id,
    };
    final auto = <String>{};

    double avail() => extent - gaps - (shut.length + auto.length) * m.edgeTab;
    bool isOpen(WorkspaceNode c) =>
        !shut.contains(c.id) && !auto.contains(c.id);

    // Fold the smallest open child while the open ones cannot all fit.
    while (true) {
      final open = [
        for (var i = 0; i < n; i++)
          if (isOpen(node.children[i])) i,
      ];
      if (open.length < 2) break;
      var need = 0.0;
      for (final i in open) {
        need += minAlong(node.children[i], axis, m, autoCollapsed: auto);
      }
      if (need <= avail() + 0.01) break;
      var small = open.first;
      for (final i in open) {
        if (node.weights[i] < node.weights[small]) small = i;
      }
      auto.add(node.children[small].id);
    }

    // Sizes of the open children: by weight, lifting any below its minimum
    // by taking from the others in proportion to their spare room.
    final open = [
      for (var i = 0; i < n; i++)
        if (isOpen(node.children[i])) i,
    ];
    final total = open.fold<double>(0, (a, i) => a + node.weights[i]);
    final room = avail();
    final sizes = <int, double>{};
    final mins = <int, double>{};
    for (final i in open) {
      sizes[i] = total <= 0
          ? room / open.length
          : room * node.weights[i] / total;
      mins[i] = minAlong(node.children[i], axis, m, autoCollapsed: auto);
    }
    var lack = 0.0;
    var spare = 0.0;
    for (final i in open) {
      if (sizes[i]! < mins[i]!) {
        lack += mins[i]! - sizes[i]!;
      } else {
        spare += sizes[i]! - mins[i]!;
      }
    }
    if (lack > 0 && spare > 0) {
      final take = lack > spare ? spare : lack;
      for (final i in open) {
        if (sizes[i]! < mins[i]!) {
          sizes[i] = mins[i]!;
        } else {
          sizes[i] = sizes[i]! - take * (sizes[i]! - mins[i]!) / spare;
        }
      }
    }

    // Place the children and the dividers between them.
    final starts = <double>[];
    var pos = isRow ? rect.left : rect.top;
    for (var i = 0; i < n; i++) {
      final c = node.children[i];
      final len = isOpen(c) ? sizes[i]! : m.edgeTab;
      starts.add(pos);
      final r = isRow
          ? Rect.fromLTWH(pos, rect.top, len, rect.height)
          : Rect.fromLTWH(rect.left, pos, rect.width, len);
      if (isOpen(c)) {
        place(c, r);
      } else {
        edgeTabs.add(
          EdgeTabSpec(
            nodeId: c.id,
            rect: r,
            axis: axis,
            auto: auto.contains(c.id) && !shut.contains(c.id),
          ),
        );
      }
      pos += len;
      if (i < n - 1) {
        final g = isRow
            ? Rect.fromLTWH(pos, rect.top, m.divider, rect.height)
            : Rect.fromLTWH(rect.left, pos, rect.width, m.divider);
        final next = node.children[i + 1];
        dividers.add(
          DividerSpec(
            splitId: node.id,
            index: i,
            axis: axis,
            rect: g,
            enabled: isOpen(c) && isOpen(next),
            prevId: c.id,
            nextId: next.id,
            pairStart: starts[i],
            pairExtent: len + (isOpen(next) ? sizes[i + 1]! : m.edgeTab),
            prevMin: isOpen(c)
                ? minAlong(c, axis, m, autoCollapsed: auto)
                : m.edgeTab,
            nextMin: isOpen(next)
                ? minAlong(next, axis, m, autoCollapsed: auto)
                : m.edgeTab,
          ),
        );
        pos += m.divider;
      }
    }
  }

  if (root != null) {
    place(root.withCollapsed(false), bounds);
  }
  return WorkspaceGeometry(
    bounds: bounds,
    nodes: nodes,
    leaves: leaves,
    dividers: dividers,
    edgeTabs: edgeTabs,
  );
}
