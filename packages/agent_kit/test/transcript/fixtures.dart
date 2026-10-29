// Transcript fixtures: the "Quota bar flickers on reconnect" turn of the
// mockup, built from agent_kit_core's items.

import 'package:agent_kit_core/agent_kit_core.dart';

final t0 = DateTime.utc(2026, 10, 26, 9);

const execOutput = [
  '   Compiling harbor-runtime v0.2.1 (crates/harbor-runtime)',
  '    Finished `test` profile [unoptimized + debuginfo] in 6.42s',
  '     Running unittests src/lib.rs',
  '',
  'running 14 tests',
  'test usage::tests::merge_adds_turn_tokens ... ok',
  'test usage::tests::percent_rounds_down ... ok',
  'test usage::tests::replay_skips_partial_turns ... ok',
  'test usage::tests::reset_clears_window ... ok',
  'test usage::tests::snapshot_survives_reconnect ... FAILED',
  'test usage::tests::stale_flag_clears_on_update ... FAILED',
  'test usage::tests::unknown_model_uses_default ... ok',
  'test usage::tests::window_rolls_at_midnight ... ok',
  'test usage::tests::zero_is_not_unknown ... ok',
  '',
  'failures:',
  '    usage::tests::snapshot_survives_reconnect',
  '    usage::tests::stale_flag_clears_on_update',
  '',
  'test result: FAILED. 12 passed; 2 failed; 0 ignored',
];

UserMessage userMessage() => UserMessage(
  id: 'u1',
  at: t0,
  text:
      'The quota bar in the web view drops to 0% and jumps back every time '
      'the socket reconnects. Keep the last known figure instead. Check how '
      'Codex and Claude Code handle it first.',
  refs: const [
    KitRef(kind: 'file', id: 'f1', label: 'usage/mod.rs'),
    KitRef(kind: 'file', id: 'f2', label: 'web/src/quota-bar.tsx'),
  ],
);

const proseMarkdown = '''
Both tools hold the last figure through a reconnect. Codex keeps the last rate-limit header and marks it stale; Claude Code just holds it. Ours resets `last` on close.

I'll follow Codex, so the bar never shows a false zero:

- keep `last` on disconnect instead of resetting it;
- set `stale_since` until the first update after reconnect;
- dim the bar while the figure is **stale**, never hide it.

```rust
pub fn is_stale(&self) -> bool {
    self.stale_since.is_some()
}
```
''';

AssistantMessage assistantMessage() =>
    const AssistantMessage(id: 'm1', markdown: proseMarkdown);

ToolOutput failingOutput() =>
    ToolOutput(text: execOutput.join('\n'), totalBytes: 2150, totalLines: 20);

ToolRow execRow({WorkState state = WorkState.failed, int? exitCode = 101}) =>
    ToolRow(
      id: 'r5',
      name: 'bash',
      kind: ToolKind.exec,
      target: 'cargo test -p harbor-runtime usage',
      state: state,
      exitCode: exitCode,
      output: failingOutput(),
      startedAt: t0.add(const Duration(seconds: 6)),
      endedAt: t0.add(const Duration(seconds: 48)),
    );

ActivityGroup activityGroup() => ActivityGroup(
  id: 'a1',
  at: t0,
  rows: [
    const ThinkingRow(
      id: 'r1',
      text:
          'Compared Codex and Claude Code usage handling\n'
          'Both keep the last figure; Codex also marks it stale.',
      durationMs: 6000,
    ),
    ToolRow(
      id: 'r2',
      name: 'read',
      kind: ToolKind.read,
      target: 'usage/mod.rs',
      state: WorkState.done,
      meta: '212 lines',
      startedAt: t0.add(const Duration(seconds: 6)),
      endedAt: t0.add(const Duration(seconds: 7)),
    ),
    ToolRow(
      id: 'r3',
      name: 'grep',
      kind: ToolKind.search,
      target: 'reset|on_close · crates/',
      state: WorkState.done,
      meta: '9 hits',
      startedAt: t0.add(const Duration(seconds: 7)),
      endedAt: t0.add(const Duration(seconds: 8)),
    ),
    ToolRow(
      id: 'r4',
      name: 'read',
      kind: ToolKind.read,
      target: 'web/src/quota-bar.tsx',
      state: WorkState.done,
      meta: '88 lines',
      startedAt: t0.add(const Duration(seconds: 8)),
      endedAt: t0.add(const Duration(seconds: 9)),
    ),
    execRow(),
    const SpawnRow(
      id: 'r6',
      childId: 'child-c7e2',
      task: 'Survey quota handling in Codex',
    ),
  ],
);

DiffLine _ctx(String t) => DiffLine(DiffOp.ctx, t);
DiffLine _add(String t) => DiffLine(DiffOp.add, t);
DiffLine _del(String t) => DiffLine(DiffOp.del, t);

/// +8 −3 in two hunks.
FileEdit modifiedEdit({bool undone = false}) => FileEdit(
  id: 'e1',
  undone: undone,
  diff: FileDiff(
    path: 'crates/harbor-runtime/src/usage/mod.rs',
    hunks: [
      DiffHunk(
        oldStart: 24,
        newStart: 24,
        lines: [
          _ctx('pub struct UsageState {'),
          _ctx('    pub window: QuotaWindow,'),
          _del('    pub last: UsageSnapshot,'),
          _add('    pub last: Option<UsageSnapshot>,'),
          _add('    pub stale_since: Option<Timestamp>,'),
          _add('    pub dirty: bool,'),
          _ctx('}'),
        ],
      ),
      DiffHunk(
        oldStart: 182,
        newStart: 183,
        lines: [
          _ctx('    pub fn on_disconnect(&mut self, now: Timestamp) {'),
          _del('        self.last = UsageSnapshot::default();'),
          _del('        self.dirty = true;'),
          _add('        self.stale_since = Some(now);'),
          _ctx('    }'),
          _add(''),
          _add('    pub fn is_stale(&self) -> bool {'),
          _add('        self.stale_since.is_some()'),
          _add('    }'),
          _ctx('}'),
        ],
      ),
    ],
  ),
);

FileEdit createdEdit() => FileEdit(
  id: 'e2',
  diff: FileDiff(
    path: 'crates/harbor-runtime/tests/quota_reconnect.rs',
    change: FileChange.created,
    hunks: [
      DiffHunk(
        oldStart: 0,
        newStart: 1,
        lines: [for (var i = 1; i <= 41; i++) _add('// line $i')],
      ),
    ],
  ),
);

const planItems = [
  PlanItem(
    id: 'p1',
    text: 'Survey Codex and Claude Code',
    state: PlanItemState.done,
  ),
  PlanItem(
    id: 'p2',
    text: 'Keep `last` on disconnect',
    state: PlanItemState.done,
  ),
  PlanItem(
    id: 'p3',
    text: 'Mark it stale until the next update',
    state: PlanItemState.now,
  ),
  PlanItem(id: 'p4', text: 'Dim the quota bar while stale'),
  PlanItem(id: 'p5', text: 'Run the usage tests'),
];

const childResult = ChildResult(
  id: 'c1',
  childId: 'child-c7e2',
  task: 'Map UsageState transitions',
  result: 'Four transitions; only on_close resets `last`.',
);

/// A transcript of [turns] user/assistant pairs, for scrolling tests.
List<TranscriptItem> longTranscript(int turns) => [
  for (var i = 0; i < turns; i++) ...[
    UserMessage(id: 'u$i', text: 'Question number $i about the quota bar.'),
    AssistantMessage(
      id: 'a$i',
      markdown:
          'Answer $i. ${'The quota bar keeps its last figure through a reconnect. ' * 3}',
    ),
  ],
];
