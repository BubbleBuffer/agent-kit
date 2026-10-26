# status

`StatusMark`, the only way the kit shows a status. Every other widget (rail
rows, header pill, crew strip, ledger, approval bar) puts a `StatusMark` next to
its text and never draws a status colour itself.

Status colours come from `BbTheme.statusStyle`; the table is in `NOTES.md`
("Status colour") of the mockup and in `docs/agent-kit.md`.
