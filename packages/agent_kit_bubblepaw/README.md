# agent_kit_bubblepaw

A pure Dart `AgentBackend` for an application-owned BubblePaw child process.
Licensed under the repository's AGPL-3.0 license. No HTTP server, token, provider
SDK or Flutter dependency is introduced.

```dart
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';

final backend = await BubblePawBackend.start(
  binaryPath: binaryPath,
  workspaceDirectory: workspaceDirectory,
  dataDirectory: dataDirectory,
);
// Pass backend to AgentWorkbench, then await backend.dispose() on exit.
```

The host command is `bubblepaw --workspace <directory> --data-dir <directory>
stdio`. The caller supplies the executable and directories. The package owns
only this child; disposal requests `shutdown`, closes stdin, waits a bounded
time, then kills that child by its process handle if necessary. Never share a
data directory with another host. Additional host arguments can be supplied
through `arguments`; callers remain responsible for their configuration.

## Protocol and capabilities

The implementation is checked against
[BubblePaw-Core v0.2.2](https://github.com/BubbleBuffer/BubblePaw-Core/tree/v0.2.2),
specifically `crates/bubblepaw-runner/src/main.rs`'s stdio dispatcher,
`docs/session-api.md`, `docs/web-contract.md` and `docs/sdk.md`.
`initialize.protocol_version` must equal **`0.1`**; any other value raises
`BubblePawProtocolMismatch` with `expectedVersion` and `actualVersion` and closes
the owned transport. Sessions and resumable events are required. The negotiated
feature list gates the optional capabilities; unknown feature names are retained
in `backend.features` without inventing support for them.

| Kit port | BubblePaw stdio | Support |
|---|---|---|
| `listChats` | `session.list` | Partial: newest 64 matching titles, no cursor; list metadata has no run status |
| `loadChat` | `session.state`, `approval.list` | Yes: canonical messages, tools, runs, queue, todo, question, usage |
| `events` | `event`, `events.after`, `events.gap` | Yes, snapshot recovery described below |
| `createChat` | `session.open` | Yes, host-bound workspace |
| `send` | `run.start`, then `run.follow_up` only on busy | Partial: text only; reference attachments are rejected before sending |
| `steer`, `followup` | `run.steer`, `run.follow_up` | Yes, using real queued-input IDs from the response |
| `cancel`, `resume` | `run.cancel`, `run.resume` | Yes |
| `decideApproval` | `approval.list`, `approval.decide` | Yes: approve / approve_session / deny |
| `answerQuestion` | `question.answer` | Partial: one question item; one suggestion label **or** one free-text answer |
| `rename` | `session.rename` | Yes; resnapshot after metadata changes |
| `rewind` | `session.rewind` | Partial: creates a new chat, including the selected message; source remains intact |
| `sendQueuedNow`, `editQueued`, `removeQueued` | No method | Missing |
| `answerChildQuestion`, `cancelChild`, `cancelJob` | No compatible advertised feature/operation | Missing |
| `archive`, `undoEdit`, profiles | No method | Missing |
| `fork`, models | No stdio fork/model-list/settings methods | Missing |
| `loadContext`, `loadSummary` | No method | Missing |
| `loadHistoryRange` | No stdio paging method or integer message sequence | Missing: see the port gap below |

Capabilities enabled: rename, resume, usage; steer with `steer`, questions with
`question`, plan with `todo`, and rewind with `rewind`. Capabilities for queue
editing/send-now, children, child answers, jobs, archive, edit undo, fork, models,
profiles, reasoning text, worktrees and context are absent. Widgets hide those
controls. Direct calls to absent optional commands return the core's specific
`KitUnsupported(capability)`; no advertised capability relies on an unsupported
RPC. Host slash commands are rejected before sending text because their results
cannot be represented as `SendResult`.

Questions have one item with ID `answer`. Suggested answers become pick-one
options with an Other input; without suggestions the item is free text. Skips,
multiple items, multiple choices, and choosing both a suggestion and text are
rejected without calling `question.answer`. This does not advertise multi-select
or multi-question support.

`rewindToNewChat(chatId, messageId)` returns the new chat summary, and
`createdChats` also emits it. The core's `rewind` delegates to this operation;
applications needing navigation must use that result or stream. It never
overwrites the source chat. BubblePaw's file restoration can report conflicts
and is limited to checkpointed file-tool effects; it is not a universal undo.

## Snapshot and event consistency

Each event subscription has independent replay/stream reconciliation state.
On a gap or replay `resync`, the adapter emits kit `gap`, reloads `session.state`
and pending approvals, then requests `events.after` using the new snapshot's
host cursor. Notifications arriving during recovery wait behind it; durable
duplicates are discarded. Replay is read in pages of 1000.

One host event can map to several kit events. Native kit sequences reserve 16
positions for each host sequence: durable subevents occupy the first positions,
snapshots and transient fragments use the last. These adapter sequences are not
host cursors or JavaScript-safe persisted wire IDs. The adapter converts them
back before replay. The stdio adapter is for native Dart applications.

`text_delta` is provisional; paragraphs confirm it. Matching prefixes produce
only missing text. A retry or conflicting prefix requests a fresh snapshot
instead of duplicating or committing provisional text. Completion reloads the
canonical message IDs; transient notifications are never written to storage.
Stdio `session.state` omits `live_seen`, so fragments at exactly the snapshot
cursor cannot be distinguished from already-included fragments and are skipped.
The canonical completion remains authoritative.

Tool starts/results, approvals, run/quota changes, questions and todos map to kit
events. Queue notifications lack input IDs, so steering/follow-up events cause a
canonical queue reload. Explicit `text` output publications map to stable-ID
plain system lines; nontext file/image/execution outputs have no kit renderer.
Settled notifications request a snapshot. Source snapshots contain only pending
questions, so resolved prompts observed live disappear on reload; their canonical
generated answer messages remain in history.
Nested transient tool boundaries request reloads: the current core has only
durable tool events, so those live-only inner rows cannot be faithfully retained.
Pending approvals are obtained separately because stdio state omits them.
Unknown question/queue timestamps use the UTC epoch; they are not arrival times.

## Errors and privacy

`BubblePawProtocolMismatch` and `BubblePawHostExited` are adapter exception types.
Host exit includes its exit code and a bounded `stderrTail`; every arbitrary
stderr line is redacted to its byte count so credentials and environment values
cannot escape through diagnostics. No environment or provider response is logged.
JSON-RPC errors are classified privately into safe kit errors. The core seals
`KitError`, so adapter lifecycle exceptions cannot currently be kit error subtypes;
the existing workbench displays its generic error text for these exceptions.

## Verification levels

All builds and tests run on GitHub-hosted CI.

1. **Unit:** in-process peers and synthetic JSON lines test framing, mapping,
   capabilities, gap/resync recovery, protocol mismatch and crashes.
2. **Local transport:** opt in with `BP_TEST_BIN`. CI downloads the pinned Linux
   v0.2.2 archive, checks its entry in `SHA256SUMS`, and runs the real child with
   the built-in `demo` provider, read-only workspace, JS mode and automatic
   summaries disabled. It sends messages, sees kit run/text/completion, and
   survives dropped real notifications followed by an injected `events.gap`.
   Gap injection tests adapter recovery, not an actual host buffer overflow.
3. **Live model:** not part of this package's acceptance run.

```sh
cd packages/agent_kit_bubblepaw
dart test
BP_TEST_BIN=/path/to/bubblepaw dart test test/local_transport_test.dart
```

## Port gaps

Requested core changes, kept outside this implementation's scope:

- Return a new chat from rewind, with file restoration/conflict details.
- Allow typed adapter lifecycle failures within the kit error contract.
- Split context details, summary loading and history paging capabilities; use
  canonical message-ID cursors for history. The HTTP `/messages` endpoint does
  not exist in v0.2.2 stdio, and message IDs have no integer event sequence.
- Distinguish single-question/text support from multi-item/multi-select support.
- Carry transient tool boundaries and text replacement/reset explicitly.
- Advertise reference attachments, follow-up admission and approvals separately.
- Allow unknown question/queue timestamps and unknown session-list status.

The internal transport interface is deliberately small. HTTP/SSE is not built.
