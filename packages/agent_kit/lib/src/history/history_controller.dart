// The fold state of the history cards, owned by the host so it outlives the
// rows (a list builds rows lazily and drops them when they scroll away).

import 'package:flutter/foundation.dart';

/// What an episode card shows below its header.
enum HistoryEpisodeView {
  /// Only the header, title and gist.
  closed,

  /// The action log.
  log,

  /// The original messages.
  messages,
}

class HistoryController extends ChangeNotifier {
  final Set<String> _chapters = {};
  final Map<String, HistoryEpisodeView> _episodes = {};
  final Set<String> _more = {};

  /// Whether the chapter card [key] (`HistoryChapter.key`) shows its episodes.
  bool chapterOpen(String key) => _chapters.contains(key);

  void setChapterOpen(String key, bool open) {
    if (open ? _chapters.add(key) : _chapters.remove(key)) notifyListeners();
  }

  void toggleChapter(String key) => setChapterOpen(key, !chapterOpen(key));

  HistoryEpisodeView episodeView(String id) =>
      _episodes[id] ?? HistoryEpisodeView.closed;

  void setEpisodeView(String id, HistoryEpisodeView view) {
    if (episodeView(id) == view) return;
    if (view == HistoryEpisodeView.closed) {
      _episodes.remove(id);
    } else {
      _episodes[id] = view;
    }
    notifyListeners();
  }

  /// The header toggles between closed and the log.
  void toggleEpisode(String id) => setEpisodeView(
    id,
    episodeView(id) == HistoryEpisodeView.closed
        ? HistoryEpisodeView.log
        : HistoryEpisodeView.closed,
  );

  /// Whether the action log of [id] shows all its rows (past the first six).
  bool moreShown(String id) => _more.contains(id);

  void showMore(String id) {
    if (_more.add(id)) notifyListeners();
  }
}
