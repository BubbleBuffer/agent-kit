# Backend mapping

How each `agent_kit_core` event and command maps onto the two backends the
kit is built for:

- **SDK**: the BubblePaw SDK, in two layers. **Layer 1** is the headless
  `bubblepaw-sdk` (`Harness`, `Store`, `HarnessEvent` with its `EventKind`).
  **Layer 2** is its client projection behind the opt-in `client` cargo
  feature, built only on layer 1's public API: views, commands, a typed
  `Event { seq, chat, kind }` stream with snapshot-then-subscribe and resync.
  Each app's bridge crate generates Dart from layer 2.
- **Scratch**: Scratch's agent gateway, the generated `NotesAgent` bridge and
  its `AgentEvent` (wire kinds in snake case).

`agent_kit_core`'s snapshot, event and command shapes are the Dart mirror
of the layer 2 contract: layer 2 can serve them as JSON unchanged, and the
golden fixtures in `packages/agent_kit_core/test/fixtures/` (format in its
`README.md`) are meant to be replayed by layer 2 as its contract tests.
Until layer 2 exists, an adapter in Dart does the projection from layer 1.

SDK gaps are written as **layer 2 needs X, from layer 1 Y** (layer 1 has
what is needed, layer 2 must project it) or **layer 1 lacks Y** (nothing to
project yet). Scratch gaps are written as **Scratch lacks X**. A backend sets
the matching `KitCapability` off until a gap is closed; widgets hide what a
backend lacks. The kit works today with the capabilities each backend can
offer; closing a gap is the backends' own roadmap.

Checked against the SDK branch with the facade crate and Scratch's
`agent/bubblepaw-sdk` branch, 2026-10.

## Reads and sequence numbers

| Kit | SDK | Scratch |
|---|---|---|
| `listChats({cursor, query})` | Layer 2 needs a paged, filtered chat list, from layer 1 `Store::list_visible_sessions` / `session_summaries(limit)`. | `sessions()`, newest first. Scratch lacks a cursor and a query. |
| `loadChat(id)`: a snapshot at `seq` N | Layer 2 needs a snapshot with its seq, from layer 1 `Harness::snapshot_with(id, read)` (gives `LogPosition{seq, streaming_text, live_seen}`) and `Harness::pending_approvals`. `Store::snapshot` alone has a store `revision`, not an event seq. | `sessionState(id)` → `AgentSessionState` with `seq`, `liveSeen`, `streamingText`, `messages`, `runs`, `pendingApprovals`, `activity`, `edits`. |
| `events(chat, after: N)` | Layer 2 needs a per-chat resumable stream, from layer 1 `events_after(N, session_id, limit ≤ 1000)`, then `Harness::subscribe()` filtered by `session_id`; `can_resume_from(N)` false becomes `gap`. | `eventsAfter(N, sessionId)` (with `resync`) then `subscribe(sessionId)`. A `resync` or a subscribe `gap` becomes kit `gap`. |
| Durable `seq` | Layer 1 `HarnessEvent.sequence`, global per store. | `AgentEvent.sequence`. |
| Transient events carry the last durable `seq` | Layer 1 does this already (`durable: false` events). | Same (`paragraph`, nested tool events). |
| `offset` on streamed text | Layer 2 needs character offsets per item, from layer 1 `LogPosition.streaming_text` and the `Paragraph` order. | Scratch lacks offsets; the adapter counts from `streamingText`. |

## Events

| Kit event | SDK | Scratch `AgentEvent` |
|---|---|---|
| `chat.renamed` | Layer 2 needs a rename event, from layer 1 `rename_session` (layer 1 has no rename event). | Scratch lacks a rename event; the adapter emits it after `renameSession`. |
| `chat.archived` | Layer 2 needs an archive event, from layer 1 `archive_chat`. Layer 1 lacks unarchive. | Scratch lacks archive (delete only). |
| `chat.settings` | Layer 2 needs the chat's model, from layer 1 `RunStarted{model}` / `RunOptions.model`. Layer 1 lacks profiles. | `run_started.model`. Scratch lacks a profile; the model pick is client-side. |
| `chat.workspace` | Layer 2 needs the workspace, from layer 1 `session_workspace`. Layer 1 lacks branch and worktree. | `AgentSession.projectId/projectName`. Scratch lacks branch and worktree. |
| `run.started` | Layer 1 `RunStarted{model}`; `RunQuotaResumed` also maps here (same run, wait cleared). | `run_started`; `run_quota_resumed`. |
| `run.waiting` | Layer 1 `RunWaitingForQuota{wait: {resume_at, reason}}`. | `run_waiting_for_quota` with JSON only; Scratch lacks quota fields. |
| `run.finished` | Layer 1 `RunFinished{status, error}`: `completed`, `failed`, `cancelled`, `interrupted`. | `run_finished{status, error}`. |
| `message.user` | Layer 2 needs a user-message event, from layer 1's stored messages on `RunStarted` / `SteeringAccepted{text}`. | Scratch lacks it; reload after `run_started` / `steering_accepted`. |
| `message.delta` (transient) | Layer 1 `Paragraph{text}` (what `streaming_text` holds) or `TextDelta`. | `paragraph`. |
| `message.assistant` | Layer 2 needs a message-completed event, from layer 1 `RunFinished.text` or the stored assistant message on `SessionSettled`. | Scratch lacks it; `run_finished.text` or reload. |
| `message.system` | Layer 1 `Output{record}` for host lines. | `output` (JSON only). |
| `message.notice` | none: the client emits notices for its own state (reconnected, compacted). | none. |
| `thinking.started` / `.delta` / `.finished` | Layer 1 lacks reasoning text. Layer 2 could open a textless thinking row from layer 1 `ModelRequestStarted`. | Scratch lacks reasoning text. |
| `tool.started` | Layer 1 `ToolStarted{call: {id, name, arguments}}`. Layer 2 needs tool kind and target, from layer 1 `ToolDefinition` and the arguments. | `tool_started{toolCall}`. |
| `tool.output` (transient) | Layer 1 lacks tool output streaming. | Scratch lacks it. |
| `tool.finished` | Layer 1 `ToolFinished{call_id, result: {content, is_error}}`. Layer 1 lacks an exit code and output size. | `tool_finished{callId, result, isError}`; `AgentToolActivity.summary` gives `meta`. |
| `edit.applied` | Layer 2 needs edit items with diffs, from layer 1 `edit`/`write` tool arguments and results. | `AgentSessionState.edits` (`AgentEdit` with hunks, `added`, `removed`, `undoable`), read on reload. Scratch lacks an edit event. |
| `edit.undone` | Layer 1 lacks edit undo. | `AgentEdit.undone` after `editUndo`; no event. |
| `plan.updated` | Layer 2 needs a plan, from layer 1's todo tool, which arrives as `HostStateChanged{key, value}` (on a branch, not merged yet). | Scratch lacks a plan. |
| `approval.requested` | Layer 1 `ApprovalRequested{approval}`. Layer 2 needs the diff, from the approval's arguments. | `approval_requested{approval}`. |
| `approval.resolved` | Layer 1 `ApprovalResolved{approval_id, state, reason}`; `approved_session` → `approvedForSession`. | `approval_resolved{approvalId, approvalState, reason}`. |
| Restart expiry | Layer 1 marks pending approvals `expired` (reason `restart`) and runs `interrupted` in `recover()` with no event. Layer 2 needs a `gap` (or the events) after recovery, from layer 1's recovery result. | Same, through the host. |
| `question.asked` / `.resolved` | Layer 1 lacks questions (they are host-level in the runner); BubblePaw has no question tool yet. | Scratch lacks questions. |
| `queue.added` | Layer 1 `FollowupQueued{text}`, `SteeringAccepted{text}`. Layer 2 needs the input id, from layer 1 `Store::queued_inputs`. Steering an idle session queues with no event in layer 1. | `followup_queued{text}`; Scratch lacks the input id. |
| `queue.edited` / `.removed` | Layer 1 lacks queue edit and remove. | Scratch lacks them. |
| `child.spawned` / `.progress` / `.finished` | Layer 2 needs child events, from layer 1 child sessions (`parent_session_id`) and their events, which share the store sequence. | Scratch lacks children. |
| `job.started` / `.output` / `.exited` | Layer 2 needs job events, from layer 1 `ProcessTools::jobs(owner)` (untyped JSON: `handle`, `command`, `status`, `exitCode`). Layer 1 lacks job output streaming. | Scratch lacks jobs. |
| `context.changed` | Layer 2 needs a context view, from the LCM store (`BubblePaw-base/docs/lcm-contract.md`): the serving view's blocks, chapters, episodes and summaries. Fields the store does not record yet stay null: the compaction trigger, `inputBefore` / `inputAfter`, per-block and per-message tokens. | Scratch lacks context data. |
| `compaction.updated` | Layer 2 needs a marker per compaction, from the LCM compaction events (gather, then apply). | none. |
| `interrupted.added` | Layer 2 needs it after `recover()`, from the interrupted run's record (reason optional). | none. |
| `child.question.asked` / `.resolved` | Layer 2 needs it, from a child session's `waiting_for_answer` state and its `tools.question` call, which goes to the parent session. | Scratch lacks children. |
| `usage.updated` | Layer 2 needs a context meter, from layer 1 `RunFinished.usage` and host state `usage.last_request`. Layer 1 lacks the context limit per chat. | Token counts per run. Scratch lacks a context meter. |
| `gap` | Layer 1 `can_resume_from` false, or a lagged broadcast receiver. | `gap{skipped}`, or `eventsAfter` with `resync`. |
| (ignored) | `HostStateChanged` (other keys), `SessionSettled` (a read trigger), `ModelRequestStarted`. | `host_state_changed`, `session_settled`, `ui_action` (Scratch's page actions). |

## Commands

| Kit command | SDK | Scratch |
|---|---|---|
| `createChat` | Layer 1 `Store::create_session(title)` / `create_session_with_workspace`. | `createSession(title)`. |
| `send` | Layer 2 needs send-or-queue, from layer 1 `Harness::start(id, text, RunOptions)`, then `followup` on `SessionBusy`. | `send(id, text, model?, context?)` → `AgentSent{started, run, inputId}`; queues when busy. |
| `steer` | Layer 1 `Harness::steer(id, text)` → `QueuedInput`. | `steer(id, text)` (unused by Scratch's own UI). |
| `followup` | Layer 1 `Harness::followup(id, text)`. | Scratch lacks an explicit follow-up; `send` while busy queues one. |
| `sendQueuedNow` | Layer 1 lacks it. | Scratch lacks it. |
| `editQueued` / `removeQueued` | Layer 1 lacks them. | Scratch lacks them. |
| `cancel` | Layer 1 `Harness::cancel(id)` (also ends quota waits). | `cancel(id)`. |
| `resume` | Layer 1 `Harness::resume(id, RunOptions)`. | Scratch lacks resume. |
| `decideApproval` | Layer 1 `Harness::decide(approval_id, Decision::Approve / ApproveForSession / Deny{reason})`; deciding twice errors → `KitConflict`. | `decideApproval(approvalId, approve / approve_session / deny, reason?)`. |
| `answerQuestion` | Layer 1 lacks it. | Scratch lacks it. |
| `answerChildQuestion` | Needs engine support: the parent answers through its own tool call today; the user answering in its place has no entry point. Capability off until then. | Scratch lacks children. |
| `rename` | Layer 1 `Store::rename_session(id, title)`. | `renameSession(id, title)`. |
| `archive` | Layer 1 `Store::archive_chat(id)`; layer 1 lacks unarchive. | Scratch lacks archive. |
| `fork` | Layer 2 needs fork as a command, from layer 1 `Store::fork_at(id, message_id, title)`. | Scratch lacks fork. |
| `rewind` | Layer 1 lacks rewind (the runner has it). | Scratch lacks rewind. |
| `cancelChild` | Layer 2 needs it, from layer 1 `Harness::cancel(child_session_id)`. | Scratch lacks children. |
| `cancelJob` | Layer 1 lacks cancelling one job (`ProcessTools::cancel_owner` cancels all of an owner's). | Scratch lacks jobs. |
| `undoEdit` | Layer 1 lacks edit undo. | `editUndo`. |
| `loadContext` / `loadHistoryRange` / `loadSummary` | Layer 2 needs them, from the LCM store (`lcm-contract.md`): chapters, episodes, summaries and events; a message range of the original history; one summary's full text. | Scratch lacks them. |
| `listModels` / `setModel` | Layer 2 needs a stored chat model, from layer 1 `RunOptions.model` and the provider resolver. | `models()`; the choice is passed to `send`. |
| `listProfiles` / `setProfile` | Layer 1 lacks profiles. | Scratch lacks profiles. |

## Errors

Layer 1 reports anyhow errors (typed only for `SessionBusy`); Scratch reports
strings (codes exist on its JSON-RPC wire only). Layer 2 needs typed errors
with display-safe messages, from layer 1's error chain:

| Kit error | SDK layer 1 | Scratch |
|---|---|---|
| `KitBusy` | `SessionBusy` (e.g. delete during a run). | "refused during a run" from `deleteSession`. |
| `KitConflict` | `decide` on a decided approval. | same. |
| `KitUnavailable` | host not reachable. | "hub unreachable". |
| `KitNotFound` | unknown session or approval id. | same. |
| `KitFailed` | anything else, with a generic message; the original goes to the log. | same. |

## Question requests from other agents

A `Question` is a request of 1 to 5 `QuestionItem`s (see
`agent-kit-core.md`). The agents whose questions a host may relay map onto it
like this. BubblePaw has no question tool yet, so the SDK and Scratch columns
above stay "lacks it".

| Kit | Claude Code `AskUserQuestion` | Codex `request_user_input` |
|---|---|---|
| The request | One call of 1 to 4 questions: a `Question` with that many items. | One call of one or more questions: a `Question`, split by the host when over 5. |
| `QuestionItem.header` | The question's short `header`. | The question's `header`. |
| `QuestionItem.text` | `question`. | `question`. |
| `QuestionItem.kind` | `multiSelect: false` is `pickOne`, `multiSelect: true` is `pickAny`. | `pickOne` when it has options, `text` when it has none. Codex has no multi-select. |
| `QuestionOption` | `options[].label` and `description`. | `options[].label` and `description`. |
| `QuestionItem.allowOther` | `true`: the tool always adds an implicit "Other" the user may type into. | The question's `isOther`. |
| `answerQuestion` | Each item's answer is its `choices` (labels) and, for Other, `text`; a `pickAny` joins several labels. A skipped item has no answer in the tool result. | `choices.first`, or `text` for Other or a text question; a skipped item is left out of the answers. |

Hosts must split anything over 5 questions into several requests (the kit
holds at most `maxQuestionItems`, so a card stays one screen). Each request is
answered, or its items skipped, before the next is shown.

## Context and child questions

Both come with their own capability (`context`, `answerChildQuestion`);
widgets hide what the backend lacks.

- **BubblePaw** maps a child's `waiting_for_answer` state and its
  `tools.question` call onto `ChildQuestion`; the question goes to the parent
  agent. Its context data comes from the LCM store
  (`BubblePaw-base/docs/lcm-contract.md`). It does not record yet: the
  compaction trigger (`ContextEvent.trigger`, `triggerText`), the input size
  before and after a compaction (`inputBefore`, `inputAfter`) and per-block
  and per-message tokens, so those fields are null and the widgets hide them.
  `answerChildQuestion` needs engine support and stays off until it exists.
- **Claude Code and Codex** lack all of this: no serving view, no episodes or
  chapters, no child questions. Their chats have `context == null`, and the
  Context pane and the child-question controls do not appear.
- The `applied` event names one `summaryId`; the mockup's text "became
  Chapter 1 and Episode 3" cannot be derived from it exactly, so the widgets
  show "Replaced 3 episodes (E1-E3), messages 1-96" built from the event's
  range.

## Settled decisions under strain

- **Approvals never expire.** The kit has no deadline field. Layer 1 can time
  an approval out (`ApprovalResolved` with `expired`); the kit shows that like
  any resolution. Keeping approvals open until answered is a host setting,
  not something the kit can enforce.
- **Restart expiry and interrupted runs** reach the client only through a
  reload, because neither backend emits events for them.

## Top gaps

1. Neither backend has queue edit, remove or send-now.
2. Layer 1 lacks questions, reasoning text and job output; layer 2 needs
   child, job and plan events, from layer 1 child sessions, `ProcessTools`
   and the todo host state. Scratch lacks all of them.
3. Layer 2 needs user-message and message-completed events, from layer 1's
   stored messages on `RunStarted` / `RunFinished` / `SessionSettled`.
4. Layer 1 lacks a tool exit code and streamed tool output; so does Scratch.
5. Layer 1 lacks branch, worktree and profile; Scratch also lacks a context
   meter.
