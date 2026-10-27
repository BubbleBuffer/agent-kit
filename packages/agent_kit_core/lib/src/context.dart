/// The context view: what the agent currently remembers, what was
/// compacted, and the original history behind it.
///
/// BubblePaw's context manager (LCM) keeps the original history and serves
/// the model a prefix of summaries plus the recent messages as written. The
/// current *serving view* is part of the chat snapshot (`ChatSnapshot.context`,
/// a [ContextView]); the structure behind it (episodes, chapters, summaries,
/// events) and the original messages are loaded on demand (`loadContext`,
/// `loadSummary`, `loadHistoryRange`), behind the `context` capability.
///
/// Fields a host does not record today are nullable, and widgets hide what
/// is null: the trigger of an event, the input size before and after an
/// apply, and the token size of a block or of a message.
library;

import 'value.dart';

/// What one block of the serving view is, in the order the model receives
/// them.
enum ContextBlockKind {
  /// Instructions, tools and the first request: sent every time.
  opening,

  /// The chapter index (named `memoryIndex` because `index` is an enum member).
  memoryIndex,

  /// The steering anchors: the first and the latest typed request, as
  /// written.
  anchors,

  /// A summary of a closed chapter.
  chapterSummary,

  /// A summary of an episode of the open chapter.
  episodeSummary,

  /// The recent messages, exactly as written.
  rawSuffix,
}

/// One block of the serving view.
final class ContextBlock extends KitValue {
  /// Creates a block.
  const ContextBlock({
    required this.kind,
    this.tokens,
    this.summaryId,
    this.firstSeq,
    this.lastSeq,
    this.messageCount,
    this.title,
  });

  /// Reads a block from JSON.
  factory ContextBlock.fromJson(Json j) => ContextBlock(
    kind: j.enumOf('kind', ContextBlockKind.values, ContextBlockKind.opening),
    tokens: j.intOpt('tokens'),
    summaryId: j.strOpt('summaryId'),
    firstSeq: j.intOpt('firstSeq'),
    lastSeq: j.intOpt('lastSeq'),
    messageCount: j.intOpt('messageCount'),
    title: j.strOpt('title'),
  );

  /// What the block is.
  final ContextBlockKind kind;

  /// Its size in tokens; null when the host does not record it (the frozen
  /// view keeps pointers, not sizes).
  final int? tokens;

  /// The summary it holds, for a summary block.
  final String? summaryId;

  /// First message sequence it covers or holds.
  final int? firstSeq;

  /// Last message sequence it covers or holds.
  final int? lastSeq;

  /// Number of messages it covers or holds.
  final int? messageCount;

  /// A title, such as the summary's.
  final String? title;

  @override
  Json toJson() => compact({
    'kind': kind.name,
    'tokens': tokens,
    'summaryId': summaryId,
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'messageCount': messageCount,
    'title': title,
  });
}

/// The serving view: the blocks the model is sent, and the limits that
/// shape them.
///
/// [window] is the context window, [applyCap] the input size at which a
/// ready compaction is applied ("Compacts near 84k"), and [responseReserve]
/// what is kept free for the reply (`window - responseReserve` is the cap).
final class ContextView extends KitValue {
  /// Creates a view.
  ContextView({
    required this.window,
    required this.applyCap,
    required this.responseReserve,
    List<ContextBlock> blocks = const [],
    List<String> pendingEpisodeIds = const [],
    this.appliedAt,
  }) : blocks = List.unmodifiable(blocks),
       pendingEpisodeIds = List.unmodifiable(pendingEpisodeIds);

  /// Reads a view from JSON.
  factory ContextView.fromJson(Json j) => ContextView(
    window: j.integer('window'),
    applyCap: j.integer('applyCap'),
    responseReserve: j.integer('responseReserve'),
    blocks: j.listOf('blocks', ContextBlock.fromJson),
    pendingEpisodeIds: j.strings('pendingEpisodeIds'),
    appliedAt: j.timeOpt('appliedAt'),
  );

  /// The context window in tokens.
  final int window;

  /// The input size near which a compaction is applied.
  final int applyCap;

  /// Tokens kept free for the response.
  final int responseReserve;

  /// The blocks, in the order the model receives them.
  final List<ContextBlock> blocks;

  /// Episodes whose summary is ready but not in the view yet.
  final List<String> pendingEpisodeIds;

  /// When the last compaction was applied.
  final DateTime? appliedAt;

  /// The blocks of [kind], in order.
  Iterable<ContextBlock> ofKind(ContextBlockKind kind) =>
      blocks.where((b) => b.kind == kind);

  /// The total of the blocks' tokens, or null when any block's size is
  /// unknown (a sum with a hole would be a guess).
  int? get totalTokens {
    if (blocks.isEmpty) return null;
    var total = 0;
    for (final b in blocks) {
      final t = b.tokens;
      if (t == null) return null;
      total += t;
    }
    return total;
  }

  /// The tokens of the fixed part (the opening), or null when unknown.
  int? get openingTokens => _sum({ContextBlockKind.opening});

  /// The tokens of the compacted memory (index, anchors and summaries), or
  /// null when any is unknown.
  int? get memoryTokens => _sum({
    ContextBlockKind.memoryIndex,
    ContextBlockKind.anchors,
    ContextBlockKind.chapterSummary,
    ContextBlockKind.episodeSummary,
  });

  /// The tokens of the live messages, or null when unknown.
  int? get liveTokens => _sum({ContextBlockKind.rawSuffix});

  int? _sum(Set<ContextBlockKind> kinds) {
    var total = 0;
    var any = false;
    for (final b in blocks) {
      if (!kinds.contains(b.kind)) continue;
      final t = b.tokens;
      if (t == null) return null;
      total += t;
      any = true;
    }
    return any ? total : null;
  }

  @override
  Json toJson() => compact({
    'window': window,
    'applyCap': applyCap,
    'responseReserve': responseReserve,
    'blocks': jsonList(blocks),
    'pendingEpisodeIds': pendingEpisodeIds.isEmpty ? null : pendingEpisodeIds,
    'appliedAt': timeJson(appliedAt),
  });
}

/// Whether a chapter or an episode can still grow.
enum ContextStatus {
  /// Still being written (the open chapter, an episode in progress).
  open,

  /// Finished; a closed chapter's summary is written once and frozen.
  closed,
}

/// A run of messages that was (or will be) summarized as one unit.
final class ContextEpisode extends KitValue {
  /// Creates an episode.
  const ContextEpisode({
    required this.id,
    required this.ordinal,
    required this.title,
    required this.firstSeq,
    required this.lastSeq,
    required this.sourceTokens,
    required this.chapterId,
    this.status = ContextStatus.closed,
    this.summaryId,
  });

  /// Reads an episode from JSON.
  factory ContextEpisode.fromJson(Json j) => ContextEpisode(
    id: j.str('id'),
    ordinal: j.integer('ordinal'),
    title: j.str('title'),
    firstSeq: j.integer('firstSeq'),
    lastSeq: j.integer('lastSeq'),
    sourceTokens: j.integer('sourceTokens'),
    chapterId: j.str('chapterId'),
    status: j.enumOf('status', ContextStatus.values, ContextStatus.closed),
    summaryId: j.strOpt('summaryId'),
  );

  /// The episode's id.
  final String id;

  /// Its number in the chat, from 1 (shown as `E1`).
  final int ordinal;

  /// A short title.
  final String title;

  /// First message it covers.
  final int firstSeq;

  /// Last message it covers.
  final int lastSeq;

  /// The size of the original messages in tokens.
  final int sourceTokens;

  /// The chapter it belongs to.
  final String chapterId;

  /// Open or closed.
  final ContextStatus status;

  /// Its own summary, once written.
  final String? summaryId;

  /// Number of messages it covers.
  int get messageCount => lastSeq - firstSeq + 1;

  @override
  Json toJson() => compact({
    'id': id,
    'ordinal': ordinal,
    'title': title,
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'sourceTokens': sourceTokens,
    'chapterId': chapterId,
    'status': status.name,
    'summaryId': summaryId,
  });
}

/// A group of episodes about one subject. A closed chapter gets one summary
/// that replaces its episodes' summaries.
final class ContextChapter extends KitValue {
  /// Creates a chapter.
  const ContextChapter({
    required this.id,
    required this.ordinal,
    required this.title,
    required this.firstSeq,
    this.lastSeq,
    this.sourceTokens,
    this.status = ContextStatus.closed,
    this.summaryId,
  });

  /// Reads a chapter from JSON.
  factory ContextChapter.fromJson(Json j) => ContextChapter(
    id: j.str('id'),
    ordinal: j.integer('ordinal'),
    title: j.str('title'),
    firstSeq: j.integer('firstSeq'),
    lastSeq: j.intOpt('lastSeq'),
    sourceTokens: j.intOpt('sourceTokens'),
    status: j.enumOf('status', ContextStatus.values, ContextStatus.closed),
    summaryId: j.strOpt('summaryId'),
  );

  /// The chapter's id.
  final String id;

  /// Its number in the chat, from 1.
  final int ordinal;

  /// A short title.
  final String title;

  /// First message it covers.
  final int firstSeq;

  /// Last message it covers; null while the chapter is open.
  final int? lastSeq;

  /// The size of its original messages; null while open.
  final int? sourceTokens;

  /// Open or closed.
  final ContextStatus status;

  /// Its summary, once closed and written.
  final String? summaryId;

  @override
  Json toJson() => compact({
    'id': id,
    'ordinal': ordinal,
    'title': title,
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'sourceTokens': sourceTokens,
    'status': status.name,
    'summaryId': summaryId,
  });
}

/// Whether a summary covers a chapter or an episode.
enum ContextSummaryKind {
  /// A closed chapter's summary.
  chapter,

  /// An episode's summary.
  episode,
}

/// A written summary and where it stands.
final class ContextSummary extends KitValue {
  /// Creates a summary.
  ContextSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.firstSeq,
    required this.lastSeq,
    required this.messageCount,
    required this.sourceTokens,
    required this.summaryTokens,
    required this.createdAt,
    this.text = '',
    List<String> episodeIds = const [],
    this.chapterId,
    this.model,
    this.closed = false,
    this.applied = false,
  }) : episodeIds = List.unmodifiable(episodeIds);

  /// Reads a summary from JSON.
  factory ContextSummary.fromJson(Json j) => ContextSummary(
    id: j.str('id'),
    kind: j.enumOf(
      'kind',
      ContextSummaryKind.values,
      ContextSummaryKind.episode,
    ),
    title: j.str('title'),
    text: j.strOpt('text') ?? '',
    firstSeq: j.integer('firstSeq'),
    lastSeq: j.integer('lastSeq'),
    messageCount: j.integer('messageCount'),
    episodeIds: j.strings('episodeIds'),
    chapterId: j.strOpt('chapterId'),
    sourceTokens: j.integer('sourceTokens'),
    summaryTokens: j.integer('summaryTokens'),
    createdAt: j.time('createdAt'),
    model: j.strOpt('model'),
    closed: j.boolean('closed'),
    applied: j.boolean('applied'),
  );

  /// The summary's id.
  final String id;

  /// Chapter or episode.
  final ContextSummaryKind kind;

  /// A short title.
  final String title;

  /// The summary, as markdown. A list from `loadContext` may leave it empty;
  /// `loadSummary` returns the whole text.
  final String text;

  /// First message it covers.
  final int firstSeq;

  /// Last message it covers.
  final int lastSeq;

  /// Number of messages it covers.
  final int messageCount;

  /// The episodes it covers.
  final List<String> episodeIds;

  /// The chapter it belongs to.
  final String? chapterId;

  /// The size of the original messages in tokens.
  final int sourceTokens;

  /// The size of the summary in tokens.
  final int summaryTokens;

  /// When it was written.
  final DateTime createdAt;

  /// The model that wrote it.
  final String? model;

  /// Whether it is closed and frozen (a closed chapter's summary).
  final bool closed;

  /// Whether it is in the serving view now.
  final bool applied;

  /// Tokens saved by using the summary instead of the originals.
  int get savedTokens => sourceTokens - summaryTokens;

  @override
  Json toJson() => compact({
    'id': id,
    'kind': kind.name,
    'title': title,
    'text': text.isEmpty ? null : text,
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'messageCount': messageCount,
    'episodeIds': episodeIds.isEmpty ? null : episodeIds,
    'chapterId': chapterId,
    'sourceTokens': sourceTokens,
    'summaryTokens': summaryTokens,
    'createdAt': timeJson(createdAt),
    'model': model,
    'closed': closed ? true : null,
    'applied': applied ? true : null,
  });
}

/// What started a summary or a compaction. A host that does not record the
/// trigger leaves `ContextEvent.trigger` null.
enum ContextTrigger {
  /// The input neared the apply cap.
  pressure,

  /// A short episode was gathered early to make room.
  emergency,

  /// An episode reached the source-size target.
  sourceSize,

  /// The subject changed, which closed a chapter.
  subjectChange,

  /// The user asked.
  manual,

  /// The host recorded a trigger this kit does not know.
  unknown,
}

/// What a [ContextEvent] records. Gathering and applying are separate: a
/// summary being written never changes the serving view by itself.
enum ContextEventKind {
  /// An episode summary was written.
  episodeWritten,

  /// A chapter was closed and its summary written.
  chapterClosed,

  /// A compaction was applied: the serving view changed.
  applied,
}

/// One entry of the compaction timeline.
final class ContextEvent extends KitValue {
  /// Creates an event.
  ContextEvent({
    required this.id,
    required this.kind,
    required this.at,
    required this.firstSeq,
    required this.lastSeq,
    required this.tokensBefore,
    required this.tokensAfter,
    this.trigger,
    this.triggerText,
    List<String> episodeIds = const [],
    this.inputBefore,
    this.inputAfter,
    this.summaryId,
  }) : episodeIds = List.unmodifiable(episodeIds);

  /// Reads an event from JSON.
  factory ContextEvent.fromJson(Json j) => ContextEvent(
    id: j.str('id'),
    kind: j.enumOf(
      'kind',
      ContextEventKind.values,
      ContextEventKind.episodeWritten,
    ),
    at: j.time('at'),
    trigger: j['trigger'] == null
        ? null
        : j.enumOf('trigger', ContextTrigger.values, ContextTrigger.unknown),
    triggerText: j.strOpt('triggerText'),
    firstSeq: j.integer('firstSeq'),
    lastSeq: j.integer('lastSeq'),
    episodeIds: j.strings('episodeIds'),
    tokensBefore: j.integer('tokensBefore'),
    tokensAfter: j.integer('tokensAfter'),
    inputBefore: j.intOpt('inputBefore'),
    inputAfter: j.intOpt('inputAfter'),
    summaryId: j.strOpt('summaryId'),
  );

  /// The event's id.
  final String id;

  /// Episode written, chapter closed or applied.
  final ContextEventKind kind;

  /// When it happened.
  final DateTime at;

  /// Why it happened; null when the host does not record it. An unknown
  /// value reads as [ContextTrigger.unknown].
  final ContextTrigger? trigger;

  /// The trigger in words, such as "input reached 80.6k, near the 84k cap".
  final String? triggerText;

  /// First message the event covers.
  final int firstSeq;

  /// Last message the event covers.
  final int lastSeq;

  /// The episodes it covers.
  final List<String> episodeIds;

  /// The covered originals' size.
  final int tokensBefore;

  /// The size of what replaces them.
  final int tokensAfter;

  /// The request's input size before the apply; applied events only, and
  /// null when the host does not record it.
  final int? inputBefore;

  /// The request's input size after the apply; applied events only, and null
  /// when the host does not record it.
  final int? inputAfter;

  /// The summary it concerns, such as the one the apply put in the view.
  final String? summaryId;

  @override
  Json toJson() => compact({
    'id': id,
    'kind': kind.name,
    'at': timeJson(at),
    'trigger': trigger?.name,
    'triggerText': triggerText,
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'episodeIds': episodeIds.isEmpty ? null : episodeIds,
    'tokensBefore': tokensBefore,
    'tokensAfter': tokensAfter,
    'inputBefore': inputBefore,
    'inputAfter': inputAfter,
    'summaryId': summaryId,
  });
}

/// The structure behind the serving view, as `loadContext` returns it.
final class ContextDetails extends KitValue {
  /// Creates the details.
  ContextDetails({
    List<ContextChapter> chapters = const [],
    List<ContextEpisode> episodes = const [],
    List<ContextSummary> summaries = const [],
    List<ContextEvent> events = const [],
  }) : chapters = List.unmodifiable(chapters),
       episodes = List.unmodifiable(episodes),
       summaries = List.unmodifiable(summaries),
       events = List.unmodifiable(events);

  /// Reads details from JSON.
  factory ContextDetails.fromJson(Json j) => ContextDetails(
    chapters: j.listOf('chapters', ContextChapter.fromJson),
    episodes: j.listOf('episodes', ContextEpisode.fromJson),
    summaries: j.listOf('summaries', ContextSummary.fromJson),
    events: j.listOf('events', ContextEvent.fromJson),
  );

  /// The chapters, oldest first.
  final List<ContextChapter> chapters;

  /// The episodes, oldest first.
  final List<ContextEpisode> episodes;

  /// The written summaries.
  final List<ContextSummary> summaries;

  /// The timeline, oldest first (widgets show it newest first).
  final List<ContextEvent> events;

  /// The summary with [id], or null.
  ContextSummary? summary(String id) {
    for (final s in summaries) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The episode with [id], or null.
  ContextEpisode? episode(String id) {
    for (final e in episodes) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The chapter with [id], or null.
  ContextChapter? chapter(String id) {
    for (final c in chapters) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Json toJson() => {
    'chapters': jsonList(chapters),
    'episodes': jsonList(episodes),
    'summaries': jsonList(summaries),
    'events': jsonList(events),
  };
}

/// Who wrote a [HistoryMessage].
enum HistoryRole {
  /// The user.
  user,

  /// The agent.
  agent,

  /// A tool call or its result.
  tool,
}

/// One line of the original history.
final class HistoryMessage extends KitValue {
  /// Creates a message.
  const HistoryMessage({
    required this.seq,
    required this.role,
    required this.preview,
    this.tokens,
  });

  /// Reads a message from JSON.
  factory HistoryMessage.fromJson(Json j) => HistoryMessage(
    seq: j.integer('seq'),
    role: j.enumOf('role', HistoryRole.values, HistoryRole.agent),
    preview: j.str('preview'),
    tokens: j.intOpt('tokens'),
  );

  /// The message's sequence number.
  final int seq;

  /// Who wrote it.
  final HistoryRole role;

  /// A one-line preview of its text.
  final String preview;

  /// Its size in tokens; null when the host does not record it.
  final int? tokens;

  @override
  Json toJson() => compact({
    'seq': seq,
    'role': role.name,
    'preview': preview,
    'tokens': tokens,
  });
}

/// A range of the original history, as `loadHistoryRange` returns it.
final class HistoryPage extends KitValue {
  /// Creates a page.
  HistoryPage({
    required this.firstSeq,
    required this.lastSeq,
    List<HistoryMessage> messages = const [],
  }) : messages = List.unmodifiable(messages);

  /// Reads a page from JSON.
  factory HistoryPage.fromJson(Json j) => HistoryPage(
    firstSeq: j.integer('firstSeq'),
    lastSeq: j.integer('lastSeq'),
    messages: j.listOf('messages', HistoryMessage.fromJson),
  );

  /// The first sequence asked for.
  final int firstSeq;

  /// The last sequence asked for.
  final int lastSeq;

  /// The messages in the range, in order. A message the host does not have
  /// is skipped.
  final List<HistoryMessage> messages;

  @override
  Json toJson() => {
    'firstSeq': firstSeq,
    'lastSeq': lastSeq,
    'messages': jsonList(messages),
  };
}
