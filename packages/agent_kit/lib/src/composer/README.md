# composer

The bottom of a chat.

| Widget | File | What it is |
|---|---|---|
| `AgentComposer` | `agent_composer.dart` | Multiline field ("Steer the agent…"), reference chips, model and workspace picks, the Steer/Queue switch, Stop (while running) and Send. Reports a `ComposerSubmission` (text, refs, and `send`/`steer`/`followup`). |
| `ComposerPick`, `ComposerModeToggle`, `ComposerRefChip` | `composer_pick.dart`, `agent_composer.dart` | The pick buttons, the switch and the chips, reusable on their own. |
| `MentionSource`, `StaticMentionSource` | `mention_source.dart` | What the composer asks about `@query`; the host answers with `KitRef`s. |
| `ApprovalBar` | `approval_bar.dart` | "Needs approval" pill, "waiting 12m" (from `requestedAt`, never a countdown), the action line, Review diff, Approve / For session / Deny with keys 1, 2, 3, and Deny's optional reason field. |
| `QueuedRow` | `queued_row.dart` | A dashed row for one queued message: Send now, Edit (inline field) and ×. |
| `QuestionPrompt` | `question_prompt.dart` | A request of 1 to 5 questions (pick one, pick any, text only; scene E): vertical option rows with number keys, the Other row, tabs and "N of M" for several, Skip, Back, Next and Answer. Reports `Map<String, QuestionAnswer>`. |
| `QuestionAnswerLines` | `question_answered.dart` | An answered request, one transcript line per question: the question muted, the answer bold or "Skipped" in italics. The transcript folder has no question row, so it lives here. |
| `composer_parts.dart` | | Internal: Lucide glyphs, `KitButton`, key hints, the dashed outline, `WaitingLabel`. Only `formatWaiting` and `shortenPath` are public. |

Mockup parts: `.approval`, `.queue`, `.composer`, `.cmp-chip`, `.seg` and the
`.btn*` primitives in `app.css`; keys from SPEC.md section 10 (10, 7.8, 7.10).

## Behaviour

- Widgets take `agent_kit_core` models (`Approval`, `QueuedInput`, `Question`,
  `KitChoice`, `KitRef`) and callbacks that map to the backend commands:
  `decideApproval`, `sendQueuedNow`, `editQueued`, `removeQueued`,
  `answerQuestion`, `cancel`, and `send`/`steer`/`followup` through
  `ComposerSubmission.delivery`. Nothing here calls the backend.
- Submit result: `AgentComposer.onSubmit` may return a future. The composer
  clears its text and picked mentions only when the result is anything but
  `false` and the field still holds what was sent; `false` or a thrown error
  keeps text, mentions and `refs`. Send does nothing while a future is pending.
  `AgentChatPane` returns whether the backend command worked, so a failed send
  keeps the draft.
- Undo: `FileEditRow.onUndo` (and `TranscriptActions.onUndo`) may return a
  future; the row reads "Undoing…" until it completes and "Undo failed" if it
  throws.
- Approval details: when an `Approval` carries `arguments`, the bar shows a
  "Details" button that opens them (JSON indented) under the action line; the
  tool and its target stay on one line with a tooltip.
- Several chat panes on screen: wrap each in `ApprovalKeyPane` (`AgentChatPane`
  does). 1, 2 and 3 then go only to the bar of the focused pane, else the pane
  focused last, never to two bars.
- Composer keys: Enter sends (while running: steers, or queues in Queue mode),
  Ctrl/Cmd+Enter while running does the other one, Shift+Enter adds a newline.
  With mention suggestions open: up/down move, Enter or Tab picks, Esc closes.
  Esc does not stop the agent (SPEC.md does not specify it).
- Approval keys: 1, 2 and 3 fire Approve, For session and Deny while focus is
  not in a text field, while focus is inside the bar (outside its reason
  field), and while the composer is empty (`ApprovalBar.composerEmpty`).
- Question keys: 1 to 9 select or toggle the current question's options (the
  Other number focuses its field); Enter sends, or moves to Next; Shift+Enter
  is a newline in a text answer. Digits act under the same focus rules as the
  approval bar (`QuestionPrompt.composerEmpty`, `captureKeys`). Tab order: the
  tabs, the options, Other, Skip, Back, Next/Answer; Space toggles a focused
  row, Up and Down move between rows. Number keys hide on a phone-sized
  window or in a compact (< 600 px) card.
- A pick-one question needs a choice, and a text question needs text, before
  Next or Answer enables; Skip declines the question instead. A pick-any
  question may be answered with nothing ticked. Answer on the last step
  returns to a question left open before it sends.
- The composer fits its own width: below `KitLayout.fitComposer` (460) Stop and
  Send drop their labels and the workspace pick hides; the model name truncates
  first. The queued row hides "Queued" below 600 px. The approval bar lays out
  two lines at wide widths, the actions under the request when narrower and
  three equal buttons when compact. Key hints hide at the phone form factor.
- The pick menus open as `bb_ui` popovers, so a `Navigator` must sit above them
  (any `WidgetsApp` with a home or routes).

## Departures from the mockup

- No theme role for the mockup's `--selected`: selected rows and tabs use
  `colors.bgSelectedBlock`, and the quiet outlines `colors.borderSubtle` and
  `colors.borderStrong`, as the queued row and the composer already do.
- The prompt keeps focus in the card after a number key or a step change
  (the card's own focus node, outside the tab order), so Enter right after
  reaches the card rather than the composer. The mockup does not say.
- Pick menus use the workspace in place of the mockup's profile.
- Send is dimmed while the field is empty (SPEC.md 7.10), where the mockup
  draws it enabled.

## Hiding what a backend lacks

`QueuedRow.hideUnavailable` omits the actions whose callback is null; `AgentComposer.showModelPick` and `showModeToggle` hide those controls. `ChatHeader.hideEmptyMenu` drops the menu button with no items. `AgentChatPane` sets them from `KitCapabilities`. The approval bar follows its own width: actions sit beside the request when there is room, else under it.
