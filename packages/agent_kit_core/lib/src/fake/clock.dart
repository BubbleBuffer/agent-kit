/// Clocks for the scripted backend: the system clock and a manual one.
library;

import 'dart:async';

/// The time source of the scripted backend.
abstract interface class KitClock {
  /// The current time.
  DateTime now();

  /// Completes after [duration] has passed on this clock.
  Future<void> sleep(Duration duration);
}

/// The real clock.
final class SystemClock implements KitClock {
  /// Creates the system clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}

/// A deterministic clock that moves only when [advance] is called.
///
/// Sleepers wake in deadline order (ties in the order they slept), and
/// each wake-up runs its continuation before the next one fires, so a
/// script plays the same way every time.
final class ManualClock implements KitClock {
  /// Creates a manual clock starting at [start] (2026-01-01 UTC by
  /// default).
  ManualClock([DateTime? start]) : _now = (start ?? DateTime.utc(2026)).toUtc();

  DateTime _now;
  final _sleepers = <_Sleeper>[];
  var _order = 0;

  @override
  DateTime now() => _now;

  @override
  Future<void> sleep(Duration duration) {
    final s = _Sleeper(_now.add(duration), _order++);
    _sleepers.add(s);
    return s.completer.future;
  }

  /// Number of sleepers not yet woken.
  int get pending => _sleepers.length;

  /// Moves the clock forward by [duration], waking every sleeper whose
  /// deadline is reached, one at a time.
  Future<void> advance(Duration duration) async {
    final target = _now.add(duration);
    await _settle();
    while (true) {
      final due = _sleepers.where((s) => !s.due.isAfter(target)).toList()
        ..sort();
      if (due.isEmpty) break;
      final next = due.first;
      _sleepers.remove(next);
      if (next.due.isAfter(_now)) _now = next.due;
      next.completer.complete();
      await _settle();
    }
    _now = target;
  }

  /// Advances until no sleeper is left, or [limit] has passed.
  Future<void> runAll({Duration limit = const Duration(hours: 1)}) async {
    final end = _now.add(limit);
    while (_sleepers.isNotEmpty && _now.isBefore(end)) {
      final first = ([..._sleepers]..sort()).first;
      final step = first.due.isAfter(_now)
          ? first.due.difference(_now)
          : Duration.zero;
      await advance(step);
    }
  }

  static Future<void> _settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

final class _Sleeper implements Comparable<_Sleeper> {
  _Sleeper(this.due, this.order);

  final DateTime due;
  final int order;
  final completer = Completer<void>();

  @override
  int compareTo(_Sleeper other) {
    final c = due.compareTo(other.due);
    return c != 0 ? c : order.compareTo(other.order);
  }
}
