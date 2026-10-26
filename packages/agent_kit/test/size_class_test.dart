// Size classes come from the container width, not the window.

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('thresholds: compact < 600 <= medium < 1000 <= expanded', () {
    expect(SizeClass.forWidth(360), SizeClass.compact);
    expect(SizeClass.forWidth(599.9), SizeClass.compact);
    expect(SizeClass.forWidth(600), SizeClass.medium);
    expect(SizeClass.forWidth(999.9), SizeClass.medium);
    expect(SizeClass.forWidth(1000), SizeClass.expanded);
    expect(SizeClass.forWidth(1600), SizeClass.expanded);
    expect(SizeClass.expanded.atLeast(SizeClass.medium), isTrue);
    expect(SizeClass.compact.atLeast(SizeClass.medium), isFalse);
  });

  testWidgets('a builder measures its own container, not the window', (
    tester,
  ) async {
    SizeClass? seen;
    Future<void> pumpWidth(double width) => pumpKit(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: SizeClassBuilder(
            builder: (context, sizeClass) {
              seen = SizeClass.of(context);
              expect(seen, sizeClass);
              return const SizedBox(height: 10);
            },
          ),
        ),
      ),
      size: const Size(1600, 400),
    );

    // The window stays 1600 wide in every case.
    await pumpWidth(390);
    expect(seen, SizeClass.compact);
    await pumpWidth(820);
    expect(seen, SizeClass.medium);
    await pumpWidth(1440);
    expect(seen, SizeClass.expanded);
  });
}
