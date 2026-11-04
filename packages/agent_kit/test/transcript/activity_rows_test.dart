// The evidence rows of an activity group: which rows show a chevron, what an
// open tool row shows, and how a group starts when it has finished.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/transcript/transcript_support.dart'
    show DisclosureChevron;
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

Finder chevronIn(String rowId) => find.descendant(
  of: find.byKey(ValueKey(rowId)),
  matching: find.byType(DisclosureChevron),
);

double chevronTurns(WidgetTester tester, String rowId) => tester
    .widget<AnimatedRotation>(
      find.descendant(
        of: chevronIn(rowId),
        matching: find.byType(AnimatedRotation),
      ),
    )
    .turns;

Finder verbIn(String rowId, String verb) =>
    find.descendant(of: find.byKey(ValueKey(rowId)), matching: find.text(verb));

ActivityGroup groupOf(List<ActivityRow> rows) =>
    ActivityGroup(id: 'g', at: t0, rows: rows);

ToolRow doneTool(
  String id, {
  String target = 'a.rs',
  String? arguments,
  ToolKind kind = ToolKind.read,
}) => ToolRow(
  id: id,
  name: 'tool',
  kind: kind,
  target: target,
  arguments: arguments,
  state: WorkState.done,
);

void main() {
  group('chevrons', () {
    testWidgets('show on rows that open and turn when open', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
      );
      // Arguments, arguments and output, and arguments that are plain text.
      for (final id in ['p1', 'p2', 'p3']) {
        expect(chevronIn(id), findsOneWidget, reason: id);
        expect(chevronTurns(tester, id), -.25, reason: id);
      }
      // No arguments and no output, and a spawn row.
      for (final id in ['p4', 'p5']) {
        expect(chevronIn(id), findsNothing, reason: id);
      }
      await tester.tap(find.text('usage/mod.rs'));
      await tester.pump();
      expect(chevronTurns(tester, 'p1'), 0);
      expect(chevronTurns(tester, 'p2'), -.25);
    });

    testWidgets('a thinking row shows one only with reasoning text', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          groupOf(const [
            ThinkingRow(id: 't1', text: 'Weighed the options', durationMs: 900),
            ThinkingRow(id: 't2', durationMs: 900),
          ]),
          initiallyOpen: true,
        ),
      );
      expect(chevronIn('t1'), findsOneWidget);
      expect(chevronIn('t2'), findsNothing);
    });

    testWidgets('rows that cannot open line up with the ones that can', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
      );
      final x = {
        for (final (id, verb) in [
          ('p1', 'read'),
          ('p2', 'exec'),
          ('p3', 'web'),
          ('p4', 'read'),
          ('p5', 'spawn'),
        ])
          tester.getTopLeft(verbIn(id, verb)).dx,
      };
      expect(x, hasLength(1));
    });
  });

  group('open tool rows', () {
    testWidgets('a row with arguments and no output opens', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          groupOf([
            doneTool('a', arguments: '{"path":"crates/a.rs","limit":50}'),
          ]),
          initiallyOpen: true,
        ),
      );
      expect(find.text('path'), findsNothing);
      await tester.tap(find.text('a.rs'));
      await tester.pump();
      expect(find.text('path'), findsOneWidget);
      expect(find.text('crates/a.rs'), findsOneWidget);
      expect(find.text('limit'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      // No output block and no captions.
      expect(find.byType(ExecOutput), findsNothing);
      expect(find.text('Command'), findsNothing);
      expect(find.text('Output'), findsNothing);
    });

    testWidgets('an empty arguments object does not open', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          groupOf([doneTool('a', arguments: '{}')]),
          initiallyOpen: true,
        ),
      );
      expect(chevronIn('a'), findsNothing);
    });

    testWidgets('shows the whole target, then arguments, then output', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
        width: 390,
        height: 1200,
      );
      Text target() => tester.widget<Text>(find.text(longCommand));
      expect(target().maxLines, 1);
      await tester.tap(find.text(longCommand));
      await tester.pump();
      // Whole, wrapped, once.
      expect(target().maxLines, isNull);
      expect(find.text(longCommand), findsOneWidget);
      expect(tester.getSize(find.text(longCommand)).height, greaterThan(32));
      // The command is not repeated as an argument; the timeout is.
      expect(find.text('command'), findsNothing);
      expect(find.text('timeout'), findsOneWidget);
      expect(find.text('120000'), findsOneWidget);
      // Arguments above the output block.
      expect(
        tester.getTopLeft(find.text('timeout')).dy,
        lessThan(tester.getTopLeft(find.byType(ExecOutput)).dy),
      );
      expect(find.text('Show all 21 lines'), findsOneWidget);
    });

    testWidgets('an exec row with only its command and no output opens to '
        'the whole command', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          groupOf([
            doneTool(
              'e',
              kind: ToolKind.exec,
              target: longCommand,
              arguments: '{"command":"$longCommand"}',
            ),
          ]),
          initiallyOpen: true,
        ),
        width: 390,
      );
      expect(chevronIn('e'), findsOneWidget);
      await tester.tap(find.text(longCommand));
      await tester.pump();
      expect(find.text('command'), findsNothing);
      expect(find.text(longCommand), findsOneWidget);
      expect(tester.widget<Text>(find.text(longCommand)).maxLines, isNull);
    });

    testWidgets('arguments that are not a JSON object show as text', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
      );
      await tester.tap(find.text('docs.rs/tokio'));
      await tester.pump();
      expect(find.text('GET https://docs.rs/tokio/latest'), findsOneWidget);
    });

    testWidgets('long output lines scroll sideways', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
        width: 390,
        height: 1200,
      );
      await tester.tap(find.text(longCommand));
      await tester.pump();
      await tester.tap(find.text('Show all 21 lines'));
      await tester.pump();
      final scroll = find.descendant(
        of: find.byType(ExecOutput),
        matching: find.byType(SingleChildScrollView),
      );
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
    });

    testWidgets('one row stays open at a time', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(toolRowsGroup(), initiallyOpen: true),
      );
      await tester.tap(find.text('usage/mod.rs'));
      await tester.pump();
      expect(find.text('limit'), findsOneWidget);
      await tester.tap(find.text('docs.rs/tokio'));
      await tester.pump();
      expect(find.text('limit'), findsNothing);
      expect(find.text('GET https://docs.rs/tokio/latest'), findsOneWidget);
    });

    testWidgets('a spawn row still opens the child', (tester) async {
      String? opened;
      await pumpTranscript(
        tester,
        ActivityGroupView(
          toolRowsGroup(),
          initiallyOpen: true,
          onOpenChild: (id) => opened = id,
        ),
      );
      await tester.tap(find.text('Survey Codex'));
      expect(opened, 'child-c7e2');
    });
  });

  group('finished groups', () {
    final finished = activityGroup();
    final running = groupOf([
      const ToolRow(id: 'r', name: 'read', kind: ToolKind.read, target: 'a.rs'),
    ]);
    final done = groupOf([doneTool('r')]);

    Future<void> pump(
      WidgetTester tester,
      ActivityGroup group, {
      bool open = false,
    }) => pumpTranscript(tester, ActivityGroupView(group, finishedOpen: open));

    testWidgets('start shut by default and open when the setting says so', (
      tester,
    ) async {
      await pump(tester, finished);
      expect(find.text('exec'), findsNothing);
      await pump(tester, finished, open: true);
      expect(find.text('exec'), findsWidgets);
    });

    testWidgets('a running group is open whatever the setting', (tester) async {
      await pump(tester, running);
      expect(find.text('read'), findsOneWidget);
    });

    testWidgets('a group that finishes follows the setting', (tester) async {
      await pump(tester, running);
      expect(find.text('read'), findsOneWidget);
      await pump(tester, done);
      expect(find.text('read'), findsNothing);

      await pump(tester, running, open: true);
      await pump(tester, done, open: true);
      expect(find.text('read'), findsOneWidget);
    });

    testWidgets('changing the setting moves groups nobody toggled', (
      tester,
    ) async {
      await pump(tester, done);
      expect(find.text('read'), findsNothing);
      await pump(tester, done, open: true);
      expect(find.text('read'), findsOneWidget);
      await pump(tester, done);
      expect(find.text('read'), findsNothing);
    });

    testWidgets('a group the person toggled keeps its state', (tester) async {
      await pump(tester, done);
      await tester.tap(find.text('Read 1 file'));
      await tester.pump();
      expect(find.text('read'), findsOneWidget);
      await pump(tester, done, open: true);
      await pump(tester, done);
      expect(find.text('read'), findsOneWidget);
    });

    testWidgets('a group the person closed stays closed', (tester) async {
      await pump(tester, finished, open: true);
      expect(find.text('exec'), findsWidgets);
      await tester.tap(find.textContaining('Searched'));
      await tester.pump();
      expect(find.text('exec'), findsNothing);
      await pump(tester, finished);
      await pump(tester, finished, open: true);
      expect(find.text('exec'), findsNothing);
    });

    testWidgets('the setting reaches groups through TranscriptActions', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        TranscriptItemView(
          finished,
          actions: const TranscriptActions(finishedActivityOpen: true),
        ),
      );
      expect(find.text('exec'), findsWidgets);
    });
  });
}
