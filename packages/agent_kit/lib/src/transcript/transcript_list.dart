// The transcript list: a lazy, scrolling column of items that
//
//  * follows the tail: while the view is at the bottom it stays there as
//    content arrives (new items, streaming text, an expanding row); scrolling
//    up lets go, and a "Jump to latest" button brings it back;
//  * restores an anchor: an item id and how far into it the view was, so a
//    chat reopens where it was left.
//
// The content column is centred at [TranscriptList.contentWidth] (the
// mockup's `--content-width`) with a 16 px minimum gutter.

import 'package:agent_kit_core/agent_kit_core.dart'
    show
        ActivityGroup,
        AssistantMessage,
        FileEdit,
        NoticeLine,
        PlanItem,
        TranscriptItem;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'plan_checklist.dart';
import 'transcript_item.dart';
import 'transcript_support.dart';

/// Where a transcript view was: the first visible item and how many px of it
/// were scrolled above the top edge.
@immutable
class TranscriptAnchor {
  const TranscriptAnchor(this.itemId, [this.offset = 0]);

  final String itemId;
  final double offset;

  @override
  bool operator ==(Object other) =>
      other is TranscriptAnchor &&
      other.itemId == itemId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(itemId, offset);

  @override
  String toString() => 'TranscriptAnchor($itemId, $offset)';
}

/// How the items of one turn (the run between two user messages) are ordered.
enum TurnLayout {
  /// As they happened: prose, edits and activity interleaved.
  chronological,

  /// The assistant's text first, then its file edits, then the activity
  /// groups, then notices; the order within each kind is kept.
  grouped,
}

/// Something other than a transcript item shown in the list, right after the
/// item [afterItemId] (the end of the transcript when that is null or no longer
/// there): a resolved question's answers, for one.
@immutable
class TranscriptInsert {
  const TranscriptInsert({
    required this.id,
    required this.child,
    this.afterItemId,
  });

  /// A stable id, unique among the items and inserts.
  final String id;

  final String? afterItemId;

  final Widget child;
}

/// Reads and drives a [TranscriptList].
class TranscriptController extends ChangeNotifier {
  _TranscriptListState? _state;

  /// Whether the list is following the tail.
  bool get following => _state?._following ?? true;

  /// Where the list is now, to save when the chat is left; null until it has
  /// content on screen.
  TranscriptAnchor? get anchor => _state?._computeAnchor();

  /// Scrolls to the newest content and follows it again.
  void jumpToLatest({bool animate = true}) =>
      _state?._jumpToLatest(animate: animate);

  /// Scrolls so [anchor]'s item is where it was.
  void restore(TranscriptAnchor anchor) => _state?._restore(anchor);

  void _changed() => notifyListeners();
}

/// An entry a host draws itself in a [TranscriptList] (see
/// [TranscriptList.entries]): a stable [id] and the widget.
@immutable
class TimelineEntry {
  const TimelineEntry({required this.id, required this.builder});

  /// Unique among the entries, stable while the entry lives (it keys the row
  /// and anchors the scroll position).
  final String id;

  final WidgetBuilder builder;
}

class TranscriptList extends StatefulWidget {
  const TranscriptList({
    super.key,
    this.items = const [],
    this.entries,
    this.actions = const TranscriptActions(),
    this.controller,
    this.initialAnchor,
    this.plan = const [],
    this.inserts = const [],
    this.leading,
    this.trailing,
    this.contentWidth = 720,
    this.followThreshold = 24,
    this.layout = TurnLayout.chronological,
    this.rowGap = 14,
    this.gapBefore,
    this.gutter = 16,
    this.padding,
    this.scroll,
    this.viewportKey,
  });

  /// The transcript, in order (`ChatSnapshot.items`).
  final List<TranscriptItem> items;

  /// Rows the host draws itself, in order, instead of [items] (Scratch's
  /// reference cards and turns, a block of summary cards above a boundary).
  /// The host's own pieces ride on the list's follow, anchor and gaps; when
  /// set, [items], [actions] and [layout] are not used.
  final List<TimelineEntry>? entries;

  final TranscriptActions actions;

  final TranscriptController? controller;

  /// Where to open instead of the tail.
  final TranscriptAnchor? initialAnchor;

  /// The plan checklist (`ChatSnapshot.plan`), shown before the first item
  /// when it has items.
  final List<PlanItem> plan;

  /// Extra entries between the items (see [TranscriptInsert]).
  final List<TranscriptInsert> inserts;

  /// Shown before the first item, after the plan (a notice).
  final Widget? leading;

  /// Shown after the last item (the interrupted notice, a typing mark).
  final Widget? trailing;

  /// The width of the content column.
  final double contentWidth;

  /// How near the bottom (px) still counts as at the bottom.
  final double followThreshold;

  /// How the items of a turn are ordered.
  final TurnLayout layout;

  /// The space above every row after the first, and above [trailing].
  final double rowGap;

  /// A different gap above the row [id] (after the row [previousId], null for
  /// the first); null keeps [rowGap].
  final double? Function(String? previousId, String id)? gapBefore;

  /// The space left and right of the column, inside [contentWidth].
  final double gutter;

  /// The list's padding; the default is 20 / 28 above and 40 below.
  final EdgeInsets? padding;

  /// The scroll controller, when the host reads or drives the position
  /// itself; the list makes its own otherwise and never disposes the host's.
  final ScrollController? scroll;

  /// The key of the scrolling viewport, for a host that measures rows.
  final GlobalKey? viewportKey;

  @override
  State<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<TranscriptList> {
  ScrollController? _ownScroll;
  ScrollController get _scroll =>
      widget.scroll ?? (_ownScroll ??= ScrollController());
  final GlobalKey _ownViewportKey = GlobalKey();
  GlobalKey get _viewportKey => widget.viewportKey ?? _ownViewportKey;
  bool _following = true;
  bool _programmatic = false;
  bool _stickScheduled = false;
  bool _built = false;
  TranscriptAnchor? _pending;
  int _restoreTries = 0;
  Map<String, int> _indexById = const {};

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    final anchor = widget.initialAnchor;
    if (anchor != null) {
      _following = false;
      _restore(anchor);
    } else {
      _scheduleStick();
    }
  }

  @override
  void didUpdateWidget(TranscriptList old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
    if (_following) _scheduleStick();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    _ownScroll?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ following

  void _setFollowing(bool value) {
    if (_following == value) return;
    // Scroll notifications can arrive while a frame is being laid out (the
    // content grew); a rebuild may not be scheduled then.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _nextFrame(() {
        if (mounted) _setFollowing(value);
      });
      return;
    }
    setState(() => _following = value);
    widget.controller?._changed();
  }

  /// The pill's distance from the bottom edge, and the length of the fade
  /// above it.
  static const _pillBottom = 12.0;
  static const _pillFade = 28.0;

  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    final p = _scroll.position;
    return p.maxScrollExtent - p.pixels <= widget.followThreshold;
  }

  void _nextFrame(VoidCallback callback) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => callback())
      ..scheduleFrame();
  }

  void _scheduleStick() {
    if (_stickScheduled) return;
    _stickScheduled = true;
    _nextFrame(() {
      _stickScheduled = false;
      if (!mounted || !_following || _programmatic || _pending != null) return;
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.pixels < p.maxScrollExtent - .5) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  bool _onNotification(Notification n) {
    if (n is ScrollMetricsNotification) {
      if (n.depth == 0 && _following) _scheduleStick();
    } else if (n is ScrollUpdateNotification) {
      if (n.depth == 0 && !_programmatic && _pending == null) {
        _setFollowing(_atBottom);
      }
    } else if (n is ScrollEndNotification) {
      if (n.depth == 0 && !_programmatic && _pending == null) {
        _setFollowing(_atBottom);
      }
    }
    return false;
  }

  Future<void> _jumpToLatest({bool animate = true}) async {
    if (!_scroll.hasClients) return;
    _pending = null;
    _setFollowing(true);
    final target = _scroll.position.maxScrollExtent;
    if (!animate || Motion.of(context).reduced) {
      _scroll.jumpTo(target);
      _scheduleStick();
      return;
    }
    _programmatic = true;
    try {
      await _scroll.animateTo(
        target,
        duration: Motion.standard,
        curve: Motion.ease,
      );
    } finally {
      _programmatic = false;
    }
    if (mounted) _scheduleStick();
  }

  // --------------------------------------------------------------- anchor

  List<_SlotInfo> _slots() {
    final root = _viewportKey.currentContext;
    final viewport = root?.findRenderObject();
    if (root == null || viewport is! RenderBox) return const [];
    final out = <_SlotInfo>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is _Slot) {
        final box = e.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
          out.add(_SlotInfo(w.index, w.id, top, box.size.height));
        }
        return;
      }
      e.visitChildren(visit);
    }

    root.visitChildElements(visit);
    out.sort((a, b) => a.index.compareTo(b.index));
    return out;
  }

  TranscriptAnchor? _computeAnchor() {
    for (final s in _slots()) {
      if (s.id.startsWith('\u0000')) continue; // leading / trailing
      if (s.top + s.height > 1) return TranscriptAnchor(s.id, -s.top);
    }
    return null;
  }

  void _restore(TranscriptAnchor anchor) {
    _pending = anchor;
    _restoreTries = 0;
    if (_built) {
      _setFollowing(false);
    } else {
      _following = false;
    }
    _nextFrame(_restoreStep);
  }

  void _restoreStep() {
    final anchor = _pending;
    if (anchor == null || !mounted) return;
    if (!_scroll.hasClients || ++_restoreTries > 16) {
      _pending = null;
      return;
    }
    final p = _scroll.position;
    final slots = _slots();
    final hit = slots.where((s) => s.id == anchor.itemId);
    if (hit.isNotEmpty) {
      final delta = hit.first.top + anchor.offset;
      if (delta.abs() < 1) {
        _pending = null;
        _setFollowing(_atBottom);
        return;
      }
      _scroll.jumpTo(
        (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    } else if (slots.isNotEmpty) {
      final index = _indexById[anchor.itemId];
      if (index == null) {
        _pending = null; // the item is gone
        return;
      }
      final step = p.viewportDimension * .8;
      final down = index > slots.first.index;
      _scroll.jumpTo(
        (p.pixels + (down ? step : -step)).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    }
    _nextFrame(_restoreStep);
  }

  // ---------------------------------------------------------------- build

  static List<TranscriptItem> _ordered(
    List<TranscriptItem> items,
    TurnLayout layout,
  ) {
    if (layout == TurnLayout.chronological) return items;
    int rank(TranscriptItem i) => switch (i) {
      AssistantMessage() => 0,
      FileEdit() => 1,
      ActivityGroup() => 2,
      NoticeLine() => 3,
      _ => -1,
    };
    final out = <TranscriptItem>[];
    var run = <TranscriptItem>[];
    void flush() {
      // List.sort is not stable, so the position breaks ties.
      final idx = List<int>.generate(run.length, (i) => i)
        ..sort((a, b) {
          final c = rank(run[a]).compareTo(rank(run[b]));
          return c != 0 ? c : a.compareTo(b);
        });
      out.addAll([for (final i in idx) run[i]]);
      run = [];
    }

    for (final i in items) {
      if (rank(i) < 0) {
        flush();
        out.add(i);
      } else {
        run.add(i);
      }
    }
    flush();
    return out;
  }

  double _gapBefore(_Row? prev, _Row cur) {
    if (prev == null) return 0;
    return widget.gapBefore?.call(prev.id, cur.id) ?? widget.rowGap;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final items = widget.entries != null
        ? [
            for (final e in widget.entries!)
              _Row(e.id, null, (context) => e.builder(context)),
          ]
        : [
            for (final i in _ordered(widget.items, widget.layout))
              _Row(
                i.id,
                i,
                (context) => TranscriptItemView(i, actions: widget.actions),
              ),
          ];
    final Widget? leading = widget.plan.isEmpty
        ? widget.leading
        : widget.leading == null
        ? PlanChecklist(widget.plan)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlanChecklist(widget.plan),
              const SizedBox(height: 12),
              widget.leading!,
            ],
          );
    final hasLeading = leading != null;
    final hasTrailing = widget.trailing != null;
    // The entries: items, each followed by its inserts.
    final known = {for (final i in items) i.id};
    final after = <String?, List<TranscriptInsert>>{};
    for (final ins in widget.inserts) {
      final key = known.contains(ins.afterItemId) ? ins.afterItemId : null;
      (after[key] ??= []).add(ins);
    }
    final entries = <({_Row? item, TranscriptInsert? insert})>[
      for (final item in items) ...[
        (item: item, insert: null),
        for (final ins in after[item.id] ?? const <TranscriptInsert>[])
          (item: null, insert: ins),
      ],
      for (final ins in after[null] ?? const <TranscriptInsert>[])
        (item: null, insert: ins),
    ];
    final count = entries.length + (hasLeading ? 1 : 0) + (hasTrailing ? 1 : 0);
    _built = true;
    _indexById = {
      for (var i = 0; i < entries.length; i++)
        (entries[i].item?.id ?? entries[i].insert!.id):
            i + (hasLeading ? 1 : 0),
    };
    return SizeClassBuilder(
      builder: (context, sizeClass) {
        final compact = sizeClass.isCompact;
        Widget column(String id, int index, double gap, Widget child) => _Slot(
          key: ValueKey(id),
          id: id,
          index: index,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.contentWidth + 2 * widget.gutter,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.gutter,
                  gap,
                  widget.gutter,
                  0,
                ),
                child: child,
              ),
            ),
          ),
        );
        final pillZone = _pillBottom + (isTouch(context) ? 38.0 : 30.0);
        final list = NotificationListener<Notification>(
          onNotification: _onNotification,
          child: ListView.builder(
            key: _viewportKey,
            controller: _scroll,
            padding:
                widget.padding ??
                EdgeInsets.only(top: compact ? 20 : 28, bottom: 40),
            itemCount: count,
            findChildIndexCallback: (key) {
              if (key is ValueKey<String>) return _indexById[key.value];
              return null;
            },
            itemBuilder: (context, index) {
              if (hasLeading && index == 0) {
                return column('\u0000leading', index, 0, leading);
              }
              if (hasTrailing && index == count - 1) {
                return column(
                  '\u0000trailing',
                  index,
                  widget.rowGap,
                  widget.trailing!,
                );
              }
              final i = index - (hasLeading ? 1 : 0);
              final entry = entries[i];
              final insert = entry.insert;
              if (insert != null) {
                return column(
                  insert.id,
                  index,
                  widget.rowGap,
                  insert.child,
                );
              }
              final item = entry.item!;
              final before = i > 0 ? entries[i - 1] : null;
              final prev = before?.item;
              return column(
                item.id,
                index,
                before != null && prev == null
                    ? widget.rowGap
                    : _gapBefore(prev, item),
                Builder(builder: item.build),
              );
            },
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            // While the "Jump to latest" pill shows, the lines under it fade
            // out above it, so it never sits on text meant to be read. The
            // layout does not change.
            if (_following)
              list
            else
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final h = bounds.height;
                  final end = ((h - pillZone) / h).clamp(0.0, 1.0);
                  final start = (end - _pillFade / h).clamp(0.0, end);
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Color(0xFF000000),
                      Color(0xFF000000),
                      Color(0x00000000),
                      Color(0x00000000),
                    ],
                    stops: [0, start, end, 1],
                  ).createShader(bounds);
                },
                child: list,
              ),
            if (!_following)
              Positioned(
                left: 0,
                right: 0,
                bottom: _pillBottom,
                child: Center(
                  child: JumpToLatestButton(
                    onTap: () => _jumpToLatest(),
                    color: t.surface,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlotInfo {
  const _SlotInfo(this.index, this.id, this.top, this.height);
  final int index;
  final String id;
  final double top, height;
}

/// Marks one entry of the list so the anchor code can find it.
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.id,
    required this.index,
    required this.child,
  });

  final String id;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The "Jump to latest" pill that shows while the list is scrolled away from
/// the tail.
class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({
    super.key,
    required this.onTap,
    this.label = 'Jump to latest',
    this.color,
  });

  final VoidCallback onTap;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        lift: 0,
        borderRadius: t.radii.pill,
        background: color ?? t.surface,
        border: Border.all(color: t.thread),
        shadow: t.colors.seam,
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: isTouch(context) ? 9 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyphIcon(glyphArrowDown, size: 14, color: t.ink),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: ts(t.typeScale.uiSmall, t.ink, weight: 600),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the list: a kit item or a host entry.
class _Row {
  const _Row(this.id, this.item, this.build);

  final String id;
  final TranscriptItem? item;
  final WidgetBuilder build;
}
