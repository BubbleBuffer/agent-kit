# agent_kit and the gallery

`packages/agent_kit` is the Flutter widget package of the kit. It depends on
`bb_ui` (primitives, which bring `bb_tokens`) and `agent_kit_core` (chat view
models and the backend port). `apps/gallery` shows its widgets on
`agent_kit_core`'s scripted fake backend. The look is the approved Scratch-skin
mockup (`lab/design/scratch-skin/` in the agent GUI lab: `theme.css` for
values, `app.css` and `app.js` for structure, `shots/` for the picture, and
`NOTES.md` for the token mapping and departures). The mockup is the visual
spec.

## Package structure

One folder per widget group under `packages/agent_kit/lib/src/`, so parallel
work does not collide. Each has one barrel (`<folder>/<folder>.dart`)
re-exported from `lib/agent_kit.dart`, and a `README.md` saying what goes
there and which mockup parts it covers.

| Folder | Holds | State |
|---|---|---|
| `theme/` | `BbTheme`, `BbThemeScope`, `SizeClass`, `SizeClassBuilder` | built |
| `status/` | `StatusMark` | built |
| `transcript/` | items, activity and evidence rows, edits, diff, plan | placeholder |
| `composer/` | composer, approval bar, queue row, picks | placeholder |
| `chrome/` | rail, header, crew strip, ledger | placeholder |
| `workspace/` | split tree, panes, docking, edge tabs | placeholder |
| `compositions/` | `AgentWorkbench`, `AgentChatPane` | placeholder |

`package:agent_kit/testing.dart` is not in the barrel: it loads the bundled
fonts (and the Lucide icon fonts, which `flutter test` does not load) for
tests. The font files live in `apps/gallery/assets/fonts/` with their OFL
licences; the gallery bundles them and `agent_kit`'s tests read them from there.
Hosts bundle the fonts themselves.

No state-management package and no code generation: widgets take plain values
and `ChangeNotifier`/`ValueListenable`s around `ChatFeed`.

## Theme

`BbTheme` is the one `ThemeExtension`, in `agent_kit` (not `bb_ui`, which is
Material-free; only the `ThemeExtension` class is imported from Material).
`BbThemeScope(brightness:, formFactor:)` installs it together with `bb_ui`'s
`AppTheme`, so the primitives and the kit read the same palette. Read it with
`BbTheme.of(context)` or `context.bb`. Widgets read roles, never raw colours.

Roles (the mockup's `theme.css` names; values from `bb_tokens`'
`AppColors`, light and dark):

| Role | Scratch token |
|---|---|
| `canvas` | `desk` |
| `surface`, `surface2` | `bgPrimary`, `bgSecondary` |
| `ink`, `muted`, `faint` | `textPrimary`, `textSecondary`, `textTertiary` |
| `seam`, `thread`, `threadStrong` | `border`, `thread`, `threadStrong` |
| `accent`, `accentInk`, `onAccent` | `accent`, `accentText`, `onAccent` |
| `constructive`, `information`, `attention`, `danger` | `okBg`, `infoBg`, `attnBg`, `dangerBg` |
| `constructiveInk`, `informationInk`, `attentionInk`, `dangerInk` | `KitInks` (see below) |
| `rail*` | follows the theme: light from `bgSecondary` and friends, dark Scratch's `rail*` |

Also on the theme: `typeScale` (Scratch's `TypeScale`, mobile under the 768 px
form factor), `spacing` (`KitSpacing`), `radii`, `motion` (with the 2400 ms
`breathe` loop), `layout` (`KitLayout`) and `statusStyle(status)`.

### Tokens added to `bb_tokens`

`theme.css` has values Scratch's tokens lack. They live in `bb_tokens`'
`tokens.dart`, matching `theme.css`:

- `KitLayout`: `sizeMedium` 600, `sizeExpanded` 1000, `fitComposer` 460,
  `paneMinWidth` 200, `paneMinHeight` 120, `edgeTab` 28, `controlHeight` 32,
  `rowHeight` 28.
- `KitInks`: the text colours of the state roles (constructive `#397748` /
  `#93BD9B`, danger `#AD4B4B` / `#E0A3A3`, attention `#874016` / `#F0D29C`,
  light / dark). `informationInk` is `textSecondary`.
- `KitMotion`: `breathe`, 2400 ms.
- `KitSpacing`: `theme.css` has no scale; the steps are 2, 4, 8, 12, 16 and 24
  px, taken from `app.css`.

## Size classes

Layout depends on the width of the widget's own container, never the window:
`SizeClassBuilder` wraps a `LayoutBuilder` and picks `SizeClass.compact` (below
600 px), `medium` (to below 1000 px) or `expanded`, using the theme's
thresholds. Descendants read it with `SizeClass.of(context)`; a nested builder
(a pane inside a workbench) measures its own area. Do not use
`MediaQuery.size` for layout. The form factor (`BbTheme.formFactor`, from the
window width as in Scratch) decides only touch sizing and the type scale.

## Status

Status is drawn by `StatusMark` only: every other widget puts one next to its
text. `StatusMark(status)` is the dot form (list rows, meta lines);
`StatusMark.pill(status)` is the header form. `label` and `detail` override the
text; the running mark breathes unless `animate: false` or the platform
reduces motion. `StatusMark.work(WorkState)` maps child agents and jobs.

| Status | Role | Dot form | Pill form |
|---|---|---|---|
| `needsYou` | attention | accent dot, attention ink, bold | attention fill and hairline, attention ink |
| `running` | ink | breathing square, muted text | same |
| `failed` | danger | red dot, danger ink | `circle-x`, danger ink |
| `done` | constructive | green dot, constructive ink | `circle-check`, constructive ink |
| `idle` | muted | hollow ring, muted text | same |
| `interrupted` | muted | ring with a dot (not in the mockup) | same |

Only "needs you" fills a pill and only it is warm.

## Gallery

`apps/gallery` (`flutter run -d chrome` in that folder). The toolbar switches
scene (the mockup's A workbench, B Scratch pane, C phone and D workspace as
placeholders, plus Components, which lists each widget in each state), light or
dark, and the width (a 360 to 1600 px slider that constrains the content, so
size classes follow it). The chat is the "Quota bar flickers on reconnect"
script of `agent_kit_core/fake.dart` on a `ScriptedBackend`, followed through a
`ChatFeed`. The default clock is a `ManualClock` played to the end, so scenes
open on the mid-task state (waiting for approval); "+10 s", "Play" and "Replay"
step it. Pass `GalleryController(clock: () => const SystemClock())` for real
time.

## Adding a widget

1. Add the file under the widget's folder in `agent_kit/lib/src/`, read only
   `BbTheme` roles and `SizeClass`, and export it from the folder's barrel.
2. Show it in each state in `apps/gallery/lib/src/components_scene.dart`
   (and in the scene it belongs to once the composition exists).
3. Add a widget test (`packages/agent_kit/test/`) and a golden: copy
   `status_mark_golden_test.dart` (tag `golden`, `pumpKit` from
   `test/harness.dart`, light and dark).
4. Render the golden (below), look at the PNG next to the mockup shot, and
   commit it under `test/goldens/`.
5. Update the folder's `README.md` and the table above.

## Goldens and how to view the shots

Golden tests are tagged `golden`; the normal test job excludes them and the
`goldens` job runs them. They render `StatusMark` in `packages/agent_kit`
(`test/goldens/status_mark_{light,dark}.png`) and every gallery scene in
`apps/gallery` at 1440, 1000 and 390 px in light and dark
(`test/goldens/<scene>_<width>_<theme>.png`), with the scripted chat played to
its end. Text is real because the bundled fonts are loaded in the tests.
Rendering happens only in CI, on `ubuntu-latest` with Flutter pinned to the
version Scratch pins (3.47.5); goldens rendered elsewhere will not match.

- Push or pull request: the job compares with the committed PNGs and fails on
  a difference (`golden-failures` artifact holds the diffs).
- Manual run: `gh workflow run ci.yml --ref <branch>` re-renders without
  comparing.
- Either way the job uploads the PNGs as the `gallery-shots` artifact:
  `gh run download <run id> -n gallery-shots` gives `components/` and
  `scenes/`. Compare them with `lab/design/scratch-skin/shots/`.
- To accept new renders, download the artifact from a manual run, copy
  `components/*.png` to `packages/agent_kit/test/goldens/` and `scenes/*.png`
  to `apps/gallery/test/goldens/`, and commit them.
- Formatting is not run on the PC either: when the format job fails it uploads
  `format-patch`; `git apply format.patch` fixes it.
