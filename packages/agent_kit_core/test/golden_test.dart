// Golden-JSON tests: each test/fixtures/<name>.jsonl is an event log that
// is folded into an empty snapshot of chat "c1" and compared with
// test/fixtures/<name>.json. Run with UPDATE_GOLDENS=1 to rewrite the
// expected files, then review the diff. The format is the shared contract
// described in test/fixtures/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:test/test.dart';

final _update = Platform.environment['UPDATE_GOLDENS'] == '1';
const _encoder = JsonEncoder.withIndent('  ');

List<File> _logs() =>
    Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Iterable<Json> _lines(File f) sync* {
  for (final raw in f.readAsLinesSync()) {
    if (raw.trim().isEmpty) continue;
    final j = jsonDecode(raw) as Json;
    if (j.containsKey('note')) continue;
    yield j;
  }
}

String _name(File f) {
  final base = f.uri.pathSegments.last;
  return base.substring(0, base.length - '.jsonl'.length);
}

void main() {
  for (final log in _logs()) {
    final name = _name(log);
    test('golden $name', () {
      var snap = ChatSnapshot.empty('c1');
      final events = <KitEvent>[];
      var lineNo = 0;
      for (final j in _lines(log)) {
        lineNo++;
        if (j['load'] case final Json load) {
          snap = ChatSnapshot.fromJson(load);
          continue;
        }
        if (j['expect'] case final Json want) {
          final have = snap.toJson();
          for (final e in want.entries) {
            expect(
              jsonEquals(have[e.key], e.value),
              isTrue,
              reason: '$name entry $lineNo: ${e.key} is ${have[e.key]}',
            );
          }
          continue;
        }
        final event = KitEvent.fromJson(j);
        expect(
          KitEvent.fromJson(event.toJson()),
          event,
          reason: '$name entry $lineNo round-trips',
        );
        events.add(event);
        snap = reduce(snap, event);
      }

      // Replaying the whole log (gaps aside) changes nothing.
      final replayed = reduceAll(snap, events.where((e) => e is! GapEvent));
      expect(replayed.toJson(), snap.toJson(), reason: 'replay is a no-op');

      // The snapshot survives a JSON round trip.
      expect(ChatSnapshot.fromJson(snap.toJson()), snap);

      final golden = File('test/fixtures/$name.json');
      final actual = '${_encoder.convert(snap.toJson())}\n';
      if (_update) {
        golden.writeAsStringSync(actual);
      } else {
        expect(
          actual,
          golden.readAsStringSync().replaceAll('\r\n', '\n'),
          reason: 'run with UPDATE_GOLDENS=1 to rewrite $name.json',
        );
      }
    });
  }

  test('fixtures cover every event kind', () {
    final seen = {
      for (final log in _logs())
        for (final j in _lines(log))
          if (j['kind'] case final String kind) kind,
    };
    expect(KitEvent.kinds.toSet().difference(seen), isEmpty);
  });
}
