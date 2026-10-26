# agent_kit_core

Pure Dart (no Flutter, no runtime dependencies): the view models of an
agent chat, the `AgentBackend` port, a pure reducer that folds events into a
snapshot, typed command errors and a scripted fake backend. Its JSON shapes
are the Dart mirror of the SDK's layer 2 client contract; see
[backend-mapping.md](backend-mapping.md).

## Libraries

- `package:agent_kit_core/agent_kit_core.dart`: models, items, events,
  snapshot, reducer, backend port, errors, `ChatFeed`.
- `package:agent_kit_core/fake.dart`: `ScriptedBackend`, `ManualClock`,
  `SystemClock` and the "Quota bar flickers on reconnect" script.

## Snapshot plus events

`loadChat(id)` returns a `ChatSnapshot` up to sequence N;
`events(chat, after: N)` streams `KitEvent`s, each `{seq, chat, kind, at?, ...}`.
`reduce(snapshot, event)` returns the next snapshot:

- events for another chat and unknown kinds change nothing;
- durable events with `seq <= snapshot.seq` are dropped;
- transient events (`message.delta`, `thinking.delta`, `tool.output`,
  `job.output`) carry the last durable seq, are dropped when older than the
  snapshot, and apply by character `offset`, so a repeated fragment is
  appended once;
- `gap` marks the snapshot `stale`; the client reloads.

A completed message replaces its streamed item. `run.finished` closes
streaming items; running tool rows become cancelled, or done when the run
completed. Rewind and fork reach a client as a `gap` and a reload.

`ChatFeed` does the loop: load, subscribe, reload on `gap` (buffering events
that arrive meanwhile), and mark the snapshot stale when the stream ends.

## Models

Immutable classes with value equality (defined by their JSON) and
`toJson`/`fromJson`; sealed classes for variants (`TranscriptItem`,
`ActivityRow`, `KitEvent`, `KitError`). Markdown is an opaque string and
references are `KitRef` spans `{kind, id, label, start, end}`. Workspace
panes are not part of core.

- **Transcript items:** user, assistant, system, notice, activity group
  (thinking, tool and spawn rows), file edit, child result.
- **Panels:** approvals, questions, queue, plan, children, jobs, usage,
  workspace, run.
- **Status** is derived, never stored: `needsYou` (pending approval or
  question), then `running` (active run, quota wait included, or a running
  child; jobs do not count), then `failed` / `interrupted` / `done` from the
  last run, else `idle`.
- **Questions** are requests of 1 to 5 questions (see below).
- **Approvals** have `requestedAt` and no deadline. After a host restart they
  come back `expired` with reason `restart`, and the run `interrupted`, which
  offers `resume`.

## Questions

A `Question` is one request from the agent: `{id, requestedAt, items, state,
answers?, reason?}`. It holds 1 to `maxQuestionItems` (5) `QuestionItem`s, and
the constructor (so `fromJson` too) throws `ArgumentError` for an empty or
longer list, or for a pick item with no options and no `allowOther`. Hosts
must split anything over 5 into several requests.

- `QuestionItem {id, header, text, kind, options, allowOther}`: `header` is
  the short tab label, `text` is markdown. `kind` is a `QuestionKind`:
  `pickOne` (one option, or typed Other text), `pickAny` (any number,
  including none, plus Other text) or `text` (a typed answer only; `options`
  is empty and `allowOther` is ignored). Kinds can vary within a request.
- `QuestionOption {label, description?}`.
- `QuestionAnswer {choices, text?, skipped}`: `choices` are option labels,
  `text` is the Other text or the answer to a `text` item, and `skipped`
  marks a declined item. For `pickOne`, at most one of `choices` and `text`
  is set.
- `Question.answers` maps item ids to answers once the request is answered.
  The port's `answerQuestion(chatId, questionId, answers)` takes the same map
  and every item gets an entry (a skipped item has `skipped: true`);
  the fake backend rejects a map with a missing item as `KitInvalid`.
- Events keep their shape: `question.asked` carries the `Question`;
  `question.resolved` carries `questionId`, `state` and `answers`.
- Like approvals, questions never expire on their own; `requestedAt` gives
  the age ("waiting 12m").

`mixedQuestionScript()` (in `fake.dart`) ends a chat waiting on a request of
a pick-one item with descriptions and Other, a pick-any item and a text item.
The widgets are `QuestionPrompt` and `QuestionAnswerLines` in `agent_kit`'s
composer folder.

## Backend port

`AgentBackend` declares `KitCapabilities`; widgets hide what a backend lacks.
Commands return futures and fail with a `KitError` subclass whose `message`
is safe to show: `KitUnsupported`, `KitNotFound`, `KitBusy`, `KitConflict`,
`KitInvalid`, `KitUnavailable`, `KitDenied`, `KitFailed`.

Besides the reads, the port has `createChat`, `send` (starts a run or
queues), `steer`, `followup`, `sendQueuedNow`, `editQueued`, `removeQueued`,
`cancel`, `resume`, `decideApproval`, `answerQuestion`, `rename`, `archive`,
`fork`, `rewind`, `cancelChild`, `cancelJob`, `undoEdit`, `listModels`,
`listProfiles`, `setModel`, `setProfile`.

## Fake backend

`ScriptedBackend` plays `ChatScript`s (timed steps of event JSON) on a
`KitClock`, folds every event into its own state and answers commands with
the events a real backend would send. Sequence numbers are global, as in the
SDK's store. Steps `$disconnect` and `$reconnect` drop and restore delivery;
reconnecting sends a `gap`. `failNext` makes the next command fail;
`commands` records every call. With `ManualClock`, playback is stepped by
`advance` or `runAll` and is deterministic.

## Tests

- `test/golden_test.dart` replays each `test/fixtures/*.jsonl` and compares
  the snapshot with `<name>.json`. The format is a shared contract, written
  up in `test/fixtures/README.md`, so the SDK's layer 2 can replay the same
  files. `UPDATE_GOLDENS=1 dart test` rewrites the expected files.
- `test/question_test.dart`: the question model (every kind round-trips,
  0 and 6 items and an option-less pick item are rejected) and the mixed
  question scenario with `answerQuestion`.
- `test/backend_test.dart`: the clock, the fake backend's commands and
  errors, and the quota scenario end to end through a reconnect, checking
  the final snapshot holds every element of the mockup.
