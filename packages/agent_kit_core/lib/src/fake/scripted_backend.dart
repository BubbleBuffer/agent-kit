/// A scripted, in-memory [AgentBackend] for galleries and tests.
library;

import 'dart:async';

import '../backend.dart';
import '../events.dart';
import '../items.dart';
import '../models.dart';
import '../reducer.dart';
import '../snapshot.dart';
import '../value.dart';
import 'clock.dart';

/// One step of a [ChatScript]: wait [after], then emit [event].
///
/// [event] is event JSON without `seq`, `chat` and `at`; the backend
/// stamps those, and fills `requestedAt` of approvals and questions and
/// `queuedAt` of queued inputs when absent. Two directives are not events:
/// `{"kind": "$disconnect"}` stops delivery to subscribers (events are
/// still recorded), and `{"kind": "$reconnect"}` resumes it with a `gap`.
final class ScriptStep {
  /// Creates a step.
  const ScriptStep(this.after, this.event);

  /// Delay after the previous step.
  final Duration after;

  /// The event JSON or directive.
  final Json event;
}

/// A timed script of events for one chat.
final class ChatScript {
  /// Creates a script.
  ChatScript({
    required this.chatId,
    required this.title,
    List<ScriptStep> steps = const [],
  }) : steps = List.unmodifiable(steps);

  /// The chat's id.
  final String chatId;

  /// The chat's initial title.
  final String title;

  /// The steps, in order.
  final List<ScriptStep> steps;
}

/// A command the fake received, for test assertions.
typedef FakeCommand = ({String name, List<Object?> args});

/// Replies to a message sent to the fake; it may emit events.
typedef FakeResponder = FutureOr<void> Function(
  ScriptedBackend backend,
  String chatId,
  String text,
);

/// An in-memory backend that plays [ChatScript]s on a [KitClock] and
/// answers commands by emitting the events a real backend would.
///
/// Sequence numbers are global to the backend, as in BubblePaw's store.
/// With a [ManualClock], playback is deterministic and stepped by
/// `ManualClock.advance`.
final class ScriptedBackend implements AgentBackend {
  /// Creates the backend with [scripts]' chats (empty until played).
  ScriptedBackend({
    List<ChatScript> scripts = const [],
    KitClock? clock,
    KitCapabilities? capabilities,
    List<KitChoice> models = const [],
    List<KitChoice> profiles = const [],
    this.onSend,
  }) : clock = clock ?? const SystemClock(),
       capabilities = capabilities ?? KitCapabilities.all(),
       _scripts = List.unmodifiable(scripts),
       _models = List.unmodifiable(models),
       _profiles = List.unmodifiable(profiles) {
    for (final s in scripts) {
      _addChat(s.chatId, s.title);
    }
  }

  /// The clock that times scripts and stamps events.
  final KitClock clock;

  @override
  final KitCapabilities capabilities;

  /// Called after `send` started a run, to script a reply.
  final FakeResponder? onSend;

  /// Every command received, in order.
  final List<FakeCommand> commands = [];

  /// When set, the next command fails with this error (then it clears).
  KitError? failNext;

  final List<ChatScript> _scripts;
  final List<KitChoice> _models;
  final List<KitChoice> _profiles;
  final _chats = <String, _FakeChat>{};
  var _seq = 0;
  var _ids = 0;

  /// The last sequence number used.
  int get lastSeq => _seq;

  /// Plays every script, concurrently, on [clock]. Completes when all
  /// scripts are done.
  Future<void> play() =>
      Future.wait([for (final s in _scripts) _play(s)]).then((_) {});

  Future<void> _play(ChatScript script) async {
    for (final step in script.steps) {
      await clock.sleep(step.after);
      switch (step.event['kind']) {
        case r'$disconnect':
          disconnect(script.chatId);
        case r'$reconnect':
          reconnect(script.chatId);
        default:
          emit(script.chatId, step.event);
      }
    }
  }

  /// Stamps [event] (JSON without `seq`, `chat` and `at`), folds it into
  /// the chat's state and delivers it to subscribers. Returns the event.
  KitEvent emit(String chatId, Json event) {
    final chat = _chats[chatId] ?? _addChat(chatId, '');
    final now = clock.now();
    final filled = _fillTimes({...event, 'chat': chatId}, now);
    final probe = KitEvent.fromJson({...filled, 'seq': 0});
    final durable = !probe.transient && probe is! GapEvent;
    final seq = durable ? ++_seq : _seq;
    final stamped = KitEvent.fromJson({...filled, 'seq': seq});
    if (stamped is! GapEvent) chat.state = reduce(chat.state, stamped);
    if (durable) {
      chat.log.add(stamped);
      chat.updatedAt = now;
    }
    if (chat.connected) chat.deliver(stamped);
    return stamped;
  }

  /// Stops delivering the chat's events, as if the connection dropped.
  void disconnect(String chatId) => _chats[chatId]?.connected = false;

  /// Resumes delivery with a `gap`, as a hub does after a reconnect.
  void reconnect(String chatId) {
    final chat = _chats[chatId];
    if (chat == null || chat.connected) return;
    chat.connected = true;
    chat.deliver(GapEvent(seq: chat.delivered, chat: chatId, at: clock.now()));
  }

  /// The backend's own current snapshot of a chat (not stale).
  ChatSnapshot? stateOf(String chatId) => _chats[chatId]?.state;

  Json _fillTimes(Json e, DateTime now) {
    final at = timeJson(now);
    Json fill(String key, String field) {
      final inner = e[key];
      if (inner is! Map<String, Object?> || inner[field] != null) return e;
      return {
        ...e,
        key: {...inner, field: at},
      };
    }

    final filled = switch (e['kind']) {
      'approval.requested' => fill('approval', 'requestedAt'),
      'question.asked' => fill('question', 'requestedAt'),
      'queue.added' => fill('input', 'queuedAt'),
      _ => e,
    };
    return {'at': at, ...filled};
  }

  _FakeChat _addChat(String id, String title) => _chats[id] = _FakeChat(
    ChatSnapshot(chatId: id, title: title),
    clock.now(),
  );

  String _id(String prefix) => '$prefix-${++_ids}';

  _FakeChat _command(
    String name,
    List<Object?> args, {
    String? chatId,
    KitCapability? needs,
  }) {
    commands.add((name: name, args: args));
    final fail = failNext;
    if (fail != null) {
      failNext = null;
      throw fail;
    }
    if (needs != null && !capabilities.has(needs)) throw KitUnsupported(needs);
    if (chatId == null) return _FakeChat(ChatSnapshot(chatId: ''), clock.now());
    final chat = _chats[chatId];
    if (chat == null) throw const KitNotFound('No such chat.');
    return chat;
  }

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) async {
    _command('listChats', [cursor, query]);
    final q = query?.toLowerCase();
    final chats = [
      for (final c in _chats.values)
        if (q == null || c.state.title.toLowerCase().contains(q))
          ChatSummary.of(c.state, updatedAt: c.updatedAt),
    ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    return ChatPage(chats: chats);
  }

  @override
  Future<ChatSnapshot> loadChat(String chatId) async =>
      _command('loadChat', [chatId], chatId: chatId).state;

  @override
  Stream<KitEvent> events(String chatId, {required int after}) {
    final chat = _chats[chatId];
    if (chat == null) return Stream.error(const KitNotFound('No such chat.'));
    late final StreamController<KitEvent> controller;
    controller = StreamController<KitEvent>(
      onListen: () {
        for (final e in chat.log) {
          if (e.seq > after) controller.add(e);
        }
        chat.subscribers.add(controller);
      },
      onCancel: () => chat.subscribers.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    _command('createChat', [title, workspace]);
    final id = _id('chat');
    final chat = _addChat(id, title ?? 'New chat');
    if (workspace != null) {
      emit(id, {
        'kind': 'chat.workspace',
        'workspace': {'name': workspace},
      });
    }
    return ChatSummary.of(chat.state, updatedAt: chat.updatedAt);
  }

  @override
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    final chat = _command('send', [chatId, text, refs], chatId: chatId);
    if (text.trim().isEmpty) throw const KitInvalid('Type a message first.');
    if (chat.state.run?.isActive ?? false) {
      final id = _queue(chatId, text, refs, QueueMode.followup);
      return SendResult(delivery: SendDelivery.queued, inputId: id);
    }
    emit(chatId, {
      'kind': 'message.user',
      'itemId': _id('user'),
      'text': text,
      if (refs.isNotEmpty) 'refs': jsonList(refs),
    });
    final runId = _id('run');
    emit(chatId, {'kind': 'run.started', 'runId': runId});
    await onSend?.call(this, chatId, text);
    return SendResult(delivery: SendDelivery.started, runId: runId);
  }

  String _queue(String chatId, String text, List<KitRef> refs, QueueMode mode) {
    final id = _id('input');
    emit(chatId, {
      'kind': 'queue.added',
      'input': {
        'id': id,
        'text': text,
        'mode': mode.name,
        if (refs.isNotEmpty) 'refs': jsonList(refs),
      },
    });
    return id;
  }

  @override
  Future<String> steer(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    _command(
      'steer',
      [chatId, text, refs],
      chatId: chatId,
      needs: KitCapability.steer,
    );
    return _queue(chatId, text, refs, QueueMode.steer);
  }

  @override
  Future<String> followup(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    _command('followup', [chatId, text, refs], chatId: chatId);
    return _queue(chatId, text, refs, QueueMode.followup);
  }

  QueuedInput _queued(_FakeChat chat, String inputId) {
    for (final q in chat.state.queue) {
      if (q.id == inputId) return q;
    }
    throw const KitNotFound('That message is no longer queued.');
  }

  @override
  Future<void> sendQueuedNow(String chatId, String inputId) async {
    final chat = _command(
      'sendQueuedNow',
      [chatId, inputId],
      chatId: chatId,
      needs: KitCapability.sendQueuedNow,
    );
    final q = _queued(chat, inputId);
    emit(chatId, {
      'kind': 'message.user',
      'itemId': _id('user'),
      'text': q.text,
      'inputId': q.id,
      if (q.refs.isNotEmpty) 'refs': jsonList(q.refs),
    });
  }

  @override
  Future<void> editQueued(String chatId, String inputId, String text) async {
    final chat = _command(
      'editQueued',
      [chatId, inputId, text],
      chatId: chatId,
      needs: KitCapability.queueEdit,
    );
    _queued(chat, inputId);
    emit(chatId, {'kind': 'queue.edited', 'inputId': inputId, 'text': text});
  }

  @override
  Future<void> removeQueued(String chatId, String inputId) async {
    final chat = _command(
      'removeQueued',
      [chatId, inputId],
      chatId: chatId,
      needs: KitCapability.queueEdit,
    );
    _queued(chat, inputId);
    emit(chatId, {'kind': 'queue.removed', 'inputId': inputId});
  }

  @override
  Future<void> cancel(String chatId) async {
    final chat = _command('cancel', [chatId], chatId: chatId);
    final run = chat.state.run;
    if (run == null || !run.isActive) return;
    emit(chatId, {
      'kind': 'run.finished',
      'runId': run.id,
      'outcome': RunOutcome.cancelled.name,
    });
  }

  @override
  Future<void> resume(String chatId) async {
    final chat = _command(
      'resume',
      [chatId],
      chatId: chatId,
      needs: KitCapability.resume,
    );
    if (chat.state.run?.outcome != RunOutcome.interrupted) {
      throw const KitConflict('Nothing to resume.');
    }
    emit(chatId, {'kind': 'run.started', 'runId': _id('run')});
  }

  @override
  Future<void> decideApproval(
    String chatId,
    String approvalId,
    ApprovalDecision decision,
  ) async {
    final chat = _command('decideApproval', [
      chatId,
      approvalId,
      decision,
    ], chatId: chatId);
    final approval = chat.state.approvals
        .where((a) => a.id == approvalId)
        .firstOrNull;
    if (approval == null) throw const KitNotFound('No such approval.');
    if (!approval.isPending) {
      throw const KitConflict('That approval was already decided.');
    }
    emit(chatId, {
      'kind': 'approval.resolved',
      'approvalId': approvalId,
      'state': (switch (decision.choice) {
        ApprovalChoice.approve => ApprovalState.approved,
        ApprovalChoice.approveForSession => ApprovalState.approvedForSession,
        ApprovalChoice.deny => ApprovalState.denied,
      }).name,
      'reason': ?decision.reason,
    });
  }

  @override
  Future<void> answerQuestion(
    String chatId,
    String questionId,
    String answer,
  ) async {
    final chat = _command(
      'answerQuestion',
      [chatId, questionId, answer],
      chatId: chatId,
      needs: KitCapability.questions,
    );
    final q = chat.state.questions.where((q) => q.id == questionId).firstOrNull;
    if (q == null) throw const KitNotFound('No such question.');
    if (!q.isPending) throw const KitConflict('That was already answered.');
    emit(chatId, {
      'kind': 'question.resolved',
      'questionId': questionId,
      'state': QuestionState.answered.name,
      'answer': answer,
    });
  }

  @override
  Future<void> rename(String chatId, String title) async {
    _command(
      'rename',
      [chatId, title],
      chatId: chatId,
      needs: KitCapability.rename,
    );
    if (title.trim().isEmpty) throw const KitInvalid('A title is needed.');
    emit(chatId, {'kind': 'chat.renamed', 'title': title});
  }

  @override
  Future<void> archive(String chatId, {bool archived = true}) async {
    _command(
      'archive',
      [chatId, archived],
      chatId: chatId,
      needs: KitCapability.archive,
    );
    emit(chatId, {'kind': 'chat.archived', 'archived': archived});
  }

  @override
  Future<ChatSummary> fork(String chatId, {String? atItemId}) async {
    final chat = _command(
      'fork',
      [chatId, atItemId],
      chatId: chatId,
      needs: KitCapability.fork,
    );
    final items = chat.state.items;
    var end = items.length;
    if (atItemId != null) {
      end = items.indexWhere((i) => i.id == atItemId) + 1;
      if (end == 0) throw const KitNotFound('No such message.');
    }
    final id = _id('chat');
    final copy = _addChat(id, '${chat.state.title} (fork)');
    copy.state = ChatSnapshot(
      chatId: id,
      title: copy.state.title,
      parentId: chatId,
      model: chat.state.model,
      profile: chat.state.profile,
      workspace: chat.state.workspace,
      items: items.sublist(0, end),
    );
    return ChatSummary.of(copy.state, updatedAt: copy.updatedAt);
  }

  @override
  Future<void> rewind(String chatId, String toItemId) async {
    final chat = _command(
      'rewind',
      [chatId, toItemId],
      chatId: chatId,
      needs: KitCapability.rewind,
    );
    final index = chat.state.items.indexWhere((i) => i.id == toItemId);
    if (index < 0 || chat.state.items[index] is! UserMessage) {
      throw const KitNotFound('No such message.');
    }
    if (chat.state.run?.isActive ?? false) throw const KitBusy();
    chat.state = chat.state.copyWith(
      seq: ++_seq,
      items: chat.state.items.sublist(0, index),
    );
    if (chat.connected) {
      chat.deliver(
        GapEvent(seq: chat.delivered, chat: chatId, at: clock.now()),
      );
    }
  }

  @override
  Future<void> cancelChild(String chatId, String childId) async {
    final chat = _command(
      'cancelChild',
      [chatId, childId],
      chatId: chatId,
      needs: KitCapability.children,
    );
    final child = chat.state.children.where((c) => c.id == childId).firstOrNull;
    if (child == null) throw const KitNotFound('No such agent.');
    if (child.state != WorkState.running) {
      throw const KitConflict('That agent already finished.');
    }
    emit(chatId, {
      'kind': 'child.finished',
      'childId': childId,
      'state': WorkState.cancelled.name,
    });
  }

  @override
  Future<void> cancelJob(String chatId, String jobId) async {
    final chat = _command(
      'cancelJob',
      [chatId, jobId],
      chatId: chatId,
      needs: KitCapability.jobs,
    );
    final job = chat.state.jobs.where((j) => j.id == jobId).firstOrNull;
    if (job == null) throw const KitNotFound('No such job.');
    if (job.state != JobState.running) {
      throw const KitConflict('That job already ended.');
    }
    emit(chatId, {
      'kind': 'job.exited',
      'jobId': jobId,
      'state': JobState.cancelled.name,
    });
  }

  @override
  Future<void> undoEdit(String chatId, String editId) async {
    final chat = _command(
      'undoEdit',
      [chatId, editId],
      chatId: chatId,
      needs: KitCapability.editUndo,
    );
    final edit = chat.state.item(editId);
    if (edit is! FileEdit) throw const KitNotFound('No such edit.');
    if (!edit.undoable || edit.undone) {
      throw const KitConflict('That edit can no longer be undone.');
    }
    emit(chatId, {'kind': 'edit.undone', 'itemId': editId});
  }

  @override
  Future<List<KitChoice>> listModels() async {
    _command('listModels', const [], needs: KitCapability.models);
    return _models;
  }

  @override
  Future<List<KitChoice>> listProfiles() async {
    _command('listProfiles', const [], needs: KitCapability.profiles);
    return _profiles;
  }

  @override
  Future<void> setModel(String chatId, String modelId) async {
    _command(
      'setModel',
      [chatId, modelId],
      chatId: chatId,
      needs: KitCapability.models,
    );
    emit(chatId, {'kind': 'chat.settings', 'model': modelId});
  }

  @override
  Future<void> setProfile(String chatId, String profileId) async {
    _command(
      'setProfile',
      [chatId, profileId],
      chatId: chatId,
      needs: KitCapability.profiles,
    );
    emit(chatId, {'kind': 'chat.settings', 'profile': profileId});
  }
}

final class _FakeChat {
  _FakeChat(this.state, this.updatedAt);

  ChatSnapshot state;
  DateTime updatedAt;
  final log = <KitEvent>[];
  final subscribers = <StreamController<KitEvent>>[];
  bool connected = true;
  int delivered = 0;

  void deliver(KitEvent e) {
    if (!e.transient && e is! GapEvent) delivered = e.seq;
    for (final s in [...subscribers]) {
      s.add(e);
    }
  }
}
