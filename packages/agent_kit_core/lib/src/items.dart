/// Transcript items and the rows of an activity group.
library;

import 'models.dart';
import 'value.dart';

/// One entry of a chat's transcript, in display order.
///
/// Every item has a stable [id] from the backend; events address items by
/// it. Unknown item types in JSON are skipped.
sealed class TranscriptItem extends KitValue {
  const TranscriptItem({required this.id, this.at});

  /// Reads an item from JSON; null for an unknown `type`.
  static TranscriptItem? fromJson(Json j) => switch (j['type']) {
    'user' => UserMessage.fromJson(j),
    'assistant' => AssistantMessage.fromJson(j),
    'system' => SystemLine.fromJson(j),
    'notice' => NoticeLine.fromJson(j),
    'activity' => ActivityGroup.fromJson(j),
    'edit' => FileEdit.fromJson(j),
    'childResult' => ChildResult.fromJson(j),
    'compaction' => CompactionItem.fromJson(j),
    'childQuestion' => ChildQuestionItem.fromJson(j),
    'interrupted' => InterruptedItem.fromJson(j),
    _ => null,
  };

  /// The item's id.
  final String id;

  /// When it was created.
  final DateTime? at;

  /// The JSON `type` tag.
  String get type;

  Json _base(Json fields) =>
      compact({'type': type, 'id': id, 'at': timeJson(at), ...fields});
}

/// A message the user sent.
final class UserMessage extends TranscriptItem {
  /// Creates a user message.
  UserMessage({
    required super.id,
    required this.text,
    super.at,
    List<KitRef> refs = const [],
    this.inputId,
  }) : refs = List.unmodifiable(refs);

  /// Reads a user message from JSON.
  factory UserMessage.fromJson(Json j) => UserMessage(
    id: j.str('id'),
    at: j.timeOpt('at'),
    text: j.str('text'),
    refs: j.listOf('refs', KitRef.fromJson),
    inputId: j.strOpt('inputId'),
  );

  /// The message text (plain, with [refs] as spans or chips).
  final String text;

  /// Mentions and attached context.
  final List<KitRef> refs;

  /// The queued input it was delivered from, if it went through the queue.
  final String? inputId;

  @override
  String get type => 'user';

  @override
  Json toJson() => _base({
    'text': text,
    if (refs.isNotEmpty) 'refs': jsonList(refs),
    'inputId': inputId,
  });
}

/// An assistant message, as markdown (code blocks are fenced markdown).
///
/// While [streaming], [markdown] grows with each delta; the completed
/// message replaces it.
final class AssistantMessage extends TranscriptItem {
  /// Creates an assistant message.
  const AssistantMessage({
    required super.id,
    required this.markdown,
    super.at,
    this.streaming = false,
    this.runId,
  });

  /// Reads an assistant message from JSON.
  factory AssistantMessage.fromJson(Json j) => AssistantMessage(
    id: j.str('id'),
    at: j.timeOpt('at'),
    markdown: j.str('markdown'),
    streaming: j.boolean('streaming'),
    runId: j.strOpt('runId'),
  );

  /// The message as markdown.
  final String markdown;

  /// Whether more text is still arriving.
  final bool streaming;

  /// The run that wrote it.
  final String? runId;

  @override
  String get type => 'assistant';

  @override
  Json toJson() => _base({
    'markdown': markdown,
    'streaming': streaming ? true : null,
    'runId': runId,
  });
}

/// A system line from the engine, such as "Context compacted" or
/// "Stopped".
final class SystemLine extends TranscriptItem {
  /// Creates a system line.
  const SystemLine({required super.id, required this.text, super.at});

  /// Reads a system line from JSON.
  factory SystemLine.fromJson(Json j) =>
      SystemLine(id: j.str('id'), at: j.timeOpt('at'), text: j.str('text'));

  /// The line.
  final String text;

  @override
  String get type => 'system';

  @override
  Json toJson() => _base({'text': text});
}

/// A notice from the host to the user, with a [tone].
final class NoticeLine extends TranscriptItem {
  /// Creates a notice.
  const NoticeLine({
    required super.id,
    required this.text,
    super.at,
    this.tone = NoticeTone.info,
  });

  /// Reads a notice from JSON.
  factory NoticeLine.fromJson(Json j) => NoticeLine(
    id: j.str('id'),
    at: j.timeOpt('at'),
    text: j.str('text'),
    tone: j.enumOf('tone', NoticeTone.values, NoticeTone.info),
  );

  /// The notice, as markdown.
  final String text;

  /// Info, success, warning or danger.
  final NoticeTone tone;

  @override
  String get type => 'notice';

  @override
  Json toJson() => _base({'text': text, 'tone': tone.name});
}

/// A run of agent work between messages: thinking, tool calls and spawns.
///
/// The summary line ("Worked 48s · thought 6s · 7 tool calls") is derived
/// from the rows: [toolCalls], [thinkingMs], [startedAt] and [endedAt].
final class ActivityGroup extends TranscriptItem {
  /// Creates a group.
  ActivityGroup({
    required super.id,
    super.at,
    this.runId,
    List<ActivityRow> rows = const [],
  }) : rows = List.unmodifiable(rows);

  /// Reads a group from JSON.
  factory ActivityGroup.fromJson(Json j) => ActivityGroup(
    id: j.str('id'),
    at: j.timeOpt('at'),
    runId: j.strOpt('runId'),
    rows: j.listOf('rows', ActivityRow.fromJson),
  );

  /// The run it belongs to.
  final String? runId;

  /// The rows, in order.
  final List<ActivityRow> rows;

  /// Number of tool calls (spawns count as calls).
  int get toolCalls => rows.whereType<ToolRow>().length + spawns;

  /// Number of child agents spawned.
  int get spawns => rows.whereType<SpawnRow>().length;

  /// Total thinking time in milliseconds.
  int get thinkingMs =>
      rows.whereType<ThinkingRow>().fold(0, (n, r) => n + (r.durationMs ?? 0));

  /// Whether any row is still running.
  bool get isRunning => rows.any((r) => r.isRunning);

  /// Returns the group with [rows] replaced.
  ActivityGroup withRows(List<ActivityRow> rows) =>
      ActivityGroup(id: id, at: at, runId: runId, rows: rows);

  @override
  String get type => 'activity';

  @override
  Json toJson() => _base({'runId': runId, 'rows': jsonList(rows)});
}

/// A file edit the agent made, with its diff and undo state.
final class FileEdit extends TranscriptItem {
  /// Creates an edit.
  const FileEdit({
    required super.id,
    required this.diff,
    super.at,
    this.callId,
    this.undoable = true,
    this.undone = false,
  });

  /// Reads an edit from JSON.
  factory FileEdit.fromJson(Json j) => FileEdit(
    id: j.str('id'),
    at: j.timeOpt('at'),
    diff: FileDiff.fromJson(j.obj('diff')),
    callId: j.strOpt('callId'),
    undoable: j.boolean('undoable', fallback: true),
    undone: j.boolean('undone'),
  );

  /// The change.
  final FileDiff diff;

  /// The tool call that made it.
  final String? callId;

  /// Whether `undoEdit` can revert it now.
  final bool undoable;

  /// Whether it was undone.
  final bool undone;

  @override
  String get type => 'edit';

  @override
  Json toJson() => _base({
    'diff': diff.toJson(),
    'callId': callId,
    'undoable': undoable,
    'undone': undone ? true : null,
  });
}

/// The return line of a child agent: "Map UsageState transitions returned"
/// with its result.
final class ChildResult extends TranscriptItem {
  /// Creates a return line.
  const ChildResult({
    required super.id,
    required this.childId,
    required this.task,
    super.at,
    this.state = WorkState.done,
    this.result,
  });

  /// Reads a return line from JSON.
  factory ChildResult.fromJson(Json j) => ChildResult(
    id: j.str('id'),
    at: j.timeOpt('at'),
    childId: j.str('childId'),
    task: j.str('task'),
    state: j.enumOf('state', WorkState.values, WorkState.done),
    result: j.strOpt('result'),
  );

  /// The child's chat id.
  final String childId;

  /// The child's task.
  final String task;

  /// How it ended.
  final WorkState state;

  /// Its answer, as markdown.
  final String? result;

  @override
  String get type => 'childResult';

  @override
  Json toJson() => _base({
    'childId': childId,
    'task': task,
    'state': state.name,
    'result': result,
  });
}

/// How far a compaction got.
enum CompactionState {
  /// Summaries are being written or applied.
  running,

  /// Applied: the serving view changed.
  done,

  /// It failed; the previous context is unchanged.
  failed,
}

/// The marker of a context compaction, placed in the transcript at the
/// point it happened: "Context compacted · 3 episodes summarized ·
/// 41k → 9k". `View` opens the context view.
///
/// Every number is optional; a widget shows only what is present.
final class CompactionItem extends TranscriptItem {
  /// Creates a compaction marker.
  const CompactionItem({
    required super.id,
    super.at,
    this.eventId,
    this.state = CompactionState.done,
    this.episodesSummarized,
    this.tokensBefore,
    this.tokensAfter,
    this.detail,
  });

  /// Reads a compaction marker from JSON.
  factory CompactionItem.fromJson(Json j) => CompactionItem(
    id: j.str('id'),
    at: j.timeOpt('at'),
    eventId: j.strOpt('eventId'),
    state: j.enumOf('state', CompactionState.values, CompactionState.done),
    episodesSummarized: j.intOpt('episodesSummarized'),
    tokensBefore: j.intOpt('tokensBefore'),
    tokensAfter: j.intOpt('tokensAfter'),
    detail: j.strOpt('detail'),
  );

  /// The `ContextEvent` this marker belongs to, once there is one.
  final String? eventId;

  /// Running, done or failed.
  final CompactionState state;

  /// How many episodes were summarized.
  final int? episodesSummarized;

  /// The size of what was replaced, in tokens.
  final int? tokensBefore;

  /// The size of what replaced it, in tokens.
  final int? tokensAfter;

  /// A muted detail, such as "summarizing episode 4 · 24k".
  final String? detail;

  @override
  String get type => 'compaction';

  @override
  Json toJson() => _base({
    'eventId': eventId,
    'state': state.name,
    'episodesSummarized': episodesSummarized,
    'tokensBefore': tokensBefore,
    'tokensAfter': tokensAfter,
    'detail': detail,
  });
}

/// A child agent's question to its parent, at the place it was asked in the
/// parent's transcript. It is not the user's [Question].
final class ChildQuestionItem extends TranscriptItem {
  /// Creates the item.
  const ChildQuestionItem({
    required super.id,
    required this.question,
    this.task = '',
    super.at,
  });

  /// Reads the item from JSON.
  factory ChildQuestionItem.fromJson(Json j) => ChildQuestionItem(
    id: j.str('id'),
    at: j.timeOpt('at'),
    question: ChildQuestion.fromJson(j.obj('question')),
    task: j.strOpt('task') ?? '',
  );

  /// The question and its state.
  final ChildQuestion question;

  /// The asking child's task, which names the row.
  final String task;

  @override
  String get type => 'childQuestion';

  @override
  Json toJson() =>
      _base({'question': question.toJson(), 'task': task.isEmpty ? null : task});
}

/// A run was interrupted (a host restart); the pane shows the resume line
/// at this point. Snapshots without the item fall back to the run's
/// outcome.
final class InterruptedItem extends TranscriptItem {
  /// Creates the item.
  const InterruptedItem({required super.id, super.at, this.reason});

  /// Reads the item from JSON.
  factory InterruptedItem.fromJson(Json j) => InterruptedItem(
    id: j.str('id'),
    at: j.timeOpt('at'),
    reason: j.strOpt('reason'),
  );

  /// Why, such as "The host restarted."
  final String? reason;

  @override
  String get type => 'interrupted';

  @override
  Json toJson() => _base({'reason': reason});
}

/// A row of an [ActivityGroup].
sealed class ActivityRow extends KitValue {
  const ActivityRow({required this.id});

  /// Reads a row from JSON; null for an unknown `type`.
  static ActivityRow? fromJson(Json j) => switch (j['type']) {
    'thinking' => ThinkingRow.fromJson(j),
    'tool' => ToolRow.fromJson(j),
    'spawn' => SpawnRow.fromJson(j),
    _ => null,
  };

  /// The row's id (for a tool row, the call id).
  final String id;

  /// The JSON `type` tag.
  String get type;

  /// Whether the row is still in progress.
  bool get isRunning;
}

/// A thinking row ("thought 6s"). [text] is the reasoning text when the
/// backend has the `reasoningText` capability.
final class ThinkingRow extends ActivityRow {
  /// Creates a thinking row.
  const ThinkingRow({
    required super.id,
    this.text,
    this.durationMs,
    this.streaming = false,
  });

  /// Reads a thinking row from JSON.
  factory ThinkingRow.fromJson(Json j) => ThinkingRow(
    id: j.str('id'),
    text: j.strOpt('text'),
    durationMs: j.intOpt('durationMs'),
    streaming: j.boolean('streaming'),
  );

  /// The reasoning text, if the backend exposes it.
  final String? text;

  /// How long it thought, once finished.
  final int? durationMs;

  /// Whether it is still thinking.
  final bool streaming;

  @override
  bool get isRunning => streaming;

  @override
  String get type => 'thinking';

  @override
  Json toJson() => compact({
    'type': type,
    'id': id,
    'text': text,
    'durationMs': durationMs,
    'streaming': streaming ? true : null,
  });
}

/// A tool call row: read, search, exec and the rest.
final class ToolRow extends ActivityRow {
  /// Creates a tool row.
  const ToolRow({
    required super.id,
    required this.name,
    this.kind = ToolKind.other,
    this.target,
    this.arguments,
    this.state = WorkState.running,
    this.meta,
    this.output,
    this.exitCode,
    this.startedAt,
    this.endedAt,
  });

  /// Reads a tool row from JSON.
  factory ToolRow.fromJson(Json j) => ToolRow(
    id: j.str('id'),
    name: j.str('name'),
    kind: j.enumOf('kind', ToolKind.values, ToolKind.other),
    target: j.strOpt('target'),
    arguments: j.strOpt('arguments'),
    state: j.enumOf('state', WorkState.values, WorkState.running),
    meta: j.strOpt('meta'),
    output: switch (j.objOpt('output')) {
      final o? => ToolOutput.fromJson(o),
      null => null,
    },
    exitCode: j.intOpt('exitCode'),
    startedAt: j.timeOpt('startedAt'),
    endedAt: j.timeOpt('endedAt'),
  );

  /// The raw tool name.
  final String name;

  /// What the tool does.
  final ToolKind kind;

  /// The path, pattern or command it acts on.
  final String? target;

  /// The arguments as a JSON string.
  final String? arguments;

  /// Running, done, failed or cancelled.
  final WorkState state;

  /// A short result such as `212 lines` or `9 hits`.
  final String? meta;

  /// Captured output (exec tools).
  final ToolOutput? output;

  /// The process exit code (exec tools).
  final int? exitCode;

  /// When it started.
  final DateTime? startedAt;

  /// When it finished.
  final DateTime? endedAt;

  @override
  bool get isRunning => state == WorkState.running;

  /// Returns a copy with the given fields replaced.
  ToolRow copyWith({
    WorkState? state,
    String? meta,
    ToolOutput? output,
    int? exitCode,
    DateTime? endedAt,
  }) => ToolRow(
    id: id,
    name: name,
    kind: kind,
    target: target,
    arguments: arguments,
    state: state ?? this.state,
    meta: meta ?? this.meta,
    output: output ?? this.output,
    exitCode: exitCode ?? this.exitCode,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
  );

  @override
  String get type => 'tool';

  @override
  Json toJson() => compact({
    'type': type,
    'id': id,
    'name': name,
    'kind': kind.name,
    'target': target,
    'arguments': arguments,
    'state': state.name,
    'meta': meta,
    'output': output?.toJson(),
    'exitCode': exitCode,
    'startedAt': timeJson(startedAt),
    'endedAt': timeJson(endedAt),
  });
}

/// A spawn row: the agent started a child agent. The child's progress is
/// in the crew (`ChatSnapshot.children`), looked up by [childId].
final class SpawnRow extends ActivityRow {
  /// Creates a spawn row.
  const SpawnRow({
    required super.id,
    required this.childId,
    required this.task,
  });

  /// Reads a spawn row from JSON.
  factory SpawnRow.fromJson(Json j) =>
      SpawnRow(id: j.str('id'), childId: j.str('childId'), task: j.str('task'));

  /// The child's chat id.
  final String childId;

  /// The child's task.
  final String task;

  @override
  bool get isRunning => false;

  @override
  String get type => 'spawn';

  @override
  Json toJson() => {'type': type, 'id': id, 'childId': childId, 'task': task};
}
