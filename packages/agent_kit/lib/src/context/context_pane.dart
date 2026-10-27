// ContextPane: what the agent remembers and what was compacted (scene F of
// the approved mockup). A meter on top, three tabs (Now, History,
// Compactions) and, on the Now tab, the detail of one summary.
//
// The pane is fed, not wired: it takes the serving view, the details the
// host loaded and two loaders (original messages by range, one summary's
// full text). `AgentContextPane` is the composition that loads them from a
// backend. The layout follows the pane's own width: from
// `KitLayout.contextSplit` the detail sits beside the list, narrower it
// replaces the list behind a back button (Esc also goes back).

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import '../transcript/markdown.dart';
import '../transcript/transcript_support.dart';
import 'context_history.dart';
import 'context_meter_bar.dart';
import 'context_now.dart';
import 'context_support.dart';
import 'context_timeline.dart';

export 'context_history.dart' show HistoryLoader;

/// Loads one summary with its full text.
typedef SummaryLoader = Future<ContextSummary> Function(String summaryId);

/// The pane's tabs.
enum ContextTab {
  /// The serving view as a stack.
  now,

  /// The original messages with chapters and episodes over them.
  history,

  /// Events over time.
  compactions,
}

/// Asks a [ContextPane] to show the Now tab, optionally on one summary. The
/// host keeps one per pane and calls it from the compaction marker and the
/// header's meter.
class ContextPaneController extends ChangeNotifier {
  String? _summaryId;
  int _token = 0;

  /// The summary of the last request, if any.
  String? get summaryId => _summaryId;

  /// Changes with every request.
  int get token => _token;

  /// Brings the Now tab forward, on [summaryId] when given.
  void showNow({String? summaryId}) {
    _summaryId = summaryId;
    _token++;
    notifyListeners();
  }
}

/// The Context pane.
class ContextPane extends StatefulWidget {
  const ContextPane({
    super.key,
    required this.view,
    this.details,
    this.loadHistory,
    this.loadSummary,
    this.controller,
    this.renderer = const LeanMarkdownRenderer(),
    this.now,
    this.initialTab = ContextTab.now,
    this.initialSummaryId,
  });

  /// The serving view (`ChatSnapshot.context`).
  final ContextView view;

  /// The structure behind it; null until the host has loaded it.
  final ContextDetails? details;

  /// Loads original messages for the History tab.
  final HistoryLoader? loadHistory;

  /// Loads a summary's full text for the detail.
  final SummaryLoader? loadSummary;
  final ContextPaneController? controller;

  /// Renders summary text.
  final MarkdownRenderer renderer;

  /// Replaces the wall clock (tests, the gallery).
  final DateTime? now;
  final ContextTab initialTab;

  /// The summary the detail starts on.
  final String? initialSummaryId;

  @override
  State<ContextPane> createState() => _ContextPaneState();
}

class _ContextPaneState extends State<ContextPane> {
  late ContextTab _tab = widget.initialTab;
  String? _selected;
  bool _detailOpen = false;
  final _paneFocus = FocusNode(debugLabel: 'context-pane', skipTraversal: true);
  String? _flashId;
  int _flashToken = 0;
  String? _historyTarget;
  int _historyToken = 0;
  final Map<String, ContextSummary> _full = {};
  final Set<String> _asked = {};
  final Map<String, GlobalKey> _keys = {};
  final _nowScroll = ScrollController();
  final _detailScroll = ScrollController();
  final _historyScroll = ScrollController();
  final _eventsScroll = ScrollController();
  Timer? _flashTimer;
  int _lastRequest = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSummaryId;
    _detailOpen = widget.initialSummaryId != null;
    _lastRequest = widget.controller?.token ?? 0;
    widget.controller?.addListener(_onRequest);
  }

  @override
  void didUpdateWidget(ContextPane old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onRequest);
      widget.controller?.addListener(_onRequest);
      _lastRequest = widget.controller?.token ?? 0;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRequest);
    _flashTimer?.cancel();
    _nowScroll.dispose();
    _detailScroll.dispose();
    _historyScroll.dispose();
    _eventsScroll.dispose();
    _paneFocus.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void _onRequest() {
    final c = widget.controller;
    if (c == null || c.token == _lastRequest) return;
    _lastRequest = c.token;
    final id = c.summaryId;
    setState(() {
      _tab = ContextTab.now;
      _detailOpen = false;
      if (id != null) {
        _selected = id;
        _flash(id);
      }
    });
    if (id != null) _reveal(id);
  }

  void _flash(String id) {
    _flashId = id;
    _flashToken++;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  void _reveal(String id) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(id).currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: .2,
        duration: BbTheme.reducedMotion(context)
            ? Duration.zero
            : context.bb.motion.standard,
        curve: context.bb.motion.ease,
      );
    });
  }

  void _select(String id) {
    setState(() {
      _selected = id;
      _detailOpen = true;
    });
    // A click does not focus anything; keep Esc working from the pane.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_paneFocus.hasFocus) _paneFocus.requestFocus();
    });
  }

  void _back() => setState(() => _detailOpen = false);

  void _goSummary(String id) {
    setState(() {
      _tab = ContextTab.now;
      _selected = id;
      _detailOpen = false;
      _flash(id);
    });
    _reveal(id);
  }

  void _goEpisode(String id) {
    setState(() {
      _tab = ContextTab.history;
      _historyTarget = 'ep:$id';
      _historyToken++;
      _flash('ep:$id');
    });
  }

  void _ensureText(String id) {
    final sum = widget.details?.summary(id);
    final load = widget.loadSummary;
    if (sum == null || sum.text.isNotEmpty || load == null) return;
    if (_full.containsKey(id) || !_asked.add(id)) return;
    load(id).then<void>(
      (s) {
        if (mounted) setState(() => _full[id] = s);
      },
      onError: (Object _) {
        if (mounted) setState(() => _full[id] = sum);
      },
    );
  }

  String? _defaultSelection(ContextView view) {
    for (final b in view.blocks) {
      if (b.summaryId != null) return b.summaryId;
    }
    return view.pendingEpisodeIds.isEmpty
        ? null
        : widget.details
              ?.episode(view.pendingEpisodeIds.first)
              ?.summaryId;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _detailOpen &&
        _tab == ContextTab.now) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final view = widget.view;
    final details = widget.details;
    final applied = details?.events
        .where((e) => e.kind == ContextEventKind.applied)
        .length;
    return Focus(
      focusNode: _paneFocus,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: t.surface,
        child: LayoutBuilder(
          builder: (context, box) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.colors.borderSubtle),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ContextMeterBar(view: view),
                        const SizedBox(height: 10),
                        _Tabs(
                          tab: _tab,
                          compactionCount: applied,
                          onSelect: (tab) => setState(() => _tab = tab),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _panel(context, box.maxWidth)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, double width) {
    final wide = width >= context.bb.layout.contextSplit;
    final view = widget.view;
    final details = widget.details;
    switch (_tab) {
      case ContextTab.now:
        final selectedId = _selected ?? (wide ? _defaultSelection(view) : null);
        if (selectedId != null) {
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => _ensureText(selectedId),
          );
        }
        final summary = selectedId == null
            ? null
            : _full[selectedId] ?? details?.summary(selectedId);
        final list = SingleChildScrollView(
          controller: _nowScroll,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          child: ContextNow(
            view: view,
            details: details,
            selected: selectedId,
            onSelect: _select,
            keyFor: _keyFor,
            flashId: _flashId,
            flashToken: _flashToken,
          ),
        );
        Widget detail({bool back = false}) => summary == null || details == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                controller: _detailScroll,
                child: ContextDetail(
                  key: ValueKey('context-detail-${summary.id}'),
                  summary: summary,
                  details: details,
                  now: widget.now ?? DateTime.now(),
                  renderer: widget.renderer,
                  loading:
                      widget.loadSummary != null &&
                      !_full.containsKey(summary.id),
                  onBack: back ? _back : null,
                  onGoEpisode: _goEpisode,
                ),
              );
        return _tabpanel(
          'What the model sees now',
          wide
              ? Row(
                  children: [
                    Expanded(child: list),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: context.bb.colors.borderSubtle,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        width: (width * .46).clamp(300.0, 440.0),
                        child: summary == null
                            ? const SizedBox.shrink()
                            : detail(),
                      ),
                    ),
                  ],
                )
              : (_detailOpen && summary != null ? detail(back: true) : list),
        );
      case ContextTab.history:
        return _tabpanel(
          'Original history',
          details == null
              ? const _Loading()
              : ContextHistory(
                  view: view,
                  details: details,
                  loadHistory: widget.loadHistory,
                  keyFor: _keyFor,
                  flashId: _flashId,
                  flashToken: _flashToken,
                  targetId: _historyTarget,
                  targetToken: _historyToken,
                  onGoSummary: _goSummary,
                  controller: _historyScroll,
                ),
        );
      case ContextTab.compactions:
        return _tabpanel(
          'Compactions over time',
          details == null
              ? const _Loading()
              : SingleChildScrollView(
                  controller: _eventsScroll,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  child: ContextTimeline(
                    view: view,
                    details: details,
                    onGoSummary: _goSummary,
                  ),
                ),
        );
    }
  }

  Widget _tabpanel(String label, Widget child) => Semantics(
    container: true,
    label: label,
    explicitChildNodes: true,
    child: child,
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Loading…',
        style: ts(t.typeScale.ui, t.faint, weight: 400),
      ),
    );
  }
}

/// The tab strip: a roving tab stop, Left and Right, Home and End move and
/// select.
class _Tabs extends StatefulWidget {
  const _Tabs({
    required this.tab,
    required this.compactionCount,
    required this.onSelect,
  });

  final ContextTab tab;
  final int? compactionCount;
  final ValueChanged<ContextTab> onSelect;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  final _nodes = [for (final _ in ContextTab.values) FocusNode(skipTraversal: false)];

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final count = ContextTab.values.length;
    final i = widget.tab.index;
    final key = event.logicalKey;
    int? next;
    if (key == LogicalKeyboardKey.arrowRight) {
      next = (i + 1) % count;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      next = (i - 1 + count) % count;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = count - 1;
    }
    if (next == null) return KeyEventResult.ignored;
    widget.onSelect(ContextTab.values[next]);
    final target = _nodes[next];
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) target.requestFocus();
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final touch = isTouch(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        label: 'Context views',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: [
              for (final tab in ContextTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: _TabButton(
                    node: _nodes[tab.index],
                    label: switch (tab) {
                      ContextTab.now => 'Now',
                      ContextTab.history => 'History',
                      ContextTab.compactions => 'Compactions',
                    },
                    glyph: switch (tab) {
                      ContextTab.now => glyphLayers,
                      ContextTab.history => glyphHistory,
                      ContextTab.compactions => glyphFoldVertical,
                    },
                    count: tab == ContextTab.compactions
                        ? widget.compactionCount
                        : null,
                    selected: widget.tab == tab,
                    height: touch ? 40 : 34,
                    onTap: () {
                      widget.onSelect(tab);
                      final node = _nodes[tab.index];
                      SchedulerBinding.instance.addPostFrameCallback((_) {
                        if (mounted) node.requestFocus();
                      });
                    },
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.node,
    required this.label,
    required this.glyph,
    required this.selected,
    required this.height,
    required this.onTap,
    this.count,
  });

  final FocusNode node;
  final String label;
  final LucideGlyph glyph;
  final int? count;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: Focus(
        focusNode: node,
        canRequestFocus: selected,
        onKeyEvent: (n, e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.enter ||
                  e.logicalKey == LogicalKeyboardKey.space)) {
            onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Hover(
            onTap: onTap,
            borderRadius: t.radii.ctl,
            hoverBackground: t.hover,
            pressedBackground: t.pressed,
            lift: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomPaint(
              foregroundPainter: _TabMark(
                selected: selected,
                focused:
                    node.hasFocus &&
                    FocusManager.instance.highlightMode ==
                        FocusHighlightMode.traditional,
                ink: t.ink,
                focus: t.focus,
                radius: t.radii.ctl,
              ),
              child: SizedBox(
                height: height,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    glyphIcon(glyph, size: 14, color: t.colors.iconSecondary),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: ts(
                        t.typeScale.ui,
                        selected ? t.ink : t.muted,
                        weight: 600,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.pressed,
                          borderRadius: t.radii.pill,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text(
                            '$count',
                            style: tabular(
                              ts(const TypeSpec(11, 16, 600), t.muted),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ink underline of the selected tab and the focus ring.
class _TabMark extends CustomPainter {
  const _TabMark({
    required this.selected,
    required this.focused,
    required this.ink,
    required this.focus,
    required this.radius,
  });

  final bool selected, focused;
  final Color ink, focus;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (selected) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          size.height - 2,
          size.width,
          size.height,
          const Radius.circular(2),
        ),
        Paint()..color = ink,
      );
    }
    if (focused) {
      canvas.drawRRect(
        radius.toRRect(Offset.zero & size).deflate(1),
        Paint()
          ..color = focus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_TabMark old) =>
      old.selected != selected ||
      old.focused != focused ||
      old.ink != ink ||
      old.focus != focus;
}
