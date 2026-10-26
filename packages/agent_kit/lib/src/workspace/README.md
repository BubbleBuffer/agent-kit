# workspace

The split tree of panes beside the chat: the tree and its dividers, pane
chrome (tabs, maximise, close, the + menu), docking by drag with the five-zone
preview, collapse to a 28 px edge tab and the size-class behaviour (column of
tabs when medium, a full-screen sheet when compact).

Mockup parts: scene D and the "Workspace" and "Collapse and docking"
sections of `NOTES.md`; `.ws-*`, `.pane*`, `.dock-*`, `.edge-tab` in
`app.css`. Pane minimums and the edge tab width are `KitLayout` tokens. The
kit owns the tree; the host supplies what a pane shows.

Add a widget here as its own file, export it from `workspace.dart`, and add a
gallery specimen and a golden (see `docs/agent-kit.md`).
