# transcript

Everything drawn inside the transcript sheet. Input is `ChatSnapshot.items`
(and `ChatSnapshot.plan`) from `agent_kit_core`; widgets take those models and
callbacks, never a backend.

| File | Widgets | Mockup |
|---|---|---|
| `transcript_list.dart` | `TranscriptList`, `TranscriptController`, `TranscriptAnchor`, `JumpToLatestButton` | `.transcript`, `.scroll` |
| `transcript_item.dart` | `TranscriptItemView` (dispatch on the item), `TranscriptActions` (the host's callbacks and markdown renderer) | |
| `messages.dart` | `UserBubble`, `AssistantProse`, `SystemLineView`, `NoticeLineView` | `.turn-user`, `.bubble`, `.prose` |
| `markdown.dart`, `code_block.dart` | `MarkdownRenderer` (interface), `LeanMarkdownRenderer` (default), `MarkdownText`, `CodeBlock` | `.prose`, `pre.code` |
| `activity_group.dart` | `ActivityGroupView`, `EvidenceRow`, `activitySummary`, `ActivitySummaryBuilder` | `.activity`, `.ev-*` |
| `exec_output.dart` | `ExecOutput` (12-line clamp with fade, footer, callbacks) | `pre.out`, `.ev-foot` |
| `file_edit_row.dart`, `diff_view.dart` | `FileEditRow`, `DiffView` | `.edit-row`, `.diff`, `.fl` (Scene D) |
| `plan_checklist.dart` | `PlanChecklist` | `.plan` |
| `child_question_row.dart` | `ChildQuestionRow` (pending, answered by the agent or you, cancelled; Open child, Answer yourself) | `.cq-*` (scene A) |
| `return_line.dart` | `ReturnLine`, `InterruptedNotice` | `.return-line` |
| `transcript_support.dart` | internal: glyphs, `KitTextButton`, formatting | |

## Behaviour

- **Follow tail.** The list stays pinned to the bottom while content arrives
  (new items, streaming text, a row expanding) until the user scrolls up;
  then "Jump to latest" shows, and pressing it (or `controller.jumpToLatest`)
  follows again. Within `followThreshold` (24 px) of the bottom counts as
  at the bottom.
- **Anchor restore.** `controller.anchor` is the first visible item's id and
  how many px of it are above the top edge; pass it back as
  `TranscriptList.initialAnchor` (or `controller.restore`) to reopen there.
- **One evidence row open at a time** in an activity group. An exec row opens
  into its output, a thinking row into its reasoning text (only when the
  backend sent it), a spawn row calls `onOpenChild`.
- **Host hooks.** `ActivityGroupView.footer` (`TranscriptActions.activityFooter`) sits under
  an open group; `FileEdit.label` replaces the row's wording; `openEveryEdit`
  shows Open on every edit; an undo callback that throws `UndoRefused(message)`
  shows the message under the row.
- **The summary line is verb counts** ("Searched 2× · Read 3 files · Ran 1
  command · 1 failed", by `ToolKind`). "Worked 48s" and "thought 6s" are
  appended only when the backend sent durations. A host replaces the line with
  `summaryOf` (`ActivityGroupView`, or `TranscriptActions`).
- **Layout by `SizeClass`** of the list's own width: item gaps 28 (22
  compact), evidence indent 58 (0 compact), edit rows drop the verb when
  compact.
- Expansion state lives in each row's `State`, keyed by item id, so it
  survives rebuilds but not scrolling the row far off screen.
- Hosts compose the plan (`PlanChecklist(snapshot.plan)`) and the interrupted
  notice (`InterruptedNotice`, from `RunInfo.outcome`) through
  `TranscriptList.leading` / `trailing`.
- A control whose callback is missing is not drawn.

Add a widget here as its own file, export it from `transcript.dart`, and add
a gallery specimen (`apps/gallery/lib/components/transcript.dart`) and a golden
(see `docs/agent-kit.md`).

## Plan and inserts

`TranscriptList.plan` draws the snapshot plan as the first row (the `leading` slot stays for notices). `inserts` places extra rows (the resolved-question answer lines) after a given item id; unknown ids go to the end.
