# Package layout and pinning

## Workspace

The repo is a Dart pub workspace. The root `pubspec.yaml` lists the members;
each member has `resolution: workspace`. One `analysis_options.yaml` at the
root (the same rules as Scratch's app) covers every package.

```
packages/
  bb_tokens/   design tokens, no dependencies besides Flutter
  bb_ui/       primitives; depends on bb_tokens (path) and lucide_icons_flutter
  agent_kit_core/  pure Dart chat models, backend port, reducer, fake backend
  agent_kit/   Flutter widgets (theme, status, ...); see agent-kit.md
```

`agent_kit_core` has its own stricter `analysis_options.yaml` (strict casts,
inference and raw types; `package:lints` recommended) and is described in
[agent-kit-core.md](agent-kit-core.md).

New packages are added under `packages/` or `apps/` and to the root
`workspace:` list (`apps/gallery` is the gallery app). Members depend
on each other with relative `path:` dependencies.

## bb_tokens

`lib/tokens.dart` is Scratch's `app/lib/ui/tokens.dart` as of 0.1.0:
`AppColors` (light, dark), `TypeScale`, `Layout`, `Radii`, `Motion`,
`FormFactor`, `AppTheme` and the `context.colors` / `context.type` lookups.
The kit tokens `KitLayout`, `KitSpacing`, `KitMotion` and `KitInks` follow, with the values of the mockup's `theme.css` (see [agent-kit.md](agent-kit.md)).
The only cut: Scratch's file re-exported its app clock (`clockNow`); that
re-export stays in Scratch. The values are hand-written for now; a generator
from the BubbleBuffer design tokens comes later.

## bb_ui

Each file is the Scratch file of the same name from `app/lib/ui/`, unchanged
except as noted. `package:bb_ui/bb_ui.dart` exports them all. Eight files
(`buttons`, `icons`, `lines`, `lucide`, `marked_list`, `selection`,
`settings_controls`, `tooltip`) were also run through `dart format`, which
changed only whitespace and trailing commas; four `if`s it split over two
lines got braces for the `curly_braces_in_flow_control_structures` lint.

| File | Contents | Change from Scratch |
|---|---|---|
| `buttons.dart` | buttons, `IconBtn` | none |
| `fields.dart` | text fields | none |
| `hover.dart` | hover and press feedback | none |
| `icons.dart`, `lucide.dart` | `Ico` and the Lucide glyph widget | none |
| `lines.dart` | hairlines | none |
| `marked_list.dart` | marked list | none |
| `menu.dart` | menus, `MenuList` | none |
| `modal.dart`, `sheet.dart`, `routes.dart` | modal panels, bottom sheets, scroll behaviour | none |
| `picker_sheet.dart` | `PickerSheet` | none |
| `reference_chip.dart` | reference chip | none |
| `selection.dart` | accent text-selection handles | none |
| `stack_card.dart` | `FoldableStackCard` | none |
| `tooltip.dart` | `AppTooltip` | the command-registry import is replaced by `AppTooltip.commandShortcuts`, a lookup the app sets |
| `settings_controls.dart` | settings heading, row, toggle, select, field, outline button, copyable text | from Scratch's `features/settings/controls.dart`; imports `bb_ui.dart` instead of Scratch's `ui/ui.dart` |
| `tokens.dart` | re-export of `bb_tokens` | new, so the files keep their `import 'tokens.dart'` |

### Host hooks

- `AppTooltip.commandShortcuts`: returns the shortcuts of a command id, or
  null. The default knows no commands. Scratch points it at its command
  registry when the registry is created.

### Fonts

The tokens name the families Atkinson Hyperlegible Next, Fragment Mono and
Bricolage Grotesque. The consuming app bundles them. The kit's tests render
with Flutter's test font.

## Consuming the kit

Pin a tag of `bb_ui` through git, with `path:` to the package:

```yaml
  bb_ui:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.1.0
      path: packages/bb_ui
```

`bb_tokens` comes with it: `bb_ui`'s relative path dependency resolves in
the same git checkout, at the commit the tag points to. Reach the tokens
through `package:bb_ui/tokens.dart` (or the `bb_ui.dart` barrel); don't
declare `bb_tokens` beside `bb_ui`. Pub records the transitive copy at the
resolved commit and a direct `ref: v0.1.0` entry at the tag name, treats the
two as different sources, and version solving fails. A consumer that must
declare `bb_tokens` directly would have to pin both entries to the same
commit sha instead of a tag.

CI's "git dependency resolves" job checks this on every push: a consumer
pins `bb_ui` by the pushed branch or tag name and imports both libraries.

To bump: change `ref:` to the new tag, run `flutter pub get`, and commit the
updated `pubspec.lock`.

## Releasing

1. Merge the change through a pull request with CI green.
2. Bump `version:` in the changed packages' pubspecs (they share one tag).
3. Tag the green commit on `main`: `git tag -a vX.Y.Z -m "agent-kit X.Y.Z"`,
   then push the tag.

## CI

`.github/workflows/ci.yml`: `dart format --set-exit-if-changed` (a patch is
uploaded on failure), `flutter analyze`, `flutter test` per Flutter package
(golden tests excluded), a `goldens` job (see [agent-kit.md](agent-kit.md)), `dart analyze
--fatal-infos` and `dart test` per pure Dart package (`agent_kit_core`), and
the git-consumer check on pushes. `.github/workflows/private-strings.yml` runs
`scripts/check-private-strings.sh` with the `PRIVATE_STRINGS` secret (patterns
for private host names, addresses and domains), plus secret formats,
self-hosted runners and personal tool folders. Every job runs on GitHub-hosted
`ubuntu-latest`; the repo is public, so self-hosted runners are never used.
