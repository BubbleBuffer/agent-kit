# Attempt 5 refresh/replay regression

`attempt-5-events.jsonl` preserves all 47 `event` notifications from the redacted
attempt-5 wire capture, including the original notification order numbers,
durable flags, aliased identities, event types and all 15 durable sequences.
It contains no private host, workspace path, provider configuration or secret.

The capture removed text, timestamps, tool calls/arguments, tool results, state
keys/values, session snapshots, usage and feature lists. Those fields in this
fixture and its peer are explicitly synthetic. Timestamps are unique test values;
text fragments confirm matching paragraphs. Tool calls are paired with the
preserved approval call IDs. Neither synthetic payloads nor the peer reconstruct
the original model wording or canonical snapshot contents.

The neighboring attempt-5 run log reported two approvals, two successful execs,
one steering delivery, three usage updates, one gap and successful completion.
All recorded durable sequences 1 through 15 were present. Every recorded replay
response had `resync: false`; the capture contained no `events.gap` notification.

The decisive recorded ordering is:

| Wire order | Record |
|---|---|
| 24 | transient text delta at sequence 1 |
| 25 | durable host-state telemetry at sequence 2 |
| 26 | transient confirming paragraph at sequence 2 |
| 27-31 | refresh reads snapshot sequence 2 and pending approvals |
| 30 | approval notification at sequence 3 arrives during that refresh |
| 32-35 | refresh replays approval sequence 3 from cursor 2 |
| 61-62 | tool result then next model request at sequence 7 |
| 63 | unexpected session-state reload immediately after that request boundary |

The backend test uses the production stdio transport and backend, releases these
notifications in their captured order, and reproduces the snapshot-2/replay-3
race. Before the fix, replay advances the watch cursor to 3 while paragraph 2 is
still queued. Both watch and projection reject that paragraph as old. At the
next request boundary the projection's visible text remains unconfirmed, so it
requests a gap and recovery. The trace's reload timing and the run log support
this path; the removed payloads prevent independent proof of original text
equality. Synthetic matching text establishes that this path fails even for a
valid contiguous stream, without a retry or transport loss.

The replay also checks two approvals and decisions, two successful tool results,
steering through the actual command API, authoritative usage, completion, exact
streamed text and offsets, and zero gaps. Snapshot replies and scheduling barriers
are deterministic reconstructions of the recorded boundaries, not a byte-exact
replay or a new live model acceptance run. Explicit host gaps and retention resync
remain covered separately by the backend suite.
