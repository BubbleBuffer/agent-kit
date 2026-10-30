# Backend mapping

The kit's backend port is implemented by adapters. BubblePaw is the public
[BubblePaw-Core v0.3.0](https://github.com/BubbleBuffer/BubblePaw-Core/tree/v0.3.0) (plus the v0.3.1 methods listed below, written against `origin/release`)
runner over **stdio JSON-RPC 0.1**, through `agent_kit_bubblepaw`. There is no
`client` Cargo feature or pre-existing layer that emits kit-shaped JSON.
Scratch is the separate `NotesAgent` bridge; its column below preserves the
existing bridge mapping and has not been requalified against a new release.

BubblePaw calls and fields were checked against the tagged source:

- [`main.rs` stdio dispatcher](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/crates/bubblepaw-runner/src/main.rs)
- [`stdio_context.rs`](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/crates/bubblepaw-runner/src/stdio_context.rs), [`context_reads.rs`](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/crates/bubblepaw-runner/src/context_reads.rs) and [`question_stdio.rs`](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/crates/bubblepaw-runner/src/question_stdio.rs)
- [Session API](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/docs/session-api.md), [context compaction](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/docs/context-compaction.md) and [child sessions](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.3.0/docs/child-sessions.md)

A method available through HTTP, core Rust or a model-facing JS tool is not
necessarily a stdio RPC. The stdio mapping below is deliberately transport-specific.
Missing capabilities are off: commands requiring them fail with `KitUnsupported`.
Pane send, cancel and approval controls default to the corresponding
capabilities. See the
[adapter README](../packages/agent_kit_bubblepaw/README.md) for lifecycle, errors,
verification levels and the complete list of desired port changes.

## Capabilities and constraints

`ChatReader` is the read-only port used by `ChatFeed`; `AgentBackend` also
provides commands. A reader declares its capabilities. A backend can expose
`BackendConstraints` for finer input limits; the default accepts references,
all question answer shapes and follow-ups while running.

| Capability | BubblePaw | Scratch read-only adapter |
|---|---|---|
| `createChat`, `send`, `cancel` | Yes | No |
| `approve` | When `approvals` is negotiated | No |
| `steer`, `questions`, `plan`, `rewind` | When the respective protocol feature is negotiated | No |
| `context` | When feature `context` is negotiated | No |
| `answerChildQuestion` | When feature `question.answer_child` is negotiated | No |
| `rename`, `resume`, `usage` | Yes | No |
| Other optional capabilities (jobs, archive, fork) | Not advertised | No |

BubblePaw rejects references, supports a single choice or free-text question
answer, and supports follow-up while running when `follow_up` is negotiated.
Scratch's adapter declares no write capabilities. The Scratch command column
below describes gateway operations, not permissions granted by that adapter.

## Reads and sequence numbers

| Kit | BubblePaw stdio | Scratch |
|---|---|---|
| `listChats({cursor, query})` | **Partial:** `session.list`. With feature `session.list.pagination` (Core v0.3.1) it sends `limit` 100 and the previous `next_cursor`, and the host orders pages (newest created first); without it, every chat comes back at once, sorted by updated time, with no cursor. The title query filters the returned page only. Its metadata has no run status. | `sessions()`, newest first; no cursor or query. |
| `loadChat(id)` | **Yes:** `session.state` plus `approval.list` for pending approvals. Snapshot has `seq`, canonical messages, runs, inputs, outputs, todo, question and usage. | `sessionState(id)` with seq, streaming text, messages, runs, approvals, activity, edits. |
| `events(chat, after: N)` | **Yes:** `events.after {session_id, after, limit:1000}`, then buffered/live `event` notifications. `resync` or `events.gap` reloads state and replays from the fresh host cursor. | `eventsAfter` then `subscribe`; resync/gap reloads. |
| Durable sequence | Adapter reserves 16 native kit sequence positions per host `HarnessEvent.sequence`, permitting multiple kit events per host event. Snapshots use the final position. Replay always converts back to host sequence. | `AgentEvent.sequence`. |
| Transient sequence and offset | `paragraph` and `text_delta` carry the last host sequence. Adapter reconciles prefixes, counts UTF-16 offsets and never persists them. Stdio state lacks `live_seen`; ambiguous fragments at the snapshot cursor are skipped. | Adapter counts from `streamingText`. |
| `loadHistoryRange` | **Yes** (feature `context`): `history.range {first_seq,last_seq,limit}` paged by `next_seq`. The kit sequence is the host's store `seq`: increasing, not necessarily dense, so span-derived counts are upper bounds. | Older-history paging is not mapped here. |
| `loadContext`, `loadSummary` | **Yes** (feature `context`): `context.structure`, `context.events`, `context.view`; `context.summary {kind,id}` with kit IDs `episode:<id>` / `chapter:<id>`. Host message IDs are resolved to sequences once and cached. The window comes from `session.state` usage when it is at or above the view's `threshold`; the reserve is then window minus threshold, else both are absent. | No mapping qualified here. |

## Events

| Kit event | BubblePaw stdio | Scratch |
|---|---|---|
| `chat.renamed` | `session.rename` updates metadata without a harness rename event; adapter emits the snapshot title diff. | Reload after `renameSession`. |
| `chat.archived` | **Missing** on stdio. | Archive missing (delete only). |
| `chat.settings` | Model read from runs/`run_started`; no model-list/settings or profile RPC. | `run_started.model`; profile missing. |
| `chat.workspace` | Host-bound workspace is supplied by the application; no branch/worktree data in stdio state. | Session project id/name. |
| `run.started` | `run_started {model}`; `run_quota_resumed` also clears the wait on the same run. | Same kinds. |
| `run.waiting` | `run_waiting_for_quota.wait {resume_at, reason}`. | Kind exists; structured quota fields missing. |
| `run.finished` | `run_finished {status,error}`; completed, failed, cancelled, interrupted. | Same kind/status. |
| `message.user` | Canonical user IDs/text are recovered from `session.state.messages`; run events omit them. | Reload after run start/steering. |
| `message.delta` | `text_delta` is provisional, `paragraph` confirms it. Matching prefixes emit only the missing suffix. Mismatch/retry requests resnapshot. | `paragraph`. |
| `message.assistant` | `run_finished.text` completes the provisional reply without a gap. Explicit snapshot reload recovers canonical message IDs. | `run_finished.text` or reload. |
| `message.system` | Canonical system messages/tool orphan results come from state; `output.record` text publications map to stable-ID plain system lines. File/image/execution publications have no kit renderer. | `output` or reload. |
| Thinking | No reasoning-text capability; model-request boundaries reset/reconcile provisional text. | No reasoning text. |
| `tool.started`, `tool.finished` | Durable `tool_started.call` and `tool_finished {call_id,result}` map directly; canonical calls/results are reconstructed on reload. No exit code is invented. | Tool started/finished, summaries in activity. |
| Nested transient tools | Kit tool events are durable; nested `durable:false` boundaries request snapshot recovery rather than consume a sequence or invent stored rows. | Nested tool progress is also transient. |
| `tool.output`, edit/undo events | No streamed tool-output or edit-undo RPC. File-tool output remains tool activity; no speculative diffs. | Edits read on reload; undo exists. |
| `plan.updated` | `host_state_changed {key:"todo",value}`; pending/in_progress/done map to todo/now/done. | Plan missing. |
| `approval.requested` | `approval_requested.approval`; pending records also from `approval.list`. | Same kind. |
| `approval.resolved` | `approval_resolved {approval_id,state,reason}`; approved_session maps to approvedForSession. | Same kind. |
| `question.asked`, `question.resolved` | **Built:** `host_state_changed {key:"question",value}`. One root question with free text and optional suggestions. A cleared question triggers state reload; snapshots retain only pending questions, so resolved prompt history disappears on reload. Child questions are not root prompts. | Questions missing. |
| Queue changes | `steering_accepted` / `followup_queued` omit input IDs, so reload real `session.state.inputs`; response IDs are retained by commands. No edit/remove methods. | Follow-up kind exists; IDs require reload. |
| Child events | **Built** (feature `child_events`): `child_run_state_changed` and `host_state_changed` keys `child_question` / `child_question_answer` mark the child stale and refresh; the diff yields `ChildSpawned`, `ChildQuestionAsked`, `ChildQuestionResolved`, `ChildFinished`. A finished child that runs again forces a gap. | Children missing. |
| Compaction events | **Built:** `context_compaction {event_id,kind,trigger}` refreshes; `CompactionUpdated` for an applied fact, `ContextChanged` when the view differs. | Missing. |
| Job events | Not advertised: `process.list` does not supply individual cancellation or streamed output. | Jobs missing. |
| `usage.updated` | `usage.last_request`, run completion and snapshot refresh trigger a diff of authoritative own-session totals/context in `session.state.usage`. Changed values emit `UsageUpdated`; per-run totals are never added twice. | Run token counts; context meter missing. |
| `gap` | `events.gap` or `events.after.resync`; reload state and replay from the last delivered durable cursor. A snapshot cursor does not discard undelivered events. Retention loss requires a snapshot reset. | gap/resync then reload. |
| Other host state / `session_settled` | Unprojected host state is ignored; `session_settled` refreshes snapshot-derived fields without an unconditional gap. Unknown event kinds are ignored. | Host-state/settled are read triggers. |

Transient events never become stored items. The display may show provisional
assistant IDs until an explicit snapshot reload replaces them; rewind requires
a canonical message ID from that snapshot. The unit and local-host
tests are distinct from live-model acceptance; neither proves a paid provider.

## Commands

| Kit command | BubblePaw stdio | Scratch |
|---|---|---|
| `createChat` | **Yes:** `session.open {title?}` in the bound workspace. | `createSession(title)`. |
| `send` | **Partial:** `run.start`; only a busy error falls back to `run.follow_up`. Text only. Host slash commands are rejected before RPC because they do not return a run. | `send` starts or queues. |
| `steer`, `followup` | **Yes:** `run.steer`, `run.follow_up`; real response input IDs. | Steer exists; send while busy queues. |
| `sendQueuedNow`, `editQueued`, `removeQueued` | **Missing.** Capabilities off. | Missing. |
| `cancel`, `resume` | **Yes:** `run.cancel`, `run.resume`. | Cancel yes; resume missing. |
| `decideApproval` | **Yes:** `approval.decide {approval_id,decision,reason?}`; approve / approve_session / deny. Verify pending approval belongs to the addressed chat. | `decideApproval`. |
| `answerQuestion` | **Partial:** `question.answer {session_id,question_id,text}`. A single item maps one chosen label or one text answer; no skipped/multiple answers. | Missing. |
| `answerChildQuestion` | **Yes** (feature `question.answer_child`): `question.answer_child {parent,child,question_id,text}`. Unknown or expired question maps to `KitNotFound`, already answered to `KitConflict`, a foreign child or blank text to `KitInvalid`. | Missing. |
| `rename` | **Yes:** `session.rename`, followed by snapshot refresh. | `renameSession`. |
| `archive` | **Missing:** `session.delete` is not archive. | Missing. |
| `fork` | **Missing:** core `Store::fork_at` and HTTP fork do not create a stdio RPC. | Missing. |
| `rewind` | **Partial:** `session.rewind {session_id,message_id}` creates a **new** session, including the selected message, and restores eligible checkpointed files. Adapter `rewindToNewChat` returns that summary and emits `createdChats`; source remains intact. | Missing. |
| `cancelChild` | **Yes (Core v0.3.1):** `child.cancel {parent, child}`, feature `child.cancel` turns on `children`. Cancels the child and what it started; the parent must be the child's direct parent. The adapter refreshes the crew afterwards. | Children missing. |
| `cancelJob` | **Missing:** `process.background` is not cancellation. | Jobs missing. |
| `undoEdit` | **Missing:** rewind is not per-edit undo. | `editUndo`. |
| `listProviders`, `setDefaultModel`, `listModels`, `setModel` | **Yes (Core v0.3.1):** `providers.list` (feature `providers.list`, capability `providers`) returns providers, kinds, whether a key was found (never the key), models, `main` and `active_main`. `roles.set_main {model}` (feature `roles.set_main`, capability `defaultModel`) saves the default as `provider/model`. `models` needs both. The host has one default, not one per chat, so `setModel` sets it for every chat and a run in progress keeps its own model. | `models()`; choice passed to send. |
| `listProfiles`, `setProfile` | **Missing.** | Missing. |

## Errors and recovery

BubblePaw stdio wraps command failures in JSON-RPC `-32000` with error strings.
The adapter recognizes source-backed busy/not-found/conflict/invalid/denied
patterns and produces safe kit errors; other RPC failures use a fixed failure
message, except code `-32004` (Core v0.5.1, a run with no provider configured): that one
becomes `KitNeedsSetup` carrying the host's message, which names the config keys and
host methods to set up. Raw provider/command errors are not logged. A busy send alone is retried
as follow-up, preventing duplicate admission after unrelated failures.

Protocol mismatch is typed with expected and actual versions. Child exit is typed
`BubblePawHostExited` (`hostExited`) with exit code and a bounded fully redacted
stderr tail. The core's sealed `KitError` prevents these adapter-specific types
from also being kit errors; this is a requested port change, not a core edit.
Pending approvals and interrupted runs recovered by the host are reflected by
fresh snapshots, even where recovery itself emits no durable event.

## Rewind semantics

Core describes an in-place rewind to before the selected item and returns void.
BubblePaw instead creates a new chat including that item; its adapter exposes
the resulting chat separately.

## Known port limits

The adapter does not introduce snapshot-backed message ordinals and leaves the
core contract unchanged. `ContextEvent.tokensBefore` and `tokensAfter`,
`ContextView.window` and `responseReserve`, and `ContextSummary.createdAt` are
nullable, so the adapter reports exactly what Core v0.3.0 sends (a view has only
a threshold; the window appears only when the session usage reports one at or
above it). Worked around: host sequences are not dense, so `messageCount`
is an upper bound, and `pendingEpisodeIds` is not derivable. The core also groups all context operations
behind one capability, seals error subtypes, returns void from rewind and treats
all tool boundaries as durable. These limits are recorded in the adapter README.
