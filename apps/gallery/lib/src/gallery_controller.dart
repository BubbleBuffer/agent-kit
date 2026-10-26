// The gallery's state: the scene, theme and width, and a chat that plays the
// "Quota bar flickers on reconnect" script on FakeAgentBackend's scripted
// backend, followed through a ChatFeed.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';

import '../components/workspace.dart';
import 'scenes.dart';

/// Width limits of the gallery's width control.
const minGalleryWidth = 360.0;
const maxGalleryWidth = 1600.0;

/// Holds what the toolbar changes and the chat the scenes show.
///
/// The default clock is a [ManualClock] that [start] plays to the end, so
/// the scenes open on the mockups' mid-task state (waiting for approval).
/// "Replay" starts over and the toolbar steps the clock. Pass a
/// `SystemClock` to play the script in real time instead.
class GalleryController extends ChangeNotifier {
  GalleryController({KitClock Function()? clock, this.autoPlay = true})
    : _newClock = clock ?? (() => ManualClock(DateTime.utc(2025, 12, 29, 10)));

  final KitClock Function() _newClock;

  /// Whether [start] and [replay] play a manual clock to the end.
  final bool autoPlay;

  GalleryScene _scene = GalleryScene.workbench;
  Brightness _brightness = Brightness.light;
  double _width = GalleryScene.workbench.presetWidth;

  late KitClock _clock = _newClock();
  ScriptedBackend? _backend;
  ChatFeed? _feed;
  StreamSubscription<ChatSnapshot>? _sub;

  GalleryScene get scene => _scene;
  Brightness get brightness => _brightness;
  double get width => _width;

  /// The followed chat's current snapshot, null before [start] completes.
  ChatSnapshot? get snapshot => _feed?.snapshot;

  /// The chat the compositions open first.
  String get chatId => quotaChatId;

  /// The time the scenes show: the script clock's, so "waiting 12m" holds.
  DateTime get now => _clock.now();

  /// The split tree of scene D, rebuilt on every start.
  WorkspaceController get workspaceController => _workspace;
  late WorkspaceController _workspace = WorkspaceController(
    galleryWorkspaceLayout(),
  );

  /// The backend (for commands from scenes).
  AgentBackend? get backend => _backend;

  /// Whether the clock can be stepped by hand.
  bool get steppable => _clock is ManualClock;

  /// Shows [scene] at its preset width (the width of its mockup shot).
  void selectScene(GalleryScene scene) {
    _scene = scene;
    _width = scene.presetWidth;
    notifyListeners();
  }

  void toggleBrightness() {
    _brightness = _brightness == Brightness.light
        ? Brightness.dark
        : Brightness.light;
    notifyListeners();
  }

  set brightness(Brightness value) {
    _brightness = value;
    notifyListeners();
  }

  set width(double value) {
    _width = value.clamp(minGalleryWidth, maxGalleryWidth);
    notifyListeners();
  }

  /// Creates the backend and the feed, and (with [autoPlay]) plays the script
  /// to its end.
  Future<void> start() async {
    await _sub?.cancel();
    await _feed?.close();
    _clock = _newClock();
    _workspace = WorkspaceController(galleryWorkspaceLayout());
    final backend = ScriptedBackend(
      scripts: [quotaReconnectScript()],
      clock: _clock,
      models: const [
        KitChoice(id: 'deepseek-v4.1-flash', label: 'DeepSeek V4.1 Flash'),
        KitChoice(id: 'claude-haiku-5.5', label: 'Haiku 5.5'),
      ],
      profiles: const [
        KitChoice(id: 'bubblepaw', label: 'bubblepaw'),
        KitChoice(id: 'scratch', label: 'scratch'),
      ],
    );
    _backend = backend;
    await _seedEarlier(backend);
    final feed = ChatFeed(backend, quotaChatId);
    _feed = feed;
    _sub = feed.snapshots.listen((_) => notifyListeners());
    await feed.start();
    unawaited(backend.play());
    final clock = _clock;
    if (clock is ManualClock) {
      await clock.advance(Duration.zero);
      if (autoPlay) {
        await playToEnd();
        await _seedToday(backend);
      }
    }
    notifyListeners();
  }

  // The rail's older sessions, stamped on earlier days of the manual clock.
  Future<void> _seedEarlier(ScriptedBackend b) async {
    final clock = _clock;
    if (clock is! ManualClock) return;
    _chat(b, 'sess-grouping', 'Session list grouping');
    await clock.advance(const Duration(days: 2, hours: 5));
    _chat(b, 'sess-retention', 'Child worktree retention');
    await clock.advance(const Duration(hours: 3));
    _chat(b, 'sess-wal', 'SQLite WAL growth on long runs', failed: true);
    await clock.advance(const Duration(hours: 17));
  }

  // Today's other sessions, after the quota chat has played.
  Future<void> _seedToday(ScriptedBackend b) async {
    final clock = _clock;
    if (clock is! ManualClock) return;
    _chat(b, 'sess-compact', 'Compact before fork');
    await clock.advance(const Duration(minutes: 12));
    b.emit('sess-steer', {
      'kind': 'chat.renamed',
      'title': 'Steer vs queue semantics',
    });
    b.emit('sess-steer', {'kind': 'run.started', 'runId': 'run-steer'});
    for (final (id, task) in const [
      ('s1', 'Read the steering code'),
      ('s2', 'Read the queue code'),
      ('s3', 'Compare the two'),
    ]) {
      b.emit('sess-steer', {
        'kind': 'child.spawned',
        'childId': id,
        'task': task,
        'runId': 'run-steer',
      });
    }
  }

  void _chat(
    ScriptedBackend b,
    String id,
    String title, {
    bool failed = false,
  }) {
    b.emit(id, {'kind': 'chat.renamed', 'title': title});
    b.emit(id, {'kind': 'run.started', 'runId': 'run-$id'});
    b.emit(id, {
      'kind': 'run.finished',
      'runId': 'run-$id',
      'outcome': failed ? 'failed' : 'completed',
    });
  }

  /// The rail's small detail line for the seeded chats.
  String? detailFor(ChatSummary chat) => switch (chat.id) {
    quotaChatId => 'edit approval',
    'sess-wal' => 'exit 101',
    _ => null,
  };

  /// Starts the script over.
  Future<void> replay() => start();

  /// Moves a manual clock forward by [by].
  Future<void> advance(Duration by) async {
    final clock = _clock;
    if (clock is! ManualClock) return;
    await clock.advance(by);
    await _settle();
    notifyListeners();
  }

  /// Plays a manual clock until the script has ended.
  Future<void> playToEnd() async {
    final clock = _clock;
    if (clock is! ManualClock) return;
    await clock.runAll(limit: const Duration(minutes: 30));
    await _settle();
    notifyListeners();
  }

  // Lets the feed's reload after a gap finish.
  static Future<void> _settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_feed?.close());
    super.dispose();
  }
}
