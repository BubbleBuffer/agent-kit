import 'package:agent_kit_core/agent_kit_core.dart';

/// Projects BubblePaw-Core v0.3.0's context reads and child sessions into kit
/// values.
///
/// The host names message ranges by message ID and the kit by integer
/// sequence. The host's own canonical `seq` (reported by `history.range`) is
/// the kit sequence. The backend resolves each ID once through `history.range`
/// and passes the answers in as [SeqOf]. A host sequence is a store sequence,
/// so it is increasing but not necessarily dense: a count derived from a
/// sequence span can exceed the number of messages.
typedef Wire = Map<String, Object?>;

/// Looks up the host sequence of a message ID resolved earlier.
typedef SeqOf = int? Function(String? messageId);

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// The kit summary ID of an episode summary. The host needs the kind to read
/// a summary, the kit passes a bare string, so the kind travels in the ID.
String episodeSummaryId(String id) => 'episode:$id';

/// The kit summary ID of a chapter summary.
String chapterSummaryId(String id) => 'chapter:$id';

/// Splits a kit summary ID into its kind and the host ID.
(ContextSummaryKind, String)? parseSummaryId(String id) {
  const episode = 'episode:';
  const chapter = 'chapter:';
  if (id.startsWith(episode) && id.length > episode.length) {
    return (ContextSummaryKind.episode, id.substring(episode.length));
  }
  if (id.startsWith(chapter) && id.length > chapter.length) {
    return (ContextSummaryKind.chapter, id.substring(chapter.length));
  }
  return null;
}

Wire _map(Object? value) => value is Map<String, Object?>
    ? Map<String, Object?>.of(value)
    : <String, Object?>{};
List<Wire> _maps(Object? value) => value is List<Object?>
    ? [for (final item in value.whereType<Map<String, Object?>>()) _map(item)]
    : const [];
String _string(Wire value, String key) => value[key] as String? ?? '';
String? _stringOpt(Wire value, String key) {
  final text = value[key];
  return text is String && text.isNotEmpty ? text : null;
}

int _int(Wire value, String key) => (value[key] as num?)?.toInt() ?? 0;
int? _intOpt(Wire value, String key) => (value[key] as num?)?.toInt();
DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Message IDs a `context.view` result refers to.
Iterable<String> viewMessageIds(Wire view) sync* {
  for (final block in _maps(view['blocks'])) {
    final first = _stringOpt(block, 'first_message_id');
    final last = _stringOpt(block, 'last_message_id');
    if (first != null) yield first;
    if (last != null) yield last;
  }
}

/// Message IDs a `context.structure` and `context.events` result refer to.
Iterable<String> structureMessageIds(Wire structure, List<Wire> events) sync* {
  for (final key in ['episodes', 'chapters', 'legacy_chapters']) {
    for (final item in _maps(structure[key])) {
      final first = _stringOpt(item, 'first_message_id');
      final last = _stringOpt(item, 'last_message_id');
      if (first != null) yield first;
      if (last != null) yield last;
    }
  }
  for (final event in events) {
    final first = _stringOpt(event, 'first_message_id');
    final last = _stringOpt(event, 'last_message_id');
    if (first != null) yield first;
    if (last != null) yield last;
  }
}

ContextBlockKind? _blockKind(Object? kind) => switch (kind) {
  'opening' => ContextBlockKind.opening,
  'memory_index' => ContextBlockKind.memoryIndex,
  'anchors' => ContextBlockKind.anchors,
  'chapter_summary' => ContextBlockKind.chapterSummary,
  'episode_summary' => ContextBlockKind.episodeSummary,
  'raw_suffix' => ContextBlockKind.rawSuffix,
  _ => null,
};

/// The serving view.
///
/// The host's `threshold` is the input size at which a compaction is applied.
/// It does not report the context window; that comes from the session's usage
/// ([windowTokens]) and the response reserve is the window minus the
/// threshold. Without a window the reserve is zero and the window equals the
/// threshold. `pendingEpisodeIds` is not derivable from stdio and stays empty.
/// [appliedAt] is the time of the latest `applied` fact.
ContextView contextView(
  Wire view, {
  required SeqOf seq,
  int? windowTokens,
  DateTime? appliedAt,
}) {
  final threshold = _int(view, 'threshold');
  final window = windowTokens != null && windowTokens >= threshold
      ? windowTokens
      : threshold;
  return ContextView(
    window: window,
    applyCap: threshold,
    responseReserve: window - threshold,
    appliedAt: appliedAt,
    blocks: [
      for (final block in _maps(view['blocks']))
        if (_blockKind(block['kind']) case final kind?)
          ContextBlock(
            kind: kind,
            tokens: _intOpt(block, 'tokens'),
            summaryId: switch ((kind, _stringOpt(block, 'id'))) {
              (ContextBlockKind.episodeSummary, final id?) => episodeSummaryId(
                id,
              ),
              (ContextBlockKind.chapterSummary, final id?) => chapterSummaryId(
                id,
              ),
              _ => null,
            },
            firstSeq: seq(_stringOpt(block, 'first_message_id')),
            lastSeq: seq(_stringOpt(block, 'last_message_id')),
          ),
    ],
  );
}

ContextTrigger? _trigger(Object? value) => switch (value) {
  null => null,
  'pressure' => ContextTrigger.pressure,
  'emergency' => ContextTrigger.emergency,
  'source_size' => ContextTrigger.sourceSize,
  'subject_change' => ContextTrigger.subjectChange,
  'manual' => ContextTrigger.manual,
  _ => ContextTrigger.unknown,
};

ContextEventKind? _eventKind(Object? value) => switch (value) {
  'episode_written' => ContextEventKind.episodeWritten,
  'chapter_closed' => ContextEventKind.chapterClosed,
  'applied' => ContextEventKind.applied,
  _ => null,
};

/// The time of the latest `applied` fact, or null.
DateTime? latestApplied(List<Wire> events) {
  DateTime? latest;
  for (final event in events) {
    if (event['kind'] != 'applied') continue;
    final at = _time(event['created_at']);
    if (at != null && (latest == null || at.isAfter(latest))) latest = at;
  }
  return latest;
}

/// The compaction markers of a transcript: one per `applied` fact.
List<CompactionItem> compactionItems(List<Wire> events) => [
  for (final event in events)
    if (event['kind'] == 'applied' && _stringOpt(event, 'id') != null)
      CompactionItem(
        id: compactionItemId(_string(event, 'id')),
        at: _time(event['created_at']),
        eventId: _string(event, 'id'),
        episodesSummarized: (event['episode_ids'] as List<Object?>?)?.length,
        tokensBefore: _intOpt(event, 'tokens_before'),
        tokensAfter: _intOpt(event, 'tokens_after'),
        detail: _stringOpt(event, 'trigger_text'),
      ),
];

/// The transcript item ID of a compaction fact.
String compactionItemId(String eventId) => 'bubblepaw:compaction:$eventId';

/// The details behind the serving view.
///
/// Episodes and chapters whose message range cannot be resolved are left out;
/// so are chapters without episodes (nothing to cover yet) and events whose
/// range cannot be resolved. Summary bodies stay empty ([ContextSummary.text]);
/// `loadSummary` has them. A summary's creation time is the time of the fact
/// that wrote it, or the UTC epoch when no fact is recorded. A summary counts
/// as applied when the serving view holds it. A fact whose
/// `tokens_before` is unknown (inherited coverage) takes the source size of
/// the episodes it covers, or zero when none are known: the kit event cannot
/// hold an unknown size.
ContextDetails contextDetails({
  required Wire structure,
  required List<Wire> events,
  required Wire? view,
  required SeqOf seq,
}) {
  final appliedIds = <String>{
    if (view != null)
      for (final block in _maps(view['blocks'])) ?_stringOpt(block, 'id'),
  };
  final episodeWires = _maps(structure['episodes']);
  final chapterWires = _maps(structure['chapters']);
  final legacyWires = _maps(structure['legacy_chapters']);
  final chapterIds = {
    for (final c in chapterWires) _string(c, 'id'),
    for (final c in legacyWires) _string(c, 'id'),
  };
  final episodeSource = {
    for (final e in episodeWires) _string(e, 'id'): _int(e, 'source_tokens'),
  };

  DateTime? writtenAt(String id, ContextEventKind kind) {
    for (final event in events) {
      if (_eventKind(event['kind']) != kind) continue;
      final ids = (event['episode_ids'] as List<Object?>? ?? const [])
          .whereType<String>();
      if (event['summary_id'] == id || (ids.contains(id))) {
        final at = _time(event['created_at']);
        if (at != null) return at;
      }
    }
    return null;
  }

  final episodes = <ContextEpisode>[];
  final summaries = <ContextSummary>[];
  for (final e in episodeWires) {
    final id = _string(e, 'id');
    final first = seq(_stringOpt(e, 'first_message_id'));
    final last = seq(_stringOpt(e, 'last_message_id'));
    if (id.isEmpty || first == null || last == null) continue;
    final title = _stringOpt(e, 'title') ?? 'Episode ${_int(e, 'ordinal')}';
    episodes.add(
      ContextEpisode(
        id: id,
        ordinal: _int(e, 'ordinal'),
        title: title,
        firstSeq: first,
        lastSeq: last,
        sourceTokens: _int(e, 'source_tokens'),
        chapterId: _string(e, 'chapter_id'),
        summaryId: episodeSummaryId(id),
      ),
    );
    summaries.add(
      ContextSummary(
        id: episodeSummaryId(id),
        kind: ContextSummaryKind.episode,
        title: title,
        firstSeq: first,
        lastSeq: last,
        messageCount: last - first + 1,
        episodeIds: [id],
        chapterId: _stringOpt(e, 'chapter_id'),
        sourceTokens: _int(e, 'source_tokens'),
        summaryTokens: _int(e, 'summary_tokens'),
        createdAt: writtenAt(id, ContextEventKind.episodeWritten) ?? _epoch,
        applied: appliedIds.contains(id),
      ),
    );
  }

  final chapters = <ContextChapter>[];
  for (final c in chapterWires) {
    final id = _string(c, 'id');
    final first = seq(_stringOpt(c, 'first_message_id'));
    final last = seq(_stringOpt(c, 'last_message_id'));
    if (id.isEmpty || first == null) continue;
    final closed = c['status'] == 'closed';
    final hasSummary = closed && _int(c, 'summary_tokens') > 0;
    final title = _stringOpt(c, 'title') ?? 'Chapter ${_int(c, 'ordinal')}';
    chapters.add(
      ContextChapter(
        id: id,
        ordinal: _int(c, 'ordinal'),
        title: title,
        firstSeq: first,
        lastSeq: closed ? last : null,
        sourceTokens: closed ? _intOpt(c, 'source_tokens') : null,
        status: closed ? ContextStatus.closed : ContextStatus.open,
        summaryId: hasSummary ? chapterSummaryId(id) : null,
      ),
    );
    if (hasSummary && last != null) {
      summaries.add(
        ContextSummary(
          id: chapterSummaryId(id),
          kind: ContextSummaryKind.chapter,
          title: title,
          firstSeq: first,
          lastSeq: last,
          messageCount: last - first + 1,
          episodeIds: [
            for (final e in episodeWires)
              if (e['chapter_id'] == id) _string(e, 'id'),
          ],
          sourceTokens: _int(c, 'source_tokens'),
          summaryTokens: _int(c, 'summary_tokens'),
          createdAt: writtenAt(id, ContextEventKind.chapterClosed) ?? _epoch,
          closed: true,
          applied: appliedIds.contains(id),
        ),
      );
    }
  }
  // Legacy chapters carry summaries of the older strategy; their source size
  // is unknown to the host.
  for (final c in legacyWires) {
    final id = _string(c, 'id');
    final first = seq(_stringOpt(c, 'first_message_id'));
    final last = seq(_stringOpt(c, 'last_message_id'));
    if (id.isEmpty || first == null || last == null) continue;
    final title = _stringOpt(c, 'title') ?? 'Chapter ${_int(c, 'ordinal')}';
    chapters.add(
      ContextChapter(
        id: id,
        ordinal: _int(c, 'ordinal'),
        title: title,
        firstSeq: first,
        lastSeq: last,
        summaryId: chapterSummaryId(id),
      ),
    );
    summaries.add(
      ContextSummary(
        id: chapterSummaryId(id),
        kind: ContextSummaryKind.chapter,
        title: title,
        firstSeq: first,
        lastSeq: last,
        messageCount: last - first + 1,
        sourceTokens: 0,
        summaryTokens: _int(c, 'summary_tokens'),
        createdAt: _epoch,
        closed: true,
        applied: appliedIds.contains(id),
      ),
    );
  }

  final contextEvents = <ContextEvent>[];
  for (final event in events) {
    final kind = _eventKind(event['kind']);
    final id = _stringOpt(event, 'id');
    final first = seq(_stringOpt(event, 'first_message_id'));
    final last = seq(_stringOpt(event, 'last_message_id'));
    if (kind == null || id == null || first == null || last == null) continue;
    final episodeIds = (event['episode_ids'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    final summary = _stringOpt(event, 'summary_id');
    contextEvents.add(
      ContextEvent(
        id: id,
        kind: kind,
        at: _time(event['created_at']) ?? _epoch,
        trigger: _trigger(event['trigger']),
        triggerText: _stringOpt(event, 'trigger_text'),
        firstSeq: first,
        lastSeq: last,
        episodeIds: episodeIds,
        tokensBefore:
            _intOpt(event, 'tokens_before') ??
            episodeIds.fold<int>(0, (n, e) => n + (episodeSource[e] ?? 0)),
        tokensAfter: _int(event, 'tokens_after'),
        inputBefore: _intOpt(event, 'input_before'),
        inputAfter: _intOpt(event, 'input_after'),
        summaryId: summary == null
            ? null
            : kind == ContextEventKind.chapterClosed ||
                  chapterIds.contains(summary)
            ? chapterSummaryId(summary)
            : episodeSummaryId(summary),
      ),
    );
  }
  return ContextDetails(
    chapters: chapters,
    episodes: episodes,
    summaries: summaries,
    events: contextEvents,
  );
}

HistoryRole _role(Object? role) => switch (role) {
  'user' => HistoryRole.user,
  'tool' => HistoryRole.tool,
  _ => HistoryRole.agent,
};

String _preview(Wire message) {
  var text = _string(message, 'content');
  if (text.trim().isEmpty) {
    final calls = [
      for (final call in _maps(message['tool_calls'])) _string(call, 'name'),
    ].where((name) => name.isNotEmpty);
    if (calls.isNotEmpty) text = 'Tool call: ${calls.join(', ')}';
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 160 ? text : '${text.substring(0, 159)}…';
}

/// One `history.range` row. System messages read as agent lines: the kit has
/// no system role.
HistoryMessage historyMessage(Wire row) {
  final message = _map(row['message']);
  return HistoryMessage(
    seq: _int(row, 'seq'),
    role: _role(message['role']),
    preview: _preview(message),
    tokens: _intOpt(row, 'tokens'),
  );
}

/// A child session as the parent's crew entry, from the child's
/// `session.state`.
///
/// The task is the child's first user message (its title when none). A child
/// whose last run finished reads as done with its last reply as the result;
/// a pending question makes it wait for an answer. An interrupted run reads
/// as cancelled: it ended without finishing.
ChildAgent childAgent(Wire state) {
  final session = _map(state['session']);
  final id = _string(session, 'id');
  final messages = _maps(state['messages']);
  String? task;
  String? reply;
  var toolCalls = 0;
  for (final message in messages) {
    final content = _string(message, 'content');
    if (message['role'] == 'user' && task == null && content.isNotEmpty) {
      task = content;
    } else if (message['role'] == 'assistant') {
      toolCalls += _maps(message['tool_calls']).length;
      if (content.isNotEmpty) reply = content;
    }
  }
  final runs = _maps(state['runs'])
    ..sort(
      (a, b) => _string(a, 'started_at').compareTo(_string(b, 'started_at')),
    );
  final last = runs.isEmpty ? null : runs.last;
  final status = last == null ? null : last['status'];
  var workState = switch (status) {
    'completed' => WorkState.done,
    'failed' => WorkState.failed,
    'cancelled' || 'interrupted' => WorkState.cancelled,
    'running' || 'waiting_for_quota' => WorkState.running,
    _ => WorkState.idle,
  };
  final question = childQuestion(id, state['question']);
  final pending = question != null && question.isPending ? question : null;
  if (pending != null && !workState.isEnded) {
    workState = WorkState.waitingForAnswer;
  }
  return ChildAgent(
    id: id,
    task: task ?? _string(session, 'title'),
    state: workState,
    toolCalls: toolCalls,
    startedAt: runs.isEmpty ? null : _time(runs.first['started_at']),
    endedAt: workState.isEnded && last != null ? _time(last['ended_at']) : null,
    result: workState == WorkState.done ? reply : null,
    pendingQuestion: workState.isEnded ? null : pending,
  );
}

/// A child's question, from its session state or from a parent's
/// `child_question` / `child_question_answer` value; null without one.
ChildQuestion? childQuestion(String childId, Object? value) {
  if (value is! Map<String, Object?>) return null;
  final wire = _map(value);
  final id = _stringOpt(wire, 'id');
  if (id == null) return null;
  final status = wire['status'];
  return ChildQuestion(
    id: id,
    childId: childId,
    text: _string(wire, 'text'),
    options: (wire['options'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList(),
    // An older question has no time; the epoch stands for unknown.
    askedAt: _time(wire['asked_at']) ?? _epoch,
    state: status == 'answered'
        ? ChildQuestionState.answered
        : status == 'cancelled'
        ? ChildQuestionState.cancelled
        : ChildQuestionState.pending,
    answer: _stringOpt(wire, 'answer'),
    answeredBy: switch (wire['answered_by']) {
      'user' => AnsweredBy.user,
      'parent' => AnsweredBy.parent,
      // An answer without an author predates the field: a parent answer.
      _ when status == 'answered' => AnsweredBy.parent,
      _ => null,
    },
  );
}

/// The child a parent event refers to, or null for other events.
String? childOfEvent(Wire event) {
  switch (event['type']) {
    case 'child_run_state_changed':
      return _stringOpt(event, 'child_session_id');
    case 'host_state_changed':
      final key = event['key'];
      if (key == 'child_question' || key == 'child_question_answer') {
        return _stringOpt(_map(event['value']), 'child_session_id');
      }
  }
  return null;
}
