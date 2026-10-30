# CrewStrip

A horizontal strip of chips, one per child agent or background job, that opens them. It draws nothing when there are no agents or jobs.

```dart
import 'package:agent_kit/agent_kit.dart';
```

## Demo

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/crew_strip_expanded-dark.png">
  <img alt="Crew strip at 1000 px with agent and job chips" src="shots/crew_strip_expanded-light.png">
</picture>

*Expanded, 1000 px: one chip per agent and job, with their titles ("Survey quota", "Map transitions" in the gallery data).*

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/crew_strip_compact-dark.png">
  <img alt="Crew strip at 390 px scrolled sideways, with the third chip cut off" src="shots/crew_strip_compact-light.png">
</picture>

*Compact, 390 px: the same chips in a strip that scrolls sideways. The third chip is cut off at the right edge, which is the scroll.*

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="shots/crew_strip_asking_parent-dark.png">
  <img alt="Crew strip with one chip for an agent that is asking its parent a question" src="shots/crew_strip_asking_parent-light.png">
</picture>

*Asking parent: a child agent waiting on its parent. The gallery frame shows that state.*

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `agents` | `List<ChildAgent>` | Default `[]`. The child agents. |
| `jobs` | `List<BackgroundJob>` | Default `[]`. The background jobs. |
| `now` | `DateTime?` | The clock for elapsed time. |
| `agentTitle` | `String Function(ChildAgent agent)?` | The chip title for an agent. |
| `jobTitle` | `String Function(BackgroundJob job)?` | The chip title for a job. |
| `onOpenAgent` | `ValueChanged<ChildAgent>?` | Called when an agent chip is tapped. |
| `onOpenJob` | `ValueChanged<BackgroundJob>?` | Called when a job chip is tapped. |

## Theme roles

`BbTheme` roles read in `crew_strip.dart`:

- `ink`, `hover`, `pressed`, `seam`, `colors.borderSubtle`, `colors.iconSecondary`
- `radii.pill` (chip shape), `typeScale.uiSmall`, `formFactor`
- Each chip's mark is a `StatusMark` or `StatusMark.work` (`crew_strip.dart:53`, `:62`). `StatusMark` uses `askingParent` for an agent waiting on its parent (`status/status_mark.dart:111`).

## Size classes

- Height: 40 px, or 32 px on touch (`crew_strip.dart:46`).
- Chip height: 26 px, or 24 px on touch.
- Title maximum width: 180 px. Tag maximum width: 140 px.
- The strip scrolls horizontally with its scrollbars off. The compact crop shows the scroll.

## Accessibility

- The strip's semantics label is the heading from `crewHeading(...)`, which reads `Still running` or `Crew`.
- Chip keys: `crew-agent-<id>` and `crew-job-<id>`.
- Each chip is a tap target that calls `onOpenAgent` or `onOpenJob`.

## Gallery and tests

- Gallery scene: the Components scene (`apps/gallery/lib/src/components_scene.dart`). Specimens: `ChromeSpecimens` in `apps/gallery/lib/components/chrome.dart` (1000 px and 390 px, with `agentTitle: 'Survey quota'` and `'Map transitions'`), and the asking-parent specimen in `apps/gallery/lib/components/context.dart`.
- Golden shots: `apps/gallery/test/component_shots_test.dart` writes `crew_strip_expanded` (CrewStrip 1), `crew_strip_compact` (CrewStrip 2) and `crew_strip_asking_parent` (CrewStrip 0 from the context specimens) to `apps/gallery/test/goldens/shots/`. `scenes_golden_test.dart` covers the sheet as `components_1000_light.png` and `components_1000_dark.png`.
- `packages/agent_kit/test/chrome/chrome_test.dart`: "the strip shows a chip per agent and job and opens them" and "the strip scrolls sideways when narrow".
- `packages/agent_kit/test/chrome/chrome_golden_test.dart`: `chrome_crew_1000_<brightness>.png` and `chrome_crew_390_<brightness>.png` in `packages/agent_kit/test/goldens/`.
- `packages/agent_kit/test/compositions/agent_workbench_test.dart` (crew group) and `packages/agent_kit/test/transcript/child_question_test.dart` (asking parent group) mention the strip.
