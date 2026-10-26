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
        TranscriptItem,
        UserMessage;
import 'package:bb_ui/bb_ui.dart';
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

class TranscriptList extends StatefulWidget {
  const TranscriptList({
    super.key,
    required this.items,
    this.actions = const TranscriptActions(),
    this.controller,
    this.initialAnchor,
    this.plan = const [],
    this.inserts = const [],
    this.leading,
    this.trailing,
    this.contentWidth = 720,
    this.followThreshold = 24,
  });

  /// The transcript, in order (`ChatSnapshot.items`).
  final List<TranscriptItem> items;

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

  @override
  State<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<TranscriptList> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
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
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ following

  void _setFollowing(bool value) {
    if (_following == value) return;
    setState(() => _following = value);
    widget.controller?._changed();
  }

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

  static int _kind(TranscriptItem i) => switch (i) {
    UserMessage() => 0,
    AssistantMessage() || ActivityGroup() || NoticeLine() => 1,
    FileEdit() => 2,
    _ => 3,
  };

  double _gapBefore(TranscriptItem? prev, TranscriptItem cur, bool compact) {
    if (prev == null) return 0;
    final turn = compact ? 22.0 : 28.0;
    final a = _kind(prev), b = _kind(cur);
    if (a == 2 && b == 2) return 6;
    if ((a == 1 || a == 2) && (b == 1 || b == 2)) return 12;
    return turn;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final items = widget.items;
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
    final entries = <({TranscriptItem? item, TranscriptInsert? insert})>[
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
              constraints: BoxConstraints(maxWidth: widget.contentWidth + 32),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, gap, 16, 0),
                child: child,
              ),
            ),
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<Notification>(
              onNotification: _onNotification,
              child: ListView.builder(
                key: _viewportKey,
                controller: _scroll,
                padding: EdgeInsets.only(top: compact ? 20 : 28, bottom: 40),
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
                      compact ? 22 : 28,
                      widget.trailing!,
                    );
                  }
                  final i = index - (hasLeading ? 1 : 0);
                  final entry = entries[i];
                  final insert = entry.insert;
                  if (insert != null) {
                    return column(insert.id, index, 12, insert.child);
                  }
                  final item = entry.item!;
                  final before = i > 0 ? entries[i - 1] : null;
                  final prev = before?.item;
                  return column(
                    item.id,
                    index,
                    before != null && prev == null
                        ? 12
                        : _gapBefore(prev, item, compact),
                    TranscriptItemView(item, actions: widget.actions),
                  );
                },
              ),
            ),
            if (!_following)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
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
