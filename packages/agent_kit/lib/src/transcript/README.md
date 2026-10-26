# transcript

Everything drawn inside the transcript sheet: user and assistant messages,
the activity group and its evidence rows (think, read, grep, exec, spawn), the
output block with its 12-line clamp, file-edit rows, the diff view, child
results, notices and the plan list.

Mockup parts: `.prose`, `.msg`, `.activity` and `.ev-*` rows, `.out`,
`.edit`, `.diff`, `.plan-list` in `app.css`; the transcript builder in
`app.js`. Input is `ChatSnapshot.items` from `agent_kit_core`.

Add a widget here as its own file, export it from `transcript.dart`, and add
a gallery specimen and a golden (see `docs/agent-kit.md`).
