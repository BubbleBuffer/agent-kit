# HistoryBoundary

The hairline where full messages begin, below the compacted history: an arrow, "Full messages from here" and the number of the first message shown in full.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/history_boundary-dark.png">
  <img alt="Hairline with a down arrow, the text Full messages from here and message 132" src="shots/history_boundary-light.png">
</picture>

*Boundary in the 1600 px scene: a hairline on each side of "Full messages from here", then "message 132". The gallery passes `messageNumber: 132`.*

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `messageNumber` | `int` (required) | One-based number of the first message shown in full. It is written after the text, unless the width is compact. |

## Theme roles

`thread` (the two hairlines), `ink` (the "Full messages from here" text, weight 600), `faint` (the message number), `colors.iconSecondary` (the arrow), `typeScale.uiSmall`.

## Size classes

The widget reads `sizeClassOf(context).isCompact`. Compact widths leave out "message N"; the text and both hairlines stay.

## Accessibility

- The row is a `Semantics` container labelled "Full messages start here, from message N". Its visible children are excluded from semantics (`ExcludeSemantics`), so the label is read in place of the visible text.
- No keyboard or tap handling.
- No reduced-motion handling in this file.

## Gallery and tests

- Gallery scene: History (`GalleryScene.history`, `HistoryScene`). It is the `boundary` entry of the scene's timeline, with `messageNumber: 132`, and it is the scene's initial anchor.
- Golden: `apps/gallery/test/component_shots_test.dart` writes `history_boundary` (index 0), `_light.png` and `_dark.png`. The whole scene is in `h_history_1600_<theme>.png` and `h_history_390_<theme>.png`.
- Other tests, `packages/agent_kit/test/history/history_test.dart`:
  - "names the first full message"
  - "leaves the number out when compact"
