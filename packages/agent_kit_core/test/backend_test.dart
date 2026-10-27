import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:test/test.dart';

void main() {
  group('ManualClock', () {
    test('wakes sleepers in deadline order, ties in sleep order', () async {
      final clock = ManualClock();
      final woke = <String>[];
      unawaited(
        clock.sleep(const Duration(seconds: 2)).then((_) => woke.add('b')),
      );
      unawaited(
        clock.sleep(const Duration(seconds: 1)).then((_) => woke.add('a')),
      );
      unawaited(
        clock.sleep(const Duration(seconds: 2)).then((_) => woke.add('c')),
      );
      expect(clock.pending, 3);
      await clock.advance(const Duration(milliseconds: 1500));
      expect(woke, ['a']);
      expect(
        clock.now(),
        DateTime.utc(2026).add(const Duration(milliseconds: 1500)),
      );
      await clock.advance(const Duration(seconds: 1));
      expect(woke, ['a', 'b', 'c']);
      expect(clock.pending, 0);
    });

    test('runAll drains chained sleeps', () async {
      final clock = ManualClock();
      var n = 0;
      Future<void> loop() async {
        for (var i = 0; i < 5; i++) {
          await clock.sleep(const Duration(minutes: 1));
          n++;
        }
      }

      unawaited(loop());
      await clock.runAll();
      expect(n, 5);
      expect(clock.now(), DateTime.utc(2026).add(const Duration(minutes: 5)));
    });
  });

  group('quota scenario', () {
    test(
      'plays end to end through a reconnect into the mockup state',
      () async {
        final clock = ManualClock();
        final backend = ScriptedBackend(
          scripts: [quotaReconnectScript()],
          clock: clock,
        );
        final feed = ChatFeed(backend, quotaChatId);
        final seen = <ChatSnapshot>[];
        final sub = feed.snapshots.listen(seen.add);
        await feed.start();
        final done = backend.play();
        await clock.runAll();
        await done;
        // Let the reload after the reconnect gap finish.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // The disconnect showed as a stale snapshot, then cleared on reload.
        final staleAt = seen.indexWhere((s) => s.stale);
        expect(
          staleAt,
          isNonNegative,
          reason: 'a gap marks the snapshot stale',
        );
        expect(seen.skip(staleAt).any((s) => !s.stale), isTrue);

        final s = feed.snapshot!;
        expect(s.stale, isFalse);
        // The feed's folded view matches the backend's own state.
        expect(s.toJson(), backend.stateOf(quotaChatId)!.toJson());

        // Header and sidebar.
        expect(s.title, 'Quota bar flickers on reconnect');
        expect(s.status, ChatStatus.needsYou);
        expect(s.workspace?.branch, 'bp/quota-reconnect');
        expect(s.workspace?.worktree, isNotNull);
        expect(s.model, 'deepseek-v4.1-flash');
        expect(s.profile, 'workspace');
        // Context meter: 38% of 128k.
        expect(s.usage?.contextLimit, 128000);
        expect((s.usage!.contextFraction! * 100).round(), 38);

        // Transcript.
        final user = s.items.whereType<UserMessage>().single;
        expect(user.refs, hasLength(2));
        final groups = s.items.whereType<ActivityGroup>().toList();
        expect(groups, isNotEmpty);
        final rows = [for (final g in groups) ...g.rows];
        expect(rows.whereType<ThinkingRow>().single.durationMs, isNotNull);
        final tools = {for (final r in rows.whereType<ToolRow>()) r.id: r};
        expect(tools['c1']?.meta, '212 lines');
        expect(tools['c3']?.kind, ToolKind.search);
        expect(tools['c7']?.exitCode, 101);
        expect(tools['c7']?.state, WorkState.failed);
        expect(tools['c7']?.output?.truncated, isTrue);
        expect(tools['c9']?.state, WorkState.running);
        expect(rows.whereType<SpawnRow>(), hasLength(3));
        final answer = s.item('a1')! as AssistantMessage;
        expect(answer.streaming, isFalse);
        expect(answer.markdown, contains('```'));
        expect(s.item('n1'), isA<NoticeLine>());
        expect(s.item('s1'), isA<SystemLine>());
        final edits = s.items.whereType<FileEdit>().toList();
        expect(edits, hasLength(2));
        expect(edits.first.diff.added, 8);
        expect(edits.last.diff.removed, greaterThan(0));
        expect(s.items.whereType<ChildResult>().single.childId, 'c7e3');

        // Panels.
        expect(s.plan, hasLength(5));
        expect(s.planDone, 2);
        final approval = s.pendingApprovals.single;
        expect(approval.id, 'ap1');
        expect(approval.diff, isNotNull);
        expect(approval.requestedAt, isNotNull);
        expect(s.queue.single.text, 'Dim the bar while stale, don’t hide it');
        expect(s.queue.single.mode, QueueMode.followup);
        final crew = {for (final c in s.children) c.id: c};
        expect(crew['c7e2']?.state, WorkState.running);
        expect(crew['c7e3']?.state, WorkState.done);
        final job = s.jobs.single;
        expect(job.exitCode, 101);
        expect(job.failed, isTrue);
        expect(job.summary, '2 failed');

        await sub.cancel();
        await feed.close();
      },
    );
  });

  group('ScriptedBackend commands', () {
    late ManualClock clock;
    late ScriptedBackend backend;
    late String chat;

    setUp(() async {
      clock = ManualClock();
      backend = ScriptedBackend(clock: clock);
      chat = (await backend.createChat(title: 'Test')).id;
    });

    ChatSnapshot state() => backend.stateOf(chat)!;

    test('send starts a run; a second send queues', () async {
      final first = await backend.send(chat, 'hello');
      expect(first.delivery, SendDelivery.started);
      expect(state().status, ChatStatus.running);
      final second = await backend.send(chat, 'and this');
      expect(second.delivery, SendDelivery.queued);
      expect(state().queue.single.id, second.inputId);
      expect(backend.commands.map((c) => c.name), [
        'createChat',
        'send',
        'send',
      ]);
    });

    test('queue: edit, send now, remove', () async {
      await backend.send(chat, 'go');
      final a = await backend.followup(chat, 'first');
      final b = await backend.followup(chat, 'second');
      await backend.editQueued(chat, a, 'first, edited');
      expect(state().queue.first.text, 'first, edited');
      await backend.sendQueuedNow(chat, a);
      expect(state().queue.map((q) => q.id), [b]);
      expect(state().items.whereType<UserMessage>().last.text, 'first, edited');
      await backend.removeQueued(chat, b);
      expect(state().queue, isEmpty);
      expect(() => backend.removeQueued(chat, b), throwsA(isA<KitNotFound>()));
    });

    test('cancel ends the run', () async {
      await backend.send(chat, 'go');
      await backend.cancel(chat);
      expect(state().run?.outcome, RunOutcome.cancelled);
      expect(state().status, ChatStatus.idle);
    });

    test('approvals: decide resolves; deciding twice conflicts', () async {
      await backend.send(chat, 'go');
      backend.emit(chat, {
        'kind': 'approval.requested',
        'approval': {'id': 'ap1', 'tool': 'exec', 'kind': 'exec'},
      });
      expect(state().status, ChatStatus.needsYou);
      await backend.decideApproval(
        chat,
        'ap1',
        const ApprovalDecision.deny('Not now'),
      );
      final ap = state().approvals.single;
      expect(ap.state, ApprovalState.denied);
      expect(ap.reason, 'Not now');
      expect(
        () => backend.decideApproval(chat, 'ap1', ApprovalDecision.approve),
        throwsA(isA<KitConflict>()),
      );
    });

    test('rename, archive, fork', () async {
      await backend.send(chat, 'go');
      await backend.rename(chat, 'Renamed');
      expect(state().title, 'Renamed');
      await backend.archive(chat);
      expect(state().archived, isTrue);
      final fork = await backend.fork(chat);
      expect(fork.parentId, chat);
      final page = await backend.listChats();
      expect(page.chats.map((c) => c.id), containsAll([chat, fork.id]));
    });

    test('unsupported capability fails with a typed error', () async {
      final limited = ScriptedBackend(
        clock: clock,
        capabilities: KitCapabilities({KitCapability.rename}),
      );
      final id = (await limited.createChat()).id;
      await limited.send(id, 'go');
      final error = await limited
          .followup(id, 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      // A follow-up is core; queue editing is not.
      expect(error, isNull);
      final queued = limited.stateOf(id)!.queue.single.id;
      await expectLater(
        limited.editQueued(id, queued, 'y'),
        throwsA(
          isA<KitUnsupported>().having(
            (e) => e.capability,
            'capability',
            KitCapability.queueEdit,
          ),
        ),
      );
    });

    test('failNext and unknown chats fail with safe messages', () async {
      backend.failNext = const KitUnavailable('The host is offline.');
      await expectLater(
        backend.send(chat, 'x'),
        throwsA(
          isA<KitUnavailable>().having(
            (e) => e.message,
            'message',
            'The host is offline.',
          ),
        ),
      );
      await expectLater(backend.loadChat('nope'), throwsA(isA<KitNotFound>()));
      await expectLater(backend.send(chat, '  '), throwsA(isA<KitInvalid>()));
    });

    test('events after a sequence replay the log, then follow live', () async {
      await backend.send(chat, 'one');
      final mid = backend.lastSeq;
      await backend.cancel(chat);
      final got = <KitEvent>[];
      final sub = backend.events(chat, after: mid).listen(got.add);
      await Future<void>.delayed(Duration.zero);
      expect(got.map((e) => e.kind), ['run.finished']);
      await backend.rename(chat, 'Live');
      await Future<void>.delayed(Duration.zero);
      expect(got.last.kind, 'chat.renamed');
      await sub.cancel();
    });

    test('disconnect holds events; reconnect sends a gap', () async {
      final got = <KitEvent>[];
      final sub = backend.events(chat, after: backend.lastSeq).listen(got.add);
      backend.disconnect(chat);
      await backend.rename(chat, 'Offline rename');
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty);
      backend.reconnect(chat);
      await Future<void>.delayed(Duration.zero);
      expect(got.single, isA<GapEvent>());
      await sub.cancel();
    });
  });

  test('a snapshot holds no status input', () {
    final s = ChatSnapshot.fromJson({'chatId': 'c', 'status': 'failed'});
    expect(s.status, ChatStatus.idle);
  });
}
