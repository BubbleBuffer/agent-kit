/// Keeps one chat's snapshot current from a backend.
library;

import 'dart:async';

import 'backend.dart';
import 'events.dart';
import 'reducer.dart';
import 'snapshot.dart';

/// Loads a chat, follows its events and folds them in with [reduce].
///
/// On a `gap` the snapshot is marked stale at once and reloaded with
/// `loadChat`; events that arrive while the reload is in flight are
/// buffered and folded into the new snapshot (the reducer drops the ones
/// it already holds). When the event stream ends, the snapshot is marked
/// stale and stays so until [reload].
final class ChatFeed {
  /// Creates a feed; call [start] to load.
  ChatFeed(this.reader, this.chatId);

  /// The read port followed by this feed.
  final ChatReader reader;

  /// The original write-capable backend, for existing callers.
  ///
  /// Throws [StateError] when this feed was constructed with a read-only
  /// [ChatReader]. Consumers of read-only feeds use [reader].
  AgentBackend get backend {
    final source = reader;
    if (source is AgentBackend) return source;
    throw StateError('This feed has a read-only ChatReader. Use reader.');
  }

  /// The chat followed.
  final String chatId;

  final _controller = StreamController<ChatSnapshot>.broadcast();
  StreamSubscription<KitEvent>? _sub;
  ChatSnapshot? _snapshot;
  List<KitEvent>? _buffer;
  bool _closed = false;

  /// The current snapshot, null before the first load completes.
  ChatSnapshot? get snapshot => _snapshot;

  /// Every new snapshot, as it changes. Load failures arrive as errors
  /// ([KitError]).
  Stream<ChatSnapshot> get snapshots => _controller.stream;

  /// Loads the chat and subscribes to its events.
  Future<ChatSnapshot> start() => reload();

  /// Reloads the snapshot and resubscribes.
  Future<ChatSnapshot> reload() async {
    await _sub?.cancel();
    _sub = null;
    final snap = await reader.loadChat(chatId);
    if (_closed) return snap;
    _set(snap);
    _sub = reader
        .events(chatId, after: snap.seq)
        .listen(_onEvent, onError: _onError, onDone: _onDone);
    return snap;
  }

  /// Stops following the chat.
  Future<void> close() async {
    _closed = true;
    await _sub?.cancel();
    await _controller.close();
  }

  void _onEvent(KitEvent event) {
    final buffer = _buffer;
    if (buffer != null) {
      if (event is! GapEvent) buffer.add(event);
      return;
    }
    final current = _snapshot;
    if (current == null) return;
    _set(reduce(current, event));
    if (event is GapEvent && event.chat == chatId) unawaited(_reloadAfterGap());
  }

  Future<void> _reloadAfterGap() async {
    _buffer = [];
    try {
      var snap = await reader.loadChat(chatId);
      for (final e in _buffer ?? const <KitEvent>[]) {
        snap = reduce(snap, e);
      }
      if (!_closed) _set(snap);
    } catch (error, stack) {
      if (!_closed) _controller.addError(error, stack);
    } finally {
      _buffer = null;
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (!_closed) _controller.addError(error, stack);
  }

  void _onDone() {
    final current = _snapshot;
    if (_closed || current == null) return;
    _set(current.stale ? current : current.copyWith(stale: true));
  }

  void _set(ChatSnapshot next) {
    if (identical(next, _snapshot)) return;
    _snapshot = next;
    if (!_closed) _controller.add(next);
  }
}
