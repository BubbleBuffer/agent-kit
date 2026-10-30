# OutlineChapterHeading

The heading of a chapter whose messages show in the outline: an open chapter, or a closed one the reader has unfolded. It is a label line over the chapter's title, with an optional menu button. With `closed: true` it shows a "Fold" line instead of the label.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/outline_chapter_heading-dark.png">
  <img alt="Heading: Chapter, since Oct 29, ongoing, over the title Release notes, with a more button at the right" src="shots/outline_chapter_heading-light.png">
</picture>

*Ongoing chapter: "Chapter · since Oct 29 · ongoing" over the title "Release notes", with the menu button at the right. The gallery's third chapter has `ongoing: true`, so `OutlineList` builds this heading instead of a card. The gallery passes `chapterActions`, so the button is shown.*

No shot covers `closed: true` (the "Chapter closed · Fold" line). `OutlineFoldState` uses it for a chapter the reader has just unfolded while its heading is still in view (`fold.deferred`). The chapter keeps this heading until the reader scrolls away from it, and then it folds into a card.

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `chapter` | `OutlineChapter` (required) | Read: `id`, `title`, `when`, `ongoing`. |
| `color` | `Color` (required) | Passed in by `OutlineList`. The build does not read it: no colour is drawn from it. |
| `onMenu` | `VoidCallback?` | Opens the host's menu. The "More" button is left out when it is null. |
| `closed` | `bool` | Default `false`. When true, the first line reads "Chapter closed · Fold" and is tappable. |
| `onFold` | `VoidCallback?` | Called by a tap on "Chapter closed · Fold". Used only when `closed` is true. |

## Behaviour

- Label line: "Chapter · <when> · ongoing" for an ongoing chapter, or "Chapter · <when> · closed" for a closed one. With `closed: true` the line is "Chapter closed · Fold" instead.
- Title: one line, ellipsised, in the display face at `typeScale.h2`.
- The menu button (`outline-chapter-menu-<id>`) appears only when `onMenu` is not null.

`OutlineList` picks this widget for an ongoing chapter (`ongoing` is true), and for a chapter in `fold.deferred` (with `closed: true` and `onFold` set to `fold.foldNow`).

## Theme roles

`colors.textTertiary` (label line and the Fold line), `colors.textPrimary` (title), `typeScale.uiSmall` (label line), `typeScale.h2` (title, through `tsDisplay`), `colors.iconTertiary` (the menu button, through `OutlineMoreButton`).

## Size classes

Does not read the size class. The title ellipsises on one line at any width.

## Accessibility

- The menu button is `OutlineMoreButton`: `Semantics(button: true, label: 'More')` with an `AppTooltip` labelled "More".
- The Fold line is a `Hover` with `onTap` (key `outline-chapter-fold-<id>`). It has no separate semantic label.
- No reduced-motion handling in this file.

## Gallery and tests

- Gallery scene: Outline (`GalleryScene.outline`, `OutlineScene`). The heading is the "Release notes" chapter, the scene's ongoing one.
- Golden: `apps/gallery/test/component_shots_test.dart` writes `outline_chapter_heading` (index 0), `_light.png` and `_dark.png`. The scene is in `g_outline_1600_<theme>.png` and `g_outline_390_<theme>.png`.
- Other tests, `packages/agent_kit/test/outline/outline_test.dart`: "chapter and section menus list the host actions"; "without host actions there is no menu button".
