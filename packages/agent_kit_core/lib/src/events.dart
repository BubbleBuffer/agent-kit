/// Kit events: what a backend streams after a snapshot.
library;

import 'models.dart';
import 'value.dart';

/// An event of one chat, as `{seq, chat, kind, at, ...payload}` JSON.
///
/// **Durable** events carry a sequence number that grows by at least one
/// per event within a store; the reducer applies one only when its [seq]
/// is above the snapshot's, so replays and duplicates are no-ops.
///
/// **Transient** events ([transient] is true: streamed text and output
/// fragments) carry the sequence of the last durable event before them and
/// never advance the snapshot's. Each carries the character `offset` at
/// which its text starts, so applying one twice changes nothing.
///
/// Unknown kinds parse as [UnknownEvent] and are ignored by the reducer.
sealed class KitEvent extends KitValue {
  const KitEvent({required this.seq, required this.chat, this.at});

  /// Reads an event from JSON. Unknown kinds give an [UnknownEvent].
  static KitEvent fromJson(Json j) {
    final seq = j.integer('seq');
    final chat = j.str('chat');
    final at = j.timeOpt('at');
    final reader = _readers[j['kind']];
    return reader == null
        ? UnknownEvent(seq: seq, chat: chat, at: at, json: j)
        : reader(j, seq, chat, at);
  }

  /// Every known kind, in documentation order.
  static List<String> get kinds => List.unmodifiable(_readers.keys);

  /// The sequence number (see the class doc).
  final int seq;

  /// The chat it belongs to.
  final String chat;

  /// When it happened on the backend.
  final DateTime? at;

  /// The JSON `kind`.
  String get kind;

  /// Whether this is a transient fragment that does not advance `seq`.
  bool get transient => false;

  /// The kind-specific fields.
  Json payload();

  @override
  Json toJson() => compact({
    'seq': seq,
    'chat': chat,
    'kind': kind,
    'at': timeJson(at),
    ...payload(),
  });
}

typedef _Reader = KitEvent Function(Json j, int seq, String chat, DateTime? at);

final Map<String, _Reader> _readers = {
  'chat.renamed': (j, seq, chat, at) =>
      ChatRenamed(seq: seq, chat: chat, at: at, title: j.str('title')),
  'chat.archived': (j, seq, chat, at) => ChatArchived(
    seq: seq,
    chat: chat,
    at: at,
    archived: j.boolean('archived', fallback: true),
  ),
  'chat.settings': (j, seq, chat, at) => ChatSettingsChanged(
    seq: seq,
    chat: chat,
    at: at,
    model: j.strOpt('model'),
    profile: j.strOpt('profile'),
  ),
  'chat.workspace': (j, seq, chat, at) => WorkspaceChanged(
    seq: seq,
    chat: chat,
    at: at,
    workspace: WorkspaceInfo.fromJson(j.obj('workspace')),
  ),
  'run.started': (j, seq, chat, at) => RunStarted(
    seq: seq,
    chat: chat,
    at: at,
    runId: j.str('runId'),
    model: j.strOpt('model'),
  ),
  'run.waiting': (j, seq, chat, at) => RunWaiting(
    seq: seq,
    chat: chat,
    at: at,
    runId: j.str('runId'),
    until: j.timeOpt('until'),
    reason: j.strOpt('reason'),
  ),
  'run.finished': (j, seq, chat, at) => RunFinished(
    seq: seq,
    chat: chat,
    at: at,
    runId: j.str('runId'),
    outcome: j.enumOf('outcome', RunOutcome.values, RunOutcome.completed),
    error: j.strOpt('error'),
  ),
  'message.user': (j, seq, chat, at) => UserMessageAdded(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    text: j.str('text'),
    refs: j.listOf('refs', KitRef.fromJson),
    inputId: j.strOpt('inputId'),
  ),
  'message.delta': (j, seq, chat, at) => MessageDelta(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    offset: j.integer('offset'),
    text: j.str('text'),
    runId: j.strOpt('runId'),
  ),
  'message.assistant': (j, seq, chat, at) => AssistantMessageCompleted(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    markdown: j.str('markdown'),
    runId: j.strOpt('runId'),
  ),
  'message.system': (j, seq, chat, at) => SystemLineAdded(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    text: j.str('text'),
  ),
  'message.notice': (j, seq, chat, at) => NoticeAdded(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    text: j.str('text'),
    tone: j.enumOf('tone', NoticeTone.values, NoticeTone.info),
  ),
  'thinking.started': (j, seq, chat, at) => ThinkingStarted(
    seq: seq,
    chat: chat,
    at: at,
    rowId: j.str('rowId'),
    runId: j.strOpt('runId'),
  ),
  'thinking.delta': (j, seq, chat, at) => ThinkingDelta(
    seq: seq,
    chat: chat,
    at: at,
    rowId: j.str('rowId'),
    offset: j.integer('offset'),
    text: j.str('text'),
    runId: j.strOpt('runId'),
  ),
  'thinking.finished': (j, seq, chat, at) => ThinkingFinished(
    seq: seq,
    chat: chat,
    at: at,
    rowId: j.str('rowId'),
    durationMs: j.intOpt('durationMs'),
    text: j.strOpt('text'),
    runId: j.strOpt('runId'),
  ),
  'tool.started': (j, seq, chat, at) => ToolStarted(
    seq: seq,
    chat: chat,
    at: at,
    callId: j.str('callId'),
    name: j.str('name'),
    toolKind: j.enumOf('toolKind', ToolKind.values, ToolKind.other),
    target: j.strOpt('target'),
    arguments: j.strOpt('arguments'),
    runId: j.strOpt('runId'),
  ),
  'tool.output': (j, seq, chat, at) => ToolOutputDelta(
    seq: seq,
    chat: chat,
    at: at,
    callId: j.str('callId'),
    offset: j.integer('offset'),
    text: j.str('text'),
  ),
  'tool.finished': (j, seq, chat, at) => ToolFinished(
    seq: seq,
    chat: chat,
    at: at,
    callId: j.str('callId'),
    state: j.enumOf('state', WorkState.values, WorkState.done),
    meta: j.strOpt('meta'),
    output: switch (j.objOpt('output')) {
      final o? => ToolOutput.fromJson(o),
      null => null,
    },
    exitCode: j.intOpt('exitCode'),
  ),
  'edit.applied': (j, seq, chat, at) => EditApplied(
    seq: seq,
    chat: chat,
    at: at,
    itemId: j.str('itemId'),
    diff: FileDiff.fromJson(j.obj('diff')),
    callId: j.strOpt('callId'),
    undoable: j.boolean('undoable', fallback: true),
  ),
  'edit.undone': (j, seq, chat, at) =>
      EditUndone(seq: seq, chat: chat, at: at, itemId: j.str('itemId')),
  'plan.updated': (j, seq, chat, at) => PlanUpdated(
    seq: seq,
    chat: chat,
    at: at,
    items: j.listOf('items', PlanItem.fromJson),
  ),
  'approval.requested': (j, seq, chat, at) => ApprovalRequested(
    seq: seq,
    chat: chat,
    at: at,
    approval: Approval.fromJson(j.obj('approval')),
  ),
  'approval.resolved': (j, seq, chat, at) => ApprovalResolved(
    seq: seq,
    chat: chat,
    at: at,
    approvalId: j.str('approvalId'),
    state: j.enumOf('state', ApprovalState.values, ApprovalState.cancelled),
    reason: j.strOpt('reason'),
  ),
  'question.asked': (j, seq, chat, at) => QuestionAsked(
    seq: seq,
    chat: chat,
    at: at,
    question: Question.fromJson(j.obj('question')),
  ),
  'question.resolved': (j, seq, chat, at) => QuestionResolved(
    seq: seq,
    chat: chat,
    at: at,
    questionId: j.str('questionId'),
    state: j.enumOf('state', QuestionState.values, QuestionState.answered),
    answer: j.strOpt('answer'),
    reason: j.strOpt('reason'),
  ),
  'queue.added': (j, seq, chat, at) => QueueAdded(
    seq: seq,
    chat: chat,
    at: at,
    input: QueuedInput.fromJson(j.obj('input')),
  ),
  'queue.edited': (j, seq, chat, at) => QueueEdited(
    seq: seq,
    chat: chat,
    at: at,
    inputId: j.str('inputId'),
    text: j.str('text'),
  ),
  'queue.removed': (j, seq, chat, at) =>
      QueueRemoved(seq: seq, chat: chat, at: at, inputId: j.str('inputId')),
  'child.spawned': (j, seq, chat, at) => ChildSpawned(
    seq: seq,
    chat: chat,
    at: at,
    childId: j.str('childId'),
    task: j.str('task'),
    callId: j.strOpt('callId'),
    runId: j.strOpt('runId'),
  ),
  'child.progress': (j, seq, chat, at) => ChildProgress(
    seq: seq,
    chat: chat,
    at: at,
    childId: j.str('childId'),
    activity: j.strOpt('activity'),
    toolCalls: j.intOpt('toolCalls'),
  ),
  'child.finished': (j, seq, chat, at) => ChildFinished(
    seq: seq,
    chat: chat,
    at: at,
    childId: j.str('childId'),
    state: j.enumOf('state', WorkState.values, WorkState.done),
    result: j.strOpt('result'),
  ),
  'job.started': (j, seq, chat, at) => JobStarted(
    seq: seq,
    chat: chat,
    at: at,
    jobId: j.str('jobId'),
    command: j.str('command'),
  ),
  'job.output': (j, seq, chat, at) => JobOutput(
    seq: seq,
    chat: chat,
    at: at,
    jobId: j.str('jobId'),
    offset: j.integer('offset'),
    text: j.str('text'),
  ),
  'job.exited': (j, seq, chat, at) => JobExited(
    seq: seq,
    chat: chat,
    at: at,
    jobId: j.str('jobId'),
    state: j.enumOf('state', JobState.values, JobState.exited),
    exitCode: j.intOpt('exitCode'),
    summary: j.strOpt('summary'),
    output: switch (j.objOpt('output')) {
      final o? => ToolOutput.fromJson(o),
      null => null,
    },
  ),
  'usage.updated': (j, seq, chat, at) => UsageUpdated(
    seq: seq,
    chat: chat,
    at: at,
    usage: Usage.fromJson(j.obj('usage')),
  ),
  'gap': (j, seq, chat, at) =>
      GapEvent(seq: seq, chat: chat, at: at, skipped: j.intOpt('skipped')),
};

/// The chat was renamed.
final class ChatRenamed extends KitEvent {
  /// Creates the event.
  const ChatRenamed({
    required super.seq,
    required super.chat,
    required this.title,
    super.at,
  });

  /// The new title.
  final String title;

  @override
  String get kind => 'chat.renamed';

  @override
  Json payload() => {'title': title};
}

/// The chat was archived or restored.
final class ChatArchived extends KitEvent {
  /// Creates the event.
  const ChatArchived({
    required super.seq,
    required super.chat,
    this.archived = true,
    super.at,
  });

  /// Whether it is archived now.
  final bool archived;

  @override
  String get kind => 'chat.archived';

  @override
  Json payload() => {'archived': archived};
}

/// The chat's model or profile changed. A null field is unchanged.
final class ChatSettingsChanged extends KitEvent {
  /// Creates the event.
  const ChatSettingsChanged({
    required super.seq,
    required super.chat,
    this.model,
    this.profile,
    super.at,
  });

  /// The new model, if it changed.
  final String? model;

  /// The new profile, if it changed.
  final String? profile;

  @override
  String get kind => 'chat.settings';

  @override
  Json payload() => {'model': model, 'profile': profile};
}

/// The chat's workspace, branch or worktree changed.
final class WorkspaceChanged extends KitEvent {
  /// Creates the event.
  const WorkspaceChanged({
    required super.seq,
    required super.chat,
    required this.workspace,
    super.at,
  });

  /// The whole new workspace info.
  final WorkspaceInfo workspace;

  @override
  String get kind => 'chat.workspace';

  @override
  Json payload() => {'workspace': workspace.toJson()};
}

/// A run started (a new turn, or a resume).
final class RunStarted extends KitEvent {
  /// Creates the event.
  const RunStarted({
    required super.seq,
    required super.chat,
    required this.runId,
    this.model,
    super.at,
  });

  /// The run's id.
  final String runId;

  /// Its model.
  final String? model;

  @override
  String get kind => 'run.started';

  @override
  Json payload() => {'runId': runId, 'model': model};
}

/// The run is paused waiting for provider quota.
final class RunWaiting extends KitEvent {
  /// Creates the event.
  const RunWaiting({
    required super.seq,
    required super.chat,
    required this.runId,
    this.until,
    this.reason,
    super.at,
  });

  /// The run's id.
  final String runId;

  /// When it resumes.
  final DateTime? until;

  /// Why it waits.
  final String? reason;

  @override
  String get kind => 'run.waiting';

  @override
  Json payload() => {
    'runId': runId,
    'until': timeJson(until),
    'reason': reason,
  };
}

/// The run ended.
///
/// Streaming items still open are closed, and tool rows of the run still
/// running are marked cancelled unless the run completed.
final class RunFinished extends KitEvent {
  /// Creates the event.
  const RunFinished({
    required super.seq,
    required super.chat,
    required this.runId,
    this.outcome = RunOutcome.completed,
    this.error,
    super.at,
  });

  /// The run's id.
  final String runId;

  /// How it ended.
  final RunOutcome outcome;

  /// The error of a failed run, safe to show.
  final String? error;

  @override
  String get kind => 'run.finished';

  @override
  Json payload() => {'runId': runId, 'outcome': outcome.name, 'error': error};
}

/// The user's message was accepted. With [inputId] it was delivered from
/// the queue, and leaves it.
final class UserMessageAdded extends KitEvent {
  /// Creates the event.
  UserMessageAdded({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.text,
    List<KitRef> refs = const [],
    this.inputId,
    super.at,
  }) : refs = List.unmodifiable(refs);

  /// The new item's id.
  final String itemId;

  /// The text.
  final String text;

  /// Mentions and attached context.
  final List<KitRef> refs;

  /// The queued input it came from.
  final String? inputId;

  @override
  String get kind => 'message.user';

  @override
  Json payload() => {
    'itemId': itemId,
    'text': text,
    if (refs.isNotEmpty) 'refs': jsonList(refs),
    'inputId': inputId,
  };
}

/// A fragment of a streaming assistant message (transient).
final class MessageDelta extends KitEvent {
  /// Creates the event.
  const MessageDelta({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.offset,
    required this.text,
    this.runId,
    super.at,
  });

  /// The streaming item's id; the completed message uses the same id.
  final String itemId;

  /// Where [text] starts in the message, in UTF-16 units.
  final int offset;

  /// The fragment.
  final String text;

  /// The run.
  final String? runId;

  @override
  bool get transient => true;

  @override
  String get kind => 'message.delta';

  @override
  Json payload() => {
    'itemId': itemId,
    'offset': offset,
    'text': text,
    'runId': runId,
  };
}

/// An assistant message is complete; it replaces the streaming item with
/// the same id.
final class AssistantMessageCompleted extends KitEvent {
  /// Creates the event.
  const AssistantMessageCompleted({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.markdown,
    this.runId,
    super.at,
  });

  /// The item's id.
  final String itemId;

  /// The whole message.
  final String markdown;

  /// The run.
  final String? runId;

  @override
  String get kind => 'message.assistant';

  @override
  Json payload() => {'itemId': itemId, 'markdown': markdown, 'runId': runId};
}

/// A system line was added.
final class SystemLineAdded extends KitEvent {
  /// Creates the event.
  const SystemLineAdded({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.text,
    super.at,
  });

  /// The item's id.
  final String itemId;

  /// The line.
  final String text;

  @override
  String get kind => 'message.system';

  @override
  Json payload() => {'itemId': itemId, 'text': text};
}

/// A notice was added.
final class NoticeAdded extends KitEvent {
  /// Creates the event.
  const NoticeAdded({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.text,
    this.tone = NoticeTone.info,
    super.at,
  });

  /// The item's id.
  final String itemId;

  /// The notice.
  final String text;

  /// Its tone.
  final NoticeTone tone;

  @override
  String get kind => 'message.notice';

  @override
  Json payload() => {'itemId': itemId, 'text': text, 'tone': tone.name};
}

/// The agent started thinking.
final class ThinkingStarted extends KitEvent {
  /// Creates the event.
  const ThinkingStarted({
    required super.seq,
    required super.chat,
    required this.rowId,
    this.runId,
    super.at,
  });

  /// The row's id.
  final String rowId;

  /// The run.
  final String? runId;

  @override
  String get kind => 'thinking.started';

  @override
  Json payload() => {'rowId': rowId, 'runId': runId};
}

/// A fragment of reasoning text (transient).
final class ThinkingDelta extends KitEvent {
  /// Creates the event.
  const ThinkingDelta({
    required super.seq,
    required super.chat,
    required this.rowId,
    required this.offset,
    required this.text,
    this.runId,
    super.at,
  });

  /// The row's id.
  final String rowId;

  /// Where [text] starts, in UTF-16 units.
  final int offset;

  /// The fragment.
  final String text;

  /// The run.
  final String? runId;

  @override
  bool get transient => true;

  @override
  String get kind => 'thinking.delta';

  @override
  Json payload() => {
    'rowId': rowId,
    'offset': offset,
    'text': text,
    'runId': runId,
  };
}

/// The agent stopped thinking. [text], when set, replaces the streamed
/// reasoning text.
final class ThinkingFinished extends KitEvent {
  /// Creates the event.
  const ThinkingFinished({
    required super.seq,
    required super.chat,
    required this.rowId,
    this.durationMs,
    this.text,
    this.runId,
    super.at,
  });

  /// The row's id.
  final String rowId;

  /// How long it thought.
  final int? durationMs;

  /// The whole reasoning text, if exposed.
  final String? text;

  /// The run.
  final String? runId;

  @override
  String get kind => 'thinking.finished';

  @override
  Json payload() => {
    'rowId': rowId,
    'durationMs': durationMs,
    'text': text,
    'runId': runId,
  };
}

/// A tool call started.
final class ToolStarted extends KitEvent {
  /// Creates the event.
  const ToolStarted({
    required super.seq,
    required super.chat,
    required this.callId,
    required this.name,
    this.toolKind = ToolKind.other,
    this.target,
    this.arguments,
    this.runId,
    super.at,
  });

  /// The call's id; the row's id.
  final String callId;

  /// The raw tool name.
  final String name;

  /// What the tool does.
  final ToolKind toolKind;

  /// Path, pattern or command.
  final String? target;

  /// Arguments as a JSON string.
  final String? arguments;

  /// The run.
  final String? runId;

  @override
  String get kind => 'tool.started';

  @override
  Json payload() => {
    'callId': callId,
    'name': name,
    'toolKind': toolKind.name,
    'target': target,
    'arguments': arguments,
    'runId': runId,
  };
}

/// A fragment of a tool call's output (transient).
final class ToolOutputDelta extends KitEvent {
  /// Creates the event.
  const ToolOutputDelta({
    required super.seq,
    required super.chat,
    required this.callId,
    required this.offset,
    required this.text,
    super.at,
  });

  /// The call's id.
  final String callId;

  /// Where [text] starts, in UTF-16 units.
  final int offset;

  /// The fragment.
  final String text;

  @override
  bool get transient => true;

  @override
  String get kind => 'tool.output';

  @override
  Json payload() => {'callId': callId, 'offset': offset, 'text': text};
}

/// A tool call finished. [output], when set, replaces streamed output.
final class ToolFinished extends KitEvent {
  /// Creates the event.
  const ToolFinished({
    required super.seq,
    required super.chat,
    required this.callId,
    this.state = WorkState.done,
    this.meta,
    this.output,
    this.exitCode,
    super.at,
  });

  /// The call's id.
  final String callId;

  /// Done, failed or cancelled.
  final WorkState state;

  /// A short result, such as `9 hits`.
  final String? meta;

  /// The final output.
  final ToolOutput? output;

  /// The exit code, for exec tools.
  final int? exitCode;

  @override
  String get kind => 'tool.finished';

  @override
  Json payload() => {
    'callId': callId,
    'state': state.name,
    'meta': meta,
    'output': output?.toJson(),
    'exitCode': exitCode,
  };
}

/// A file edit was applied.
final class EditApplied extends KitEvent {
  /// Creates the event.
  const EditApplied({
    required super.seq,
    required super.chat,
    required this.itemId,
    required this.diff,
    this.callId,
    this.undoable = true,
    super.at,
  });

  /// The edit item's id, used by `undoEdit`.
  final String itemId;

  /// The change.
  final FileDiff diff;

  /// The tool call that made it.
  final String? callId;

  /// Whether it can be undone.
  final bool undoable;

  @override
  String get kind => 'edit.applied';

  @override
  Json payload() => {
    'itemId': itemId,
    'diff': diff.toJson(),
    'callId': callId,
    'undoable': undoable,
  };
}

/// A file edit was undone.
final class EditUndone extends KitEvent {
  /// Creates the event.
  const EditUndone({
    required super.seq,
    required super.chat,
    required this.itemId,
    super.at,
  });

  /// The edit item's id.
  final String itemId;

  @override
  String get kind => 'edit.undone';

  @override
  Json payload() => {'itemId': itemId};
}

/// The plan changed; [items] is the whole new plan.
final class PlanUpdated extends KitEvent {
  /// Creates the event.
  PlanUpdated({
    required super.seq,
    required super.chat,
    required List<PlanItem> items,
    super.at,
  }) : items = List.unmodifiable(items);

  /// The whole plan.
  final List<PlanItem> items;

  @override
  String get kind => 'plan.updated';

  @override
  Json payload() => {'items': jsonList(items)};
}

/// An approval was requested.
final class ApprovalRequested extends KitEvent {
  /// Creates the event.
  const ApprovalRequested({
    required super.seq,
    required super.chat,
    required this.approval,
    super.at,
  });

  /// The request.
  final Approval approval;

  @override
  String get kind => 'approval.requested';

  @override
  Json payload() => {'approval': approval.toJson()};
}

/// An approval was resolved by the user, or by the host (expired with
/// reason `restart`, or cancelled with its run).
final class ApprovalResolved extends KitEvent {
  /// Creates the event.
  const ApprovalResolved({
    required super.seq,
    required super.chat,
    required this.approvalId,
    required this.state,
    this.reason,
    super.at,
  });

  /// The approval's id.
  final String approvalId;

  /// How it was resolved.
  final ApprovalState state;

  /// Deny reason, or why it expired.
  final String? reason;

  @override
  String get kind => 'approval.resolved';

  @override
  Json payload() => {
    'approvalId': approvalId,
    'state': state.name,
    'reason': reason,
  };
}

/// The agent asked the user a question.
final class QuestionAsked extends KitEvent {
  /// Creates the event.
  const QuestionAsked({
    required super.seq,
    required super.chat,
    required this.question,
    super.at,
  });

  /// The question.
  final Question question;

  @override
  String get kind => 'question.asked';

  @override
  Json payload() => {'question': question.toJson()};
}

/// A question was answered, expired or cancelled.
final class QuestionResolved extends KitEvent {
  /// Creates the event.
  const QuestionResolved({
    required super.seq,
    required super.chat,
    required this.questionId,
    this.state = QuestionState.answered,
    this.answer,
    this.reason,
    super.at,
  });

  /// The question's id.
  final String questionId;

  /// How it was resolved.
  final QuestionState state;

  /// The answer.
  final String? answer;

  /// Why it expired or was cancelled.
  final String? reason;

  @override
  String get kind => 'question.resolved';

  @override
  Json payload() => {
    'questionId': questionId,
    'state': state.name,
    'answer': answer,
    'reason': reason,
  };
}

/// A message was queued (steer or follow-up).
final class QueueAdded extends KitEvent {
  /// Creates the event.
  const QueueAdded({
    required super.seq,
    required super.chat,
    required this.input,
    super.at,
  });

  /// The queued input.
  final QueuedInput input;

  @override
  String get kind => 'queue.added';

  @override
  Json payload() => {'input': input.toJson()};
}

/// A queued message was edited.
final class QueueEdited extends KitEvent {
  /// Creates the event.
  const QueueEdited({
    required super.seq,
    required super.chat,
    required this.inputId,
    required this.text,
    super.at,
  });

  /// The input's id.
  final String inputId;

  /// The new text.
  final String text;

  @override
  String get kind => 'queue.edited';

  @override
  Json payload() => {'inputId': inputId, 'text': text};
}

/// A queued message was removed without delivery. Delivery is a
/// `message.user` with the input's id instead.
final class QueueRemoved extends KitEvent {
  /// Creates the event.
  const QueueRemoved({
    required super.seq,
    required super.chat,
    required this.inputId,
    super.at,
  });

  /// The input's id.
  final String inputId;

  @override
  String get kind => 'queue.removed';

  @override
  Json payload() => {'inputId': inputId};
}

/// A child agent was spawned: adds a spawn row and a crew entry.
final class ChildSpawned extends KitEvent {
  /// Creates the event.
  const ChildSpawned({
    required super.seq,
    required super.chat,
    required this.childId,
    required this.task,
    this.callId,
    this.runId,
    super.at,
  });

  /// The child's chat id.
  final String childId;

  /// Its task.
  final String task;

  /// The spawning tool call; the spawn row's id (defaults to the child id).
  final String? callId;

  /// The run.
  final String? runId;

  @override
  String get kind => 'child.spawned';

  @override
  Json payload() => {
    'childId': childId,
    'task': task,
    'callId': callId,
    'runId': runId,
  };
}

/// A child agent made progress. A null field is unchanged.
final class ChildProgress extends KitEvent {
  /// Creates the event.
  const ChildProgress({
    required super.seq,
    required super.chat,
    required this.childId,
    this.activity,
    this.toolCalls,
    super.at,
  });

  /// The child's chat id.
  final String childId;

  /// What it is doing now.
  final String? activity;

  /// Tool calls so far.
  final int? toolCalls;

  @override
  String get kind => 'child.progress';

  @override
  Json payload() => {
    'childId': childId,
    'activity': activity,
    'toolCalls': toolCalls,
  };
}

/// A child agent ended. With a [result], or when it failed, a return
/// line is added to the transcript.
final class ChildFinished extends KitEvent {
  /// Creates the event.
  const ChildFinished({
    required super.seq,
    required super.chat,
    required this.childId,
    this.state = WorkState.done,
    this.result,
    super.at,
  });

  /// The child's chat id.
  final String childId;

  /// Done, failed or cancelled.
  final WorkState state;

  /// Its answer, as markdown.
  final String? result;

  @override
  String get kind => 'child.finished';

  @override
  Json payload() => {'childId': childId, 'state': state.name, 'result': result};
}

/// A background job started.
final class JobStarted extends KitEvent {
  /// Creates the event.
  const JobStarted({
    required super.seq,
    required super.chat,
    required this.jobId,
    required this.command,
    super.at,
  });

  /// The job's id.
  final String jobId;

  /// The command line.
  final String command;

  @override
  String get kind => 'job.started';

  @override
  Json payload() => {'jobId': jobId, 'command': command};
}

/// A fragment of a job's output (transient).
final class JobOutput extends KitEvent {
  /// Creates the event.
  const JobOutput({
    required super.seq,
    required super.chat,
    required this.jobId,
    required this.offset,
    required this.text,
    super.at,
  });

  /// The job's id.
  final String jobId;

  /// Where [text] starts, in UTF-16 units.
  final int offset;

  /// The fragment.
  final String text;

  @override
  bool get transient => true;

  @override
  String get kind => 'job.output';

  @override
  Json payload() => {'jobId': jobId, 'offset': offset, 'text': text};
}

/// A background job exited or was cancelled. [output], when set,
/// replaces streamed output.
final class JobExited extends KitEvent {
  /// Creates the event.
  const JobExited({
    required super.seq,
    required super.chat,
    required this.jobId,
    this.state = JobState.exited,
    this.exitCode,
    this.summary,
    this.output,
    super.at,
  });

  /// The job's id.
  final String jobId;

  /// Exited or cancelled.
  final JobState state;

  /// The exit code.
  final int? exitCode;

  /// A one-line result.
  final String? summary;

  /// The final output.
  final ToolOutput? output;

  @override
  String get kind => 'job.exited';

  @override
  Json payload() => {
    'jobId': jobId,
    'state': state.name,
    'exitCode': exitCode,
    'summary': summary,
    'output': output?.toJson(),
  };
}

/// Token usage changed; [usage] is the whole new figure.
final class UsageUpdated extends KitEvent {
  /// Creates the event.
  const UsageUpdated({
    required super.seq,
    required super.chat,
    required this.usage,
    super.at,
  });

  /// The usage.
  final Usage usage;

  @override
  String get kind => 'usage.updated';

  @override
  Json payload() => {'usage': usage.toJson()};
}

/// Events were missed (a reconnect, a lagging subscriber, or a change such
/// as a rewind that the backend does not express as events).
///
/// The reducer marks the snapshot stale; the consumer reloads it with
/// `loadChat` and continues from the new snapshot's sequence. [seq] is the
/// last sequence delivered before the gap; [skipped], if known, how many
/// events were lost.
final class GapEvent extends KitEvent {
  /// Creates the event.
  const GapEvent({
    required super.seq,
    required super.chat,
    this.skipped,
    super.at,
  });

  /// Number of events lost, if known.
  final int? skipped;

  @override
  String get kind => 'gap';

  @override
  Json payload() => {'skipped': skipped};
}

/// An event of a kind this kit does not know. The reducer ignores it.
final class UnknownEvent extends KitEvent {
  /// Creates the event.
  UnknownEvent({
    required super.seq,
    required super.chat,
    required Json json,
    super.at,
  }) : json = Map.unmodifiable(json);

  /// The event's raw JSON.
  final Json json;

  @override
  String get kind => json['kind'] is String ? json['kind'] as String : '';

  @override
  Json payload() => {
    for (final e in json.entries)
      if (!const {'seq', 'chat', 'kind', 'at'}.contains(e.key)) e.key: e.value,
  };
}
