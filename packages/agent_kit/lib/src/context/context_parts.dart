// Small widgets the context pane shares: a dashed outline, the flash that
// marks the target of a jump, the grey tag (`E3`, `Chapter 1`) and a label
// for a block of the pane. Not exported from the barrel.

import 'dart:math' as math;

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// Paints a dashed outline of a rounded rectangle, or only a dashed vertical
/// line down the left edge ([leftOnly]), inside the box it covers.
class DashedPainter extends CustomPainter {
  const DashedPainter({
    required this.color,
    this.radius = BorderRadius.zero,
    this.width = 1,
    this.dash = 4,
    this.gap = 3,
    this.leftOnly = false,
  });

  final Color color;
  final BorderRadius radius;
  final double width, dash, gap;
  final bool leftOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (leftOnly) {
      path
        ..moveTo(width / 2, 0)
        ..lineTo(width / 2, size.height);
    } else {
      path.addRRect(radius.toRRect(Offset.zero & size).deflate(width / 2));
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + dash, metric.length)),
          paint,
        );
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.leftOnly != leftOnly;
}

/// Lights [child] for a moment when [active] turns true or [token] changes
/// while it is. Off under reduced motion: the jump itself still lands.
class CxFlash extends StatefulWidget {
  const CxFlash({
    super.key,
    required this.active,
    required this.token,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(6)),
  });

  final bool active;
  final int token;
  final BorderRadius radius;
  final Widget child;

  @override
  State<CxFlash> createState() => _CxFlashState();
}

class _CxFlashState extends State<CxFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _startPending = false;

  @override
  void initState() {
    super.initState();
    _startPending = widget.active;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startPending) {
      _startPending = false;
      _start();
    }
  }

  @override
  void didUpdateWidget(CxFlash old) {
    super.didUpdateWidget(old);
    if (widget.active && (!old.active || old.token != widget.token)) _start();
  }

  void _start() {
    if (BbTheme.reducedMotion(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final a = _c.isAnimating ? (1 - _c.value) * .55 : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            color: a == 0 ? null : t.accent.withValues(alpha: a * .35),
          ),
          child: child,
        );
      },
    );
  }
}

/// The grey tag: `E3`, `Chapter 1`, `Now`.
class CxTag extends StatelessWidget {
  const CxTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.pressed,
        borderRadius: BorderRadius.circular(t.radii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          text,
          maxLines: 1,
          style: ts(const TypeSpec(11, 18, 700), t.muted),
        ),
      ),
    );
  }
}

/// A group label with a size at the right (`.cx-grp`).
class CxGroup extends StatelessWidget {
  const CxGroup(this.label, this.trailing, {super.key});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label, style: ts(const TypeSpec(12, 16, 700), t.muted)),
          ),
          if (trailing != null)
            Text(trailing!, style: ts(const TypeSpec(12, 16, 500), t.faint)),
        ],
      ),
    );
  }
}

/// A quiet paragraph (`.cx-note`).
class CxNote extends StatelessWidget {
  const CxNote(this.text, {super.key, this.top = 10});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, top, 2, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          text,
          style: ts(const TypeSpec(13, 18, 500), t.muted, weight: 400),
        ),
      ),
    );
  }
}
