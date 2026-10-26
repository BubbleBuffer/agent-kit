// Golden screenshots of the chrome widgets at 390 and 1000 px, light and dark.
// Run `flutter test --tags golden --update-goldens` (or the CI dispatch) to
// re-render; CI compares against the committed PNGs in test/goldens.

@Tags(['golden'])
library;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chrome_harness.dart';
import 'samples.dart' as s;

SessionRail _rail() => SessionRail(
  workspaceName: 'bubblepaw-base',
  groups: groupSessions(s.chats, s.now),
  selectedId: 'quota',
  detailFor: s.detailFor,
  now: s.now,
  initials: 'BC',
);

Widget _sheet(Widget child) => Builder(
  builder: (context) => ColoredBox(
    color: context.bb.surface,
    child: Align(alignment: Alignment.topCenter, child: child),
  ),
);

Widget _headers() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    ChatHeader(
      chat: s.chats[0],
      branch: 'quota-bar-reconnect',
      worktree: '/work/quota',
      usage: s.usage,
      workspaceShown: true,
      onToggleWorkspace: () {},
      menuItems: [ChromeMenuItem('Rename', () {})],
    ),
    ChatHeader(
      chat: s.chats[1],
      statusDetail: '3 agents',
      branch: 'main',
      usage: s.usage,
      onToggleWorkspace: () {},
    ),
    ChatHeader(
      chat: s.chats[4],
      branch: 'wal-growth',
      usage: const Usage(contextTokens: 120000, contextLimit: 128000),
    ),
    ChatHeader(
      chat: ChatSummary(
        id: 'done',
        title: 'A very long title that has to be cut where the room ends',
        status: ChatStatus.done,
      ),
      branch: 'release',
      usage: s.usage,
      onToggleWorkspace: () {},
    ),
  ],
);

Widget _crew({required bool wide}) {
  final strip = CrewStrip(
    agents: s.agents,
    jobs: s.jobs,
    now: s.now,
    agentTitle: s.agentTitle,
  );
  final ledger = CrewLedger(agents: s.agents, jobs: s.jobs, now: s.now);
  final usage = UsageByModel(models: s.models, usage: s.usage);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      strip,
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 252, child: ledger),
                  const SizedBox(width: 24),
                  SizedBox(width: 252, child: usage),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ledger, const SizedBox(height: 16), usage],
              ),
      ),
    ],
  );
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;

    testWidgets('rail, $name', (tester) async {
      await pumpChrome(
        tester,
        SizedBox(width: 240, child: _rail()),
        brightness: brightness,
        size: const Size(240, 560),
      );
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('../goldens/chrome_rail_$name.png'),
      );
    });

    testWidgets('rail as a sliding screen, 390, $name', (tester) async {
      final controller = RailController(open: true);
      addTearDown(controller.dispose);
      await pumpChrome(
        tester,
        RailLayout(
          controller: controller,
          rail: _rail(),
          child: _sheet(_headers()),
        ),
        brightness: brightness,
        size: const Size(390, 640),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('../goldens/chrome_rail_compact_390_$name.png'),
      );
    });

    testWidgets('hidden rail with the show button, 1000, $name', (
      tester,
    ) async {
      final controller = RailController(hidden: true);
      addTearDown(controller.dispose);
      await pumpChrome(
        tester,
        RailLayout(
          controller: controller,
          rail: _rail(),
          child: _sheet(_headers()),
        ),
        brightness: brightness,
        size: const Size(1000, 240),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('../goldens/chrome_rail_hidden_1000_$name.png'),
      );
    });

    for (final width in [1000, 390]) {
      testWidgets('header, $width, $name', (tester) async {
        await pumpChrome(
          tester,
          _sheet(_headers()),
          brightness: brightness,
          size: Size(width.toDouble(), 240),
        );
        await expectLater(
          find.byType(WidgetsApp),
          matchesGoldenFile('../goldens/chrome_header_${width}_$name.png'),
        );
      });

      testWidgets('crew, $width, $name', (tester) async {
        await pumpChrome(
          tester,
          _sheet(_crew(wide: width > 600)),
          brightness: brightness,
          size: Size(width.toDouble(), width > 600 ? 340 : 520),
        );
        await expectLater(
          find.byType(WidgetsApp),
          matchesGoldenFile('../goldens/chrome_crew_${width}_$name.png'),
        );
      });
    }
  }
}
