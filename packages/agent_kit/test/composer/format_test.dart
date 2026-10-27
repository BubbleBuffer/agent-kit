import 'package:agent_kit/src/composer/composer_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 12, 12);

  test('formatWaiting counts up', () {
    String f(Duration d) => formatWaiting(now.subtract(d), now);
    expect(f(const Duration(seconds: 20)), 'waiting <1m');
    expect(f(const Duration(minutes: 12)), 'waiting 12m');
    expect(f(const Duration(minutes: 65)), 'waiting 1h 5m');
    expect(f(const Duration(days: 2, hours: 3)), 'waiting 2d');
  });

  test('shortenPath keeps the last two segments', () {
    expect(
      shortenPath('crates/bubblepaw-host/src/usage/mod.rs'),
      '…/usage/mod.rs',
    );
    expect(shortenPath('mod.rs'), 'mod.rs');
    expect(shortenPath(r'C:\repo\src\usage\mod.rs'), '…/usage/mod.rs');
  });
}
