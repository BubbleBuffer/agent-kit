# SizeClassBuilder

Measures its own width and gives its `builder` the `SizeClass` for that width; this sheet also covers `SizeClass` (the three classes) and `SizeClassScope` (the inherited widget that carries the class down the tree). Both are bb-ui's (`bb_tokens`); `agent_kit` re-exports them.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

No demo: not a visual widget.

## Parameters

`SizeClassBuilder` (a `StatelessWidget`):

| Parameter | Type | Notes |
|---|---|---|
| `builder` | `Widget Function(BuildContext context, SizeClass sizeClass)` | required. Gets the class of this widget's own width. The builder's context can read the class again with `sizeClassOf(context)` or `context.sizeClass`. |

`SizeClassScope` (bb-ui's `InheritedWidget`, built by `SizeClassBuilder`):

| Parameter | Type | Notes |
|---|---|---|
| `sizeClass` | `SizeClass` | required. The class the subtree reads. It notifies dependents only when the class changes. |
| `child` | `Widget` | required. |

## Theme roles

`SizeClassBuilder` reads no theme value: the thresholds are bb-ui's `SizeClass.mediumWidth` (600) and `SizeClass.expandedWidth` (1000).

## Size classes

`SizeClass` has three values:

| Class | Width |
|---|---|
| `SizeClass.compact` | below 600 px |
| `SizeClass.medium` | 600 px up to 1000 px |
| `SizeClass.expanded` | 1000 px and wider |

- `SizeClass.forWidth(width)` is the function the builder uses. An unbounded width (no bounded constraint) counts as `expanded`.
- Layout follows the container's width, never the window.
- Helpers: bb-ui's `isCompact` and `atLeast(other)`; the kit's `KitSizeClass` extension adds `isMedium` and `isExpanded`. `sizeClassOf(context)` returns the nearest scope's class, or `expanded` when there is none; bb-ui's `context.sizeClass` falls back to the window's class instead.
- Users in the kit: `chrome/rail_layout.dart` (the rail area), `compositions/agent_workbench.dart` (the area beside the rail), `composer/approval_bar.dart`, `composer/question_prompt.dart`, `composer/queued_row.dart`, `transcript/transcript_list.dart` and `workspace/agent_workspace.dart`. The transcript rows read `sizeClassOf`.

## Accessibility

None in the code.

## Gallery and tests

- Gallery:
  - `apps/gallery/lib/src/scenes.dart:227` (`_AreaLine`) shows the width of its area and the class it gets: `Area <width> px → <class>`.
  - `apps/gallery/lib/components/context.dart:74`, `apps/gallery/lib/components/transcript.dart:18` and `apps/gallery/lib/src/outline_scene.dart:148` wrap their specimens in a `SizeClassBuilder`.
  - The workbench scenes (A, C and F) use it through `AgentWorkbench` (`apps/gallery/lib/src/scenes.dart:127-151`).
- Golden: no shot. The scene goldens in `apps/gallery/test/scenes_golden_test.dart` (scenes at 390, 1000, 1440 and 1600 px) show the classes through the layout they produce.
- Other tests:
  - `packages/agent_kit/test/size_class_test.dart`: the thresholds (599.9, 600, 999.9, 1000 and 1600 px), `atLeast`, and the builder measuring its own container and not the window (`:21`).
  - `packages/agent_kit/test/history/history_test.dart:56` and `packages/agent_kit/test/transcript/harness.dart:37` wrap widgets in a `SizeClassBuilder`.
  - `packages/agent_kit/test/compositions/agent_workbench_test.dart` checks the workbench's ledger or strip by width (expanded, medium and compact).
