// Golden screenshots of StatusMark: every status, both variants, light and
// dark. Run `flutter test --tags golden --update-goldens` (or the CI dispatch)
// to re-render; CI compares against the committed PNGs.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _sheet() => Builder(
  builder: (context) {
    final t = context.bb;
    return ColoredBox(
      color: t.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in ChatStatus.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 190,
                        child: StatusMark(s, detail: '3 agents'),
                      ),
                      SizedBox(width: 170, child: StatusMark.pill(s)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  },
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('status marks, ${brightness.name}', (tester) async {
      await pumpKit(
        tester,
        _sheet(),
        brightness: brightness,
        size: const Size(420, 300),
      );
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/status_mark_${brightness.name}.png'),
      );
    });
  }
}
