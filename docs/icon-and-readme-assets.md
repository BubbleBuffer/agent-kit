# Icon and README assets

- `design/icon/glyph/agent-kit-glyph.svg` is the kit's glyph and `design/icon/tile/agent-kit-tile.svg` the app tile (square, full-bleed, glyph at 80% of the tile height, like the other BubbleBuffer icons). Both come from `design/icon/build.py`, which draws the cat-eared transcript panel over two context layers from straight-line geometry. Run `python design/icon/build.py` to rebuild them.
- `design/readme/agent-kit-{light,dark}.svg` is the README lockup: the glyph plus the name in Bricolage Grotesque (wght 700, opsz 96), set as outlines. Rebuild it with `design/readme/wordmark.py` (needs fontTools):

  ```sh
  python design/readme/wordmark.py --glyph design/icon/glyph/agent-kit-glyph.svg \
    --font "apps/gallery/assets/fonts/BricolageGrotesque[opsz,wdth,wght].ttf" \
    --axes wght=700,opsz=96 --text agent-kit --out design/readme --name agent-kit
  ```

- `design/readme/shots/` holds copies of committed goldens (`apps/gallery/test/goldens/a_workbench_1440_*`, `c_phone_390_*`; `packages/agent_kit/test/goldens/composer_1000_*` cropped to 690 px high, `context_now_680_*`). Refresh them from the goldens after a UI change.
