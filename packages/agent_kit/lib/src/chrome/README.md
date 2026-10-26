# chrome

The frame around a chat: the rail (workspace header, search, grouped session
rows with status meta, settings), the chat header (title, status pill, branch,
context meter, menu), the crew strip (child agents and jobs as chips) and the
"Still running" ledger.

Mockup parts: `.rail*`, `.rr-*`, `.hdr`, `.cs-*`, `.lg-*` in `app.css`.
Status always goes through `StatusMark`. The rail follows the theme (see
`BbTheme.rail*`). Input is `ChatSummary`, `ChatSnapshot.children` and
`jobs`.

Add a widget here as its own file, export it from `chrome.dart`, and add a
gallery specimen and a golden (see `docs/agent-kit.md`).
