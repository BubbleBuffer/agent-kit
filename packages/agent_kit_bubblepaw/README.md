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
[BubblePaw-Core v0.3.1](https://github.com/BubbleBuffer/BubblePaw-Core/tree/v0.3.1),
specifically `crates/bubblepaw-runner/src/main.rs`'s stdio dispatcher,
`stdio_context.rs`, `context_reads.rs` and `question_stdio.rs`, with
`docs/session-api.md`, `docs/context-compaction.md`, `docs/lcm-contract.md` and
`docs/child-sessions.md`. Where those docs and the code differed, the code won.
`initialize.protocol_version` must equal **`0.1`**; any other value raises
`BubblePawProtocolMismatch` with `expectedVersion` and `actualVersion` and closes
the owned transport. Sessions and resumable events are required. The negotiated
feature list gates the optional capabilities; unknown feature names are retained
in `backend.features` without inventing support for them.

| Kit port | BubblePaw stdio | Support |
|---|---|---|
| `listChats` | `session.list` | Partial: with feature `session.list.pagination` pages of 100 by `next_cursor`; otherwise every chat, newest first; the title query filters the returned page; list metadata has no run status |
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
| `answerChildQuestion` | `question.answer_child {parent, child, question_id, text}` (feature `question.answer_child`) | Yes; `KitNotFound` for a gone question, `KitConflict` for an answered one |
| `cancelChild` | `child.cancel {parent, child}` (feature `child.cancel`, capability `children`) | Yes: then the crew is read again |
| `listProviders` | `providers.list` (feature `providers.list`, capability `providers`) | Yes: names, kinds, whether a key was found, models, default; no key value is read |
| `setDefaultModel`, `setModel` | `roles.set_main {model}` (feature `roles.set_main`, capability `defaultModel`) | Yes: host-wide default as `provider/model`; `setModel` ignores its chat |
| `listModels` | `providers.list` (capability `models` needs both features above) | Yes: usable models only (provider has no key requirement or its key was found) |
| `cancelJob` | No compatible advertised feature/operation | Missing |
| `archive`, `undoEdit`, profiles | No method | Missing |
| `fork` | No stdio fork method | Missing |
| `loadContext` | `context.structure`, `context.events`, `context.view` (feature `context`) | Yes, see "Context and children" |
| `loadSummary` | `context.summary {kind, id}` (kit ID `episode:<id>` or `chapter:<id>`) | Yes |
| `loadHistoryRange` | `history.range {first_seq, last_seq, limit}`, paged by `next_seq` | Yes, in host store sequences |
| `ChatSnapshot.context`, compaction markers | `context.view`, `context.events`, the `context_compaction` event | Yes, with feature `context` |
| Child agents and child questions | `session.list`, the child's `session.state`, `child_run_state_changed`, `child_question`, `child_question_answer` (feature `child_events`) | Yes: crew entries and questions; no child cancel |

Capabilities enabled: createChat, send, cancel, rename, resume, usage; approve
with `approvals`, steer with `steer`, questions with
`question`, plan with `todo`, rewind with `rewind`, context with `context` and
child answers with `question.answer_child`. Capabilities for queue
editing/send-now, child cancel, jobs, archive, edit undo, fork, models,
profiles, reasoning text and worktrees are absent. Widgets hide those
controls. Direct calls to absent optional commands return the core's specific
`KitUnsupported(capability)`; no advertised capability relies on an unsupported
RPC. Host slash commands are rejected before sending text because their results
cannot be represented as `SendResult`.

Questions have one item with ID `answer`. Suggested answers become pick-one
options with an Other input; without suggestions the item is free text. Skips,
multiple items, multiple choices, and choosing both a suggestion and text are
rejected without calling `question.answer`. This does not advertise multi-select
or multi-question support. `BackendConstraints` exposes reference rejection,
the supported question kinds, and whether `follow_up` was negotiated.

`rewindToNewChat(chatId, messageId)` returns the new chat summary, and
`createdChats` also emits it. The core's `rewind` delegates to this operation;
applications needing navigation must use that result or stream. It never
overwrites the source chat. BubblePaw's file restoration can report conflicts
and is limited to checkpointed file-tool effects; it is not a universal undo.

## Context and children (Core v0.3.0)

Each of these turns on only when `initialize.features` names it.

**Sequences.** The kit addresses messages by integer sequence; the host names
them by message ID in its context reads. The kit sequence is the host's canonical
store `seq`, which `history.range` returns with every row. The adapter resolves
each ID once (`history.range` with the ID as both bounds) and caches it. A host
sequence increases but is not necessarily dense, so counts derived from a span
(`ContextEpisode.messageCount`, `ContextSummary.messageCount`) are upper bounds;
a block's `messageCount` stays null. An episode, chapter or event whose IDs
cannot be resolved is left out of `loadContext`.

**`ChatSnapshot.context`.** `context.view` has `threshold`, the input size at
which a compaction is applied (`applyCap`), and the blocks. It has no window: the
window is `usage.context.window_tokens` of `session.state`, the reserve is the
window minus the cap; without a window (or one below the cap) both are null,
which the widgets show as absent.
`pendingEpisodeIds` stays empty (not derivable over stdio). `appliedAt` is the
time of the latest `applied` fact. A failing context read leaves `context` null
rather than failing the chat. `context.view` carries the frozen prefix messages
too; each chat load reads it once.

**`loadContext`.** `context.structure` (episodes, subject chapters, legacy
chapters), `context.events` and `context.view`. Summary bodies stay empty;
`loadSummary` has them. A summary's creation time is the time of the fact that
wrote it (null when none is recorded); it is `applied` when the view
holds it. The host's `tokens_before` and `tokens_after` stay null when absent
(`ContextEvent.tokensBefore` and `tokensAfter` are nullable).

**`loadHistoryRange`.** `history.range` with `first_seq`/`last_seq`, pages of 1000
followed by `next_seq`, at most 20 pages. Rows carry a one-line preview; system
messages read as agent lines (the kit has no system role).

**`context_compaction`.** The event only names the fact. The adapter refreshes
and publishes the difference: a `CompactionUpdated` marker
(`bubblepaw:compaction:<id>`) for an `applied` fact, and `ContextChanged` when
the serving view differs. `episode_written` and `chapter_closed` change neither
by themselves; applications re-read `loadContext`. After a reload the markers
return from `context.events`, in time order.

**Children.** A parent's children are its `session.list` entries with a matching
`parent_session_id`; each child's `session.state` gives the crew entry: the task
is its first user message, a finished run reads as done with the last reply as
the result, an interrupted run as cancelled, and a pending question as waiting
for an answer. The three child events do not carry the task or result, so each
marks its child stale and refreshes; the stream then publishes `ChildSpawned`,
`ChildQuestionAsked`, `ChildQuestionResolved` (answered, with its author, or
cancelled) and `ChildFinished`. Child records are cached only while the chat has
an open event stream. A finished child that runs again cannot be shown by kit
events (an ended child never leaves its state), so the stream resyncs with a gap.
A spawn row in the transcript appears for live events only, not after a reload.

## Snapshot and event consistency

Each event subscription has independent replay/stream reconciliation state.
On a gap or replay `resync`, the adapter emits kit `gap`, reloads `session.state`
and pending approvals, then requests `events.after` from the last delivered
durable cursor. Retained events through the snapshot boundary are delivered
before adopting its state; retention loss remains an explicit discontinuity.
Notifications arriving during recovery wait behind it; durable duplicates are
discarded. During ordinary refresh replay, already-buffered notifications through
each replay boundary are delivered in arrival order before the cursor advances.
This keeps transient confirming paragraphs ahead of later durable approvals or
tools; a refresh cannot turn a valid next model request into a false text retry.
Each buffered notification is consumed once. Replay is read in pages of 1000.

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

`BubblePawBackend.connectionLost` completes with the error that ended the host
connection (a `BubblePawHostExited` when the child exits), including while no
event stream is open, so an idle application can show the failure at once. It
never completes after a deliberate `dispose`.

## Verification levels

All builds and tests run on GitHub-hosted CI.

1. **Unit:** in-process peers and synthetic JSON lines test framing, mapping,
   capabilities, gap/resync recovery, protocol mismatch and crashes.
2. **Local transport:** opt in with `BP_TEST_BIN`. CI downloads the pinned Linux
   v0.3.1 archive, checks its entry in `SHA256SUMS`, and runs the real child with
   the built-in `demo` provider, read-only workspace, native mode and automatic
   summaries disabled. It sends messages, sees kit run/text/completion, and
   survives dropped real notifications followed by an injected `events.gap`.
   Gap injection tests adapter recovery, not an actual host buffer overflow. It
   also reads the context, every summary and the whole history range of a demo
   chat; the demo writes no episodes, so only the shape of those reads is asserted.
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
Every check prints its own PASS/FAIL line, including observed approvals, exec
starts/finishes, steering queue events and command acceptance, usage events,
gaps and completion. Failures and timeouts print the same diagnostic rows.
Usage reconciliation may finish after `run.finished`, so the script waits for
the first usage event within the existing overall deadline before verifying.
Canonical history checks print separate rows once that stage is reached.

The attempt-3 fixture preserves recorded durable ordering. Its content-bearing
payloads were removed at capture time; the regression uses explicit synthetic
replacements and cannot identify that historical run's exact failed check. See
`test/fixtures/transport/attempt-3-README.md` for the evidence limits.

The attempt-5 regression preserves all 47 captured event notifications, including
transient text and all 15 durable sequences. It reproduces a confirming paragraph
overtaken by approval replay during a usage refresh, then checks zero gaps through
tools, approvals, steering, usage and completion. Content and snapshots are
synthetic because the capture removed them. See
`test/fixtures/transport/attempt-5-README.md` for the recorded boundaries and limits.

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

The adapter does not assign snapshot-backed message ordinals or change the core
contract: history ranges use the host's store sequence.

Requested core changes, kept outside this implementation's scope:

- Return a new chat from rewind, with file restoration/conflict details.
- Allow typed adapter lifecycle failures within the kit error contract.
- Split context details, summary loading and history paging capabilities; use
  canonical message-ID cursors for history. Core v0.3.0 reads ranges by ID or by
  store sequence; the kit's `messageCount` assumes a dense sequence.
- Express the single-item and no-skip limits beyond the supported question kinds.
- Carry transient tool boundaries and text replacement/reset explicitly.
- Allow unknown question/queue timestamps and unknown session-list status.

The internal transport interface is deliberately small. HTTP/SSE is not built.
