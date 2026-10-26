# compositions

The widgets that put the groups together: `AgentWorkbench` (rail, chat
sheet, ledger, optional workspace; scenes A, C and D) and `AgentChatPane`
(one chat with crew strip, for a docked pane; scene B). They own the size
class of their area and hand it down with `SizeClassBuilder`.

Compositions only arrange widgets from the other folders; they hold no
drawing of their own. Input is an `AgentBackend` (through `ChatFeed`).

Add a widget here as its own file, export it from `compositions.dart`, and
add a gallery scene and a golden (see `docs/agent-kit.md`).
