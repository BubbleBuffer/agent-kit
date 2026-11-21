# Package layout and pinning

## Workspace

The root `pubspec.yaml` lists four Dart pub workspace members, each with
`resolution: workspace`:

```
packages/
  agent_kit_core/      pure Dart models, ChatReader and AgentBackend ports, capabilities, reducer, fake backend
  agent_kit_bubblepaw/ pure Dart BubblePaw stdio JSON-RPC adapter
  agent_kit/           Flutter agent widgets and compositions
apps/
  gallery/             agent scenes, scripted and optional live backend
```

`agent_kit` has one folder per widget group under `lib/src/` (see
[agent_kit and the gallery](agent-kit.md#package-structure)). `outline/` holds the
chapter presentation of a long chat: chapter cards, headings and section
dividers, the where-am-I strip, the contents and menus, and the
`OutlineController` a host owns for fold state and jumps. It works over plain
view models (`Outline`, `OutlineChapter`, `OutlineSection`) and host-supplied
`OutlineAction`s, needs nothing in `agent_kit_core`, and is exported through the
`agent_kit` barrel (README: `packages/agent_kit/lib/src/outline/README.md`).

The three library packages share version `0.21.1`; the gallery remains an
unpublished app. Local members use relative `path:` dependencies. The pure Dart
packages have their own strict analysis options; the root Flutter lint rules
cover the widget package and gallery. See [core](agent-kit-core.md),
[widgets and gallery](agent-kit.md) and the
[BubblePaw adapter](../packages/agent_kit_bubblepaw/README.md).

## Shared UI dependency

Product-neutral `bb_ui` and `bb_tokens` now live in
[BubbleBuffer/bb-ui](https://github.com/BubbleBuffer/bb-ui). Both `agent_kit` and
the gallery directly declare exactly this source:

```yaml
  bb_ui:
    git:
      url: https://github.com/BubbleBuffer/bb-ui
      ref: 012d9f283b8378fb7197c6238e7068dfd3205c30
      path: packages/bb_ui
```

`bb_tokens` comes through `bb_ui`'s relative path dependency in that repository.
Reach tokens through `package:bb_ui/tokens.dart` or its main barrel. A direct
`bb_tokens` entry pinned to a tag can conflict with its transitive source at the
resolved commit, so leave it transitive. The public token APIs, including
`KitLayout`, `KitMotion` and `KitInks`, remain available; `KitSpacing` and
`FormFactor` are gone in bb-ui 0.8 (use `Space`, and `Density` with
`SizeClass`). The pin is a commit of bb-ui's 0.8 line until its `v0.8.0` tag
exists; move both pins (and the plugin's `ref` in `analysis_options.yaml`) to
the tag then.

The bb-ui repository owns the vendored palette, colour generator, generated
colours, neutral package tests and neutral component gallery. Agent widgets
continue to read `BbTheme` roles derived from that palette. See
[bb_tokens colour workflow](https://github.com/BubbleBuffer/bb-ui/blob/012d9f283b8378fb7197c6238e7068dfd3205c30/packages/bb_tokens/README.md).

## Consuming the kit

For the widgets, declare only `agent_kit`; its relative core dependency is
resolved within the same Git checkout:

```yaml
  agent_kit:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.15.1
      path: packages/agent_kit
```

For the adapter alone, use that URL and ref with
`path: packages/agent_kit_bubblepaw`. It also brings core transitively.

When a host needs multiple agent packages directly, pin every same-repository
entry to the **same full commit SHA**, including a direct core entry if one is
needed. A direct tag reference and a transitive path dependency resolved at a
SHA may be treated as different sources by Pub. For direct primitive imports,
declare `bb_ui` with the exact external source above; do not copy its sources
into an application.

CI's Git consumer check pins `agent_kit` at the pushed commit, leaves core
transitive and declares `bb_ui` directly using the same pinned source. It analyzes
imports from the agent widgets, primitives and token re-export.

## Fonts and goldens

Hosts bundle Atkinson Hyperlegible Next, Fragment Mono and Bricolage Grotesque.
The agent gallery retains its own files and OFL licences in
`apps/gallery/assets/fonts`. `agent_kit/testing.dart` loads those files and the
Lucide icon fonts for the agent tests. The agent gallery, test configuration and
all existing golden PNGs stay here; neutral-gallery goldens live in bb-ui.

## Releasing

1. Release the required bb-ui tag before updating its Git pin here. Release
   0.21.0 pins bb-ui 0.9.1 by its merge commit `012d9f2` on bb-ui `main`
   (the commit to tag `v0.9.1`); switch the ref to the tag name once the tag
   is pushed.
2. Merge the agent-kit change with hosted CI green. Bump the three library
   versions together; the current release is `0.21.1`.
3. Tag the green commit on `main` as `v0.21.1` and push the tag.

### 0.21.1

The context meter's legend labels wrap within their run instead of
overflowing a narrow meter at large text sizes (found by BubblePaw-Desktop's
adaptive matrix at 480 px with 2x text). No API change.

### 0.21.0: bb-ui 0.9

bb-ui 0.9 builds its tokens from the unified BubbleBuffer language:

- Weights are `Weight.regular`, `strong`, `display` and `displayStrong`;
  0.8's `medium`, `semibold` and `bold` became `strong` (`displayStrong` for
  bold in the display face).
- `AppColors.onAccent` is `accentInk`; the palette's old `accentInk` (accent
  text) is `accentText`. `dart run bb_lints:migrate` makes both renames by
  type, so the two colours cannot swap.
- Token values follow the design repository, so text is heavier and spacing
  and control heights move slightly; the goldens are re-rendered. The wide
  crew scene is 20 px taller to fit.

Hosts move from 0.20 by running the migrate tool while still on 0.20 (bb-ui
0.8), then bumping both pins.

### 0.20.0: bb-ui 0.8

A breaking release for hosts:

- `BbTheme` and `BbThemeScope` take `density:` (bb-ui's `Density`, default
  pointer) instead of `formFactor:`; `BbTheme.spacing`, `sizeMedium` and
  `sizeExpanded` are gone (use `Space`, `SizeClass.mediumWidth` and
  `SizeClass.expandedWidth`). New getters: `metrics` and `touch`.
- `SizeClass` and `SizeClassScope` are bb-ui's, re-exported by `agent_kit`.
  `SizeClass.of`/`maybeOf` became `sizeClassOf(context)` (expanded without a
  builder); `isMedium` and `isExpanded` come from the `KitSizeClass` extension.
- `KitIcon.size` is an `IconSize`; `RailShowButton.size` is a `ControlSize`.
- Sizes follow the density (touch controls are 44 px) and spacing snaps to
  bb-ui's scale, so screens move by a few pixels.
- Hosts that set `formFactor: FormFactor.forWidth(w)` now set
  `density: Density.forPlatform(defaultTargetPlatform)` (or touch for a
  phone-sized test window) and keep layout decisions on `SizeClass`.

Applications update their pins and lockfiles when adopting a release. This
workspace ignores its generated `pubspec.lock`.

## CI

`.github/workflows/ci.yml` runs formatting (with a patch artifact on failure),
`dart analyze --fatal-infos` at the workspace root (which also runs the
bb_lints plugin; `flutter analyze` and `dart analyze` with sub-directory
arguments skip it), widget/gallery tests, agent goldens, strict core analysis and
tests, and the Git consumer check on pushes. `bubblepaw.yml` analyzes and tests
the adapter, verifies it against a pinned public BubblePaw host, and builds the
gallery for web and Linux. Colour generation and neutral package CI run in
bb-ui; the `raw-colours` job here checks the kit's own source. `private-strings.yml` checks tracked files with the `PRIVATE_STRINGS`
secret, secret formats and personal tool-folder rules. All jobs run on
GitHub-hosted runners.
