import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/chrome/command_key.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chrome_harness.dart';
import 'samples.dart' as s;

SessionRail _rail({
  ValueChanged<ChatSummary>? onSelect,
  VoidCallback? onNewChat,
  VoidCallback? onSearch,
  VoidCallback? onSettings,
  VoidCallback? onHide,
}) => SessionRail(
  workspaceName: 'bubblepaw-base',
  groups: groupSessions(s.chats, s.now),
  selectedId: 'quota',
  detailFor: s.detailFor,
  now: s.now,
  initials: 'BC',
  onSelect: onSelect,
  onNewChat: onNewChat,
  onSearch: onSearch,
  onSettings: onSettings,
  onHide: onHide,
);

Widget _railBox({
  ValueChanged<ChatSummary>? onSelect,
  VoidCallback? onNewChat,
  VoidCallback? onSearch,
  VoidCallback? onSettings,
  VoidCallback? onHide,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: 240,
    height: 640,
    child: _rail(
      onSelect: onSelect,
      onNewChat: onNewChat,
      onSearch: onSearch,
      onSettings: onSettings,
      onHide: onHide,
    ),
  ),
);

void main() {
  group('command key hints', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Ctrl off macOS, Cmd on macOS and iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(commandKeyHint('Ctrl+B'), 'Ctrl+B');
      expect(commandKeyHint('Ctrl K'), 'Ctrl K');
      for (final p in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = p;
        expect(commandKeyHint('Ctrl+B'), '⌘B');
        expect(commandKeyHint('Ctrl K'), '⌘K');
      }
    });
  });

  group('formatting', () {
    test('elapsed times', () {
      expect(formatElapsed(const Duration(seconds: 41)), '41s');
      expect(formatElapsed(const Duration(seconds: 64)), '1m 04s');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 5)), '12m');
      expect(formatElapsed(const Duration(minutes: 65)), '1h 05m');
    });

    test('token counts', () {
      expect(formatTokens(812), '812');
      expect(formatTokens(48200), '48.2k');
      expect(formatTokens(128000), '128k');
      expect(formatTokens(1240000), '1.24M');
    });

    test('ages', () {
      expect(
        chatAge(s.now.subtract(const Duration(minutes: 12)), s.now),
        '12m',
      );
      expect(chatAge(s.now.subtract(const Duration(hours: 2)), s.now), '2h');
      expect(
        chatAge(s.now.subtract(const Duration(days: 1)), s.now),
        'Yesterday',
      );
      expect(chatAge(null, s.now), '');
    });

    test('rows group into Today and Earlier', () {
      final groups = groupSessions(s.chats, s.now);
      expect(groups.map((g) => g.label), ['Today', 'Earlier']);
      expect(groups[0].chats.map((c) => c.id), ['quota', 'steer', 'fork']);
      expect(groups[1].chats.length, 3);
    });

    test('default meta text', () {
      expect(railDetail(s.chats[1], s.now), '3 agents');
      expect(railDetail(s.chats[0], s.now), isNull);
      expect(railDetail(s.chats[4], s.now), 'exit 101');
      expect(railDetail(s.chats[2], s.now), '12m');
    });
  });

  group('SessionRail', () {
    testWidgets('shows groups, rows with status meta and the footer', (
      tester,
    ) async {
      await pumpChrome(tester, _railBox(), size: const Size(300, 700));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.text(s.quotaTitle), findsOneWidget);
      expect(
        find.textContaining('Waiting for you', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('edit approval', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('bubblepaw-base'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Ctrl K'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('BC'), findsOneWidget);
    });

    testWidgets('callbacks fire', (tester) async {
      final picked = <String>[];
      var newChats = 0, searches = 0, settings = 0, hides = 0;
      await pumpChrome(
        tester,
        _railBox(
          onSelect: (c) => picked.add(c.id),
          onNewChat: () => newChats++,
          onSearch: () => searches++,
          onSettings: () => settings++,
          onHide: () => hides++,
        ),
        size: const Size(300, 700),
      );
      await tester.tap(find.text('Steer vs queue semantics'));
      await tester.tap(find.byKey(const ValueKey('rail-new-chat')));
      await tester.tap(find.byKey(const ValueKey('rail-search')));
      await tester.tap(find.byKey(const ValueKey('rail-settings')));
      await tester.tap(find.byKey(const ValueKey('rail-hide')));
      expect(picked, ['steer']);
      expect([newChats, searches, settings, hides], [1, 1, 1, 1]);
    });
  });

  group('SessionRail load more', () {
    Widget railWith({
      bool hasMore = true,
      bool loading = false,
      bool failed = false,
      VoidCallback? onLoadMore,
    }) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 240,
        height: 640,
        child: SessionRail(
          workspaceName: 'bubblepaw-base',
          groups: groupSessions(s.chats, s.now),
          selectedId: 'quota',
          detailFor: s.detailFor,
          now: s.now,
          initials: 'BC',
          hasMore: hasMore,
          loadingMore: loading,
          loadMoreFailed: failed,
          onLoadMore: onLoadMore,
        ),
      ),
    );

    testWidgets('ends the list with a row that loads the next page', (
      tester,
    ) async {
      var loads = 0;
      await pumpChrome(
        tester,
        railWith(onLoadMore: () => loads++),
        size: const Size(300, 700),
      );
      expect(find.text('Show older sessions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rail-load-more')));
      expect(loads, 1);
    });

    testWidgets('there is no row on the last page', (tester) async {
      await pumpChrome(
        tester,
        railWith(hasMore: false),
        size: const Size(300, 700),
      );
      expect(find.byKey(const ValueKey('rail-load-more')), findsNothing);
      expect(find.text('Show older sessions'), findsNothing);
    });

    testWidgets('says it is loading and ignores presses meanwhile', (
      tester,
    ) async {
      var loads = 0;
      await pumpChrome(
        tester,
        railWith(loading: true, onLoadMore: () => loads++),
        size: const Size(300, 700),
      );
      expect(find.text('Loading older sessions…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rail-load-more')));
      expect(loads, 0);
    });

    testWidgets('after a failure the row offers another try', (tester) async {
      var loads = 0;
      await pumpChrome(
        tester,
        railWith(failed: true, onLoadMore: () => loads++),
        size: const Size(300, 700),
      );
      expect(
        find.text('Could not load older sessions. Try again'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('rail-load-more')));
      expect(loads, 1);
    });
  });

  group('RailLayout', () {
    Widget layout(RailController controller) => RailLayout(
      controller: controller,
      rail: _rail(),
      child: Focus(
        autofocus: true,
        child: const Align(
          alignment: Alignment.topLeft,
          child: RailShowButton(),
        ),
      ),
    );

    testWidgets('the hide button folds the column and the show button '
        'brings it back', (tester) async {
      final controller = RailController();
      addTearDown(controller.dispose);
      await pumpChrome(tester, layout(controller), size: const Size(1000, 640));
      expect(find.byKey(const ValueKey('rail-hide')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-show')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('rail-hide')));
      await tester.pumpAndSettle();
      expect(controller.hidden, isTrue);
      expect(find.byKey(const ValueKey('rail-hide')), findsNothing);
      expect(find.byKey(const ValueKey('rail-show')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rail-show')));
      await tester.pumpAndSettle();
      expect(controller.hidden, isFalse);
      expect(find.byKey(const ValueKey('rail-hide')), findsOneWidget);
    });

    testWidgets('Ctrl+B toggles the rail', (tester) async {
      final controller = RailController();
      addTearDown(controller.dispose);
      await pumpChrome(tester, layout(controller), size: const Size(1000, 640));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.hidden, isTrue);
    });

    testWidgets('compact: a sliding screen opened from the menu button and '
        'closed by picking a row', (tester) async {
      final controller = RailController();
      addTearDown(controller.dispose);
      await pumpChrome(tester, layout(controller), size: const Size(390, 640));
      expect(find.byKey(const ValueKey('rail-hide')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('rail-show')));
      await tester.pumpAndSettle();
      expect(controller.open, isTrue);
      expect(find.text(s.quotaTitle), findsOneWidget);

      await tester.tap(find.text('Compact before fork'));
      await tester.pumpAndSettle();
      expect(controller.open, isFalse);
      expect(find.text('Compact before fork'), findsNothing);
    });

    test('the controller keeps the two states apart', () {
      final controller = RailController()..hide(SizeClass.expanded);
      expect(controller.isVisible(SizeClass.expanded), isFalse);
      expect(controller.isVisible(SizeClass.compact), isFalse);
      controller.show(SizeClass.compact);
      expect(controller.isVisible(SizeClass.compact), isTrue);
      expect(controller.isVisible(SizeClass.medium), isFalse);
      controller.dispose();
    });
  });

  group('ChatHeader', () {
    ChatHeader header({
      VoidCallback? onToggleWorkspace,
      List<ChromeMenuItem> menuItems = const [],
    }) => ChatHeader(
      chat: s.chats.first,
      branch: 'quota-bar-reconnect',
      worktree: '/work/bubblepaw-base-quota',
      usage: s.usage,
      workspaceShown: true,
      onToggleWorkspace: onToggleWorkspace,
      menuItems: menuItems,
    );

    testWidgets('wide: tile, title, pill, branch and the meter label', (
      tester,
    ) async {
      await pumpChrome(
        tester,
        Align(alignment: Alignment.topCenter, child: header()),
        size: const Size(1000, 200),
      );
      expect(find.text(s.quotaTitle), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('quota-bar-reconnect'), findsOneWidget);
      expect(find.text('38% context'), findsOneWidget);
    });

    testWidgets('narrow: drops the branch and the meter label', (tester) async {
      await pumpChrome(
        tester,
        Align(alignment: Alignment.topCenter, child: header()),
        size: const Size(390, 200),
      );
      expect(find.text(s.quotaTitle), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('quota-bar-reconnect'), findsNothing);
      expect(find.text('38% context'), findsNothing);
    });

    testWidgets('a very long title truncates without overflowing', (
      tester,
    ) async {
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: ChatHeader(
            chat: ChatSummary(
              id: 'x',
              title: 'A very long session title ' * 8,
              status: ChatStatus.running,
            ),
            branch: 'a-long-branch-name/with/many/segments',
            usage: s.usage,
          ),
        ),
        size: const Size(700, 200),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the workspace toggle and the session menu call back', (
      tester,
    ) async {
      var toggled = 0, archived = 0;
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: header(
            onToggleWorkspace: () => toggled++,
            menuItems: [
              ChromeMenuItem('Rename', () {}),
              ChromeMenuItem(
                'Archive',
                () => archived++,
                separatorBefore: true,
              ),
            ],
          ),
        ),
        size: const Size(1000, 300),
      );
      await tester.tap(find.byKey(const ValueKey('header-workspace')));
      expect(toggled, 1);

      await tester.tap(find.byKey(const ValueKey('header-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(archived, 1);
      expect(find.text('Rename'), findsNothing);
    });
  });

  group('Crew', () {
    testWidgets('the strip shows a chip per agent and job and opens them', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: CrewStrip(
            agents: s.agents,
            jobs: s.jobs,
            now: s.now,
            agentTitle: s.agentTitle,
            onOpenAgent: (a) => opened.add(a.id),
            onOpenJob: (j) => opened.add(j.id),
          ),
        ),
        size: const Size(700, 200),
      );
      expect(find.text('Survey quota'), findsOneWidget);
      expect(find.text('Map transitions'), findsOneWidget);
      expect(find.text('cargo test'), findsOneWidget);
      expect(find.textContaining('1m 04s', findRichText: true), findsOneWidget);
      expect(find.textContaining('ready', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('2 failed', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Map transitions'));
      await tester.tap(find.text('cargo test'));
      expect(opened, ['map', 'test']);
    });

    testWidgets('the strip scrolls sideways when narrow', (tester) async {
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: CrewStrip(
            agents: s.agents,
            jobs: s.jobs,
            now: s.now,
            agentTitle: s.agentTitle,
          ),
        ),
        size: const Size(240, 200),
      );
      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('the strip is empty without a crew', (tester) async {
      await pumpChrome(tester, const CrewStrip(), size: const Size(300, 100));
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('the ledger draws nothing without agents and jobs', (
      tester,
    ) async {
      await pumpChrome(tester, const CrewLedger(), size: const Size(300, 100));
      expect(find.text('Still running'), findsNothing);
    });

    testWidgets('the ledger counts, lists and opens its entries', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 252,
            child: CrewLedger(
              agents: s.agents,
              jobs: s.jobs,
              now: s.now,
              onOpenAgent: (a) => opened.add(a.id),
              onOpenJob: (j) => opened.add(j.id),
            ),
          ),
        ),
        size: const Size(300, 600),
      );
      // One agent runs, one has a result and the command exited: the
      // heading must not claim they all still run.
      expect(find.text('Still running'), findsNothing);
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('1 running · 2 finished'), findsOneWidget);
      expect(find.text('Survey quota handling in Codex'), findsOneWidget);
      expect(
        find.text('read codex-rs/core/src/rate_limits.rs'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Result ready', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('exited 101', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('background · 41s'), findsOneWidget);
      await tester.tap(find.text('cargo test -p bubblepaw-host usage'));
      await tester.tap(find.text('Survey quota handling in Codex'));
      expect(opened, ['test', 'survey']);
    });

    testWidgets('the heading says Still running only while every entry runs', (
      tester,
    ) async {
      Future<void> show(List<ChildAgent> agents, List<BackgroundJob> jobs) =>
          pumpChrome(
            tester,
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 252,
                child: CrewLedger(agents: agents, jobs: jobs, now: s.now),
              ),
            ),
            size: const Size(300, 400),
          );
      final running = ChildAgent(
        id: 'a',
        task: 'Check the logs',
        startedAt: s.now.subtract(const Duration(seconds: 30)),
      );
      final asking = ChildAgent(
        id: 'b',
        task: 'Pick a colour',
        state: WorkState.waitingForAnswer,
        startedAt: s.now.subtract(const Duration(seconds: 30)),
      );
      final failed = ChildAgent(
        id: 'c',
        task: 'Build it',
        state: WorkState.failed,
        endedAt: s.now,
      );
      final job = BackgroundJob(
        id: 'j',
        command: 'cargo test',
        startedAt: s.now.subtract(const Duration(seconds: 5)),
      );

      await show([running, asking], [job]);
      expect(find.text('Still running'), findsOneWidget);
      expect(find.text('2 agents · 1 command'), findsOneWidget);

      await show([running], const []);
      expect(find.text('1 agent'), findsOneWidget);

      await show([running, failed], [job]);
      expect(find.text('Still running'), findsNothing);
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('2 running · 1 finished'), findsOneWidget);

      await show([failed], const []);
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('1 finished'), findsOneWidget);
    });

    testWidgets('Cancel is offered on a running agent only', (tester) async {
      final cancelled = <String>[];
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 252,
            child: CrewLedger(
              agents: s.agents,
              jobs: s.jobs,
              now: s.now,
              onCancelAgent: (a) => cancelled.add(a.id),
            ),
          ),
        ),
        size: const Size(300, 600),
      );
      // 'survey' runs; 'map' has its result.
      expect(
        find.byKey(const ValueKey('ledger-cancel-survey')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ledger-cancel-map')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ledger-cancel-survey')));
      expect(cancelled, ['survey']);
    });

    testWidgets('without onCancelAgent there is no Cancel', (tester) async {
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 252,
            child: CrewLedger(agents: s.agents, jobs: s.jobs, now: s.now),
          ),
        ),
        size: const Size(300, 600),
      );
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('a cancelling agent shows it and cannot be cancelled twice', (
      tester,
    ) async {
      final cancelled = <String>[];
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 252,
            child: CrewLedger(
              agents: s.agents,
              jobs: s.jobs,
              now: s.now,
              onCancelAgent: (a) => cancelled.add(a.id),
              cancelling: const {'survey'},
            ),
          ),
        ),
        size: const Size(300, 600),
      );
      expect(find.text('Cancelling…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ledger-cancel-survey')));
      expect(cancelled, isEmpty);
    });
  });

  group('UsageByModel', () {
    testWidgets('shares by model with the small ones folded', (tester) async {
      await pumpChrome(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 252,
            child: UsageByModel(models: s.models, usage: s.usage),
          ),
        ),
        size: const Size(300, 300),
      );
      expect(find.text('By model'), findsOneWidget);
      expect(find.text('deepseek-v4.1-flash'), findsOneWidget);
      expect(find.text('77%'), findsOneWidget);
      expect(find.text('23%'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('<1%'), findsOneWidget);
      expect(find.text('1.24M tokens'), findsOneWidget);
    });

    testWidgets('says so when there is no usage', (tester) async {
      await pumpChrome(
        tester,
        const UsageByModel(models: []),
        size: const Size(300, 200),
      );
      expect(find.text('No usage yet'), findsOneWidget);
    });
  });
}
