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

Ordinary snapshot refreshes retain the last delivered durable cursor and replay
from it before emitting snapshot-derived changes. Steering, `run_finished` and
`session_settled` refresh state without routine kit gaps. Projection changes that
exceed the 16 reserved positions, incompatible text and nested transient tool
boundaries can still require a resync.

One host event can map to several kit events. Native kit sequences reserve 16
positions for each host sequence: durable subevents occupy the first positions,
snapshots and transient fragments use the last. These adapter sequences are not
host cursors or JavaScript-safe persisted wire IDs. The adapter converts them
back before replay. The stdio adapter is for native Dart applications.

`text_delta` is provisional; paragraphs confirm it. Matching prefixes produce
only missing text. A retry or conflicting prefix requests a fresh snapshot
instead of duplicating or committing provisional text. Streamed assistant IDs
remain stable through completion and ordinary refreshes; an explicit `loadChat`
returns canonical message IDs. Load that snapshot before rewinding: rewind
requires a canonical message ID. Transient notifications are never written to storage.
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
Usage updates compare authoritative session totals on `usage.last_request`, run
completion and refresh; per-request usage is not treated as the session total.
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
   the built-in `demo` provider, read-only workspace, native mode and automatic
   summaries disabled. It sends messages, sees kit run/text/completion, and
   survives dropped real notifications followed by an injected `events.gap`.
   Gap injection tests adapter recovery, not an actual host buffer overflow.
3. **Live model:** the opt-in script below exercises a real configured provider.
   It is never run in CI and has no live acceptance result until a user runs it.

```sh
cd packages/agent_kit_bubblepaw
dart test
BP_TEST_BIN=/path/to/bubblepaw dart test test/local_transport_test.dart
```

## Opt-in live model acceptance

`tool/live_check.dart` makes real model calls and automatically **approves every
approval request in the new acceptance session**, once per request. Invoking it
authorizes that behavior. Use a trusted provider configuration and a disposable
workspace. These approval decisions are not a sandbox: a model tool can affect
resources outside its workspace. No live credentials belong in this repository
or in command arguments.

```sh
cd packages/agent_kit_bubblepaw
dart run tool/live_check.dart \
  --binary /path/to/bubblepaw \
  --config /path/to/private-provider.toml \
  --trace /path/to/new-redacted-wire.jsonl
```

The provider, authentication references and model come from the private TOML
configuration. Additional host arguments follow `--`, for example
`-- --model MODEL`. The script forces native tools,
`approvals.tools.exec="ask"`, and disables automatic summaries. Built-in tools
do not declare approval requirements by default, so the explicit per-tool policy
is necessary to observe an approval. It uses two separate exec calls, handles
every approval (including later requests), steers while the first approved exec
is active, awaits kit `run.finished`, and checks successful process results plus
canonical steering delivery and the final reply. It also requires at least one
`UsageUpdated` and zero kit gaps during this ordinary run. Choose a provider that
reports usage; missing usage or a resync makes the check fail. The printed result
includes approval, process, usage and gap counts without message contents.

Workspace and data directories default to temporary directories that the script
removes. Optional `--workspace` and `--data-dir` retain caller-supplied directories;
the data directory must be empty and dedicated to this child. `--timeout-seconds`
bounds the live send, completion, pending decisions and final snapshot together;
it defaults to 180 (maximum 3600). Disposal shuts down only the process the script
started. A failed check prints a fixed stage/reason without arbitrary provider,
exception or path text. A provider may decline the requested tools; that is a
failed live acceptance check, not evidence that the local transport is broken.

`--trace` is optional and requires a new file. It tees actual stdin/stdout JSON
lines at the byte pipes before transport parsing, rather than reconstructing
notifications from kit events. Each JSONL entry records the observed line order,
direction, byte count, completeness and structurally redacted record. Protocol
constants are allowlisted and IDs are replaced with consistent aliases. Text,
commands, arguments, paths, arbitrary values and unknown keys are removed;
stderr and malformed/incomplete lines retain counts only. This is a **redacted
wire capture**, not byte-exact raw output. Cross-pipe ordering is the order
observed by Dart, not a claim about simultaneous writes in the host. The host's
own private data directory remains separate from this capture.

## Port gaps

`loadHistoryRange` remains an absent capability, pending a paging RPC in
BubblePaw stdio. The adapter does not assign snapshot-backed message ordinals
or change the core contract.

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
