// Sample data of the chrome tests: the mockup's rail, crew and usage.

import 'package:agent_kit/agent_kit.dart' show ModelUsage, chatAge;
import 'package:agent_kit_core/agent_kit_core.dart';

/// The clock of every chrome test.
final now = DateTime(2026, 10, 26, 15);

const quotaTitle = 'Quota bar flickers on reconnect';

final chats = <ChatSummary>[
  ChatSummary(
    id: 'quota',
    title: quotaTitle,
    status: ChatStatus.needsYou,
    updatedAt: now.subtract(const Duration(minutes: 2)),
  ),
  ChatSummary(
    id: 'steer',
    title: 'Steer vs queue semantics',
    status: ChatStatus.running,
    runningChildren: 3,
    updatedAt: now.subtract(const Duration(minutes: 20)),
  ),
  ChatSummary(
    id: 'fork',
    title: 'Compact before fork',
    updatedAt: now.subtract(const Duration(minutes: 12)),
  ),
  ChatSummary(
    id: 'worktree',
    title: 'Child worktree retention',
    updatedAt: now.subtract(const Duration(days: 1)),
  ),
  ChatSummary(
    id: 'wal',
    title: 'SQLite WAL growth on long runs',
    status: ChatStatus.failed,
    error: 'exit 101',
    updatedAt: now.subtract(const Duration(days: 2)),
  ),
  ChatSummary(
    id: 'grouping',
    title: 'Session list grouping',
    updatedAt: now.subtract(const Duration(days: 5)),
  ),
];

String? detailFor(ChatSummary chat) => switch (chat.status) {
  ChatStatus.needsYou => 'edit approval',
  ChatStatus.running => '${chat.runningChildren} agents',
  ChatStatus.failed => chat.error,
  _ => chatAge(chat.updatedAt, now),
};

final agents = <ChildAgent>[
  ChildAgent(
    id: 'survey',
    task: 'Survey quota handling in Codex',
    activity: 'read codex-rs/core/src/rate_limits.rs',
    toolCalls: 5,
    startedAt: now.subtract(const Duration(minutes: 1, seconds: 4)),
  ),
  ChildAgent(
    id: 'map',
    task: 'Map UsageState transitions',
    state: WorkState.done,
    activity: 'read-only',
    toolCalls: 9,
    startedAt: now.subtract(const Duration(minutes: 3)),
    endedAt: now.subtract(const Duration(minutes: 1)),
  ),
];

final jobs = <BackgroundJob>[
  BackgroundJob(
    id: 'test',
    command: 'cargo test -p bubblepaw-host usage',
    state: JobState.exited,
    exitCode: 101,
    summary: '2 failed',
    startedAt: now.subtract(const Duration(seconds: 41)),
    endedAt: now,
  ),
];

String agentTitle(ChildAgent agent) =>
    agent.id == 'survey' ? 'Survey quota' : 'Map transitions';

const usage = Usage(
  contextTokens: 48640,
  contextLimit: 128000,
  inputTokens: 1100000,
  outputTokens: 140000,
);

const models = <ModelUsage>[
  ModelUsage('deepseek-v4.1-flash', 960000),
  ModelUsage('gpt-6.1-sol', 280000),
  ModelUsage('haiku-5.5', 4000),
];
