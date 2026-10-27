# workspace

The split tree of panes beside the chat: the tree and its dividers, pane
chrome (tabs, maximise, close, the + menu), docking by drag with the five-zone
preview, collapse to a 28 px edge tab and the size-class behaviour (column of
tabs when medium, a full-screen sheet when compact).

Mockup parts: scene D and the "Workspace" and "Collapse and docking"
sections of `NOTES.md`; `.ws-*`, `.pane*`, `.dock-*`, `.edge-tab` in
`app.css`. Pane minimums and the edge tab width are `KitLayout` tokens. The
kit owns the tree; the host supplies what a pane shows.

`WorkspaceKind.context` (id `context`) is the kind the workbench builds as the Context pane itself.

Add a widget here as its own file, export it from `workspace.dart`, and add a
gallery specimen and a golden (see `docs/agent-kit.md`).

## Files

- `workspace_model.dart`: the immutable split tree and its pure operations
  (split, close, dock, resize, collapse, restore, maximise), with JSON.
- `workspace_geometry.dart`: pure layout of the tree into rects, dividers and
  edge tabs; minimums are 200x120 and a pane that cannot fit folds to a tab.
- `workspace_controller.dart`: a `ChangeNotifier` holding the layout.
- `agent_workspace.dart`: `AgentWorkspace`, the widget. The host passes a
  `paneBuilder` keyed by tab kind and id, a `kinds` list for the + menu, and
  `open` for the compact sheet.


## Edge tabs and the add button

An edge tab of an auto-folded pane is a button: tapping it unfolds the pane (`WorkspaceController.unfold`), folding the smallest visible sibling instead. The `+` shows only on the last pane (tree order) that is big enough to split.
