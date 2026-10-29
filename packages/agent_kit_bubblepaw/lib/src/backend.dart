import 'dart:async';
import 'dart:collection';

import 'package:agent_kit_core/agent_kit_core.dart';

import 'context_projection.dart';
import 'errors.dart';
import 'projection.dart';
import 'provider_projection.dart';
import 'transport.dart';

/// A BubblePaw 0.1 stdio host owned by its consuming application.
///
/// Create with [start], await initialization, and always await [dispose].
/// Optional commands are advertised only when the negotiated host feature and
/// the stdio method can carry the kit semantics.
final class BubblePawBackend
    implements AgentBackend, BackendConstraintsProvider {
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
        KitCapability.send,
        KitCapability.cancel,
        KitCapability.createChat,
        if (backend.features.contains('approvals')) KitCapability.approve,
        if (backend.features.contains('steer')) KitCapability.steer,
        if (backend.features.contains('question')) KitCapability.questions,
        if (backend.features.contains('todo')) KitCapability.plan,
        if (backend.features.contains('rewind')) KitCapability.rewind,
        KitCapability.rename,
        KitCapability.resume,
        KitCapability.usage,
        if (backend.features.contains('context')) KitCapability.context,
        if (backend.features.contains('question.answer_child'))
          KitCapability.answerChildQuestion,
        if (backend.features.contains('child.cancel')) KitCapability.children,
        if (backend.features.contains('providers.list'))
          KitCapability.providers,
        if (backend.features.contains('roles.set_main'))
          KitCapability.defaultModel,
        // The composer's model pick needs both: the list and the setter.
        if (backend.features.containsAll({'providers.list', 'roles.set_main'}))
          KitCapability.models,
      ]);
      backend._constraints = BackendConstraints(
        acceptsReferences: false,
        followUpWhileRunning: backend.features.contains('follow_up'),
        supportedQuestionKinds: backend.features.contains('question')
            ? const {QuestionKind.text, QuestionKind.pickOne}
            : const <QuestionKind>{},
      );
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
  final Map<String, _Extras> _extras = {};
  final Map<String, int> _messageSeqs = {};
  final Map<String, ChildAgent> _childAgents = {};
  final Map<String, ChildQuestion> _childQuestions = {};
  final Set<String> _staleChildren = {};
  final Map<String, String> _childParents = {};
  final Map<String, Future<ChatSnapshot>> _loading = {};
  final Set<_Watch> _watches = {};
  final _created = StreamController<ChatSummary>.broadcast();
  Future<void>? _disposing;
  bool _closed = false;

  /// Exact features returned by initialize; unknown features are retained.
  late final Set<String> features;
  late final KitCapabilities _capabilities;
  late final BackendConstraints _constraints;

  final _lost = Completer<Object>();

  /// Completes with the error that ended the host connection (a
  /// [BubblePawHostExited] when the child exits), whether or not any event
  /// stream is open. Never completes after [dispose] and never completes with
  /// an error, so an unobserved future is safe.
  Future<Object> get connectionLost => _lost.future;

  /// New sessions created by [rewindToNewChat] (also called by [rewind]).
  /// The original session is never relabelled as the rewound session.
  Stream<ChatSummary> get createdChats => _created.stream;

  @override
  KitCapabilities get capabilities => _capabilities;

  @override
  BackendConstraints get constraints => _constraints;

  // The host default (`active_main`) as last read. Only the composer's pick
  // shows it, so a failed read leaves the last run's model there instead.
  String? _defaultModel;
  Future<void>? _readingDefault;

  Future<void> _knowDefaultModel() {
    if (_defaultModel != null) return Future.value();
    return _readingDefault ??= () async {
      try {
        await listProviders();
      } on KitUnavailable {
        rethrow;
      } on KitError {
        // The snapshot goes without a default.
      } finally {
        _readingDefault = null;
      }
    }();
  }

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

  /// Chats per page when the host pages `session.list`.
  static const chatPageSize = 100;

  /// With feature `session.list.pagination` the host pages the list (newest
  /// created first, [chatPageSize] a page) and [cursor] is the previous
  /// page's `next_cursor`. Without it the host returns every chat at once,
  /// sorted here by update time, and has no cursor. The title [query]
  /// filters the returned page only.
  @override
  Future<ChatPage> listChats({String? cursor, String? query}) async {
    final paged = features.contains('session.list.pagination');
    if (cursor != null && !paged) {
      throw const KitInvalid('BubblePaw chat lists have no cursor.');
    }
    final Object? result;
    String? next;
    if (paged) {
      final page = _object(
        await _request('session.list', {
          'limit': chatPageSize,
          'cursor': ?cursor,
        }),
      );
      result = page['sessions'];
      final wire = page['next_cursor'];
      next = wire is String && wire.isNotEmpty ? wire : null;
    } else {
      result = await _request('session.list');
    }
    final sessions = _objects(result);
    if (!paged) {
      sessions.sort(
        (a, b) =>
            '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'),
      );
    }
    final needle = query?.toLowerCase();
    return ChatPage(
      chats: [
        for (final session in sessions.where(
          (s) =>
              needle == null ||
              '${s['title'] ?? ''}'.toLowerCase().contains(needle),
        ))
          _projection('${session['id']}').summary(session),
      ],
      nextCursor: next,
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
    final extras = await _loadExtras(id, state);
    _states[id] = state;
    _extras[id] = extras;
    if (capabilities.has(KitCapability.models)) await _knowDefaultModel();
    return _projection(id).snapshot(
      state,
      workspaceDirectory: workspaceDirectory,
      children: extras.children,
      context: extras.context,
      compactions: extras.compactions,
      defaultModel: _defaultModel,
    );
  }

  // Context and child reads add to session.state only when their features are
  // negotiated. A failing auxiliary read leaves that part out rather than
  // making the whole chat unloadable; a lost host still fails.
  Future<_Extras> _loadExtras(String id, Json state) async {
    ContextView? context;
    var compactions = const <CompactionItem>[];
    if (features.contains('context')) {
      try {
        final events = _objects(
          _object(
            await _request('context.events', {'session_id': id}),
          )['events'],
        );
        compactions = compactionItems(events);
        final wire = _object(
          await _request('context.view', {'session_id': id}),
        )['view'];
        if (wire is Map<String, Object?>) {
          final view = _object(wire);
          await _resolveSeqs(id, viewMessageIds(view));
          context = contextView(
            view,
            seq: _seqLookup(id),
            windowTokens:
                _object(_object(state['usage'])['context'])['window_tokens']
                    as int?,
            appliedAt: latestApplied(events),
          );
        }
      } on KitUnavailable {
        rethrow;
      } on KitError {
        context = null;
      }
    }
    var children = const <ChildAgent>[];
    if (features.contains('child_events')) {
      children = await _loadChildren(id);
    }
    return _Extras(children, context, compactions);
  }

  // Child records are cached only while the parent has an open event stream:
  // that stream delivers the child events which mark a record stale. Without
  // one, every read refetches.
  Future<List<ChildAgent>> _loadChildren(String parent) async {
    final watched = _watches.any((w) => w.chatId == parent && !w.closed);
    final listed = _objects(await _request('session.list'));
    final ids = [
      for (final session in listed)
        if (session['parent_session_id'] == parent && session['id'] is String)
          session['id']! as String,
    ];
    if (!watched) {
      for (final id in ids) {
        _childAgents.remove(id);
        _childQuestions.remove(id);
      }
    }
    final fetch = [
      for (final id in ids)
        if (!_childAgents.containsKey(id) || _staleChildren.contains(id)) id,
    ];
    for (var i = 0; i < fetch.length; i += 6) {
      await Future.wait([
        for (final id in fetch.skip(i).take(6)) _fetchChild(parent, id),
      ]);
    }
    final agents = [for (final id in ids) ?_childAgents[id]];
    if (!watched) {
      for (final id in ids) {
        _childAgents.remove(id);
      }
    }
    agents.sort((a, b) {
      final at = a.startedAt, bt = b.startedAt;
      if (at != null && bt != null && at != bt) return at.compareTo(bt);
      if ((at == null) != (bt == null)) return at == null ? 1 : -1;
      return a.id.compareTo(b.id);
    });
    return agents;
  }

  Future<void> _fetchChild(String parent, String id) async {
    _staleChildren.remove(id);
    _childParents[id] = parent;
    try {
      final state = _object(
        await _request('session.state', {'session_id': id}),
      );
      final agent = childAgent(state);
      _childAgents[id] = agent;
      final question = childQuestion(id, state['question']);
      if (question == null) {
        _childQuestions.remove(id);
      } else {
        _childQuestions[id] = question;
      }
    } on KitNotFound {
      _childAgents.remove(id);
      _childQuestions.remove(id);
    }
  }

  // The host sequence of each message ID the host named, resolved through
  // history.range and kept: a message keeps its sequence.
  Future<void> _resolveSeqs(String chat, Iterable<String> ids) async {
    final todo = {
      for (final id in ids)
        if (!_messageSeqs.containsKey('$chat\u0000$id')) id,
    }.toList();
    for (var i = 0; i < todo.length; i += 8) {
      await Future.wait([
        for (final id in todo.skip(i).take(8)) _resolveSeq(chat, id),
      ]);
    }
  }

  Future<void> _resolveSeq(String chat, String id) async {
    try {
      final page = _object(
        await _request('history.range', {
          'session_id': chat,
          'first_message_id': id,
          'last_message_id': id,
          'limit': 1,
        }),
      );
      final rows = _objects(page['messages']);
      final seq = rows.isEmpty ? null : rows.first['seq'];
      if (seq is int) _messageSeqs['$chat\u0000$id'] = seq;
    } on KitNotFound {
      return;
    } on KitInvalid {
      return;
    }
  }

  SeqOf _seqLookup(String chat) =>
      (id) => id == null ? null : _messageSeqs['$chat\u0000$id'];

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
        if (!_watches.any((w) => w.chatId == chatId)) {
          // Cached child records are only kept current by an open stream.
          for (final entry in _childParents.entries.toList()) {
            if (entry.value != chatId) continue;
            _childAgents.remove(entry.key);
            _childQuestions.remove(entry.key);
          }
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
        watch.notifyGap();
      } else if (method == 'event' && params['session_id'] == watch.chatId) {
        watch.notify(params);
      }
    }
  }

  void _transportError(Object error, [StackTrace? stack]) {
    if (!_closed && !_lost.isCompleted) _lost.complete(error);
    for (final watch in _watches.toList()) {
      if (!watch.closed) watch.controller.addError(error, stack);
    }
  }

  void _transportDone() {
    if (!_closed && !_lost.isCompleted) _lost.complete(const KitUnavailable());
    for (final watch in _watches.toList()) {
      unawaited(watch.controller.close());
      watch.closed = true;
    }
    _watches.clear();
  }

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    _require(KitCapability.createChat);
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
    _require(KitCapability.send);
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
      if (!constraints.followUpWhileRunning) rethrow;
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
    _require(KitCapability.send);
    if (!constraints.followUpWhileRunning) {
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
    _require(KitCapability.cancel);
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
    _require(KitCapability.approve);
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
  ) async {
    _require(KitCapability.answerChildQuestion);
    if (text.trim().isEmpty) throw const KitInvalid('Enter an answer.');
    await _request('question.answer_child', {
      'parent': chatId,
      'child': childId,
      'question_id': questionId,
      'text': text,
    });
    _staleChildren.add(childId);
    await _refreshWatches(chatId);
  }

  @override
  Future<void> archive(String chatId, {bool archived = true}) =>
      _missing(KitCapability.archive);
  @override
  Future<ChatSummary> fork(String chatId, {String? atItemId}) =>
      _missing(KitCapability.fork);

  /// Cancels the child and everything it started. Needs feature
  /// `child.cancel`; [chatId] must be the child's direct parent.
  @override
  Future<void> cancelChild(String chatId, String childId) async {
    _require(KitCapability.children);
    await _request('child.cancel', {'parent': chatId, 'child': childId});
    _staleChildren.add(childId);
    await _refreshWatches(chatId);
  }

  @override
  Future<void> cancelJob(String chatId, String jobId) =>
      _missing(KitCapability.jobs);
  @override
  Future<void> undoEdit(String chatId, String editId) =>
      _missing(KitCapability.editUndo);
  @override
  Future<List<KitChoice>> listModels() async {
    _require(KitCapability.models);
    return modelChoices(await listProviders());
  }

  @override
  Future<List<KitChoice>> listProfiles() => _missing(KitCapability.profiles);

  /// The host has one default model, not one per chat: this sets it for
  /// every chat, as [setDefaultModel] does. A run in progress keeps its model.
  @override
  Future<void> setModel(String chatId, String modelId) async {
    _require(KitCapability.models);
    await setDefaultModel(modelId);
  }

  @override
  Future<ProviderSetup> listProviders() async {
    _require(KitCapability.providers);
    final setup = providerSetup(_object(await _request('providers.list')));
    _defaultModel = setup.defaultModel;
    return setup;
  }

  @override
  Future<ProviderSetup> setDefaultModel(String modelId) async {
    _require(KitCapability.defaultModel);
    final id = modelId.trim();
    if (!id.contains('/')) {
      throw const KitInvalid('Choose a model as provider/model.');
    }
    final setup = providerSetup(
      _object(await _request('roles.set_main', {'model': id})),
    );
    _defaultModel = setup.defaultModel;
    for (final watch in _watches.toList()) {
      watch.enqueue(watch.refresh);
    }
    return setup;
  }

  @override
  Future<void> setProfile(String chatId, String profileId) =>
      _missing(KitCapability.profiles);
  @override
  Future<ContextDetails> loadContext(String chatId) async {
    _require(KitCapability.context);
    final structure = _object(
      await _request('context.structure', {'session_id': chatId}),
    );
    final events = _objects(
      _object(
        await _request('context.events', {'session_id': chatId}),
      )['events'],
    );
    final view = _object(
      await _request('context.view', {'session_id': chatId}),
    )['view'];
    await _resolveSeqs(chatId, structureMessageIds(structure, events));
    return contextDetails(
      structure: structure,
      events: events,
      view: view is Map<String, Object?> ? _object(view) : null,
      seq: _seqLookup(chatId),
    );
  }

  /// Pages are read to the end of the range, at most 20 pages of 1000.
  @override
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  ) async {
    _require(KitCapability.context);
    if (firstSeq < 0 || lastSeq < firstSeq) {
      throw const KitInvalid('The history range must be ordered.');
    }
    final messages = <HistoryMessage>[];
    var next = firstSeq;
    for (var page = 0; page < 20; page++) {
      final result = _object(
        await _request('history.range', {
          'session_id': chatId,
          'first_seq': next,
          'last_seq': lastSeq,
          'limit': 1000,
        }),
      );
      messages.addAll(_objects(result['messages']).map(historyMessage));
      final more = result['next_seq'];
      if (more is! int || more <= next) break;
      next = more;
    }
    return HistoryPage(
      firstSeq: firstSeq,
      lastSeq: lastSeq,
      messages: messages,
    );
  }

  @override
  Future<ContextSummary> loadSummary(String chatId, String summaryId) async {
    _require(KitCapability.context);
    final parsed = parseSummaryId(summaryId);
    if (parsed == null) throw const KitNotFound();
    final known = (await loadContext(chatId)).summary(summaryId);
    if (known == null) throw const KitNotFound();
    final result = _object(
      await _request('context.summary', {
        'session_id': chatId,
        'kind': parsed.$1.name,
        'id': parsed.$2,
      }),
    );
    return ContextSummary.fromJson({
      ...known.toJson(),
      'text': result['summary'] is String ? result['summary'] : null,
    });
  }

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
    final extras = backend._extras[chatId];
    view = state == null
        ? ChatSnapshot.empty(chatId)
        : projection.snapshot(
            state,
            workspaceDirectory: backend.workspaceDirectory,
            children: extras?.children ?? const [],
            context: extras?.context,
            compactions: extras?.compactions ?? const [],
          );
  }
  final BubblePawBackend backend;
  final String chatId;
  final StreamController<KitEvent> controller;
  final BubblePawProjection projection = BubblePawProjection();
  late ChatSnapshot view;
  Future<void> _tail = Future<void>.value();
  final _notifications = Queue<_PendingNotification>();
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

  void notify(Json event) => _queueNotification(event);

  void notifyGap() => _queueNotification(null);

  void _queueNotification(Json? event) {
    final pending = _PendingNotification(event);
    _notifications.add(pending);
    enqueue(() async {
      if (pending.consumed) return;
      _notifications.removeFirst();
      pending.consumed = true;
      if (event == null) {
        await recover();
      } else {
        await consume(event);
      }
    });
  }

  // A snapshot refresh can replay a later durable event while earlier live
  // notifications wait behind it in _tail. Deliver that buffered prefix first:
  // advancing the cursor would otherwise discard a confirming paragraph and
  // misclassify the next model request as a retry. Original queued actions
  // become no-ops; replay and notification copies still share durable dedupe.
  bool _drainNotifications(int through) {
    var refreshNeeded = false;
    while (_notifications.isNotEmpty) {
      final pending = _notifications.first;
      final event = pending.event;
      // An explicit host gap is an ordering barrier. Its queued recovery must
      // report the discontinuity before any later notification is delivered.
      if (event == null || (event['sequence'] as int? ?? 0) > through) break;
      _notifications.removeFirst();
      pending.consumed = true;
      refreshNeeded = _consume(event) || refreshNeeded;
    }
    return refreshNeeded;
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
    var refreshNeeded = _drainNotifications(cursor);
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
        final sequence = event['sequence'] as int? ?? 0;
        if (through != null && sequence > through) {
          refreshNeeded = _drainNotifications(through) || refreshNeeded;
          return _ReplayResult(resync: resyncNeeded, refresh: refreshNeeded);
        }
        refreshNeeded = _drainNotifications(sequence) || refreshNeeded;
        refreshNeeded = _consume(event) || refreshNeeded;
      }
      refreshNeeded = _drainNotifications(through ?? cursor) || refreshNeeded;
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
    final child = childOfEvent(event);
    if (child != null) backend._staleChildren.add(child);
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

  bool _needsRefresh(Json event) => switch (event['type']) {
    'context_compaction' => backend.features.contains('context'),
    'child_run_state_changed' => backend.features.contains('child_events'),
    'run_started' ||
    'run_finished' ||
    'steering_accepted' ||
    'followup_queued' ||
    'session_settled' => true,
    'host_state_changed' =>
      event['key'] == 'usage.last_request' ||
          (backend.features.contains('child_events') &&
              childOfEvent(event) != null),
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
        if (changes == null ||
            (changes.isNotEmpty &&
                changes.length > barrier * 16 + 14 - first + 1)) {
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

  // Null when the snapshot cannot be reached by events from the current view.
  List<KitEvent Function(int)>? _changes(ChatSnapshot snapshot) {
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
      } else if (item is CompactionItem) {
        changes.add(
          (seq) => CompactionUpdated(
            seq: seq,
            chat: chatId,
            at: item.at,
            itemId: item.id,
            state: item.state,
            eventId: item.eventId,
            episodesSummarized: item.episodesSummarized,
            tokensBefore: item.tokensBefore,
            tokensAfter: item.tokensAfter,
            detail: item.detail,
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
    // Only the host default can change under a view; without the model pick
    // the snapshot's model is the last run's, which run events already carry.
    final model = snapshot.model;
    if (backend.capabilities.has(KitCapability.models) &&
        model != null &&
        model != view.model) {
      changes.add(
        (seq) => ChatSettingsChanged(seq: seq, chat: chatId, model: model),
      );
    }
    final usage = snapshot.usage;
    if (usage != null && usage != view.usage) {
      // Replacement session-own totals, never addition of run or request usage.
      changes.add((seq) => UsageUpdated(seq: seq, chat: chatId, usage: usage));
    }
    final context = snapshot.context;
    if (context != null && context != view.context) {
      changes.add(
        (seq) => ContextChanged(seq: seq, chat: chatId, context: context),
      );
    }
    final childChanges = _childChanges(snapshot);
    if (childChanges == null) return null;
    return changes..addAll(childChanges);
  }

  // Children reach a view through their records, not through events with the
  // task and result in them: a new child is spawned, a question appears or
  // resolves, an ended child finishes. A child that ended and runs again
  // cannot be shown by an event (an ended child never leaves its state), so
  // that returns null and the caller resyncs.
  List<KitEvent Function(int)>? _childChanges(ChatSnapshot snapshot) {
    final changes = <KitEvent Function(int)>[];
    final known = {for (final c in view.children) c.id: c};
    for (final child in snapshot.children) {
      final old = known[child.id];
      final question = child.pendingQuestion;
      if (old == null) {
        changes.add(
          (seq) => ChildSpawned(
            seq: seq,
            chat: chatId,
            at: child.startedAt,
            childId: child.id,
            task: child.task,
          ),
        );
        if (question != null) {
          changes.add(
            (seq) =>
                ChildQuestionAsked(seq: seq, chat: chatId, question: question),
          );
        }
        if (child.state.isEnded) {
          changes.add(
            (seq) => ChildFinished(
              seq: seq,
              chat: chatId,
              at: child.endedAt,
              childId: child.id,
              state: child.state,
              result: child.result,
            ),
          );
        }
        continue;
      }
      if (old.state.isEnded) {
        if (!child.state.isEnded) return null;
        continue;
      }
      final before = old.pendingQuestion;
      if (before != null && before.id != question?.id) {
        final last = backend._childQuestions[child.id];
        final resolved =
            last != null && last.id == before.id && !last.isPending;
        changes.add(
          (seq) => ChildQuestionResolved(
            seq: seq,
            chat: chatId,
            at: resolved ? last.answeredAt : child.endedAt,
            childId: child.id,
            questionId: before.id,
            state: resolved ? last.state : ChildQuestionState.cancelled,
            answer: resolved ? last.answer : null,
            answeredBy: resolved ? last.answeredBy : null,
          ),
        );
      }
      if (question != null && question.id != before?.id) {
        changes.add(
          (seq) =>
              ChildQuestionAsked(seq: seq, chat: chatId, question: question),
        );
      }
      if (child.state.isEnded) {
        changes.add(
          (seq) => ChildFinished(
            seq: seq,
            chat: chatId,
            at: child.endedAt,
            childId: child.id,
            state: child.state,
            result: child.result,
          ),
        );
      } else if (child.state != old.state &&
          child.state != WorkState.waitingForAnswer &&
          old.state != WorkState.waitingForAnswer) {
        changes.add(
          (seq) => ChildProgress(
            seq: seq,
            chat: chatId,
            childId: child.id,
            state: child.state,
          ),
        );
      }
    }
    return changes;
  }
}

final class _Extras {
  const _Extras(this.children, this.context, this.compactions);
  final List<ChildAgent> children;
  final ContextView? context;
  final List<CompactionItem> compactions;
}

final class _ReplayResult {
  const _ReplayResult({this.resync = false, this.refresh = false});
  final bool resync;
  final bool refresh;
}

final class _PendingNotification {
  _PendingNotification(this.event);
  final Json? event;
  bool consumed = false;
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
