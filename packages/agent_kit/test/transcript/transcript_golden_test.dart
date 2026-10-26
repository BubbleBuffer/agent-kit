// Golden screenshots of the transcript widgets at 390 and 1000 px, light and
// dark: the mockup's turn (user, plan, prose, activity with an open exec,
// edits, return line) and every other state. CI renders them; compare with
// lab/design/scratch-skin/shots/. Re-render with
// `flutter test --tags golden --update-goldens` or the CI dispatch.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

/// The list's column: 16 px gutter, content at most 720 px wide, items
/// separated by [gaps] (the turn gap is 28, 22 when compact).
class _Sheet extends StatelessWidget {
  const _Sheet(this.children);

  /// Widgets and the gap above each (null for the first).
  final List<(double?, Widget)> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.only(top: 28, bottom: 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 752),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (gap, child) in children) ...[
                if (gap != null) SizedBox(height: gap),
                child,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _turn() => _Sheet([
  (null, UserBubble(userMessage())),
  (28, const PlanChecklist(planItems, initiallyOpen: true)),
  (28, AssistantProse(assistantMessage())),
  (
    12,
    ActivityGroupView(
      activityGroup(),
      initiallyOpen: true,
      initiallyOpenRow: 'r5',
      onOpenOutput: (_) {},
      onOpenChild: (_) {},
    ),
  ),
  (
    12,
    FileEditRow(
      modifiedEdit(),
      initiallyOpen: true,
      onReviewDiff: () {},
      onUndo: () {},
    ),
  ),
  (6, FileEditRow(createdEdit(), onOpen: () {}, onUndo: () {})),
  (28, ReturnLine(childResult, onOpen: (_) {})),
]);

Widget _states() {
  final running = ActivityGroup(
    id: 'g-run',
    at: t0,
    rows: [
      const ThinkingRow(id: 't1', streaming: true),
      ToolRow(
        id: 'x1',
        name: 'read',
        kind: ToolKind.read,
        target: 'usage/mod.rs',
        state: WorkState.done,
        meta: '212 lines',
      ),
      const ToolRow(
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
  final mixed = ActivityGroup(
    id: 'g-mix',
    at: t0,
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
      ToolRow(
        id: 'm3',
        name: 'bash',
        kind: ToolKind.exec,
        target: 'cargo check',
        state: WorkState.done,
        exitCode: 0,
        meta: '3.1s',
      ),
    ],
  );
  final deleted = FileEdit(
    id: 'e3',
    diff: FileDiff(
      path: 'crates/bubblepaw-host/src/usage/legacy.rs',
      change: FileChange.deleted,
      hunks: [
        DiffHunk(
          oldStart: 1,
          newStart: 0,
          lines: [
            const DiffLine(DiffOp.del, 'pub fn legacy() {}'),
            const DiffLine(DiffOp.del, ''),
          ],
        ),
      ],
    ),
  );
  return _Sheet([
    (null, const PlanChecklist(planItems)),
    (28, ActivityGroupView(running, initiallyOpen: true)),
    (12, ActivityGroupView(activityGroup(), initiallyOpen: false)),
    (
      12,
      ActivityGroupView(
        activityGroup(),
        initiallyOpen: true,
        initiallyOpenRow: 'r1',
      ),
    ),
    (12, ActivityGroupView(mixed, initiallyOpen: true)),
    (
      12,
      FileEditRow(
        modifiedEdit(undone: true),
        onReviewDiff: () {},
        onUndo: () {},
      ),
    ),
    (6, FileEditRow(deleted, onReviewDiff: () {}, onUndo: () {})),
    (28, const SystemLineView(SystemLine(id: 's', text: 'Context compacted'))),
    for (final tone in NoticeTone.values)
      (
        12,
        NoticeLineView(
          NoticeLine(id: tone.name, text: 'A ${tone.name} notice', tone: tone),
        ),
      ),
    (28, InterruptedNotice(onResume: () {})),
    (
      12,
      ReturnLine(
        const ChildResult(
          id: 'c2',
          childId: 'child-9a1f',
          task: 'Survey quota handling in Codex',
          state: WorkState.failed,
        ),
        onOpen: (_) {},
      ),
    ),
    (
      28,
      const CodeBlock(
        'fn main() { println!("a long line that scrolls sideways instead of wrapping, so it runs past the edge"); }',
        language: 'rust',
      ),
    ),
    (28, Center(child: JumpToLatestButton(onTap: () {}))),
  ]);
}

void main() {
  const heights = {
    ('turn', 390): 2500.0,
    ('turn', 1000): 2000.0,
    ('states', 390): 2900.0,
    ('states', 1000): 2300.0,
  };
  final sheets = <String, Widget Function()>{'turn': _turn, 'states': _states};
  for (final entry in sheets.entries) {
    for (final width in [390, 1000]) {
      for (final brightness in Brightness.values) {
        final name = 'transcript_${entry.key}_${width}_${brightness.name}';
        testWidgets(name, (tester) async {
          await pumpTranscript(
            tester,
            entry.value(),
            brightness: brightness,
            width: width.toDouble(),
            height: heights[(entry.key, width)]!,
          );
          await expectLater(
            find.byType(WidgetsApp),
            matchesGoldenFile('../goldens/$name.png'),
          );
        });
      }
    }
  }
}
