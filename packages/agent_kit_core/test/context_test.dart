import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:test/test.dart';

Json _roundTrip(KitValue v) => v.toJson();

void main() {
  group('context models', () {
    test('the sample view round-trips and adds up to 48.6k', () {
      final view = quotaContextView();
      expect(ContextView.fromJson(_roundTrip(view)), view);
      expect(view.totalTokens, 48600);
      expect(view.openingTokens, 6100);
      expect(view.memoryTokens, 9000);
      expect(view.liveTokens, 33500);
      expect(view.window, 128000);
      expect(view.applyCap, 84000);
      expect(view.pendingEpisodeIds, ['e4']);
      expect(
        view.blocks.map((b) => b.kind),
        containsAllInOrder([
          ContextBlockKind.opening,
          ContextBlockKind.memoryIndex,
          ContextBlockKind.anchors,
          ContextBlockKind.chapterSummary,
          ContextBlockKind.episodeSummary,
          ContextBlockKind.rawSuffix,
        ]),
      );
    });

    test('a block without tokens leaves the sums unknown, never zero', () {
      final view = ContextView(
        window: 128000,
        applyCap: 84000,
        responseReserve: 44000,
        blocks: const [
          ContextBlock(kind: ContextBlockKind.opening),
          ContextBlock(kind: ContextBlockKind.rawSuffix, tokens: 900),
        ],
      );
      expect(view.totalTokens, isNull);
      expect(view.openingTokens, isNull);
      expect(view.memoryTokens, isNull);
      expect(view.liveTokens, 900);
      final json = view.toJson();
      expect(
        ((json['blocks']! as List).first as Map).containsKey('tokens'),
        isFalse,
      );
      expect(ContextView.fromJson(json), view);
    });

    test('details round-trip and look things up by id', () {
      final details = quotaContextDetails();
      expect(ContextDetails.fromJson(_roundTrip(details)), details);
      expect(details.chapters.map((c) => c.id), ['ch1', 'ch2']);
      expect(details.chapter('ch2')!.status, ContextStatus.open);
      expect(details.chapter('ch2')!.lastSeq, isNull);
      expect(details.episodes, hasLength(4));
      expect(details.episode('e3')!.messageCount, 38);
      expect(details.summary('sum-ch1')!.applied, isTrue);
      expect(details.summary('sum-e4')!.applied, isFalse);
      expect(details.summary('sum-ch1')!.savedTokens, 27700);
      expect(details.summary('nope'), isNull);
      final applied = details.events.where(
        (e) => e.kind == ContextEventKind.applied,
      );
      expect(applied, hasLength(1));
      expect(applied.single.inputBefore, 80600);
      expect(applied.single.inputAfter, 48600);
    });

    test('what the host does not record stays null and out of the JSON', () {
      final bare = ContextEvent(
        id: 'x',
        kind: ContextEventKind.applied,
        at: DateTime.utc(2026),
        firstSeq: 1,
        lastSeq: 9,
        tokensBefore: 100,
        tokensAfter: 30,
      );
      final json = bare.toJson();
      for (final key in [
        'trigger',
        'triggerText',
        'inputBefore',
        'inputAfter',
        'summaryId',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      final back = ContextEvent.fromJson(json);
      expect(back.trigger, isNull);
      expect(back.inputBefore, isNull);
      expect(back, bare);
    });

    test('an unknown trigger reads as unknown, a missing one as null', () {
      final base = ContextEvent(
        id: 'x',
        kind: ContextEventKind.episodeWritten,
        at: DateTime.utc(2026),
        firstSeq: 1,
        lastSeq: 2,
        tokensBefore: 10,
        tokensAfter: 5,
      ).toJson();
      expect(
        ContextEvent.fromJson({...base, 'trigger': 'cosmicRay'}).trigger,
        ContextTrigger.unknown,
      );
      expect(ContextEvent.fromJson(base).trigger, isNull);
      expect(
        ContextEvent.fromJson({...base, 'kind': 'future'}).kind,
        ContextEventKind.episodeWritten,
      );
    });

    test('history pages hold messages with optional tokens', () {
      final page = HistoryPage(
        firstSeq: 1,
        lastSeq: 2,
        messages: const [
          HistoryMessage(seq: 1, role: HistoryRole.user, preview: 'Hi'),
          HistoryMessage(
            seq: 2,
            role: HistoryRole.tool,
            preview: 'read',
            tokens: 9,
          ),
        ],
      );
      expect(HistoryPage.fromJson(_roundTrip(page)), page);
      expect(page.messages.first.tokens, isNull);
      expect(page.toJson().toString(), isNot(contains('tokens: null')));
    });
  });

  group('context in the snapshot', () {
    ChatSnapshot fold(Iterable<Json> events) {
      var seq = 0;
      return reduceAll(ChatSnapshot.empty('c1'), [
        for (final e in events) KitEvent.fromJson({...e, 'seq': ++seq, 'chat': 'c1'}),
      ]);
    }

    test('context.changed replaces the view; the snapshot round-trips', () {
      final first = quotaContextView();
      final second = ContextView(
        window: 128000,
        applyCap: 84000,
        responseReserve: 44000,
        blocks: const [ContextBlock(kind: ContextBlockKind.opening)],
      );
      final one = fold([
        {'kind': 'context.changed', 'context': first.toJson()},
      ]);
      expect(one.context, first);
      final two = reduce(
        one,
        KitEvent.fromJson({
          'seq': 2,
          'chat': 'c1',
          'kind': 'context.changed',
          'context': second.toJson(),
        }),
      );
      expect(two.context, second);
      expect(ChatSnapshot.fromJson(two.toJson()), two);
      expect(ChatSnapshot.empty('c1').context, isNull);
      expect(ChatSnapshot.empty('c1').toJson().containsKey('context'), isFalse);
    });

    test('a compaction marker is updated in place, at its first position', () {
      final s = fold([
        {'kind': 'message.user', 'itemId': 'u1', 'text': 'go'},
        {
          'kind': 'compaction.updated',
          'itemId': 'cm1',
          'state': 'running',
          'detail': 'summarizing episode 4 · 24k',
          'at': '2026-10-26T09:00:00.000Z',
        },
        {'kind': 'message.system', 'itemId': 's1', 'text': 'later'},
        {
          'kind': 'compaction.updated',
          'itemId': 'cm1',
          'state': 'done',
          'eventId': 'ev1',
          'episodesSummarized': 3,
          'tokensBefore': 41000,
          'tokensAfter': 9000,
          'at': '2026-10-26T09:00:05.000Z',
        },
      ]);
      expect(s.items.map((i) => i.id), ['u1', 'cm1', 's1']);
      final marker = s.item('cm1')! as CompactionItem;
      expect(marker.state, CompactionState.done);
      expect(marker.episodesSummarized, 3);
      expect(marker.tokensBefore, 41000);
      expect(marker.detail, isNull);
      expect(marker.at, DateTime.utc(2026, 10, 26, 9));
      expect(TranscriptItem.fromJson(marker.toJson()), marker);
    });

    test('a marker with no figures keeps them null', () {
      final s = fold([
        {'kind': 'compaction.updated', 'itemId': 'cm1', 'state': 'failed'},
      ]);
      final marker = s.item('cm1')! as CompactionItem;
      expect(marker.state, CompactionState.failed);
      expect(marker.episodesSummarized, isNull);
      expect(marker.tokensBefore, isNull);
      expect(marker.tokensAfter, isNull);
    });

    test('interrupted.added adds the item; the run outcome is separate', () {
      final s = fold([
        {'kind': 'run.started', 'runId': 'r1'},
        {
          'kind': 'run.finished',
          'runId': 'r1',
          'outcome': 'interrupted',
          'at': '2026-10-26T09:05:00.000Z',
        },
        {
          'kind': 'interrupted.added',
          'itemId': 'i1',
          'reason': 'The host restarted.',
          'at': '2026-10-26T09:05:00.000Z',
        },
      ]);
      final item = s.item('i1')! as InterruptedItem;
      expect(item.reason, 'The host restarted.');
      expect(item.at, DateTime.utc(2026, 10, 26, 9, 5));
      expect(s.status, ChatStatus.interrupted);
      expect(TranscriptItem.fromJson(item.toJson()), item);
    });

    test('a resolved question carries the time it was answered', () {
      final s = fold([
        {
          'kind': 'question.asked',
          'question': {
            'id': 'q1',
            'requestedAt': '2026-10-26T09:00:00.000Z',
            'items': [
              {'id': 'a', 'header': 'A', 'text': 'A?', 'kind': 'text'},
            ],
          },
        },
        {
          'kind': 'question.resolved',
          'questionId': 'q1',
          'answers': {
            'a': {'text': 'yes'},
          },
          'at': '2026-10-26T09:03:00.000Z',
        },
      ]);
      final q = s.questions.single;
      expect(q.answeredAt, DateTime.utc(2026, 10, 26, 9, 3));
      expect(Question.fromJson(q.toJson()).answeredAt, q.answeredAt);
    });
  });

  group('context on the fake backend', () {
    late ScriptedBackend backend;

    setUp(() {
      backend = ScriptedBackend(
        scripts: [quotaReconnectScript()],
        clock: ManualClock(),
      );
    });

    test('loadContext, loadSummary and loadHistoryRange answer', () async {
      final details = await backend.loadContext(quotaChatId);
      expect(details, quotaContextDetails());
      final summary = await backend.loadSummary(quotaChatId, 'sum-ch1');
      expect(summary.text, contains('Decision (user)'));
      final page = await backend.loadHistoryRange(quotaChatId, 30, 34);
      expect(page.messages.map((m) => m.seq), [30, 31, 32, 33, 34]);
      expect(page.messages[1].role, HistoryRole.agent);
      expect(page.messages[3].role, HistoryRole.tool);
      final tail = await backend.loadHistoryRange(quotaChatId, 140, 200);
      expect(tail.messages.last.seq, 143);
      await expectLater(
        backend.loadSummary(quotaChatId, 'nope'),
        throwsA(isA<KitNotFound>()),
      );
      await expectLater(
        backend.loadHistoryRange(quotaChatId, 9, 3),
        throwsA(isA<KitInvalid>()),
      );
    });

    test('a chat without data has empty details', () async {
      final id = (await backend.createChat()).id;
      final details = await backend.loadContext(id);
      expect(details.events, isEmpty);
      expect((await backend.loadHistoryRange(id, 1, 5)).messages, isEmpty);
    });

    test('without the capability the three calls are unsupported', () async {
      final limited = ScriptedBackend(
        scripts: [quotaReconnectScript()],
        clock: ManualClock(),
        capabilities: KitCapabilities(const [KitCapability.children]),
      );
      for (final call in <Future<Object?> Function()>[
        () => limited.loadContext(quotaChatId),
        () => limited.loadHistoryRange(quotaChatId, 1, 2),
        () => limited.loadSummary(quotaChatId, 'sum-ch1'),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<KitUnsupported>().having(
              (e) => e.capability,
              'capability',
              KitCapability.context,
            ),
          ),
        );
      }
    });

    test('the capabilities round-trip by name', () {
      final caps = KitCapabilities(const [
        KitCapability.context,
        KitCapability.answerChildQuestion,
      ]);
      final back = KitCapabilities.fromJson(caps.toJson());
      expect(back.has(KitCapability.context), isTrue);
      expect(back.has(KitCapability.answerChildQuestion), isTrue);
      expect(back.has(KitCapability.steer), isFalse);
    });
  });
}
