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
/// Canonical message IDs are only available in session.state. Run completion
/// and queue changes finish with a [GapEvent], requesting a reload.
/// Provisional reply IDs disappear when that snapshot replaces the old one.
final class BubblePawProjection {
  final Map<String, _Session> _sessions = {};

  /// Converts a kit sequence back to its BubblePaw durable cursor.
  static int hostSequence(int kitSequence) => kitSequence ~/ 16;

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
  ChatSnapshot snapshot(
    Map<String, Object?> state, {
    required String workspaceDirectory,
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
      model: run?.model,
      workspace: WorkspaceInfo(
        name: directoryParts.isEmpty ? workspaceDirectory : directoryParts.last,
        path: workspaceDirectory,
      ),
      run: run,
      items: items,
      approvals: [for (final a in _maps(state['approvals'])) approval(a)],
      // Root answer endpoints cannot answer child questions.
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
      if (rawSeq < state.sequence || rawSeq <= state.snapshotSequence)
        return const [];
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
        return [gap()];
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
          // following snapshot reload obtains the authoritative session usage.
          gap(),
        ];
      case 'steering_accepted':
      case 'followup_queued':
      case 'session_settled':
      case 'output':
        // Input notifications omit queue/message IDs; never manufacture them.
        return [gap()];
      default:
        return const [];
    }
  }
}

final _unknownTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _base(int seq) {
  if (seq < 0 || seq > 576460752303423487) {
    throw const FormatException(
      'BubblePaw sequence cannot fit the native kit cursor',
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
String? _safeRunError(Object? value) => value == null
    ? null
    : 'The BubblePaw run ended before completing.';

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
