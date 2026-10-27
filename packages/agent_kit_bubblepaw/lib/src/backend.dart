import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';

import 'errors.dart';
import 'projection.dart';
import 'transport.dart';

/// A BubblePaw 0.1 stdio host owned by its consuming application.
///
/// Create with [start], await initialization, and always await [dispose].
/// Optional commands are advertised only when the negotiated host feature and
/// the stdio method can carry the kit semantics.
final class BubblePawBackend implements AgentBackend {
  BubblePawBackend._(this._transport, this.workspaceDirectory);

  /// The protocol understood by this adapter (independent of binary version).
  static const protocolVersion = '0.1';

  /// Starts a child host and completes its protocol handshake.
  static Future<BubblePawBackend> start({
    required String binaryPath,
    required String workspaceDirectory,
    required String dataDirectory,
    List<String> arguments = const [],
  }) async => connect(
    await StdioBubblePawTransport.start(
      binaryPath: binaryPath,
      workspaceDirectory: workspaceDirectory,
      dataDirectory: dataDirectory,
      arguments: arguments,
    ),
    workspaceDirectory: workspaceDirectory,
  );

  /// Connects an internal transport. Useful for deterministic protocol peers.
  /// Ownership transfers to the backend, including on handshake failure.
  static Future<BubblePawBackend> connect(
    BubblePawTransport transport, {
    required String workspaceDirectory,
  }) async {
    final backend = BubblePawBackend._(transport, workspaceDirectory);
    backend._subscription = transport.notifications.listen(
      backend._notification,
      onError: backend._transportError,
      onDone: backend._transportDone,
    );
    try {
      final result = _object(await transport.request('initialize'));
      final actual = result['protocol_version'];
      if (actual != protocolVersion) {
        throw BubblePawProtocolMismatch(
          expectedVersion: protocolVersion,
          actualVersion: actual is String ? actual : null,
        );
      }
      backend.features = Set.unmodifiable(
        (result['features'] as List<Object?>? ?? const []).whereType<String>(),
      );
      if (!backend.features.containsAll({'sessions', 'events'})) {
        throw const BubblePawException(
          'missingFeatures',
          'The host does not provide sessions and resumable events.',
        );
      }
      backend._capabilities = KitCapabilities([
        if (backend.features.contains('steer')) KitCapability.steer,
        if (backend.features.contains('question')) KitCapability.questions,
        if (backend.features.contains('todo')) KitCapability.plan,
        if (backend.features.contains('rewind')) KitCapability.rewind,
        KitCapability.rename,
        KitCapability.resume,
        KitCapability.usage,
      ]);
      return backend;
    } catch (_) {
      await backend.dispose();
      rethrow;
    }
  }

  /// The workspace bound to the owned host.
  final String workspaceDirectory;
  final BubblePawTransport _transport;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  final Map<String, BubblePawProjection> _projections = {};
  final Map<String, Json> _states = {};
  final Map<String, Future<ChatSnapshot>> _loading = {};
  final Set<_Watch> _watches = {};
  final _created = StreamController<ChatSummary>.broadcast();
  Future<void>? _disposing;
  bool _closed = false;

  /// Exact features returned by initialize; unknown features are retained.
  late final Set<String> features;
  late final KitCapabilities _capabilities;

  /// New sessions created by [rewindToNewChat] (also called by [rewind]).
  /// The original session is never relabelled as the rewound session.
  Stream<ChatSummary> get createdChats => _created.stream;

  @override
  KitCapabilities get capabilities => _capabilities;

  BubblePawProjection _projection(String id) =>
      _projections.putIfAbsent(id, BubblePawProjection.new);

  Future<Object?> _request(String method, [Json params = const {}]) async {
    if (_closed) throw const KitUnavailable('The BubblePaw host is closed.');
    try {
      return await _transport.request(method, params);
    } on BubblePawException catch (error) {
      // Preserve typed lifecycle diagnostics; raw host/provider error messages
      // never enter a KitError's user-facing message.
      if (error is BubblePawHostExited) rethrow;
      throw switch (error.code) {
        'busy' => const KitBusy(),
        'notFound' => const KitNotFound(),
        'conflict' => const KitConflict(),
        'invalid' => const KitInvalid(),
        'denied' => const KitDenied(),
        'requestTimeout' ||
        'transportClosed' ||
        'writeFailed' => const KitUnavailable(),
        _ => const KitFailed('The BubblePaw command failed.'),
      };
    }
  }

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) async {
    if (cursor != null) {
      throw const KitInvalid('BubblePaw chat lists have no cursor.');
    }
    final result = await _request('session.list');
    final sessions = _objects(result);
    sessions.sort(
      (a, b) =>
          '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'),
    );
    final needle = query?.toLowerCase();
    return ChatPage(
      chats: [
        for (final session
            in sessions
                .where(
                  (s) =>
                      needle == null ||
                      '${s['title'] ?? ''}'.toLowerCase().contains(needle),
                )
                .take(64))
          _projection('${session['id']}').summary(session),
      ],
    );
  }

  @override
  Future<ChatSnapshot> loadChat(String chatId) {
    final current = _loading[chatId];
    if (current != null) return current;
    final future = _load(chatId);
    _loading[chatId] = future;
    unawaited(
      future.then<void>(
        (_) {
          _loading.remove(chatId);
        },
        onError: (Object _, StackTrace _) {
          _loading.remove(chatId);
        },
      ),
    );
    return future;
  }

  Future<ChatSnapshot> _load(String id) async {
    final state = _object(await _request('session.state', {'session_id': id}));
    if (features.contains('approvals')) {
      state['approvals'] = await _request('approval.list', {'session_id': id});
    }
    _states[id] = state;
    return _projection(id)
        .snapshot(state, workspaceDirectory: workspaceDirectory);
  }

  @override
  Stream<KitEvent> events(String chatId, {required int after}) {
    late final _Watch watch;
    final controller = StreamController<KitEvent>(
      onListen: () {
        if (_closed) {
          watch.controller.addError(const KitUnavailable());
          unawaited(watch.controller.close());
          return;
        }
        _watches.add(watch);
        watch.enqueue(
          () => watch.replay(BubblePawProjection.hostSequence(after)),
        );
      },
      onCancel: () {
        watch.closed = true;
        _watches.remove(watch);
      },
    );
    watch = _Watch(this, chatId, controller);
    return controller.stream;
  }

  void _notification(Json notification) {
    final method = notification['method'];
    final params = _object(notification['params']);
    for (final watch in _watches.toList()) {
      if (method == 'events.gap') {
        watch.enqueue(() => watch.recover());
      } else if (method == 'event' && params['session_id'] == watch.chatId) {
        watch.enqueue(() => watch.consume(params));
      }
    }
  }

  void _transportError(Object error, [StackTrace? stack]) {
    for (final watch in _watches.toList()) {
      if (!watch.closed) watch.controller.addError(error, stack);
    }
  }

  void _transportDone() {
    for (final watch in _watches.toList()) {
      unawaited(watch.controller.close());
      watch.closed = true;
    }
    _watches.clear();
  }

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    if (workspace != null && workspace != workspaceDirectory) {
      throw const KitInvalid('This host is bound to one workspace.');
    }
    final session = _object(await _request('session.open', {'title': ?title}));
    return _projection('${session['id']}').summary(session);
  }

  void _text(String text, List<KitRef> refs) {
    if (text.trim().isEmpty) throw const KitInvalid('Enter a message.');
    if (RegExp(r'^/(rename|rewind|compact|reload)(\s|$)')
        .hasMatch(text.trim())) {
      throw const KitInvalid('Use a chat action for BubblePaw host commands.');
    }
    if (refs.isNotEmpty) {
      throw const KitInvalid(
        'BubblePaw stdio accepts text without attachments.',
      );
    }
  }

  @override
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    _text(text, refs);
    try {
      final result = _object(
        await _request('run.start', {'session_id': chatId, 'text': text}),
      );
      if (result['id'] is! String) {
        // Slash commands can return rename/rewind/compact results instead of
        // runs. Force a snapshot, never claim that these started a model turn.
        await _refreshWatches(chatId);
        throw const KitInvalid(
          'Use the corresponding chat action for host commands.',
        );
      }
      return SendResult(
        delivery: SendDelivery.started,
        runId: result['id'] as String,
      );
    } on KitBusy {
      final id = await followup(chatId, text, refs: refs);
      return SendResult(delivery: SendDelivery.queued, inputId: id);
    }
  }

  @override
  Future<String> steer(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    _require(KitCapability.steer);
    return _input('run.steer', chatId, text, refs);
  }

  @override
  Future<String> followup(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    if (!features.contains('follow_up')) {
      throw const KitInvalid('This host does not accept follow-up input.');
    }
    return _input('run.follow_up', chatId, text, refs);
  }

  Future<String> _input(
    String method,
    String chatId,
    String text,
    List<KitRef> refs,
  ) async {
    _text(text, refs);
    final result = _object(
      await _request(method, {'session_id': chatId, 'text': text}),
    );
    if (result['id'] is! String) {
      throw const KitInvalid('A queued input was not created.');
    }
    await _refreshWatches(chatId);
    return result['id'] as String;
  }

  @override
  Future<void> cancel(String chatId) async {
    await _request('run.cancel', {'session_id': chatId});
  }

  @override
  Future<void> resume(String chatId) async {
    _require(KitCapability.resume);
    await _request('run.resume', {'session_id': chatId});
  }

  @override
  Future<void> decideApproval(
    String chatId,
    String approvalId,
    ApprovalDecision decision,
  ) async {
    if (!features.contains('approvals')) {
      throw const KitInvalid('This host does not provide approval requests.');
    }
    final approvals = _objects(
      await _request('approval.list', {'session_id': chatId}),
    );
    if (!approvals.any((a) => a['id'] == approvalId)) throw const KitNotFound();
    await _request('approval.decide', {
      'approval_id': approvalId,
      'decision': switch (decision.choice) {
        ApprovalChoice.approve => 'approve',
        ApprovalChoice.approveForSession => 'approve_session',
        ApprovalChoice.deny => 'deny',
      },
      if (decision.reason != null) 'reason': decision.reason,
    });
  }

  @override
  Future<void> answerQuestion(
    String chatId,
    String questionId,
    Map<String, QuestionAnswer> answers,
  ) async {
    _require(KitCapability.questions);
    final snap = await loadChat(chatId);
    final matching = snap.questions.where((q) => q.id == questionId);
    if (matching.isEmpty) throw const KitNotFound();
    final question = matching.first;
    if (!question.isPending) throw const KitConflict();
    if (question.items.length != 1 ||
        answers.length != 1 ||
        !answers.containsKey(question.items.single.id)) {
      throw const KitInvalid('BubblePaw accepts one answer per question.');
    }
    final answer = answers.values.single;
    if (answer.skipped ||
        answer.choices.length > 1 ||
        (answer.choices.isNotEmpty && answer.text != null)) {
      throw const KitInvalid('Choose one suggestion or enter one text answer.');
    }
    final text =
        answer.text ?? (answer.choices.isEmpty ? '' : answer.choices.single);
    if (text.trim().isEmpty) throw const KitInvalid('Enter an answer.');
    if (answer.choices.isNotEmpty &&
        !question.items.single.options.any(
          (o) => o.label == answer.choices.single,
        )) {
      throw const KitInvalid('Choose one of the suggested answers.');
    }
    await _request('question.answer', {
      'session_id': chatId,
      'question_id': questionId,
      'text': text,
    });
  }

  @override
  Future<void> rename(String chatId, String title) async {
    _require(KitCapability.rename);
    await _request('session.rename', {'session_id': chatId, 'title': title});
    await _refreshWatches(chatId);
  }

  /// Rewinds files/history into a new session and returns its summary.
  /// BubblePaw includes the selected canonical message in the fork.
  Future<ChatSummary> rewindToNewChat(String chatId, String messageId) async {
    _require(KitCapability.rewind);
    final result = _object(
      await _request('session.rewind', {
        'session_id': chatId,
        'message_id': messageId,
      }),
    );
    final id = result['session_id'];
    if (id is! String) {
      throw const KitFailed('The host returned no rewound chat.');
    }
    final snap = await loadChat(id);
    final summary = ChatSummary.of(snap);
    if (!_created.isClosed) _created.add(summary);
    return summary;
  }

  @override
  Future<void> rewind(String chatId, String toItemId) async {
    await rewindToNewChat(chatId, toItemId);
  }

  Future<void> _refreshWatches(String chatId) async {
    for (final watch in _watches.where((w) => w.chatId == chatId).toList()) {
      watch.enqueue(watch.refresh);
    }
  }

  void _require(KitCapability capability) {
    if (!capabilities.has(capability)) throw KitUnsupported(capability);
  }

  Future<T> _missing<T>(KitCapability capability) =>
      Future<T>.error(KitUnsupported(capability));

  @override
  Future<void> sendQueuedNow(String chatId, String inputId) =>
      _missing(KitCapability.sendQueuedNow);
  @override
  Future<void> editQueued(String chatId, String inputId, String text) =>
      _missing(KitCapability.queueEdit);
  @override
  Future<void> removeQueued(String chatId, String inputId) =>
      _missing(KitCapability.queueEdit);
  @override
  Future<void> answerChildQuestion(
    String chatId,
    String childId,
    String questionId,
    String text,
  ) => _missing(KitCapability.answerChildQuestion);
  @override
  Future<void> archive(String chatId, {bool archived = true}) =>
      _missing(KitCapability.archive);
  @override
  Future<ChatSummary> fork(String chatId, {String? atItemId}) =>
      _missing(KitCapability.fork);
  @override
  Future<void> cancelChild(String chatId, String childId) =>
      _missing(KitCapability.children);
  @override
  Future<void> cancelJob(String chatId, String jobId) =>
      _missing(KitCapability.jobs);
  @override
  Future<void> undoEdit(String chatId, String editId) =>
      _missing(KitCapability.editUndo);
  @override
  Future<List<KitChoice>> listModels() => _missing(KitCapability.models);
  @override
  Future<List<KitChoice>> listProfiles() => _missing(KitCapability.profiles);
  @override
  Future<void> setModel(String chatId, String modelId) =>
      _missing(KitCapability.models);
  @override
  Future<void> setProfile(String chatId, String profileId) =>
      _missing(KitCapability.profiles);
  @override
  Future<ContextDetails> loadContext(String chatId) =>
      _missing(KitCapability.context);
  @override
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  ) => _missing(KitCapability.context);
  @override
  Future<ContextSummary> loadSummary(String chatId, String summaryId) =>
      _missing(KitCapability.context);

  /// Gracefully stops only the host owned by this backend; idempotent.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    await _subscription.cancel();
    for (final watch in _watches.toList()) {
      watch.closed = true;
      unawaited(watch.controller.close());
    }
    _watches.clear();
    await _transport.dispose();
    unawaited(_created.close());
  }
}

final class _Watch {
  _Watch(this.backend, this.chatId, this.controller) {
    final state = backend._states[chatId];
    view = state == null
        ? ChatSnapshot.empty(chatId)
        : projection.snapshot(
            state,
            workspaceDirectory: backend.workspaceDirectory,
          );
  }
  final BubblePawBackend backend;
  final String chatId;
  final StreamController<KitEvent> controller;
  final BubblePawProjection projection = BubblePawProjection();
  late ChatSnapshot view;
  Future<void> _tail = Future<void>.value();
  bool closed = false;

  // Only delivered durable host events advance this cursor. Loading a newer
  // snapshot must not hide events that subscribers have never received.
  int cursor = 0;
  int _recoveries = 0;

  void enqueue(Future<void> Function() action) {
    _tail = _tail
        .then((_) async {
          if (!closed) await action();
        })
        .catchError((Object error, StackTrace stack) {
          if (!closed) controller.addError(error, stack);
        });
  }

  void emit(KitEvent event) {
    if (closed) return;
    view = reduce(view, event);
    controller.add(event);
  }

  Future<void> replay(int after) async {
    cursor = after;
    // A cached load can be newer than this subscription's requested cursor.
    // Keep its view for diffs, but never let it suppress requested replay.
    projection.replayFrom(chatId, after);
    final result = await _replay();
    if (result.resync) {
      await recover();
    } else if (result.refresh) {
      await refresh();
    }
  }

  Future<_ReplayResult> _replay({int? through}) async {
    var refreshNeeded = false;
    var resyncNeeded = false;
    while (!closed) {
      final before = cursor;
      final result = _object(
        await backend._request('events.after', {
          'session_id': chatId,
          'after': cursor,
          'limit': 1000,
        }),
      );
      // v0.2.2 still returns retained events when the earlier prefix was
      // pruned. Deliver those events and page onward; resync describes the
      // missing prefix, not permission to discard the available suffix.
      resyncNeeded = result['resync'] == true || resyncNeeded;
      final events = _objects(result['events']);
      for (final event in events) {
        if (through != null && (event['sequence'] as int? ?? 0) > through) {
          return _ReplayResult(resync: resyncNeeded, refresh: refreshNeeded);
        }
        refreshNeeded = _consume(event) || refreshNeeded;
      }
      if (events.length < 1000) {
        return _ReplayResult(resync: resyncNeeded, refresh: refreshNeeded);
      }
      if (cursor <= before) {
        throw const KitUnavailable('BubblePaw replay made no progress.');
      }
    }
    return _ReplayResult(resync: resyncNeeded, refresh: refreshNeeded);
  }

  // Replaying a page never recursively refreshes. Its caller reconciles once
  // at a snapshot barrier, then reads later durable events from the same cursor.
  bool _consume(Json event) {
    if (closed) return false;
    final seq = event['sequence'] as int? ?? 0;
    final durable = event['durable'] != false;
    if ((durable && seq <= cursor) || (!durable && seq < cursor)) return false;
    if (durable) cursor = seq;
    var refreshNeeded = false;
    for (final kit in projection.event(event)) {
      if (kit is GapEvent) {
        // The source stream cannot describe this view (e.g. a text retry or
        // nested transient tool). Its fresh canonical state is authoritative.
        refreshNeeded = true;
        _projectionGap = true;
      } else {
        emit(kit);
      }
    }
    return refreshNeeded || _needsRefresh(event);
  }

  bool _projectionGap = false;

  static bool _needsRefresh(Json event) => switch (event['type']) {
    'run_started' ||
    'run_finished' ||
    'steering_accepted' ||
    'followup_queued' ||
    'session_settled' => true,
    'host_state_changed' => event['key'] == 'usage.last_request',
    _ => false,
  };

  Future<void> consume(Json event) async {
    if (_consume(event)) {
      if (_projectionGap) {
        await recover();
      } else {
        await refresh();
      }
    }
  }

  /// Refresh representable host state without reporting transport loss or
  /// resetting provisional text/tool reconciliation. Replay precedes the diff:
  /// a snapshot can already contain a tool start whose notification is queued.
  Future<void> refresh() => _synchronize(gap: false);

  Future<void> recover() => _synchronize(gap: true);

  Future<void> _synchronize({required bool gap}) async {
    if (closed) return;
    if (++_recoveries > 3) {
      _recoveries--;
      throw const KitUnavailable(
        'BubblePaw could not recover its event cursor.',
      );
    }
    try {
      if (gap) emit(GapEvent(seq: cursor * 16 + 15, chat: chatId));
      var snapshot = await backend.loadChat(chatId);
      if (closed) return;
      // A concurrent caller may have started the shared load before the most
      // recent event. Retry rather than applying an older snapshot over it.
      if (BubblePawProjection.hostSequence(snapshot.seq) < cursor) {
        snapshot = await backend.loadChat(chatId);
        if (BubblePawProjection.hostSequence(snapshot.seq) < cursor) {
          throw const KitUnavailable('BubblePaw returned an older snapshot.');
        }
      }
      final barrier = BubblePawProjection.hostSequence(snapshot.seq);
      // Even after retention loss, newly committed events can arrive during
      // session.state. Deliver every available event up to its barrier before
      // adopting canonical state; only the actually missing prefix is lost.
      final replayed = await _replay(through: barrier);
      if (replayed.resync) {
        // Retention removed an earlier prefix. Available retained events
        // have been delivered; explicitly resync the missing part from state.
        if (!gap) emit(GapEvent(seq: cursor * 16 + 15, chat: chatId));
        _adopt(snapshot);
      } else if (gap || _projectionGap) {
        if (!gap) emit(GapEvent(seq: cursor * 16 + 15, chat: chatId));
        // Replay has delivered every retained durable event through this
        // barrier. Only now may canonical state replace stream state, so
        // future live fragments use the same baseline as the reloaded feed.
        _adopt(snapshot);
      } else {
        final changes = _changes(snapshot);
        final first = view.seq >= barrier * 16
            ? view.seq + 1
            : barrier * 16 + 2;
        if (changes.isNotEmpty &&
            changes.length > barrier * 16 + 14 - first + 1) {
          // The fixed 16-slot wire mapping cannot encode an arbitrarily
          // large snapshot diff, or mutation at an already loaded cursor.
          // Every replayable durable event has still been delivered first.
          if (!gap) emit(GapEvent(seq: cursor * 16 + 15, chat: chatId));
          _adopt(snapshot);
        } else {
          for (var index = 0; index < changes.length; index++) {
            emit(changes[index](first + index));
          }
        }
      }
      final later = await _replay();
      if (later.resync) {
        await recover();
      } else if (later.refresh || _projectionGap) {
        // A continuing run can advance during every snapshot request. Do not
        // count ordinary forward progress against the resync retry bound.
        enqueue(_projectionGap ? () => recover() : refresh);
      }
    } finally {
      _recoveries--;
    }
  }

  void _adopt(ChatSnapshot snapshot) {
    final base = BubblePawProjection.hostSequence(snapshot.seq) * 16;
    final sequence = view.seq >= base ? view.seq + 1 : base + 2;
    final usage = snapshot.usage;
    // Recovery snapshots carry authoritative session totals too. Deliver the
    // change after retained durable events, before replacing reconciliation
    // state. A fully loaded cursor has no slot; the explicit gap covers it.
    if (usage != null && usage != view.usage && sequence <= base + 14) {
      emit(UsageUpdated(seq: sequence, chat: chatId, usage: usage));
    }
    projection.adopt(snapshot);
    view = snapshot;
    cursor = BubblePawProjection.hostSequence(snapshot.seq);
    _projectionGap = false;
  }

  List<KitEvent Function(int)> _changes(ChatSnapshot snapshot) {
    final changes = <KitEvent Function(int)>[];
    if (snapshot.title != view.title) {
      changes.add(
        (seq) => ChatRenamed(seq: seq, chat: chatId, title: snapshot.title),
      );
    }
    for (final item in snapshot.items) {
      if (view.items.any((old) => old.id == item.id)) continue;
      if (item is UserMessage) {
        changes.add(
          (seq) => UserMessageAdded(
            seq: seq,
            chat: chatId,
            at: item.at,
            itemId: item.id,
            text: item.text,
            refs: item.refs,
          ),
        );
      } else if (item is SystemLine) {
        changes.add(
          (seq) => SystemLineAdded(
            seq: seq,
            chat: chatId,
            at: item.at,
            itemId: item.id,
            text: item.text,
          ),
        );
      }
    }
    for (final old in view.queue) {
      if (!snapshot.queue.any((input) => input.id == old.id)) {
        changes.add(
          (seq) => QueueRemoved(seq: seq, chat: chatId, inputId: old.id),
        );
      }
    }
    for (final input in snapshot.queue) {
      if (!view.queue.contains(input)) {
        changes.add((seq) => QueueAdded(seq: seq, chat: chatId, input: input));
      }
    }
    final usage = snapshot.usage;
    if (usage != null && usage != view.usage) {
      // Replacement session-own totals, never addition of run or request usage.
      changes.add((seq) => UsageUpdated(seq: seq, chat: chatId, usage: usage));
    }
    return changes;
  }
}

final class _ReplayResult {
  const _ReplayResult({this.resync = false, this.refresh = false});
  final bool resync;
  final bool refresh;
}

Json _object(Object? value) => value is Map<String, Object?>
    ? Map<String, Object?>.of(value)
    : <String, Object?>{};
List<Json> _objects(Object? value) => value is List<Object?>
    ? value
          .whereType<Map<String, Object?>>()
          .map(Map<String, Object?>.of)
          .toList()
    : <Json>[];
