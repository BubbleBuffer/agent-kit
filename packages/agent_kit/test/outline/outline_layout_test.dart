// The pure parts of the outline: the models' presentation, the layout of rows
// over items and anchors, and the stable keys.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/outline/outline_model.dart' show outlineWhen;
import 'package:flutter_test/flutter_test.dart';

import 'outline_harness.dart';

void main() {
  group('presentation', () {
    test('a Name: sentence title splits into a name and a gist', () {
      final c = OutlineChapter(
        id: 'a',
        title: 'Quota bar: it flickers on reconnect',
        first: 'm0',
        last: 'm1',
      );
      expect(c.title, 'Quota bar');
      expect(c.gist, 'it flickers on reconnect');
    });

    test('the gist falls back to the first sentence of the summary', () {
      final c = OutlineChapter(
        id: 'a',
        title: 'Reconnect',
        summary: 'It flickers. Then it settles.',
        first: 'm0',
        last: 'm1',
      );
      expect(c.title, 'Reconnect');
      expect(c.gist, 'It flickers.');
      expect(
        OutlineChapter(id: 'b', title: 'T', first: 'm0', last: 'm1').gist,
        isNull,
      );
    });

    test('a section drops its chapter name as a prefix', () {
      final c = OutlineChapter(
        id: 'a',
        title: 'Reconnect',
        first: 'm0',
        last: 'm9',
        sections: const [
          OutlineSection(
            id: 's',
            title: 'Reconnect: backoff',
            first: 'm0',
            last: 'm4',
          ),
        ],
      );
      expect(c.sections.single.title, 'backoff');
      expect(c.sections.single.rawTitle, 'Reconnect: backoff');
    });

    test(
      'the decision is the first one that is not blank or a split label',
      () {
        expect(
          OutlineChapter(
            id: 'a',
            title: 'T',
            first: 'm0',
            last: 'm1',
            decisions: const [
              ' ',
              'No context boundary selected from 3 candidates',
              ' Keep the last figure ',
            ],
          ).decision,
          'Keep the last figure',
        );
      },
    );

    test('dates read as a range', () {
      final start = DateTime(2026, 9, 28, 10);
      expect(outlineWhen(null, null), '');
      expect(outlineWhen(start, null), 'since Sep 28');
      expect(outlineWhen(start, DateTime(2026, 9, 28, 18)), 'Sep 28');
      expect(outlineWhen(start, DateTime(2026, 9, 30, 9)), 'Sep 28 – 30');
      expect(outlineWhen(start, DateTime(2026, 10, 2, 9)), 'Sep 28 – Oct 2');
      final open = OutlineChapter(
        id: 'a',
        title: 'T',
        first: 'm0',
        last: 'm1',
        startedAt: start,
        endedAt: DateTime(2026, 9, 30),
        ongoing: true,
      );
      expect(open.when, 'since Sep 28');
    });
  });

  group('layout', () {
    final outline = fixtureOutline();
    OutlineLayout build({
      Outline? use,
      bool Function(OutlineChapter)? folded,
      int count = 60,
      Map<String, String>? anchors,
      List<String>? items,
    }) => OutlineLayout.build(
      outline: use ?? outline,
      itemIds: items ?? itemsOf(count),
      anchorIds: anchorsOf(count),
      anchorOf: anchors ?? anchorMap(count),
      folded: folded ?? (c) => c.foldedByDefault,
    );

    test('closed chapters fold to one card each', () {
      final layout = build();
      expect(layout.rows.map((r) => r.key), ['chap:c0', 'chap:c1', 'chap:c2']);
      expect(layout.rows.every((r) => r is ChapterRow && r.folded), isTrue);
      // Hidden items still know their chapter.
      expect(layout.chapterOfItem('i25'), 1);
    });

    test('an unfolded chapter shows its sections and items in order', () {
      final layout = build(folded: (c) => c.id != 'c1');
      final keys = layout.rows.map((r) => r.key).toList();
      expect(keys.first, 'chap:c0');
      final at = keys.indexOf('chap:c1');
      expect(keys[at + 1], 'sec:c1s0');
      expect(keys[at + 2], 'item:i20');
      expect(keys.indexOf('sec:c1s1'), at + 12);
      expect(keys.indexOf('item:i30'), keys.indexOf('sec:c1s1') + 1);
      expect(keys.last, 'chap:c2');
      final item = layout.rows[at + 2] as ItemRow;
      expect(item.itemId, 'i20');
      expect(item.chapter, 1);
      expect(item.section, 0);
    });

    test('a turn that runs into the next chapter stays visible', () {
      // Item t holds the last anchor of chapter 0 and the first of chapter 1.
      final anchors = anchorMap(60)
        ..['m19'] = 'turn'
        ..['m20'] = 'turn';
      final items = [for (var n = 0; n < 60; n++) 'i$n']
        ..remove('i19')
        ..remove('i20')
        ..insert(19, 'turn');
      final layout = build(anchors: anchors, items: items);
      expect(layout.rows.map((r) => r.key), contains('item:turn'));
    });

    test('items with no anchor stay with the item before them', () {
      final items = itemsOf(60)..insert(25, 'note');
      final layout = build(items: items, folded: (c) => false);
      final keys = layout.rows.map((r) => r.key).toList();
      expect(keys.indexOf('item:note'), keys.indexOf('item:i24') + 1);
      expect((layout.rows[keys.indexOf('item:note')]).chapter, 1);
    });

    test('target and spanKeys follow the anchors', () {
      final layout = build();
      final target = layout.target('m25', 'm27')!;
      expect(target.itemId, 'i25');
      expect(target.chapter, 1);
      expect(layout.spanKeys('m25', 'm27'), {
        'item:i25',
        'item:i26',
        'item:i27',
      });
      // The ends may come in either order.
      expect(layout.target('m27', 'm25')!.itemId, 'i25');
      expect(layout.target('x', 'y'), isNull);
      expect(layout.spanKeys('x', 'y'), isEmpty);
      expect(layout.rowIndex('chap:c1'), 1);
      expect(layout.rowIndex('item:i25'), isNull);
    });

    test('segments split by chapter and section; none without an outline', () {
      final s = outlineSegments(outline, anchorsOf(60));
      expect(s['m0'], '0.0');
      expect(s['m10'], '0.1');
      expect(s['m45'], '2.0');
      expect(s['m55'], '2.1');
      expect(outlineSegments(Outline.empty, anchorsOf(60)), isEmpty);
      final partial = outlineSegments(
        Outline([outline.chapters[1]]),
        anchorsOf(60),
      );
      expect(partial['m0'], '-');
    });
  });
}
