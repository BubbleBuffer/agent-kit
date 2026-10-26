# Package layout and pinning

## Workspace

The repo is a Dart pub workspace. The root `pubspec.yaml` lists the members;
each member has `resolution: workspace`. One `analysis_options.yaml` at the
root (the same rules as Scratch's app) covers every package.

```
packages/
  bb_tokens/   design tokens, no dependencies besides Flutter
  bb_ui/       primitives; depends on bb_tokens (path) and lucide_icons_flutter
```

New packages (`agent_kit_core`, `agent_kit`, later `apps/gallery`) are added
under `packages/` or `apps/` and to the root `workspace:` list. Members depend
on each other with relative `path:` dependencies.

## bb_tokens

`lib/tokens.dart` is Scratch's `app/lib/ui/tokens.dart` as of 0.1.0:
`AppColors` (light, dark), `TypeScale`, `Layout`, `Radii`, `Motion`,
`FormFactor`, `AppTheme` and the `context.colors` / `context.type` lookups.
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

Pin a tag through git, with `path:` to the package. Declare `bb_tokens` too
when the app imports it directly:

```yaml
  bb_tokens:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.1.0
      path: packages/bb_tokens
  bb_ui:
    git:
      url: https://github.com/BubbleBuffer/agent-kit.git
      ref: v0.1.0
      path: packages/bb_ui
```

`bb_ui`'s path dependency on `bb_tokens` resolves inside the same git
checkout, so both entries name the same package. CI's "git dependency
resolves" job checks this on every push, with and without the direct
`bb_tokens` entry.

To bump: change `ref:` in both entries to the new tag, run `flutter pub get`,
and commit the updated `pubspec.lock`.

## Releasing

1. Merge the change through a pull request with CI green.
2. Bump `version:` in the changed packages' pubspecs (they share one tag).
3. Tag the green commit on `main`: `git tag -a vX.Y.Z -m "agent-kit X.Y.Z"`,
   then push the tag.

## CI

`.github/workflows/ci.yml`: `dart format --set-exit-if-changed`,
`flutter analyze`, `flutter test` per package, and the git-consumer check on
pushes. `.github/workflows/private-strings.yml` runs
`scripts/check-private-strings.sh` with the `PRIVATE_STRINGS` secret (patterns
for private host names, addresses and domains), plus secret formats,
self-hosted runners and personal tool folders. Every job runs on GitHub-hosted
`ubuntu-latest`; the repo is public, so self-hosted runners are never used.
