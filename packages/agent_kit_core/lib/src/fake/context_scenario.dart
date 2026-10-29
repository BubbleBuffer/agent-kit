/// The context data of the quota scenario: the mockups' LCM history.
library;

import '../context.dart';

/// The model the sample summaries name.
const _model = 'deepseek-v4.1-flash';

/// The chat's earlier day; the sample events happened on it, so they read
/// as older than the scenario that plays on the fake clock.
DateTime _t(int hour, int minute) => DateTime.utc(2025, 12, 28, hour, minute);

/// The serving view after one applied compaction: 48.6k of a 128k window,
/// the apply cap at 84k. Fixed 6.1k, compacted memory 9.0k (from 41k) and
/// live messages 33.5k, with the summary of episode 4 ready but not in the
/// view yet.
ContextView quotaContextView() => ContextView(
  window: 128000,
  applyCap: 84000,
  responseReserve: 44000,
  appliedAt: _t(12, 48),
  pendingEpisodeIds: const ['e4'],
  blocks: const [
    ContextBlock(
      kind: ContextBlockKind.opening,
      tokens: 6100,
      title: 'Instructions, tools and your first request',
    ),
    ContextBlock(
      kind: ContextBlockKind.memoryIndex,
      tokens: 1400,
      title: 'Chapter index',
    ),
    ContextBlock(
      kind: ContextBlockKind.anchors,
      tokens: 1700,
      firstSeq: 1,
      lastSeq: 88,
      title: 'Your requests, word for word',
    ),
    ContextBlock(
      kind: ContextBlockKind.chapterSummary,
      tokens: 3800,
      summaryId: 'sum-ch1',
      firstSeq: 1,
      lastSeq: 58,
      messageCount: 58,
      title: 'How usage figures flow, and how other tools hold them',
    ),
    ContextBlock(
      kind: ContextBlockKind.episodeSummary,
      tokens: 2100,
      summaryId: 'sum-e3',
      firstSeq: 59,
      lastSeq: 96,
      messageCount: 38,
      title: 'Reproduce the flicker with failing tests',
    ),
    ContextBlock(
      kind: ContextBlockKind.rawSuffix,
      tokens: 33500,
      firstSeq: 97,
      lastSeq: 143,
      messageCount: 47,
      title: 'Recent messages, as written',
    ),
  ],
);

/// The structure behind [quotaContextView]: two chapters (the first closed),
/// four episodes, four summaries (two applied), and the six events of the
/// timeline, one of them an applied compaction. Every optional figure is
/// filled in.
ContextDetails quotaContextDetails() => ContextDetails(
  chapters: const [
    ContextChapter(
      id: 'ch1',
      ordinal: 1,
      title: 'How usage figures flow, and how other tools hold them',
      firstSeq: 1,
      lastSeq: 58,
      sourceTokens: 31500,
      summaryId: 'sum-ch1',
    ),
    ContextChapter(
      id: 'ch2',
      ordinal: 2,
      title: 'Keep the last figure',
      firstSeq: 59,
      status: ContextStatus.open,
    ),
  ],
  episodes: const [
    ContextEpisode(
      id: 'e1',
      ordinal: 1,
      title: 'Locate the quota bar and its socket handling',
      firstSeq: 1,
      lastSeq: 31,
      sourceTokens: 14200,
      chapterId: 'ch1',
      summaryId: 'sum-e1',
    ),
    ContextEpisode(
      id: 'e2',
      ordinal: 2,
      title: 'Survey Codex and Claude Code',
      firstSeq: 32,
      lastSeq: 58,
      sourceTokens: 17300,
      chapterId: 'ch1',
      summaryId: 'sum-e2',
    ),
    ContextEpisode(
      id: 'e3',
      ordinal: 3,
      title: 'Reproduce the flicker with failing tests',
      firstSeq: 59,
      lastSeq: 96,
      sourceTokens: 9500,
      chapterId: 'ch2',
      summaryId: 'sum-e3',
    ),
    ContextEpisode(
      id: 'e4',
      ordinal: 4,
      title: 'Draft the stale-figure fix',
      firstSeq: 97,
      lastSeq: 131,
      sourceTokens: 24100,
      chapterId: 'ch2',
      summaryId: 'sum-e4',
    ),
  ],
  summaries: [
    ContextSummary(
      id: 'sum-ch1',
      kind: ContextSummaryKind.chapter,
      title: 'How usage figures flow, and how other tools hold them',
      text:
          '**Goal.** Stop the web quota bar dropping to 0% when the socket '
          'reconnects.\n\n'
          '- `UsageState` in `usage/mod.rs` holds `last`; `on_close` resets '
          'it with `default()`. The web client reads it over `/ws/usage`.\n'
          '- Codex keeps the last rate-limit header and marks it stale. '
          'Claude Code holds the figure silently.\n'
          '- **Decision (user):** follow Codex. Dim the bar while stale, '
          'never hide it.\n\n'
          '**Open then:** whether a stale figure should show its age.',
      firstSeq: 1,
      lastSeq: 58,
      messageCount: 58,
      episodeIds: const ['e1', 'e2'],
      chapterId: 'ch1',
      sourceTokens: 31500,
      summaryTokens: 3800,
      createdAt: _t(11, 41),
      model: _model,
      closed: true,
      applied: true,
    ),
    ContextSummary(
      id: 'sum-e1',
      kind: ContextSummaryKind.episode,
      title: 'Locate the quota bar and its socket handling',
      text:
          'The bar is `web/src/quota-bar.tsx`; it reads `UsageState` over '
          '`/ws/usage`, and `UsageState` resets `last` on close.',
      firstSeq: 1,
      lastSeq: 31,
      messageCount: 31,
      episodeIds: const ['e1'],
      chapterId: 'ch1',
      sourceTokens: 14200,
      summaryTokens: 1900,
      createdAt: _t(10, 52),
      model: _model,
    ),
    ContextSummary(
      id: 'sum-e2',
      kind: ContextSummaryKind.episode,
      title: 'Survey Codex and Claude Code',
      text:
          'Codex keeps the last rate-limit header and marks it stale; Claude '
          'Code holds the figure silently. The user chose to follow Codex.',
      firstSeq: 32,
      lastSeq: 58,
      messageCount: 27,
      episodeIds: const ['e2'],
      chapterId: 'ch1',
      sourceTokens: 17300,
      summaryTokens: 2200,
      createdAt: _t(11, 34),
      model: _model,
    ),
    ContextSummary(
      id: 'sum-e3',
      kind: ContextSummaryKind.episode,
      title: 'Reproduce the flicker with failing tests',
      text:
          'Added `snapshot_survives_reconnect` and '
          '`stale_flag_clears_on_update` to the usage tests.\n\n'
          '- First run of `cargo test -p harbor-runtime usage`: 12 passed, '
          '2 failed.\n'
          '- Both fail because `last` is reset to the default on close.',
      firstSeq: 59,
      lastSeq: 96,
      messageCount: 38,
      episodeIds: const ['e3'],
      chapterId: 'ch2',
      sourceTokens: 9500,
      summaryTokens: 2100,
      createdAt: _t(12, 30),
      model: _model,
      applied: true,
    ),
    ContextSummary(
      id: 'sum-e4',
      kind: ContextSummaryKind.episode,
      title: 'Draft the stale-figure fix',
      text:
          'Changed `UsageState.last` to an `Option` and added `stale_since`, '
          'so a disconnect keeps the figure.\n\n'
          '- The edit to `usage/mod.rs` (+8 −3) is waiting for '
          'approval.',
      firstSeq: 97,
      lastSeq: 131,
      messageCount: 35,
      episodeIds: const ['e4'],
      chapterId: 'ch2',
      sourceTokens: 24100,
      summaryTokens: 2900,
      createdAt: _t(13, 20),
      model: _model,
    ),
  ],
  events: [
    ContextEvent(
      id: 'ev1',
      kind: ContextEventKind.episodeWritten,
      at: _t(10, 52),
      trigger: ContextTrigger.sourceSize,
      triggerText: 'the episode reached the 24k source size',
      firstSeq: 1,
      lastSeq: 31,
      episodeIds: const ['e1'],
      tokensBefore: 14200,
      tokensAfter: 1900,
      summaryId: 'sum-e1',
    ),
    ContextEvent(
      id: 'ev2',
      kind: ContextEventKind.episodeWritten,
      at: _t(11, 34),
      trigger: ContextTrigger.sourceSize,
      triggerText: 'the episode reached the 24k source size',
      firstSeq: 32,
      lastSeq: 58,
      episodeIds: const ['e2'],
      tokensBefore: 17300,
      tokensAfter: 2200,
      summaryId: 'sum-e2',
    ),
    ContextEvent(
      id: 'ev3',
      kind: ContextEventKind.chapterClosed,
      at: _t(11, 41),
      trigger: ContextTrigger.subjectChange,
      triggerText: 'the subject moved from reading code to fixing it',
      firstSeq: 1,
      lastSeq: 58,
      episodeIds: const ['e1', 'e2'],
      tokensBefore: 31500,
      tokensAfter: 3800,
      summaryId: 'sum-ch1',
    ),
    ContextEvent(
      id: 'ev4',
      kind: ContextEventKind.episodeWritten,
      at: _t(12, 30),
      trigger: ContextTrigger.emergency,
      triggerText: 'a short episode, summarized early under pressure',
      firstSeq: 59,
      lastSeq: 96,
      episodeIds: const ['e3'],
      tokensBefore: 9500,
      tokensAfter: 2100,
      summaryId: 'sum-e3',
    ),
    ContextEvent(
      id: 'ev-applied-1',
      kind: ContextEventKind.applied,
      at: _t(12, 48),
      trigger: ContextTrigger.pressure,
      triggerText: 'input reached 80.6k, near the 84k cap',
      firstSeq: 1,
      lastSeq: 96,
      episodeIds: const ['e1', 'e2', 'e3'],
      tokensBefore: 41000,
      tokensAfter: 9000,
      inputBefore: 80600,
      inputAfter: 48600,
      summaryId: 'sum-ch1',
    ),
    ContextEvent(
      id: 'ev5',
      kind: ContextEventKind.episodeWritten,
      at: _t(13, 20),
      trigger: ContextTrigger.sourceSize,
      triggerText: 'the episode reached the 24k source size',
      firstSeq: 97,
      lastSeq: 131,
      episodeIds: const ['e4'],
      tokensBefore: 24100,
      tokensAfter: 2900,
      summaryId: 'sum-e4',
    ),
  ],
);

/// The original messages 1 to 143 of the quota chat, with the lines the
/// mockup shows at the edges of each episode and plausible filler between.
List<HistoryMessage> quotaHistory() {
  const known = <int, (HistoryRole, String, int)>{
    1: (
      HistoryRole.user,
      'The quota bar in the web view drops to 0% every time the socket '
          'reconnects…',
      62,
    ),
    2: (HistoryRole.agent, "I'll start with where the figure is held.", 28),
    31: (
      HistoryRole.agent,
      'UsageState resets `last` on close, and the web client reads it over '
          '/ws/usage.',
      104,
    ),
    32: (
      HistoryRole.agent,
      'Starting a read-only survey of how Codex holds the rate-limit figure.',
      41,
    ),
    33: (HistoryRole.tool, 'spawn · Survey quota handling in Codex', 9),
    58: (
      HistoryRole.user,
      'Follow Codex: keep the figure and mark it stale.',
      20,
    ),
    59: (
      HistoryRole.agent,
      'Writing a test that drops the socket and checks the figure.',
      35,
    ),
    88: (HistoryRole.user, 'Dim the bar while stale, but never hide it.', 22),
    96: (
      HistoryRole.tool,
      'cargo test -p harbor-runtime usage · 12 passed, 2 failed',
      412,
    ),
    97: (
      HistoryRole.agent,
      'Keeping `last` on disconnect, behind an Option.',
      58,
    ),
    131: (HistoryRole.tool, 'edit · usage/mod.rs +8 −3', 190),
    132: (
      HistoryRole.agent,
      'Mark it stale until the first update after reconnect.',
      47,
    ),
    133: (HistoryRole.tool, 'read · usage/mod.rs', 1900),
    142: (
      HistoryRole.tool,
      'cargo test -p harbor-runtime usage · exit 101',
      420,
    ),
    143: (
      HistoryRole.agent,
      'Two tests still fail. Waiting for your approval of the edit.',
      52,
    ),
  };
  const filler = <(HistoryRole, String, int)>[
    (HistoryRole.tool, 'read · web/src/quota-bar.tsx', 640),
    (HistoryRole.agent, 'The component reads `percent` from the socket.', 44),
    (HistoryRole.tool, 'grep · on_close · 9 hits', 210),
    (HistoryRole.agent, 'Checking what resets the snapshot.', 31),
  ];
  return [
    for (var seq = 1; seq <= 143; seq++)
      if (known[seq] case (final role, final text, final tokens))
        HistoryMessage(seq: seq, role: role, preview: text, tokens: tokens)
      else
        HistoryMessage(
          seq: seq,
          role: filler[seq % filler.length].$1,
          preview: filler[seq % filler.length].$2,
          tokens: filler[seq % filler.length].$3,
        ),
  ];
}
