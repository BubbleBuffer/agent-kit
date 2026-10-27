/// Small view models: status enums, references, diffs, approvals,
/// questions, the queue, the plan, the crew, usage and the workspace.
library;

import 'value.dart';

/// The status of a chat, in the mockups' vocabulary.
///
/// The reducer derives it from the snapshot (see `ChatSnapshot.status`);
/// widgets read it and never compute it.
enum ChatStatus {
  /// An approval or a question is waiting for the user.
  needsYou,

  /// A run is active (or waiting for quota), or a child agent is running.
  running,

  /// The last run failed.
  failed,

  /// The last run completed.
  done,

  /// No run yet, or the last run was cancelled.
  idle,

  /// The last run was interrupted by a host restart; it can be resumed.
  interrupted,
}

/// How a run ended.
enum RunOutcome {
  /// The run finished normally.
  completed,

  /// The run ended with an error.
  failed,

  /// The user (or a host) cancelled the run.
  cancelled,

  /// A host restart interrupted the run.
  interrupted,
}

/// The state of a unit of work: a tool call, a child agent.
enum WorkState {
  /// Still in progress.
  running,

  /// Finished successfully.
  done,

  /// Finished with an error (for a process: a non-zero exit).
  failed,

  /// Cancelled, or abandoned because its run ended.
  cancelled,

  /// A child agent asked its parent a question and waits for the answer.
  /// The question is addressed to an agent, never to the user, so this does
  /// not make the chat "need you".
  waitingForAnswer,

  /// A child agent finished its turn and waits for its next message.
  idle,

  /// A child agent ran out of time.
  timedOut,
}

/// Helpers on [WorkState].
extension WorkStateX on WorkState {
  /// Whether the work has ended for good: done, failed, cancelled or timed
  /// out. A running, waiting or idle child can still change.
  bool get isEnded => switch (this) {
    WorkState.done ||
    WorkState.failed ||
    WorkState.cancelled ||
    WorkState.timedOut => true,
    WorkState.running || WorkState.waitingForAnswer || WorkState.idle => false,
  };
}

/// What a tool call does, for its icon and verb. Unknown kinds read as
/// [other]; the raw tool name is kept beside it.
enum ToolKind {
  /// Reads a file.
  read,

  /// Searches files (grep, glob).
  search,

  /// Runs a command.
  exec,

  /// Edits a file.
  edit,

  /// Writes or creates a file.
  write,

  /// Fetches or searches the web.
  web,

  /// Anything else.
  other,
}

/// The tone of a notice line.
enum NoticeTone {
  /// Neutral information.
  info,

  /// Something worked.
  success,

  /// Something needs care.
  warning,

  /// Something failed.
  danger,
}

/// An opaque reference to host content: a file, a page, a chat, a person.
///
/// The kit never interprets [kind] or [id]; the host renders the chip or
/// the inline mention. When [start] and [end] are set, the reference is a
/// span of the owning text (UTF-16 offsets, end exclusive); otherwise it is
/// attached context shown as a chip.
final class KitRef extends KitValue {
  /// Creates a reference.
  const KitRef({
    required this.kind,
    required this.id,
    required this.label,
    this.start,
    this.end,
  });

  /// Reads a reference from JSON.
  factory KitRef.fromJson(Json j) => KitRef(
    kind: j.str('kind'),
    id: j.str('id'),
    label: j.str('label'),
    start: j.intOpt('start'),
    end: j.intOpt('end'),
  );

  /// The host's kind, such as `file` or `page`.
  final String kind;

  /// The host's id for the target.
  final String id;

  /// Text to show.
  final String label;

  /// Start of the span in the owning text, if it is a span.
  final int? start;

  /// End of the span (exclusive), if it is a span.
  final int? end;

  @override
  Json toJson() => compact({
    'kind': kind,
    'id': id,
    'label': label,
    'start': start,
    'end': end,
  });
}

/// One line of a diff.
enum DiffOp {
  /// An added line.
  add,

  /// A removed line.
  del,

  /// An unchanged context line.
  ctx,
}

/// A line of a diff hunk.
final class DiffLine extends KitValue {
  /// Creates a diff line.
  const DiffLine(this.op, this.text);

  /// Reads a diff line from JSON.
  factory DiffLine.fromJson(Json j) =>
      DiffLine(j.enumOf('op', DiffOp.values, DiffOp.ctx), j.str('text'));

  /// Added, removed or context.
  final DiffOp op;

  /// The line's text, without the sign and the newline.
  final String text;

  @override
  Json toJson() => {'op': op.name, 'text': text};
}

/// A hunk of a diff: lines starting at [oldStart] in the old file and
/// [newStart] in the new one (1-based). Line numbers of each line follow
/// from the starts and the ops.
final class DiffHunk extends KitValue {
  /// Creates a hunk.
  DiffHunk({
    required this.oldStart,
    required this.newStart,
    required List<DiffLine> lines,
  }) : lines = List.unmodifiable(lines);

  /// Reads a hunk from JSON.
  factory DiffHunk.fromJson(Json j) => DiffHunk(
    oldStart: j.integer('oldStart'),
    newStart: j.integer('newStart'),
    lines: j.listOf('lines', DiffLine.fromJson),
  );

  /// First old line (1-based; 0 for a new file).
  final int oldStart;

  /// First new line (1-based; 0 for a deleted file).
  final int newStart;

  /// The lines.
  final List<DiffLine> lines;

  @override
  Json toJson() => {
    'oldStart': oldStart,
    'newStart': newStart,
    'lines': jsonList(lines),
  };
}

/// What a file change does to the file.
enum FileChange {
  /// The file existed and was changed.
  modified,

  /// The file is new.
  created,

  /// The file was removed.
  deleted,
}

/// A diff of one file. The `+8 −3` counts are derived ([added],
/// [removed]), never stored, so they cannot disagree with the lines.
final class FileDiff extends KitValue {
  /// Creates a diff.
  FileDiff({
    required this.path,
    this.change = FileChange.modified,
    List<DiffHunk> hunks = const [],
  }) : hunks = List.unmodifiable(hunks);

  /// Reads a diff from JSON.
  factory FileDiff.fromJson(Json j) => FileDiff(
    path: j.str('path'),
    change: j.enumOf('change', FileChange.values, FileChange.modified),
    hunks: j.listOf('hunks', DiffHunk.fromJson),
  );

  /// The file's path, relative to the workspace when it is inside it.
  final String path;

  /// Modified, created or deleted.
  final FileChange change;

  /// The hunks, in file order.
  final List<DiffHunk> hunks;

  /// Number of added lines.
  int get added => _count(DiffOp.add);

  /// Number of removed lines.
  int get removed => _count(DiffOp.del);

  int _count(DiffOp op) =>
      hunks.fold(0, (n, h) => n + h.lines.where((l) => l.op == op).length);

  @override
  Json toJson() => {
    'path': path,
    'change': change.name,
    'hunks': jsonList(hunks),
  };
}

/// Captured output of a tool call or a background job.
///
/// [text] may be a tail of the whole output; [totalBytes] and
/// [totalLines], when known, describe the whole, and [truncated] says that
/// [text] is not all of it ("Show all 20 lines", "Open full output").
final class ToolOutput extends KitValue {
  /// Creates output.
  const ToolOutput({
    required this.text,
    this.totalBytes,
    this.totalLines,
    this.truncated = false,
  });

  /// Reads output from JSON.
  factory ToolOutput.fromJson(Json j) => ToolOutput(
    text: j.str('text'),
    totalBytes: j.intOpt('totalBytes'),
    totalLines: j.intOpt('totalLines'),
    truncated: j.boolean('truncated'),
  );

  /// The output text (stdout and stderr interleaved, as the backend has it).
  final String text;

  /// Size of the whole output in bytes, if known.
  final int? totalBytes;

  /// Line count of the whole output, if known.
  final int? totalLines;

  /// Whether [text] is only part of the output.
  final bool truncated;

  /// Returns this output with [more] appended at character [offset].
  ///
  /// Idempotent: text already present is skipped, and a chunk past the end
  /// (a lost fragment) is ignored until the complete output arrives.
  ToolOutput appendAt(int offset, String more) {
    final next = appendText(text, offset, more);
    return identical(next, text)
        ? this
        : ToolOutput(
            text: next,
            totalBytes: totalBytes,
            totalLines: totalLines,
            truncated: truncated,
          );
  }

  @override
  Json toJson() => compact({
    'text': text,
    'totalBytes': totalBytes,
    'totalLines': totalLines,
    'truncated': truncated ? true : null,
  });
}

/// Appends [more] to [text] at [offset], idempotently: returns [text]
/// itself when nothing new applies.
String appendText(String text, int offset, String more) {
  if (offset < 0 || offset > text.length) return text;
  final end = offset + more.length;
  if (end <= text.length) return text;
  return text + more.substring(text.length - offset);
}

/// The state of an approval request.
enum ApprovalState {
  /// Waiting for the user. Approvals never expire on a timer.
  pending,

  /// Approved once.
  approved,

  /// Approved for the rest of the session.
  approvedForSession,

  /// Denied, with an optional reason.
  denied,

  /// Resolved by the host without the user, e.g. reason `restart`.
  expired,

  /// Withdrawn because its run ended.
  cancelled,
}

/// A tool call waiting for the user's approval.
///
/// There is no deadline: approvals never expire on a timer. Widgets derive
/// "waiting 12m" from [requestedAt]. After a host restart a pending
/// approval comes back [ApprovalState.expired] with reason `restart`.
final class Approval extends KitValue {
  /// Creates an approval.
  const Approval({
    required this.id,
    required this.tool,
    required this.requestedAt,
    this.kind = ToolKind.other,
    this.target,
    this.summary,
    this.arguments,
    this.diff,
    this.callId,
    this.runId,
    this.state = ApprovalState.pending,
    this.reason,
    this.decidedAt,
  });

  /// Reads an approval from JSON.
  factory Approval.fromJson(Json j) => Approval(
    id: j.str('id'),
    tool: j.str('tool'),
    requestedAt: j.time('requestedAt'),
    kind: j.enumOf('kind', ToolKind.values, ToolKind.other),
    target: j.strOpt('target'),
    summary: j.strOpt('summary'),
    arguments: j.strOpt('arguments'),
    diff: switch (j.objOpt('diff')) {
      final d? => FileDiff.fromJson(d),
      null => null,
    },
    callId: j.strOpt('callId'),
    runId: j.strOpt('runId'),
    state: j.enumOf('state', ApprovalState.values, ApprovalState.pending),
    reason: j.strOpt('reason'),
    decidedAt: j.timeOpt('decidedAt'),
  );

  /// The approval's id, used by `decideApproval`.
  final String id;

  /// The raw tool name, such as `edit`.
  final String tool;

  /// When it was requested.
  final DateTime requestedAt;

  /// What the tool does.
  final ToolKind kind;

  /// The path or command it acts on.
  final String? target;

  /// A one-line description, if the backend has one.
  final String? summary;

  /// The tool arguments as a JSON string, for a details view.
  final String? arguments;

  /// The proposed change, for edit and write tools.
  final FileDiff? diff;

  /// The tool call it gates.
  final String? callId;

  /// The run it belongs to.
  final String? runId;

  /// Pending or how it was resolved.
  final ApprovalState state;

  /// Why it was denied or expired (`restart` after a host restart).
  final String? reason;

  /// When it was resolved.
  final DateTime? decidedAt;

  /// Whether it still waits for the user.
  bool get isPending => state == ApprovalState.pending;

  /// Returns the approval resolved as [state].
  Approval resolve(ApprovalState state, {String? reason, DateTime? at}) =>
      Approval(
        id: id,
        tool: tool,
        requestedAt: requestedAt,
        kind: kind,
        target: target,
        summary: summary,
        arguments: arguments,
        diff: diff,
        callId: callId,
        runId: runId,
        state: state,
        reason: reason,
        decidedAt: at,
      );

  @override
  Json toJson() => compact({
    'id': id,
    'tool': tool,
    'requestedAt': timeJson(requestedAt),
    'kind': kind.name,
    'target': target,
    'summary': summary,
    'arguments': arguments,
    'diff': diff?.toJson(),
    'callId': callId,
    'runId': runId,
    'state': state.name,
    'reason': reason,
    'decidedAt': timeJson(decidedAt),
  });
}

/// The state of a question to the user.
enum QuestionState {
  /// Waiting for an answer.
  pending,

  /// Answered.
  answered,

  /// Resolved by the host without an answer (e.g. after a restart).
  expired,

  /// Withdrawn because its run ended.
  cancelled,
}

/// How a [QuestionItem] is answered.
enum QuestionKind {
  /// Exactly one of the options, or typed "Other" text.
  pickOne,

  /// Any number of the options (including none), plus typed "Other" text.
  pickAny,

  /// A typed answer only.
  text,
}

/// The most questions one [Question] request may hold. Hosts split anything
/// longer into several requests.
const maxQuestionItems = 5;

/// One choice of a [QuestionItem].
final class QuestionOption extends KitValue {
  /// Creates an option.
  const QuestionOption({required this.label, this.description});

  /// Reads an option from JSON.
  factory QuestionOption.fromJson(Json j) => QuestionOption(
    label: j.str('label'),
    description: j.strOpt('description'),
  );

  /// The option's text; also what an answer's `choices` holds.
  final String label;

  /// A muted line under the label, if any.
  final String? description;

  @override
  Json toJson() => compact({'label': label, 'description': description});
}

/// One question of a request.
final class QuestionItem extends KitValue {
  /// Creates an item.
  QuestionItem({
    required this.id,
    required this.header,
    required this.text,
    this.kind = QuestionKind.pickOne,
    List<QuestionOption> options = const [],
    this.allowOther = false,
  }) : options = List.unmodifiable(options);

  /// Reads an item from JSON.
  factory QuestionItem.fromJson(Json j) => QuestionItem(
    id: j.str('id'),
    header: j.str('header'),
    text: j.str('text'),
    kind: j.enumOf('kind', QuestionKind.values, QuestionKind.pickOne),
    options: j.listOf('options', QuestionOption.fromJson),
    allowOther: j.boolean('allowOther'),
  );

  /// The item's id within its request; the key of the answers.
  final String id;

  /// The short tab label.
  final String header;

  /// The question, as markdown.
  final String text;

  /// How it is answered.
  final QuestionKind kind;

  /// The choices; empty for [QuestionKind.text].
  final List<QuestionOption> options;

  /// Whether a typed "Other" row follows the options. Ignored for
  /// [QuestionKind.text].
  final bool allowOther;

  @override
  Json toJson() => compact({
    'id': id,
    'header': header,
    'text': text,
    'kind': kind.name,
    'options': jsonList(options),
    'allowOther': allowOther,
  });
}

/// The answer to one [QuestionItem].
final class QuestionAnswer extends KitValue {
  /// Creates an answer.
  QuestionAnswer({
    List<String> choices = const [],
    this.text,
    this.skipped = false,
  }) : choices = List.unmodifiable(choices);

  /// Reads an answer from JSON.
  factory QuestionAnswer.fromJson(Json j) => QuestionAnswer(
    choices: j.strings('choices'),
    text: j.strOpt('text'),
    skipped: j.boolean('skipped'),
  );

  /// The labels of the chosen options.
  final List<String> choices;

  /// The typed "Other" text, or the answer to a text question. For
  /// [QuestionKind.pickOne], at most one of [choices] and [text] is set.
  final String? text;

  /// Whether the user declined to answer.
  final bool skipped;

  @override
  Json toJson() =>
      compact({'choices': choices, 'text': text, 'skipped': skipped});
}

/// A request from the agent to the user: 1 to [maxQuestionItems] questions,
/// each with its own kind.
final class Question extends KitValue {
  /// Creates a request. Throws [ArgumentError] when [items] is empty or
  /// longer than [maxQuestionItems], or when a pick item has no options and
  /// no "Other" row.
  Question({
    required this.id,
    required this.requestedAt,
    required List<QuestionItem> items,
    this.state = QuestionState.pending,
    Map<String, QuestionAnswer>? answers,
    this.reason,
    this.answeredAt,
  }) : items = List.unmodifiable(items),
       answers = answers == null ? null : Map.unmodifiable(answers) {
    if (items.isEmpty || items.length > maxQuestionItems) {
      throw ArgumentError.value(
        items.length,
        'items',
        'a question holds 1 to $maxQuestionItems items',
      );
    }
    for (final item in items) {
      if (item.kind != QuestionKind.text &&
          item.options.isEmpty &&
          !item.allowOther) {
        throw ArgumentError.value(
          item.id,
          'items',
          'a pick item needs options or allowOther',
        );
      }
    }
  }

  /// Reads a request from JSON.
  factory Question.fromJson(Json j) {
    final answers = j.objOpt('answers');
    return Question(
      id: j.str('id'),
      requestedAt: j.time('requestedAt'),
      items: j.listOf('items', QuestionItem.fromJson),
      state: j.enumOf('state', QuestionState.values, QuestionState.pending),
      answers: answers == null ? null : answersFromJson(answers),
      reason: j.strOpt('reason'),
      answeredAt: j.timeOpt('answeredAt'),
    );
  }

  /// Reads a map of answers keyed by item id.
  static Map<String, QuestionAnswer> answersFromJson(Json j) => {
    for (final key in j.keys) key: QuestionAnswer.fromJson(j.obj(key)),
  };

  /// Writes a map of answers keyed by item id.
  static Json answersToJson(Map<String, QuestionAnswer> answers) => {
    for (final e in answers.entries) e.key: e.value.toJson(),
  };

  /// The request's id, used by `answerQuestion`.
  final String id;

  /// When it was asked.
  final DateTime requestedAt;

  /// The questions, in order.
  final List<QuestionItem> items;

  /// Pending or how it was resolved.
  final QuestionState state;

  /// The answers, keyed by item id, once answered.
  final Map<String, QuestionAnswer>? answers;

  /// Why it expired or was cancelled.
  final String? reason;

  /// When the user answered it; null while pending and when the backend
  /// did not say. Widgets place a resolved question by this time.
  final DateTime? answeredAt;

  /// Whether it still waits for the user.
  bool get isPending => state == QuestionState.pending;

  @override
  Json toJson() => compact({
    'id': id,
    'requestedAt': timeJson(requestedAt),
    'items': jsonList(items),
    'state': state.name,
    'answers': answers == null ? null : answersToJson(answers!),
    'reason': reason,
    'answeredAt': timeJson(answeredAt),
  });
}

/// How a queued message reaches the agent.
enum QueueMode {
  /// Delivered into the running turn at the next step.
  steer,

  /// Delivered as the next turn once the current run ends.
  followup,
}

/// A message waiting in the queue. The composer offers Send now (deliver
/// as a steer), Edit and Remove on it.
final class QueuedInput extends KitValue {
  /// Creates a queued input.
  QueuedInput({
    required this.id,
    required this.text,
    required this.queuedAt,
    this.mode = QueueMode.followup,
    List<KitRef> refs = const [],
  }) : refs = List.unmodifiable(refs);

  /// Reads a queued input from JSON.
  factory QueuedInput.fromJson(Json j) => QueuedInput(
    id: j.str('id'),
    text: j.str('text'),
    queuedAt: j.time('queuedAt'),
    mode: j.enumOf('mode', QueueMode.values, QueueMode.followup),
    refs: j.listOf('refs', KitRef.fromJson),
  );

  /// The input's id, used by the queue commands.
  final String id;

  /// The message text.
  final String text;

  /// When it was queued.
  final DateTime queuedAt;

  /// Steer or follow-up.
  final QueueMode mode;

  /// References in or attached to [text].
  final List<KitRef> refs;

  /// Returns this input with new text.
  QueuedInput withText(String text) => QueuedInput(
    id: id,
    text: text,
    queuedAt: queuedAt,
    mode: mode,
    refs: refs,
  );

  @override
  Json toJson() => {
    'id': id,
    'text': text,
    'queuedAt': timeJson(queuedAt),
    'mode': mode.name,
    if (refs.isNotEmpty) 'refs': jsonList(refs),
  };
}

/// The state of a plan item.
enum PlanItemState {
  /// Not started.
  todo,

  /// In progress now.
  now,

  /// Done.
  done,
}

/// One step of the agent's plan checklist.
final class PlanItem extends KitValue {
  /// Creates a plan item.
  const PlanItem({
    required this.id,
    required this.text,
    this.state = PlanItemState.todo,
  });

  /// Reads a plan item from JSON.
  factory PlanItem.fromJson(Json j) => PlanItem(
    id: j.str('id'),
    text: j.str('text'),
    state: j.enumOf('state', PlanItemState.values, PlanItemState.todo),
  );

  /// The item's id.
  final String id;

  /// The step.
  final String text;

  /// Todo, now or done.
  final PlanItemState state;

  @override
  Json toJson() => {'id': id, 'text': text, 'state': state.name};
}

/// The state of a [ChildQuestion].
enum ChildQuestionState {
  /// Waiting for the parent agent to answer.
  pending,

  /// Answered.
  answered,

  /// Withdrawn because the child ended.
  cancelled,
}

/// Who answered a [ChildQuestion].
enum AnsweredBy {
  /// The parent agent, with an ordinary message.
  parent,

  /// The user, in the parent's place ("Answer yourself").
  user,
}

/// A question a child agent asked its parent.
///
/// It goes to the parent agent, not the user: it never makes the chat
/// "need you", and it is not a [Question]. The child waits as
/// [WorkState.waitingForAnswer] until the parent answers. [options] are the
/// child's suggestions; the parent answers in its own words.
final class ChildQuestion extends KitValue {
  /// Creates a child question.
  ChildQuestion({
    required this.id,
    required this.childId,
    required this.text,
    required this.askedAt,
    List<String> options = const [],
    this.state = ChildQuestionState.pending,
    this.answer,
    this.answeredAt,
    this.answeredBy,
  }) : options = List.unmodifiable(options);

  /// Reads a child question from JSON.
  factory ChildQuestion.fromJson(Json j) => ChildQuestion(
    id: j.str('id'),
    childId: j.str('childId'),
    text: j.str('text'),
    options: j.strings('options'),
    askedAt: j.time('askedAt'),
    state: j.enumOf(
      'state',
      ChildQuestionState.values,
      ChildQuestionState.pending,
    ),
    answer: j.strOpt('answer'),
    answeredAt: j.timeOpt('answeredAt'),
    answeredBy: j.enumOpt('answeredBy', AnsweredBy.values),
  );

  /// The question's id, used by `answerChildQuestion`.
  final String id;

  /// The asking child's chat id.
  final String childId;

  /// The question.
  final String text;

  /// The child's suggested answers; may be empty.
  final List<String> options;

  /// When it was asked. Widgets derive "Asking parent · 40s" from it; it
  /// never expires on a timer.
  final DateTime askedAt;

  /// Pending, answered or cancelled.
  final ChildQuestionState state;

  /// The answer, once answered.
  final String? answer;

  /// When it was answered.
  final DateTime? answeredAt;

  /// Who answered: the parent agent or the user.
  final AnsweredBy? answeredBy;

  /// Whether it still waits for an answer.
  bool get isPending => state == ChildQuestionState.pending;

  /// Returns this question resolved as [state].
  ChildQuestion resolve(
    ChildQuestionState state, {
    String? answer,
    DateTime? at,
    AnsweredBy? by,
  }) => ChildQuestion(
    id: id,
    childId: childId,
    text: text,
    options: options,
    askedAt: askedAt,
    state: state,
    answer: answer,
    answeredAt: at,
    answeredBy: by,
  );

  @override
  Json toJson() => compact({
    'id': id,
    'childId': childId,
    'text': text,
    'options': options.isEmpty ? null : options,
    'askedAt': timeJson(askedAt),
    'state': state.name,
    'answer': answer,
    'answeredAt': timeJson(answeredAt),
    'answeredBy': answeredBy?.name,
  });
}

/// A child agent in the crew.
///
/// [id] is the child's own chat id, so a widget can open it with
/// `loadChat`. A finished child with a [result] also has a return line in
/// the parent's transcript. While the child waits for its parent's answer,
/// [state] is [WorkState.waitingForAnswer] and [pendingQuestion] is set.
final class ChildAgent extends KitValue {
  /// Creates a child agent.
  const ChildAgent({
    required this.id,
    required this.task,
    this.state = WorkState.running,
    this.activity,
    this.toolCalls = 0,
    this.startedAt,
    this.endedAt,
    this.result,
    this.pendingQuestion,
  });

  /// Reads a child agent from JSON.
  factory ChildAgent.fromJson(Json j) => ChildAgent(
    id: j.str('id'),
    task: j.str('task'),
    state: j.enumOf('state', WorkState.values, WorkState.running),
    activity: j.strOpt('activity'),
    toolCalls: j.intOpt('toolCalls') ?? 0,
    startedAt: j.timeOpt('startedAt'),
    endedAt: j.timeOpt('endedAt'),
    result: j.strOpt('result'),
    pendingQuestion: switch (j.objOpt('pendingQuestion')) {
      final q? => ChildQuestion.fromJson(q),
      null => null,
    },
  );

  /// The child's chat id.
  final String id;

  /// What it was asked to do.
  final String task;

  /// Running, waiting for an answer, idle, done, failed, cancelled or timed
  /// out.
  final WorkState state;

  /// What it is doing now, such as `read rate_limits.rs`.
  final String? activity;

  /// Tool calls so far.
  final int toolCalls;

  /// When it started.
  final DateTime? startedAt;

  /// When it ended.
  final DateTime? endedAt;

  /// Its final answer, as markdown.
  final String? result;

  /// The question it is waiting on, so the strip and the ledger can show it
  /// without loading the child.
  final ChildQuestion? pendingQuestion;

  /// Returns a copy with the given fields replaced. [clearQuestion] drops
  /// [pendingQuestion].
  ChildAgent copyWith({
    WorkState? state,
    String? activity,
    int? toolCalls,
    DateTime? endedAt,
    String? result,
    ChildQuestion? pendingQuestion,
    bool clearQuestion = false,
  }) => ChildAgent(
    id: id,
    task: task,
    state: state ?? this.state,
    activity: activity ?? this.activity,
    toolCalls: toolCalls ?? this.toolCalls,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    result: result ?? this.result,
    pendingQuestion: clearQuestion
        ? null
        : pendingQuestion ?? this.pendingQuestion,
  );

  @override
  Json toJson() => compact({
    'id': id,
    'task': task,
    'state': state.name,
    'activity': activity,
    'toolCalls': toolCalls,
    'startedAt': timeJson(startedAt),
    'endedAt': timeJson(endedAt),
    'result': result,
    'pendingQuestion': pendingQuestion?.toJson(),
  });
}

/// The state of a background job.
enum JobState {
  /// Still running.
  running,

  /// The process exited; see `exitCode`.
  exited,

  /// Cancelled before it exited.
  cancelled,
}

/// A background command started by the agent.
final class BackgroundJob extends KitValue {
  /// Creates a job.
  const BackgroundJob({
    required this.id,
    required this.command,
    this.state = JobState.running,
    this.exitCode,
    this.startedAt,
    this.endedAt,
    this.output,
    this.summary,
  });

  /// Reads a job from JSON.
  factory BackgroundJob.fromJson(Json j) => BackgroundJob(
    id: j.str('id'),
    command: j.str('command'),
    state: j.enumOf('state', JobState.values, JobState.running),
    exitCode: j.intOpt('exitCode'),
    startedAt: j.timeOpt('startedAt'),
    endedAt: j.timeOpt('endedAt'),
    output: switch (j.objOpt('output')) {
      final o? => ToolOutput.fromJson(o),
      null => null,
    },
    summary: j.strOpt('summary'),
  );

  /// The job's id, used by `cancelJob`.
  final String id;

  /// The command line.
  final String command;

  /// Running, exited or cancelled.
  final JobState state;

  /// The exit code once exited.
  final int? exitCode;

  /// When it started.
  final DateTime? startedAt;

  /// When it ended.
  final DateTime? endedAt;

  /// Its output (often a tail).
  final ToolOutput? output;

  /// A one-line result, such as `2 failed`.
  final String? summary;

  /// Whether it exited with a non-zero code.
  bool get failed => state == JobState.exited && (exitCode ?? 0) != 0;

  /// Returns a copy with the given fields replaced.
  BackgroundJob copyWith({
    JobState? state,
    int? exitCode,
    DateTime? endedAt,
    ToolOutput? output,
    String? summary,
  }) => BackgroundJob(
    id: id,
    command: command,
    state: state ?? this.state,
    exitCode: exitCode ?? this.exitCode,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    output: output ?? this.output,
    summary: summary ?? this.summary,
  );

  @override
  Json toJson() => compact({
    'id': id,
    'command': command,
    'state': state.name,
    'exitCode': exitCode,
    'startedAt': timeJson(startedAt),
    'endedAt': timeJson(endedAt),
    'output': output?.toJson(),
    'summary': summary,
  });
}

/// Token usage of a chat and the context meter.
final class Usage extends KitValue {
  /// Creates usage.
  const Usage({
    this.contextTokens,
    this.contextLimit,
    this.inputTokens,
    this.outputTokens,
    this.cacheReadTokens,
  });

  /// Reads usage from JSON.
  factory Usage.fromJson(Json j) => Usage(
    contextTokens: j.intOpt('contextTokens'),
    contextLimit: j.intOpt('contextLimit'),
    inputTokens: j.intOpt('inputTokens'),
    outputTokens: j.intOpt('outputTokens'),
    cacheReadTokens: j.intOpt('cacheReadTokens'),
  );

  /// Tokens in the current context window.
  final int? contextTokens;

  /// The model's context window.
  final int? contextLimit;

  /// Input tokens used by the chat so far.
  final int? inputTokens;

  /// Output tokens used by the chat so far.
  final int? outputTokens;

  /// Input tokens served from the provider cache.
  final int? cacheReadTokens;

  /// The context meter's fill, 0 to 1, when both figures are known.
  double? get contextFraction {
    final used = contextTokens, limit = contextLimit;
    if (used == null || limit == null || limit <= 0) return null;
    return (used / limit).clamp(0.0, 1.0);
  }

  @override
  Json toJson() => compact({
    'contextTokens': contextTokens,
    'contextLimit': contextLimit,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
  });
}

/// Where a chat works: the workspace, its branch and worktree.
final class WorkspaceInfo extends KitValue {
  /// Creates workspace info.
  const WorkspaceInfo({
    required this.name,
    this.path,
    this.branch,
    this.worktree,
  });

  /// Reads workspace info from JSON.
  factory WorkspaceInfo.fromJson(Json j) => WorkspaceInfo(
    name: j.str('name'),
    path: j.strOpt('path'),
    branch: j.strOpt('branch'),
    worktree: j.strOpt('worktree'),
  );

  /// Display name of the workspace.
  final String name;

  /// Its root path on the host.
  final String? path;

  /// The checked-out branch.
  final String? branch;

  /// The worktree path, when the chat works in its own worktree.
  final String? worktree;

  @override
  Json toJson() => compact({
    'name': name,
    'path': path,
    'branch': branch,
    'worktree': worktree,
  });
}

/// The current or last run of a chat.
final class RunInfo extends KitValue {
  /// Creates run info.
  const RunInfo({
    required this.id,
    this.model,
    this.startedAt,
    this.endedAt,
    this.outcome,
    this.error,
    this.waitingUntil,
    this.waitReason,
  });

  /// Reads run info from JSON.
  factory RunInfo.fromJson(Json j) => RunInfo(
    id: j.str('id'),
    model: j.strOpt('model'),
    startedAt: j.timeOpt('startedAt'),
    endedAt: j.timeOpt('endedAt'),
    outcome: j.enumOpt('outcome', RunOutcome.values),
    error: j.strOpt('error'),
    waitingUntil: j.timeOpt('waitingUntil'),
    waitReason: j.strOpt('waitReason'),
  );

  /// The run's id.
  final String id;

  /// The model it runs on.
  final String? model;

  /// When it started.
  final DateTime? startedAt;

  /// When it ended.
  final DateTime? endedAt;

  /// How it ended; null while it is active.
  final RunOutcome? outcome;

  /// The error of a failed run, safe to show.
  final String? error;

  /// While waiting for provider quota: when it resumes.
  final DateTime? waitingUntil;

  /// While waiting for provider quota: why.
  final String? waitReason;

  /// Whether the run is still active (including a quota wait).
  bool get isActive => outcome == null;

  /// Whether the run is paused waiting for quota.
  bool get isWaiting =>
      isActive && (waitingUntil != null || waitReason != null);

  @override
  Json toJson() => compact({
    'id': id,
    'model': model,
    'startedAt': timeJson(startedAt),
    'endedAt': timeJson(endedAt),
    'outcome': outcome?.name,
    'error': error,
    'waitingUntil': timeJson(waitingUntil),
    'waitReason': waitReason,
  });
}

/// A model or profile a chat can use.
final class KitChoice extends KitValue {
  /// Creates a choice.
  const KitChoice({required this.id, required this.label, this.detail});

  /// Reads a choice from JSON.
  factory KitChoice.fromJson(Json j) => KitChoice(
    id: j.str('id'),
    label: j.str('label'),
    detail: j.strOpt('detail'),
  );

  /// The id passed to `setModel` or `setProfile`.
  final String id;

  /// Text to show.
  final String label;

  /// A secondary line, such as the provider or the context window.
  final String? detail;

  @override
  Json toJson() => compact({'id': id, 'label': label, 'detail': detail});
}
