# OutlineWhereStrip

The where-am-I strip over the outline: a dot in the chapter's colour, the chapter title, the section after a "›", and a "Contents ▾" label. A tap on the strip opens the contents sheet. Also documented here: `showOutlineContents` (the contents sheet, which has no shot of its own) and `OutlineFlash`, the tint that marks a row a jump has landed on.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/outline_where_strip-dark.png">
  <img alt="Strip with an orange dot, the chapter title Quota bar and Contents at the right" src="shots/outline_where_strip-light.png">
</picture>

*Top of the outline: the strip shows the chapter "Quota bar" with its dot and no section. The gallery's `OutlineController.where` supplies the chapter and section; the scene sits at the top of the first chapter in this shot.*

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `where` | `ValueListenable<OutlineWhere>` (required) | The chapter and section titles and ids at the top of the transcript, with nulls above the first chapter. The strip rebuilds when it changes. Pass `controller.where`. |
| `onTap` | `VoidCallback` (required) | Called when the strip is tapped. The gallery calls `controller.showContents(context)`. |
| `colors` | `Map<String, Color>` | Default `{}`. The dot's colour for each chapter id. A chapter without an entry uses `colors.accent`. `outlineStripColors(context, outline)` builds the map. |

`OutlineWhere` is a record: `chapter` and `section` (titles), and `chapterId` and `sectionId` (ids). Nulls mean above the first chapter (the strip then shows "Chat").

## Behaviour

- Dot: 8 px circle in `colors[chapterId]`, or `accent` when there is none.
- Title: `where.chapter`, or "Chat" when null, in weight 600 (`textPrimary`, `typeScale.ui`). With a section, "  ›  <section>" follows in `textTertiary`.
- Right: "Contents ▾" in `textTertiary`.
- Height 40 px, background `bgSecondary`, bottom rule `border`, horizontal padding `Layout.gutter`. Ellipsised on one line.
- The whole strip is a `Hover` (key `outline-where`) with radius 0 and the tap handler.

## Contents sheet: `showOutlineContents`

`showOutlineContents(context, {required outline, required where, required onChapter, required onSection})` opens a `PickerSheet` through `showPickerSheet`. On desktop it is 440 by 560; on a phone it is 70% of the height. The header reads "Contents · N chapters" (or "1 chapter").

- Each chapter is a `MarkedRow` (key `outline-contents-chapter-<id>`) with its title, and its date range and decision or gist beneath.
- Each section is a row under its chapter, tapping it calls `onSection`.
- The chapter or section at `where` shows a "you're here" tag (`_HereTag`) in `accentText`. The chapter tag shows when the reader is on the chapter and not on a section.
- Tapping a chapter closes the sheet and calls `onChapter`.

`OutlineControllerContents.showContents(context)` (in `outline_list.dart`) calls it with the controller's `outline`, `where.value`, `openChapter` and `openSection`.

## OutlineFlash

`OutlineFlash({required token, required child})` tints a row after a jump lands on it. It holds for a quarter second, then fades over the rest of `OutlineFlash.duration` (1600 ms). A new `token` restarts it. `OutlineList` wraps the rows in `controller.flashKeys` with it.

## Theme roles

Strip: `colors.bgSecondary` (background), `colors.border` (bottom rule), `colors.textPrimary` (chapter title), `colors.textTertiary` (section, "Contents ▾"), `colors.accent` (fallback dot), `typeScale.ui`, `Layout.gutter`.
Contents sheet: `colors.textPrimary`, `colors.textTertiary`, `colors.accentText` (the "you're here" tag), `typeScale.uiSmall`, `typeScale.ui`.

## Size classes

Does not read the size class. The strip is one 40 px line at any width; the title ellipsises. The contents sheet is a phone sheet at 70% height or a 440 by 560 desktop sheet, chosen by `showPickerSheet`, and its list scrolls inside the sheet.

## Accessibility

- The strip is a `Hover` with `onTap`; it has no `Semantics` label of its own, so the text is read as written.
- The contents rows are `MarkedRow`s, each with its title as label.
- No reduced-motion handling in the strip. `OutlineFlash` runs its fade regardless.

## Gallery and tests

- Gallery scene: Outline (`GalleryScene.outline`, `OutlineScene`). The strip sits above the list and its tap calls `showContents`.
- Golden: `apps/gallery/test/component_shots_test.dart` writes `outline_where_strip` (index 0, padding 0), `_light.png` and `_dark.png`. The contents sheet has no shot: the strip's shot shows the strip only, and no `outline_contents` file exists under `docs/components/outline/shots/`.
- Other tests, `packages/agent_kit/test/outline/outline_test.dart`:
  - "the contents name a chapter and jump to it"
  - "a contents section jump reveals its divider and names it"
  - "a jump lands on the item of its anchor and flashes the span"
  - "a jump to an unknown span does nothing"
  - "a jump highlights its target, and the highlight fades"
  - "the contents fit a phone: the list scrolls inside the sheet"
  - The gallery test `apps/gallery/test/outline_scene_test.dart` covers the scene.
