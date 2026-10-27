The adjacent attempt-3 trace retains 116 redacted protocol records from the
reported live failure. Byte lengths and unknown field names were removed for
publication. Only protocol constants, ordinal ID aliases, booleans, cursors and
redaction markers remain. There are no hosts, filesystem paths or credentials.

The original capture already removed entire tool-start payloads, exec result
content, all usage values, canonical session contents and text. These values
cannot be recovered from this fixture. In particular, repeating `[REDACTED]`
as live text would manufacture text-reconciliation gaps.

The backend regression replays its 15 durable notifications in sequence through
the production stdio transport and adapter replay path. Missing tool metadata is
reconstructed from the preceding approval's aliases; successful exec results
and final session usage are synthetic. Live text is omitted. This tests the
recorded durable ordering with usage withheld until the terminal refresh; it
does not establish the original run's token counts, process exit codes or text
consistency, nor identify its exact failed check.

Before the fix, terminal delivery followed by settled approval/steering commands
triggered immediate verification, rejecting a valid run before the adapter's
session-usage refresh completed. The regression failed at that verification
point. The script now waits for a usage event within its existing overall
deadline. Missing usage still fails, and no acceptance threshold was relaxed.
