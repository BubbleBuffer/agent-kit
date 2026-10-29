// Golden screenshots of the providers section at 680 and 390 px, light and
// dark. Run `flutter test --tags golden --update-goldens` (or the CI dispatch)
// to re-render.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chrome/chrome_harness.dart';
import 'provider_samples.dart';

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;
    for (final width in [680, 390]) {
      testWidgets('providers, $width, $name', (tester) async {
        await pumpChrome(
          tester,
          Builder(
            builder: (context) => ColoredBox(
              color: context.bb.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ProviderList(
                  setup: sampleProviders(reload: true),
                  onMakeDefault: (_) {},
                ),
              ),
            ),
          ),
          brightness: brightness,
          size: Size(width.toDouble(), width > 600 ? 560 : 700),
        );
        await expectLater(
          find.byType(WidgetsApp),
          matchesGoldenFile('../goldens/provider_settings_${width}_$name.png'),
        );
      });
    }
  }
}
