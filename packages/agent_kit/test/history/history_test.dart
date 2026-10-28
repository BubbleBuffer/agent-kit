// The history cards: the folding toggles (chapter, episode, "+N more"), a
// split chapter's footers, a v2 episode, the legacy card, the boundary, and
// the date and marker helpers.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/history/history_cards.dart'
    show historyActionsShown;
import 'package:agent_kit/src/history/history_model.dart'
    show HistoryMarkerTone, historyClock, historyMarkerRuns, historyWhen;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

HistoryEpisode _episode(String id, {int actions = 3, String? gist}) =>
    HistoryEpisode(
      id: id,
      title: 'Title $id',
      gist: gist ?? 'Gist $id.',
      startedAt: DateTime(2026, 10, 27, 13, 41),
      endedAt: DateTime(2026, 10, 27, 13, 56),
      messageCount: 38,
      actions: [
        for (var i = 0; i < actions; i++)
          HistoryAction(verb: 'Read', target: 'file$i.rs'),
      ],
    );

HistoryChapter _chapter({
  String id = 'c1',
  int part = 1,
  int parts = 1,
  int? messages = 58,
  int? episodes = 2,
  bool closed = true,
  List<HistoryEpisode>? list,
}) => HistoryChapter(
  id: id,
  title: 'How usage figures flow',
  summary: 'The bar drops to zero when the socket closes.',
  startedAt: DateTime(2026, 10, 26),
  endedAt: DateTime(2026, 10, 27),
  closed: closed,
  part: part,
  parts: parts,
  messageCount: messages,
  episodeCount: episodes,
  episodes: list ?? [_episode('a'), _episode('b')],
);

Future<void> _pump(WidgetTester tester, Widget child, {double w = 700}) =>
    pumpKit(
      tester,
      SizeClassBuilder(
        builder: (context, _) => SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
      size: Size(w, 1400),
    );

void main() {
  group('helpers', () {
    test('historyWhen', () {
      expect(
        historyWhen(DateTime(2026, 10, 26), DateTime(2026, 10, 27)),
        'Oct 26 – 27',
      );
      expect(
        historyWhen(DateTime(2026, 10, 30), DateTime(2026, 11, 2)),
        'Oct 30 – Nov 2',
      );
      expect(
        historyWhen(DateTime(2026, 10, 26, 9), DateTime(2026, 10, 26, 18)),
        'Oct 26',
      );
      expect(historyWhen(DateTime(2026, 10, 27), null), 'since Oct 27');
      expect(historyWhen(null, null), '');
    });

    test('historyClock', () {
      expect(
        historyClock(
          DateTime(2026, 10, 27, 13, 41),
          DateTime(2026, 10, 27, 14),
        ),
        '13:41–14:00',
      );
      expect(historyClock(null, null), '');
    });

    test('marker tones follow the words', () {
      expect(historyMarkerRuns('+12 −3'), [
        ('+12', HistoryMarkerTone.added),
        (' −3', HistoryMarkerTone.removed),
      ]);
      expect(historyMarkerRuns('created'), [
        ('created', HistoryMarkerTone.added),
      ]);
      expect(historyMarkerRuns('failed · 2 tests'), [
        ('failed · 2 tests', HistoryMarkerTone.removed),
      ]);
      expect(historyMarkerRuns('passed · 14'), [
        ('passed · 14', HistoryMarkerTone.ok),
      ]);
      expect(historyMarkerRuns('+4 −1 · passed · 14'), [
        ('+4', HistoryMarkerTone.added),
        (' −1', HistoryMarkerTone.removed),
        (' ·', HistoryMarkerTone.neutral),
        (' passed · 14', HistoryMarkerTone.ok),
      ]);
    });
  });

  group('chapter card', () {
    testWidgets('reads alone, opens into episodes and folds again', (
      tester,
    ) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        HistoryChapterCard(chapter: _chapter(), controller: controller),
      );
      expect(find.text('Chapter · Oct 26 – 27 · closed'), findsOneWidget);
      expect(find.text('How usage figures flow'), findsOneWidget);
      expect(
        find.text('The bar drops to zero when the socket closes.'),
        findsOneWidget,
      );
      expect(find.text('58 messages · 2 episodes'), findsOneWidget);
      expect(find.text('Show episodes'), findsOneWidget);
      expect(find.text('Title a'), findsNothing);

      await tester.tap(_key('history-chapter-c1-toggle'));
      await tester.pump();
      expect(controller.chapterOpen('c1'), isTrue);
      expect(find.text('Hide episodes'), findsOneWidget);
      expect(find.text('Title a'), findsOneWidget);
      expect(find.text('Title b'), findsOneWidget);
      // The summary stays while open.
      expect(
        find.text('The bar drops to zero when the socket closes.'),
        findsOneWidget,
      );

      await tester.tap(_key('history-chapter-c1-face'));
      await tester.pump();
      expect(controller.chapterOpen('c1'), isFalse);
      expect(find.text('Title a'), findsNothing);
    });

    testWidgets('only the last part of a split chapter shows counts', (
      tester,
    ) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Column(
          children: [
            HistoryChapterCard(
              chapter: _chapter(
                parts: 2,
                messages: null,
                episodes: null,
                list: [_episode('a')],
              ),
              controller: controller,
            ),
            HistoryChapterCard(
              chapter: _chapter(part: 2, parts: 2, list: [_episode('b')]),
              controller: controller,
            ),
          ],
        ),
      );
      // Both parts carry the title; the counts appear once.
      expect(find.text('How usage figures flow'), findsNWidgets(2));
      expect(find.text('58 messages · 2 episodes'), findsOneWidget);
      // The parts fold independently.
      await tester.tap(_key('history-chapter-c1#2-toggle'));
      await tester.pump();
      expect(controller.chapterOpen('c1#2'), isTrue);
      expect(controller.chapterOpen('c1#1'), isFalse);
      expect(find.text('Title b'), findsOneWidget);
      expect(find.text('Title a'), findsNothing);
    });

    testWidgets('decisions and sections are rows of the face; empty ones '
        'leave no row', (tester) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Column(
          children: [
            HistoryChapterCard(
              chapter: HistoryChapter(
                id: 'full',
                title: 'With rows',
                summary: 'A summary.',
                messageCount: 58,
                episodeCount: 2,
                decisions: const ['Follow Codex.', 'Keep the figure.'],
                sections: const [
                  HistorySection(name: 'Find the cause'),
                  HistorySection(name: 'Survey Codex'),
                ],
              ),
              controller: controller,
            ),
            HistoryChapterCard(
              chapter: HistoryChapter(
                id: 'bare',
                title: 'Without rows',
                summary: 'A summary.',
                messageCount: 10,
                episodeCount: 1,
              ),
              controller: controller,
            ),
          ],
        ),
      );
      // The closed card reads alone: both rows are on its face.
      expect(find.text('Follow Codex.'), findsOneWidget);
      expect(find.text('Keep the figure.'), findsOneWidget);
      expect(find.text('Find the cause'), findsOneWidget);
      expect(find.text('Survey Codex'), findsOneWidget);
      expect(
        find.text('58 messages · 2 episodes · 2 sections'),
        findsOneWidget,
      );
      // The chapter without them has neither row, and no sections count.
      expect(find.text('10 messages · 1 episode'), findsOneWidget);
      expect(_key('history-chapter-bare-decision-0'), findsNothing);
      expect(_key('history-chapter-bare-section-0'), findsNothing);
      expect(_key('history-chapter-full-decision-1'), findsOneWidget);
      expect(_key('history-chapter-full-section-1'), findsOneWidget);
    });

    testWidgets('a chapter without a summary shows the title only', (
      tester,
    ) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        HistoryChapterCard(
          chapter: HistoryChapter(
            id: 'x',
            title: 'Bare',
            messageCount: 3,
            episodeCount: 1,
          ),
          controller: controller,
        ),
      );
      expect(find.text('Bare'), findsOneWidget);
      expect(find.text('3 messages · 1 episode'), findsOneWidget);
      expect(find.text('Show episodes'), findsNothing);
    });
  });

  testWidgets('the current chapter is a plain header over its episodes', (
    tester,
  ) async {
    final controller = HistoryController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      HistoryCurrentChapter(
        chapter: HistoryChapter(
          id: 'cur',
          title: '',
          closed: false,
          startedAt: DateTime(2026, 10, 27),
          episodes: [_episode('a'), _episode('b'), _episode('c')],
        ),
        controller: controller,
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText() ==
                'Current chapter · since Oct 27 · 3 episodes',
      ),
      findsOneWidget,
    );
    expect(find.text('Title a'), findsOneWidget);
    expect(find.text('Title c'), findsOneWidget);
    expect(find.text('Show episodes'), findsNothing);
  });

  group('episode card', () {
    HistoryMessagesBuilder messages() =>
        (context, e) => Text('Original messages of ${e.id}');

    testWidgets('header, log, messages and back', (tester) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        HistoryEpisodeCard(
          episode: _episode('e3'),
          controller: controller,
          messagesBuilder: messages(),
        ),
      );
      expect(
        find.textContaining('Episode · 13:41–13:56 · 38 messages'),
        findsOneWidget,
      );
      expect(find.text('3 actions'), findsOneWidget);
      expect(find.text('Title e3'), findsOneWidget);
      expect(find.text('Gist e3.'), findsOneWidget);
      expect(find.text('file0.rs'), findsNothing);

      await tester.tap(_key('history-episode-e3-header'));
      await tester.pump();
      expect(controller.episodeView('e3'), HistoryEpisodeView.log);
      expect(find.text('file0.rs'), findsOneWidget);
      expect(find.text('Show messages'), findsOneWidget);

      await tester.tap(_key('history-episode-e3-messages'));
      await tester.pump();
      expect(controller.episodeView('e3'), HistoryEpisodeView.messages);
      expect(find.text('Original messages of e3'), findsOneWidget);
      expect(find.text('file0.rs'), findsNothing);
      expect(find.text('Show action log'), findsOneWidget);

      await tester.tap(_key('history-episode-e3-log'));
      await tester.pump();
      expect(controller.episodeView('e3'), HistoryEpisodeView.log);

      await tester.tap(_key('history-episode-e3-header'));
      await tester.pump();
      expect(controller.episodeView('e3'), HistoryEpisodeView.closed);
    });

    testWidgets('rows past six fold behind "+N more"', (tester) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      final n = historyActionsShown + 4;
      controller.setEpisodeView('e4', HistoryEpisodeView.log);
      await _pump(
        tester,
        HistoryEpisodeCard(
          episode: _episode('e4', actions: n),
          controller: controller,
          messagesBuilder: messages(),
        ),
      );
      expect(find.text('file${historyActionsShown - 1}.rs'), findsOneWidget);
      expect(find.text('file$historyActionsShown.rs'), findsNothing);
      expect(find.text('+4 more'), findsOneWidget);

      await tester.tap(_key('history-episode-e4-more'));
      await tester.pump();
      expect(find.text('file${n - 1}.rs'), findsOneWidget);
      expect(find.text('+4 more'), findsNothing);
    });

    testWidgets('exactly six rows fold nothing', (tester) async {
      final controller = HistoryController();
      addTearDown(controller.dispose);
      controller.setEpisodeView('e', HistoryEpisodeView.log);
      await _pump(
        tester,
        HistoryEpisodeCard(
          episode: _episode('e', actions: historyActionsShown),
          controller: controller,
        ),
      );
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets(
      'an episode without actions has no counts and goes to messages',
      (tester) async {
        final controller = HistoryController();
        addTearDown(controller.dispose);
        await _pump(
          tester,
          HistoryEpisodeCard(
            episode: _episode('v2', actions: 0),
            controller: controller,
            messagesBuilder: messages(),
          ),
        );
        expect(find.textContaining('action'), findsNothing);
        expect(find.text('Title v2'), findsOneWidget);
        await tester.tap(_key('history-episode-v2-messages'));
        await tester.pump();
        expect(controller.episodeView('v2'), HistoryEpisodeView.messages);
        expect(find.text('Original messages of v2'), findsOneWidget);
        expect(find.text('Show action log'), findsNothing);
        await tester.tap(_key('history-episode-v2-header'));
        await tester.pump();
        expect(controller.episodeView('v2'), HistoryEpisodeView.closed);
      },
    );

    testWidgets('points of interest show their kind and reason', (
      tester,
    ) async {
      final controller = HistoryController()
        ..setEpisodeView('e', HistoryEpisodeView.log);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        HistoryEpisodeCard(
          episode: const HistoryEpisode(
            id: 'e',
            title: 'T',
            actions: [
              HistoryAction(
                verb: 'Ran',
                target: 'cargo test',
                marker: 'failed · 2 tests',
                point: HistoryPoint(
                  kind: HistoryPointKind.error,
                  reason: 'two tests fail',
                ),
              ),
              HistoryAction(
                verb: 'Asked',
                target: '“Show how old?”',
                point: HistoryPoint(
                  kind: HistoryPointKind.question,
                  reason: 'you said not now',
                ),
              ),
            ],
            flaggedCount: 2,
            errorCount: 1,
          ),
          controller: controller,
        ),
      );
      expect(find.text('2 actions · 2 flagged · 1 error'), findsOneWidget);
      expect(find.text('failed · 2 tests'), findsOneWidget);
      expect(find.text('error'), findsOneWidget);
      expect(find.text('open question'), findsOneWidget);
      expect(find.text('two tests fail'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a legacy card shows title, summary, times and count', (
    tester,
  ) async {
    await _pump(
      tester,
      HistoryLegacyCard(
        legacy: HistoryLegacy(
          id: 'l',
          title: 'Older work',
          summary: 'Set up the socket.',
          startedAt: DateTime(2026, 10, 24),
          endedAt: DateTime(2026, 10, 25),
          messageCount: 142,
        ),
      ),
    );
    expect(find.text('Chapter · Oct 24 – 25 · closed'), findsOneWidget);
    expect(find.text('Older work'), findsOneWidget);
    expect(find.text('Set up the socket.'), findsOneWidget);
    expect(find.text('142 messages'), findsOneWidget);
  });

  group('boundary', () {
    testWidgets('names the first full message', (tester) async {
      await _pump(tester, const HistoryBoundary(messageNumber: 132));
      expect(find.text('Full messages from here'), findsOneWidget);
      expect(find.text('message 132'), findsOneWidget);
    });

    testWidgets('leaves the number out when compact', (tester) async {
      await _pump(tester, const HistoryBoundary(messageNumber: 132), w: 390);
      expect(find.text('Full messages from here'), findsOneWidget);
      expect(find.text('message 132'), findsNothing);
    });
  });
}
