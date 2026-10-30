"""Rebuilds the agent-kit icon: glyph/agent-kit-glyph.svg and tile/agent-kit-tile.svg.

Concept "Stack": a cat-eared transcript panel over two context layers. Family
rules from the BubblePaw and Scratch glyphs: milk body #FFFAF1, charcoal outline
#282A2F with square caps and bevel joins, cut corners, calico ears (charcoal
left, apricot right), one apricot accent, quiet lower facet #E4DCCF, tile
#F2EBDD (square, full-bleed) with the glyph at 80% of the tile height.
Straight-line geometry only. Run from anywhere: python build.py
"""
import os

MILK, FACET, INK, APR, TILE = "#FFFAF1", "#E4DCCF", "#282A2F", "#DE945F", "#F2EBDD"
SW = 50
HERE = os.path.dirname(os.path.abspath(__file__))
WHY = "Cat-eared transcript panel over two context layers: transcript plus context and workspace."


def pts(p):
    return " ".join(f"{x:g},{y:g}" for x, y in p)


def poly(p, fill="none", stroke=None, sw=SW):
    s = f' stroke="{stroke}" stroke-width="{sw:g}" stroke-linecap="square" stroke-linejoin="bevel"' if stroke else ""
    return f'<polygon points="{pts(p)}" fill="{fill}"{s}/>'


def chamfer(x, y, w, h, c):
    return [(x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
            (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c)]


def head(x0, T, W, bottom, c=50):
    H = 0.30 * W
    yc, yn = T + H, T + 0.72 * H
    o = [(x0, yc), (x0 + .097 * W, T), (x0 + .177 * W, T), (x0 + .379 * W, yn),
         (x0 + .621 * W, yn), (x0 + .823 * W, T), (x0 + .903 * W, T), (x0 + W, yc),
         (x0 + W, bottom - c), (x0 + W - c, bottom), (x0 + c, bottom), (x0, bottom - c)]
    left = [(x0, yc), (x0 + .097 * W, T), (x0 + .177 * W, T), (x0 + .379 * W, yn), (x0 + .24 * W, yc + 6)]
    right = [(x0 + W, yc), (x0 + .903 * W, T), (x0 + .823 * W, T), (x0 + .621 * W, yn), (x0 + .76 * W, yc + 6)]
    facet = [(x0, bottom - 90), (x0 + c + 40, bottom - 40), (x0 + W, bottom - 40),
             (x0 + W - c, bottom), (x0 + c, bottom), (x0, bottom - c)]
    return poly(o, MILK) + poly(facet, FACET) + poly(left, INK) + poly(right, APR) + poly(o, "none", INK)


def line(x1, y1, x2, y2):
    return (f'<line x1="{x1:g}" y1="{y1:g}" x2="{x2:g}" y2="{y2:g}" stroke="{INK}" '
            f'stroke-width="40" stroke-linecap="square"/>')


def art():
    back2 = poly(chamfer(250, 640, 500, 200, 40), MILK, INK)
    back1 = poly(chamfer(200, 560, 600, 200, 44), MILK, INK)
    inner = line(270, 440, 600, 440) + f'<rect x="270" y="500" width="160" height="44" fill="{APR}"/>'
    return back2 + back1 + head(150, 110, 700, 620) + inner, (150, 110, 850, 840)


def main():
    body, (x0, y0, x1, y1) = art()
    pad = SW / 2 + 0.04 * max(x1 - x0, y1 - y0)
    ns = '<svg xmlns="http://www.w3.org/2000/svg" '
    with open(os.path.join(HERE, "glyph", "agent-kit-glyph.svg"), "w", newline="\n") as f:
        f.write(f'{ns}viewBox="{x0 - pad:g} {y0 - pad:g} {x1 - x0 + 2 * pad:g} {y1 - y0 + 2 * pad:g}">'
                f'<title>agent-kit</title><desc>{WHY}</desc>{body}</svg>\n')
    k = 1024 / max(x1 - x0 + SW, y1 - y0 + SW)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    with open(os.path.join(HERE, "tile", "agent-kit-tile.svg"), "w", newline="\n") as f:
        f.write(f'{ns}viewBox="0 0 1280 1280"><title>agent-kit tile</title><desc>{WHY}</desc>'
                f'<rect width="1280" height="1280" fill="{TILE}"/>'
                f'<g transform="translate(640 640) scale({k:.4f}) translate({-cx:g} {-cy:g})">{body}</g></svg>\n')


if __name__ == "__main__":
    main()
