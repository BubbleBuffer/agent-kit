// The compacted-history scene (mockup scene H): older history as cards above a
// "Full messages from here" hairline, the live end below it in full. It is laid
// out the way a host does it: `TranscriptList(entries:)` with a
// `HistoryController` holding the fold state, opened on the boundary. The
// states shown at once: a legacy summary, a closed chapter folded, one opened
// onto its episodes (a v2 episode, an action log with "+N more" folded, the
// original messages), a split chapter in two parts, and the current chapter.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show AssistantMessage, TranscriptItem, UserMessage;
import 'package:flutter/widgets.dart';

const _tests = 'cargo test -p harbor-runtime usage';

DateTime _at(int day, int h, int m) => DateTime(2026, 10, day, h, m);

String _plus(int a, int d) => '+$a −$d';

final _e1 = HistoryEpisode(
  id: 'e1',
  title: 'Find where the figure is cleared',
  gist: 'UsageState resets its last figure when the socket closes.',
  startedAt: _at(26, 10, 4),
  endedAt: _at(26, 10, 52),
  messageCount: 31,
  actions: const [
    HistoryAction(verb: 'Read', target: 'usage/mod.rs'),
    HistoryAction(verb: 'Read', target: 'web/src/ws.ts'),
    HistoryAction(
      verb: 'Ran',
      target: 'rg "last = None" crates/',
      point: HistoryPoint(
        kind: HistoryPointKind.decision,
        reason: 'the reset is in on_close',
      ),
    ),
  ],
  flaggedCount: 1,
);

final _e2 = HistoryEpisode(
  id: 'e2',
  title: 'Survey Codex and Claude Code',
  gist: 'Codex keeps the last rate-limit header and marks it stale.',
  startedAt: _at(26, 11, 4),
  endedAt: _at(26, 11, 41),
  messageCount: 27,
  actions: const [
    HistoryAction(verb: 'Read', target: 'codex-rs/core/src/rate_limits.rs'),
    HistoryAction(verb: 'Asked', target: '“Show how old the figure is?”'),
  ],
);

/// Summarized before episodes had an action log.
final _v2 = HistoryEpisode(
  id: 'v2',
  title: 'Sketch the quota bar states',
  gist: 'Four states: fresh, stale, failed and unknown.',
  startedAt: _at(27, 9, 12),
  endedAt: _at(27, 9, 40),
  messageCount: 18,
);

final _e3 = HistoryEpisode(
  id: 'e3',
  title: 'Reproduce the flicker with a failing test',
  gist: 'The reconnect test fails because the figure is cleared on close.',
  startedAt: _at(27, 13, 41),
  endedAt: _at(27, 13, 56),
  messageCount: 38,
  actions: [
    const HistoryAction(verb: 'Read', target: 'usage/mod.rs'),
    const HistoryAction(verb: 'Read', target: 'web/src/ws.ts'),
    const HistoryAction(
      verb: 'Created',
      target: 'tests/quota_reconnect.rs',
      marker: 'created',
    ),
    const HistoryAction(
      verb: 'Ran',
      target: _tests,
      marker: 'failed · 2 tests',
      point: HistoryPoint(
        kind: HistoryPointKind.error,
        reason: 'snapshot_survives_reconnect fails',
      ),
    ),
    HistoryAction(
      verb: 'Edited',
      target: 'tests/quota_reconnect.rs',
      marker: _plus(6, 2),
      point: const HistoryPoint(
        kind: HistoryPointKind.correction,
        reason: '“test the reconnect, not the poller”',
      ),
    ),
  ],
  flaggedCount: 2,
  errorCount: 1,
);

final _e4 = HistoryEpisode(
  id: 'e4',
  title: 'Keep the last figure behind an Option',
  gist: 'UsageState keeps the last figure on disconnect; 14 tests pass.',
  startedAt: _at(27, 14, 2),
  endedAt: _at(27, 14, 20),
  messageCount: 12,
  actions: [
    const HistoryAction(verb: 'Read', target: 'usage/mod.rs'),
    const HistoryAction(verb: 'Read', target: 'web/src/quota-bar.tsx'),
    HistoryAction(
      verb: 'Edited',
      target: 'usage/mod.rs',
      marker: _plus(8, 3),
      point: const HistoryPoint(
        kind: HistoryPointKind.decision,
        reason: 'keep last in an Option',
      ),
    ),
    const HistoryAction(
      verb: 'Ran',
      target: _tests,
      marker: 'failed · 2 tests',
      point: HistoryPoint(
        kind: HistoryPointKind.error,
        reason: 'stale_flag_clears_on_update',
      ),
    ),
    HistoryAction(
      verb: 'Edited',
      target: 'usage/mod.rs',
      marker: _plus(4, 1),
      point: const HistoryPoint(
        kind: HistoryPointKind.correction,
        reason: '“don’t hide the bar while stale”',
      ),
    ),
    const HistoryAction(
      verb: 'Asked',
      target: '“Show how old the figure is?”',
      point: HistoryPoint(
        kind: HistoryPointKind.question,
        reason: 'you said not now',
      ),
    ),
    HistoryAction(
      verb: 'Edited',
      target: 'web/src/quota-bar.tsx',
      marker: _plus(9, 2),
    ),
    const HistoryAction(
      verb: 'Created',
      target: 'tests/stale_flag.rs',
      marker: 'created',
    ),
    const HistoryAction(verb: 'Ran', target: _tests, marker: 'passed · 14'),
    const HistoryAction(
      verb: 'Deleted',
      target: 'usage/legacy.rs',
      marker: 'deleted',
      point: HistoryPoint(
        kind: HistoryPointKind.decision,
        reason: 'dead after the Option change',
      ),
    ),
  ],
  flaggedCount: 5,
  errorCount: 1,
);

final _e5 = HistoryEpisode(
  id: 'e5',
  title: 'Mark the figure stale after a reconnect',
  gist: 'stale_since is set on close and cleared by the first update.',
  startedAt: _at(27, 14, 21),
  endedAt: _at(27, 14, 38),
  messageCount: 23,
  actions: [
    HistoryAction(
      verb: 'Edited',
      target: 'usage/mod.rs',
      marker: _plus(12, 2),
      point: const HistoryPoint(
        kind: HistoryPointKind.decision,
        reason: 'stale until the first update, not a timer',
      ),
    ),
    const HistoryAction(verb: 'Ran', target: _tests, marker: 'passed · 14'),
  ],
  flaggedCount: 1,
);

HistoryEpisode _mini(String id, String title, String gist, int day) =>
    HistoryEpisode(
      id: id,
      title: title,
      gist: gist,
      startedAt: _at(day, 10, 0),
      endedAt: _at(day, 10, 30),
      messageCount: 29,
      actions: const [HistoryAction(verb: 'Read', target: 'usage/mod.rs')],
    );

final _chapters = <Object>[
  HistoryLegacy(
    id: 'checkpoint',
    summary:
        'Set up the usage socket and the first version of the quota bar. '
        'The bar read its figure from /ws/usage and cleared it on every '
        'close.',
    startedAt: _at(24, 9, 0),
    endedAt: _at(25, 17, 30),
    messageCount: 142,
    colorIndex: 0,
  ),
  HistoryChapter(
    id: 'c1',
    title: 'How usage figures flow',
    summary:
        'The bar drops to zero because UsageState resets its last figure '
        'when the socket closes, and the web client reads that field over '
        '/ws/usage. Codex keeps the last rate-limit header and marks it '
        'stale; Claude Code just holds it.',
    startedAt: _at(26, 10, 4),
    endedAt: _at(26, 11, 41),
    messageCount: 58,
    episodeCount: 2,
    episodes: [
      _mini('c1a', 'Find the cause', 'The reset is in on_close.', 26),
      _mini('c1b', 'Survey Codex and Claude Code', 'Codex marks it stale.', 26),
    ],
    decisions: const ['Follow Codex: keep the figure and mark it stale.'],
    sections: const [
      HistorySection(name: 'Find the cause', firstEpisode: 1, lastEpisode: 1),
      HistorySection(
        name: 'Survey Codex and Claude Code',
        firstEpisode: 2,
        lastEpisode: 2,
      ),
    ],
    colorIndex: 1,
  ),
  HistoryChapter(
    id: 'c2',
    title: 'Sketch the quota bar',
    summary:
        'The bar has four states. The stale one stays readable and says '
        'how old the figure is only on request.',
    startedAt: _at(27, 9, 12),
    endedAt: _at(27, 12, 30),
    messageCount: 41,
    episodeCount: 3,
    episodes: [_v2, _e1, _e2],
    colorIndex: 2,
  ),
  HistoryChapter(
    id: 'c3',
    title: 'Backoff and retries',
    summary: 'Reconnects back off from one second to a minute, with jitter.',
    startedAt: _at(26, 15, 0),
    endedAt: _at(26, 15, 40),
    part: 1,
    parts: 2,
    colorIndex: 3,
  ),
  HistoryChapter(
    id: 'c3',
    title: 'Backoff and retries',
    summary: 'Reconnects back off from one second to a minute, with jitter.',
    startedAt: _at(26, 16, 10),
    endedAt: _at(26, 17, 0),
    part: 2,
    parts: 2,
    messageCount: 34,
    episodeCount: 3,
    decisions: const ['Back off from one second to a minute, with jitter.'],
    colorIndex: 3,
  ),
  HistoryChapter(
    id: 'cur',
    title: '',
    closed: false,
    startedAt: _at(27, 13, 41),
    episodes: [_e3, _e4, _e5],
  ),
];

const _live = <(bool, String)>[
  (true, 'Now dim the bar while it’s stale, but keep it readable.'),
  (
    false,
    'Dimming the stale bar to 60% opacity; the figure stays at full size.',
  ),
  (false, 'Done. The stale bar is dimmed and still readable at small sizes.'),
];

const _originals = <(bool, String)>[
  (true, 'Keep the last figure when the socket closes.'),
  (false, 'Keeping last on disconnect, behind an Option.'),
  (false, 'Edited usage/mod.rs and ran the usage tests: 14 passed.'),
];

TranscriptItem _item(String id, bool user, String text) => user
    ? UserMessage(id: id, text: text)
    : AssistantMessage(id: id, markdown: text);

class HistoryScene extends StatefulWidget {
  const HistoryScene({super.key});

  @override
  State<HistoryScene> createState() => _HistorySceneState();
}

class _HistorySceneState extends State<HistoryScene> {
  final HistoryController _history = HistoryController()
    // The second chapter opens onto its episodes; the first stays folded.
    ..setChapterOpen('c2', true)
    ..setEpisodeView('e1', HistoryEpisodeView.log)
    ..setEpisodeView('e2', HistoryEpisodeView.messages)
    ..setEpisodeView('e4', HistoryEpisodeView.log)
    ..setEpisodeView('e5', HistoryEpisodeView.messages);

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  Widget _originalMessages(BuildContext context, HistoryEpisode episode) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (user, text)) in _originals.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            TranscriptItemView(_item('${episode.id}-$i', user, text)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final entries = <TimelineEntry>[
      for (final c in _chapters)
        if (c is HistoryLegacy)
          TimelineEntry(
            id: 'legacy:${c.id}',
            builder: (_) => HistoryLegacyCard(legacy: c),
          )
        else if (c is HistoryChapter && c.closed)
          TimelineEntry(
            id: 'chapter:${c.key}',
            builder: (_) => HistoryChapterCard(
              chapter: c,
              controller: _history,
              messagesBuilder: _originalMessages,
            ),
          )
        else if (c is HistoryChapter)
          TimelineEntry(
            id: 'chapter:${c.key}',
            builder: (_) => HistoryCurrentChapter(
              chapter: c,
              controller: _history,
              messagesBuilder: _originalMessages,
            ),
          ),
      TimelineEntry(
        id: 'boundary',
        builder: (_) => const HistoryBoundary(messageNumber: 132),
      ),
      for (final (i, (user, text)) in _live.indexed)
        TimelineEntry(
          id: 'live-$i',
          builder: (_) => TranscriptItemView(_item('live-$i', user, text)),
        ),
    ];
    return ColoredBox(
      color: t.surface,
      child: TranscriptList(
        entries: entries,
        initialAnchor: const TranscriptAnchor('boundary'),
        gapBefore: (previousId, id) => switch (id) {
          'boundary' => 24,
          'live-0' => 24,
          _
              when previousId != null &&
                  previousId != 'boundary' &&
                  !previousId.startsWith('live-') &&
                  !id.startsWith('live-') =>
            24,
          _ => null,
        },
      ),
    );
  }
}
