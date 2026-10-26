# Golden fixtures: the event contract

These fixtures define how events fold into a chat snapshot. They are plain
JSON so that any implementation can replay them: the Dart reducer here, and
later the SDK's client projection (its `client` feature) as its own contract
tests. Copy or vendor the directory as it is; nothing in it is Dart-specific.

## Files

- `<name>.jsonl`: one JSON object per line, in order.
- `<name>.json`: the expected snapshot after the whole log, pretty-printed
  with a 2-space indent and a trailing newline.

## Log lines

Each line is exactly one of:

| Line | Meaning |
|---|---|
| `{"note": "..."}` | A comment. Skip it. |
| `{"seq": 1, "chat": "c1", "kind": "...", ...}` | An event. Fold it into the current snapshot. |
| `{"load": {...snapshot}}` | A reload: replace the current snapshot with this one (what `loadChat` returns after a `gap`). |
| `{"expect": {"key": value, ...}}` | A check: each key of the current snapshot's JSON equals the value. `null` means the key is absent. |

Replay starts from the empty snapshot of chat `c1`:
`{"chatId": "c1", "seq": 0, "title": ""}` with every list empty.

## Checks an implementation runs

1. Every event line parses and serialises back to an equal object.
2. Folding the log gives the expected `.json`, compared as JSON values.
3. Folding every event of the log again (gaps aside) into the final snapshot
   changes nothing.
4. The final snapshot parses and serialises back to an equal object.
5. Together, the logs use every event kind.

## Folding rules

- An event for another chat is ignored.
- An unknown `kind` is ignored and does not advance `seq`. Unknown fields are
  ignored; an unknown enum value reads as the field's default.
- A durable event with `seq <= snapshot.seq` is dropped; otherwise it applies
  and `snapshot.seq` becomes its `seq`.
- Transient events (`message.delta`, `thinking.delta`, `tool.output`,
  `job.output`) carry the last durable `seq`. One with `seq < snapshot.seq`
  is dropped. The rest apply by character `offset`: text already present is
  not appended twice, and a fragment past the end is skipped.
- `gap` sets `"stale": true`; the client then reloads (a `load` line).

## Wire conventions

- Keys are camelCase. Enum values are camelCase strings (`needsYou`,
  `approvedForSession`).
- Events are flat: `seq`, `chat`, `kind`, optional `at`, then the payload.
  Transcript items and activity rows are tagged by `type`.
- Times are UTC ISO 8601 with milliseconds (`2026-10-26T09:00:00.000Z`).
  Durations are integer milliseconds (`durationMs`).
- Absent optional values are omitted, never `null`. Lists on the snapshot
  are always present, possibly empty. A missing flag takes its default
  (`streaming` false, `undoable` and `freeText` true).
- `status` on the snapshot is derived from the rest and is written but never
  read. `stale` is client state; a server never sends it.
- Markdown and text are opaque strings. References are
  `{kind, id, label?, start?, end?}` spans.
