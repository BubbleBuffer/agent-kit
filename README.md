# agent-kit

Agent chat widgets and backend ports for BubbleBuffer apps. The three library
packages share version **0.15.0**; product-neutral Flutter primitives and design
tokens live in [bb-ui](https://github.com/BubbleBuffer/bb-ui).

| Package | What it is |
|---|---|
| [`agent_kit`](packages/agent_kit) | Flutter agent UI: theme, status, transcript, composer, chrome, context, workspace and compositions. |
| [`agent_kit_core`](packages/agent_kit_core) | Pure Dart chat models, the `ChatReader` and `AgentBackend` ports, capabilities and constraints, event reducer, typed command errors and a scripted backend. |
| [`agent_kit_bubblepaw`](packages/agent_kit_bubblepaw) | Pure Dart BubblePaw stdio JSON-RPC backend implementing that port. |

[`apps/gallery`](apps/gallery) keeps the agent scenes, scripted backend and
optional live BubblePaw mode. Its bundled fonts and committed goldens remain
here. The neutral component gallery belongs to bb-ui.

## Use it

Depend on the agent widget package through Git:

```yaml
dependencies:
  agent_kit:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.15.0
      path: packages/agent_kit
```

The package brings `agent_kit_core` and pins `bb_ui` to
`https://github.com/BubbleBuffer/bb-ui`, ref `v0.6.0`, path `packages/bb_ui`.
Tokens are re-exported through `package:bb_ui/tokens.dart`. A host that imports
`bb_ui` directly should declare that identical Git source. See
[package layout and pinning](docs/package-layout.md) for multiple agent packages.

Hosts bundle Atkinson Hyperlegible Next, Fragment Mono and Bricolage Grotesque.
The gallery includes those fonts with their OFL licences for its own use and
the agent widget tests.

## Develop

This is a Dart pub workspace containing the three libraries and agent gallery.
CI runs formatting, analysis, package tests, golden comparisons and a Git
consumer check on GitHub-hosted runners. The BubblePaw workflow also checks the
adapter against a pinned public host and builds the gallery. Colour generation
and neutral package checks live in bb-ui. See [the docs](docs/README.md).

## Licence

`AGPL-3.0-or-later`; see [LICENSE](LICENSE).
