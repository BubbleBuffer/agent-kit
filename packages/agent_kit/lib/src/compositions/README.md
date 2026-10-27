# compositions

Two widgets that turn an `AgentBackend` into a working agent chat. They are
the only widgets in the kit that call a backend; every other widget takes
models and callbacks.

## AgentChatPane

`AgentChatPane(backend: ..., chatId: ...)` shows one chat.

- It owns a `ChatFeed`, closes it on dispose, and closes the old feed and
  opens the next when `chatId` (or the backend) changes. The draft in the
  composer is cleared on a switch.
- Top to bottom: `ChatHeader`, the crew strip (when it has agents or jobs
  and `showCrewStrip` is on), the transcript, then the dock: pending
  approvals, the pending question, queued inputs, one error line, the composer.
- Commands: send, steer or queue (a backend without `steer` queues), send now,
  edit and remove a queued input, approve, approve for session, deny with a
  reason, answer a question, stop, undo an edit, resume an interrupted run,
  switch model or profile, fork and archive (from the header menu).
- A failed command shows one dismissible line above the composer (a `KitError`
  shows its message). A failed send puts the text back in the composer. There
  is no modal.
- Controls a backend lacks are left out, by `KitCapabilities`: send now, queue
  edit, the Steer/Queue switch, the model and profile picks, undo, resume,
  questions, fork and archive. The header's menu button goes with its last
  item.
- Loading shows "Loading…". A failed load shows the message and Retry.
- The snapshot's plan draws as the transcript's plan checklist. A resolved
  question draws its `QuestionAnswerLines` after the last item that was
  there when it was asked. A run that ended `interrupted` ends the transcript
  with `InterruptedNotice`.
- `sideBuilder` adds the column beside the transcript at the expanded size
  (the crew ledger). The pane lays the grid out as the mockup does: left gutter
  of two thirds of the free width (at least 16 px), the content column, 40 px,
  252 px of side column.

Not in the pane: older-history paging (the feed holds the whole transcript),
rename, per-model usage (the host supplies it to the workbench).

## AgentWorkbench

`AgentWorkbench(backend: ..., initialChatId: ...)` is the whole app.

- `RailLayout` and `SessionRail` list the backend's chats, grouped by day
  (`groupSessions`); the list refreshes when the open chat's status or title
  changes. The new-chat button creates a chat through the backend.
- The sheet holds an `AgentChatPane`. The crew shows as `CrewLedger` (with
  `UsageByModel` when `modelUsage` is given) when the whole width is expanded
  and no workspace is open, else as the strip under the header.
- The workspace is optional: pass `workspaceController`, `workspaceKinds` and
  `workspacePaneBuilder`. The header gets the toggle. Beside the chat when
  the width beside the rail is expanded (chat 44%, 444 to 584 px) or medium
  (workspace 40%, 240 to 420 px); a full-screen sheet over the chat when it is
  compact.
- With the `context` capability the + menu gets a Context kind. The
  compaction marker's View and the header meter open the Context pane (they
  add it when absent and bring it forward on Now); `AgentContextPane` loads
  the structure and answers the History and summary loaders.
- Layout follows the widget's own constraints through `SizeClass`, never the
  window.
- Host data stays parameters: `modelUsage`, `detailFor`, the pane builder,
  and the open-file, open-agent and review-diff callbacks.

Add a composition as its own file, export it from `compositions.dart`, and add
a gallery scene and a golden (see `docs/agent-kit.md`).
