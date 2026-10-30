# BbTheme

The one `ThemeExtension` of the kit, with the semantic colour roles, status styles, radii, motion, type scale and layout tokens that widgets read through `BbTheme.of(context)` or `context.bb`, and that `BbThemeScope` installs for a subtree.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

No demo: not a visual widget.

## Parameters

`BbTheme` (the default constructor; `colors` is positional):

| Parameter | Type | Notes |
|---|---|---|
| `colors` | `AppColors` | required. The bb-ui palette every role is derived from. `BbTheme.light()` passes `AppColors.light`, `BbTheme.dark()` passes `AppColors.darkTheme`. |
| `formFactor` | `FormFactor` | Default `FormFactor.desktop`. Decides touch sizing and the type scale (`typeScale`). It is not a size class. |
| `layout` | `KitLayout` | Default `KitLayout.standard`. The size-class thresholds and the pane tokens. |
| `spacing` | `KitSpacing` | Default `KitSpacing.standard`. The spacing scale. |

Also `BbTheme.light({formFactor})` and `BbTheme.dark({formFactor})`, which build the theme from bb-ui's light or dark palette.

`BbThemeScope` (a `StatelessWidget`):

| Parameter | Type | Notes |
|---|---|---|
| `brightness` | `Brightness` | required. `Brightness.dark` builds `BbTheme.dark`; anything else builds `BbTheme.light`. |
| `child` | `Widget` | required. The subtree that reads the theme. |
| `formFactor` | `FormFactor` | Default `FormFactor.desktop`. Passed to the theme and to bb-ui's `AppTheme`. |

`BbThemeScope` installs a `BbTheme` (an `InheritedWidget`), bb-ui's `AppTheme` (which the bb-ui primitives read), and a default `DefaultTextStyle` in the theme's body type and ink. No `MaterialApp` or `Theme` is needed.

## Fields

`BbTheme` has these fields. The source column gives the value in the constructor (`theme/bb_theme.dart`, `BbTheme._`).

| Field | Type | Source |
|---|---|---|
| `colors` | `AppColors` | the palette passed in |
| `formFactor` | `FormFactor` | the parameter |
| `layout` | `KitLayout` | the parameter |
| `spacing` | `KitSpacing` | the parameter |
| `brightness` | `Brightness` | `colors.dark ? dark : light` |
| `canvas` | `Color` | `colors.desk` (the desk behind sheets) |
| `surface` | `Color` | `colors.bgPrimary` (the sheet a transcript sits on) |
| `surface2` | `Color` | `colors.bgSecondary` (wells, bubbles, code, the composer) |
| `ink` | `Color` | `colors.textPrimary` |
| `muted` | `Color` | `colors.textSecondary` |
| `faint` | `Color` | `colors.textTertiary` |
| `seam` | `Color` | `colors.border` (hairlines and card edges) |
| `thread` | `Color` | `colors.thread` |
| `threadStrong` | `Color` | `colors.threadStrong` (dashed borders, hollow marks) |
| `hover` | `Color` | `colors.bgHover` |
| `pressed` | `Color` | `colors.bgPressed` |
| `accent` | `Color` | `colors.accent` (primary action, selection, live marks) |
| `accentHover` | `Color` | `colors.accentHover` |
| `accentInk` | `Color` | `colors.accentText` |
| `onAccent` | `Color` | `colors.onAccent` |
| `constructive` | `Color` | `colors.okBg` |
| `constructiveInk` | `Color` | `KitInks` constructive (text on the fill) |
| `information` | `Color` | `colors.infoBg` |
| `informationInk` | `Color` | `colors.textSecondary` |
| `attention` | `Color` | `colors.attnBg` |
| `attentionInk` | `Color` | `KitInks` attention |
| `danger` | `Color` | `colors.dangerBg` |
| `dangerInk` | `Color` | `KitInks` danger |
| `focus` | `Color` | `colors.focus` |
| `codeBackground` | `Color` | `colors.inlineCodeBg` |
| `codeInk` | `Color` | `colors.inlineCodeText` |
| `rail` | `Color` | dark: `colors.rail`; light: `colors.bgSecondary` |
| `railHover` | `Color` | dark: `colors.rail2`; light: `colors.bgHover` |
| `railSelected` | `Color` | dark: `railInk` at 10% alpha blended over `rail2`; light: `colors.bgPressed` |
| `railInk` | `Color` | dark: `colors.railInk`; light: `colors.textPrimary` |
| `railMuted` | `Color` | dark: `colors.railMuted`; light: `colors.textSecondary` |
| `railLine` | `Color` | dark: `colors.railLine`; light: `colors.border` |
| `status` | `Map<ChatStatus, BbStatusStyle>` | one style for each `ChatStatus`: `needsYou`, `running`, `failed`, `done`, `idle`, `interrupted` |
| `askingParent` | `BbStatusStyle` | `colors.palette.statusAskingParentMark` and `...Ink`; no fill |
| `ctxOpening` | `Color` | `colors.palette.ctxOpening` |
| `ctxSummary` | `Color` | `colors.palette.ctxSummary` |
| `ctxLive` | `Color` | `colors.palette.ctxLive` |
| `radii` | `BbRadii` | const. Getters `sm`, `md`, `lg`, `sheet`, `ctl`, `field`, `panel`, `pill` (bb-ui `Radii`) |
| `motion` | `BbMotion` | const. Getters `fast`, `standard`, `sheet`, `wiggle`, `breathe`, `ease`, `settle` |
| `typeScale` | `TypeScale` (getter) | `TypeScale.mobile` when `formFactor` is mobile, else `TypeScale.desktop` |
| `sizeMedium` | `double` (getter) | `layout.sizeMedium` |
| `sizeExpanded` | `double` (getter) | `layout.sizeExpanded` |

`statusStyle(ChatStatus)` returns `status[s]`. A `BbStatusStyle` has `mark` (the dot, square or ring), `ink` (the text and icon colour), and `fill` and `line` (set only for `needsYou`).

Reading the theme: `BbTheme.of(context)` and `context.bb` assert that a `BbThemeScope` is above the context. `BbTheme.maybeOf(context)` returns null instead. `copyWith` rebuilds the theme with a different palette, form factor, layout or spacing. `lerp` does not blend: the nearer theme wins at the halfway point.

## Size classes

`BbTheme` is not a layout widget. It holds the thresholds: `sizeMedium` (compact below it) and `sizeExpanded` (expanded from it), both from `layout` (bb-ui's `KitLayout`). They are 600 and 1000 px. `docs/agent-kit.md:125` and `packages/agent_kit/test/bb_theme_test.dart:65-66` state these values. `SizeClassBuilder` reads them.

`formFactor` is separate. It is set by the host (the gallery sets it from the scene's width, `apps/gallery/lib/src/scene_frame.dart:34`), and it changes touch sizing and the type scale only. It does not change the layout.

## Accessibility

- `BbTheme.reducedMotion(context)` returns `MediaQuery.maybeDisableAnimationsOf(context) ?? false` (`bb_theme.dart:227`). The widgets that check it are `status/status_mark.dart:254`, `context/context_pane.dart:193`, `context/context_parts.dart:113`, `context/context_history.dart:104`, and `workspace/agent_workspace.dart:421` and `:658`.
- The `...Ink` roles are the text colours for the state fills, taken from `KitInks.of(colors)` (`bb_theme.dart:83`, `:116`, `:120`, `:122`).
- The theme adds no `Semantics`.

## Gallery and tests

- Gallery: `SceneFrame.build` wraps each scene in a `BbThemeScope` with the scene's brightness and `FormFactor.forWidth(width)` (`apps/gallery/lib/src/scene_frame.dart:32-34`). The toolbar's Light and Dark button (`apps/gallery/lib/src/toolbar.dart:50`) changes `controller.brightness`, which `apps/gallery/lib/src/gallery_app.dart:62-72` passes to each `SceneFrame`. `apps/gallery/lib/components/composer.dart:448` and `apps/gallery/lib/src/live_gallery.dart:182` also wrap their content in a `BbThemeScope`.
- Golden: no shot. The scene goldens (`apps/gallery/test/scenes_golden_test.dart`) render every scene in light and dark through `SceneFrame`, so each one shows the roles.
- Other tests:
  - `packages/agent_kit/test/bb_theme_test.dart`: the light and dark roles match the mockup's token mapping; the status roles follow the status table; the size thresholds and pane tokens match `theme.css`; `BbThemeScope` gives a `BbTheme` and bb-ui's `AppTheme`.
  - The test harnesses wrap widgets in `BbThemeScope`: `packages/agent_kit/test/harness.dart`, `packages/agent_kit/test/chrome/chrome_harness.dart`, `packages/agent_kit/test/composer/composer_harness.dart`, `packages/agent_kit/test/compositions/compositions_harness.dart`, `packages/agent_kit/test/outline/outline_harness.dart`, `packages/agent_kit/test/transcript/harness.dart`, and `packages/agent_kit/test/status_mark_test.dart`.
  - `packages/agent_kit/test/transcript/transcript_test.dart` checks text colours against `BbTheme.light().dangerInk` and `constructiveInk` (`:259`, `:437`).
