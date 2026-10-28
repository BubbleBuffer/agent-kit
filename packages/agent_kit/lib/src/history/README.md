# history

Compacted history: older chat history shown as closed-chapter, episode and
legacy cards above a "Full messages from here" hairline, with the live end of
the chat below it in full. The look is scene H of the scratch-skin mockup
(approved 2026-10-27). Widgets take plain view models and a `HistoryController`;
no backend or bridge type is imported, so a host maps its own data.

| File | Holds |
|---|---|
| `history_model.dart` | `HistoryChapter`, `HistoryEpisode`, `HistoryAction`, `HistoryPoint`, `HistoryLegacy` (plain immutable view models) and the date, clock and marker-tone helpers |
| `history_controller.dart` | `HistoryController`: which chapters are open, each episode's view (closed, log, messages) and which logs show all rows; owned by the host so it outlives lazily built rows |
| `history_cards.dart` | `HistoryChapterCard`, `HistoryCurrentChapter`, `HistoryEpisodeCard`, `HistoryLegacyCard`, `HistoryBoundary` |

Not modelled, because the store has none yet: a chapter's decisions and
sections. Add them as plain fields on `HistoryChapter` when they exist.
