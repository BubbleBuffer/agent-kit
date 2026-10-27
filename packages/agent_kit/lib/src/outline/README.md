# outline

A long chat read as chapters: closed chapters fold to one card, the open one
shows as a heading, sections are dividers, and a strip over the transcript says
where the reader is. Ported from Scratch's agent chat (`outline_*.dart`,
`chat_reader_controller.dart`, `agent_outline.dart`) over neutral models; the
look is Scratch's, in the kit's tokens. Widgets take models and callbacks, never
a backend or a host type. What a menu entry or a card button does is the host's:
it passes `OutlineAction`s and the kit renders them.

Nothing here needs `agent_kit_core`: the models are plain immutable view
models, because no backend supplies an outline yet.

| File | Holds |
|---|---|
| `outline_model.dart` | `Outline`, `OutlineChapter`, `OutlineSection` (stable id, title, summary, decisions, dates, message count, first and last anchor id) |
| `outline_layout.dart` | `OutlineLayout` (rows for an outline, items, anchors and fold state), `OutlineRow` (`ItemRow`, `ChapterRow`, `SectionRow`), `OutlineTarget`, `outlineSegments` |
| `outline_fold.dart` | `OutlineFoldState`: shown, expanded, deferred and collapsing chapters, the stable row keys |
| `outline_controller.dart` | `OutlineController` (owns the fold state and the list controller; `sync`, `jump`, `openChapter`, `openSection`, `toggleMessages`, `where`), `OutlineWhere` |
| `outline_list.dart` | `OutlineList` (the rows in an `AnchoredList`), `OutlineController.showContents`, `outlineStripColors` |
| `outline_chapter_widgets.dart` | `OutlineChapterCard`, `OutlineChapterHeading`, `OutlineSectionDivider`, `OutlineMoreButton`, `OutlineAction`, `outlineColor` |
| `outline_location.dart` | `OutlineWhereStrip`, `OutlineFlash` |
| `outline_contents.dart` | `showOutlineContents`, `showOutlineMenu` |
| `anchored_list.dart` | `AnchoredList`, `AnchoredListController`: index navigation without laying out the rows in between |
| `outline_names.dart`, `decision_line.dart` | internal: the "Name: sentence" title split and the decision line; not exported |

## Anchors

A chapter or section covers the **anchors** from its `first` to its `last` id,
inclusive. An anchor is one entry of the transcript's ordered list of ids
(Scratch uses message ids). The host also says which transcript item shows each
anchor (`anchorOf`): a grouped turn answers for every anchor it holds, and an
item that shows none (a note, an approval, the live reply) stays with the item
before it. Item ids of the pieces of one split turn are `<turn>#<n>`, which the
stable keys fold back into one name.

## Host contract

```dart
final c = OutlineController(vsync: this, mounted: () => mounted, update: setState);
// in build:
c.sync(outline: outline, itemIds: ids, anchorIds: anchors, anchorOf: anchorOf);
// then
OutlineWhereStrip(where: c.where, onTap: () => c.showContents(context), ...)
OutlineList(controller: c, itemBuilder: (context, row) => ..., chapterActions: ...)
```

`sync` lays the rows out, notices chapters that closed since the last build and
keys the rows; the host calls it from `build` before the list reads the layout.
`update` is the host's `setState` (every fold, expand or flash goes through it).
`positionRestore` is bumped by every navigation, so a position restore the host
queued earlier can tell it was overtaken. Message-position keeping, following
the end of a live reply and pending references stay with the host: they need its
store.

## Behaviour

- **Folding.** A closed chapter is a card with its messages hidden; "Show
  messages" unfolds them under it. The open chapter is a heading and cannot fold.
- **Closing around the reader.** A chapter that closes while the reader is
  inside it stays open under "Chapter closed · Fold" until they scroll away or
  tap Fold; any other closed chapter folds on the next frame with a 240 ms
  collapse.
- **Stable keys.** Rows are keyed by the first anchor they carry
  (`chap:first:<id>`, `sec:first:<id>`, `item:<id>`, `item:<id>~<n>`), so a
  section inserted earlier never changes a later row's identity and a folded-away
  item maps to its chapter's card.
- **Jumps.** `jump` unfolds a hidden chapter, scrolls to the span's first shown
  row (a section's divider when named) and flashes the span for 1.6 s. The
  contents and a card's sections use it.
- **Colours.** Chapters and sections take the space colours in turn
  (`outlineColor`); nothing is hard-coded.
- **Not exported:** `outline_names.dart`, `decision_line.dart`, `outlineCountLine`
  and `outlineWhen`.
