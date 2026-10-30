# AgentChatPane

One chat on an `AgentBackend`, with its header, crew strip, transcript and dock (approvals, question, queued inputs, error line, composer), where `AgentWorkbench` puts one in its sheet.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/agent_chat_pane_390-dark.png">
  <img alt="Workbench at phone width (390 px): a menu button at top left, crew chips under the header, the transcript, the approval bar, the queued row and the composer" src="shots/agent_chat_pane_390-light.png">
</picture>

*Phone (scene C at 390 px). The shot shows the whole workbench at phone width, not the pane alone. The rail is behind the "Sessions" menu button at top left. The chat pane is the sheet: the crew strip under the header, the transcript, then the dock with the approval bar, the queued row and the composer. The gallery builds it with `AgentWorkbench`.*

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `backend` | `AgentBackend` | required. Where the chat lives. |
| `chatId` | `String` | required. The chat to show. Changing it closes the old feed, opens the next, and clears the composer's draft. |
| `now` | `DateTime?` | Replaces the wall clock for ages (tests, the gallery). |
| `showCrewStrip` | `bool` | Default `true`. Shows the crew strip under the header when the chat has child agents or jobs. |
| `sideBuilder` | `Widget? Function(BuildContext, ChatSnapshot)?` | The column beside the transcript at the expanded size (the crew ledger). Null, or a builder that returns null, means no column. |
| `workspaceShown` | `bool` | Default `false`. The state of the header's workspace toggle. |
| `onToggleWorkspace` | `VoidCallback?` | Called by the header's workspace button. Null leaves the button out. |
| `onSnapshot` | `ValueChanged<ChatSnapshot>?` | Called with each new snapshot, for a host that mirrors the chat. |
| `onOpenChat` | `ValueChanged<String>?` | A fork was made: open this chat. |
| `onChatsChanged` | `VoidCallback?` | The chat list may have changed (the chat was archived). |
| `statusDetail` | `String? Function(ChatSnapshot)?` | The text after the status pill's label. By default, "edit approval" for a pending approval and "N agents" for a run with child agents. |
| `transcriptActions` | `TranscriptActions` | Default `TranscriptActions()`. What the transcript's rows open. The pane adds Undo itself when the backend has `editUndo`. |
| `mentions` | `MentionSource?` | Where `@` mentions in the composer come from. |
| `onReviewApproval` | `ValueChanged<Approval>?` | "Review diff" on an approval. |
| `onOpenAgent` | `ValueChanged<ChildAgent>?` | A crew strip chip was opened. |
| `onOpenJob` | `ValueChanged<BackgroundJob>?` | A background job in the crew was opened. |
| `onOpenContext` | `VoidCallback?` | Opens the Context pane on Now. The header's context meter and the compaction marker's View call it. Null leaves them inert: the meter is then a plain readout. |
| `contentWidth` | `double` | Default `720`. The width of the transcript's content column. |
| `turnLayout` | `TurnLayout` | Default `TurnLayout.chronological`. How a turn's items are ordered. |
| `paneActions` | `AgentPaneActions?` | Named parameter, optional. Overrides which of send, stop and approval decisions work. Without it, they follow the backend's `send`, `cancel` and `approve` capabilities. |

`AgentPaneActions(send, stop, decide)` takes three booleans, each default `true`. `AgentPaneActions.all` turns all three on whatever the backend reports. `AgentPaneActions.readOnly` turns all three off: the messages and approvals still show, and the controls stay drawn but disabled. Answering a question, the queue, undo, resume, fork, archive and the model and profile picks still follow the capabilities alone.

## Theme roles

`BbTheme` roles read in `agent_chat_pane.dart`, including its private `_ErrorLine`:

- `typeScale.ui` and `typeScale.uiSmall`: the text sizes of the loading and failure states and the error line.
- `faint`: "Loading…" (`:480`).
- `ink`: the failed-load title "Couldn’t load this chat" (`:491`).
- `muted`: the failure message under it (`:497`).
- `dangerInk`: the error line's text (`:772`).
- `radii.field` and `colors.borderStrong`: the error line's box (`:759-760`). `colors` is bb-ui's `AppColors`.

## Size classes

The pane does not read `SizeClass`. It measures its own width with a `LayoutBuilder` (`_grid`, `agent_chat_pane.dart:510`).

- With a `sideBuilder` that returns a column, the grid is: a left gutter, the content column, 40 px, then a 252 px side column. The gutter takes two thirds of the free width and is at least 16 px.
- The side column is left out when the width is unbounded or when the room for the content would be under 160 px. The room is `width − 3 × 40 − 252 − 16` (`:519-521`).
- The content column is `min(contentWidth, room)`, capped at `contentWidth + 32` with 16 px padding on each side (`:523`, `:590`).
- Without a side column, the transcript column is `contentWidth` wide (720 px by default), centred.

## Accessibility

- The "Loading the chat" text is a live region with that label (`agent_chat_pane.dart:478-479`). A load failure is a live region holding the message and a Retry button (`:483-500`).
- The error line is a live region whose label is the message, with a "Dismiss" button (`:755`, `:779`).
- Send, Stop and the approval decisions are drawn disabled when the pane's actions turn them off. They cannot be invoked by tap, key or semantics action (the pane's doc comment). The test "semantics call the controls disabled" checks the semantics.
- Approval keys: with the approval bar on screen, the keys 1, 2 and 3 (no modifier) approve, approve for session, and open Deny (`composer/approval_bar.dart:128-150`). With several panes on screen, the keys go to the bar of the focused pane, or the pane focused last. Each pane is wrapped in `ApprovalKeyPane` (`agent_chat_pane.dart:415`; `approval_bar.dart:681-683`). Escape on the deny step goes back (`approval_bar.dart:298`).

## Gallery and tests

- Gallery scene: none of its own. Scene B ("Scratch pane") is named for `AgentChatPane` in `apps/gallery/lib/src/scenes.dart:21-31`, but `buildScene` returns a placeholder for it (`:124-125`). The pane is seen in scenes A, C and F through `AgentWorkbench` (`scenes.dart:127-151`).
- Golden: the shot is a copy of `apps/gallery/test/goldens/c_phone_390_light.png` (and `_dark.png`). `apps/gallery/test/scenes_golden_test.dart` writes it (scene phone at 390 × 844), not `component_shots_test.dart`. The copies are byte-identical to the scene goldens.
- Other tests:
  - `packages/agent_kit/test/compositions/agent_chat_pane_test.dart`: each command reaches the backend (approve, deny with reason, steer or queue, stop, edit and remove a queued input, send now, answer a question, resume and fork); capabilities hide controls; `paneActions` overrides; a failed command shows one dismissible line; a failed send gives the text back; the load failure offers Retry; read-only semantics; a chat switch closes the old feed.
  - `packages/agent_kit/test/transcript/child_question_test.dart`: mounts `AgentChatPane` for child-agent questions.
  - `packages/agent_kit/test/compositions/agent_workbench_test.dart`: mounts the pane through the workbench.
- No package golden covers the pane.
