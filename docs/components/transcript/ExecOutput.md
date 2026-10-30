# ExecOutput

Tool output: a mono block clamped to 12 lines with a fade, and a footer with the size, the exit status, "Show all N lines" and "Open full output".

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/exec_output-dark.png">
  <img alt="A single grey mono line, 'Finished `dev` profile in 0.4s', on a light well, with no footer" src="shots/exec_output-light.png">
</picture>

*Short output with exit code 0: the standalone specimen `ExecOutput(output: ToolOutput(text: ...), exitCode: 0)`. Nothing is clamped, and the footer is empty: there is no `totalBytes`, the exit is not failed, and no callbacks are set.*

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `output` | `ToolOutput` | Required. `text` is split into lines (a trailing empty line is dropped). `totalLines` sets the "Show all N lines" count (the counted lines when null). `totalBytes`, when set, shows the size in the footer. |
| `exitCode` | `int?` | A non-zero value shows "exited N" in the footer, in danger. |
| `clampLines` | `int` | Default 12. Lines shown before the fade. |
| `onShowAll` | `VoidCallback?` | Called when the output is expanded. The block also expands in place either way. |
| `onOpenFull` | `VoidCallback?` | "Open full output". Not drawn when null. |

Behaviour from the code:

- Lines matching `\bFAILED\b`, a line starting with `error`, or `panicked at` are drawn in danger ink.
- When the output is longer than `clampLines` and not expanded, the last 36 px fade out.
- "Show all N lines" becomes "Show fewer lines" when expanded. It appears only when there are lines and the block is clamped or expanded.
- Line height is 18 px, mono 12 px.

## Theme roles

`muted` (output text), `dangerInk` (failed lines and the exit text), `faint` (footer size and separator), `surface2` (well fill), `radii.sm` (corners), `typeScale.uiSmall` (footer text). The fade uses the bb_ui constants `kMaskOpaque` and `kTransparent`, which are not theme roles.

## Size classes

Does not read the size class. The block does not wrap: it scrolls sideways inside its well (`softWrap: false`), and the footer wraps (`Wrap`) when there is no room beside it.

## Accessibility

- `Semantics(container: true, label: 'Output, N lines')`, with `, exited X` added when the exit code is non-zero.
- "Show all" and "Open full output" are `KitTextButton`s, each with its own button semantics and label.
- No keyboard handling in this file.

## Gallery and tests

- Gallery scene: Components. Specimen "Exec output, short" in `TranscriptSpecimens` (`apps/gallery/lib/components/transcript.dart`).
- Golden: `apps/gallery/test/component_shots_test.dart` writes `exec_output`, which takes the second `ExecOutput` in the scene (index 1), light and dark. Index 0 is the clamped output inside the open activity group.
- Other tests, in `packages/agent_kit/test/transcript/transcript_test.dart`: "clamps, shows all, opens the full output" (line 310) and "short output has no clamp button" (338).
- Transcript goldens in `packages/agent_kit/test/goldens/transcript_turn_*.png` and `transcript_states_*.png`.
