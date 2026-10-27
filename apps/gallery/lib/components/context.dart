// Context and child-question specimens for the Components scene: the meter,
// the compaction marker in each state, the Context pane at two widths and on
// each tab, and the child question row in each state, on hand-built
// `agent_kit_core` values (the "Quota bar flickers on reconnect" chat).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

final _view = quotaContextView();
final _details = quotaContextDetails();
final _asked = DateTime.utc(2025, 12, 29, 10);
final _now = _asked.add(const Duration(seconds: 40));

/// A deterministic stand-in for the backend's `loadHistoryRange`.
Future<HistoryPage> _history(int first, int last) async => HistoryPage(
  firstSeq: first,
  lastSeq: last,
  messages: [
    for (var seq = first; seq <= last; seq++)
      HistoryMessage(
        seq: seq,
        role: seq % 5 == 1
            ? HistoryRole.user
            : seq % 3 == 0
            ? HistoryRole.tool
            : HistoryRole.agent,
        preview: seq % 3 == 0
            ? 'read · usage/mod.rs'
            : 'Keeping the last figure on disconnect, behind an Option.',
        tokens: 40 + seq * 3,
      ),
  ],
);

Future<ContextSummary> _summary(String id) async =>
    _details.summary(id) ?? _details.summaries.first;

ChildQuestionItem _item(
  String id, {
  required String task,
  required String text,
  List<String> options = const [],
  ChildQuestionState state = ChildQuestionState.pending,
  String? answer,
  AnsweredBy? by,
}) => ChildQuestionItem(
  id: 'childq:$id',
  task: task,
  question: ChildQuestion(
    id: id,
    childId: 'child-$id',
    text: text,
    options: options,
    askedAt: _asked,
    state: state,
    answer: answer,
    answeredAt: answer == null ? null : _asked.add(const Duration(seconds: 20)),
    answeredBy: by,
  ),
);

/// The context pane, the compaction marker and the child question row.
class ContextSpecimens extends StatelessWidget {
  const ContextSpecimens({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return SizedBox(
      width: double.infinity,
      child: SizeClassBuilder(
        builder: (context, sizeClass) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Context', style: ts(t.typeScale.h3, t.ink)),
            const _Sub('Context meter (header): plain readout and button'),
            Wrap(
              spacing: 24,
              children: [
                const ContextMeter(fraction: .38),
                ContextMeter(fraction: .38, onTap: () {}),
              ],
            ),
            const _Sub('Context meter with segments and the apply cap'),
            ContextMeterBar(view: _view),
            const _Sub('Meter when the host records no block sizes'),
            ContextMeterBar(
              view: ContextView(
                window: 128000,
                applyCap: 84000,
                responseReserve: 44000,
                blocks: const [
                  ContextBlock(kind: ContextBlockKind.opening),
                  ContextBlock(kind: ContextBlockKind.rawSuffix),
                ],
              ),
            ),
            const _Sub('Compaction marker: done, running, failed'),
            CompactionMarker(
              const CompactionItem(
                id: 'm1',
                episodesSummarized: 3,
                tokensBefore: 41000,
                tokensAfter: 9000,
              ),
              onView: () {},
            ),
            CompactionMarker(
              const CompactionItem(
                id: 'm2',
                state: CompactionState.running,
                detail: 'summarizing episode 4 · 24k',
              ),
              onView: () {},
            ),
            CompactionMarker(
              const CompactionItem(
                id: 'm3',
                state: CompactionState.failed,
                detail: 'the previous context is unchanged',
              ),
              onView: () {},
            ),
            const _Sub('Context pane, wide (summary beside the list)'),
            _Frame(
              height: 760,
              width: 760,
              child: ContextPane(
                view: _view,
                details: _details,
                loadHistory: _history,
                loadSummary: _summary,
                now: _now,
                initialSummaryId: 'sum-ch1',
              ),
            ),
            const _Sub('Context pane, narrow'),
            _Frame(
              height: 640,
              width: 420,
              child: ContextPane(
                view: _view,
                details: _details,
                loadHistory: _history,
                loadSummary: _summary,
                now: _now,
              ),
            ),
            const _Sub('Context pane, narrow, summary open'),
            _Frame(
              height: 760,
              width: 420,
              child: ContextPane(
                view: _view,
                details: _details,
                loadHistory: _history,
                loadSummary: _summary,
                now: _now,
                initialSummaryId: 'sum-e4',
              ),
            ),
            const _Sub('Context pane, History'),
            _Frame(
              height: 760,
              width: 680,
              child: ContextPane(
                view: _view,
                details: _details,
                loadHistory: _history,
                now: _now,
                initialTab: ContextTab.history,
              ),
            ),
            const _Sub('Context pane, Compactions'),
            _Frame(
              height: 760,
              width: 680,
              child: ContextPane(
                view: _view,
                details: _details,
                now: _now,
                initialTab: ContextTab.compactions,
              ),
            ),
            SizedBox(height: t.spacing.xl),
            Text('Child questions', style: ts(t.typeScale.h3, t.ink)),
            const _Sub('Asking parent in the crew strip and the ledger'),
            CrewStrip(agents: [_asking], now: _now),
            CrewLedger(agents: [_asking], now: _now),
            const _Sub('Pending'),
            ChildQuestionRow(
              _item(
                'k2',
                task: 'Trace socket reconnect in the web client',
                text:
                    'Is the reconnect handled in web/src/ws.ts, or in the '
                    'shared client?',
                options: const ['ws.ts', 'Shared client'],
              ),
              now: _now,
              onOpenChild: (_) {},
              onAnswer: (_, _, _) {},
            ),
            const _Sub('Pending, composing'),
            ChildQuestionRow(
              _item(
                'k3',
                task: 'Trace socket reconnect in the web client',
                text:
                    'Is the reconnect handled in web/src/ws.ts, or in the '
                    'shared client?',
                options: const ['ws.ts', 'Shared client'],
              ),
              now: _now,
              onOpenChild: (_) {},
              onAnswer: (_, _, _) {},
              initialComposing: true,
            ),
            const _Sub('Pending, the backend cannot take a user answer'),
            ChildQuestionRow(
              _item(
                'k4',
                task: 'Survey quota handling in Codex',
                text: 'Which rate-limit path should I read?',
              ),
              now: _now,
              onOpenChild: (_) {},
            ),
            const _Sub('Answered by the agent'),
            ChildQuestionRow(
              _item(
                'k1',
                task: 'Survey quota handling in Codex',
                text:
                    'Codex has two rate-limit paths, the CLI and the app '
                    'server. Which one should I read?',
                options: const ['App server', 'CLI', 'Both'],
                state: ChildQuestionState.answered,
                answer:
                    'App server only. The CLI path is a thin wrapper '
                    'around it.',
                by: AnsweredBy.parent,
              ),
              now: _now,
              onOpenChild: (_) {},
            ),
            const _Sub('Answered by you'),
            ChildQuestionRow(
              _item(
                'k5',
                task: 'Trace socket reconnect in the web client',
                text: 'Is the reconnect handled in ws.ts?',
                state: ChildQuestionState.answered,
                answer: 'Shared client, see web/src/net.ts.',
                by: AnsweredBy.user,
              ),
              now: _now,
            ),
            const _Sub('Cancelled'),
            ChildQuestionRow(
              _item(
                'k6',
                task: 'Trace socket reconnect in the web client',
                text: 'Is the reconnect handled in ws.ts?',
                state: ChildQuestionState.cancelled,
              ),
              now: _now,
            ),
          ],
        ),
      ),
    );
  }
}

final _asking = ChildAgent(
  id: 'child-k2',
  task: 'Trace socket reconnect in the web client',
  state: WorkState.waitingForAnswer,
  startedAt: _asked.subtract(const Duration(minutes: 2)),
  pendingQuestion: ChildQuestion(
    id: 'k2',
    childId: 'child-k2',
    text: 'Is the reconnect handled in web/src/ws.ts, or in the shared client?',
    askedAt: _asked,
  ),
);

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(top: t.spacing.lg, bottom: t.spacing.sm),
      child: Text(text, style: ts(t.typeScale.uiSmall, t.muted)),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.height,
    required this.width,
  });

  final Widget child;
  final double height, width;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: t.seam),
          borderRadius: BorderRadius.circular(t.radii.md),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radii.md),
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }
}
