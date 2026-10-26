// The workspace model: an immutable split tree and the pure operations on it.
//
// Leaves are panes ("tab groups") holding tabs; splits are rows or columns of
// children with weights (the mockup's `--f`). Every operation is a method of
// [WorkspaceLayout] that returns a new layout (or the same instance when
// nothing changed), so they are testable without widgets. The whole layout
// serialises to JSON for hosts that persist it. This is UI state: it lives in
// agent_kit, not in agent_kit_core.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// The direction a split lays out its children in.
enum SplitAxis {
  /// Side by side (vertical dividers).
  row,

  /// Stacked (horizontal dividers).
  column;

  bool get isRow => this == row;
}

/// An edge of a pane, or of the whole workspace.
enum DockSide {
  left,
  right,
  top,
  bottom;

  /// The axis of the split a drop on this side makes.
  SplitAxis get axis =>
      this == left || this == right ? SplitAxis.row : SplitAxis.column;

  /// Whether the dropped pane goes before (left of, above) the target.
  bool get before => this == left || this == top;
}

/// The five drop zones of a pane.
enum DockZone {
  left,
  right,
  top,
  bottom,

  /// Add as a tab of the pane's group.
  center;

  /// The side of a split zone, or null for [center].
  DockSide? get side => switch (this) {
    left => DockSide.left,
    right => DockSide.right,
    top => DockSide.top,
    bottom => DockSide.bottom,
    center => null,
  };
}

/// Where a dragged tab lands: a zone of a pane, or the outer edge of the
/// workspace (a full-height or full-width split).
@immutable
class DockTarget {
  const DockTarget.pane(this.leafId, this.zone) : edge = null;
  const DockTarget.outer(this.edge) : leafId = null, zone = null;

  final String? leafId;
  final DockZone? zone;
  final DockSide? edge;

  bool get isOuter => edge != null;

  @override
  bool operator ==(Object other) =>
      other is DockTarget &&
      other.leafId == leafId &&
      other.zone == zone &&
      other.edge == edge;

  @override
  int get hashCode => Object.hash(leafId, zone, edge);

  @override
  String toString() =>
      isOuter ? 'DockTarget.outer($edge)' : 'DockTarget.pane($leafId, $zone)';
}

/// One pane content: [kind] says what it is (the host's builder keys on it)
/// and [id] which one. [title] overrides the kind's label.
@immutable
class WorkspaceTab {
  const WorkspaceTab({required this.id, required this.kind, this.title});

  final String id;
  final String kind;
  final String? title;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    if (title != null) 'title': title,
  };

  factory WorkspaceTab.fromJson(Map<String, Object?> json) => WorkspaceTab(
    id: _string(json, 'id'),
    kind: _string(json, 'kind'),
    title: json['title'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is WorkspaceTab &&
      other.id == id &&
      other.kind == kind &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, kind, title);

  @override
  String toString() => 'WorkspaceTab($id, $kind)';
}

/// A node of the split tree. [collapsed] folds it to an edge tab in its
/// parent split; the weights stay, so restoring brings back the old size.
@immutable
sealed class WorkspaceNode {
  const WorkspaceNode(this.id, this.collapsed);

  final String id;
  final bool collapsed;

  WorkspaceNode withCollapsed(bool value);

  Map<String, Object?> toJson();

  factory WorkspaceNode.fromJson(Map<String, Object?> json) {
    final type = _string(json, 'type');
    final collapsed = json['collapsed'] == true;
    switch (type) {
      case 'leaf':
        final tabs = [
          for (final t in _list(json, 'tabs')) WorkspaceTab.fromJson(_map(t)),
        ];
        if (tabs.isEmpty) throw const FormatException('A pane has no tabs.');
        final active = json['active'] as String?;
        return WorkspaceLeaf(
          id: _string(json, 'id'),
          tabs: tabs,
          active: tabs.any((t) => t.id == active) ? active : null,
          collapsed: collapsed,
        );
      case 'split':
        final children = [
          for (final c in _list(json, 'children'))
            WorkspaceNode.fromJson(_map(c)),
        ];
        final weights = [
          for (final w in _list(json, 'weights')) (w as num).toDouble(),
        ];
        if (children.length != weights.length || children.isEmpty) {
          throw const FormatException('Split children and weights differ.');
        }
        return WorkspaceSplit(
          id: _string(json, 'id'),
          axis: _string(json, 'axis') == 'column'
              ? SplitAxis.column
              : SplitAxis.row,
          children: children,
          weights: weights,
          collapsed: collapsed,
        );
    }
    throw FormatException('Unknown node type "$type".');
  }
}

/// A pane: a group of tabs, one of them showing.
final class WorkspaceLeaf extends WorkspaceNode {
  WorkspaceLeaf({
    required String id,
    required List<WorkspaceTab> tabs,
    String? active,
    bool collapsed = false,
  }) : assert(tabs.isNotEmpty),
       assert(active == null || tabs.any((t) => t.id == active)),
       tabs = List.unmodifiable(tabs),
       active = active ?? tabs.first.id,
       super(id, collapsed);

  final List<WorkspaceTab> tabs;

  /// The id of the tab that shows.
  final String active;

  WorkspaceTab get activeTab => tabs.firstWhere((t) => t.id == active);

  WorkspaceTab? tabById(String id) {
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  WorkspaceLeaf copyWith({
    List<WorkspaceTab>? tabs,
    String? active,
    bool? collapsed,
  }) => WorkspaceLeaf(
    id: id,
    tabs: tabs ?? this.tabs,
    active: active ?? this.active,
    collapsed: collapsed ?? this.collapsed,
  );

  @override
  WorkspaceLeaf withCollapsed(bool value) =>
      value == collapsed ? this : copyWith(collapsed: value);

  @override
  Map<String, Object?> toJson() => {
    'type': 'leaf',
    'id': id,
    if (collapsed) 'collapsed': true,
    'active': active,
    'tabs': [for (final t in tabs) t.toJson()],
  };
}

/// A row or column of [children] sharing the space by [weights].
final class WorkspaceSplit extends WorkspaceNode {
  WorkspaceSplit({
    required String id,
    required this.axis,
    required List<WorkspaceNode> children,
    List<double>? weights,
    bool collapsed = false,
  }) : assert(weights == null || weights.length == children.length),
       children = List.unmodifiable(children),
       weights = List.unmodifiable(
         weights ?? List<double>.filled(children.length, 1),
       ),
       super(id, collapsed);

  final SplitAxis axis;
  final List<WorkspaceNode> children;
  final List<double> weights;

  WorkspaceSplit copyWith({
    List<WorkspaceNode>? children,
    List<double>? weights,
    bool? collapsed,
  }) => WorkspaceSplit(
    id: id,
    axis: axis,
    children: children ?? this.children,
    weights: weights ?? (children == null ? this.weights : null),
    collapsed: collapsed ?? this.collapsed,
  );

  @override
  WorkspaceSplit withCollapsed(bool value) =>
      value == collapsed ? this : copyWith(collapsed: value);

  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'id': id,
    'axis': axis.name,
    if (collapsed) 'collapsed': true,
    'weights': weights,
    'children': [for (final c in children) c.toJson()],
  };
}

const Object _keep = Object();

/// The whole workspace state: the tree, the maximised pane and the front tab
/// (the one shown when the tree flattens into tabs).
@immutable
class WorkspaceLayout {
  const WorkspaceLayout({this.root, this.maximised, this.front});

  const WorkspaceLayout.empty() : root = null, maximised = null, front = null;

  /// The tree; null when there is no pane.
  final WorkspaceNode? root;

  /// The id of the maximised leaf, if any.
  final String? maximised;

  /// The id of the tab shown when the area is medium or compact. Also the
  /// last tab the user touched, which new panes dock beside.
  final String? front;

  // ----- JSON -----

  Map<String, Object?> toJson() => {
    'version': 1,
    if (root != null) 'root': root!.toJson(),
    if (maximised != null) 'maximised': maximised,
    if (front != null) 'front': front,
  };

  /// Reads a layout written by [toJson]. Throws [FormatException] on a
  /// malformed document.
  factory WorkspaceLayout.fromJson(Map<String, Object?> json) {
    final rootJson = json['root'];
    final root = rootJson == null
        ? null
        : WorkspaceNode.fromJson(_map(rootJson));
    return WorkspaceLayout(
      root: root,
      maximised: json['maximised'] as String?,
      front: json['front'] as String?,
    )._tidy();
  }

  // ----- queries -----

  bool get isEmpty => root == null;

  /// Every leaf, in tree order.
  List<WorkspaceLeaf> get leaves => [if (root != null) ..._leavesOf(root!)];

  /// Every tab, in tree order.
  List<WorkspaceTab> get tabs => [for (final l in leaves) ...l.tabs];

  WorkspaceNode? node(String id) => root == null ? null : _find(root!, id);

  WorkspaceLeaf? leaf(String id) {
    final n = node(id);
    return n is WorkspaceLeaf ? n : null;
  }

  WorkspaceLeaf? leafOfTab(String tabId) {
    for (final l in leaves) {
      if (l.tabById(tabId) != null) return l;
    }
    return null;
  }

  WorkspaceTab? tab(String tabId) => leafOfTab(tabId)?.tabById(tabId);

  /// The split that holds [id], or null for the root.
  WorkspaceSplit? parentOf(String id) =>
      root == null ? null : _parent(root!, id);

  /// The tab to show when the tree is flattened.
  WorkspaceTab? get frontTab {
    final f = front == null ? null : tab(front!);
    if (f != null) return f;
    final all = tabs;
    return all.isEmpty ? null : all.first;
  }

  /// The leaf [frontTab] is in.
  WorkspaceLeaf? get frontLeaf {
    final f = frontTab;
    return f == null ? null : leafOfTab(f.id);
  }

  // ----- operations -----

  /// Adds a new pane for [kind], beside [besideLeaf] (default: the front
  /// pane's leaf): right of it in a row, below it in a column. The first
  /// pane becomes the root.
  WorkspaceLayout addPane({
    required String kind,
    String? title,
    String? besideLeaf,
  }) {
    final tab = WorkspaceTab(id: _freshId('t'), kind: kind, title: title);
    final fresh = WorkspaceLeaf(id: _freshId('p'), tabs: [tab]);
    final r = root;
    if (r == null) {
      return _rebuild(fresh, front: tab.id, maximised: null);
    }
    final target = besideLeaf != null && leaf(besideLeaf) != null
        ? besideLeaf
        : (frontLeaf ?? leaves.first).id;
    final parent = _parent(r, target);
    final side = parent != null && parent.axis == SplitAxis.column
        ? DockSide.bottom
        : DockSide.right;
    return _rebuild(
      _insertBeside(r, target, side, fresh),
      front: tab.id,
      maximised: null,
    );
  }

  /// Splits [leafId]: a new pane for [kind] goes on [side] of it.
  WorkspaceLayout split({
    required String leafId,
    required DockSide side,
    required String kind,
    String? title,
  }) {
    if (leaf(leafId) == null) return this;
    final tab = WorkspaceTab(id: _freshId('t'), kind: kind, title: title);
    final fresh = WorkspaceLeaf(id: _freshId('p'), tabs: [tab]);
    return _rebuild(
      _insertBeside(root!, leafId, side, fresh),
      front: tab.id,
      maximised: null,
    );
  }

  /// Adds a tab for [kind] to the group [leafId] and shows it.
  WorkspaceLayout addTab({
    required String leafId,
    required String kind,
    String? title,
  }) {
    final l = leaf(leafId);
    if (l == null) return this;
    final tab = WorkspaceTab(id: _freshId('t'), kind: kind, title: title);
    return _rebuild(
      _replace(
        root!,
        leafId,
        (_) => l.copyWith(tabs: [...l.tabs, tab], active: tab.id),
      ),
      front: tab.id,
    )._uncollapsePath(leafId);
  }

  /// Closes a tab. An emptied pane goes too; emptied splits unwrap.
  WorkspaceLayout closeTab(String tabId) {
    final l = leafOfTab(tabId);
    if (l == null) return this;
    if (l.tabs.length == 1) {
      return _rebuild(
        _replace(root!, l.id, (_) => null),
        front: front == tabId ? null : front,
      );
    }
    final i = l.tabs.indexWhere((t) => t.id == tabId);
    final rest = [...l.tabs]..removeAt(i);
    final active = l.active == tabId
        ? rest[math.min(i, rest.length - 1)].id
        : l.active;
    return _rebuild(
      _replace(root!, l.id, (_) => l.copyWith(tabs: rest, active: active)),
      front: front == tabId ? active : front,
    );
  }

  /// Closes the tab showing in [leafId].
  WorkspaceLayout closeLeaf(String leafId) {
    final l = leaf(leafId);
    return l == null ? this : closeTab(l.active);
  }

  /// Shows [tabId] in its group, and as the front tab.
  WorkspaceLayout activate(String tabId) {
    final l = leafOfTab(tabId);
    if (l == null) return this;
    if (l.active == tabId && front == tabId && !_pathCollapsed(l.id)) {
      return this;
    }
    return _rebuild(
      _replace(root!, l.id, (_) => l.copyWith(active: tabId)),
      front: tabId,
    )._uncollapsePath(l.id);
  }

  /// Moves [tabId] to [target]. Dropping a lone tab on its own pane does
  /// nothing; centre on the own group does nothing either.
  WorkspaceLayout dock(String tabId, DockTarget target) {
    final src = leafOfTab(tabId);
    final r = root;
    if (src == null || r == null) return this;
    final tab = src.tabById(tabId)!;
    final targetId = target.isOuter ? r.id : target.leafId;
    if (targetId == null || node(targetId) == null) return this;
    if (!target.isOuter && targetId == src.id) {
      if (target.zone == DockZone.center || src.tabs.length == 1) return this;
    }
    // 1. Take the tab out of its group.
    WorkspaceNode? without;
    if (src.tabs.length == 1) {
      without = _replace(r, src.id, (_) => null);
    } else {
      final i = src.tabs.indexWhere((t) => t.id == tabId);
      final rest = [...src.tabs]..removeAt(i);
      final active = src.active == tabId
          ? rest[math.min(i, rest.length - 1)].id
          : src.active;
      without = _replace(
        r,
        src.id,
        (_) => src.copyWith(tabs: rest, active: active),
      );
    }
    if (without == null) return this;
    final base = without;
    // 2. Put it at the target.
    final WorkspaceNode? tree;
    if (!target.isOuter && target.zone == DockZone.center) {
      final dest = leaf(target.leafId!)!;
      tree = _replace(
        base,
        dest.id,
        (_) => dest.copyWith(
          tabs: [...dest.tabs, tab],
          active: tab.id,
          collapsed: false,
        ),
      );
    } else {
      final side = target.isOuter ? target.edge! : target.zone!.side!;
      final fresh = WorkspaceLeaf(
        id: src.tabs.length == 1 ? src.id : _freshId('p'),
        tabs: [tab],
      );
      tree = _insertBeside(
        base,
        target.isOuter ? base.id : target.leafId!,
        side,
        fresh,
      );
    }
    final moved = _rebuild(tree, front: tabId, maximised: null);
    final dest = moved.leafOfTab(tabId);
    return dest == null ? moved : moved._uncollapsePath(dest.id);
  }

  /// Gives the child [index] of split [splitId] the fraction [share] (0 to 1)
  /// of the combined weight of it and its next sibling.
  WorkspaceLayout resize(String splitId, int index, double share) {
    final s = node(splitId);
    if (s is! WorkspaceSplit || index < 0 || index + 1 >= s.children.length) {
      return this;
    }
    final total = s.weights[index] + s.weights[index + 1];
    final a = total * share.clamp(0.0, 1.0);
    final w = [...s.weights];
    w[index] = a;
    w[index + 1] = total - a;
    return _rebuild(_replace(root!, splitId, (_) => s.copyWith(weights: w)));
  }

  /// Makes child [index] of split [splitId] and its next sibling even.
  WorkspaceLayout evenSplit(String splitId, int index) {
    final s = node(splitId);
    if (s is! WorkspaceSplit || index < 0 || index + 1 >= s.children.length) {
      return this;
    }
    final avg = (s.weights[index] + s.weights[index + 1]) / 2;
    final w = [...s.weights];
    w[index] = avg;
    w[index + 1] = avg;
    return _rebuild(_replace(root!, splitId, (_) => s.copyWith(weights: w)));
  }

  /// Folds [nodeId] to an edge tab. At least one sibling must stay open.
  WorkspaceLayout collapse(String nodeId) {
    final n = node(nodeId);
    final p = parentOf(nodeId);
    if (n == null || p == null || n.collapsed) return this;
    final open = p.children.where((c) => !c.collapsed && c.id != nodeId);
    if (open.isEmpty) return this;
    return _rebuild(
      _replace(root!, nodeId, (x) => x.withCollapsed(true)),
      maximised: maximised != null && _contains(n, maximised!)
          ? null
          : maximised,
    );
  }

  /// Opens a collapsed node at the size it had before.
  WorkspaceLayout restore(String nodeId) {
    final n = node(nodeId);
    if (n == null || !n.collapsed) return this;
    return _rebuild(_replace(root!, nodeId, (x) => x.withCollapsed(false)));
  }

  WorkspaceLayout toggleCollapse(String nodeId) {
    final n = node(nodeId);
    if (n == null) return this;
    return n.collapsed ? restore(nodeId) : collapse(nodeId);
  }

  /// Maximises [leafId] over the whole area.
  WorkspaceLayout maximise(String leafId) {
    if (leaf(leafId) == null || maximised == leafId) return this;
    return _rebuild(root, maximised: leafId)._uncollapsePath(leafId);
  }

  /// Puts a maximised pane back.
  WorkspaceLayout unmaximise() =>
      maximised == null ? this : _rebuild(root, maximised: null);

  WorkspaceLayout toggleMaximise(String leafId) =>
      maximised == leafId ? unmaximise() : maximise(leafId);

  // ----- internals -----

  WorkspaceLayout _rebuild(
    WorkspaceNode? newRoot, {
    Object? maximised = _keep,
    Object? front = _keep,
  }) => WorkspaceLayout(
    root: newRoot,
    maximised: identical(maximised, _keep)
        ? this.maximised
        : maximised as String?,
    front: identical(front, _keep) ? this.front : front as String?,
  )._tidy();

  /// Normalises the tree and drops references to things that are gone.
  WorkspaceLayout _tidy() {
    final r = root == null ? null : _normalize(root!);
    final layout = WorkspaceLayout(root: r, maximised: maximised, front: front);
    final max = layout.maximised;
    final fr = layout.front;
    final fixedMax = max != null && layout.leaf(max) != null ? max : null;
    final fixedFront = fr != null && layout.tab(fr) != null
        ? fr
        : (layout.tabs.isEmpty ? null : layout.tabs.first.id);
    if (fixedMax == max && fixedFront == fr && identical(r, root)) return this;
    return WorkspaceLayout(root: r, maximised: fixedMax, front: fixedFront);
  }

  bool _pathCollapsed(String leafId) {
    bool go(WorkspaceNode n) {
      if (!_contains(n, leafId)) return false;
      if (n.collapsed) return true;
      return n is WorkspaceSplit && n.children.any(go);
    }

    return root != null && go(root!);
  }

  WorkspaceLayout _uncollapsePath(String leafId) {
    if (!_pathCollapsed(leafId)) return this;
    WorkspaceNode go(WorkspaceNode n) {
      if (!_contains(n, leafId)) return n;
      final open = n.withCollapsed(false);
      if (open is WorkspaceSplit) {
        return open.copyWith(
          children: [for (final c in open.children) go(c)],
          weights: open.weights,
        );
      }
      return open;
    }

    return WorkspaceLayout(root: go(root!), maximised: maximised, front: front);
  }

  String _freshId(String prefix) {
    final used = <String>{};
    void walk(WorkspaceNode n) {
      used.add(n.id);
      if (n is WorkspaceLeaf) {
        for (final t in n.tabs) {
          used.add(t.id);
        }
      } else if (n is WorkspaceSplit) {
        n.children.forEach(walk);
      }
    }

    if (root != null) walk(root!);
    var i = 1;
    while (used.contains('$prefix$i')) {
      i++;
    }
    return '$prefix$i';
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceLayout &&
      other.maximised == maximised &&
      other.front == front &&
      _jsonEquals(other.root?.toJson(), root?.toJson());

  @override
  int get hashCode => Object.hash(maximised, front, root?.toJson().toString());
}

// ----- tree helpers -----

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

List<WorkspaceLeaf> _leavesOf(WorkspaceNode n) => switch (n) {
  WorkspaceLeaf() => [n],
  WorkspaceSplit() => [for (final c in n.children) ..._leavesOf(c)],
};

WorkspaceNode? _find(WorkspaceNode n, String id) {
  if (n.id == id) return n;
  if (n is WorkspaceSplit) {
    for (final c in n.children) {
      final f = _find(c, id);
      if (f != null) return f;
    }
  }
  return null;
}

bool _contains(WorkspaceNode n, String id) => _find(n, id) != null;

WorkspaceSplit? _parent(WorkspaceNode n, String id) {
  if (n is! WorkspaceSplit) return null;
  for (final c in n.children) {
    if (c.id == id) return n;
    final p = _parent(c, id);
    if (p != null) return p;
  }
  return null;
}

/// Replaces node [id] by what [f] returns (null removes it). The result is
/// not normalised.
WorkspaceNode? _replace(
  WorkspaceNode n,
  String id,
  WorkspaceNode? Function(WorkspaceNode) f,
) {
  if (n.id == id) return f(n);
  if (n is! WorkspaceSplit) return n;
  final kids = <WorkspaceNode>[];
  final ws = <double>[];
  var changed = false;
  for (var i = 0; i < n.children.length; i++) {
    final c = _replace(n.children[i], id, f);
    if (!identical(c, n.children[i])) changed = true;
    if (c != null) {
      kids.add(c);
      ws.add(n.weights[i]);
    }
  }
  if (!changed) return n;
  if (kids.isEmpty) return null;
  return WorkspaceSplit(
    id: n.id,
    axis: n.axis,
    children: kids,
    weights: ws,
    collapsed: n.collapsed,
  );
}

/// Drops empty splits, unwraps one-child splits, merges same-axis nesting
/// and keeps at least one child of each split open.
WorkspaceNode? _normalize(WorkspaceNode n) {
  if (n is! WorkspaceSplit) return n;
  final kids = <WorkspaceNode>[];
  final ws = <double>[];
  var changed = false;
  for (var i = 0; i < n.children.length; i++) {
    final c = _normalize(n.children[i]);
    if (!identical(c, n.children[i])) changed = true;
    if (c == null) continue;
    final w = n.weights[i];
    if (c is WorkspaceSplit && c.axis == n.axis && !c.collapsed) {
      final sum = c.weights.fold<double>(0, (a, b) => a + b);
      for (var j = 0; j < c.children.length; j++) {
        kids.add(c.children[j]);
        ws.add(sum == 0 ? w / c.children.length : w * c.weights[j] / sum);
      }
      changed = true;
    } else {
      kids.add(c);
      ws.add(w);
    }
  }
  if (kids.isEmpty) return null;
  if (kids.length == 1) return kids.single.withCollapsed(n.collapsed);
  if (kids.every((k) => k.collapsed)) {
    kids[0] = kids[0].withCollapsed(false);
    changed = true;
  }
  if (!changed) return n;
  return WorkspaceSplit(
    id: n.id,
    axis: n.axis,
    children: kids,
    weights: ws,
    collapsed: n.collapsed,
  );
}

/// Inserts [fresh] on [side] of node [targetId]. Beside a child of a split of
/// the same axis it shares that child's weight; otherwise the target is
/// wrapped in a new split.
WorkspaceNode _insertBeside(
  WorkspaceNode root,
  String targetId,
  DockSide side,
  WorkspaceLeaf fresh,
) {
  final axis = side.axis;
  final before = side.before;
  final target = _find(root, targetId)!;
  final parent = _parent(root, targetId);
  if (parent != null && parent.axis == axis) {
    final i = parent.children.indexWhere((c) => c.id == targetId);
    final half = parent.weights[i] / 2;
    final kids = [...parent.children];
    final ws = [...parent.weights];
    ws[i] = half;
    final at = before ? i : i + 1;
    kids.insert(at, fresh);
    ws.insert(at, half);
    return _replace(
      root,
      parent.id,
      (_) => WorkspaceSplit(
        id: parent.id,
        axis: parent.axis,
        children: kids,
        weights: ws,
        collapsed: parent.collapsed,
      ),
    )!;
  }
  if (parent == null && target is WorkspaceSplit && target.axis == axis) {
    // The outer edge of a root split of the same axis.
    final avg =
        target.weights.fold<double>(0, (a, b) => a + b) / target.weights.length;
    final kids = before
        ? [fresh, ...target.children]
        : [...target.children, fresh];
    final ws = before ? [avg, ...target.weights] : [...target.weights, avg];
    return WorkspaceSplit(
      id: target.id,
      axis: axis,
      children: kids,
      weights: ws,
    );
  }
  // Wrap the target. Around the root the old tree keeps twice the room.
  final wrapId = _wrapId(root);
  final inner = target.withCollapsed(false);
  final wrapped = WorkspaceSplit(
    id: wrapId,
    axis: axis,
    children: before ? [fresh, inner] : [inner, fresh],
    weights: parent == null
        ? (before ? <double>[1, 2] : <double>[2, 1])
        : <double>[1, 1],
    collapsed: target.collapsed,
  );
  return _replace(root, targetId, (_) => wrapped)!;
}

String _wrapId(WorkspaceNode root) {
  final used = <String>{};
  void walk(WorkspaceNode n) {
    used.add(n.id);
    if (n is WorkspaceLeaf) {
      for (final t in n.tabs) {
        used.add(t.id);
      }
    } else if (n is WorkspaceSplit) {
      n.children.forEach(walk);
    }
  }

  walk(root);
  var i = 1;
  while (used.contains('s$i')) {
    i++;
  }
  return 's$i';
}

// ----- JSON helpers -----

String _string(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw FormatException('Expected a string at "$key".');
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is List) return v.cast<Object?>();
  throw FormatException('Expected a list at "$key".');
}

Map<String, Object?> _map(Object? v) {
  if (v is Map) return v.cast<String, Object?>();
  throw const FormatException('Expected an object.');
}
