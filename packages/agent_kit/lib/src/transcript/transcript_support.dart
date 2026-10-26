// Small pieces the transcript widgets share: Lucide glyphs, the text button,
// mono type without ligatures, and formatting helpers.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';

const glyphChevronDown = (
  LucideIcons.chevronDown300,
  LucideIcons.chevronDown,
  LucideIcons.chevronDown500,
);
const glyphChevronRight = (
  LucideIcons.chevronRight300,
  LucideIcons.chevronRight,
  LucideIcons.chevronRight500,
);
const glyphCheck = (
  LucideIcons.check300,
  LucideIcons.check,
  LucideIcons.check500,
);
const glyphTerminal = (
  LucideIcons.terminal300,
  LucideIcons.terminal,
  LucideIcons.terminal500,
);
const glyphArrowDown = (
  LucideIcons.arrowDown300,
  LucideIcons.arrowDown,
  LucideIcons.arrowDown500,
);
const glyphFileText = (
  LucideIcons.fileText300,
  LucideIcons.fileText,
  LucideIcons.fileText500,
);
const glyphFilePen = (
  LucideIcons.filePen300,
  LucideIcons.filePen,
  LucideIcons.filePen500,
);
const glyphFilePlus = (
  LucideIcons.filePlus300,
  LucideIcons.filePlus,
  LucideIcons.filePlus500,
);
const glyphListChecks = (
  LucideIcons.listChecks300,
  LucideIcons.listChecks,
  LucideIcons.listChecks500,
);
const glyphEye = (LucideIcons.eye300, LucideIcons.eye, LucideIcons.eye500);
const glyphRefresh = (
  LucideIcons.refreshCw300,
  LucideIcons.refreshCw,
  LucideIcons.refreshCw500,
);
const glyphCircleCheck = (
  LucideIcons.circleCheck300,
  LucideIcons.circleCheck,
  LucideIcons.circleCheck500,
);
const glyphCircleX = (
  LucideIcons.circleX300,
  LucideIcons.circleX,
  LucideIcons.circleX500,
);

/// A Lucide glyph at the kit's 1.5 px visual stroke.
Widget glyphIcon(LucideGlyph g, {required double size, required Color color}) =>
    LucideIcon(lucideWeight(g, size, 1.5), size: size, color: color);

/// Mono text style without ligatures (NOTES.md, departure 9).
TextStyle monoStyle(TypeSpec spec, Color color, {int? weight}) =>
    ts(spec, color, weight: weight, mono: true).copyWith(
      fontFeatures: const [
        FontFeature.disable('calt'),
        FontFeature.disable('liga'),
      ],
    );

/// The size class of the nearest builder, or expanded without one.
SizeClass sizeClassOf(BuildContext context) =>
    SizeClass.maybeOf(context) ?? SizeClass.expanded;

/// Whether the theme asks for touch-sized controls.
bool isTouch(BuildContext context) =>
    context.bb.formFactor == FormFactor.mobile;

/// The last [parts] segments of [path] ("usage/mod.rs").
String tailPath(String path, {int parts = 2}) {
  final segs = path.split(RegExp(r'[\/]')).where((s) => s.isNotEmpty);
  final list = segs.toList();
  if (list.length <= parts) return list.join('/');
  return list.sublist(list.length - parts).join('/');
}

/// "48s", "1m 04s", "1h 02m".
String formatDuration(int ms) {
  final s = (ms / 1000).round();
  if (s < 60) return '${s < 1 ? 1 : s}s';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// "212 B", "2.1 KB", "3.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A text-only action (`.btn-text` in the mockup): 12/16 semibold, muted,
/// with an optional 14 px glyph before the label.
class KitTextButton extends StatelessWidget {
  const KitTextButton(
    this.label, {
    super.key,
    this.onTap,
    this.glyph,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final LucideGlyph? glyph;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = color ?? t.muted;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: isTouch(context) ? 32 : 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                glyphIcon(glyph!, size: 14, color: c),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                maxLines: 1,
                style: ts(t.typeScale.uiSmall, c, weight: 600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chevron of a disclosure: down when open, right (rotated down) shut.
class DisclosureChevron extends StatelessWidget {
  const DisclosureChevron({super.key, required this.open, this.size = 13});

  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return AnimatedRotation(
      turns: open ? 0 : -.25,
      duration: Motion.of(context).fast,
      curve: Motion.ease,
      child: glyphIcon(
        glyphChevronDown,
        size: size,
        color: t.colors.iconTertiary,
      ),
    );
  }
}
