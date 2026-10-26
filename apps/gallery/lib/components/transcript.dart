// Transcript specimens for the Components scene: every transcript widget in
// each of its states, on hand-built `agent_kit_core` items (the "Quota bar
// flickers on reconnect" turn of the mockup).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

/// Every widget of the transcript group, in each state. Lays out by its own
/// width, so the gallery's width slider shows the size classes.
class TranscriptSpecimens extends StatelessWidget {
  const TranscriptSpecimens({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SizeClassBuilder(
      builder: (context, sizeClass) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: context.bb.spacing.xl),
          Text(
            'Transcript',
            style: ts(context.bb.typeScale.h3, context.bb.ink),
          ),
          const _Sub(
            'Transcript list (follows the tail; scroll up for the button)',
          ),
          _Frame(
            height: 380,
            child: TranscriptList(
              items: _listItems(),
              actions: TranscriptActions(
                onReviewDiff: (_) {},
                onUndo: (_) {},
                onOpenFile: (_) {},
                onOpenOutput: (_) {},
                onOpenChild: (_) {},
              ),
              trailing: InterruptedNotice(onResume: () {}),
            ),
          ),
          const _Sub('Jump to latest'),
          Align(
            alignment: Alignment.centerLeft,
            child: JumpToLatestButton(onTap: () {}),
          ),
          const _Sub('User message, with context chips'),
          UserBubble(_user, onRefTap: (_) {}),
          const _Sub('Assistant prose (default markdown renderer)'),
          AssistantProse(_assistant),
          const _Sub('Code block'),
          const CodeBlock(
            'pub fn is_stale(&self) -> bool {\n    self.stale_since.is_some()\n}',
            language: 'rust',
          ),
          const _Sub('System and notice lines'),
          const SystemLineView(SystemLine(id: 's', text: 'Context compacted')),
          for (final tone in NoticeTone.values) ...[
            const SizedBox(height: 8),
            NoticeLineView(
              NoticeLine(
                id: tone.name,
                text: 'A ${tone.name} notice',
                tone: tone,
              ),
            ),
          ],
          const _Sub('Activity group: collapsed'),
          ActivityGroupView(_activity(), initiallyOpen: false),
          const _Sub('Activity group: open, exec output clamped'),
          ActivityGroupView(
            _activity(),
            initiallyOpen: true,
            initiallyOpenRow: 'r5',
            onOpenOutput: (_) {},
            onOpenChild: (_) {},
          ),
          const _Sub('Activity group: running, thinking streaming'),
          ActivityGroupView(_running(), initiallyOpen: true),
          const _Sub(
            'Activity group: thinking text open, failed and cancelled rows',
          ),
          ActivityGroupView(
            _activity(),
            initiallyOpen: true,
            initiallyOpenRow: 'r1',
          ),
          const SizedBox(height: 12),
          ActivityGroupView(_mixed(), initiallyOpen: true),
          const _Sub('Exec output, short'),
          const ExecOutput(
            output: ToolOutput(text: 'Finished `dev` profile in 0.4s\n'),
            exitCode: 0,
          ),
          const _Sub('Files / edit rows'),
          FileEditRow(
            _modified(),
            initiallyOpen: true,
            onReviewDiff: () {},
            onUndo: () {},
          ),
          const SizedBox(height: 6),
          FileEditRow(_created(), onOpen: () {}, onUndo: () {}),
          const SizedBox(height: 6),
          FileEditRow(_modified(undone: true), onReviewDiff: () {}),
          const _Sub('Diff view'),
          DiffView(_modified().diff),
          const _Sub('Plan: collapsed and open'),
          const PlanChecklist(_plan),
          const SizedBox(height: 12),
          const PlanChecklist(_plan, initiallyOpen: true),
          const _Sub('Return line and interrupted notice'),
          ReturnLine(_childResult, onOpen: (_) {}),
          const SizedBox(height: 12),
          ReturnLine(_childFailed, onOpen: (_) {}),
          const SizedBox(height: 12),
          InterruptedNotice(onResume: () {}),
        ],
      ),
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(top: t.spacing.lg, bottom: t.spacing.sm),
      child: Text(text, style: ts(t.typeScale.uiSmall, t.faint)),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radii.md),
          border: Border.all(color: t.seam),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radii.md),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- fixtures

final _t0 = DateTime.utc(2026, 10, 26, 9);

final _user = UserMessage(
  id: 'u1',
  text:
      'The quota bar in the web view drops to 0% and jumps back every time '
      'the socket reconnects. Keep the last known figure instead. Check how '
      'Codex and Claude Code handle it first.',
  refs: const [
    KitRef(kind: 'file', id: 'f1', label: 'usage/mod.rs'),
    KitRef(kind: 'file', id: 'f2', label: 'web/src/quota-bar.tsx'),
  ],
);

const _assistant = AssistantMessage(
  id: 'm1',
  markdown: '''
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
''',
);

const _outputLines = [
  '   Compiling bubblepaw-host v0.2.1 (crates/bubblepaw-host)',
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

ActivityGroup _activity() => ActivityGroup(
  id: 'a1',
  at: _t0,
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
      startedAt: _t0.add(const Duration(seconds: 6)),
      endedAt: _t0.add(const Duration(seconds: 7)),
    ),
    ToolRow(
      id: 'r3',
      name: 'grep',
      kind: ToolKind.search,
      target: 'reset|on_close · crates/',
      state: WorkState.done,
      meta: '9 hits',
      startedAt: _t0.add(const Duration(seconds: 7)),
      endedAt: _t0.add(const Duration(seconds: 8)),
    ),
    ToolRow(
      id: 'r4',
      name: 'read',
      kind: ToolKind.read,
      target: 'web/src/quota-bar.tsx',
      state: WorkState.done,
      meta: '88 lines',
      startedAt: _t0.add(const Duration(seconds: 8)),
      endedAt: _t0.add(const Duration(seconds: 9)),
    ),
    ToolRow(
      id: 'r5',
      name: 'bash',
      kind: ToolKind.exec,
      target: 'cargo test -p bubblepaw-host usage',
      state: WorkState.failed,
      exitCode: 101,
      output: ToolOutput(
        text: _outputLines.join('\n'),
        totalBytes: 2150,
        totalLines: 20,
      ),
      startedAt: _t0.add(const Duration(seconds: 6)),
      endedAt: _t0.add(const Duration(seconds: 48)),
    ),
    const SpawnRow(
      id: 'r6',
      childId: 'child-c7e2',
      task: 'Survey quota handling in Codex',
    ),
  ],
);

ActivityGroup _running() => ActivityGroup(
  id: 'g-run',
  at: _t0,
  rows: const [
    ThinkingRow(id: 't1', streaming: true),
    ToolRow(
      id: 'x1',
      name: 'read',
      kind: ToolKind.read,
      target: 'usage/mod.rs',
      state: WorkState.done,
      meta: '212 lines',
    ),
    ToolRow(
      id: 'x2',
      name: 'bash',
      kind: ToolKind.exec,
      target: 'cargo test -p bubblepaw-host usage',
      meta: '12s',
      output: ToolOutput(
        text: '   Compiling bubblepaw-host v0.2.1\nrunning 14 tests\n',
      ),
    ),
  ],
);

ActivityGroup _mixed() => ActivityGroup(
  id: 'g-mix',
  at: _t0,
  rows: const [
    ToolRow(
      id: 'm1',
      name: 'web',
      kind: ToolKind.web,
      target: 'docs.example/rate-limits',
      state: WorkState.failed,
      meta: 'timeout',
    ),
    ToolRow(
      id: 'm2',
      name: 'bash',
      kind: ToolKind.exec,
      target: 'cargo fmt',
      state: WorkState.cancelled,
    ),
  ],
);

FileEdit _modified({bool undone = false}) => FileEdit(
  id: 'e1',
  undone: undone,
  diff: FileDiff(
    path: 'crates/bubblepaw-host/src/usage/mod.rs',
    hunks: [
      DiffHunk(
        oldStart: 24,
        newStart: 24,
        lines: const [
          DiffLine(DiffOp.ctx, 'pub struct UsageState {'),
          DiffLine(DiffOp.ctx, '    pub window: QuotaWindow,'),
          DiffLine(DiffOp.del, '    pub last: UsageSnapshot,'),
          DiffLine(DiffOp.add, '    pub last: Option<UsageSnapshot>,'),
          DiffLine(DiffOp.add, '    pub stale_since: Option<Timestamp>,'),
          DiffLine(DiffOp.add, '    pub dirty: bool,'),
          DiffLine(DiffOp.ctx, '}'),
        ],
      ),
      DiffHunk(
        oldStart: 182,
        newStart: 183,
        lines: const [
          DiffLine(
            DiffOp.ctx,
            '    pub fn on_disconnect(&mut self, now: Timestamp) {',
          ),
          DiffLine(DiffOp.del, '        self.last = UsageSnapshot::default();'),
          DiffLine(DiffOp.del, '        self.dirty = true;'),
          DiffLine(DiffOp.add, '        self.stale_since = Some(now);'),
          DiffLine(DiffOp.ctx, '    }'),
          DiffLine(DiffOp.add, ''),
          DiffLine(DiffOp.add, '    pub fn is_stale(&self) -> bool {'),
          DiffLine(DiffOp.add, '        self.stale_since.is_some()'),
          DiffLine(DiffOp.add, '    }'),
          DiffLine(DiffOp.ctx, '}'),
        ],
      ),
    ],
  ),
);

FileEdit _created() => FileEdit(
  id: 'e2',
  diff: FileDiff(
    path: 'crates/bubblepaw-host/tests/quota_reconnect.rs',
    change: FileChange.created,
    hunks: [
      DiffHunk(
        oldStart: 0,
        newStart: 1,
        lines: [
          for (var i = 1; i <= 41; i++) DiffLine(DiffOp.add, '// line $i'),
        ],
      ),
    ],
  ),
);

const _plan = [
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

const _childResult = ChildResult(
  id: 'c1',
  childId: 'child-c7e2',
  task: 'Map UsageState transitions',
  result: 'Four transitions; only on_close resets `last`.',
);

const _childFailed = ChildResult(
  id: 'c2',
  childId: 'child-9a1f',
  task: 'Survey quota handling in Codex',
  state: WorkState.failed,
);

List<TranscriptItem> _listItems() => [
  _user,
  _assistant,
  _activity(),
  _modified(),
  _created(),
  _childResult,
  const NoticeLine(
    id: 'n1',
    text: 'The usage tests still fail.',
    tone: NoticeTone.warning,
  ),
];
