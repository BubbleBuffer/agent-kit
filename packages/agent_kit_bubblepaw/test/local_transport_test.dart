// Opt in with BP_TEST_BIN pointing at the public v0.3.1 binary. The provider
// below is BubblePaw's built-in deterministic demo, with no paid/live calls.
import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_bubblepaw/src/transport.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

const _demoReply = 'Offline demo completed through native capabilities.';

void main() {
  final binary = Platform.environment['BP_TEST_BIN'];
  test(
    'released stdio host sends KIT events and recovers an injected gap',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-kit-stdio-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await Directory('${root.path}/workspace').create();
      final data = await Directory('${root.path}/data').create();
      await File('${workspace.path}/fixture.txt')
          .writeAsString('Offline fixture');
      final transport = _GapTransport(
        await StdioBubblePawTransport.start(
          binaryPath: binary!,
          workspaceDirectory: workspace.path,
          dataDirectory: data.path,
          // v0.3.1's demo supports the native surface (provider/scripted.rs).
          // It lists only this disposable workspace. JS nested progress can
          // legitimately trigger a canonical reload before run_finished arrives;
          // native mode lets this test also observe the complete KIT event trio.
          arguments: const [
            '--set',
            "agent.execution_mode='native'",
            '--provider',
            'demo',
            '--no-auto-summarize',
            '--read-only',
          ],
        ),
      );
      addTearDown(transport.dispose);
      final backend = await BubblePawBackend.connect(
        transport,
        workspaceDirectory: workspace.path,
      );
      addTearDown(backend.dispose);
      final chat = await backend.createChat(title: 'Offline stdio acceptance');
      expect(
        (await backend.listChats()).chats.any((c) => c.id == chat.id),
        isTrue,
      );

      final feed = ChatFeed(backend, chat.id);
      addTearDown(feed.close);
      final errors = <Object>[];
      final snapshots = feed.snapshots.listen((_) {}, onError: errors.add);
      addTearDown(snapshots.cancel);
      await feed.start();
      final events = <KitEvent>[];
      final subscription = backend
          .events(chat.id, after: feed.snapshot!.seq)
          .listen(events.add, onError: errors.add);
      addTearDown(subscription.cancel);

      String diagnostics() {
        final snapshot = feed.snapshot;
        return 'kitKinds=${events.map((event) => event.kind).toList()}; '
            'snapshot={seq:${snapshot?.seq}, runId:${snapshot?.run?.id}, '
            'outcome:${snapshot?.run?.outcome?.name}, '
            'stale:${snapshot?.stale}, items:${snapshot?.items.length}}; '
            'errorTypes=${errors.map((error) => error.runtimeType).toList()}; '
            'requests=${transport.requestCounts}; '
            'hostShapes=${transport.notificationShapes}';
      }

      final first = await backend.send(chat.id, 'Run the offline demo');
      expect(first.delivery, SendDelivery.started);
      await _until(
        () =>
            feed.snapshot?.run?.id == first.runId &&
            feed.snapshot?.run?.outcome == RunOutcome.completed,
        stage: 'first completed snapshot',
        diagnostics: diagnostics,
      );
      await _until(
        () => events.whereType<RunFinished>().any(
          (event) => event.runId == first.runId,
        ),
        stage: 'first KIT run.finished event',
        diagnostics: diagnostics,
      );
      expect(events.whereType<RunStarted>(), isNotEmpty);
      expect(events.whereType<GapEvent>(), isEmpty);
      expect(
        events.any(
          (event) =>
              event is MessageDelta || event is AssistantMessageCompleted,
        ),
        isTrue,
      );
      expect(
        feed.snapshot!.items.whereType<AssistantMessage>().any(
          (item) => item.markdown.contains(_demoReply) && !item.streaming,
        ),
        isTrue,
      );

      final stateReads = transport.stateReads;
      final replayReads = transport.replayReads;
      final previousSeq = feed.snapshot!.seq;
      transport.dropNextDurableEvent(chat.id);
      final second = await backend.send(chat.id, 'Recover a dropped event');
      await _until(
        () =>
            transport.injectedGaps == 1 &&
            transport.stateReads > stateReads &&
            transport.replayReads > replayReads &&
            feed.snapshot?.run?.id == second.runId &&
            feed.snapshot?.run?.outcome == RunOutcome.completed &&
            feed.snapshot!.seq > previousSeq &&
            !feed.snapshot!.stale,
        stage: 'injected gap recovery',
        diagnostics: diagnostics,
      );
      expect(transport.droppedEvents, 1);
      await _until(
        () => events.whereType<RunFinished>().any(
          (event) => event.runId == second.runId,
        ),
        stage: 'replayed second completion',
        diagnostics: diagnostics,
      );
      expect(
        events.whereType<RunStarted>().where(
          (event) => event.runId == second.runId,
        ),
        hasLength(1),
      );
      expect(
        events.whereType<RunFinished>().where(
          (event) => event.runId == second.runId,
        ),
        hasLength(1),
      );
      expect(
        feed.snapshot!.items.whereType<UserMessage>().any(
          (item) => item.text == 'Recover a dropped event',
        ),
        isTrue,
      );
      expect(
        feed.snapshot!.items
            .whereType<AssistantMessage>()
            .where(
              (item) => item.markdown.contains(_demoReply) && !item.streaming,
            )
            .length,
        2,
      );

      final third = await backend.send(chat.id, 'Continue after recovery');
      await _until(
        () =>
            feed.snapshot?.run?.id == third.runId &&
            feed.snapshot?.run?.outcome == RunOutcome.completed,
        stage: 'subsequent completed snapshot',
        diagnostics: diagnostics,
      );
      expect(errors, isEmpty);
      expect(feed.snapshot!.stale, isFalse);
    },
    skip: binary == null || binary.trim().isEmpty
        ? 'Set BP_TEST_BIN to opt in to the released local stdio host.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'released host preserves approved tool boundaries across steer and gap',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-kit-approval-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await Directory('${root.path}/workspace').create();
      final data = await Directory('${root.path}/data').create();
      final transport = _GapTransport(
        await StdioBubblePawTransport.start(
          binaryPath: binary!,
          workspaceDirectory: workspace.path,
          dataDirectory: data.path,
          arguments: const [
            '--provider',
            'demo',
            '--no-auto-summarize',
            '--set',
            "agent.execution_mode='native'",
            '--set',
            "approvals.tools.exec='ask'",
          ],
        ),
      );
      addTearDown(transport.dispose);
      final backend = await BubblePawBackend.connect(
        transport,
        workspaceDirectory: workspace.path,
      );
      addTearDown(backend.dispose);
      final chat = await backend.createChat(title: 'Offline approval recovery');
      final initial = await backend.loadChat(chat.id);
      final events = <KitEvent>[];
      final errors = <Object>[];
      final subscription = backend
          .events(chat.id, after: initial.seq)
          .listen(events.add, onError: errors.add);
      addTearDown(subscription.cancel);
      String diagnostics() =>
          'kinds=${events.map((event) => event.kind).toList()}; '
          'errors=${errors.map((error) => error.runtimeType).toList()}; '
          'hostShapes=${transport.notificationShapes}';
      final run = await backend.send(chat.id, 'Run the offline demo');
      await _until(
        () => events.whereType<ApprovalRequested>().isNotEmpty,
        stage: 'exec approval',
        diagnostics: diagnostics,
      );
      final approval = events.whereType<ApprovalRequested>().single.approval;
      expect(approval.tool, 'exec');
      // An approval keeps the real run active while steering is admitted.
      await backend.steer(chat.id, 'Complete the offline demo');
      // Drop the actual durable exec start after approval; the real host log
      // must replay it even if session.state has already advanced past it.
      transport.dropNextDurableEvent(chat.id, type: 'tool_started');
      await backend.decideApproval(
        chat.id,
        approval.id,
        ApprovalDecision.approve,
      );
      await _until(
        () => events.whereType<RunFinished>().any(
          (event) => event.runId == run.runId,
        ),
        stage: 'approved run completion',
        diagnostics: diagnostics,
      );
      expect(transport.injectedGaps, 1);
      expect(events.whereType<GapEvent>(), hasLength(1));
      final starts = events
          .whereType<ToolStarted>()
          .where((event) => event.name == 'exec')
          .toList();
      expect(starts, hasLength(1));
      expect(
        events.whereType<ToolFinished>().where(
          (event) => event.callId == starts.single.callId,
        ),
        hasLength(1),
      );
      expect(
        events.whereType<ApprovalResolved>().where(
          (event) => event.approvalId == approval.id,
        ),
        hasLength(1),
      );
      expect(
        events.whereType<RunFinished>().where(
          (event) => event.runId == run.runId,
        ),
        hasLength(1),
      );
      expect(errors, isEmpty);
    },
    skip: binary == null || binary.trim().isEmpty
        ? 'Set BP_TEST_BIN to opt in to the released local stdio host.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'released v0.3.1 host serves context and history reads on a demo chat',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-kit-context-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await Directory('${root.path}/workspace').create();
      final data = await Directory('${root.path}/data').create();
      final backend = await BubblePawBackend.start(
        binaryPath: binary!,
        workspaceDirectory: workspace.path,
        dataDirectory: data.path,
        arguments: const [
          '--set',
          "agent.execution_mode='native'",
          '--provider',
          'demo',
          '--no-auto-summarize',
          '--read-only',
        ],
      );
      addTearDown(backend.dispose);
      // The v0.3.1 host advertises all three features this adapter reads.
      expect(
        backend.features,
        containsAll(['context', 'child_events', 'question.answer_child']),
      );
      expect(backend.capabilities.has(KitCapability.context), isTrue);
      expect(
        backend.capabilities.has(KitCapability.answerChildQuestion),
        isTrue,
      );
      final chat = await backend.createChat(title: 'Offline context reads');
      final run = await backend.send(chat.id, 'Run the offline demo');
      var snapshot = await backend.loadChat(chat.id);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (snapshot.run?.id != run.runId ||
          snapshot.run?.outcome != RunOutcome.completed) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for the demo run: ${snapshot.run?.outcome}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        snapshot = await backend.loadChat(chat.id);
      }
      // The demo provider writes no episodes, so the structure may be empty and
      // the view null. These reads must succeed; only their shape is asserted.
      final details = await backend.loadContext(chat.id);
      for (final episode in details.episodes) {
        expect(episode.firstSeq, lessThanOrEqualTo(episode.lastSeq));
      }
      for (final summary in details.summaries) {
        final whole = await backend.loadSummary(chat.id, summary.id);
        expect(whole.id, summary.id);
      }
      expect(snapshot.children, isEmpty);
      final page = await backend.loadHistoryRange(chat.id, 0, 1 << 40);
      expect(page.messages, isNotEmpty);
      expect(page.messages.first.role, HistoryRole.user);
      expect(page.messages.first.preview, 'Run the offline demo');
      expect(
        page.messages.map((m) => m.seq),
        orderedEquals([...page.messages.map((m) => m.seq)]..sort()),
      );
      // A second range starting after the first message holds the rest.
      final rest = await backend.loadHistoryRange(
        chat.id,
        page.messages.first.seq + 1,
        1 << 40,
      );
      expect(rest.messages.length, page.messages.length - 1);
    },
    skip: binary == null || binary.trim().isEmpty
        ? 'Set BP_TEST_BIN to opt in to the released local stdio host.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'released v0.3.1 host lists providers and pages the session list',
    () async {
      final root = await Directory.systemTemp.createTemp('agent-kit-hc-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await Directory('${root.path}/workspace').create();
      final data = await Directory('${root.path}/data').create();
      final backend = await BubblePawBackend.start(
        binaryPath: binary!,
        workspaceDirectory: workspace.path,
        dataDirectory: data.path,
        arguments: const [
          '--set',
          "agent.execution_mode='native'",
          '--provider',
          'demo',
          '--no-auto-summarize',
          '--read-only',
        ],
      );
      addTearDown(backend.dispose);
      expect(
        backend.features,
        containsAll([
          'providers.list',
          'roles.set_main',
          'session.list.pagination',
          'child.cancel',
        ]),
      );
      for (final c in [
        KitCapability.providers,
        KitCapability.defaultModel,
        KitCapability.models,
        KitCapability.children,
      ]) {
        expect(backend.capabilities.has(c), isTrue, reason: '$c');
      }

      final setup = await backend.listProviders();
      expect(setup.providers.map((p) => p.name), contains('demo'));

      await backend.createChat(title: 'First');
      await backend.createChat(title: 'Second');
      final page = await backend.listChats();
      expect(page.chats.map((c) => c.title), containsAll(['First', 'Second']));
      expect(page.nextCursor, isNull);
    },
    skip: binary == null || binary.trim().isEmpty
        ? 'Set BP_TEST_BIN to opt in to the released local stdio host.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _until(
  bool Function() predicate, {
  required String stage,
  required String Function() diagnostics,
}) async {
  try {
    await (() async {
      while (!predicate()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    })().timeout(const Duration(seconds: 30));
  } on TimeoutException {
    fail('Timed out waiting for $stage. ${diagnostics()}');
  }
}

/// Forwards a real child's requests and notifications. Only the explicitly
/// armed notification loss and gap are synthetic: this proves adapter recovery,
/// not a host broadcast-buffer overflow. No responses or session data are faked.
class _GapTransport implements BubblePawTransport {
  _GapTransport(this.inner) {
    _subscription = inner.notifications.listen(
      _forward,
      onError: _notifications.addError,
      onDone: _notifications.close,
    );
  }

  final BubblePawTransport inner;
  final _notifications = StreamController<Map<String, Object?>>.broadcast();
  late final StreamSubscription<Map<String, Object?>> _subscription;
  String? _dropFor;
  String? _dropType;
  int _lastForwarded = 0;
  int stateReads = 0;
  int replayReads = 0;
  int droppedEvents = 0;
  int injectedGaps = 0;
  bool _disposed = false;
  final requestCounts = <String, int>{};
  final notificationShapes = <Map<String, Object?>>[];

  void dropNextDurableEvent(String chatId, {String? type}) {
    _dropFor = chatId;
    _dropType = type;
  }

  void _forward(Map<String, Object?> notification) {
    final params = notification['params'];
    if (notification['method'] == 'event' && params is Map) {
      if (notificationShapes.length < 128) {
        // Only protocol shape is retained: no text, arguments, values or paths.
        final type = params['type'];
        const knownTypes = {
          'host_state_changed',
          'output',
          'session_settled',
          'run_started',
          'run_waiting_for_quota',
          'run_quota_resumed',
          'paragraph',
          'model_request_started',
          'text_delta',
          'tool_started',
          'tool_finished',
          'steering_accepted',
          'followup_queued',
          'run_finished',
          'approval_requested',
          'approval_resolved',
        };
        final key = params['key'];
        const knownKeys = {'todo', 'question', 'usage.last_request'};
        notificationShapes.add({
          'type': knownTypes.contains(type) ? type : '<other>',
          if (type == 'host_state_changed')
            'key': knownKeys.contains(key) ? key : '<other>',
          'sequence': params['sequence'] is int ? params['sequence'] : null,
          'durable': params['durable'] == true,
        });
      }
      if (params['durable'] == true) {
        if (_dropFor != null &&
            params['session_id'] == _dropFor &&
            (_dropType == null || params['type'] == _dropType)) {
          _dropFor = null;
          droppedEvents++;
          injectedGaps++;
          _notifications.add({
            'jsonrpc': '2.0',
            'method': 'events.gap',
            'params': {
              'skipped': 1,
              'after': _lastForwarded,
              'recover_with': 'events.after',
            },
          });
          return;
        }
        final sequence = params['sequence'];
        if (sequence is int && sequence > _lastForwarded) {
          _lastForwarded = sequence;
        }
      }
    }
    _notifications.add(notification);
  }

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    requestCounts.update(method, (count) => count + 1, ifAbsent: () => 1);
    if (method == 'session.state') stateReads++;
    if (method == 'events.after') replayReads++;
    return inner.request(method, params);
  }

  @override
  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await inner.dispose();
    await _subscription.cancel();
    if (!_notifications.isClosed) await _notifications.close();
  }
}
