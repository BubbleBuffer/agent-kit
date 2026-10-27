# bb_tokens

BubbleBuffer design tokens for Flutter: colours, type scale, layout, radii and
motion. Scratch's look is the default.

## Where the colours come from

Every colour is generated. The canonical source is the `agent-kit` profile of
the BubbleBuffer design repository (`BubbleBuffer/BubbleBufferDesign`,
`product-profiles.json`). Three files carry it into this package:

| File | What it is | Edit it? |
|---|---|---|
| `tokens/agent-kit.json` | The profile's resolved light and dark palette, vendored. A `vendored` header names the source repository, the commit and the command. | No, re-vendor it. |
| `tool/generate_colors.dart` | Plain Dart (SDK only). Reads the JSON and writes `lib/src/colors.g.dart`. | Yes. |
| `lib/src/colors.g.dart` | `ProfileColors.light` and `ProfileColors.dark`: every role as a `Color`, shadows as `BoxShadow` lists. | No. |

`lib/tokens.dart` keeps the non-colour tokens (type, spacing, radii, motion,
layout) and the public API. `AppColors` (Scratch's field names) and
`KitInks` are backed by the generated palette; the roles that have no
`AppColors` field (status, diff, context, control colours) are on
`AppColors.palette`. `kTransparent` and `kMaskOpaque` are the only hand-written
colour constants. Widgets read `BbTheme` roles, never raw colours: CI runs
`scripts/check-raw-colours.sh` over `packages/agent_kit`, `packages/bb_ui` and
`apps/`.

## Changing a colour

Cross-repo sync is a command you run, not automation: the design repository
may be private, and this repository's CI cannot reach it.

1. In a checkout of the design repository, change the `agent-kit` profile in
   `plugins/bubblebuffer-design/assets/design-system/product-profiles.json`,
   run `npm run design:generate`, and merge that change.
2. From that checkout, vendor the palette into this repository:

   ```
   node plugins/bubblebuffer-design/skills/bubblebuffer-design-system/scripts/generate-design-css.mjs \
     --profile agent-kit --json <path to this repo>/packages/bb_tokens/tokens/agent-kit.json
   ```

3. In `packages/bb_tokens`, regenerate the Dart colours:

   ```
   dart tool/generate_colors.dart
   ```

4. Commit `tokens/agent-kit.json` and `lib/src/colors.g.dart` together. CI
   regenerates `colors.g.dart` and fails on any difference. Goldens may move;
   re-render them with the manual `workflow_dispatch` run (see
   `docs/agent-kit.md`).

The Scratch-skin mockup's `theme.css` is generated from the same profile; its
`--css <path>` option writes it in the same step as the JSON.
