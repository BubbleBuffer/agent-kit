/// The mockups' "Quota bar flickers on reconnect" chat as a script.
library;

import 'context_scenario.dart';
import 'scripted_backend.dart';

/// The chat id of [quotaReconnectScript].
const quotaChatId = 'quota-reconnect';

/// The "Quota bar flickers on reconnect" scenario from the approved
/// mockups, end to end.
///
/// The agent surveys the code, spawns two child agents, streams an answer
/// with a code block, edits files, runs the tests (exit 101) in the
/// foreground and in the background, and updates its plan. The connection
/// drops for a few seconds (events keep happening) and comes back with a
/// `gap`. At the end it waits for approval of an edit, with a follow-up
/// queued: the mockups' mid-task state, status `needsYou`.
///
/// The LCM history of the mockups is part of it: one child asks its parent a
/// question and gets an answer, another is left asking (40 seconds before
/// the end), a compaction marker runs and completes, and the chat has the
/// context view of 48.6k of 128k tokens, with `loadContext`,
/// `loadHistoryRange` and `loadSummary` answering from [quotaContextDetails]
/// and [quotaHistory].
///
/// It takes about five minutes on the script clock.
ChatScript quotaReconnectScript() {
  Duration s(int seconds) => Duration(seconds: seconds);
  const run = 'run-quota-1';
  const prompt =
      'The quota bar drops to 0% for a moment whenever the web app '
      'reconnects. Find out why and fix it so the last figure stays up '
      'while we reconnect.';
  const answer =
      'The flicker comes from `on_disconnect`: it resets the snapshot, so '
      'the bar draws 0% until the first update after the reconnect.\n\n'
      '- Keep `last` on disconnect.\n'
      '- Mark it **stale** until the next update.\n'
      '- Dim the bar while stale; never hide it.\n\n'
      '```rust\n'
      'fn on_disconnect(&mut self, now: Instant) {\n'
      '    // was: self.last = UsageSnapshot::default();\n'
      '    self.stale_since = Some(now);\n'
      '}\n'
      '```\n';
  const testOutput =
      'running 14 tests\n'
      'test usage::snapshot_survives_reconnect ... FAILED\n'
      'test usage::stale_flag_clears_on_update ... FAILED\n'
      'test usage::percent_rounds_down ... ok\n'
      '\n'
      'test result: FAILED. 12 passed; 2 failed; 0 ignored\n';

  Map<String, Object?> line(String op, String text) => {'op': op, 'text': text};

  return ChatScript(
    chatId: quotaChatId,
    title: 'Quota bar flickers on reconnect',
    context: quotaContextDetails(),
    history: quotaHistory(),
    steps: [
      const ScriptStep(Duration.zero, {
        'kind': 'chat.workspace',
        'workspace': {
          'name': 'bubblepaw',
          'path': 'projects/bubblepaw',
          'branch': 'bp/quota-reconnect',
          'worktree': '.worktrees/quota-reconnect',
        },
      }),
      const ScriptStep(Duration.zero, {
        'kind': 'chat.settings',
        'model': 'deepseek-v4.1-flash',
        'profile': 'workspace',
      }),
      ScriptStep(s(1), {
        'kind': 'message.user',
        'itemId': 'u1',
        'text': prompt,
        'refs': [
          {
            'kind': 'file',
            'id': 'crates/bubblepaw-host/src/usage/mod.rs',
            'label': 'usage/mod.rs',
          },
          {
            'kind': 'file',
            'id': 'web/src/quota-bar.tsx',
            'label': 'web/src/quota-bar.tsx',
          },
        ],
      }),
      const ScriptStep(Duration.zero, {
        'kind': 'run.started',
        'runId': run,
        'model': 'deepseek-v4.1-flash',
      }),
      ScriptStep(s(1), {
        'kind': 'thinking.started',
        'rowId': 't1',
        'runId': run,
      }),
      ScriptStep(s(2), {
        'kind': 'thinking.delta',
        'rowId': 't1',
        'offset': 0,
        'text': 'Compared Codex and Claude Code ',
      }),
      ScriptStep(s(2), {
        'kind': 'thinking.delta',
        'rowId': 't1',
        'offset': 31,
        'text': 'usage handling',
      }),
      ScriptStep(s(2), {
        'kind': 'thinking.finished',
        'rowId': 't1',
        'durationMs': 6000,
      }),
      ScriptStep(s(1), {
        'kind': 'tool.started',
        'callId': 'c1',
        'name': 'read',
        'toolKind': 'read',
        'target': 'crates/bubblepaw-host/src/usage/mod.rs',
      }),
      ScriptStep(s(1), {
        'kind': 'tool.finished',
        'callId': 'c1',
        'meta': '212 lines',
      }),
      ScriptStep(s(1), {
        'kind': 'tool.started',
        'callId': 'c2',
        'name': 'read',
        'toolKind': 'read',
        'target': 'web/src/quota-bar.tsx',
      }),
      ScriptStep(s(1), {
        'kind': 'tool.finished',
        'callId': 'c2',
        'meta': '88 lines',
      }),
      ScriptStep(s(1), {
        'kind': 'tool.started',
        'callId': 'c3',
        'name': 'grep',
        'toolKind': 'search',
        'target': 'reset|on_close · crates/',
      }),
      ScriptStep(s(1), {
        'kind': 'tool.finished',
        'callId': 'c3',
        'meta': '9 hits',
      }),
      ScriptStep(s(1), {
        'kind': 'child.spawned',
        'childId': 'c7e2',
        'task': 'Survey quota handling in Codex',
        'callId': 'c4',
        'runId': run,
      }),
      const ScriptStep(Duration.zero, {
        'kind': 'child.spawned',
        'childId': 'c7e3',
        'task': 'Map UsageState transitions',
        'callId': 'c5',
        'runId': run,
      }),
      ScriptStep(s(1), {
        'kind': 'plan.updated',
        'items': [
          {'id': 'p1', 'text': 'Survey Codex and Claude Code', 'state': 'now'},
          {'id': 'p2', 'text': 'Keep `last` on disconnect', 'state': 'todo'},
          {
            'id': 'p3',
            'text': 'Mark it stale until the next update',
            'state': 'todo',
          },
          {
            'id': 'p4',
            'text': 'Dim the quota bar while stale',
            'state': 'todo',
          },
          {'id': 'p5', 'text': 'Run the usage tests', 'state': 'todo'},
        ],
      }),
      ScriptStep(s(4), {
        'kind': 'child.progress',
        'childId': 'c7e2',
        'activity': 'read codex-rs/core/src/rate_limits.rs',
        'toolCalls': 3,
      }),
      ScriptStep(s(2), {
        'kind': 'child.question.asked',
        'question': {
          'id': 'cq1',
          'childId': 'c7e2',
          'text':
              'Codex has two rate-limit paths, the CLI and the app server. '
              'Which one should I read?',
          'options': ['App server', 'CLI', 'Both'],
        },
      }),
      ScriptStep(s(4), {
        'kind': 'child.question.resolved',
        'childId': 'c7e2',
        'questionId': 'cq1',
        'answer': 'App server only. The CLI path is a thin wrapper around it.',
        'answeredBy': 'parent',
      }),
      ScriptStep(s(2), {
        'kind': 'usage.updated',
        'usage': {
          'contextTokens': 31200,
          'contextLimit': 128000,
          'inputTokens': 58000,
          'outputTokens': 2100,
        },
      }),
      // The connection drops; the run goes on.
      ScriptStep(s(1), {'kind': r'$disconnect'}),
      ScriptStep(s(2), {
        'kind': 'message.delta',
        'itemId': 'a1',
        'offset': 0,
        'text': answer.substring(0, 60),
        'runId': run,
      }),
      ScriptStep(s(2), {
        'kind': 'child.finished',
        'childId': 'c7e3',
        'state': 'done',
        'result':
            'UsageState goes Live → Stale on disconnect and back to Live on '
            'the next update; nothing else resets it.',
      }),
      ScriptStep(s(10), {'kind': r'$reconnect'}),
      ScriptStep(s(1), {
        'kind': 'message.delta',
        'itemId': 'a1',
        'offset': 60,
        'text': answer.substring(60, 140),
        'runId': run,
      }),
      ScriptStep(s(2), {
        'kind': 'message.assistant',
        'itemId': 'a1',
        'markdown': answer,
        'runId': run,
      }),
      ScriptStep(s(1), {
        'kind': 'message.notice',
        'itemId': 'n1',
        'text': 'Reconnected. Showing what happened while offline.',
        'tone': 'info',
      }),
      ScriptStep(s(1), {
        'kind': 'compaction.updated',
        'itemId': 'cm1',
        'state': 'running',
        'detail': 'summarizing episode 4 · 24k',
      }),
      ScriptStep(s(3), {
        'kind': 'compaction.updated',
        'itemId': 'cm1',
        'state': 'done',
        'eventId': 'ev-applied-1',
        'episodesSummarized': 3,
        'tokensBefore': 41000,
        'tokensAfter': 9000,
      }),
      ScriptStep(Duration.zero, {
        'kind': 'context.changed',
        'context': quotaContextView().toJson(),
      }),
      ScriptStep(s(2), {
        'kind': 'edit.applied',
        'itemId': 'e1',
        'callId': 'c6',
        'diff': {
          'path': 'tests/quota_reconnect.rs',
          'change': 'created',
          'hunks': [
            {
              'oldStart': 0,
              'newStart': 1,
              'lines': [
                line('add', 'use bubblepaw_host::usage::UsageState;'),
                line('add', ''),
                line('add', '#[test]'),
                line('add', 'fn snapshot_survives_reconnect() {'),
                line('add', '    let mut s = UsageState::default();'),
                line('add', '    s.on_disconnect(Instant::now());'),
                line('add', '    assert!(s.last.is_some());'),
                line('add', '}'),
              ],
            },
          ],
        },
      }),
      ScriptStep(s(1), {
        'kind': 'plan.updated',
        'items': [
          {'id': 'p1', 'text': 'Survey Codex and Claude Code', 'state': 'done'},
          {'id': 'p2', 'text': 'Keep `last` on disconnect', 'state': 'done'},
          {
            'id': 'p3',
            'text': 'Mark it stale until the next update',
            'state': 'now',
          },
          {
            'id': 'p4',
            'text': 'Dim the quota bar while stale',
            'state': 'todo',
          },
          {'id': 'p5', 'text': 'Run the usage tests', 'state': 'todo'},
        ],
      }),
      ScriptStep(s(1), {
        'kind': 'tool.started',
        'callId': 'c7',
        'name': 'exec',
        'toolKind': 'exec',
        'target': 'cargo test -p bubblepaw-host usage',
        'runId': run,
      }),
      ScriptStep(s(2), {
        'kind': 'tool.output',
        'callId': 'c7',
        'offset': 0,
        'text': testOutput.substring(0, 17),
      }),
      ScriptStep(s(4), {
        'kind': 'tool.output',
        'callId': 'c7',
        'offset': 17,
        'text': testOutput.substring(17),
      }),
      ScriptStep(s(1), {
        'kind': 'tool.finished',
        'callId': 'c7',
        'state': 'failed',
        'exitCode': 101,
        'meta': '2 failed',
        'output': {
          'text': testOutput,
          'totalBytes': 2150,
          'totalLines': 20,
          'truncated': true,
        },
      }),
      ScriptStep(s(1), {
        'kind': 'job.started',
        'jobId': 'j1',
        'command': 'cargo test -p bubblepaw-host usage',
      }),
      ScriptStep(s(20), {
        'kind': 'job.output',
        'jobId': 'j1',
        'offset': 0,
        'text': testOutput,
      }),
      ScriptStep(s(21), {
        'kind': 'job.exited',
        'jobId': 'j1',
        'exitCode': 101,
        'summary': '2 failed',
      }),
      ScriptStep(s(1), {
        'kind': 'message.system',
        'itemId': 's1',
        'text': 'Background job exited 101.',
      }),
      ScriptStep(s(1), {
        'kind': 'child.spawned',
        'childId': 'c7e4',
        'task': 'Trace socket reconnect in the web client',
        'callId': 'c10',
        'runId': run,
      }),
      ScriptStep(s(2), {
        'kind': 'child.question.asked',
        'question': {
          'id': 'cq2',
          'childId': 'c7e4',
          'text':
              'Is the reconnect handled in web/src/ws.ts, or in the shared '
              'client?',
          'options': ['ws.ts', 'Shared client'],
        },
      }),
      // The question stays pending to the end of the script.
      ScriptStep(s(35), {
        'kind': 'child.progress',
        'childId': 'c7e4',
        'activity': 'read web/src/ws.ts',
        'toolCalls': 4,
      }),
      ScriptStep(s(1), {
        'kind': 'edit.applied',
        'itemId': 'e2',
        'callId': 'c8',
        'diff': {
          'path': 'crates/bubblepaw-host/src/usage/mod.rs',
          'hunks': [
            {
              'oldStart': 52,
              'newStart': 52,
              'lines': [
                line('ctx', 'impl UsageState {'),
                line('del', '    fn on_disconnect(&mut self) {'),
                line('del', '        self.last = UsageSnapshot::default();'),
                line('add', '    fn on_disconnect(&mut self, now: Instant) {'),
                line('add', '        // Keep the last figure; mark it stale.'),
                line('add', '        self.stale_since = Some(now);'),
                line('ctx', '    }'),
              ],
            },
            {
              'oldStart': 70,
              'newStart': 71,
              'lines': [
                line(
                  'ctx',
                  '    fn on_update(&mut self, snap: UsageSnapshot) {',
                ),
                line('del', '        self.last = snap;'),
                line('add', '        self.last = Some(snap);'),
                line('add', '        self.stale_since = None;'),
                line('add', '    }'),
                line('add', ''),
                line('add', '    pub fn is_stale(&self) -> bool {'),
                line('add', '        self.stale_since.is_some()'),
                line('ctx', '    }'),
              ],
            },
          ],
        },
      }),
      ScriptStep(s(1), {
        'kind': 'usage.updated',
        'usage': {
          'contextTokens': 48640,
          'contextLimit': 128000,
          'inputTokens': 112000,
          'outputTokens': 5400,
          'cacheReadTokens': 64000,
        },
      }),
      ScriptStep(s(1), {
        'kind': 'tool.started',
        'callId': 'c9',
        'name': 'edit',
        'toolKind': 'edit',
        'target': 'crates/bubblepaw-host/src/usage/mod.rs',
        'runId': run,
      }),
      ScriptStep(Duration.zero, {
        'kind': 'approval.requested',
        'approval': {
          'id': 'ap1',
          'tool': 'edit',
          'kind': 'edit',
          'target': 'crates/bubblepaw-host/src/usage/mod.rs',
          'callId': 'c9',
          'runId': run,
          'diff': {
            'path': 'crates/bubblepaw-host/src/usage/mod.rs',
            'hunks': [
              {
                'oldStart': 88,
                'newStart': 88,
                'lines': [
                  line('ctx', '    pub fn view(&self) -> UsageView {'),
                  line('del', '        let percent = self.last.percent;'),
                  line('del', '        UsageView { percent }'),
                  line('del', '    }'),
                  line('add', '        let Some(last) = &self.last else {'),
                  line('add', '            return UsageView::empty();'),
                  line('add', '        };'),
                  line('add', '        UsageView {'),
                  line('add', '            percent: last.percent,'),
                  line('add', '            stale: self.is_stale(),'),
                  line('add', '        }'),
                  line('add', '    }'),
                ],
              },
            ],
          },
        },
      }),
      ScriptStep(s(2), {
        'kind': 'queue.added',
        'input': {
          'id': 'q1',
          'text': 'Dim the bar while stale, don’t hide it',
          'mode': 'followup',
        },
      }),
    ],
  );
}
