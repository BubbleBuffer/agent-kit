// Gallery entries of the chrome group: the session rail (column, sliding
// screen, hidden), the chat header in each status and width, the crew strip,
// the ledger, the context meter and the usage view. The data is the mockup's
// demo task ("Quota bar flickers on reconnect") with a fixed clock.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

final _now = DateTime(2026, 10, 26, 15);

final _chats = <ChatSummary>[
  ChatSummary(
    id: 'quota',
    title: 'Quota bar flickers on reconnect',
    status: ChatStatus.needsYou,
    updatedAt: _now.subtract(const Duration(minutes: 2)),
  ),
  ChatSummary(
    id: 'steer',
    title: 'Steer vs queue semantics',
    status: ChatStatus.running,
    runningChildren: 3,
    updatedAt: _now.subtract(const Duration(minutes: 20)),
  ),
  ChatSummary(
    id: 'fork',
    title: 'Compact before fork',
    updatedAt: _now.subtract(const Duration(minutes: 12)),
  ),
  ChatSummary(
    id: 'worktree',
    title: 'Child worktree retention',
    updatedAt: _now.subtract(const Duration(days: 1)),
  ),
  ChatSummary(
    id: 'wal',
    title: 'SQLite WAL growth on long runs',
    status: ChatStatus.failed,
    error: 'exit 101',
    updatedAt: _now.subtract(const Duration(days: 2)),
  ),
  ChatSummary(
    id: 'grouping',
    title: 'Session list grouping',
    updatedAt: _now.subtract(const Duration(days: 5)),
  ),
];

final _agents = <ChildAgent>[
  ChildAgent(
    id: 'survey',
    task: 'Survey quota handling in Codex',
    activity: 'read codex-rs/core/src/rate_limits.rs',
    toolCalls: 5,
    startedAt: _now.subtract(const Duration(minutes: 1, seconds: 4)),
  ),
  ChildAgent(
    id: 'map',
    task: 'Map UsageState transitions',
    state: WorkState.done,
    activity: 'read-only',
    toolCalls: 9,
    startedAt: _now.subtract(const Duration(minutes: 3)),
    endedAt: _now.subtract(const Duration(minutes: 1)),
  ),
];

final _jobs = <BackgroundJob>[
  BackgroundJob(
    id: 'test',
    command: 'cargo test -p bubblepaw-host usage',
    state: JobState.exited,
    exitCode: 101,
    summary: '2 failed',
    startedAt: _now.subtract(const Duration(seconds: 41)),
    endedAt: _now,
  ),
];

String? _detailFor(ChatSummary chat) => switch (chat.status) {
  ChatStatus.needsYou => 'edit approval',
  _ => railDetail(chat, _now),
};

String _agentTitle(ChildAgent agent) =>
    agent.id == 'survey' ? 'Survey quota' : 'Map transitions';

SessionRail _rail() => SessionRail(
  workspaceName: 'bubblepaw-base',
  groups: groupSessions(_chats, _now),
  selectedId: 'quota',
  detailFor: _detailFor,
  now: _now,
  initials: 'BC',
);

const _usage = Usage(
  contextTokens: 48640,
  contextLimit: 128000,
  inputTokens: 1100000,
  outputTokens: 140000,
);

const _models = <ModelUsage>[
  ModelUsage('deepseek-v4.1-flash', 960000),
  ModelUsage('gpt-6.1-sol', 280000),
  ModelUsage('gpt-6.1-nano', 4000),
];

/// Every chrome widget in each state.
class ChromeSpecimens extends StatelessWidget {
  const ChromeSpecimens({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label(
          'SessionRail: the 240 px column, and a sliding screen at 390 px',
        ),
        Wrap(
          spacing: t.spacing.xl,
          runSpacing: t.spacing.lg,
          children: [
            SizedBox(width: 240, height: 560, child: _rail()),
            const _SlidingRail(),
          ],
        ),
        SizedBox(height: t.spacing.xl),
        const _Label('Hidden rail: the header gets the show button'),
        const _HiddenRail(),
        SizedBox(height: t.spacing.xl),
        const _Label('ChatHeader at 1000 px: needs you, running, failed, done'),
        const _Headers(maxWidth: 1000),
        SizedBox(height: t.spacing.xl),
        const _Label(
          'ChatHeader at 390 px: tile, branch and meter label dropped',
        ),
        const _Headers(maxWidth: 390),
        SizedBox(height: t.spacing.xl),
        const _Label('CrewStrip at 1000 px and 390 px (scrolls sideways)'),
        _Boxed(
          maxWidth: 1000,
          child: CrewStrip(
            agents: _agents,
            jobs: _jobs,
            now: _now,
            agentTitle: _agentTitle,
          ),
        ),
        SizedBox(height: t.spacing.md),
        _Boxed(
          maxWidth: 390,
          child: CrewStrip(
            agents: _agents,
            jobs: _jobs,
            now: _now,
            agentTitle: _agentTitle,
          ),
        ),
        SizedBox(height: t.spacing.xl),
        const _Label('CrewLedger ("Still running") and UsageByModel'),
        Wrap(
          spacing: t.spacing.xl,
          runSpacing: t.spacing.lg,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 252,
              child: CrewLedger(agents: _agents, jobs: _jobs, now: _now),
            ),
            const SizedBox(
              width: 252,
              child: UsageByModel(models: _models, usage: _usage),
            ),
          ],
        ),
        SizedBox(height: t.spacing.xl),
        const _Label('ContextMeter: 12%, 38%, 96%, bar only'),
        const Wrap(
          spacing: 24,
          children: [
            ContextMeter(fraction: .12),
            ContextMeter(fraction: .38),
            ContextMeter(fraction: .96),
            ContextMeter(fraction: .38, showLabel: false),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.sm),
      child: Text(
        text,
        style: ts(const TypeSpec(12, 16, 400), t.faint, mono: true),
      ),
    );
  }
}

/// Gives [child] up to [maxWidth], at the top left.
class _Boxed extends StatelessWidget {
  const _Boxed({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.seam),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Headers extends StatelessWidget {
  const _Headers({required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return _Boxed(
      maxWidth: maxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatHeader(
            chat: _chats[0],
            branch: 'quota-bar-reconnect',
            worktree: '/work/bubblepaw-base-quota',
            usage: _usage,
            workspaceShown: true,
            onToggleWorkspace: () {},
            menuItems: [
              ChromeMenuItem('Rename', () {}),
              ChromeMenuItem('Archive', () {}, separatorBefore: true),
            ],
          ),
          ChatHeader(
            chat: _chats[1],
            statusDetail: '3 agents',
            branch: 'main',
            usage: _usage,
            onToggleWorkspace: () {},
          ),
          ChatHeader(
            chat: _chats[4],
            branch: 'wal-growth',
            usage: const Usage(contextTokens: 120000, contextLimit: 128000),
          ),
          ChatHeader(
            chat: ChatSummary(
              id: 'done',
              title: 'A very long title that is cut where the room ends',
              status: ChatStatus.done,
            ),
            branch: 'release',
            usage: _usage,
            onToggleWorkspace: () {},
          ),
        ],
      ),
    );
  }
}

/// A compact-width layout with its sliding rail open.
class _SlidingRail extends StatefulWidget {
  const _SlidingRail();

  @override
  State<_SlidingRail> createState() => _SlidingRailState();
}

class _SlidingRailState extends State<_SlidingRail> {
  final _controller = RailController(open: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return SizedBox(
      width: 390,
      height: 560,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.seam),
        ),
        child: RailLayout(
          controller: _controller,
          rail: _rail(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ChatHeader(chat: _chats[0], branch: 'main', usage: _usage),
          ),
        ),
      ),
    );
  }
}

/// A medium-width layout with the rail column folded away.
class _HiddenRail extends StatefulWidget {
  const _HiddenRail();

  @override
  State<_HiddenRail> createState() => _HiddenRailState();
}

class _HiddenRailState extends State<_HiddenRail> {
  final _controller = RailController(hidden: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 760,
        height: 120,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.seam),
          ),
          child: RailLayout(
            controller: _controller,
            rail: _rail(),
            child: Align(
              alignment: Alignment.topCenter,
              child: ChatHeader(
                chat: _chats[0],
                branch: 'quota-bar-reconnect',
                usage: _usage,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
