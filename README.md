# agent-kit

Flutter UI packages shared by BubbleBuffer apps: Scratch today, BubblePaw
Desktop next. No Material.

| Package | What it is |
|---|---|
| [`bb_tokens`](packages/bb_tokens) | Design tokens: colours (light and dark), type scale, layout, radii, motion. Scratch's look is the default. |
| [`bb_ui`](packages/bb_ui) | Product-neutral primitives: buttons, icon buttons, fields, hover, menus, tooltip, Lucide icons, sheets and modals, picker sheet, foldable stack card, reference chip, marked list, settings rows and controls. |

Agent packages (`agent_kit_core`, `agent_kit`) come later.

## Use it

Pin a tag of `bb_ui` through git; `bb_tokens` comes with it, and
`package:bb_ui/tokens.dart` re-exports it. See
[docs/package-layout.md](docs/package-layout.md).

```yaml
dependencies:
  bb_ui:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.1.0
      path: packages/bb_ui
```

The primitives use the font families Atkinson Hyperlegible Next, Fragment
Mono and Bricolage Grotesque. The kit does not bundle them yet; the app
declares them.

## Develop

A Dart pub workspace: `flutter pub get` at the root, then `flutter analyze`
and `flutter test` in a package. CI runs `dart format`, `flutter analyze`,
the tests of each package, a git-consumer check and the private-strings
check. Docs: [docs/README.md](docs/README.md).

## Licence

`AGPL-3.0-or-later`; see [LICENSE](LICENSE).
