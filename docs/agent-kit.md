# agent_kit and the gallery

`packages/agent_kit` is the Flutter widget package of the kit. It depends on
`bb_ui` from [bb-ui](https://github.com/BubbleBuffer/bb-ui), pinned to `v0.7.1`
(primitives, which bring `bb_tokens`), and `agent_kit_core` (chat view
models and the backend port). `apps/gallery` shows its widgets on
`agent_kit_core`'s scripted fake backend. The look is the approved Scratch-skin
mockup (`lab/design/scratch-skin/` in the agent GUI lab: `theme.css` for
values, `app.css` and `app.js` for structure, `shots/` for the picture, and
`NOTES.md` for the token mapping and departures). The mockup is the visual
spec.

`packages/agent_kit_bubblepaw` adds a pure Dart `AgentBackend` over an owned
BubblePaw stdio JSON-RPC child. It pins protocol `0.1`, negotiates capabilities
and recovers snapshots after event gaps. See its
[README](../packages/agent_kit_bubblepaw/README.md) for the v0.3.1 mapping and
limits. The gallery's optional desktop live mode uses `BP_BIN`, `BP_WORKSPACE`
and `BP_DATA` Dart defines; with no defines the scripted gallery is unchanged.
See [gallery usage](../apps/gallery/README.md).

## Package structure

One folder per widget group under `packages/agent_kit/lib/src/`, so parallel
work does not collide. Each has one barrel (`<folder>/<folder>.dart`)
re-exported from `lib/agent_kit.dart`, and a `README.md` saying what goes
there and which mockup parts it covers.

| Folder | Holds |
|---|---|
| `theme/` | `BbTheme`, `BbThemeScope`, `SizeClass`, `SizeClassBuilder` |
| `status/` | `StatusMark` |
| `transcript/` | items, activity and evidence rows, edits, diff, plan |
| `composer/` | composer, approval bar, queue row, picks |
| `chrome/` | rail, header, crew strip, ledger |
| `context/` | Context pane, meter bar, compaction marker |
| `outline/` | chapter cards, headings, dividers, where-am-I strip, contents, `OutlineController` |
| `history/` | compacted history: chapter, episode and legacy cards, the boundary hairline, `HistoryController` |
| `workspace/` | split tree, panes, docking, edge tabs |
| `compositions/` | `AgentWorkbench`, `AgentChatPane` |
| `shared/` | internal helpers: path segments, the one icon drawing (`kit_icon.dart`) |

## Compositions

Two widgets put the folders together; an app shows a working agent chat by
dropping one in, fed by an `AgentBackend`.

`AgentChatPane(backend, chatId)` is one chat: header, transcript with its
plan, approval bars, question prompt, queued inputs, error line and composer,
with the crew strip, or a side column (the ledger) when the host gives one.
It opens a `ChatFeed`, closes it when the chat or backend changes, and maps
every user action to a backend command (approve, deny, answer, steer or queue,
cancel, edit or remove a queued input, undo an edit, resume, fork, archive,
pick model or profile). A command that fails shows the error's message in a
dismissible line; a failed send gives the text back to the composer. Optional
controls the backend's `capabilities` lack are hidden. Send, Stop and approval
actions default to their corresponding capabilities; `paneActions` can
explicitly override them. For a read-only backend, the messages and pending approvals stay, while Send, Stop and Approve, For session
and Deny are drawn disabled and cannot be invoked (the composer field is
read-only). Resolved questions
show their answer lines in the transcript; an interrupted run ends with the
interrupted notice and a Resume action.

A host can fit the pane into its own screen. `metrics` (`PaneMetrics`) sets the
transcript gutter, row gap, list padding and the dock's padding and gutter; the
defaults are the kit's own spacing. `showHeader: false` leaves the `ChatHeader`
out and `headerBuilder` replaces it. `transcriptBuilder` replaces the transcript
list: it gets the snapshot and a `PaneTranscriptSlot` (the wired actions, the
controller, the content width, the metrics, the layout, the inserts and the
interrupted notice), so a host that draws the history another way (an outline,
compacted summaries) keeps the pane's commands, dock and feed.
`transcriptController` hands the host the pane's scroll controller; the pane
never disposes it.

`AgentWorkbench(backend)` is the app shell: the session rail (chats grouped
by day, from `listChats`), an `AgentChatPane` in the sheet, the ledger or crew
strip, and an optional `AgentWorkspace` beside the chat. The whole width picks
the rail and the ledger (expanded and no workspace open) or crew strip; the
area beside the rail picks how the workspace sits (a full-screen sheet when
compact, a 240 to 420 px column when medium, beside a 444 to 584 px chat when
expanded). The host passes what the kit cannot know: the workspace name, the
per-model usage, panes, and callbacks to open files, agents and jobs.

With a paged `listChats` the rail ends in a "Show older sessions" row that
loads the next `nextCursor` page; with the `children` capability the ledger
shows Cancel on a running agent (expanded width only); its heading counts only
running agents ("Crew" with "1 running · 2 finished" when mixed). `ProviderSettings(backend: ...)` is the
settings section for providers and models: a read-only list, plus Make
default with `defaultModel`. The composer's model pick, when `defaultModel` is
on, is titled "Default model" because it sets the host default.

Needs outside the kit: `agent_kit_core` has no interrupted transcript item (the
pane uses the run's outcome), no answered time or transcript position for a
question (placed by request time), no older-history paging, and no per-model
usage.

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

### Tokens supplied by `bb_tokens`

`theme.css` has values Scratch's tokens lack. They live in bb-ui's `bb_tokens`
package and remain available through `package:bb_ui/tokens.dart`:

- `KitLayout`: `sizeMedium` 600, `sizeExpanded` 1000, `fitComposer` 460,
  `paneMinWidth` 200, `paneMinHeight` 120, `edgeTab` 28, `controlHeight` 32,
  `rowHeight` 28.
- `KitInks`: the text colours of the state roles (constructive `#397748` /
  `#93BD9B`, danger `#AD4B4B` / `#E0A3A3`, attention `#874016` / `#F0D29C`,
  light / dark). `informationInk` is `textSecondary`.
- `KitMotion`: `breathe`, 2400 ms.
- `KitSpacing`: `theme.css` has no scale; the steps are 2, 4, 8, 12, 16 and 24
  px, taken from `app.css`.

### One colour source

The palette is the `agent-kit` profile of the BubbleBuffer design repository.
The [bb-ui repository](https://github.com/BubbleBuffer/bb-ui) owns the vendored
palette, colour generator and generated `ProfileColors.light` and `.dark`.
`AppColors`, `KitInks`, `spaceColor` and the status styles of `BbTheme` read
that palette; roles without an `AppColors` field are on `AppColors.palette`.
The mockup's `theme.css` is generated from the same profile. Widgets use
`kTransparent` for transparent paint and theme or palette roles for colours.

Colour generation, drift checking and the raw-colour check of bb-ui's own code run
in bb-ui. Raw colours in this repository's `packages/agent_kit*` and `apps/` are
caught by `scripts/check-raw-colours.sh` (vendored from bb-ui `v0.7.1`; re-sync it
when the pin moves) in the `raw-colours` CI job, which first runs
`scripts/test-check-raw-colours.sh`, a failing-case test of the script.
To change the palette, follow its
[bb_tokens workflow](https://github.com/BubbleBuffer/bb-ui/blob/v0.7.1/packages/bb_tokens/README.md),
release that dependency and update both `bb_ui` Git pins here together. Agent
CI then compares the existing agent goldens against the updated palette; it
does not generate a local copy of the shared colours.

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
`StatusMark.pill(status)` is the header form. `label` replaces the label and `detail` follows it after " · "; the running mark breathes unless `animate: false` or the platform
reduces motion. `StatusMark.work(WorkState)` maps a child agent's work state; `StatusMark.askingParent()` marks a child waiting for its parent's answer (see [StatusMark](components/status/StatusMark.md)).

| Status | Role | Dot form | Pill form |
|---|---|---|---|
| `needsYou` | attention | accent dot, attention ink, bold | attention fill and hairline, attention ink |
| `running` | ink | breathing square, muted text | same |
| `failed` | danger | red dot, danger ink | `circle-x`, danger ink |
| `done` | constructive | green dot, constructive ink | `circle-check`, constructive ink |
| `idle` | muted | hollow ring, muted text | same |
| `interrupted` | muted | ring with a dot (not in the mockup) | same |

Only "needs you" fills a pill and only it is warm.

## Compacted history

`history/` draws older chat history as cards (scene H of the scratch-skin
mockup, approved 2026-10-27). The host feeds them through
`TranscriptList(entries:)` and keeps what is open in a `HistoryController`; the
widgets take plain view models and import no backend or bridge type.

| Widget | Shows |
|---|---|
| `HistoryChapterCard` | A closed chapter. Closed it reads alone: kicker (`Chapter · Oct 26 – 27 · closed`), title, summary paragraph, counts (`58 messages · 2 episodes`). Layered top edge while closed, edge colour from `colorIndex` (`outlineColor`), "Show episodes" / "Hide episodes" in the foot. A part of a split chapter is a card with the same title; only the last part has counts (`messageCount` and `episodeCount` are null on the others). |
| `HistoryCurrentChapter` | The open chapter: a plain group header (`Current chapter · since Oct 27 · 3 episodes`) over its episode cards, which are always listed. |
| `HistoryEpisodeCard` | A mono header line (`Episode · 13:41–13:56 · 38 messages`, then `N actions · N flagged · N errors` at the right, left out when compact), the title and a gist. The header opens the action log; "Show messages" opens the originals (the host's `HistoryMessagesBuilder`) and "Show action log" goes back. Log rows are verb, a chip for the target, a change marker (`+12 −3`, `created`, `failed · 2 tests`, `passed · 14`, coloured by its words) and an optional point-of-interest line. Rows past six fold behind `+N more`. An episode without actions (summarized before logs) has no counts and goes straight to the messages. |
| `HistoryLegacyCard` | A summary from before chapters and episodes: title when there is one, the summary, the times and the message count. Nothing opens. |
| `HistoryBoundary` | The hairline `Full messages from here · message N` (the number is left out when compact). |

A chapter card also shows its `decisions` (one `◆` line each, in `ink`) and `sections` (a coloured bar and a name each, colours from `outlineColor`) under the summary, and `N sections` in the counts. Both are plain fields on `HistoryChapter`, set on the last part of a split chapter only; an empty list leaves its row out, so a chapter without them looks as before. Section names and decisions are data: the card adds no label. The gallery's H scene (`HistoryScene`) shows a legacy
card, a folded chapter, an opened one with a v2 episode, a log with `+N more`
and the originals, a split chapter and the current chapter, opened on the
boundary.

## Gallery

`apps/gallery` (`flutter run -d chrome` in that folder). The toolbar switches
scene (the mockup's A workbench, C phone, D workspace and F context as
`AgentWorkbench` on the fake backend, B Scratch pane as a placeholder, G Outline
as a hand-built chat in chapters on an `OutlineController`, H Compacted history as the
cards over a boundary, plus Components, which
lists each widget in each state), light or
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
5. Add a crop of the specimen to `apps/gallery/test/component_shots_test.dart` (its type and position in the scene, see the file header), render it, and copy the PNGs to `docs/components/<folder>/shots/` as `<name>-light.png` and `<name>-dark.png`.
6. Write the widget's sheet in `docs/components/<folder>/<Widget>.md` (copy a neighbour: demo, parameters, theme roles, size classes, accessibility, gallery and tests) and add it to the index in [README.md](README.md).
7. Update the folder's `README.md` and the table above.

## Goldens and how to view the shots

Golden tests are tagged `golden`; the normal test job excludes them and the
`goldens` job runs them. They render `StatusMark` in `packages/agent_kit`
(`test/goldens/status_mark_{light,dark}.png`) and every gallery scene in
`apps/gallery` (A at 1440 and 1000, C at 390, D at 1600 and 1000, F context and
G outline at 1600 and 390, and the whole Components sheet at 1000 px, light and
dark;
`test/goldens/<scene>_<width>_<theme>.png`), with the scripted chat played to
its end. `apps/gallery/test/component_shots_test.dart` renders the Components, History and Outline scenes again and keeps one crop per widget state as `test/goldens/shots/<name>_<theme>.png`; the [component sheets](components/) show those crops. Text is real because the bundled fonts are loaded in the tests.
Rendering happens only in CI, on `ubuntu-latest` with Flutter pinned to the
version this repo's CI pins (3.47.5); goldens rendered elsewhere will not match.

- Push or pull request: the job compares with the committed PNGs and fails on
  a difference (`golden-failures` artifact holds the diffs).
- Manual run: `gh workflow run ci.yml --ref <branch>` re-renders without
  comparing.
- Either way the job uploads the PNGs as the `gallery-shots` artifact:
  `gh run download <run id> -n gallery-shots` gives `components/`,
  `scenes/` and `crops/` (the widget crops of the component sheets). Compare them with `lab/design/scratch-skin/shots/`.
- To accept new renders, download the artifact from a manual run, copy
  `components/*.png` to `packages/agent_kit/test/goldens/` and `scenes/*.png`
  to `apps/gallery/test/goldens/` (`crops/*.png` to `goldens/shots/`, and copy them to `docs/components/<folder>/shots/` as in "Adding a widget"), and commit them.
- Formatting is not run on the PC either: when the format job fails it uploads
  `format-patch`; `git apply format.patch` fixes it.
