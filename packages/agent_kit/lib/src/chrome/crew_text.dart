// How the crew strip and the ledger word the state of a child agent or a
// background job. Not exported from the barrel.

import 'package:agent_kit_core/agent_kit_core.dart';

import 'chrome_format.dart';

/// The status a background job shows: running, done (exit 0), failed (any
/// other exit code) or idle (cancelled).
ChatStatus jobStatus(BackgroundJob job) => switch (job.state) {
  JobState.running => ChatStatus.running,
  JobState.cancelled => ChatStatus.idle,
  JobState.exited => job.failed ? ChatStatus.failed : ChatStatus.done,
};

/// How long a unit of work has run (or ran), or null when it has no start.
Duration? workElapsed(DateTime? start, DateTime? end, DateTime now) {
  if (start == null) return null;
  return (end ?? now).difference(start);
}

/// The default chip label of a job: the first two words of the command
/// ("cargo test").
String jobShortName(BackgroundJob job) =>
    job.command.trim().split(RegExp(r'\s+')).take(2).join(' ');

/// The chip tag of an agent: the elapsed time while it runs, then `ready`.
String agentTag(ChildAgent agent, DateTime now) => switch (agent.state) {
  WorkState.running => _elapsedOr(
    workElapsed(agent.startedAt, agent.endedAt, now),
    'running',
  ),
  WorkState.done => 'ready',
  WorkState.failed => 'failed',
  WorkState.cancelled => 'cancelled',
  WorkState.waitingForAnswer => 'asking parent',
  WorkState.idle => 'idle',
  WorkState.timedOut => 'timed out',
};

/// The chip tag of a job: the elapsed time while it runs, then its summary
/// (`2 failed`) or its exit code.
String jobTag(BackgroundJob job, DateTime now) => switch (job.state) {
  JobState.running => _elapsedOr(
    workElapsed(job.startedAt, job.endedAt, now),
    'running',
  ),
  JobState.cancelled => 'cancelled',
  JobState.exited =>
    job.summary ?? (job.failed ? 'exit ${job.exitCode}' : 'done'),
};

/// The ledger's status label of an agent.
String agentLabel(ChildAgent agent, DateTime now) => switch (agent.state) {
  WorkState.running => _elapsedOr(
    workElapsed(agent.startedAt, agent.endedAt, now),
    'Running',
  ),
  WorkState.done => 'Result ready',
  WorkState.failed => 'Failed',
  WorkState.cancelled => 'Cancelled',
  WorkState.waitingForAnswer => _asking(agent, now),
  WorkState.idle => 'Idle',
  WorkState.timedOut => 'Timed out',
};

/// `Asking parent · 40s`: the wait runs from the question and never expires.
String _asking(ChildAgent agent, DateTime now) {
  final q = agent.pendingQuestion;
  if (q == null) return 'Asking parent';
  final d = now.difference(q.askedAt);
  return 'Asking parent · ${formatElapsed(d.isNegative ? Duration.zero : d)}';
}

/// The question an asking agent shows in the ledger's mono line, in quotes;
/// null for any other agent.
String? askingLine(ChildAgent agent) {
  final q = agent.pendingQuestion;
  if (agent.state != WorkState.waitingForAnswer || q == null) return null;
  return '“${q.text}”';
}

/// The ledger's status label of a job.
String jobLabel(BackgroundJob job, DateTime now) => switch (job.state) {
  JobState.running => 'Running',
  JobState.cancelled => 'Cancelled',
  JobState.exited => 'exited ${job.exitCode ?? 0}',
};

/// The ledger's mono line under a job: `background · 41s`.
String jobDetailLine(BackgroundJob job, DateTime now) {
  final elapsed = workElapsed(job.startedAt, job.endedAt, now);
  return elapsed == null
      ? 'background'
      : 'background · ${formatElapsed(elapsed)}';
}

/// `Still running` header counts: `2 agents · 1 command`.
String crewCounts(int agents, int jobs) => [
  if (agents > 0) plural(agents, 'agent'),
  if (jobs > 0) plural(jobs, 'command'),
].join(' · ');

String _elapsedOr(Duration? d, String fallback) =>
    d == null ? fallback : formatElapsed(d);
