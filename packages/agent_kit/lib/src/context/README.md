# context

What the agent remembers and what was compacted (scene F of the mockup, with
the compaction marker of scene A). Input is `ChatSnapshot.context`
(`ContextView`), the structure behind it (`ContextDetails`) and the two
loaders the host answers from `loadHistoryRange` and `loadSummary`. Widgets
take models and callbacks, never a backend; `AgentContextPane` in
`compositions/` is the one that loads them.

Mockup parts: "Context view (scene F)" in `NOTES.md`; `.ctx-*`, `.mk` and
`.evt` in `app.css`. Colours are `BbTheme.ctxOpening`, `ctxSummary` and
`ctxLive`; nothing else is hard-coded.

| File | Widgets |
|---|---|
| `context_pane.dart` | `ContextPane` (meter, Now / History / Compactions tabs, detail), `ContextPaneController` (`showNow({summaryId})`), `ContextTab`, `SummaryLoader` |
| `context_meter_bar.dart` | `ContextMeterBar` (opening, memory and live segments, the apply cap), `contextSegments` |
| `compaction_marker.dart` | `CompactionMarker` (running, done, failed; View) |
| `context_now.dart`, `context_history.dart`, `context_timeline.dart` | internal: the three tabs and `ContextDetail` |
| `context_parts.dart`, `context_support.dart` | internal: flash, tags, groups, notes, formatting (`ctxTokens`, `ctxLimit`) |

## Behaviour

- **Tabs** are a roving tab stop: Left, Right, Home and End move and select.
- **Detail.** From `KitLayout.contextSplit` (680 px) the summary detail sits
  beside the list; narrower it replaces the list behind a back button, and
  Esc goes back.
- **Links.** A timeline event opens its summary on Now; a summary opens the
  original messages on History. The target flashes (not under reduced
  motion).
- **History** is windowed: each episode asks the loader for its first two
  messages and its last one, so a long chat loads nothing it does not show.
- **Optional fields** (block sizes, model, times) are left out when null.
- **Not exported:** the tab files and `context_parts.dart`.
