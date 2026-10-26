// Small pieces the composer widgets share: Lucide glyphs, the kit's buttons
// (the mockup's .btn, .btn-text and .btn-icon), the key hint, a dashed outline
// and the "waiting 12m" label.
//
// Everything reads BbTheme roles; sizes follow the mockup's app.css. Touch
// sizing follows the form factor (NOTES.md, departure 5): 40 px controls and
// no key hints on a phone-sized window.

import 'dart:async';
import 'dart:math' as math;

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';

/// The Lucide glyphs the composer widgets draw (all three stroke weights).
abstract final class ComposerGlyphs {
  static const LucideGlyph square = (
    LucideIcons.square300,
    LucideIcons.square,
    LucideIcons.square500,
  );
  static const LucideGlyph arrowUp = (
    LucideIcons.arrowUp300,
    LucideIcons.arrowUp,
    LucideIcons.arrowUp500,
  );
  static const LucideGlyph arrowDown = (
    LucideIcons.arrowDown300,
    LucideIcons.arrowDown,
    LucideIcons.arrowDown500,
  );
  static const LucideGlyph sendHorizontal = (
    LucideIcons.sendHorizontal300,
    LucideIcons.sendHorizontal,
    LucideIcons.sendHorizontal500,
  );
  static const LucideGlyph chevronDown = (
    LucideIcons.chevronDown300,
    LucideIcons.chevronDown,
    LucideIcons.chevronDown500,
  );
  static const LucideGlyph clock = (
    LucideIcons.clock300,
    LucideIcons.clock,
    LucideIcons.clock500,
  );
  static const LucideGlyph x = (
    LucideIcons.x300,
    LucideIcons.x,
    LucideIcons.x500,
  );
  static const LucideGlyph fileText = (
    LucideIcons.fileText300,
    LucideIcons.fileText,
    LucideIcons.fileText500,
  );
  static const LucideGlyph filePen = (
    LucideIcons.filePen300,
    LucideIcons.filePen,
    LucideIcons.filePen500,
  );
  static const LucideGlyph terminal = (
    LucideIcons.terminal300,
    LucideIcons.terminal,
    LucideIcons.terminal500,
  );
  static const LucideGlyph globe = (
    LucideIcons.globe300,
    LucideIcons.globe,
    LucideIcons.globe500,
  );
  static const LucideGlyph search = (
    LucideIcons.search300,
    LucideIcons.search,
    LucideIcons.search500,
  );
  static const LucideGlyph wrench = (
    LucideIcons.wrench300,
    LucideIcons.wrench,
    LucideIcons.wrench500,
  );
  static const LucideGlyph check = (
    LucideIcons.check300,
    LucideIcons.check,
    LucideIcons.check500,
  );
  static const LucideGlyph messageSquare = (
    LucideIcons.messageSquare300,
    LucideIcons.messageSquare,
    LucideIcons.messageSquare500,
  );
  static const LucideGlyph messageCircleQuestion = (
    LucideIcons.messageCircleQuestion300,
    LucideIcons.messageCircleQuestion,
    LucideIcons.messageCircleQuestion500,
  );
}

/// Whether the window is phone-sized: touch controls, no key hints.
bool isTouch(BbTheme t) => t.formFactor == FormFactor.mobile;

/// The height of the agent's buttons (`--ctl-h`: 32, and 40 on touch).
double controlHeight(BbTheme t) => isTouch(t) ? 40 : t.layout.controlHeight;

/// A Lucide glyph at [size], drawn at the mockup's 1.5 px visual stroke.
class KitIcon extends StatelessWidget {
  const KitIcon(this.glyph, {super.key, this.size = 14, this.color});

  final LucideGlyph glyph;
  final double size;

  /// Defaults to the secondary icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LucideIcon(
      lucideWeight(glyph, size, 1.5),
      size: size,
      color: color ?? context.bb.colors.iconSecondary,
    ),
  );
}

/// A shortcut hint: a small outlined mono label (`.kc`).
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return ExcludeSemantics(
      child: Opacity(
        opacity: .8,
        child: Container(
          height: 18,
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radii.sm),
            border: Border.all(color: color.withValues(alpha: .3)),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: ts(const TypeSpec(11, 16, 400), color, mono: true),
          ),
        ),
      ),
    );
  }
}

/// How a [KitButton] looks.
enum KitButtonKind {
  /// The solid accent button (Approve, Send).
  primary,

  /// The surface button with a thread outline (For session, Stop).
  secondary,

  /// Text on a hover surface (Review diff, Edit, Back).
  quiet,

  /// A secondary button in the danger ink (Deny in the reason state).
  danger,
}

/// The kit's button. [iconOnly] keeps a square [height] by [height] hit area
/// and the label as the semantics label.
class KitButton extends StatelessWidget {
  const KitButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = KitButtonKind.secondary,
    this.icon,
    this.iconSize = 14,
    this.keyHint,
    this.iconOnly = false,
    this.height,
    this.fontSize,
    this.hoverBackground,
    this.semanticLabel,
  });

  final String label;

  /// Null disables the button (drawn at 45%).
  final VoidCallback? onTap;
  final KitButtonKind kind;
  final LucideGlyph? icon;
  final double iconSize;

  /// A key hint such as `1`; hidden on touch.
  final String? keyHint;
  final bool iconOnly;

  /// Defaults to the control height, or 28 (40 on touch) for [quiet].
  final double? height;
  final double? fontSize;

  /// A tint for hover and focus, for the Send now button.
  final Color? hoverBackground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final quiet = kind == KitButtonKind.quiet;
    final h = height ?? (quiet ? (isTouch(t) ? 40 : 28) : controlHeight(t));
    final fg = switch (kind) {
      KitButtonKind.primary => t.onAccent,
      KitButtonKind.danger => t.dangerInk,
      _ => t.ink,
    };
    var style = ts(
      t.typeScale.ui,
      fg,
      weight: kind == KitButtonKind.primary ? 700 : 600,
    );
    if (fontSize != null) style = style.copyWith(fontSize: fontSize);
    final hint = keyHint;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) KitIcon(icon!, size: iconSize, color: fg),
        if (!iconOnly && label.isNotEmpty) ...[
          if (icon != null) const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
        if (!iconOnly && hint != null && !isTouch(t)) ...[
          const SizedBox(width: 8),
          KeyCap(hint, color: fg),
        ],
      ],
    );
    final background = switch (kind) {
      KitButtonKind.primary => t.accent,
      KitButtonKind.quiet => null,
      _ => t.surface,
    };
    final hoverBg =
        hoverBackground ??
        switch (kind) {
          KitButtonKind.primary => t.accentHover,
          KitButtonKind.quiet => t.hover,
          KitButtonKind.danger => Color.alphaBlend(
            t.dangerInk.withValues(alpha: .08),
            t.surface,
          ),
          KitButtonKind.secondary => Color.alphaBlend(
            t.ink.withValues(alpha: .05),
            t.surface,
          ),
        };
    final button = Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: quiet ? BorderRadius.circular(t.radii.md) : t.radii.ctl,
        background: background,
        hoverBackground: hoverBg,
        pressedBackground: kind == KitButtonKind.primary
            ? t.accentHover
            : t.pressed,
        border: switch (kind) {
          KitButtonKind.secondary ||
          KitButtonKind.danger => Border.all(color: t.thread),
          _ => null,
        },
        padding: iconOnly
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: quiet ? 8 : 12),
        child: SizedBox(
          height: h,
          width: iconOnly ? h : null,
          child: Center(widthFactor: 1, child: content),
        ),
      ),
    );
    return onTap == null ? Opacity(opacity: .45, child: button) : button;
  }
}

/// A small square icon button (`.btn-icon`).
class KitIconButton extends StatelessWidget {
  const KitIconButton(
    this.glyph, {
    super.key,
    required this.label,
    required this.onTap,
    this.size,
    this.iconSize = 14,
  });

  final LucideGlyph glyph;

  /// The semantics label.
  final String label;
  final VoidCallback? onTap;

  /// Defaults to 28, or 40 on touch.
  final double? size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final s = size ?? (isTouch(t) ? 40 : 28);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radii.md),
        child: SizedBox(
          width: s,
          height: s,
          child: Center(child: KitIcon(glyph, size: iconSize)),
        ),
      ),
    );
  }
}

/// Wraps [child] in an [AppTooltip] when an [Overlay] is available.
class KitTip extends StatelessWidget {
  const KitTip({super.key, required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m == null || Overlay.maybeOf(context) == null) return child;
    return AppTooltip(label: m, child: child);
  }
}

/// The surface of the approval and question bars: the `ApprovalCard` look
/// (surface, thread outline, panel radius, hairline shadow).
class BarSurface extends StatelessWidget {
  const BarSurface({super.key, required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radii.panel,
        border: Border.all(color: t.thread),
        boxShadow: t.colors.seam,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A dashed rounded outline around [child] (the queued row).
class DashedOutline extends StatelessWidget {
  const DashedOutline({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedPainter(color, radius),
    child: child,
  );
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.color, this.radius);

  final Color color;
  final BorderRadius radius;

  static const _dash = 4.0, _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(radius.toRRect((Offset.zero & size).deflate(.5)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + _dash, metric.length)),
          paint,
        );
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}

/// "waiting 12m": how long a request has waited. Approvals and questions
/// never expire, so this is an age, never a countdown.
String formatWaiting(DateTime requestedAt, DateTime now) {
  final d = now.difference(requestedAt);
  if (d.inMinutes < 1) return 'waiting <1m';
  if (d.inMinutes < 60) return 'waiting ${d.inMinutes}m';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? 'waiting ${d.inHours}h' : 'waiting ${d.inHours}h ${m}m';
  }
  return 'waiting ${d.inDays}d';
}

/// The tail of [path] for the action line: `…/usage/mod.rs`. Leading `./` and
/// `../` are dropped; a path of one or two segments is kept whole.
String shortenPath(String path) {
  final segments = path
      .split(RegExp(r'[\\/]'))
      .where((s) => s.isNotEmpty && s != '.' && s != '..')
      .toList();
  if (segments.length <= 2) return segments.join('/');
  return '…/${segments.sublist(segments.length - 2).join('/')}';
}

/// A clock icon with "waiting 12m", refreshed every 30 s. [now] replaces the
/// wall clock (tests, the gallery).
class WaitingLabel extends StatefulWidget {
  const WaitingLabel({super.key, required this.requestedAt, this.now});

  final DateTime requestedAt;
  final DateTime? now;

  @override
  State<WaitingLabel> createState() => _WaitingLabelState();
}

class _WaitingLabelState extends State<WaitingLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WaitingLabel old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.now == null && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (widget.now != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final now = widget.now ?? DateTime.now();
    final text = formatWaiting(widget.requestedAt, now);
    return KitTip(
      message: 'Requested ${text.substring('waiting '.length)} ago',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KitIcon(ComposerGlyphs.clock, size: 12, color: t.muted),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: ts(t.typeScale.uiSmall, t.muted),
          ),
        ],
      ),
    );
  }
}
