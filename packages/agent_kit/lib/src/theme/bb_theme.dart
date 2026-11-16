// BbTheme: the one ThemeExtension of the kit. It maps bb-ui's tokens
// (bb_tokens) to the semantic roles of the approved mockup's theme.css, so
// widgets read roles and never raw colours.
//
// It lives in agent_kit, not bb_ui: ThemeExtension is a Material type, and
// bb_ui is Material-free. Only the `ThemeExtension` class is imported from
// Material. The lookup is BbThemeScope (an InheritedWidget), so no
// MaterialApp or Theme is needed; a host that has a ThemeData can also put
// the BbTheme in `ThemeData.extensions`.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:bb_ui/tokens.dart';
// BbTheme is a ThemeExtension so a host can also put it in ThemeData.
// ignore: bb_lints/no_material
import 'package:flutter/material.dart' show ThemeExtension;
import 'package:flutter/widgets.dart';

import 'kit_tokens.dart';

/// How one status looks (one row of the kit's status table).
@immutable
class BbStatusStyle {
  const BbStatusStyle({
    required this.mark,
    required this.ink,
    this.fill,
    this.line,
  });

  /// The colour of the dot, square or ring.
  final Color mark;

  /// The colour of the status text and icon.
  final Color ink;

  /// The pill fill; only "needs you" has one.
  final Color? fill;

  /// The pill's hairline outline; only "needs you" has one.
  final Color? line;
}

/// Motion tokens: bb-ui's durations and curves plus the breathe loop.
@immutable
class BbMotion {
  const BbMotion();

  Duration get fast => Motion.fast;
  Duration get standard => Motion.standard;
  Duration get sheet => Motion.sheet;
  Duration get wiggle => Motion.wiggle;
  Duration get breathe => KitMotion.standard.breathe;
  Curve get ease => Motion.ease;
  Curve get settle => Motion.settle;
}

/// Radii tokens (bb-ui's `Radii`).
@immutable
class BbRadii {
  const BbRadii();

  double get sm => Radii.sm;
  double get md => Radii.md;
  double get lg => Radii.lg;
  double get sheet => Radii.sheet;
  BorderRadius get ctl => Radii.ctl;
  BorderRadius get field => Radii.field;
  BorderRadius get panel => Radii.panel;
  BorderRadius get pill => Radii.pill;
}

/// Semantic roles, status roles, type, metrics, radii, motion and the kit's
/// layout sizes.
///
/// Build one from the bb-ui colours ([AppColors]); [BbThemeScope] does this from a
/// [Brightness]. Role names follow `theme.css`: `canvas`, `surface`, `ink`,
/// `muted`, `seam`, `accent`, `constructive`, `information`, `attention`
/// and `danger` (the four state roles also have an `...Ink` text colour).
@immutable
class BbTheme extends ThemeExtension<BbTheme> {
  /// Derives every role from [colors].
  factory BbTheme(
    AppColors colors, {
    Density density = Density.pointer,
    KitLayout layout = KitLayout.standard,
  }) => BbTheme._(colors, density, layout, KitInks.of(colors));

  /// The light theme.
  factory BbTheme.light({Density density = Density.pointer}) =>
      BbTheme(AppColors.light, density: density);

  /// The dark theme.
  factory BbTheme.dark({Density density = Density.pointer}) =>
      BbTheme(AppColors.darkTheme, density: density);

  BbTheme._(this.colors, this.density, this.layout, KitInks inks)
    : brightness = colors.dark ? Brightness.dark : Brightness.light,
      canvas = colors.desk,
      surface = colors.bgPrimary,
      surface2 = colors.bgSecondary,
      ink = colors.textPrimary,
      muted = colors.textSecondary,
      faint = colors.textTertiary,
      seam = colors.border,
      thread = colors.thread,
      threadStrong = colors.threadStrong,
      hover = colors.bgHover,
      pressed = colors.bgPressed,
      accent = colors.accent,
      accentHover = colors.accentHover,
      accentInk = colors.accentText,
      onAccent = colors.onAccent,
      constructive = colors.okBg,
      constructiveInk = inks.constructive,
      information = colors.infoBg,
      informationInk = colors.textSecondary,
      attention = colors.attnBg,
      attentionInk = inks.attention,
      danger = colors.dangerBg,
      dangerInk = inks.danger,
      focus = colors.focus,
      codeBackground = colors.inlineCodeBg,
      codeInk = colors.inlineCodeText,
      // The rail follows the theme: light builds it from light tokens, dark
      // uses the bb-ui rail tokens.
      rail = colors.dark ? colors.rail : colors.bgSecondary,
      railHover = colors.dark ? colors.rail2 : colors.bgHover,
      railSelected = colors.dark
          ? Color.alphaBlend(
              colors.railInk.withValues(alpha: KitAlpha.railSelected),
              colors.rail2,
            )
          : colors.bgPressed,
      railInk = colors.dark ? colors.railInk : colors.textPrimary,
      railMuted = colors.dark ? colors.railMuted : colors.textSecondary,
      railLine = colors.dark ? colors.railLine : colors.border,
      status = _statuses(colors),
      askingParent = BbStatusStyle(
        mark: colors.palette.statusAskingParentMark,
        ink: colors.palette.statusAskingParentInk,
      ),
      ctxOpening = colors.palette.ctxOpening,
      ctxSummary = colors.palette.ctxSummary,
      ctxLive = colors.palette.ctxLive;

  /// The bb-ui palette this theme was derived from; `bb_ui` reads it.
  final AppColors colors;

  /// How the user points: it sets control heights, icon sizes and the type
  /// ramp ([typeScale], [metrics]). Layout follows [SizeClass] instead.
  final Density density;

  /// Pane minimums, the composer's fit width and other layout sizes.
  final KitLayout layout;

  final Brightness brightness;

  /// The desk behind sheets.
  final Color canvas;

  /// The sheet a transcript sits on.
  final Color surface;

  /// Wells, bubbles, code and the composer (`--surface-2`).
  final Color surface2;

  final Color ink, muted, faint;

  /// Hairlines and card edges.
  final Color seam;

  /// Stronger lines: dashed borders, hollow marks.
  final Color thread, threadStrong;

  /// Hover and pressed overlays.
  final Color hover, pressed;

  /// Primary action, selection and live marks.
  final Color accent, accentHover, accentInk, onAccent;

  /// State roles: bb-ui's fills and the inks chosen for text on them.
  final Color constructive, constructiveInk;
  final Color information, informationInk;
  final Color attention, attentionInk;
  final Color danger, dangerInk;

  final Color focus;

  /// Inline code and code blocks.
  final Color codeBackground, codeInk;

  /// The rail (session list). It follows the theme.
  final Color rail, railHover, railSelected, railInk, railMuted, railLine;

  /// Status roles (see [statusStyle]).
  final Map<ChatStatus, BbStatusStyle> status;

  /// A child waiting on its parent: muted, never a fill or the accent.
  final BbStatusStyle askingParent;

  /// The context meter's non-text segments: the fixed opening, the compacted
  /// summaries and the live messages.
  final Color ctxOpening, ctxSummary, ctxLive;

  final BbRadii radii = const BbRadii();
  final BbMotion motion = const BbMotion();

  /// bb-ui's type ramp for the [density].
  TypeScale get typeScale => density.type;

  /// bb-ui's control, row and icon sizes for the [density].
  Metrics get metrics => density.metrics;

  /// Whether the user points with a finger ([Density.touch]).
  bool get touch => density == Density.touch;

  /// How [s] looks.
  BbStatusStyle statusStyle(ChatStatus s) => status[s]!;

  /// Whether the user or platform asked to reduce motion.
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The theme above [context] (see [BbThemeScope]).
  static BbTheme of(BuildContext context) {
    final theme = maybeOf(context);
    assert(theme != null, 'No BbThemeScope above this context.');
    return theme!;
  }

  /// The theme above [context], or null.
  static BbTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BbThemeInherited>()?.theme;

  @override
  BbTheme copyWith({AppColors? colors, Density? density, KitLayout? layout}) =>
      BbTheme(
        colors ?? this.colors,
        density: density ?? this.density,
        layout: layout ?? this.layout,
      );

  /// Themes do not blend; the nearer one wins at the halfway point.
  @override
  BbTheme lerp(covariant ThemeExtension<BbTheme>? other, double t) =>
      other is! BbTheme || t < .5 ? this : other;

  static Map<ChatStatus, BbStatusStyle> _statuses(AppColors c) {
    final p = c.palette;
    return {
      // Only "needs you" fills a pill, and only it may be warm.
      ChatStatus.needsYou: BbStatusStyle(
        mark: p.statusNeedsYouMark,
        ink: p.statusNeedsYouInk,
        fill: p.statusNeedsYouBg,
        line: p.statusNeedsYouLine,
      ),
      ChatStatus.running: BbStatusStyle(
        mark: p.statusRunningMark,
        ink: p.statusRunningInk,
      ),
      ChatStatus.failed: BbStatusStyle(
        mark: p.statusFailedMark,
        ink: p.statusFailedInk,
      ),
      ChatStatus.done: BbStatusStyle(
        mark: p.statusDoneMark,
        ink: p.statusDoneInk,
      ),
      ChatStatus.idle: BbStatusStyle(
        mark: p.statusIdleMark,
        ink: p.statusIdleInk,
      ),
      // Not in the mockup: the idle ring with a dot inside.
      ChatStatus.interrupted: BbStatusStyle(
        mark: p.statusInterruptedMark,
        ink: p.statusInterruptedInk,
      ),
    };
  }
}

class _BbThemeInherited extends InheritedWidget {
  const _BbThemeInherited({required this.theme, required super.child});

  final BbTheme theme;

  @override
  bool updateShouldNotify(_BbThemeInherited old) =>
      old.theme.colors != theme.colors ||
      old.theme.density != theme.density ||
      old.theme.layout != theme.layout;
}

/// Installs a [BbTheme] and `bb_ui`'s [AppTheme] (which the primitives read)
/// for [brightness], and a default text style so stray text is never drawn
/// with the framework's debug style.
class BbThemeScope extends StatelessWidget {
  const BbThemeScope({
    super.key,
    required this.brightness,
    required this.child,
    this.density = Density.pointer,
  });

  final Brightness brightness;

  /// How the user points; the host picks it, for example with
  /// `Density.forPlatform(defaultTargetPlatform)`.
  final Density density;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = brightness == Brightness.dark
        ? BbTheme.dark(density: density)
        : BbTheme.light(density: density);
    return _BbThemeInherited(
      theme: theme,
      child: AppTheme(
        colors: theme.colors,
        density: density,
        child: DefaultTextStyle(
          style: ts(theme.typeScale.body, theme.ink),
          child: child,
        ),
      ),
    );
  }
}

/// `context.bb` is the nearest [BbTheme].
extension BbThemeContext on BuildContext {
  BbTheme get bb => BbTheme.of(this);
}
