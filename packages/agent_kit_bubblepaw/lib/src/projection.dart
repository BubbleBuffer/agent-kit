import 'dart:convert';

import 'package:agent_kit_core/agent_kit_core.dart';

/// Projects the pinned BubblePaw stdio session API into kit values.
///
/// Kit sequences reserve sixteen positions per host sequence. Snapshots use
/// the last position; durable events use the first positions, and live text
/// uses the last. This allows one host event to produce several kit events.
/// These are native Dart sequences, not JavaScript-safe wire cursors. Always
/// use the original host cursor (or [hostSequence]) for `events.after`.
///
/// Canonical message IDs are only available in session.state. Live replies keep
/// their provisional IDs through completion, until an explicit snapshot reload.
/// Queue and usage changes are reconciled by the backend from session.state.
/// Explicit `text` publications are preserved as system lines; file, image,
/// archived table and execution outputs have no matching kit renderer.
final class BubblePawProjection {
  final Map<String, _Session> _sessions = {};

  /// Converts a kit sequence back to its BubblePaw durable cursor.
  static int hostSequence(int kitSequence) => kitSequence ~/ 16;

  /// Seeds a subscription at its requested cursor, even when the cached
  /// snapshot was loaded later. A newer snapshot must not suppress replay.
  void replayFrom(String chatId, int after) {
    final state = _sessions[chatId];
    if (state == null || after < state.sequence) {
      _sessions[chatId] = _Session(after);
    }
  }

  /// Resets stream reconciliation only after an explicit view discontinuity.
  void adopt(ChatSnapshot snapshot) {
    final sequence = hostSequence(snapshot.seq);
    final state = _Session(
      sequence,
      snapshotSequence: sequence,
      model: snapshot.run?.model,
    );
    for (final item in snapshot.items.whereType<AssistantMessage>()) {
      final run = item.runId;
      if (item.streaming && run != null) {
        final reply = state.reply(run);
        reply.confirmed = item.markdown;
        reply.visible = item.markdown;
        reply.requestPrefix = item.markdown;
      }
    }
    _sessions[snapshot.chatId] = state;
  }

  /// Releases all stream reconciliation state, or just that of [chatId].
  void reset([String? chatId]) {
    if (chatId == null) {
      _sessions.clear();
    } else {
      _sessions.remove(chatId);
    }
  }

  /// Reads a complete session.state result and resets its stream state.
  ///
  /// The caller may add `approvals` from approval.list. BubblePaw does not
  /// expose timestamps for queued inputs or questions; the epoch represents
  /// an unknown time, rather than an invented arrival time.
  ///
  /// [children], [context] and [compactions] come from other reads (child
  /// sessions, `context.view` and `context.events`) and stay empty without
  /// the matching host features.
  ChatSnapshot snapshot(
    Map<String, Object?> state, {
    required String workspaceDirectory,
    List<ChildAgent> children = const [],
    ContextView? context,
    List<CompactionItem> compactions = const [],
    String? defaultModel,
  }) {
    final session = _map(state['session']);
    final chat = _string(session, 'id');
    final rawSeq = _integer(state, 'seq');
    final seq = _base(rawSeq) + 15;
    final runs = _maps(state['runs']).toList()
      ..sort(
        (a, b) => _string(a, 'started_at').compareTo(_string(b, 'started_at')),
      );
    final lastRun = runs.isEmpty ? null : runs.last;
    final run = lastRun == null ? null : _run(lastRun);
    final items = <TranscriptItem>[];
    final toolLocations = <String, int>{};
    for (final message in _maps(state['messages'])) {
      final id = _string(message, 'id');
      final at = _time(message['created_at']);
      final content = _string(message, 'content');
      switch (message['role']) {
        case 'user':
          items.add(UserMessage(id: id, text: content, at: at));
        case 'assistant':
          if (content.isNotEmpty) {
            items.add(AssistantMessage(id: id, markdown: content, at: at));
          }
          final calls = _maps(message['tool_calls']).toList();
          if (calls.isNotEmpty) {
            final rows = <ActivityRow>[];
            for (final call in calls) {
              final callId = _string(call, 'id');
              toolLocations[callId] = items.length;
              rows.add(
                ToolRow(
                  id: callId,
                  name: _string(call, 'name'),
                  arguments: _arguments(call['arguments']),
                  startedAt: at,
                  // A missing tool result is not evidence of success.
                  state: run?.isActive == true
                      ? WorkState.running
                      : WorkState.cancelled,
                ),
              );
            }
            items.add(
              ActivityGroup(id: 'bubblepaw:tools:$id', at: at, rows: rows),
            );
          }
        case 'tool':
          final callId = message['tool_call_id'];
          final index = toolLocations[callId];
          if (index != null) {
            final group = items[index] as ActivityGroup;
            items[index] = group.withRows([
              for (final row in group.rows)
                if (row is ToolRow && row.id == callId)
                  row.copyWith(
                    state: message['is_error'] == true
                        ? WorkState.failed
                        : WorkState.done,
                    output: ToolOutput(text: content),
                    endedAt: at,
                  )
                else
                  row,
            ]);
          } else {
            // Retention/archives can contain a result without its call.
            items.add(SystemLine(id: id, text: content, at: at));
          }
        case 'system':
          items.add(SystemLine(id: id, text: content, at: at));
      }
    }
    void place(TranscriptItem line) {
      final at = line.at;
      final next = at == null
          ? -1
          : items.indexWhere((item) => item.at?.isAfter(at) == true);
      items.insert(next < 0 ? items.length : next, line);
    }

    for (final record in _maps(state['outputs'])) {
      final line = _outputLine(record);
      if (line == null || items.any((item) => item.id == line.id)) continue;
      place(line);
    }
    for (final marker in compactions) {
      if (items.every((item) => item.id != marker.id)) place(marker);
    }
    final stream = _Session(
      rawSeq,
      snapshotSequence: rawSeq,
      model: run?.model,
    );
    final streamingText = state['streaming_text'];
    if (run != null &&
        run.isActive &&
        streamingText is String &&
        streamingText.isNotEmpty) {
      final reply = stream.reply(run.id);
      reply.confirmed = streamingText;
      reply.visible = streamingText;
      reply.requestPrefix = streamingText;
      items.add(
        AssistantMessage(
          id: _replyId(run.id),
          markdown: streamingText,
          streaming: true,
          runId: run.id,
        ),
      );
    }
    _sessions[chat] = stream;
    final questionWire = state['question'];
    final directoryParts = workspaceDirectory
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty);
    return ChatSnapshot(
      chatId: chat,
      seq: seq,
      title: _string(session, 'title'),
      parentId: session['parent_session_id'] as String?,
      // The model of the run in progress; otherwise the host default, which
      // is what the next run uses.
      model: run != null && run.isActive
          ? run.model ?? defaultModel
          : defaultModel ?? run?.model,
      workspace: WorkspaceInfo(
        name: directoryParts.isEmpty ? workspaceDirectory : directoryParts.last,
        path: workspaceDirectory,
      ),
      run: run,
      items: items,
      approvals: [for (final a in _maps(state['approvals'])) approval(a)],
      // Root answer endpoints cannot answer child questions. The source state
      // endpoint returns pending questions only, so resolved history disappears
      // on reload even when resolution was observed in the live event stream.
      questions:
          questionWire is Map<String, Object?> &&
              session['parent_session_id'] == null
          ? [question(_map(questionWire))]
          : const [],
      queue: [
        for (final input in _maps(state['inputs']))
          if (input['state'] == 'pending')
            QueuedInput(
              id: _string(input, 'id'),
              text: _string(input, 'text'),
              queuedAt: _unknownTime,
              mode: input['kind'] == 'steer'
                  ? QueueMode.steer
                  : QueueMode.followup,
            ),
      ],
      plan: _plan(state['todo']),
      usage: _usage(state['usage']),
      children: children,
      context: context,
    );
  }

  /// Metadata available from session.list; that endpoint has no run status.
  ChatSummary summary(Map<String, Object?> session) => ChatSummary(
    id: _string(session, 'id'),
    title: _string(session, 'title'),
    parentId: session['parent_session_id'] as String?,
    updatedAt: _time(session['updated_at']),
  );

  /// Maps the persisted approval record, without inferring a tool category.
  Approval approval(Map<String, Object?> wire) => Approval(
    id: _string(wire, 'id'),
    tool: _string(wire, 'tool'),
    callId: wire['call_id'] as String?,
    runId: wire['run_id'] as String?,
    arguments: _arguments(wire['arguments']),
    requestedAt: _time(wire['created_at']) ?? _unknownTime,
    decidedAt: _time(wire['decided_at']),
    state: _approvalState(wire['state']),
    reason: wire['reason'] as String?,
  );

  /// One free text question, with optional suggestions and an Other input.
  /// Its answer key is always `answer`; selected suggestions remain labels.
  Question question(Map<String, Object?> wire, {DateTime? requestedAt}) {
    final options = (wire['options'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    final status = wire['status'];
    return Question(
      id: _string(wire, 'id'),
      requestedAt: requestedAt ?? _unknownTime,
      state: status == 'answered'
          ? QuestionState.answered
          : status == 'cancelled'
          ? QuestionState.cancelled
          : QuestionState.pending,
      items: [
        QuestionItem(
          id: 'answer',
          header: 'Question',
          text: _string(wire, 'text'),
          kind: options.isEmpty ? QuestionKind.text : QuestionKind.pickOne,
          options: [for (final label in options) QuestionOption(label: label)],
          allowOther: options.isNotEmpty,
        ),
      ],
      answers: status == 'answered'
          ? {'answer': QuestionAnswer(text: wire['answer'] as String?)}
          : null,
    );
  }

  /// Reads a HarnessEvent, `event` notification, or `events.gap` notification.
  ///
  /// stdio snapshots omit the web API's live_seen. Live fragments at the exact
  /// snapshot cursor are therefore discarded: their inclusion is unknowable.
  /// Later durable boundaries and canonical reloads recover the complete text.
  List<KitEvent> event(Map<String, Object?> wire) {
    if (wire['method'] == 'events.gap') {
      final params = _map(wire['params']);
      return [
        for (final entry in _sessions.entries)
          GapEvent(
            seq:
                _base(entry.value.sequence < 0 ? 0 : entry.value.sequence) + 15,
            chat: entry.key,
            skipped: params['skipped'] as int?,
          ),
      ];
    }
    if (wire['method'] == 'event') wire = _map(wire['params']);
    final chat = _string(wire, 'session_id');
    final run = _string(wire, 'run_id');
    final rawSeq = _integer(wire, 'sequence');
    final durable = wire['durable'] != false;
    final seq = _base(rawSeq);
    final at = _time(wire['created_at']);
    final state = _sessions.putIfAbsent(chat, () => _Session(-1));
    if (durable) {
      if (rawSeq <= state.sequence) return const [];
      state.sequence = rawSeq;
      state.live.clear();
    } else {
      if (rawSeq < state.sequence || rawSeq <= state.snapshotSequence) {
        return const [];
      }
      // A repeated notification must keep the same offset, even when it follows
      // other fragments. Source timestamps retain their original precision.
      final fingerprint = jsonEncode(wire);
      if (!state.live.add(fingerprint)) return const [];
    }
    GapEvent gap() => GapEvent(seq: seq + 14, chat: chat, at: at);
    switch (wire['type']) {
      case 'run_started':
        state.model = wire['model'] as String?;
        state.replies.clear();
        return [
          RunStarted(
            seq: seq,
            chat: chat,
            at: at,
            runId: run,
            model: state.model,
          ),
        ];
      case 'run_waiting_for_quota':
        final wait = _map(wire['wait']);
        return [
          RunWaiting(
            seq: seq,
            chat: chat,
            at: at,
            runId: run,
            until: _time(wait['resume_at']),
            reason: wait['reason'] as String?,
          ),
        ];
      case 'run_quota_resumed':
        // Core clears quota wait on RunStarted; the host retains the run ID.
        return [
          RunStarted(
            seq: seq,
            chat: chat,
            at: at,
            runId: run,
            model: state.model,
          ),
        ];
      case 'text_delta':
      case 'paragraph':
        final reply = state.reply(run);
        if (reply.blocked) return const [];
        final text = _string(wire, 'text');
        String next;
        if (wire['type'] == 'text_delta') {
          reply.requestText += text;
          next = _join(reply.requestPrefix, reply.requestText);
        } else {
          reply.confirmed = _join(reply.confirmed, text);
          next = reply.confirmed;
        }
        if (reply.visible.startsWith(next)) return const [];
        if (!next.startsWith(reply.visible)) {
          reply.blocked = true;
          return [gap()];
        }
        final offset = reply.visible.length;
        reply.visible = next;
        return [
          MessageDelta(
            seq: seq + 15,
            chat: chat,
            at: at,
            itemId: _replyId(run),
            runId: run,
            offset: offset,
            text: next.substring(offset),
          ),
        ];
      case 'model_request_started':
        final reply = state.reply(run);
        if (reply.visible != reply.confirmed) {
          reply.blocked = true;
          return [gap()];
        }
        reply.requestPrefix = reply.confirmed;
        reply.requestText = '';
        return const [];
      case 'tool_started':
        // Nested tool boundaries are live-only. Core tool events are durable,
        // so they cannot represent those without consuming future sequences.
        if (!durable) return [gap()];
        final call = _map(wire['call']);
        return [
          ToolStarted(
            seq: seq,
            chat: chat,
            at: at,
            runId: run,
            callId: _string(call, 'id'),
            name: _string(call, 'name'),
            arguments: _arguments(call['arguments']),
          ),
        ];
      case 'tool_finished':
        if (!durable) return [gap()];
        final result = _map(wire['result']);
        return [
          ToolFinished(
            seq: seq,
            chat: chat,
            at: at,
            callId: _string(wire, 'call_id'),
            state: result['pending'] == true
                ? WorkState.running
                : result['is_error'] == true
                ? WorkState.failed
                : WorkState.done,
            output: ToolOutput(text: _string(result, 'content')),
          ),
        ];
      case 'approval_requested':
        return [
          ApprovalRequested(
            seq: seq,
            chat: chat,
            at: at,
            approval: approval(_map(wire['approval'])),
          ),
        ];
      case 'approval_resolved':
        return [
          ApprovalResolved(
            seq: seq,
            chat: chat,
            at: at,
            approvalId: _string(wire, 'approval_id'),
            state: _approvalState(wire['state']),
            reason: wire['reason'] as String?,
          ),
        ];
      case 'host_state_changed':
        if (wire['key'] == 'todo') {
          return [
            PlanUpdated(
              seq: seq,
              chat: chat,
              at: at,
              items: _plan(wire['value']),
            ),
          ];
        }
        if (wire['key'] == 'question') {
          final value = wire['value'];
          if (value is! Map<String, Object?>) return [gap()];
          final q = _map(value);
          if (q['parent_session_id'] != null) return [gap()];
          if (q['status'] == 'pending') {
            return [
              QuestionAsked(
                seq: seq,
                chat: chat,
                at: at,
                question: question(q, requestedAt: at),
              ),
            ];
          }
          return [
            QuestionResolved(
              seq: seq,
              chat: chat,
              at: at,
              questionId: _string(q, 'id'),
              state: q['status'] == 'answered'
                  ? QuestionState.answered
                  : QuestionState.cancelled,
              answers: q['status'] == 'answered'
                  ? {'answer': QuestionAnswer(text: q['answer'] as String?)}
                  : null,
            ),
          ];
        }
        // usage.last_request is published for every provider response, even
        // without usage values. It is not a history discontinuity. Session
        // totals are read on completion; unknown host state has no kit view.
        return const [];
      case 'run_finished':
        state.replies.remove(run);
        final text = wire['text'];
        return [
          if (text is String && text.isNotEmpty)
            AssistantMessageCompleted(
              seq: seq,
              chat: chat,
              at: at,
              itemId: _replyId(run),
              markdown: text,
              runId: run,
            ),
          RunFinished(
            seq: seq + 1,
            chat: chat,
            at: at,
            runId: run,
            outcome: _outcome(wire['status']) ?? RunOutcome.failed,
            error: _safeRunError(wire['error']),
          ),
          // Run usage is an aggregate for this run, not session totals. The
          // backend reads authoritative session usage without declaring a gap.
        ];
      case 'output':
        final line = _outputLine(_map(wire['record']));
        if (line == null) return const [];
        return [
          SystemLineAdded(
            seq: seq,
            chat: chat,
            at: line.at,
            itemId: line.id,
            text: line.text,
          ),
        ];
      case 'steering_accepted':
      case 'followup_queued':
      case 'session_settled':
        // Input notifications omit queue/message IDs; never manufacture them.
        // The backend refreshes queue/usage without resetting this projection.
        return const [];
      default:
        return const [];
    }
  }
}

final _unknownTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _base(int seq) {
  // v0.2.2 store_serving.rs caps source cursors at (1 << 53) - 1. Scaling
  // still fits native Dart; this literal also lets non-live web apps compile.
  if (seq < 0 || seq > 9007199254740991) {
    throw const FormatException(
      'BubblePaw sequence is outside the protocol range',
    );
  }
  return seq * 16;
}

Map<String, Object?> _map(Object? value) => value is Map<String, Object?>
    ? Map<String, Object?>.of(value)
    : <String, Object?>{};
Iterable<Map<String, Object?>> _maps(Object? value) => value is List<Object?>
    ? value.whereType<Map<String, Object?>>().map(_map)
    : const [];
String _string(Map<String, Object?> value, String key) =>
    value[key] as String? ?? '';
int _integer(Map<String, Object?> value, String key) => value[key] as int? ?? 0;
DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
String _arguments(Object? value) => jsonEncode(value);
SystemLine? _outputLine(Map<String, Object?> record) {
  final output = _map(record['output']);
  final text = output['text'];
  final id = record['id'];
  if (output['type'] != 'text' ||
      text is! String ||
      id is! String ||
      id.isEmpty) {
    return null;
  }
  return SystemLine(id: id, text: text, at: _time(record['created_at']));
}

String _replyId(String run) => 'bubblepaw:reply:$run';
String _join(String first, String second) => first.isEmpty
    ? second
    : second.isEmpty
    ? first
    : '$first\n\n$second';

RunOutcome? _outcome(Object? status) => switch (status) {
  'completed' => RunOutcome.completed,
  'failed' => RunOutcome.failed,
  'cancelled' => RunOutcome.cancelled,
  'interrupted' => RunOutcome.interrupted,
  _ => null,
};

RunInfo _run(Map<String, Object?> run) => RunInfo(
  id: _string(run, 'id'),
  model: run['model'] as String?,
  startedAt: _time(run['started_at']),
  endedAt: _time(run['ended_at']),
  outcome: _outcome(run['status']),
  error: _safeRunError(run['error']),
  waitReason: run['status'] == 'waiting_for_quota'
      ? 'Waiting for provider quota'
      : null,
);

// Host errors contain unrestricted anyhow cause chains and may include raw
// provider responses. Keep diagnostics out of the presentation model.
String? _safeRunError(Object? value) =>
    value == null ? null : 'The BubblePaw run ended before completing.';

ApprovalState _approvalState(Object? value) => switch (value) {
  'approved' => ApprovalState.approved,
  'approved_session' => ApprovalState.approvedForSession,
  'denied' => ApprovalState.denied,
  'expired' => ApprovalState.expired,
  'cancelled' => ApprovalState.cancelled,
  _ => ApprovalState.pending,
};

List<PlanItem> _plan(Object? value) => [
  for (final (index, item) in _maps(value).indexed)
    PlanItem(
      id: 'bubblepaw:todo:$index',
      text: _string(item, 'text'),
      state: item['status'] == 'done'
          ? PlanItemState.done
          : item['status'] == 'in_progress'
          ? PlanItemState.now
          : PlanItemState.todo,
    ),
];

Usage? _usage(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final wire = _map(value);
  final context = _map(wire['context']);
  // Own totals describe this chat; descendants are represented separately by
  // the host, so using total here would silently change the meaning.
  final tokens = _map(_map(wire['own'])['tokens']);
  return Usage(
    contextTokens: context['last_request_input_tokens'] as int?,
    contextLimit: context['window_tokens'] as int?,
    inputTokens: tokens['input_tokens'] as int?,
    outputTokens: tokens['output_tokens'] as int?,
    cacheReadTokens: tokens['cache_read_tokens'] as int?,
  );
}

final class _Session {
  _Session(this.sequence, {this.snapshotSequence = -1, this.model});
  int sequence;
  final int snapshotSequence;
  String? model;
  final Map<String, _Reply> replies = {};
  final Set<String> live = {};
  _Reply reply(String run) => replies.putIfAbsent(run, _Reply.new);
}

final class _Reply {
  String confirmed = '';
  String visible = '';
  String requestPrefix = '';
  String requestText = '';
  bool blocked = false;
}
