# SizeClassBuilder

Measures its own width and gives its `builder` the `SizeClass` for that width, from the theme's thresholds; this sheet also covers `SizeClass` (the three classes) and `SizeClassScope` (the inherited widget that carries the class down the tree).

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

No demo: not a visual widget.

## Parameters

`SizeClassBuilder` (a `StatelessWidget`):

| Parameter | Type | Notes |
|---|---|---|
| `builder` | `Widget Function(BuildContext context, SizeClass sizeClass)` | required. Gets the class of this widget's own width. The builder's context can read the class again with `SizeClass.of(context)`. |

`SizeClassScope` (an `InheritedWidget`, built by `SizeClassBuilder`):

| Parameter | Type | Notes |
|---|---|---|
| `sizeClass` | `SizeClass` | required. The class the subtree reads. It notifies dependents only when the class changes. |
| `child` | `Widget` | required. |

## Theme roles

`SizeClassBuilder` reads no colour or type role. It reads the thresholds `sizeMedium` and `sizeExpanded` from `BbTheme.of(context)` (`packages/agent_kit/lib/src/theme/size_class.dart:55` and `:61-62`). Those assert that a `BbThemeScope` is above the builder.

## Size classes

`SizeClass` has three values:

| Class | Width |
|---|---|
| `SizeClass.compact` | below `sizeMedium` (600 px) |
| `SizeClass.medium` | from `sizeMedium` to below `sizeExpanded` (600 px up to 1000 px) |
| `SizeClass.expanded` | `sizeExpanded` (1000 px) and wider |

- The thresholds are the theme's `sizeMedium` and `sizeExpanded`, from bb-ui's `KitLayout`. The values 600 and 1000 are stated in `docs/agent-kit.md:125` and asserted in `packages/agent_kit/test/bb_theme_test.dart:65-66`.
- `SizeClass.forWidth(width, {medium = 600, expanded = 1000})` takes the same thresholds as arguments. It is the function the builder uses, with the theme's values. A caller that does not pass them gets the defaults: `packages/agent_kit/lib/src/composer/agent_composer.dart:643` does this.
- An unbounded width (no bounded constraint) counts as `expanded`.
- Layout follows the container's width, never the window.
- Helpers on the enum: `isCompact`, `isMedium`, `isExpanded`, `atLeast(other)` (this class is `other` or wider), `SizeClass.of(context)` (asserts that a builder is above), and `SizeClass.maybeOf(context)` (returns null instead).
- Users in the kit: `chrome/rail_layout.dart:39` (the rail area), `compositions/agent_workbench.dart:391` (the area beside the rail), `composer/approval_bar.dart:212`, `composer/question_prompt.dart:389`, `composer/queued_row.dart:90`, `transcript/transcript_list.dart:506`, and `workspace/agent_workspace.dart:456`. `transcript/transcript_support.dart:89` reads `SizeClass.maybeOf` and falls back to `expanded`.

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
