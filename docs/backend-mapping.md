# Backend mapping

The kit's backend port is implemented by adapters. BubblePaw is the public
[BubblePaw-Core v0.2.2](https://github.com/BubbleBuffer/BubblePaw-Core/tree/v0.2.2)
runner over **stdio JSON-RPC 0.1**, through `agent_kit_bubblepaw`. There is no
`client` Cargo feature or pre-existing layer that emits kit-shaped JSON.
Scratch is the separate `NotesAgent` bridge; its column below preserves the
existing bridge mapping and has not been requalified against a new release.

BubblePaw calls and fields were checked against the tagged source:

- [`main.rs` stdio dispatcher](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.2.2/crates/bubblepaw-runner/src/main.rs)
- [Session API](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.2.2/docs/session-api.md)
- [Web contract](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.2.2/docs/web-contract.md)
- [SDK](https://github.com/BubbleBuffer/BubblePaw-Core/blob/v0.2.2/docs/sdk.md)

A method available through HTTP, core Rust or a model-facing JS tool is not
necessarily a stdio RPC. The stdio mapping below is deliberately transport-specific.
Missing optional capabilities are off, so widgets hide those actions. See the
[adapter README](../packages/agent_kit_bubblepaw/README.md) for lifecycle, errors,
verification levels and the complete list of desired port changes.

## Reads and sequence numbers

| Kit | BubblePaw stdio | Scratch |
|---|---|---|
| `listChats({cursor, query})` | **Partial:** `session.list`, sorted by updated time, title-filtered locally, capped at 64, no cursor. Its metadata has no run status. | `sessions()`, newest first; no cursor or query. |
| `loadChat(id)` | **Yes:** `session.state` plus `approval.list` for pending approvals. Snapshot has `seq`, canonical messages, runs, inputs, outputs, todo, question and usage. | `sessionState(id)` with seq, streaming text, messages, runs, approvals, activity, edits. |
| `events(chat, after: N)` | **Yes:** `events.after {session_id, after, limit:1000}`, then buffered/live `event` notifications. `resync` or `events.gap` reloads state and replays from the fresh host cursor. | `eventsAfter` then `subscribe`; resync/gap reloads. |
| Durable sequence | Adapter reserves 16 native kit sequence positions per host `HarnessEvent.sequence`, permitting multiple kit events per host event. Snapshots use the final position. Replay always converts back to host sequence. | `AgentEvent.sequence`. |
| Transient sequence and offset | `paragraph` and `text_delta` carry the last host sequence. Adapter reconciles prefixes, counts UTF-16 offsets and never persists them. Stdio state lacks `live_seen`; ambiguous fragments at the snapshot cursor are skipped. | Adapter counts from `streamingText`. |
| `loadHistoryRange` | **Missing on the current port:** stdio has only full canonical `session.state.messages`; IDs are strings without integer message sequences. HTTP message-ID paging is not a stdio method. `context` remains off. | Older-history paging is not mapped here. |
| `loadContext`, `loadSummary` | **Missing:** no stdio RPC. Hooks remain the absent core methods, without fabricated data. | No mapping qualified here. |

## Events

| Kit event | BubblePaw stdio | Scratch |
|---|---|---|
| `chat.renamed` | `session.rename` updates metadata without a harness rename event; adapter emits gap and reloads. | Reload after `renameSession`. |
| `chat.archived` | **Missing** on stdio. | Archive missing (delete only). |
| `chat.settings` | Model read from runs/`run_started`; no model-list/settings or profile RPC. | `run_started.model`; profile missing. |
| `chat.workspace` | Host-bound workspace is supplied by the application; no branch/worktree data in stdio state. | Session project id/name. |
| `run.started` | `run_started {model}`; `run_quota_resumed` also clears the wait on the same run. | Same kinds. |
| `run.waiting` | `run_waiting_for_quota.wait {resume_at, reason}`. | Kind exists; structured quota fields missing. |
| `run.finished` | `run_finished {status,error}`; completed, failed, cancelled, interrupted. | Same kind/status. |
| `message.user` | Canonical user IDs/text are recovered from `session.state.messages`; run events omit them. | Reload after run start/steering. |
| `message.delta` | `text_delta` is provisional, `paragraph` confirms it. Matching prefixes emit only the missing suffix. Mismatch/retry requests resnapshot. | `paragraph`. |
| `message.assistant` | `run_finished.text` completes provisional reply, followed by a canonical reload to recover real message IDs. | `run_finished.text` or reload. |
| `message.system` | Canonical system messages/tool orphan results come from state; `output` requests a snapshot. | `output` or reload. |
| Thinking | No reasoning-text capability; model-request boundaries reset/reconcile provisional text. | No reasoning text. |
| `tool.started`, `tool.finished` | Durable `tool_started.call` and `tool_finished {call_id,result}` map directly; canonical calls/results are reconstructed on reload. No exit code is invented. | Tool started/finished, summaries in activity. |
| Nested transient tools | Kit tool events are durable; nested `durable:false` boundaries request snapshot recovery rather than consume a sequence or invent stored rows. | Nested tool progress is also transient. |
| `tool.output`, edit/undo events | No streamed tool-output or edit-undo RPC. File-tool output remains tool activity; no speculative diffs. | Edits read on reload; undo exists. |
| `plan.updated` | `host_state_changed {key:"todo",value}`; pending/in_progress/done map to todo/now/done. | Plan missing. |
| `approval.requested` | `approval_requested.approval`; pending records also from `approval.list`. | Same kind. |
| `approval.resolved` | `approval_resolved {approval_id,state,reason}`; approved_session maps to approvedForSession. | Same kind. |
| `question.asked`, `question.resolved` | **Built:** `host_state_changed {key:"question",value}`. One root question with free text and optional suggestions. A cleared question triggers state reload. Child questions are not root prompts. | Questions missing. |
| Queue changes | `steering_accepted` / `followup_queued` omit input IDs, so reload real `session.state.inputs`; response IDs are retained by commands. No edit/remove methods. | Follow-up kind exists; IDs require reload. |
| Child/job events | Not advertised: initialization has no complete child feature, and `process.list` does not supply individual cancellation or streamed output. | Children/jobs missing. |
| `usage.updated` | Authoritative own-session totals/context in `session.state.usage`; changes/finish request snapshot, never add per-run totals twice. | Run token counts; context meter missing. |
| `gap` | `events.gap` or `events.after.resync`; adapter reloads state, then resumes replay. | gap/resync then reload. |
| Other host state / `session_settled` | Snapshot refresh; unknown event kinds safely ignored. | Host-state/settled are read triggers. |

Transient events never become stored items. The display may show provisional
assistant text until canonical completion replaces it. The unit and local-host
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
| `answerChildQuestion` | **Missing:** root endpoint explicitly rejects child sessions; no substitution with a root answer. | Missing. |
| `rename` | **Yes:** `session.rename`, followed by snapshot refresh. | `renameSession`. |
| `archive` | **Missing:** `session.delete` is not archive. | Missing. |
| `fork` | **Missing:** core `Store::fork_at` and HTTP fork do not create a stdio RPC. | Missing. |
| `rewind` | **Partial:** `session.rewind {session_id,message_id}` creates a **new** session, including the selected message, and restores eligible checkpointed files. Adapter `rewindToNewChat` returns that summary and emits `createdChats`; source remains intact. | Missing. |
| `cancelChild` | **Missing capability:** no complete child projection/negotiated feature. | Children missing. |
| `cancelJob` | **Missing:** `process.background` is not cancellation. | Jobs missing. |
| `undoEdit` | **Missing:** rewind is not per-edit undo. | `editUndo`. |
| `listModels`, `setModel` | **Missing:** run options can carry a model, but no stdio model enumeration/settings RPC. | `models()`; choice passed to send. |
| `listProfiles`, `setProfile` | **Missing.** | Missing. |

## Errors and recovery

BubblePaw stdio wraps command failures in JSON-RPC `-32000` with error strings.
The adapter recognizes source-backed busy/not-found/conflict/invalid/denied
patterns and produces safe kit errors; other RPC failures use a fixed failure
message. Raw provider/command errors are not logged. A busy send alone is retried
as follow-up, preventing duplicate admission after unrelated failures.

Protocol mismatch is typed with expected and actual versions. Child exit is typed
`BubblePawHostExited` (`hostExited`) with exit code and a bounded fully redacted
stderr tail. The core's sealed `KitError` prevents these adapter-specific types
from also being kit errors; this is a requested port change, not a core edit.
Pending approvals and interrupted runs recovered by the host are reflected by
fresh snapshots, even where recovery itself emits no durable event.

## Remaining port gaps

The adapter cannot faithfully implement integer-sequence history paging from
string message IDs without defining new semantics. The core also groups all
context operations behind one capability, seals error subtypes, returns void
from rewind, treats all tool boundaries as durable, and has no question-shape,
attachment or unknown-timestamp capability. These limits are recorded in the
adapter README. Core and BubblePaw source remain read-only in this change.
