// The outline in a host: folding a chapter's messages in and out with stable
// keys, the where-am-I strip, the contents reaching far chapters and sections,
// jumps landing on their anchor, the flash, host actions and the empty state.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart' show Ico;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outline_harness.dart';

Finder _strip(String text) => find.descendant(
  of: keyed('outline-where'),
  matching: find.textContaining(text),
);

/// The tint a flashing row paints: its wrapper's own box, the first one.
Color _tint(WidgetTester tester, Finder flash) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: flash, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('a closed chapter shows as a card, its messages open under it', (
    tester,
  ) async {
    await pumpOutline(tester);

    expect(keyed('outline-chapter-c0'), findsOneWidget);
    expect(find.textContaining('Message 0'), findsNothing);
    expect(find.text('Show messages'), findsWidgets);

    await tester.tap(keyed('outline-card-show-c0'));
    await tester.pump();
    expect(find.text('Hide messages'), findsOneWidget);
    expect(find.text('Message 0'), findsOneWidget);
    // The section divider shows with the messages.
    expect(keyed('outline-section-sec:c0s0'), findsOneWidget);

    await tester.tap(keyed('outline-card-show-c0'));
    await tester.pump();
    await tester.pump(OutlineFoldState.collapseDuration);
    expect(find.text('Message 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folding and unfolding keeps the other rows keys stable', (
    tester,
  ) async {
    final host = await pumpOutline(
      tester,
      outline: fixtureOutline(perChapter: 4),
      count: 12,
    );
    final fold = host.controller.fold;
    final folded = List.of(fold.stableKeys);
    expect(folded, ['chap:first:m0', 'chap:first:m4', 'chap:first:m8']);

    await tester.tap(keyed('outline-card-show-c0'));
    await tester.pump();
    final unfolded = List.of(fold.stableKeys);
    // The chapter's own key and the later chapters' keys do not change; the
    // new keys are the messages and sections, named by their first anchor.
    expect(unfolded.first, 'chap:first:m0');
    expect(unfolded.sublist(unfolded.length - 2), [
      'chap:first:m4',
      'chap:first:m8',
    ]);
    expect(unfolded, contains('sec:first:m0'));
    expect(unfolded, contains('item:m0'));
    expect(unfolded, contains('sec:first:m2'));
    expect(unfolded.toSet().length, unfolded.length);
    // The rows keep their place: the key now at an index is the row there.
    expect(fold.indexOfKey('item:m1'), unfolded.indexOf('item:m1'));
    expect(fold.indexOfKey('chap:first:m4'), unfolded.length - 2);
    expect(keyed('outline-chapter-c1'), findsOneWidget);
    expect(keyed('outline-chapter-c2'), findsOneWidget);

    await tester.tap(keyed('outline-card-show-c0'));
    await tester.pump();
    await tester.pump(OutlineFoldState.collapseDuration);
    expect(fold.stableKeys, folded);
    // A message seen before and folded away now maps to its chapter's card, so
    // the list rebases there instead of losing its place.
    expect(fold.indexOfKey('item:m1'), 0);
    expect(fold.indexOfKey('nothing'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the contents name a chapter and jump to it', (tester) async {
    final host = await pumpOutline(tester);
    // The strip starts on the first chapter, the top row.
    expect(_strip('Chapter 0'), findsOneWidget);

    await tester.tap(keyed('outline-where'));
    await tester.pumpAndSettle();
    expect(keyed('outline-contents'), findsOneWidget);
    expect(find.textContaining('Contents · 3 chapters'), findsOneWidget);
    await tester.tap(keyed('outline-contents-chapter-c2'));
    await tester.pumpAndSettle();

    expect(_strip('Chapter 2'), findsOneWidget);
    // The chapter unfolds under its card; chapter 0 stays folded.
    expect(find.textContaining('Message 40'), findsWidgets);
    expect(find.textContaining('Message 0'), findsNothing);
    expect(host.controller.flashKeys, {'chap:c2'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a contents section jump reveals its divider and names it', (
    tester,
  ) async {
    await pumpOutline(tester);

    await tester.tap(keyed('outline-where'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('outline-contents-section-c1s1'));
    await tester.pumpAndSettle();

    expect(keyed('outline-section-sec:c1s1'), findsOneWidget);
    expect(_strip('Section 1.1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a jump lands on the item of its anchor and flashes the span', (
    tester,
  ) async {
    final host = await pumpOutline(tester);
    final c = host.controller;

    final done = c.jump('m25', 'm26');
    await tester.pump();
    await tester.pump();
    await done;
    await tester.pump();

    // Chapter 1 was folded: it is shown, and the target is on screen.
    expect(c.fold.hidden(c.outline.chapters[1]), isFalse);
    expect(keyed('msg-i25'), findsOneWidget);
    expect(c.flashKeys, {'item:i25', 'item:i26'});
    expect(c.layout!.target('m25', 'm26')!.itemId, 'i25');
    expect(c.layout!.rowIndex('item:i25'), isNotNull);
    // The top of the list is the span's first row, in section 1 of chapter 1.
    expect(_strip('Chapter 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a jump to an unknown span does nothing', (tester) async {
    final host = await pumpOutline(tester);
    final before = host.controller.flashToken;
    await host.controller.jump('nope', 'nada');
    await tester.pump();
    expect(host.controller.flashToken, before);
    expect(host.controller.flashKeys, isEmpty);
  });

  testWidgets('a jump highlights its target, and the highlight fades', (
    tester,
  ) async {
    await pumpOutline(tester);

    await tester.tap(keyed('outline-where'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('outline-contents-chapter-c2'));
    await tester.pump();
    final flash = find.ancestor(
      of: keyed('outline-chapter-c2'),
      matching: find.byType(OutlineFlash),
    );
    for (var i = 0; i < 60 && flash.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(flash, findsOneWidget);
    expect(_tint(tester, flash).a, greaterThan(0));

    await tester.pump(OutlineFlash.duration);
    expect(_tint(tester, flash).a, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host actions appear on an open card and fire', (tester) async {
    final fired = <String>[];
    await pumpOutline(
      tester,
      cardActions: (chapter) => [
        OutlineAction(
          label: 'File it',
          onSelected: () => fired.add('card ${chapter.id}'),
        ),
      ],
    );

    // A closed card shows no host action; opening it adds the button.
    expect(find.text('File it'), findsNothing);
    await tester.tap(keyed('outline-card-face-c0'));
    await tester.pumpAndSettle();
    expect(find.text('File it'), findsOneWidget);
    await tester.tap(keyed('outline-card-action-c0-0'));
    await tester.pump();
    expect(fired, ['card c0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter and section menus list the host actions', (
    tester,
  ) async {
    final fired = <String>[];
    await pumpOutline(
      tester,
      outline: fixtureOutline(ongoingLast: true),
      chapterActions: (chapter) => [
        OutlineAction(
          label: 'Chapter action',
          icon: Ico.plus,
          onSelected: () => fired.add('chapter ${chapter.id}'),
        ),
      ],
      sectionActions: (chapter, section) => [
        OutlineAction(
          label: 'Section action',
          onSelected: () => fired.add('section ${section.id}'),
        ),
      ],
    );

    // The open chapter is a heading with a menu; its sections show too.
    await tester.tap(keyed('outline-chapter-menu-c2'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter action'), findsOneWidget);
    await tester.tap(find.text('Chapter action'));
    await tester.pumpAndSettle();
    expect(fired, ['chapter c2']);
    // The sheet closed before the action ran.
    expect(find.text('Chapter action'), findsNothing);

    await tester.tap(keyed('outline-section-menu-c2s0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section action'));
    await tester.pumpAndSettle();
    expect(fired, ['chapter c2', 'section c2s0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without host actions there is no menu button', (tester) async {
    await pumpOutline(tester, outline: fixtureOutline(ongoingLast: true));
    expect(keyed('outline-chapter-c2'), findsOneWidget);
    expect(keyed('outline-chapter-menu-c2'), findsNothing);
    expect(keyed('outline-section-menu-c2s0'), findsNothing);
  });

  testWidgets('an empty outline shows only the items', (tester) async {
    final host = await pumpOutline(tester, outline: Outline.empty, count: 6);

    expect(host.controller.layout!.rows, everyElement(isA<ItemRow>()));
    expect(host.controller.layout!.rows, hasLength(6));
    expect(find.text('Message 0'), findsOneWidget);
    expect(find.text('Show messages'), findsNothing);
    expect(_strip('Chat'), findsOneWidget);
    expect(host.controller.where.value.chapter, isNull);

    await tester.tap(keyed('outline-where'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contents · 0 chapters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chapter that closes while the reader is inside it stays', (
    tester,
  ) async {
    final host = await pumpOutline(
      tester,
      outline: fixtureOutline(ongoingLast: true),
    );
    final c = host.controller;
    expect(c.fold.openFirsts, {'m40'});
    final closed = fixtureOutline();
    // The reader is looking at an anchor inside the chapter that now closes.
    c.fold.closeFolds(closed, {'m40'}, anchorsOf(60), 'm45');
    expect(c.fold.deferred, {'m40'});
    expect(c.fold.shown['m40'], isTrue);
    expect(c.fold.hidden(closed.chapters[2]), isFalse);

    // Folding by hand collapses it on the next frame, then hides it.
    c.fold.foldNow('m40');
    await tester.pump();
    await tester.pump();
    expect(c.fold.collapsing.containsKey('m40'), isTrue);
    await tester.pumpAndSettle();
    expect(c.fold.collapsing, isEmpty);
    expect(c.fold.shown.containsKey('m40'), isFalse);
    expect(c.fold.hidden(closed.chapters[2]), isTrue);
  });

  testWidgets('the contents fit a phone: the list scrolls inside the sheet', (
    tester,
  ) async {
    await pumpOutline(tester, size: const Size(390, 780));

    await tester.tap(keyed('outline-where'));
    await tester.pumpAndSettle();
    expect(keyed('outline-contents-scroll'), findsOneWidget);
    await tester.tap(keyed('outline-contents-chapter-c2'));
    await tester.pumpAndSettle();
    expect(_strip('Chapter 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
