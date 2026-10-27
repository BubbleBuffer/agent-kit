// Opt in with BP_TEST_BIN pointing at the public v0.2.2 binary. The provider
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
          // v0.2.2's demo supports the native surface (provider/scripted.rs).
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
  int _lastForwarded = 0;
  int stateReads = 0;
  int replayReads = 0;
  int droppedEvents = 0;
  int injectedGaps = 0;
  bool _disposed = false;
  final requestCounts = <String, int>{};
  final notificationShapes = <Map<String, Object?>>[];

  void dropNextDurableEvent(String chatId) => _dropFor = chatId;

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
        if (_dropFor != null && params['session_id'] == _dropFor) {
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
