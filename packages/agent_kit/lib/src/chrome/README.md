# chrome

The frame around a chat: the rail (workspace header, search, grouped session
rows with status meta, settings), the chat header (title, status pill, branch,
context meter, menu), the crew strip (child agents and jobs as chips) and the
"Still running" ledger.

Mockup parts: `.rail*`, `.rr-*`, `.hdr`, `.cs-*`, `.lg-*` in `app.css`.
Status always goes through `StatusMark`. The rail follows the theme (see
`BbTheme.rail*`). Input is `ChatSummary`, `ChatSnapshot.children` and
`jobs`.

| File | Widgets |
|---|---|
| `session_rail.dart` | `SessionRail` (project switcher with new chat and hide, search with the Ctrl K hint, grouped rows, settings footer with the avatar), `SessionRow` |
| `rail_layout.dart` | `RailLayout` (the rail beside the content, or sliding over it when compact; Ctrl+B), `RailShowButton` (the header's way back) |
| `rail_model.dart` | `RailController` (`hidden` above compact, `open` when compact), `RailScope`, `SessionGroup` |
| `chat_header.dart` | `ChatHeader` (tile, title, `StatusMark` pill, branch, workspace toggle, session menu), `ContextMeter` (a button when `onOpenContext` is set), `ChromeMenuItem` |
| `crew_strip.dart` | `CrewStrip`: chips for agents and jobs, scrolling sideways; a child waiting for its parent reads `asking parent` |
| `crew_ledger.dart` | `CrewLedger`: the "Still running" column |
| `usage_view.dart` | `UsageByModel` and `ModelUsage`: tokens by model |
| `chrome_format.dart` | `groupSessions`, `railDetail`, `chatAge`, `formatElapsed`, `formatTokens` |

Not in the barrel: `chrome_icons.dart` (the Lucide glyphs bb_ui's `Ico` lacks),
`chrome_button.dart` and `crew_text.dart`.

## How the pieces fit

- `RailLayout(controller:, rail: SessionRail(...), child: ...)` measures its own
  width. Above compact the rail is a 240 px column that folds to 0 and slides
  out (`controller.hidden`); compact shows the content full width with the rail
  as a sliding screen over it (`controller.open`). Both animate with the
  `sheet` motion token, and not at all when the platform reduces motion.
- Inside the layout, the rail's hide button and `RailShowButton` use the
  `RailScope`. `ChatHeader` includes a `RailShowButton`: the menu button in
  compact, `panel-left-open` when the column is hidden, nothing otherwise.
- `ChatHeader` drops the tile, the branch and the meter's label when its own
  width is below the compact threshold; the title and branch truncate first.
- `CrewStrip` is the medium/compact form of `CrewLedger`; the composition picks
  one by `SizeClass`.
- Per-model usage is not in `agent_kit_core` (`Usage` is per chat), so
  `UsageByModel` takes `ModelUsage` values from the host.
