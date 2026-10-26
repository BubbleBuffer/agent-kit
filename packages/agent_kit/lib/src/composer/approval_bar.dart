// ApprovalBar: the request the agent is waiting on, above the composer.
//
// Line one is the "Needs approval" pill (a StatusMark) and how long the
// request has waited ("waiting 12m", from `requestedAt`: approvals never
// expire, so there is no countdown). Line two is the tool, the path, the
// +/- counts and Review diff. The actions are Approve (primary), For session
// and Deny, with the keys 1, 2 and 3.
//
// Keys 1/2/3 (SPEC.md, section 10) fire the actions while focus is not in a
// text field, or while focus is inside the bar (outside its reason field),
// or while the composer is empty ([ApprovalBar.composerEmpty]).
//
// Deny opens an optional reason field in the bar: Enter denies, Esc goes back.
// Layout: two lines on the left and the actions on the right when the bar is
// wide, the actions under the request when it is narrower, and three equal
// buttons across a compact (< 600 px) bar. Key hints hide on touch.

import 'package:agent_kit_core/agent_kit_core.dart'
    show Approval, ApprovalDecision, ChatStatus, FileDiff, ToolKind;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'composer_parts.dart';

/// The approval bar for one pending [approval].
class ApprovalBar extends StatefulWidget {
  /// Creates the bar.
  const ApprovalBar({
    super.key,
    required this.approval,
    required this.onDecide,
    this.onReview,
    this.now,
    this.composerEmpty,
    this.initiallyDenying = false,
    this.captureKeys = true,
  });

  /// The request (its tool, target, diff and `requestedAt`).
  final Approval approval;

  /// The decision, for `decideApproval`. A denial may carry a reason.
  final ValueChanged<ApprovalDecision> onDecide;

  /// Review diff was pressed. The link shows only when there is a handler
  /// and the approval has a diff.
  final VoidCallback? onReview;

  /// Replaces the wall clock for "waiting 12m" (tests, the gallery).
  final DateTime? now;

  /// Whether the composer is empty. Pressing 1, 2 or 3 in a focused, empty
  /// composer acts on the approval. Without it, only keys outside text fields
  /// and inside the bar do.
  final bool Function()? composerEmpty;

  /// Starts in the reason state (the gallery's specimen of it).
  final bool initiallyDenying;

  /// Whether the bar listens for 1, 2 and 3. Turn it off on all but one bar
  /// when several are shown at once (the gallery).
  final bool captureKeys;

  @override
  State<ApprovalBar> createState() => _ApprovalBarState();
}

class _ApprovalBarState extends State<ApprovalBar> {
  final _barFocus = FocusNode(
    debugLabel: 'approval bar',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _denyAnchor = FocusNode(
    debugLabel: 'approval deny',
    skipTraversal: true,
  );
  final _reason = TextEditingController();
  final _reasonFocus = FocusNode(debugLabel: 'approval reason');
  late bool _denying = widget.initiallyDenying;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _barFocus.dispose();
    _denyAnchor.dispose();
    _reason.dispose();
    _reasonFocus.dispose();
    super.dispose();
  }

  bool _isEditing(FocusNode? node) {
    final context = node?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.captureKeys ||
        _denying ||
        !widget.approval.isPending ||
        !mounted) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return false;
    }
    final key = event.logicalKey;
    final VoidCallback? action;
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      action = _approve;
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      action = _forSession;
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      action = _openDeny;
    } else {
      action = null;
    }
    if (action == null) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (_isEditing(focus)) {
      if (_barFocus.hasFocus) return false; // typing in the bar
      if (widget.composerEmpty?.call() != true) return false;
    }
    action();
    return true;
  }

  void _approve() => widget.onDecide(ApprovalDecision.approve);
  void _forSession() => widget.onDecide(ApprovalDecision.approveForSession);

  void _openDeny() {
    setState(() => _denying = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reasonFocus.requestFocus();
    });
  }

  void _back() {
    setState(() {
      _denying = false;
      _reason.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _denyAnchor.requestFocus();
      _denyAnchor.nextFocus();
    });
  }

  void _deny() {
    final reason = _reason.text.trim();
    widget.onDecide(
      reason.isEmpty
          ? const ApprovalDecision.deny()
          : ApprovalDecision.deny(reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final touch = isTouch(t);
    return Focus(
      focusNode: _barFocus,
      child: Semantics(
        container: true,
        label: _denying ? 'Deny request' : 'Approval needed',
        child: SizeClassBuilder(
          builder: (context, size) => BarSurface(
            padding: EdgeInsets.fromLTRB(
              touch ? 10 : 12,
              touch ? 10 : 8,
              touch ? 10 : 8,
              touch ? 10 : 8,
            ),
            child: _denying
                ? _denyBody(context, t, size)
                : _body(context, t, size),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, BbTheme t, SizeClass size) {
    final what = _What(
      approval: widget.approval,
      now: widget.now,
      onReview: widget.onReview,
    );
    final actions = <Widget>[
      KitButton(
        label: 'Approve',
        kind: KitButtonKind.primary,
        keyHint: '1',
        onTap: _approve,
      ),
      KitButton(label: 'For session', keyHint: '2', onTap: _forSession),
      Focus(
        focusNode: _denyAnchor,
        child: KitButton(label: 'Deny', keyHint: '3', onTap: _openDeny),
      ),
    ];
    if (size.isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          what,
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Stretch(actions[i])),
              ],
            ],
          ),
        ],
      );
    }
    final acts = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          actions[i],
        ],
      ],
    );
    return _WrapActs(what: what, acts: acts);
  }

  Widget _denyBody(BuildContext context, BbTheme t, SizeClass size) {
    final a = widget.approval;
    final subject = a.target ?? a.diff?.path;
    final h = controlHeight(t);
    final field = FieldFrame(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _back();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          label: 'Reason for the agent',
          textField: true,
          child: PlainField(
            controller: _reason,
            focusNode: _reasonFocus,
            style: ts(
              isTouch(t) ? t.typeScale.body : t.typeScale.ui,
              t.ink,
              weight: 400,
            ),
            placeholder: 'Reason for the agent (optional)',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _deny(),
          ),
        ),
      ),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KitButton(label: 'Back', kind: KitButtonKind.quiet, onTap: _back),
        const SizedBox(width: 8),
        KitButton(label: 'Deny', kind: KitButtonKind.danger, onTap: _deny),
      ],
    );
    final title = Row(
      children: [
        Text(
          'Deny ${a.tool}',
          maxLines: 1,
          style: ts(t.typeScale.ui, t.ink, weight: 700),
        ),
        if (subject != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              size.isCompact ? shortenPath(subject) : subject,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: ts(const TypeSpec(12.5, 20, 400), t.muted, mono: true),
            ),
          ),
        ],
      ],
    );
    if (size.isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 8),
          field,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: buttons),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            buttons,
          ],
        ),
      ],
    );
  }
}

/// Gives a button the full width its parent allows.
class _Stretch extends StatelessWidget {
  const _Stretch(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, child: child);
}

/// The two lines on the left: pill and age, then the action.
class _What extends StatelessWidget {
  const _What({required this.approval, this.now, this.onReview});

  final Approval approval;
  final DateTime? now;
  final VoidCallback? onReview;

  static LucideGlyph _glyph(ToolKind kind) => switch (kind) {
    ToolKind.edit || ToolKind.write => ComposerGlyphs.filePen,
    ToolKind.exec => ComposerGlyphs.terminal,
    ToolKind.web => ComposerGlyphs.globe,
    ToolKind.search => ComposerGlyphs.search,
    ToolKind.read => ComposerGlyphs.fileText,
    ToolKind.other => ComposerGlyphs.wrench,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final diff = approval.diff;
    final subject = approval.target ?? diff?.path ?? approval.summary;
    final isPath =
        approval.kind == ToolKind.edit ||
        approval.kind == ToolKind.write ||
        approval.kind == ToolKind.read;
    const mono = TypeSpec(12.5, 20, 400);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const StatusMark.pill(ChatStatus.needsYou, label: 'Needs approval'),
            const SizedBox(width: 8),
            WaitingLabel(requestedAt: approval.requestedAt, now: now),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            const SizedBox(width: 1),
            KitIcon(_glyph(approval.kind), size: 14),
            const SizedBox(width: 6),
            Text(
              approval.tool,
              maxLines: 1,
              style: ts(const TypeSpec(13, 20, 700), t.ink, mono: true),
            ),
            if (subject != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: KitTip(
                  message: subject,
                  child: Text(
                    isPath ? shortenPath(subject) : subject,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ts(mono, t.muted, mono: true),
                  ),
                ),
              ),
            ],
            if (diff != null) ..._counts(t, diff),
            if (diff != null && onReview != null) ...[
              const SizedBox(width: 2),
              KitButton(
                label: 'Review diff',
                kind: KitButtonKind.quiet,
                onTap: onReview,
              ),
            ],
          ],
        ),
      ],
    );
  }

  List<Widget> _counts(BbTheme t, FileDiff diff) {
    final style = ts(const TypeSpec(12, 20, 700), t.ink, mono: true);
    return [
      const SizedBox(width: 6),
      Text(
        '+${diff.added}',
        maxLines: 1,
        style: style.copyWith(color: t.constructiveInk),
      ),
      const SizedBox(width: 6),
      Text(
        '−${diff.removed}',
        maxLines: 1,
        style: style.copyWith(color: t.dangerInk),
      ),
    ];
  }
}

/// The request and its actions, laid out like the mockup's flex row with wrap
/// (`.ap-what{flex:1 1 280px}`, `.ap-acts{flex:1 0 auto; justify-content:
/// flex-end}`): side by side while the request keeps at least 280 px, else the
/// actions drop under it, right-aligned. It follows the width it is given, not
/// a fixed breakpoint.
class _WrapActs extends MultiChildRenderObjectWidget {
  _WrapActs({required Widget what, required Widget acts})
    : super(children: [what, acts]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWrapActs();
}

typedef _Plan = ({Size size, Offset what, Offset acts});

class _RenderWrapActs extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  static const _minWhat = 280.0;
  static const _gapX = 12.0;
  static const _gapY = 8.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ActsParentData) {
      child.parentData = _ActsParentData();
    }
  }

  RenderBox get _what => firstChild!;
  RenderBox get _acts => childAfter(firstChild!)!;

  _Plan _plan(BoxConstraints c, ChildLayouter layout) {
    final maxW = c.hasBoundedWidth ? c.maxWidth : double.infinity;
    final a = layout(_acts, BoxConstraints(maxWidth: maxW));
    if (maxW.isFinite && maxW < _minWhat + _gapX + a.width) {
      final w = layout(_what, BoxConstraints(minWidth: maxW, maxWidth: maxW));
      return (
        size: c.constrain(Size(maxW, w.height + _gapY + a.height)),
        what: Offset.zero,
        acts: Offset(maxW - a.width, w.height + _gapY),
      );
    }
    final whatW = maxW.isFinite ? maxW - _gapX - a.width : null;
    final w = layout(
      _what,
      whatW == null
          ? const BoxConstraints()
          : BoxConstraints(minWidth: whatW, maxWidth: whatW),
    );
    final h = w.height > a.height ? w.height : a.height;
    final width = maxW.isFinite ? maxW : w.width + _gapX + a.width;
    return (
      size: c.constrain(Size(width, h)),
      what: Offset(0, (h - w.height) / 2),
      acts: Offset(width - a.width, (h - a.height) / 2),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _plan(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  void performLayout() {
    final plan = _plan(constraints, ChildLayoutHelper.layoutChild);
    (_what.parentData! as _ActsParentData).offset = plan.what;
    (_acts.parentData! as _ActsParentData).offset = plan.acts;
    size = plan.size;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final a = _acts.getMinIntrinsicWidth(height);
    final w = _what.getMinIntrinsicWidth(height);
    return a > w ? a : w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _what.getMaxIntrinsicWidth(height) +
      _gapX +
      _acts.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ActsParentData extends ContainerBoxParentData<RenderBox> {}
