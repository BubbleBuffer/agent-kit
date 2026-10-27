/// The chat snapshot, chat summaries and the derived status.
library;

import 'context.dart';
import 'items.dart';
import 'models.dart';
import 'value.dart';

/// Everything a chat screen shows, as of event sequence [seq].
///
/// `AgentBackend.loadChat` returns one; `reduce` folds events into it.
/// [status] is derived from the other fields when the snapshot is built,
/// so it can never disagree with them; its JSON value is ignored on read.
final class ChatSnapshot extends KitValue {
  /// Creates a snapshot.
  ChatSnapshot({
    required this.chatId,
    this.seq = 0,
    this.title = '',
    this.archived = false,
    this.parentId,
    this.model,
    this.profile,
    this.workspace,
    this.run,
    List<TranscriptItem> items = const [],
    List<Approval> approvals = const [],
    List<Question> questions = const [],
    List<QueuedInput> queue = const [],
    List<PlanItem> plan = const [],
    List<ChildAgent> children = const [],
    List<BackgroundJob> jobs = const [],
    this.usage,
    this.context,
    this.stale = false,
  }) : items = List.unmodifiable(items),
       approvals = List.unmodifiable(approvals),
       questions = List.unmodifiable(questions),
       queue = List.unmodifiable(queue),
       plan = List.unmodifiable(plan),
       children = List.unmodifiable(children),
       jobs = List.unmodifiable(jobs);

  /// An empty chat at sequence 0.
  factory ChatSnapshot.empty(String chatId) => ChatSnapshot(chatId: chatId);

  /// Reads a snapshot from JSON.
  factory ChatSnapshot.fromJson(Json j) => ChatSnapshot(
    chatId: j.str('chatId'),
    seq: j.intOpt('seq') ?? 0,
    title: j.strOpt('title') ?? '',
    archived: j.boolean('archived'),
    parentId: j.strOpt('parentId'),
    model: j.strOpt('model'),
    profile: j.strOpt('profile'),
    workspace: switch (j.objOpt('workspace')) {
      final w? => WorkspaceInfo.fromJson(w),
      null => null,
    },
    run: switch (j.objOpt('run')) {
      final r? => RunInfo.fromJson(r),
      null => null,
    },
    items: j.listOf('items', TranscriptItem.fromJson),
    approvals: j.listOf('approvals', Approval.fromJson),
    questions: j.listOf('questions', Question.fromJson),
    queue: j.listOf('queue', QueuedInput.fromJson),
    plan: j.listOf('plan', PlanItem.fromJson),
    children: j.listOf('children', ChildAgent.fromJson),
    jobs: j.listOf('jobs', BackgroundJob.fromJson),
    usage: switch (j.objOpt('usage')) {
      final u? => Usage.fromJson(u),
      null => null,
    },
    context: switch (j.objOpt('context')) {
      final c? => ContextView.fromJson(c),
      null => null,
    },
    stale: j.boolean('stale'),
  );

  /// The chat's id.
  final String chatId;

  /// The last durable event folded in. Events with a lower or equal
  /// sequence are already part of this snapshot.
  final int seq;

  /// The chat's title.
  final String title;

  /// Whether the chat is archived.
  final bool archived;

  /// The parent chat, for a child agent or a fork.
  final String? parentId;

  /// The model the next run uses.
  final String? model;

  /// The profile the next run uses.
  final String? profile;

  /// Workspace, branch and worktree.
  final WorkspaceInfo? workspace;

  /// The current or last run.
  final RunInfo? run;

  /// The transcript, in order.
  final List<TranscriptItem> items;

  /// Approval requests: pending ones and the chat's resolved history.
  final List<Approval> approvals;

  /// Questions: pending ones and the chat's resolved history.
  final List<Question> questions;

  /// Queued messages, in delivery order.
  final List<QueuedInput> queue;

  /// The plan checklist.
  final List<PlanItem> plan;

  /// The crew's child agents.
  final List<ChildAgent> children;

  /// Background jobs.
  final List<BackgroundJob> jobs;

  /// Token usage and the context meter.
  final Usage? usage;

  /// What the agent currently remembers (the context view's serving view);
  /// null for a chat without context data, such as a short chat or a
  /// backend without the `context` capability.
  final ContextView? context;

  /// Set by a `gap` event: events were missed, so the snapshot may be out
  /// of date until it is reloaded. Widgets dim what may be stale.
  final bool stale;

  /// The chat's status, derived (see [deriveStatus]).
  late final ChatStatus status = deriveStatus(this);

  /// Pending approvals, oldest first.
  Iterable<Approval> get pendingApprovals =>
      approvals.where((a) => a.isPending);

  /// Pending questions, oldest first.
  Iterable<Question> get pendingQuestions =>
      questions.where((q) => q.isPending);

  /// Child questions still waiting for an answer, oldest first. They are
  /// addressed to the parent agent, so they are not in [pendingQuestions]
  /// and never make the chat [ChatStatus.needsYou].
  Iterable<ChildQuestion> get pendingChildQuestions => [
    for (final c in children)
      if (c.pendingQuestion case final q? when q.isPending) q,
  ];

  /// Plan items done, for "2 of 5".
  int get planDone => plan.where((p) => p.state == PlanItemState.done).length;

  /// The item with [id], or null.
  TranscriptItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced. To clear [run] or
  /// [usage], build a new snapshot.
  ChatSnapshot copyWith({
    int? seq,
    String? title,
    bool? archived,
    String? model,
    String? profile,
    WorkspaceInfo? workspace,
    RunInfo? run,
    List<TranscriptItem>? items,
    List<Approval>? approvals,
    List<Question>? questions,
    List<QueuedInput>? queue,
    List<PlanItem>? plan,
    List<ChildAgent>? children,
    List<BackgroundJob>? jobs,
    Usage? usage,
    ContextView? context,
    bool? stale,
  }) => ChatSnapshot(
    chatId: chatId,
    seq: seq ?? this.seq,
    title: title ?? this.title,
    archived: archived ?? this.archived,
    parentId: parentId,
    model: model ?? this.model,
    profile: profile ?? this.profile,
    workspace: workspace ?? this.workspace,
    run: run ?? this.run,
    items: items ?? this.items,
    approvals: approvals ?? this.approvals,
    questions: questions ?? this.questions,
    queue: queue ?? this.queue,
    plan: plan ?? this.plan,
    children: children ?? this.children,
    jobs: jobs ?? this.jobs,
    usage: usage ?? this.usage,
    context: context ?? this.context,
    stale: stale ?? this.stale,
  );

  @override
  Json toJson() => compact({
    'chatId': chatId,
    'seq': seq,
    'title': title,
    'status': status.name,
    'archived': archived ? true : null,
    'parentId': parentId,
    'model': model,
    'profile': profile,
    'workspace': workspace?.toJson(),
    'run': run?.toJson(),
    'items': jsonList(items),
    'approvals': jsonList(approvals),
    'questions': jsonList(questions),
    'queue': jsonList(queue),
    'plan': jsonList(plan),
    'children': jsonList(children),
    'jobs': jsonList(jobs),
    'usage': usage?.toJson(),
    'context': context?.toJson(),
    'stale': stale ? true : null,
  });
}

/// Derives a chat's status, in this order:
///
/// 1. [ChatStatus.needsYou] when an approval or a question is pending (a
///    child agent's question to its parent is neither);
/// 2. [ChatStatus.running] when the run is active (a quota wait counts) or
///    a child agent is running;
/// 3. from the last run's outcome: failed → [ChatStatus.failed],
///    interrupted → [ChatStatus.interrupted], completed →
///    [ChatStatus.done];
/// 4. otherwise (no run, or cancelled) [ChatStatus.idle].
///
/// Background jobs do not make a chat running: no agent is working.
ChatStatus deriveStatus(ChatSnapshot s) {
  if (s.approvals.any((a) => a.isPending) ||
      s.questions.any((q) => q.isPending)) {
    return ChatStatus.needsYou;
  }
  final run = s.run;
  if ((run != null && run.isActive) ||
      s.children.any((c) => c.state == WorkState.running)) {
    return ChatStatus.running;
  }
  return switch (run?.outcome) {
    RunOutcome.failed => ChatStatus.failed,
    RunOutcome.interrupted => ChatStatus.interrupted,
    RunOutcome.completed => ChatStatus.done,
    RunOutcome.cancelled || null => ChatStatus.idle,
  };
}

/// A row of the chat list.
final class ChatSummary extends KitValue {
  /// Creates a summary.
  const ChatSummary({
    required this.id,
    required this.title,
    this.status = ChatStatus.idle,
    this.updatedAt,
    this.parentId,
    this.archived = false,
    this.workspace,
    this.runningChildren = 0,
    this.error,
  });

  /// Summarizes a snapshot.
  factory ChatSummary.of(ChatSnapshot s, {DateTime? updatedAt}) => ChatSummary(
    id: s.chatId,
    title: s.title,
    status: s.status,
    updatedAt: updatedAt,
    parentId: s.parentId,
    archived: s.archived,
    workspace: s.workspace?.name,
    runningChildren: s.children
        .where((c) => c.state == WorkState.running)
        .length,
    error: s.run?.error,
  );

  /// Reads a summary from JSON.
  factory ChatSummary.fromJson(Json j) => ChatSummary(
    id: j.str('id'),
    title: j.str('title'),
    status: j.enumOf('status', ChatStatus.values, ChatStatus.idle),
    updatedAt: j.timeOpt('updatedAt'),
    parentId: j.strOpt('parentId'),
    archived: j.boolean('archived'),
    workspace: j.strOpt('workspace'),
    runningChildren: j.intOpt('runningChildren') ?? 0,
    error: j.strOpt('error'),
  );

  /// The chat's id.
  final String id;

  /// The chat's title.
  final String title;

  /// Its status, derived by the backend adapter with [deriveStatus].
  final ChatStatus status;

  /// When it last changed.
  final DateTime? updatedAt;

  /// The parent chat, for a child or a fork.
  final String? parentId;

  /// Whether it is archived.
  final bool archived;

  /// The workspace's display name.
  final String? workspace;

  /// Child agents running ("3 agents").
  final int runningChildren;

  /// The last run's error, for a failed chat.
  final String? error;

  @override
  Json toJson() => compact({
    'id': id,
    'title': title,
    'status': status.name,
    'updatedAt': timeJson(updatedAt),
    'parentId': parentId,
    'archived': archived ? true : null,
    'workspace': workspace,
    'runningChildren': runningChildren == 0 ? null : runningChildren,
    'error': error,
  });
}

/// A page of the chat list.
final class ChatPage extends KitValue {
  /// Creates a page.
  ChatPage({required List<ChatSummary> chats, this.nextCursor})
    : chats = List.unmodifiable(chats);

  /// Reads a page from JSON.
  factory ChatPage.fromJson(Json j) => ChatPage(
    chats: j.listOf('chats', ChatSummary.fromJson),
    nextCursor: j.strOpt('nextCursor'),
  );

  /// The chats, newest first.
  final List<ChatSummary> chats;

  /// Pass to `listChats` for the next page; null on the last page.
  final String? nextCursor;

  @override
  Json toJson() =>
      compact({'chats': jsonList(chats), 'nextCursor': nextCursor});
}
