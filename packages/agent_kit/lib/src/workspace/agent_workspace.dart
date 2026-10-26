// AgentWorkspace: the tiling pane area beside the chat (mockup scene D).
//
// The kit owns the split tree, the dividers, the pane chrome (tabs, maximise,
// close, the + menu), collapse to edge tabs, docking by drag and the
// size-class behaviour. What a pane shows comes from the host through
// [AgentWorkspace.paneBuilder].
//
//   expanded  the split tree
//   medium    one column: a row of pane tabs above the front pane
//   compact   a full-screen sheet with pane tabs; the host opens it (`open`)
//             and gets `onClose` from the chevron
//
// Pane contents sit in one flat stack keyed by tab id, so a pane keeps its
// state when it is docked somewhere else.

import 'dart:math' as math;

import 'package:bb_ui/bb_ui.dart'
    show AppTooltip, Hover, LucideIcon, globalRectOf, ts;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';
import 'workspace_controller.dart';
import 'workspace_geometry.dart';
import 'workspace_model.dart';

/// A kind of pane the host can show: its label and icon, and a row of the
/// + menu.
@immutable
class WorkspaceKind {
  const WorkspaceKind({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;

  /// The mockup's four kinds (the + menu of scene D).
  static const browser = WorkspaceKind(
    id: 'browser',
    label: 'Browser',
    icon: WorkspaceIcons.globe,
  );
  static const terminal = WorkspaceKind(
    id: 'terminal',
    label: 'Terminal',
    icon: WorkspaceIcons.terminal,
  );
  static const file = WorkspaceKind(
    id: 'file',
    label: 'File',
    icon: WorkspaceIcons.fileCode,
  );
  static const activity = WorkspaceKind(
    id: 'activity',
    label: 'Activity',
    icon: WorkspaceIcons.activity,
  );

  /// Browser, Terminal, File and Activity, in the order of the mockup's menu.
  static const standard = [browser, terminal, file, activity];
}

/// Lucide glyphs the workspace and its host panes use that `bb_ui`'s `Ico`
/// does not have.
abstract final class WorkspaceIcons {
  static const IconData globe = LucideIcons.globe;
  static const IconData terminal = LucideIcons.terminal;
  static const IconData fileCode = LucideIcons.fileCode;
  static const IconData activity = LucideIcons.activity;
  static const IconData arrowLeft = LucideIcons.arrowLeft;
  static const IconData arrowRight = LucideIcons.arrowRight;
  static const IconData rotateCw = LucideIcons.rotateCw;
  static const IconData clock = LucideIcons.clock;
}

/// Builds what a pane shows. [tab] carries the pane [WorkspaceTab.kind] and
/// [WorkspaceTab.id].
typedef WorkspacePaneBuilder = Widget Function(
  BuildContext context,
  WorkspaceTab tab,
);

/// Height of a pane header (`.wp-head`).
const double _headerHeight = 32;

/// How far past a pane's minimum a divider drag goes before it previews
/// hiding the pane.
const double _snapPast = 24;

/// Distance from the outer edge where a drop makes a full-height or
/// full-width split.
const double _edgeZone = 22;

/// Fraction of a pane (from an edge) where a drop docks rather than adds a tab.
const double _zoneFraction = 0.28;

class AgentWorkspace extends StatefulWidget {
  const AgentWorkspace({
    super.key,
    required this.controller,
    required this.kinds,
    required this.paneBuilder,
    this.open = true,
    this.onClose,
    this.sizeClass,
  });

  /// The layout and its operations.
  final WorkspaceController controller;

  /// The kinds of pane, in the order of the + menu.
  final List<WorkspaceKind> kinds;

  /// What each pane shows.
  final WorkspacePaneBuilder paneBuilder;

  /// The size class to lay out for. By default the workspace measures its own
  /// width; a host that sizes the workspace from the area around it (as
  /// [AgentWorkbench] does) passes the area's class.
  final SizeClass? sizeClass;

  /// Compact only: whether the full-screen sheet is up.
  final bool open;

  /// Compact only: the sheet's chevron ("Back to chat").
  final VoidCallback? onClose;

  @override
  State<AgentWorkspace> createState() => _AgentWorkspaceState();
}

class _DockDrag {
  const _DockDrag({
    required this.tabId,
    required this.leafId,
    required this.pos,
    this.target,
  });

  final String tabId;
  final String leafId;

  /// Pointer position in the body's coordinates.
  final Offset pos;
  final DockTarget? target;

  _DockDrag moved(Offset pos, DockTarget? target) =>
      _DockDrag(tabId: tabId, leafId: leafId, pos: pos, target: target);
}

class _Pending {
  const _Pending(this.pointer, this.start, this.tabId, this.leafId);
  final int pointer;
  final Offset start;
  final String tabId;
  final String leafId;
}

class _DividerDrag {
  _DividerDrag(this.spec, this.startLayout, this.grab);
  final DividerSpec spec;
  final WorkspaceLayout startLayout;
  final double grab;
  String? snapId;
}

class _AgentWorkspaceState extends State<AgentWorkspace> {
  final _rootKey = GlobalKey();
  final _bodyKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'AgentWorkspace');

  WorkspaceGeometry? _geo;
  bool _expanded = true;

  _Pending? _pending;
  String? _chipTab;
  _DockDrag? _drag;

  _DividerDrag? _dividerDrag;

  bool _menuOpen = false;
  String? _menuLeaf;
  Rect _menuAnchor = Rect.zero;

  WorkspaceController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(AgentWorkspace old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  WorkspaceKind _kind(String id) {
    for (final k in widget.kinds) {
      if (k.id == id) return k;
    }
    return WorkspaceKind(id: id, label: id, icon: LucideIcons.panelLeft);
  }

  String _tabLabel(WorkspaceTab tab) => tab.title ?? _kind(tab.kind).label;

  String _nodeLabel(WorkspaceNode node) {
    final leaves = _leafList(node);
    return leaves.map((l) => _tabLabel(l.activeTab)).join(' · ');
  }

  IconData _nodeIcon(WorkspaceNode node) =>
      _kind(_leafList(node).first.activeTab.kind).icon;

  static List<WorkspaceLeaf> _leafList(WorkspaceNode n) => switch (n) {
    WorkspaceLeaf() => [n],
    WorkspaceSplit() => [for (final c in n.children) ..._leafList(c)],
  };

  // ----- menu -----

  void _openMenu(String? leafId, Rect anchor) {
    setState(() {
      _menuOpen = true;
      _menuLeaf = leafId;
      _menuAnchor = anchor;
    });
    _focus.requestFocus();
  }

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
  }

  void _pickKind(WorkspaceKind kind) {
    final leaf = _menuLeaf;
    setState(() => _menuOpen = false);
    _c.addPane(kind.id, besideLeaf: leaf);
  }

  // ----- dock by drag -----

  void _chipDown(PointerDownEvent e, String tabId) => _chipTab = tabId;

  void _headerDown(PointerDownEvent e, WorkspaceLeaf leaf) {
    final tab = _chipTab ?? leaf.active;
    _chipTab = null;
    if ((e.buttons & 0x01) == 0) return;
    if (!_expanded || _c.layout.maximised != null) return;
    _pending = _Pending(e.pointer, e.position, tab, leaf.id);
  }

  void _headerMove(PointerMoveEvent e) {
    final p = _pending;
    if (p == null || p.pointer != e.pointer) return;
    if (_drag == null) {
      if ((e.position - p.start).distance < 6) return;
      _focus.requestFocus();
      _drag = _DockDrag(
        tabId: p.tabId,
        leafId: p.leafId,
        pos: _local(e.position),
      );
    }
    final pos = _local(e.position);
    final geo = _geo;
    final target = geo == null
        ? null
        : hitDockTarget(pos, geo, _c.layout, _drag!.tabId);
    setState(() => _drag = _drag!.moved(pos, target));
  }

  void _headerUp(PointerUpEvent e) {
    final p = _pending;
    if (p == null || p.pointer != e.pointer) return;
    _pending = null;
    final d = _drag;
    if (d == null) return;
    setState(() => _drag = null);
    final target = d.target;
    if (target != null) _c.dock(d.tabId, target);
  }

  void _headerCancel(PointerCancelEvent e) {
    if (_pending?.pointer != e.pointer) return;
    _pending = null;
    if (_drag != null) setState(() => _drag = null);
  }

  Offset _local(Offset global) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_drag != null) {
        setState(() {
          _drag = null;
          _pending = null;
        });
        return KeyEventResult.handled;
      }
      if (_dividerDrag != null) {
        _dividerEnd(commit: false);
        return KeyEventResult.handled;
      }
      if (_menuOpen) {
        _closeMenu();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ----- dividers -----

  void _dividerStart(DividerSpec spec, Offset global) {
    final local = _local(global);
    final along = spec.axis.isRow ? local.dx : local.dy;
    final from = spec.axis.isRow ? spec.rect.left : spec.rect.top;
    _dividerDrag = _DividerDrag(spec, _c.layout, along - from);
    setState(() {});
  }

  void _dividerUpdate(Offset global) {
    final d = _dividerDrag;
    if (d == null) return;
    final spec = d.spec;
    final local = _local(global);
    final along = spec.axis.isRow ? local.dx : local.dy;
    final raw = along - d.grab - spec.pairStart;
    final total = spec.pairExtent;
    final lo = spec.prevMin;
    final hi = total - spec.nextMin;
    String? snap;
    if (raw < lo - _snapPast) {
      snap = spec.prevId;
    } else if (raw > hi + _snapPast) {
      snap = spec.nextId;
    }
    final pos = hi < lo ? total / 2 : raw.clamp(lo, hi).toDouble();
    d.snapId = snap;
    _c.layout = d.startLayout.resize(spec.splitId, spec.index, pos / total);
    setState(() {});
  }

  void _dividerEnd({bool commit = true}) {
    final d = _dividerDrag;
    if (d == null) return;
    _dividerDrag = null;
    if (!commit) {
      _c.layout = d.startLayout;
    } else if (d.snapId != null) {
      // Collapse at the size it had before the drag, so the edge tab
      // restores that size.
      _c.layout = d.startLayout.collapse(d.snapId!);
    }
    setState(() {});
  }

  void _dividerNudge(DividerSpec spec, double delta) {
    final prev =
        (spec.axis.isRow ? spec.rect.left : spec.rect.top) - spec.pairStart;
    final lo = spec.prevMin;
    final hi = spec.pairExtent - spec.nextMin;
    if (hi < lo) return;
    final pos = (prev + delta).clamp(lo, hi).toDouble();
    _c.resize(spec.splitId, spec.index, pos / spec.pairExtent);
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    Widget buildFor(BuildContext context, SizeClass sizeClass) {
      _expanded = sizeClass.isExpanded;
      final layout = _c.layout;
      final Widget body;
      if (layout.isEmpty) {
        body = _buildEmpty(context, t);
      } else if (sizeClass.isExpanded) {
        body = _buildTree(context, t, layout);
      } else {
        body = _buildTabbed(context, t, layout, sizeClass.isCompact);
      }
      Widget result = body;
      if (sizeClass.isCompact) {
        final dur = BbTheme.reducedMotion(context)
            ? Duration.zero
            : t.motion.sheet;
        result = ExcludeSemantics(
          excluding: !widget.open,
          child: IgnorePointer(
            ignoring: !widget.open,
            child: AnimatedSlide(
              offset: Offset(0, widget.open ? 0 : 1),
              duration: dur,
              curve: t.motion.ease,
              child: result,
            ),
          ),
        );
      }
      return Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: Semantics(
          container: true,
          label: 'Workspace',
          child: Stack(
            key: _rootKey,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: result),
              if (_menuOpen) ..._buildMenu(context, t),
            ],
          ),
        ),
      );
    }

    final forced = widget.sizeClass;
    if (forced == null) return SizeClassBuilder(builder: buildFor);
    return SizeClassScope(
      sizeClass: forced,
      child: Builder(builder: (context) => buildFor(context, forced)),
    );
  }

  Widget _buildEmpty(BuildContext context, BbTheme t) => DecoratedBox(
    decoration: BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.seam),
      borderRadius: t.radii.panel,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No panes open', style: ts(t.typeScale.ui, t.muted)),
          SizedBox(height: t.spacing.sm),
          Builder(
            builder: (context) => _HeadButton(
              key: const ValueKey('wp-add-empty'),
              icon: LucideIcons.plus,
              label: 'Add pane',
              onTap: () => _openMenu(null, globalRectOf(context)),
            ),
          ),
        ],
      ),
    ),
  );

  // ----- expanded: the tree -----

  Widget _buildTree(BuildContext context, BbTheme t, WorkspaceLayout layout) {
    final metrics = WorkspaceMetrics(
      minWidth: t.layout.paneMinWidth,
      minHeight: t.layout.paneMinHeight,
      edgeTab: t.layout.edgeTab,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 1000,
          constraints.hasBoundedHeight ? constraints.maxHeight : 600,
        );
        final geo = layoutWorkspace(layout.root, size, metrics);
        _geo = geo;
        final max = layout.maximised;
        final snapNode = _dividerDrag?.snapId;
        final snapLeaves = <String>{
          if (snapNode != null && layout.node(snapNode) != null)
            for (final l in _leafList(layout.node(snapNode)!)) l.id,
        };
        final drag = _drag;
        final dragLeaf = drag == null
            ? null
            : (layout.leaf(drag.leafId)?.tabs.length == 1 ? drag.leafId : null);

        // Only the last pane that can still split shows +; a new pane goes
        // beside it (right, or below in a column), so it needs room for two.
        String? adder;
        for (final leaf in layout.leaves) {
          final r = max == null ? geo.leaves[leaf.id] : geo.bounds;
          if (r == null || (max != null && max != leaf.id)) continue;
          final parent = layout.parentOf(leaf.id);
          final below = parent != null && parent.axis == SplitAxis.column;
          final need =
              2 * (below ? metrics.minHeight : metrics.minWidth) +
              metrics.divider;
          if ((below ? r.height : r.width) >= need) adder = leaf.id;
        }
        final frames = <Widget>[];
        final contents = <Widget>[];
        for (final leaf in layout.leaves) {
          final placed = max == leaf.id ? geo.bounds : geo.leaves[leaf.id];
          final rect = placed ?? Rect.zero;
          // A collapsed pane keeps its content (off screen) so it keeps its
          // state.
          final hidden = placed == null || (max != null && max != leaf.id);
          final dim = snapLeaves.contains(leaf.id)
              ? .32
              : (dragLeaf == leaf.id ? .4 : 1.0);
          if (placed != null) {
            frames.add(
              Positioned.fromRect(
                key: ValueKey('wp-leaf-${leaf.id}'),
                rect: rect,
                child: Offstage(
                  offstage: hidden,
                  child: Opacity(
                    opacity: dim,
                    child: _buildFrame(
                      context,
                      t,
                      layout,
                      leaf,
                      max == leaf.id,
                      adder == leaf.id,
                    ),
                  ),
                ),
              ),
            );
          }
          final body = Rect.fromLTRB(
            rect.left + 1,
            rect.top + 1 + _headerHeight,
            rect.right - 1,
            rect.bottom - 1,
          );
          final tab = leaf.activeTab;
          contents.add(
            Positioned.fromRect(
              key: ValueKey('wp-content-${tab.id}'),
              rect: body.width < 0 || body.height < 0 ? Rect.zero : body,
              child: Offstage(
                offstage: hidden,
                child: Opacity(
                  opacity: dim,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(9),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('wp-pane-${tab.id}'),
                      child: widget.paneBuilder(context, tab),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final overlay = <Widget>[];
        if (max == null) {
          for (final spec in geo.dividers) {
            overlay.add(
              Positioned.fromRect(
                key: ValueKey('wp-divider-${spec.splitId}-${spec.index}'),
                rect: spec.rect,
                child: _Divider(
                  spec: spec,
                  dragging:
                      _dividerDrag?.spec.splitId == spec.splitId &&
                      _dividerDrag?.spec.index == spec.index,
                  onStart: (p) => _dividerStart(spec, p),
                  onUpdate: _dividerUpdate,
                  onEnd: (commit) => _dividerEnd(commit: commit),
                  onEven: () => _c.evenSplit(spec.splitId, spec.index),
                  onNudge: (d) => _dividerNudge(spec, d),
                ),
              ),
            );
          }
          for (final e in geo.edgeTabs) {
            final node = layout.node(e.nodeId);
            if (node == null) continue;
            overlay.add(
              Positioned.fromRect(
                key: ValueKey('wp-edge-${e.nodeId}'),
                rect: e.rect,
                child: _EdgeTab(
                  label: _nodeLabel(node),
                  icon: _nodeIcon(node),
                  vertical: e.axis.isRow,
                  enabled: true,
                  onTap: () => _c.unfold(e.nodeId, geo.nodes.keys.toSet()),
                ),
              ),
            );
          }
          final snapRect = snapNode == null ? null : geo.nodes[snapNode];
          if (snapNode != null && snapRect != null) {
            overlay.add(
              Positioned.fromRect(
                rect: snapRect,
                child: IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _Pill(
                        key: const ValueKey('wp-snap-hint'),
                        text:
                            'Release to hide ${_nodeLabel(layout.node(snapNode)!)}',
                        inverse: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        if (drag != null && drag.target != null) {
          final r = dockPreviewRect(drag.target!, geo);
          if (r != null) {
            overlay.add(
              AnimatedPositioned(
                key: const ValueKey('wp-dock-preview'),
                duration: BbTheme.reducedMotion(context)
                    ? Duration.zero
                    : t.motion.fast,
                curve: t.motion.ease,
                left: r.left,
                top: r.top,
                width: r.width,
                height: r.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.information.withValues(alpha: .72),
                      borderRadius: t.radii.field,
                      border: Border.all(color: t.threadStrong, width: 1.5),
                    ),
                    child: Center(
                      child: _Pill(text: dockCaption(drag.target!)),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        if (drag != null) {
          final tab = layout.tab(drag.tabId);
          if (tab != null) {
            overlay.add(
              Positioned(
                key: const ValueKey('wp-dock-ghost'),
                left: drag.pos.dx + 14,
                top: drag.pos.dy + 12,
                child: IgnorePointer(
                  child: _Pill(
                    text: _tabLabel(tab),
                    icon: _kind(tab.kind).icon,
                    ghost: true,
                  ),
                ),
              ),
            );
          }
        }

        return Stack(
          key: _bodyKey,
          clipBehavior: Clip.none,
          children: [...frames, ...contents, ...overlay],
        );
      },
    );
  }

  /// The pane's border, background and header (the content goes above it).
  Widget _buildFrame(
    BuildContext context,
    BbTheme t,
    WorkspaceLayout layout,
    WorkspaceLeaf leaf,
    bool maximised,
    bool showAdd,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.seam),
        borderRadius: t.radii.panel,
        boxShadow: maximised ? t.colors.seamHover : null,
      ),
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: _buildHeader(context, t, leaf, maximised, showAdd),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    BbTheme t,
    WorkspaceLeaf leaf,
    bool maximised,
    bool showAdd,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.seam)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: MouseRegion(
                cursor: maximised ? MouseCursor.defer : SystemMouseCursors.grab,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _headerDown(e, leaf),
                  onPointerMove: _headerMove,
                  onPointerUp: _headerUp,
                  onPointerCancel: _headerCancel,
                  child: ClipRect(
                    child: Row(
                      children: [
                        for (final tab in leaf.tabs)
                          Flexible(
                            child: Listener(
                              onPointerDown: (e) => _chipDown(e, tab.id),
                              child: _TabChip(
                                key: ValueKey('wp-tab-${tab.id}'),
                                label: _tabLabel(tab),
                                icon: _kind(tab.kind).icon,
                                selected: tab.id == leaf.active,
                                onTap: () => _c.activate(tab.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showAdd)
              Builder(
                builder: (context) => _HeadButton(
                  key: ValueKey('wp-add-${leaf.id}'),
                  icon: LucideIcons.plus,
                  label: 'Add pane',
                  onTap: () => _openMenu(leaf.id, globalRectOf(context)),
                ),
              ),
            _HeadButton(
              key: ValueKey('wp-max-${leaf.id}'),
              icon: maximised ? LucideIcons.minimize2 : LucideIcons.maximize2,
              label: maximised ? 'Restore pane' : 'Maximise pane',
              size: 14,
              onTap: () => _c.toggleMaximise(leaf.id),
            ),
            _HeadButton(
              key: ValueKey('wp-close-${leaf.id}'),
              icon: LucideIcons.x,
              label: 'Close pane',
              size: 14,
              onTap: () => _c.closeLeaf(leaf.id),
            ),
          ],
        ),
      ),
    );
  }

  // ----- medium and compact: one column of tabs -----

  Widget _buildTabbed(
    BuildContext context,
    BbTheme t,
    WorkspaceLayout layout,
    bool compact,
  ) {
    final tabs = layout.tabs;
    final front = layout.frontTab!;
    final bar = SizedBox(
      height: compact ? 52 : 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: compact ? Border(bottom: BorderSide(color: t.seam)) : null,
        ),
        child: Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(8, 0, 4, 0)
              : EdgeInsets.zero,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: const ValueKey('wp-ws-tabs'),
                    children: [
                      for (final tab in tabs)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: _TabChip(
                            key: ValueKey('wp-ws-tab-${tab.id}'),
                            label: _tabLabel(tab),
                            icon: _kind(tab.kind).icon,
                            selected: tab.id == front.id,
                            height: compact ? 36 : 24,
                            onTap: () => _c.activate(tab.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Builder(
                builder: (context) => _HeadButton(
                  key: const ValueKey('wp-ws-add'),
                  icon: LucideIcons.plus,
                  label: 'Add pane',
                  size: compact ? 18 : 16,
                  box: compact ? 40 : 26,
                  onTap: () =>
                      _openMenu(layout.frontLeaf?.id, globalRectOf(context)),
                ),
              ),
              if (compact)
                _HeadButton(
                  key: const ValueKey('wp-sheet-close'),
                  icon: LucideIcons.chevronDown,
                  label: 'Back to chat',
                  size: 18,
                  box: 40,
                  onTap: widget.onClose,
                ),
            ],
          ),
        ),
      ),
    );
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: compact ? null : Border.all(color: t.seam),
        borderRadius: compact ? null : t.radii.panel,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 0 : 1),
        child: ClipRRect(
          borderRadius: compact ? BorderRadius.zero : t.radii.panel,
          child: KeyedSubtree(
            key: ValueKey('wp-pane-${front.id}'),
            child: widget.paneBuilder(context, front),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: compact ? t.surface : const Color(0x00000000),
      child: Column(
        children: [
          bar,
          if (!compact) const SizedBox(height: 6),
          Expanded(
            child: SizedBox(width: double.infinity, child: pane),
          ),
        ],
      ),
    );
  }

  // ----- the + menu -----

  List<Widget> _buildMenu(BuildContext context, BbTheme t) {
    const width = 176.0;
    final root = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = root == null
        ? _menuAnchor
        : root.globalToLocal(_menuAnchor.topLeft) & _menuAnchor.size;
    final maxLeft = root == null
        ? 8.0
        : math.max(8.0, root.size.width - width - 8);
    final left = (anchor.right + 30 - width).clamp(8.0, maxLeft).toDouble();
    return [
      Positioned.fill(
        child: GestureDetector(
          key: const ValueKey('wp-menu-barrier'),
          behavior: HitTestBehavior.opaque,
          onTap: _closeMenu,
        ),
      ),
      Positioned(
        left: left,
        top: anchor.bottom + 4,
        width: width,
        child: DecoratedBox(
          key: const ValueKey('wp-menu'),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.thread),
            borderRadius: t.radii.panel,
            boxShadow: t.colors.seamHover,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Semantics(
              label: 'Add pane',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                    child: Text(
                      'Add pane',
                      style: ts(t.typeScale.uiSmall, t.faint),
                    ),
                  ),
                  for (final k in widget.kinds)
                    Hover(
                      key: ValueKey('wp-menu-${k.id}'),
                      onTap: () => _pickKind(k),
                      lift: 0,
                      hoverBackground: t.hover,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            LucideIcon(k.icon, size: 16, color: t.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                k.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ts(t.typeScale.ui, t.ink, weight: 400),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

// ----- dock geometry (pure) -----

/// The drop target under [p] (in the workspace's coordinates) for dragging
/// [tabId], or null when there is none or the drop would change nothing.
DockTarget? hitDockTarget(
  Offset p,
  WorkspaceGeometry geo,
  WorkspaceLayout layout,
  String tabId,
) {
  final b = geo.bounds;
  if (!b.contains(p)) return null;
  if (p.dx - b.left < _edgeZone) return const DockTarget.outer(DockSide.left);
  if (b.right - p.dx < _edgeZone) return const DockTarget.outer(DockSide.right);
  if (p.dy - b.top < _edgeZone) return const DockTarget.outer(DockSide.top);
  if (b.bottom - p.dy < _edgeZone) {
    return const DockTarget.outer(DockSide.bottom);
  }
  for (final e in geo.leaves.entries) {
    final r = e.value;
    if (!r.contains(p)) continue;
    final leaf = layout.leaf(e.key);
    if (leaf == null) continue;
    final own = leaf.tabById(tabId) != null;
    if (own && leaf.tabs.length == 1) return null;
    final fx = (p.dx - r.left) / r.width;
    final fy = (p.dy - r.top) / r.height;
    final d = {
      DockZone.left: fx,
      DockZone.right: 1 - fx,
      DockZone.top: fy,
      DockZone.bottom: 1 - fy,
    };
    var zone = DockZone.left;
    for (final z in d.keys) {
      if (d[z]! < d[zone]!) zone = z;
    }
    if (d[zone]! > _zoneFraction) zone = DockZone.center;
    if (own && zone == DockZone.center) return null;
    return DockTarget.pane(e.key, zone);
  }
  return null;
}

/// Where the dropped pane would land, for the translucent preview.
Rect? dockPreviewRect(DockTarget target, WorkspaceGeometry geo) {
  final b = geo.bounds;
  if (target.isOuter) {
    final w = b.width;
    final h = b.height;
    return switch (target.edge!) {
      DockSide.left => Rect.fromLTWH(0, 0, w / 3, h),
      DockSide.right => Rect.fromLTWH(w * 2 / 3, 0, w / 3, h),
      DockSide.top => Rect.fromLTWH(0, 0, w, h / 3),
      DockSide.bottom => Rect.fromLTWH(0, h * 2 / 3, w, h / 3),
    };
  }
  final r = geo.leaves[target.leafId];
  if (r == null) return null;
  return switch (target.zone!) {
    DockZone.center => r.deflate(6),
    DockZone.left => Rect.fromLTWH(r.left, r.top, r.width / 2, r.height),
    DockZone.right => Rect.fromLTWH(
      r.left + r.width / 2,
      r.top,
      r.width / 2,
      r.height,
    ),
    DockZone.top => Rect.fromLTWH(r.left, r.top, r.width, r.height / 2),
    DockZone.bottom => Rect.fromLTWH(
      r.left,
      r.top + r.height / 2,
      r.width,
      r.height / 2,
    ),
  };
}

/// The caption of the preview.
String dockCaption(DockTarget target) {
  if (target.isOuter) {
    return switch (target.edge!) {
      DockSide.left => 'Full height, left',
      DockSide.right => 'Full height, right',
      DockSide.top => 'Full width, top',
      DockSide.bottom => 'Full width, bottom',
    };
  }
  return switch (target.zone!) {
    DockZone.center => 'Add as tab',
    DockZone.left => 'Dock left',
    DockZone.right => 'Dock right',
    DockZone.top => 'Dock above',
    DockZone.bottom => 'Dock below',
  };
}

// ----- small widgets -----

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.height = 24,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      selected: selected,
      child: Hover(
        onTap: onTap,
        lift: 0,
        selected: selected,
        selectedColor: t.pressed,
        hoverBackground: t.hover,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LucideIcon(icon, size: 14, color: t.faint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(
                    t.typeScale.uiSmall,
                    selected ? t.ink : t.muted,
                    weight: selected ? 600 : 500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadButton extends StatelessWidget {
  const _HeadButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 16,
    this.box = 26,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double box;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return AppTooltip(
      label: label,
      child: Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          lift: 0,
          hoverBackground: t.hover,
          child: SizedBox(
            width: box,
            height: box,
            child: Center(
              child: LucideIcon(icon, size: size, color: t.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// The caption and ghost pill: ink on surface (the snap hint, inverse), or a
/// surface chip with a hairline (the preview caption and the drag ghost).
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.text,
    this.icon,
    this.inverse = false,
    this.ghost = false,
  });

  final String text;
  final IconData? icon;
  final bool inverse;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final fg = inverse ? t.surface : t.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inverse ? t.ink : t.surface,
        borderRadius: t.radii.pill,
        border: inverse ? null : Border.all(color: ghost ? t.thread : t.seam),
        boxShadow: ghost ? t.colors.seamHover : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: ghost ? 6 : 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              LucideIcon(icon!, size: 14, color: t.faint),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: ts(t.typeScale.uiSmall, fg, weight: 600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeTab extends StatelessWidget {
  const _EdgeTab({
    required this.label,
    required this.icon,
    required this.vertical,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// A tab on the side of a row split reads top to bottom.
  final bool vertical;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: ts(t.typeScale.uiSmall, t.muted, weight: 600),
    );
    final glyph = LucideIcon(icon, size: 14, color: t.faint);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Show $label',
      child: Hover(
        onTap: enabled ? onTap : null,
        lift: 0,
        background: t.surface,
        hoverBackground: t.hover,
        borderRadius: t.radii.field,
        border: Border.all(color: t.seam),
        child: ClipRect(
          child: vertical
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      glyph,
                      const SizedBox(height: 8),
                      Flexible(child: RotatedBox(quarterTurns: 1, child: text)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      glyph,
                      const SizedBox(width: 8),
                      Flexible(child: text),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// A drag handle: drag, double-click to even, arrow keys to nudge.
class _Divider extends StatefulWidget {
  const _Divider({
    required this.spec,
    required this.dragging,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onEven,
    required this.onNudge,
  });

  final DividerSpec spec;
  final bool dragging;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final ValueChanged<bool> onEnd;
  final VoidCallback onEven;
  final ValueChanged<double> onNudge;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  final _node = FocusNode(debugLabel: 'Divider');
  bool _hover = false;
  bool _focus = false;
  int? _pointer;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final spec = widget.spec;
    final row = spec.axis.isRow;
    if (!spec.enabled) return const SizedBox.expand();
    final lit = _hover || _focus || widget.dragging;
    final line = DecoratedBox(
      decoration: BoxDecoration(
        color: lit ? t.threadStrong : const Color(0x00000000),
        borderRadius: BorderRadius.circular(2),
      ),
      child: SizedBox(width: row ? 2 : null, height: row ? null : 2),
    );
    return Semantics(
      label: 'Resize panes',
      child: Focus(
        focusNode: _node,
        onFocusChange: (v) => setState(
          () => _focus =
              v &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional,
        ),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final step = HardwareKeyboard.instance.isShiftPressed ? 64.0 : 16.0;
          final k = event.logicalKey;
          if (row && k == LogicalKeyboardKey.arrowLeft ||
              !row && k == LogicalKeyboardKey.arrowUp) {
            widget.onNudge(-step);
            return KeyEventResult.handled;
          }
          if (row && k == LogicalKeyboardKey.arrowRight ||
              !row && k == LogicalKeyboardKey.arrowDown) {
            widget.onNudge(step);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.enter) {
            widget.onEven();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: row
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onEven,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (_pointer != null) return;
                _pointer = e.pointer;
                _node.requestFocus();
                widget.onStart(e.position);
              },
              onPointerMove: (e) {
                if (e.pointer == _pointer) widget.onUpdate(e.position);
              },
              onPointerUp: (e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                widget.onEnd(true);
              },
              onPointerCancel: (e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                widget.onEnd(false);
              },
              child: Padding(
                padding: row
                    ? const EdgeInsets.symmetric(horizontal: 3, vertical: 12)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: line,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
