// StatusMark: the only widget that draws a status. Every status surface
// (rail row, header pill, crew strip, ledger, approval bar) puts one next to
// its text. The look follows NOTES.md's status table:
//
//   needs you    attention pill with a hairline, or an accent dot + attention ink
//   running      a breathing ink square, muted text
//   failed       danger ink (dot, or circle-x in the pill form)
//   done         constructive ink (dot, or circle-check in the pill form)
//   idle         a hollow ring, muted text
//   interrupted  the idle ring with a dot inside (not in the mockup)

import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus, WorkState;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';

/// The default label of [status].
String statusLabel(ChatStatus status) => switch (status) {
  ChatStatus.needsYou => 'Waiting for you',
  ChatStatus.running => 'Running',
  ChatStatus.failed => 'Failed',
  ChatStatus.done => 'Done',
  ChatStatus.idle => 'Idle',
  ChatStatus.interrupted => 'Interrupted',
};

/// The status a unit of work (a child agent, a tool call) shows.
ChatStatus statusOfWork(WorkState state) => switch (state) {
  WorkState.running => ChatStatus.running,
  WorkState.done => ChatStatus.done,
  WorkState.failed => ChatStatus.failed,
  WorkState.cancelled => ChatStatus.idle,
  // A child asking its parent is not working and not for the user: a static
  // mark. The crew widgets word it ("asking parent").
  WorkState.waitingForAnswer => ChatStatus.idle,
  WorkState.idle => ChatStatus.idle,
  WorkState.timedOut => ChatStatus.failed,
};

/// How a [StatusMark] is drawn.
enum StatusMarkVariant {
  /// A small mark and the label, for list rows and meta lines (the rail).
  dot,

  /// The header form: "needs you" is a filled pill; the others are an icon
  /// or mark and a bold label with no fill.
  pill,
}

/// A status as a mark and a label. See the file comment for the table.
///
/// [label] defaults to [statusLabel]. [detail] follows it after a middle dot
/// ("Running · 3 agents") in the same ink at 80%. The running mark breathes
/// unless [animate] is false or the platform reduces motion.
class StatusMark extends StatelessWidget {
  const StatusMark(
    this.status, {
    super.key,
    this.variant = StatusMarkVariant.dot,
    this.label,
    this.detail,
    this.animate = true,
  }) : _asking = false;

  /// A child waiting for its parent's answer: a static speech-bubble glyph
  /// in the muted "asking" ink, worded "Asking parent". It is not "needs
  /// you" and does not count as running.
  const StatusMark.askingParent({
    super.key,
    this.variant = StatusMarkVariant.dot,
    this.label,
    this.detail,
    this.animate = true,
  }) : status = ChatStatus.idle,
       _asking = true;

  /// The pill form of [status].
  const StatusMark.pill(
    this.status, {
    super.key,
    this.label,
    this.detail,
    this.animate = true,
  }) : variant = StatusMarkVariant.pill,
       _asking = false;

  /// The status of a unit of work. A child waiting for an answer shows as
  /// [StatusMark.askingParent].
  StatusMark.work(
    WorkState state, {
    super.key,
    this.variant = StatusMarkVariant.dot,
    this.label,
    this.detail,
    this.animate = true,
  }) : status = statusOfWork(state),
       _asking = state == WorkState.waitingForAnswer;

  final ChatStatus status;
  final bool _asking;
  final StatusMarkVariant variant;
  final String? label;
  final String? detail;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = BbTheme.of(context);
    final style = _asking ? theme.askingParent : theme.statusStyle(status);
    final text = label ?? (_asking ? 'Asking parent' : statusLabel(status));
    return switch (variant) {
      StatusMarkVariant.dot => _dotForm(theme, style, text),
      StatusMarkVariant.pill => _pillForm(theme, style, text),
    };
  }

  Widget _dotForm(BbTheme theme, BbStatusStyle style, String text) {
    final base = ts(
      theme.typeScale.uiSmall,
      style.ink,
      weight: status == ChatStatus.needsYou ? 600 : 500,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_asking)
          _icon(
            LucideIcons.messageCircleQuestion300,
            LucideIcons.messageCircleQuestion,
            LucideIcons.messageCircleQuestion500,
            style.ink,
          )
        else
          _Glyph(status: status, style: style, animate: animate),
        SizedBox(width: theme.spacing.xs + 2),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: text,
              children: [
                if (detail != null)
                  TextSpan(
                    text: ' · $detail',
                    style: TextStyle(
                      color: style.ink.withValues(alpha: .8),
                      fontWeight: fw(500),
                    ),
                  ),
              ],
            ),
            style: base,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _pillForm(BbTheme theme, BbStatusStyle style, String text) {
    // `.pill` in the mockup: 600 12/18 whatever the form factor.
    final textStyle = ts(const TypeSpec(12, 18, 600), style.ink);
    final labelText = Text(
      detail == null ? text : '$text · $detail',
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (status == ChatStatus.needsYou) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: theme.radii.pill,
          border: Border.all(color: style.line!),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          child: labelText,
        ),
      );
    }
    final icon = _asking
        ? _icon(
            LucideIcons.messageCircleQuestion300,
            LucideIcons.messageCircleQuestion,
            LucideIcons.messageCircleQuestion500,
            style.ink,
          )
        : switch (status) {
      ChatStatus.done => _icon(
        LucideIcons.circleCheck300,
        LucideIcons.circleCheck,
        LucideIcons.circleCheck500,
        style.ink,
      ),
      ChatStatus.failed => _icon(
        LucideIcons.circleX300,
        LucideIcons.circleX,
        LucideIcons.circleX500,
        style.ink,
      ),
      _ => Padding(
        padding: const EdgeInsets.all(2),
        child: _Glyph(status: status, style: style, animate: animate),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: theme.spacing.xs),
        Flexible(child: labelText),
      ],
    );
  }

  static Widget _icon(
    IconData light,
    IconData regular,
    IconData bold,
    Color c,
  ) {
    return LucideIcon(
      lucideWeight((light, regular, bold), 12, 1.5),
      size: 12,
      color: c,
    );
  }
}

/// The 8 px mark: a dot, a breathing square or a ring.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.status,
    required this.style,
    required this.animate,
  });

  final ChatStatus status;
  final BbStatusStyle style;
  final bool animate;

  static const _size = 8.0;

  @override
  Widget build(BuildContext context) {
    final shape = switch (status) {
      ChatStatus.needsYou || ChatStatus.done || ChatStatus.failed => _box(
        BoxDecoration(color: style.mark, shape: BoxShape.circle),
      ),
      ChatStatus.running => _Breathing(
        enabled: animate && !BbTheme.reducedMotion(context),
        period: BbTheme.of(context).motion.breathe,
        child: _box(
          BoxDecoration(
            color: style.mark,
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
      ChatStatus.idle => _box(
        BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: style.mark, width: 1.5),
        ),
      ),
      ChatStatus.interrupted => _box(
        BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: style.mark, width: 1.5),
        ),
        child: Center(
          child: SizedBox(
            width: 2.5,
            height: 2.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.mark,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    };
    return ExcludeSemantics(child: shape);
  }

  static Widget _box(BoxDecoration decoration, {Widget? child}) => SizedBox(
    width: _size,
    height: _size,
    child: DecoratedBox(decoration: decoration, child: child),
  );
}

/// The running mark's loop: opacity .35 to 1 and scale .8 to 1, back and
/// forth (`breathe` in the mockup). Still, at full strength, when disabled.
class _Breathing extends StatefulWidget {
  const _Breathing({
    required this.enabled,
    required this.period,
    required this.child,
  });

  final bool enabled;
  final Duration period;
  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Breathing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    } else if (!widget.enabled) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final v = curve.value;
        return Opacity(
          opacity: .35 + .65 * v,
          child: Transform.scale(scale: .8 + .2 * v, child: child),
        );
      },
    );
  }
}
