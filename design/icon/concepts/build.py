"""Generates the four agent-kit icon concepts (glyph.svg + tile.svg each).

Family rules taken from the BubblePaw and Scratch glyphs: milk body #FFFAF1,
charcoal outline #282A2F with square caps and bevel joins, cut (chamfered)
corners, calico ears (charcoal left, apricot right), one apricot accent, quiet
lower facet #E4DCCF, tile #F2EBDD with the glyph at 80% of the tile height.
Only straight-line geometry, plus Lucide `arrow-up` (ISC) copied verbatim.
Run: python build.py
"""
import os

MILK, FACET, INK, APR, TILE = "#FFFAF1", "#E4DCCF", "#282A2F", "#DE945F", "#F2EBDD"
SW = 50  # outline stroke in glyph units (Scratch: 54.5 on an ~800 wide glyph)
HERE = os.path.dirname(os.path.abspath(__file__))


def pts(p):
    return " ".join(f"{x:g},{y:g}" for x, y in p)


def poly(p, fill="none", stroke=None, sw=SW):
    s = f' stroke="{stroke}" stroke-width="{sw:g}" stroke-linecap="square" stroke-linejoin="bevel"' if stroke else ""
    return f'<polygon points="{pts(p)}" fill="{fill}"{s}/>'


def chamfer(x, y, w, h, c):
    return [(x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
            (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c)]


def eared(x0, T, W, bottom, c):
    """Cat-eared head outline (Scratch cover proportions). Returns outline, ear patches, bbox."""
    H = 0.30 * W
    yc, yn = T + H, T + 0.72 * H
    o = [(x0, yc), (x0 + .097 * W, T), (x0 + .177 * W, T), (x0 + .379 * W, yn),
         (x0 + .621 * W, yn), (x0 + .823 * W, T), (x0 + .903 * W, T), (x0 + W, yc),
         (x0 + W, bottom - c), (x0 + W - c, bottom), (x0 + c, bottom), (x0, bottom - c)]
    left = [(x0, yc), (x0 + .097 * W, T), (x0 + .177 * W, T), (x0 + .379 * W, yn), (x0 + .24 * W, yc + 6)]
    right = [(x0 + W, yc), (x0 + .903 * W, T), (x0 + .823 * W, T), (x0 + .621 * W, yn), (x0 + .76 * W, yc + 6)]
    return o, left, right, yc


def head(x0, T, W, bottom, c=50, facet=True):
    o, l, r, yc = eared(x0, T, W, bottom, c)
    g = [poly(o, MILK)]
    if facet:
        g.append(poly([(x0, bottom - 90), (x0 + c + 40, bottom - 40), (x0 + W, bottom - 40),
                       (x0 + W - c, bottom), (x0 + c, bottom), (x0, bottom - c)], FACET))
    g += [poly(l, INK), poly(r, APR), poly(o, "none", INK)]
    return "".join(g)


def line(x1, y1, x2, y2, col=INK, sw=40):
    return (f'<line x1="{x1:g}" y1="{y1:g}" x2="{x2:g}" y2="{y2:g}" stroke="{col}" '
            f'stroke-width="{sw:g}" stroke-linecap="square"/>')


def rect(x, y, w, h, fill):
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="{fill}"/>'


# bbox below is (x0, y0, x1, y1) of the outline centre line
def c1():  # transcript: a cat-eared chat bubble
    body = head(150, 110, 700, 720)
    tail = (poly([(240, 700), (240, 860), (400, 700)], MILK, INK) +
            poly([(250, 700), (250, 700), (390, 700)], "none"))
    # redraw the bubble's bottom edge over the tail seam so the tail joins the body
    inner = line(270, 450, 640, 450) + line(270, 550, 480, 550) + rect(520, 515, 44, 70, APR)
    return tail + head(150, 110, 700, 720) + inner, (150, 110, 850, 860)


def c2():  # stack: context layers behind a cat-eared transcript panel
    back2 = poly(chamfer(250, 640, 500, 200, 40), MILK, INK)
    back1 = poly(chamfer(200, 560, 600, 200, 44), MILK, INK)
    front = head(150, 110, 700, 620)
    inner = line(270, 440, 600, 440) + rect(270, 500, 160, 44, APR)
    return back2 + back1 + front + inner, (150, 110, 850, 840)


def arrow(cx, cy, size, col=INK, sw=44):  # Lucide arrow-up, ISC, paths verbatim
    k = size / 24
    return (f'<g transform="translate({cx - size / 2:g} {cy - size / 2:g}) scale({k:g})" fill="none" '
            f'stroke="{col}" stroke-width="{sw / k:g}" stroke-linecap="square" stroke-linejoin="bevel">'
            f'<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/></g>')


def c3():  # composer: cat-eared input with caret and send
    body = head(100, 230, 800, 740, facet=False)
    caret = rect(190, 560, 44, 100, APR)
    text = line(290, 610, 520, 610)
    send = poly(chamfer(660, 520, 190, 190, 40), APR, INK, 36)
    return body + caret + text + send + arrow(755, 615, 110, INK, 26), (100, 230, 900, 740)


def c4():  # kit: 2x2 widget tiles, the top-left one eared, the last one apricot
    t = 300
    a = head(150, 110, t, 500, 40, facet=False)
    b = poly(chamfer(550, 200, t, t, 40), MILK, INK)
    c = poly(chamfer(150, 600, t, t, 40), MILK, INK)
    d = poly(chamfer(550, 600, t, t, 40), APR, INK)
    inner = line(220, 390, 380, 390, INK, 36) + line(620, 350, 780, 350, INK, 36) + line(220, 750, 380, 750, INK, 36)
    return a + b + c + d + inner, (150, 110, 850, 900)


CONCEPTS = [
    ("1-transcript", c1, "A cat-eared chat bubble with an apricot caret: the transcript, the kit's centre."),
    ("2-stack", c2, "Cat-eared transcript panel over two context layers: transcript plus context and workspace."),
    ("3-composer", c3, "A cat-eared prompt field with caret and a send button (Lucide arrow-up, ISC): the composer."),
    ("4-kit", c4, "A 2x2 grid of widget tiles, one eared, one apricot: parts that compose into an app."),
]


def write(name, svg_fn, why):
    body, (x0, y0, x1, y1) = svg_fn()
    pad = SW / 2 + 0.04 * max(x1 - x0, y1 - y0)
    vx, vy, vw, vh = x0 - pad, y0 - pad, x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    d = os.path.join(HERE, name)
    os.makedirs(d, exist_ok=True)
    head_ = '<svg xmlns="http://www.w3.org/2000/svg" '
    with open(os.path.join(d, "glyph.svg"), "w", newline="\n") as f:
        f.write(f'{head_}viewBox="{vx:g} {vy:g} {vw:g} {vh:g}"><title>agent-kit {name}</title>'
                f'<desc>{why}</desc>{body}</svg>\n')
    k = 1024 / max(x1 - x0 + SW, y1 - y0 + SW)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    with open(os.path.join(d, "tile.svg"), "w", newline="\n") as f:
        f.write(f'{head_}viewBox="0 0 1280 1280"><title>agent-kit {name} tile</title><desc>{why}</desc>'
                f'<rect width="1280" height="1280" fill="{TILE}"/>'
                f'<g transform="translate(640 640) scale({k:.4f}) translate({-cx:g} {-cy:g})">{body}</g></svg>\n')
    with open(os.path.join(d, "RATIONALE.txt"), "w", newline="\n") as f:
        f.write(why + "\n")


if __name__ == "__main__":
    for n, fn, why in CONCEPTS:
        write(n, fn, why)
