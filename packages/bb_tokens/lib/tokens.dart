// Approved Stacks tokens plus the app-wide type scale and bundled fonts.
// Every colour comes from `src/colors.g.dart`, generated from the agent-kit
// profile of the BubbleBuffer design repository (packages/bb_tokens/README.md).
// No Material anywhere: this is the only theme the widgets read.

import 'package:flutter/widgets.dart';

import 'src/colors.g.dart';

export 'src/colors.g.dart';

/// Bundled fonts used identically on every platform and in golden tests.
String sansFamily = 'Atkinson Hyperlegible Next';
String monoFamily = 'Fragment Mono';
String displayFamily = 'Bricolage Grotesque';
const monoFallback = ['monospace'];

/// Fully transparent. `Colors.transparent` is Material, which the kit avoids.
const kTransparent = Color(0x00000000);

/// An opaque colour for alpha masks, where only the alpha channel matters.
const kMaskOpaque = Color(0xFF000000);

/// Quiet space colours shared by the tree, agenda and checklist progress.
const spaceColorNames = ['apricot', 'paw', 'moss', 'duvet', 'sun', 'sky'];
Color? spaceColor(String? name, Brightness brightness) {
  final p = brightness == Brightness.dark
      ? ProfileColors.dark
      : ProfileColors.light;
  return switch (name) {
    'apricot' => p.spaceApricot,
    'paw' => p.spacePaw,
    'moss' => p.spaceMoss,
    'duvet' => p.spaceDuvet,
    'sun' => p.spaceSun,
    'sky' => p.spaceSky,
    _ => null,
  };
}

/// Opaque edge/tile colours; the quiet dot/pill palette above stays separate.
class SpacePatch {
  const SpacePatch(this.fill, this.deep, this.ink);
  final Color fill, deep, ink;

  Color get hover => Color.alphaBlend(ink.withValues(alpha: .12), fill);

  /// Moss keeps its original backing behind title/glyphs on hover.
  Color get hoverTextBacking =>
      fill == ProfileColors.light.spacePatchMossFill ? fill : hover;
}

SpacePatch? spacePatch(
  String? name,
  Brightness brightness, {
  bool rail = false,
}) {
  final dark = brightness == Brightness.dark || (rail && name == 'duvet');
  final p = dark ? ProfileColors.dark : ProfileColors.light;
  return switch (name) {
    'apricot' => SpacePatch(
      p.spacePatchApricotFill,
      p.spacePatchApricotDeep,
      p.spacePatchApricotInk,
    ),
    'paw' => SpacePatch(
      p.spacePatchPawFill,
      p.spacePatchPawDeep,
      p.spacePatchPawInk,
    ),
    'moss' => SpacePatch(
      p.spacePatchMossFill,
      p.spacePatchMossDeep,
      p.spacePatchMossInk,
    ),
    'duvet' => SpacePatch(
      p.spacePatchDuvetFill,
      p.spacePatchDuvetDeep,
      p.spacePatchDuvetInk,
    ),
    'sun' => SpacePatch(
      p.spacePatchSunFill,
      p.spacePatchSunDeep,
      p.spacePatchSunInk,
    ),
    'sky' => SpacePatch(
      p.spacePatchSkyFill,
      p.spacePatchSkyDeep,
      p.spacePatchSkyInk,
    ),
    _ => null,
  };
}

class AppColors {
  const AppColors({
    required this.dark,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgElevated,
    required this.bgHover,
    required this.bgPressed,
    required this.bgSelectedBlock,
    required this.textSelection,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconTertiary,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.borderTranslucent,
    required this.divider,
    required this.accent,
    required this.accentHover,
    required this.inlineCodeBg,
    required this.inlineCodeText,
    required this.overlay,
    required this.desk,
    required this.accentText,
    required this.onAccent,
    required this.focus,
    required this.thread,
    required this.threadStrong,
    required this.okBg,
    required this.infoBg,
    required this.attnBg,
    required this.dangerBg,
    required this.pawBg,
    required this.rail,
    required this.rail2,
    required this.railInk,
    required this.railMuted,
    required this.railLine,
    required this.seam,
    required this.seamHover,
    required this.stack,
    ProfileColors? palette,
  }) : palette = palette ?? (dark ? ProfileColors.dark : ProfileColors.light);

  /// Every role of the agent-kit profile, including the ones below that
  /// have no field of their own (status, diff, context and control colours).
  final ProfileColors palette;
  final bool dark;
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color bgElevated;
  final Color bgHover;
  final Color bgPressed;
  final Color bgSelectedBlock;
  final Color textSelection;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconTertiary;
  final Color border;
  final Color borderSubtle;
  final Color borderStrong;
  final Color borderTranslucent;
  final Color divider;
  final Color accent;
  final Color accentHover;
  final Color inlineCodeBg;
  final Color inlineCodeText;
  final Color overlay;
  final Color desk;
  final Color accentText;
  final Color onAccent;
  final Color focus;
  final Color thread;
  final Color threadStrong;
  final Color okBg;
  final Color infoBg;
  final Color attnBg;
  final Color dangerBg;
  final Color pawBg;
  final Color rail;
  final Color rail2;
  final Color railInk;
  final Color railMuted;
  final Color railLine;
  final List<BoxShadow> seam, seamHover, stack;
  // Compatibility for screens that still refer to the old shadow names.
  List<BoxShadow> get shadowMenu => seamHover;
  List<BoxShadow> get shadowSmall => seam;

  static final light = _appColors(ProfileColors.light, dark: false);

  static final darkTheme = _appColors(ProfileColors.dark, dark: true);
}

/// Scratch's field names over the generated palette.
AppColors _appColors(ProfileColors p, {required bool dark}) => AppColors(
  dark: dark,
  palette: p,
  bgPrimary: p.surface,
  bgSecondary: p.surface2,
  bgTertiary: p.desk,
  bgElevated: p.raised,
  bgHover: p.hover,
  bgPressed: p.pressed,
  bgSelectedBlock: p.selected,
  textSelection: p.selection,
  textPrimary: p.ink,
  textSecondary: p.muted,
  textTertiary: p.faint,
  textDisabled: p.disabled,
  iconPrimary: p.ink,
  iconSecondary: p.icon,
  iconTertiary: p.iconFaint,
  border: p.seam,
  borderSubtle: p.seamSubtle,
  borderStrong: p.seamStrong,
  borderTranslucent: p.seam,
  divider: p.seam,
  accent: p.accent,
  accentHover: p.accentHover,
  inlineCodeBg: p.codeBg,
  inlineCodeText: p.codeInk,
  overlay: p.scrim,
  desk: p.desk,
  accentText: p.accentInk,
  onAccent: p.onAccent,
  focus: p.focus,
  thread: p.thread,
  threadStrong: p.threadStrong,
  okBg: p.constructive,
  infoBg: p.information,
  attnBg: p.attention,
  dangerBg: p.danger,
  pawBg: p.pawTint,
  rail: p.scratchRail,
  rail2: p.scratchRail2,
  railInk: p.scratchRailInk,
  railMuted: p.scratchRailMuted,
  railLine: p.scratchRailLine,
  seam: p.shadow,
  seamHover: p.shadowHover,
  stack: p.shadowStack,
);

/// One entry of the type scale: size / line height in logical px, weight.
class TypeSpec {
  const TypeSpec(this.size, this.line, this.weight);
  final double size, line;
  final int weight;
}

class TypeScale {
  const TypeScale({
    required this.pageTitle,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.body,
    required this.ui,
    required this.uiSmall,
    required this.code,
  });
  final TypeSpec pageTitle, h1, h2, h3, body, ui, uiSmall, code;

  static const desktop = TypeScale(
    pageTitle: TypeSpec(40, 48, 700),
    h1: TypeSpec(30, 39, 600),
    h2: TypeSpec(24, 31.2, 600),
    h3: TypeSpec(20, 26, 600),
    body: TypeSpec(16, 24, 400),
    ui: TypeSpec(14, 20, 500),
    uiSmall: TypeSpec(12, 16, 500),
    code: TypeSpec(13.6, 20.4, 400),
  );

  static const mobile = TypeScale(
    pageTitle: TypeSpec(28, 33.6, 700),
    h1: TypeSpec(24, 31.2, 600),
    h2: TypeSpec(20, 26, 600),
    h3: TypeSpec(18, 23.4, 600),
    body: TypeSpec(16, 22, 400),
    ui: TypeSpec(15, 20, 500),
    uiSmall: TypeSpec(13, 16, 500),
    code: TypeSpec(13.6, 20.4, 400), // 85% of body, line 1.5
  );
}

FontWeight fw(int w) => FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)];

TextStyle ts(TypeSpec s, Color color, {int? weight, bool mono = false}) =>
    TextStyle(
      inherit: false,
      fontFamily: mono ? monoFamily : sansFamily,
      // Fragment Mono supplies symbols missing from the bundled body font.
      fontFamilyFallback: mono ? monoFallback : [monoFamily],
      fontSize: s.size,
      height: s.line / s.size,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: fw(weight ?? s.weight),
      color: color,
      decoration: TextDecoration.none,
    );

TextStyle tsRaw(double size, double line, int weight, Color color) =>
    ts(TypeSpec(size, line, weight), color);

/// Display typography, including the prototype's condensed variable axes.
TextStyle tsDisplay(TypeSpec s, Color color, {int? weight}) {
  final w = weight ?? 640;
  return ts(s, color, weight: w).copyWith(
    fontFamily: displayFamily,
    fontVariations: [
      FontVariation('opsz', s.size.clamp(12.0, 96.0)),
      const FontVariation('wdth', 90),
      FontVariation('wght', w.toDouble()),
    ],
    letterSpacing: -.03 * s.size,
  );
}

class Layout {
  // desktop
  static const contentWidth = 720.0;
  static const textWidth = 708.0;
  static const blockPaddingX = 2.0;
  static const blockRowGap = 2.0;
  static const textBlockHeight = 28.0;
  static const topbarHeight = 44.0;
  static const sidebarWidth = 240.0;
  static const sidebarRowHeight = 30.0;
  static const handleOffset = -44.0;
  // mobile
  static const gutter = 18.0;
  static const keyboardToolbarHeight = 44.0;
  static const minTapTarget = 44.0;
  static const listRowHeight = 44.0;
  static const indent = 24.0;
}

class Radii {
  // Legacy scalar values for specialised editor geometry.
  static const sm = 4.0, md = 6.0, lg = 10.0, sheet = 12.0;
  static const ctl = BorderRadius.only(
    topLeft: Radius.circular(7),
    topRight: Radius.circular(11),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(9),
  );
  static const field = BorderRadius.only(
    topLeft: Radius.circular(6),
    topRight: Radius.circular(10),
    bottomRight: Radius.circular(6),
    bottomLeft: Radius.circular(8),
  );
  static const panel = BorderRadius.only(
    topLeft: Radius.circular(12),
    topRight: Radius.circular(18),
    bottomRight: Radius.circular(10),
    bottomLeft: Radius.circular(16),
  );
  static const pill = BorderRadius.all(Radius.circular(999));
}

class Motion {
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 220);
  static const sheet = Duration(milliseconds: 250);
  static const wiggle = Duration(milliseconds: 200);
  static const ease = Cubic(.2, .8, .2, 1);
  static const settle = Cubic(.22, 1.25, .36, 1);
  static const easing = ease;
  static MotionDurations of(BuildContext context) =>
      MotionDurations(MediaQuery.disableAnimationsOf(context));
}

class MotionDurations {
  const MotionDurations(this.reduced);
  final bool reduced;
  Duration get fast => reduced ? Duration.zero : Motion.fast;
  Duration get standard => reduced ? Duration.zero : Motion.standard;
  Duration get sheet => reduced ? Duration.zero : Motion.sheet;
  Duration get wiggle => reduced ? Duration.zero : Motion.wiggle;
}

/// Desktop: sidebar, top search, selection toolbar, popovers, drag handles.
/// Mobile: stack navigation, bottom bar, keyboard toolbar, bottom sheets.
enum FormFactor {
  desktop,
  mobile;

  /// The one switch between the two layouts: the window's logical width.
  static const breakpoint = 768.0;

  static FormFactor forWidth(double width) =>
      width < breakpoint ? mobile : desktop;
}

class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    required this.colors,
    required this.formFactor,
    required super.child,
  });
  final AppColors colors;
  final FormFactor formFactor;

  bool get mobile => formFactor == FormFactor.mobile;
  TypeScale get type => mobile ? TypeScale.mobile : TypeScale.desktop;

  static AppTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTheme>()!;

  @override
  bool updateShouldNotify(AppTheme old) =>
      old.colors != colors || old.formFactor != formFactor;
}

extension ThemeX on BuildContext {
  AppColors get colors => AppTheme.of(this).colors;
  TypeScale get type => AppTheme.of(this).type;
  FormFactor get formFactor => AppTheme.of(this).formFactor;
  bool get mobile => AppTheme.of(this).mobile;
}

// ---------------------------------------------------------------------------
// Agent kit tokens: the values of the approved Scratch-skin mockup's
// `theme.css` that Scratch's own tokens do not have. Widgets read them through
// the agent kit's `BbTheme`.
// ---------------------------------------------------------------------------

/// Layout thresholds and sizes of the agent kit (`--size-*`, `--fit-composer`,
/// `--pane-min-*`, `--edge-tab`, `--ctl-h`, `--row` in `theme.css`).
///
/// The kit lays out by the width of its own container, never the window:
/// compact is below [sizeMedium], medium from there to below [sizeExpanded],
/// expanded from [sizeExpanded] up.
class KitLayout {
  const KitLayout({
    this.sizeMedium = 600,
    this.sizeExpanded = 1000,
    this.fitComposer = 460,
    this.contextSplit = 680,
    this.paneMinWidth = 200,
    this.paneMinHeight = 120,
    this.edgeTab = 28,
    this.controlHeight = 32,
    this.rowHeight = 28,
  });

  /// The values of `theme.css`.
  static const standard = KitLayout();

  /// Container width where compact ends.
  final double sizeMedium;

  /// Container width where medium ends.
  final double sizeExpanded;

  /// Composer width below which Stop and Send drop their labels.
  final double fitComposer;

  /// Context pane width from which a summary's detail sits beside the list
  /// instead of replacing it.
  final double contextSplit;

  /// A workspace pane never renders narrower than this.
  final double paneMinWidth;

  /// A workspace pane never renders shorter than this.
  final double paneMinHeight;

  /// Width of a collapsed pane's edge tab.
  final double edgeTab;

  /// Height of the agent's buttons (`--ctl-h`).
  final double controlHeight;

  /// Height of a list row (`--row`).
  final double rowHeight;
}

/// The kit's spacing scale. `theme.css` has no scale, so these are the steps
/// `app.css` uses (2, 4, 6/8, 10/12, 16, 24 px).
class KitSpacing {
  const KitSpacing({
    this.hair = 2,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
  });

  static const standard = KitSpacing();

  final double hair, xs, sm, md, lg, xl;
}

/// Motion that Scratch's [Motion] lacks.
class KitMotion {
  const KitMotion({this.breathe = const Duration(milliseconds: 2400)});

  static const standard = KitMotion();

  /// One cycle of the running mark's breathing loop (`--breathe`).
  final Duration breathe;
}

/// Text colours for the state roles. Scratch has only fills for them
/// (`okBg`, `dangerBg`, ...); these are the inks the mockup chose:
/// constructive and danger from the edit-row counts in Scratch's
/// `agent_turn.dart`, attention from `accentText` (light) or the attention
/// hue at full strength (dark, 5.3:1 on the 20% fill).
class KitInks {
  const KitInks({
    required this.constructive,
    required this.danger,
    required this.attention,
  });

  static final light = KitInks(
    constructive: ProfileColors.light.constructiveInk,
    danger: ProfileColors.light.dangerInk,
    attention: ProfileColors.light.attentionInk,
  );

  static final dark = KitInks(
    constructive: ProfileColors.dark.constructiveInk,
    danger: ProfileColors.dark.dangerInk,
    attention: ProfileColors.dark.attentionInk,
  );

  /// The inks that go with [colors].
  static KitInks of(AppColors colors) => colors.dark ? dark : light;

  final Color constructive, danger, attention;
}
