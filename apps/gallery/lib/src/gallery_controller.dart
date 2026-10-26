// The gallery's state: the scene, theme and width, and a chat that plays the
// "Quota bar flickers on reconnect" script on FakeAgentBackend's scripted
// backend, followed through a ChatFeed.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';

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
    : _newClock = clock ?? (() => ManualClock());

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
    final backend = ScriptedBackend(
      scripts: [quotaReconnectScript()],
      clock: _clock,
    );
    _backend = backend;
    final feed = ChatFeed(backend, quotaChatId);
    _feed = feed;
    _sub = feed.snapshots.listen((_) => notifyListeners());
    await feed.start();
    unawaited(backend.play());
    final clock = _clock;
    if (clock is ManualClock) {
      await clock.advance(Duration.zero);
      if (autoPlay) await playToEnd();
    }
    notifyListeners();
  }

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
