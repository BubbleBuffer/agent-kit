# composer

The bottom of a chat.

| Widget | File | What it is |
|---|---|---|
| `AgentComposer` | `agent_composer.dart` | Multiline field ("Steer the agent…"), reference chips, model and workspace picks, the Steer/Queue switch, Stop (while running) and Send. Reports a `ComposerSubmission` (text, refs, and `send`/`steer`/`followup`). |
| `ComposerPick`, `ComposerModeToggle`, `ComposerRefChip` | `composer_pick.dart`, `agent_composer.dart` | The pick buttons, the switch and the chips, reusable on their own. |
| `MentionSource`, `StaticMentionSource` | `mention_source.dart` | What the composer asks about `@query`; the host answers with `KitRef`s. |
| `ApprovalBar` | `approval_bar.dart` | "Needs approval" pill, "waiting 12m" (from `requestedAt`, never a countdown), the action line, Review diff, Approve / For session / Deny with keys 1, 2, 3, and Deny's optional reason field. |
| `QueuedRow` | `queued_row.dart` | A dashed row for one queued message: Send now, Edit (inline field) and ×. |
| `QuestionPrompt` | `question_prompt.dart` | The agent's question with option buttons and a typed answer. Not in the mockup (see below). |
| `composer_parts.dart` | | Internal: Lucide glyphs, `KitButton`, key hints, the dashed outline, `WaitingLabel`. Only `formatWaiting` and `shortenPath` are public. |

Mockup parts: `.approval`, `.queue`, `.composer`, `.cmp-chip`, `.seg` and the
`.btn*` primitives in `app.css`; keys from SPEC.md section 10 (10, 7.8, 7.10).

## Behaviour

- Widgets take `agent_kit_core` models (`Approval`, `QueuedInput`, `Question`,
  `KitChoice`, `KitRef`) and callbacks that map to the backend commands:
  `decideApproval`, `sendQueuedNow`, `editQueued`, `removeQueued`,
  `answerQuestion`, `cancel`, and `send`/`steer`/`followup` through
  `ComposerSubmission.delivery`. Nothing here calls the backend.
- Composer keys: Enter sends (while running: steers, or queues in Queue mode),
  Ctrl/Cmd+Enter while running does the other one, Shift+Enter adds a newline.
  With mention suggestions open: up/down move, Enter or Tab picks, Esc closes.
  Esc does not stop the agent (SPEC.md does not specify it).
- Approval keys: 1, 2 and 3 fire Approve, For session and Deny while focus is
  not in a text field, while focus is inside the bar (outside its reason
  field), and while the composer is empty (`ApprovalBar.composerEmpty`).
- The composer fits its own width: below `KitLayout.fitComposer` (460) Stop and
  Send drop their labels and the workspace pick hides; the model name truncates
  first. The queued row hides "Queued" below 600 px. The approval bar lays out
  two lines at wide widths, the actions under the request when narrower and
  three equal buttons when compact. Key hints hide at the phone form factor.
- The pick menus open as `bb_ui` popovers, so a `Navigator` must sit above them
  (any `WidgetsApp` with a home or routes).

## Departures from the mockup

- The question prompt is new (same surface, pill and age line as the approval
  bar; options as buttons, one answer field).
- Pick menus use the workspace in place of the mockup's profile.
- Send is dimmed while the field is empty (SPEC.md 7.10), where the mockup
  draws it enabled.
