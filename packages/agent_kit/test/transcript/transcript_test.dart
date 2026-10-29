// Widget tests for the transcript group: markdown, the activity group and its
// rows, output clamp, edit rows, diff, plan, return lines and the list's
// follow-tail and anchor restore.

import 'dart:async' show Completer;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bb_ui/hover.dart';

import 'fixtures.dart';
import 'harness.dart';

/// The fade that clears the lines under the "Jump to latest" pill.
Finder get pillFade => find.descendant(
  of: find.byType(TranscriptList),
  matching: find.byType(ShaderMask),
);

void main() {
  group('markdown', () {
    test('splits blocks', () {
      final blocks = parseMarkdownBlocks(proseMarkdown);
      expect(blocks.map((b) => b.runtimeType), [
        MdParagraph,
        MdParagraph,
        MdList,
        MdCode,
      ]);
      expect((blocks[2] as MdList).items, hasLength(3));
      expect((blocks[3] as MdCode).language, 'rust');
    });

    test('an open fence runs to the end', () {
      final blocks = parseMarkdownBlocks('text\n\n```dart\nlet x = 1;');
      expect((blocks.last as MdCode).code, 'let x = 1;');
    });

    test('numbered lists, headings and quotes', () {
      final blocks = parseMarkdownBlocks('# Title\n\n3. a\n4. b\n\n> quoted');
      expect(blocks[0], isA<MdHeading>());
      expect((blocks[1] as MdList).start, 3);
      expect(blocks[2], isA<MdQuote>());
    });

    test('inline runs', () {
      final spans = parseMarkdownInline('a `b` **c** *d* [e](u) snake_case');
      expect(spans.where((s) => s.code).map((s) => s.text), ['b']);
      expect(spans.where((s) => s.bold).map((s) => s.text), ['c']);
      expect(spans.where((s) => s.italic).map((s) => s.text), ['d']);
      expect(spans.where((s) => s.link != null).map((s) => s.link), ['u']);
      expect(spans.last.text, contains('snake_case'));
    });

    testWidgets('the default renderer draws prose and a code block', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        SingleChildScrollView(child: AssistantProse(assistantMessage())),
      );
      expect(
        find.textContaining('Both tools hold the last figure'),
        findsOneWidget,
      );
      expect(find.byType(CodeBlock), findsOneWidget);
      expect(find.textContaining('self.stale_since.is_some()'), findsOneWidget);
    });

    testWidgets('a link calls back', (tester) async {
      String? tapped;
      await pumpTranscript(
        tester,
        AssistantProse(
          const AssistantMessage(id: 'm', markdown: 'See [the docs](x://y).'),
          onLinkTap: (u) => tapped = u,
        ),
      );
      final rich = find.byType(RichText).first;
      final box = tester.getTopLeft(rich);
      // "See " is 4 characters wide; tap inside "the docs".
      await tester.tapAt(box + const Offset(50, 10));
      expect(tapped, 'x://y');
    });
  });

  group('messages', () {
    testWidgets('user bubble, chips and tap', (tester) async {
      KitRef? tapped;
      await pumpTranscript(
        tester,
        UserBubble(userMessage(), onRefTap: (r) => tapped = r),
      );
      expect(
        find.textContaining('The quota bar in the web view'),
        findsOneWidget,
      );
      await tester.tap(find.text('usage/mod.rs'));
      expect(tapped?.id, 'f1');
    });

    testWidgets('notice and system lines', (tester) async {
      await pumpTranscript(
        tester,
        Column(
          children: [
            const SystemLineView(
              SystemLine(id: 's', text: 'Context compacted'),
            ),
            for (final tone in NoticeTone.values)
              NoticeLineView(
                NoticeLine(
                  id: tone.name,
                  text: 'Tone ${tone.name}',
                  tone: tone,
                ),
              ),
          ],
        ),
      );
      expect(find.text('Context compacted'), findsOneWidget);
      for (final tone in NoticeTone.values) {
        expect(find.text('Tone ${tone.name}'), findsOneWidget);
      }
    });
  });

  group('activity group', () {
    test('summary line', () {
      expect(
        activitySummary(activityGroup()),
        'Searched 1× · Read 2 files · Ran 1 command · Started 1 agent · 1 failed · Worked 48s · thought 6s',
      );
      expect(
        activitySummary(
          ActivityGroup(
            id: 'g',
            rows: [const ToolRow(id: 't', name: 'x')],
          ),
        ),
        '1 other call',
      );
      expect(activitySummary(ActivityGroup(id: 'g')), 'Worked');
      // No durations from the backend, no time parts.
      expect(
        activitySummary(
          ActivityGroup(
            id: 'g',
            rows: [
              const ToolRow(
                id: 'a',
                name: 'x',
                kind: ToolKind.edit,
                state: WorkState.done,
              ),
              const ToolRow(
                id: 'b',
                name: 'y',
                kind: ToolKind.write,
                state: WorkState.failed,
              ),
            ],
          ),
        ),
        'Edited 2 files · 1 failed',
      );
    });

    testWidgets('a footer shows under the rows only while open', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(activityGroup(), footer: const Text('Show code')),
      );
      expect(find.text('Show code'), findsNothing);
      await tester.tap(find.textContaining('Searched 1×'));
      await tester.pump();
      expect(find.text('Show code'), findsOneWidget);
    });

    testWidgets('a host can replace the summary line', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          activityGroup(),
          summaryOf: (g) => 'Looked around (${g.toolCalls})',
        ),
      );
      expect(find.text('Looked around (5)'), findsOneWidget);
    });

    testWidgets('Enter on the focused summary expands it', (tester) async {
      await pumpTranscript(tester, ActivityGroupView(activityGroup()));
      expect(find.text('exec'), findsNothing);
      // Focus the summary, as Tab would.
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byType(Hover),
                matching: find.byType(MouseRegion),
              )
              .last,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('exec'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('exec'), findsNothing);
    });

    testWidgets('opens into rows, one at a time', (tester) async {
      await pumpTranscript(tester, ActivityGroupView(activityGroup()));
      const summary =
          'Searched 1× · Read 2 files · Ran 1 command · Started 1 agent · 1 failed · Worked 48s · thought 6s';
      expect(find.text(summary), findsOneWidget);
      expect(find.text('exec'), findsNothing);

      await tester.tap(find.text(summary));
      await tester.pump();
      for (final verb in ['think', 'read', 'grep', 'exec', 'spawn']) {
        expect(find.text(verb), findsWidgets, reason: verb);
      }
      expect(find.text('212 lines'), findsOneWidget);
      expect(find.text('9 hits'), findsOneWidget);
      expect(find.text('child c7e2'), findsOneWidget);

      await tester.tap(find.text('cargo test -p harbor-runtime usage'));
      await tester.pump();
      expect(find.text('Show all 20 lines'), findsOneWidget);

      await tester.tap(
        find.text('Compared Codex and Claude Code usage handling'),
      );
      await tester.pump();
      expect(find.text('Show all 20 lines'), findsNothing);
      expect(
        find.text(
          'Compared Codex and Claude Code usage handling\n'
          'Both keep the last figure; Codex also marks it stale.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the exit status is in danger', (tester) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(activityGroup(), initiallyOpen: true),
      );
      final style = tester.widget<Text>(find.text('exit 101')).style!;
      expect(style.color, BbTheme.light().dangerInk);
    });

    testWidgets('a spawn row opens the child', (tester) async {
      String? opened;
      await pumpTranscript(
        tester,
        ActivityGroupView(
          activityGroup(),
          initiallyOpen: true,
          onOpenChild: (id) => opened = id,
        ),
      );
      await tester.tap(find.text('Survey quota handling in Codex'));
      expect(opened, 'child-c7e2');
    });

    testWidgets('running and failed tool rows use the status mark', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        ActivityGroupView(
          ActivityGroup(
            id: 'g',
            rows: const [
              ToolRow(
                id: 'a',
                name: 'read',
                kind: ToolKind.read,
                target: 'a.rs',
              ),
              ToolRow(
                id: 'b',
                name: 'web',
                kind: ToolKind.web,
                target: 'b',
                state: WorkState.failed,
                meta: 'timeout',
              ),
            ],
          ),
          initiallyOpen: true,
        ),
      );
      expect(find.byType(StatusMark), findsNWidgets(2));
      expect(find.text('timeout'), findsOneWidget);
    });
  });

  group('exec output', () {
    testWidgets('clamps, shows all, opens the full output', (tester) async {
      var showAll = 0;
      var full = 0;
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: ExecOutput(
            output: failingOutput(),
            exitCode: 101,
            onShowAll: () => showAll++,
            onOpenFull: () => full++,
          ),
        ),
      );
      expect(find.textContaining('zero_is_not_unknown'), findsNothing);
      expect(find.text('2.1 KB'), findsOneWidget);
      expect(find.text('exited 101'), findsOneWidget);

      await tester.tap(find.text('Show all 20 lines'));
      await tester.pump();
      expect(showAll, 1);
      expect(find.textContaining('zero_is_not_unknown'), findsOneWidget);
      expect(find.text('Show fewer lines'), findsOneWidget);

      await tester.tap(find.text('Open full output'));
      expect(full, 1);
    });

    testWidgets('short output has no clamp button', (tester) async {
      await pumpTranscript(
        tester,
        const ExecOutput(output: ToolOutput(text: 'ok\n'), exitCode: 0),
      );
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.text('Open full output'), findsNothing);
    });
  });

  group('edit row and diff', () {
    testWidgets('counts, callbacks and the diff', (tester) async {
      var review = 0;
      var undo = 0;
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: FileEditRow(
            modifiedEdit(),
            onReviewDiff: () => review++,
            onUndo: () => undo++,
          ),
        ),
      );
      expect(find.text('Edited usage/mod.rs'), findsOneWidget);
      expect(find.text('+8'), findsOneWidget);
      expect(find.text('−3'), findsOneWidget);
      expect(find.byType(DiffView), findsNothing);

      await tester.tap(find.text('Edited usage/mod.rs'));
      await tester.pump();
      expect(find.byType(DiffView), findsOneWidget);

      await tester.tap(find.text('Review diff'));
      await tester.tap(find.text('Undo'));
      expect(review, 1);
      expect(undo, 1);
    });

    testWidgets('shows the last two segments of a Windows or a slash path', (
      tester,
    ) async {
      for (final path in [
        r'C:\repo\src\usage\mod.rs',
        r'C:\repo/src\usage/mod.rs',
        '/repo/src/usage/mod.rs',
      ]) {
        await pumpTranscript(
          tester,
          SingleChildScrollView(
            child: FileEditRow(
              FileEdit(
                id: 'w',
                diff: FileDiff(path: path),
              ),
            ),
          ),
        );
        expect(find.text('Edited usage/mod.rs'), findsOneWidget, reason: path);
      }
    });

    testWidgets('a created file offers Open; an undone edit no Undo', (
      tester,
    ) async {
      var opened = 0;
      await pumpTranscript(
        tester,
        Column(
          children: [
            FileEditRow(createdEdit(), onOpen: () => opened++, onUndo: () {}),
            FileEditRow(modifiedEdit(undone: true), onUndo: () {}),
          ],
        ),
      );
      expect(find.text('Created tests/quota_reconnect.rs'), findsOneWidget);
      await tester.tap(find.text('Open'));
      expect(opened, 1);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Undone'), findsOneWidget);
    });

    testWidgets('the diff numbers lines and strikes removals', (tester) async {
      final diff = modifiedEdit().diff;
      await pumpTranscript(
        tester,
        SingleChildScrollView(child: DiffView(diff)),
      );
      expect(find.text('24'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('183'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      final removed = tester.widget<Text>(
        find.text('    pub last: UsageSnapshot,'),
      );
      expect(removed.style!.decoration, TextDecoration.lineThrough);
      final added = tester.widget<Text>(
        find.text('    pub last: Option<UsageSnapshot>,'),
      );
      expect(added.style!.color, BbTheme.light().constructiveInk);
    });
  });

  group('plan', () {
    testWidgets('one line that opens', (tester) async {
      await pumpTranscript(tester, const PlanChecklist(planItems));
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.textContaining('Survey Codex'), findsNothing);

      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(find.textContaining('Survey Codex'), findsOneWidget);
      expect(find.textContaining('Run the usage tests'), findsOneWidget);

      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(find.textContaining('Survey Codex'), findsNothing);
    });
  });

  group('return lines', () {
    testWidgets('a child result opens the child', (tester) async {
      String? opened;
      await pumpTranscript(
        tester,
        ReturnLine(childResult, onOpen: (id) => opened = id),
      );
      expect(find.textContaining('Map UsageState transitions'), findsOneWidget);
      expect(find.text('Result ready'), findsOneWidget);
      await tester.tap(find.text('Open'));
      expect(opened, 'child-c7e2');
    });

    testWidgets('the interrupted notice resumes', (tester) async {
      var resumed = 0;
      await pumpTranscript(
        tester,
        InterruptedNotice(onResume: () => resumed++),
      );
      expect(find.text('Interrupted by a restart'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      expect(resumed, 1);
    });
  });

  group('transcript list', () {
    Widget list(
      List<TranscriptItem> items,
      TranscriptController controller, {
      TranscriptAnchor? anchor,
    }) => TranscriptList(
      items: items,
      controller: controller,
      initialAnchor: anchor,
    );

    bool atBottom(WidgetTester tester) {
      final p = listPosition(tester);
      return p.maxScrollExtent - p.pixels < 2;
    }

    testWidgets('follows the tail, lets go on scroll, jumps back', (
      tester,
    ) async {
      final controller = TranscriptController();
      addTearDown(controller.dispose);
      await pumpTranscript(tester, list(longTranscript(20), controller));
      await tester.pumpAndSettle();
      expect(listPosition(tester).maxScrollExtent, greaterThan(500));
      expect(atBottom(tester), isTrue);
      expect(find.text('Jump to latest'), findsNothing);
      expect(pillFade, findsNothing);

      // New content keeps it pinned.
      await pumpTranscript(tester, list(longTranscript(21), controller));
      await tester.pumpAndSettle();
      expect(atBottom(tester), isTrue);

      // Scrolling up lets go and shows the button.
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(controller.following, isFalse);
      expect(find.text('Jump to latest'), findsOneWidget);
      // The lines under the pill fade out above it.
      expect(pillFade, findsOneWidget);
      final before = listPosition(tester).pixels;

      await pumpTranscript(tester, list(longTranscript(22), controller));
      await tester.pumpAndSettle();
      expect(listPosition(tester).pixels, closeTo(before, 2));
      expect(atBottom(tester), isFalse);

      await tester.tap(find.text('Jump to latest'));
      await tester.pumpAndSettle();
      expect(atBottom(tester), isTrue);
      expect(controller.following, isTrue);
      expect(find.text('Jump to latest'), findsNothing);
      expect(pillFade, findsNothing);
    });

    testWidgets('restores an anchor', (tester) async {
      final controller = TranscriptController();
      addTearDown(controller.dispose);
      await pumpTranscript(
        tester,
        list(
          longTranscript(60),
          controller,
          anchor: const TranscriptAnchor('u30'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.following, isFalse);
      final anchor = controller.anchor!;
      expect(anchor.itemId, 'u30');
      expect(anchor.offset.abs(), lessThan(2));
      expect(
        find.text('Question number 30 about the quota bar.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'host entries ride on the list: uniform gaps, a boundary below cards',
      (tester) async {
        final entries = [
          TimelineEntry(id: 'c1', builder: (_) => const Text('Summary one')),
          TimelineEntry(id: 'c2', builder: (_) => const Text('Summary two')),
          TimelineEntry(
            id: 'boundary',
            builder: (_) => const Text('Full messages from here'),
          ),
          TimelineEntry(id: 'm1', builder: (_) => const Text('First message')),
        ];
        await pumpTranscript(
          tester,
          TranscriptList(
            entries: entries,
            gapBefore: (prev, id) => id == 'boundary' ? 30 : null,
          ),
          height: 3000,
        );
        await tester.pumpAndSettle();
        double top(String t) => tester.getTopLeft(find.text(t)).dy;
        double bottom(String t) => tester.getBottomLeft(find.text(t)).dy;
        expect(top('Summary two') - bottom('Summary one'), 14);
        expect(top('Full messages from here') - bottom('Summary two'), 30);
        expect(top('First message') - bottom('Full messages from here'), 14);
      },
    );

    testWidgets('the hosts scroll controller and viewport key are used', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final viewport = GlobalKey();
      await pumpTranscript(
        tester,
        TranscriptList(
          entries: [
            for (var i = 0; i < 40; i++)
              TimelineEntry(id: 'e$i', builder: (_) => Text('Row $i')),
          ],
          scroll: scroll,
          viewportKey: viewport,
          gutter: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.hasClients, isTrue);
      expect(viewport.currentContext, isNotNull);
      expect(scroll.position.extentAfter, lessThan(2)); // follows the tail
    });

    testWidgets('grouped layout puts text, edits, then activity', (
      tester,
    ) async {
      final items = <TranscriptItem>[
        userMessage(),
        activityGroup(),
        modifiedEdit(),
        assistantMessage(),
      ];
      Future<List<double>> tops(TurnLayout layout) async {
        await pumpTranscript(
          tester,
          TranscriptList(items: items, layout: layout),
          height: 3000,
        );
        await tester.pumpAndSettle();
        return [
          tester.getTopLeft(find.byType(AssistantProse)).dy,
          tester.getTopLeft(find.byType(FileEditRow)).dy,
          tester.getTopLeft(find.byType(ActivityGroupView)).dy,
        ];
      }

      final chrono = await tops(TurnLayout.chronological);
      expect(chrono[2], lessThan(chrono[1]));
      expect(chrono[1], lessThan(chrono[0]));
      final grouped = await tops(TurnLayout.grouped);
      expect(grouped[0], lessThan(grouped[1]));
      expect(grouped[1], lessThan(grouped[2]));
    });

    testWidgets('renders every item kind', (tester) async {
      final items = <TranscriptItem>[
        userMessage(),
        assistantMessage(),
        activityGroup(),
        modifiedEdit(),
        childResult,
        const SystemLine(id: 's', text: 'Context compacted'),
        const NoticeLine(id: 'n', text: 'Heads up', tone: NoticeTone.warning),
      ];
      await pumpTranscript(
        tester,
        TranscriptList(
          items: items,
          leading: const PlanChecklist(planItems),
          trailing: const InterruptedNotice(),
        ),
        height: 3000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget);
      expect(find.text('Interrupted by a restart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws the plan, and inserts after their item', (tester) async {
      final items = <TranscriptItem>[
        userMessage(),
        assistantMessage(),
        const SystemLine(id: 's', text: 'Context compacted'),
      ];
      await pumpTranscript(
        tester,
        TranscriptList(
          items: items,
          plan: planItems,
          inserts: [
            TranscriptInsert(
              id: 'ins-1',
              afterItemId: items[1].id,
              child: const Text('inserted answers'),
            ),
            const TranscriptInsert(id: 'ins-2', child: Text('at the end')),
          ],
        ),
        height: 3000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Plan'), findsOneWidget);
      final ins = tester.getTopLeft(find.text('inserted answers')).dy;
      final sys = tester.getTopLeft(find.text('Context compacted')).dy;
      final end = tester.getTopLeft(find.text('at the end')).dy;
      expect(ins, lessThan(sys));
      expect(end, greaterThan(sys));
    });
  });

  group('undo that finishes later', () {
    testWidgets('reads Undoing… until the future completes', (tester) async {
      final done = Completer<void>();
      var undo = 0;
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: FileEditRow(
            modifiedEdit(),
            onUndo: () {
              undo++;
              return done.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.text('Undoing…'), findsOneWidget);
      await tester.tap(find.text('Undoing…'));
      await tester.pump();
      expect(undo, 1);
      done.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Undo failed'), findsNothing);
    });

    testWidgets('says Undo failed and allows another try', (tester) async {
      var undo = 0;
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: FileEditRow(
            modifiedEdit(),
            onUndo: () async {
              undo++;
              throw StateError('no');
            },
          ),
        ),
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Undo failed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(undo, 2);
    });

    testWidgets('a refusal shows its message instead of Undo failed', (
      tester,
    ) async {
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: FileEditRow(
            modifiedEdit(),
            onUndo: () async => throw const UndoRefused('The page changed.'),
          ),
        ),
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('The page changed.'), findsOneWidget);
      expect(find.text('Undo failed'), findsNothing);
    });

    testWidgets('a host label, and Open on every edit when asked', (
      tester,
    ) async {
      final base = modifiedEdit();
      await pumpTranscript(
        tester,
        SingleChildScrollView(
          child: FileEditRow(
            FileEdit(
              id: base.id,
              diff: base.diff,
              label: 'Moved Garden plan to trash',
            ),
            onOpen: () {},
            openEveryEdit: true,
          ),
        ),
      );
      expect(find.text('Moved Garden plan to trash'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
