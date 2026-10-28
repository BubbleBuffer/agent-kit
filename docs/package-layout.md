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

The three library packages share version `0.14.0`; the gallery remains an
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
      ref: v0.6.0
      path: packages/bb_ui
```

`bb_tokens` comes through `bb_ui`'s relative path dependency in that repository.
Reach tokens through `package:bb_ui/tokens.dart` or its main barrel. A direct
`bb_tokens` entry pinned to a tag can conflict with its transitive source at the
resolved commit, so leave it transitive. The public token APIs, including
`KitLayout`, `KitSpacing`, `KitMotion` and `KitInks`, remain available.

The bb-ui repository owns the vendored palette, colour generator, generated
colours, neutral package tests and neutral component gallery. Agent widgets
continue to read `BbTheme` roles derived from that palette. See
[bb_tokens colour workflow](https://github.com/BubbleBuffer/bb-ui/blob/v0.6.0/packages/bb_tokens/README.md).

## Consuming the kit

For the widgets, declare only `agent_kit`; its relative core dependency is
resolved within the same Git checkout:

```yaml
  agent_kit:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.14.0
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
transitive and declares `bb_ui` directly using its `v0.6.0` source. It analyzes
imports from the agent widgets, primitives and token re-export.

## Fonts and goldens

Hosts bundle Atkinson Hyperlegible Next, Fragment Mono and Bricolage Grotesque.
The agent gallery retains its own files and OFL licences in
`apps/gallery/assets/fonts`. `agent_kit/testing.dart` loads those files and the
Lucide icon fonts for the agent tests. The agent gallery, test configuration and
all existing golden PNGs stay here; neutral-gallery goldens live in bb-ui.

## Releasing

1. Release the required bb-ui tag before updating its Git pin here. This split
   requires `bb-ui` tag `v0.6.0` to exist before dependency resolution can pass.
2. Merge the agent-kit change with hosted CI green. Bump the three library
   versions together; the current release is `0.14.0`.
3. Tag the green commit on `main` as `v0.14.0` and push the tag.

Applications update their pins and lockfiles when adopting a release. This
workspace ignores its generated `pubspec.lock`.

## CI

`.github/workflows/ci.yml` runs formatting (with a patch artifact on failure),
Flutter analysis, widget/gallery tests, agent goldens, strict core analysis and
tests, and the Git consumer check on pushes. `bubblepaw.yml` analyzes and tests
the adapter, verifies it against a pinned public BubblePaw host, and builds the
gallery for web and Linux. Colour generation and neutral package CI run in
bb-ui; the `raw-colours` job here checks the kit's own source. `private-strings.yml` checks tracked files with the `PRIVATE_STRINGS`
secret, secret formats and personal tool-folder rules. All jobs run on
GitHub-hosted runners.
