# composer

The bottom of a chat: the composer (text field, Steer/Queue switch, model and
profile pickers, Stop and Send), the approval bar (needs-approval pill, waiting
time, tool and path, Approve / For session / Deny), the queue row (Send now,
Edit, remove) and the picks (references and context chips).

Mockup parts: `.composer`, `.approval`, `.queued`, `.cmp-chip`,
`.ctx-chip` in `app.css`. The composer fits its own width: below
`KitLayout.fitComposer` Stop and Send drop their labels. Input is
`ChatSnapshot.approvals`, `queue` and the backend commands.

Add a widget here as its own file, export it from `composer.dart`, and add a
gallery specimen and a golden (see `docs/agent-kit.md`).
