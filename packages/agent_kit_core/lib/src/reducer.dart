/// The pure event reducer.
library;

import 'events.dart';
import 'items.dart';
import 'models.dart';
import 'snapshot.dart';

/// Folds [event] into [snapshot] and returns the new snapshot.
///
/// A pure function: no clock, no I/O, and [snapshot] is never changed.
/// It returns [snapshot] itself (identical) when the event changes nothing:
///
/// - an event of another chat, or of an unknown kind;
/// - a durable event with `seq <= snapshot.seq` (a replay or duplicate);
/// - a transient fragment with `seq < snapshot.seq` (older than the
///   snapshot), or one whose text is already present;
/// - an event naming an item, row, approval or entry that does not exist,
///   where the event cannot create it.
///
/// A durable event sets the snapshot's `seq` to its own. A [GapEvent]
/// marks the snapshot stale, whatever its sequence; the consumer then
/// reloads it with `loadChat`.
ChatSnapshot reduce(ChatSnapshot snapshot, KitEvent event) {
  if (event.chat != snapshot.chatId) return snapshot;
  if (event is UnknownEvent) return snapshot;
  if (event is GapEvent) {
    return snapshot.stale ? snapshot : snapshot.copyWith(stale: true);
  }
  if (event.transient) {
    if (event.seq < snapshot.seq) return snapshot;
    return _apply(snapshot, event);
  }
  if (event.seq <= snapshot.seq) return snapshot;
  return _apply(snapshot, event).copyWith(seq: event.seq);
}

/// Folds every event of [events] into [snapshot], in order.
ChatSnapshot reduceAll(ChatSnapshot snapshot, Iterable<KitEvent> events) =>
    events.fold(snapshot, reduce);

ChatSnapshot _apply(ChatSnapshot s, KitEvent e) => switch (e) {
  ChatRenamed(:final title) => s.copyWith(title: title),
  ChatArchived(:final archived) => s.copyWith(archived: archived),
  ChatSettingsChanged(:final model, :final profile) => s.copyWith(
    model: model,
    profile: profile,
  ),
  WorkspaceChanged(:final workspace) => s.copyWith(workspace: workspace),
  RunStarted() => s.copyWith(
    run: RunInfo(id: e.runId, model: e.model ?? s.model, startedAt: e.at),
  ),
  RunWaiting() => _runWaiting(s, e),
  RunFinished() => _runFinished(s, e),
  UserMessageAdded() => _userMessage(s, e),
  MessageDelta() => _messageDelta(s, e),
  AssistantMessageCompleted() => _upsertItem(
    s,
    AssistantMessage(
      id: e.itemId,
      at: _itemAt(s, e.itemId) ?? e.at,
      markdown: e.markdown,
      runId: e.runId ?? _runId(s),
    ),
  ),
  SystemLineAdded() => _upsertItem(
    s,
    SystemLine(id: e.itemId, at: e.at, text: e.text),
  ),
  NoticeAdded() => _upsertItem(
    s,
    NoticeLine(id: e.itemId, at: e.at, text: e.text, tone: e.tone),
  ),
  ThinkingStarted() => _upsertRow(
    s,
    e.runId,
    e.at,
    ThinkingRow(id: e.rowId, streaming: true),
    (_) => null,
  ),
  ThinkingDelta() => _upsertRow(
    s,
    e.runId,
    e.at,
    ThinkingRow(
      id: e.rowId,
      text: appendText('', e.offset, e.text),
      streaming: true,
    ),
    (row) {
      if (row is! ThinkingRow || !row.streaming) return row;
      final text = row.text ?? '';
      final next = appendText(text, e.offset, e.text);
      return identical(next, text)
          ? row
          : ThinkingRow(id: row.id, text: next, streaming: true);
    },
  ),
  ThinkingFinished() => _upsertRow(
    s,
    e.runId,
    e.at,
    ThinkingRow(id: e.rowId, text: e.text, durationMs: e.durationMs),
    (row) => ThinkingRow(
      id: e.rowId,
      text: e.text ?? (row is ThinkingRow ? row.text : null),
      durationMs: e.durationMs,
    ),
  ),
  ToolStarted() => _upsertRow(
    s,
    e.runId,
    e.at,
    ToolRow(
      id: e.callId,
      name: e.name,
      kind: e.toolKind,
      target: e.target,
      arguments: e.arguments,
      startedAt: e.at,
    ),
    (row) => row,
  ),
  ToolOutputDelta() => _updateRow(s, e.callId, (row) {
    if (row is! ToolRow || !row.isRunning) return row;
    final out = row.output ?? const ToolOutput(text: '');
    final next = out.appendAt(e.offset, e.text);
    return identical(next, out) ? row : row.copyWith(output: next);
  }),
  ToolFinished() => _updateRow(
    s,
    e.callId,
    (row) => row is ToolRow
        ? row.copyWith(
            state: e.state,
            meta: e.meta,
            output: e.output,
            exitCode: e.exitCode,
            endedAt: e.at,
          )
        : row,
  ),
  EditApplied() => _upsertItem(
    s,
    FileEdit(
      id: e.itemId,
      at: e.at,
      diff: e.diff,
      callId: e.callId,
      undoable: e.undoable,
    ),
  ),
  EditUndone() => _updateItem(
    s,
    e.itemId,
    (item) => item is FileEdit && !item.undone
        ? FileEdit(
            id: item.id,
            at: item.at,
            diff: item.diff,
            callId: item.callId,
            undoable: false,
            undone: true,
          )
        : item,
  ),
  PlanUpdated(:final items) => s.copyWith(plan: items),
  ApprovalRequested(:final approval) => s.copyWith(
    approvals: _upsertById(s.approvals, approval, (a) => a.id),
  ),
  ApprovalResolved() => _resolveApproval(s, e),
  QuestionAsked(:final question) => s.copyWith(
    questions: _upsertById(s.questions, question, (q) => q.id),
  ),
  QuestionResolved() => _resolveQuestion(s, e),
  QueueAdded(:final input) => s.copyWith(
    queue: _upsertById(s.queue, input, (q) => q.id),
  ),
  QueueEdited() => _editQueue(s, e),
  QueueRemoved(:final inputId) => _dropQueued(s, inputId),
  ChildSpawned() => _childSpawned(s, e),
  ChildProgress() => _updateChild(
    s,
    e.childId,
    (c) => c.state.isEnded
        ? c
        : c.copyWith(
            activity: e.activity,
            toolCalls: e.toolCalls,
            // A waiting child changes state by its question and answer,
            // not by progress.
            state: c.state == WorkState.waitingForAnswer ? null : e.state,
          ),
  ),
  ChildQuestionAsked() => _childQuestionAsked(s, e),
  ChildQuestionResolved() => _childQuestionResolved(s, e),
  ChildFinished() => _childFinished(s, e),
  JobStarted() => s.copyWith(
    jobs: _upsertById(
      s.jobs,
      BackgroundJob(id: e.jobId, command: e.command, startedAt: e.at),
      (j) => j.id,
    ),
  ),
  JobOutput() => _updateJob(s, e.jobId, (j) {
    if (j.state != JobState.running) return j;
    final out = j.output ?? const ToolOutput(text: '');
    final next = out.appendAt(e.offset, e.text);
    return identical(next, out) ? j : j.copyWith(output: next);
  }),
  JobExited() => _updateJob(
    s,
    e.jobId,
    (j) => j.copyWith(
      state: e.state,
      exitCode: e.exitCode,
      endedAt: e.at,
      summary: e.summary,
      output: e.output,
    ),
  ),
  UsageUpdated(:final usage) => s.copyWith(usage: usage),
  ContextChanged(:final context) => s.copyWith(context: context),
  CompactionUpdated() => _upsertItem(
    s,
    CompactionItem(
      id: e.itemId,
      at: _itemAt(s, e.itemId) ?? e.at,
      eventId: e.eventId,
      state: e.state,
      episodesSummarized: e.episodesSummarized,
      tokensBefore: e.tokensBefore,
      tokensAfter: e.tokensAfter,
      detail: e.detail,
    ),
  ),
  InterruptedAdded() => _upsertItem(
    s,
    InterruptedItem(id: e.itemId, at: e.at, reason: e.reason),
  ),
  GapEvent() || UnknownEvent() => s,
};

String? _runId(ChatSnapshot s) => s.run?.id;

DateTime? _itemAt(ChatSnapshot s, String id) => s.item(id)?.at;

ChatSnapshot _runWaiting(ChatSnapshot s, RunWaiting e) {
  final run = s.run;
  if (run == null || run.id != e.runId || !run.isActive) return s;
  return s.copyWith(
    run: RunInfo(
      id: run.id,
      model: run.model,
      startedAt: run.startedAt,
      waitingUntil: e.until,
      waitReason: e.reason ?? 'quota',
    ),
  );
}

ChatSnapshot _runFinished(ChatSnapshot s, RunFinished e) {
  final run = s.run;
  if (run != null && run.id != e.runId) return s;
  final rowEnd = e.outcome == RunOutcome.completed
      ? WorkState.done
      : WorkState.cancelled;
  final items = [
    for (final item in s.items)
      switch (item) {
        AssistantMessage(streaming: true) => AssistantMessage(
          id: item.id,
          at: item.at,
          markdown: item.markdown,
          runId: item.runId,
        ),
        ActivityGroup() when item.isRunning => item.withRows([
          for (final row in item.rows)
            switch (row) {
              ThinkingRow(streaming: true) => ThinkingRow(
                id: row.id,
                text: row.text,
                durationMs: row.durationMs,
              ),
              ToolRow(isRunning: true) => row.copyWith(
                state: rowEnd,
                endedAt: e.at,
              ),
              _ => row,
            },
        ]),
        _ => item,
      },
  ];
  return s.copyWith(
    items: items,
    run: RunInfo(
      id: e.runId,
      model: run?.model,
      startedAt: run?.startedAt,
      endedAt: e.at,
      outcome: e.outcome,
      error: e.error,
    ),
  );
}

ChatSnapshot _userMessage(ChatSnapshot s, UserMessageAdded e) {
  final next = _upsertItem(
    s,
    UserMessage(
      id: e.itemId,
      at: e.at,
      text: e.text,
      refs: e.refs,
      inputId: e.inputId,
    ),
  );
  final inputId = e.inputId;
  return inputId == null ? next : _dropQueued(next, inputId);
}

ChatSnapshot _messageDelta(ChatSnapshot s, MessageDelta e) {
  final existing = s.item(e.itemId);
  if (existing == null) {
    if (e.offset != 0) return s;
    return s.copyWith(
      items: [
        ...s.items,
        AssistantMessage(
          id: e.itemId,
          at: e.at,
          markdown: e.text,
          streaming: true,
          runId: e.runId ?? _runId(s),
        ),
      ],
    );
  }
  if (existing is! AssistantMessage || !existing.streaming) return s;
  final next = appendText(existing.markdown, e.offset, e.text);
  if (identical(next, existing.markdown)) return s;
  return _replaceItem(
    s,
    AssistantMessage(
      id: existing.id,
      at: existing.at,
      markdown: next,
      streaming: true,
      runId: existing.runId,
    ),
  );
}

/// Replaces the item with the same id in place, or appends it.
ChatSnapshot _upsertItem(ChatSnapshot s, TranscriptItem item) =>
    s.item(item.id) == null
    ? s.copyWith(items: [...s.items, item])
    : _replaceItem(s, item);

ChatSnapshot _replaceItem(ChatSnapshot s, TranscriptItem item) =>
    s.copyWith(items: [for (final i in s.items) i.id == item.id ? item : i]);

ChatSnapshot _updateItem(
  ChatSnapshot s,
  String id,
  TranscriptItem Function(TranscriptItem) update,
) {
  final item = s.item(id);
  if (item == null) return s;
  final next = update(item);
  return identical(next, item) ? s : _replaceItem(s, next);
}

/// Adds [row] to the open activity group, or updates the row with the
/// same id where it is.
///
/// The open group is the last transcript item when it is an
/// [ActivityGroup] of the same run; otherwise a new group (id
/// `activity:<row id>`) is appended. A message or edit after a group
/// closes it. [update] returns the new row for an existing one, or null to
/// keep it.
ChatSnapshot _upsertRow(
  ChatSnapshot s,
  String? runId,
  DateTime? at,
  ActivityRow row,
  ActivityRow? Function(ActivityRow existing) update,
) {
  for (final item in s.items) {
    if (item is! ActivityGroup) continue;
    for (final existing in item.rows) {
      if (existing.id == row.id) {
        final next = update(existing);
        if (next == null || identical(next, existing)) return s;
        return _updateRow(s, row.id, (_) => next);
      }
    }
  }
  final run = runId ?? _runId(s);
  final last = s.items.isEmpty ? null : s.items.last;
  if (last is ActivityGroup && (last.runId == null || last.runId == run)) {
    return _replaceItem(s, last.withRows([...last.rows, row]));
  }
  return s.copyWith(
    items: [
      ...s.items,
      ActivityGroup(id: 'activity:${row.id}', at: at, runId: run, rows: [row]),
    ],
  );
}

ChatSnapshot _updateRow(
  ChatSnapshot s,
  String rowId,
  ActivityRow Function(ActivityRow) update,
) {
  for (final item in s.items) {
    if (item is! ActivityGroup) continue;
    for (final row in item.rows) {
      if (row.id != rowId) continue;
      final next = update(row);
      if (identical(next, row)) return s;
      return _replaceItem(
        s,
        item.withRows([for (final r in item.rows) r.id == rowId ? next : r]),
      );
    }
  }
  return s;
}

List<T> _upsertById<T>(List<T> list, T value, String Function(T) id) {
  final key = id(value);
  return list.any((v) => id(v) == key)
      ? [for (final v in list) id(v) == key ? value : v]
      : [...list, value];
}

ChatSnapshot _resolveApproval(ChatSnapshot s, ApprovalResolved e) {
  if (!s.approvals.any((a) => a.id == e.approvalId && a.isPending)) return s;
  return s.copyWith(
    approvals: [
      for (final a in s.approvals)
        a.id == e.approvalId
            ? a.resolve(e.state, reason: e.reason, at: e.at)
            : a,
    ],
  );
}

ChatSnapshot _resolveQuestion(ChatSnapshot s, QuestionResolved e) {
  if (!s.questions.any((q) => q.id == e.questionId && q.isPending)) return s;
  return s.copyWith(
    questions: [
      for (final q in s.questions)
        q.id == e.questionId
            ? Question(
                id: q.id,
                requestedAt: q.requestedAt,
                items: q.items,
                state: e.state,
                answers: e.answers,
                reason: e.reason,
                answeredAt: e.state == QuestionState.answered ? e.at : null,
              )
            : q,
    ],
  );
}

ChatSnapshot _editQueue(ChatSnapshot s, QueueEdited e) {
  if (!s.queue.any((q) => q.id == e.inputId)) return s;
  return s.copyWith(
    queue: [
      for (final q in s.queue) q.id == e.inputId ? q.withText(e.text) : q,
    ],
  );
}

ChatSnapshot _dropQueued(ChatSnapshot s, String inputId) =>
    s.queue.any((q) => q.id == inputId)
    ? s.copyWith(
        queue: [
          for (final q in s.queue)
            if (q.id != inputId) q,
        ],
      )
    : s;

ChatSnapshot _childSpawned(ChatSnapshot s, ChildSpawned e) {
  final withRow = _upsertRow(
    s,
    e.runId,
    e.at,
    SpawnRow(id: e.callId ?? e.childId, childId: e.childId, task: e.task),
    (row) => row,
  );
  if (withRow.children.any((c) => c.id == e.childId)) return withRow;
  return withRow.copyWith(
    children: [
      ...withRow.children,
      ChildAgent(id: e.childId, task: e.task, startedAt: e.at),
    ],
  );
}

ChatSnapshot _childFinished(ChatSnapshot s, ChildFinished e) {
  ChildAgent? child;
  for (final c in s.children) {
    if (c.id == e.childId) child = c;
  }
  if (child == null || child.state.isEnded) return s;
  final next = _updateChild(
    s,
    e.childId,
    (c) => c.copyWith(
      state: e.state,
      endedAt: e.at,
      result: e.result,
      clearQuestion: true,
    ),
  );
  final withQuestion = _closeChildQuestion(
    next,
    child.pendingQuestion,
    ChildQuestionState.cancelled,
    at: e.at,
  );
  if (e.result == null &&
      e.state != WorkState.failed &&
      e.state != WorkState.timedOut) {
    return withQuestion;
  }
  return _upsertItem(
    withQuestion,
    ChildResult(
      id: 'return:${e.childId}',
      at: e.at,
      childId: e.childId,
      task: child.task,
      state: e.state,
      result: e.result,
    ),
  );
}

ChatSnapshot _updateChild(
  ChatSnapshot s,
  String id,
  ChildAgent Function(ChildAgent) update,
) {
  if (!s.children.any((c) => c.id == id)) return s;
  return s.copyWith(
    children: [for (final c in s.children) c.id == id ? update(c) : c],
  );
}

ChatSnapshot _updateJob(
  ChatSnapshot s,
  String id,
  BackgroundJob Function(BackgroundJob) update,
) {
  BackgroundJob? job;
  for (final j in s.jobs) {
    if (j.id == id) job = j;
  }
  if (job == null) return s;
  final next = update(job);
  if (identical(next, job)) return s;
  return s.copyWith(jobs: [for (final j in s.jobs) j.id == id ? next : j]);
}

String _childQuestionItemId(String questionId) => 'childq:$questionId';

ChatSnapshot _childQuestionAsked(ChatSnapshot s, ChildQuestionAsked e) {
  final q = e.question;
  ChildAgent? child;
  for (final c in s.children) {
    if (c.id == q.childId) child = c;
  }
  // A question of an unknown or ended child has no one to wait.
  if (child == null || child.state.isEnded) return s;
  final withChild = _updateChild(
    s,
    q.childId,
    (c) => c.copyWith(state: WorkState.waitingForAnswer, pendingQuestion: q),
  );
  return _upsertItem(
    withChild,
    ChildQuestionItem(
      id: _childQuestionItemId(q.id),
      at: q.askedAt,
      question: q,
      task: child.task,
    ),
  );
}

ChatSnapshot _childQuestionResolved(ChatSnapshot s, ChildQuestionResolved e) {
  ChildAgent? child;
  for (final c in s.children) {
    if (c.id == e.childId) child = c;
  }
  final pending = child?.pendingQuestion;
  if (child == null ||
      pending == null ||
      pending.id != e.questionId ||
      !pending.isPending) {
    return s;
  }
  final answered = e.state == ChildQuestionState.answered;
  final next = _updateChild(
    s,
    e.childId,
    (c) => c.copyWith(
      state: answered && c.state == WorkState.waitingForAnswer
          ? WorkState.running
          : null,
      clearQuestion: true,
    ),
  );
  return _closeChildQuestion(
    next,
    pending,
    e.state,
    answer: e.answer,
    at: e.at,
    by: answered ? e.answeredBy ?? AnsweredBy.parent : null,
  );
}

/// Marks [question]'s transcript item as resolved as [state]; does nothing
/// without a pending question or its item.
ChatSnapshot _closeChildQuestion(
  ChatSnapshot s,
  ChildQuestion? question,
  ChildQuestionState state, {
  String? answer,
  DateTime? at,
  AnsweredBy? by,
}) {
  if (question == null || !question.isPending) return s;
  final resolved = question.resolve(state, answer: answer, at: at, by: by);
  return _updateItem(
    s,
    _childQuestionItemId(question.id),
    (item) => item is ChildQuestionItem
        ? ChildQuestionItem(
            id: item.id,
            at: item.at,
            question: resolved,
            task: item.task,
          )
        : item,
  );
}
