"""Generates the tosk brand art (SVG) in colour and black & white (e-ink).

Run:  python app/tool/brand/make_brand.py   -> app/assets/brand/*.svg

Everything is drawn from the same shapes with two palettes, so the e-ink
versions stay in sync with the colour ones. Pure Python, no dependencies.
"""
from __future__ import annotations

import math
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "assets" / "brand"

COLOR = dict(
    line="#2B1D14", fur="#C9572B", fur2="#E08A43", belly="#F6E7C8", eye="#2B1D14",
    shine="#FFFFFF", nose="#2B1D14", paper="#F3E9D2", ink="#6B4A2F", bark="#6B4A2F",
    bark2="#8A6442", leaf="#5E8C4A", leaf2="#7FAE5F", node="#F6E7C8", bg="none",
    tailtip="#F0B57A", rune="#6B4A2F",
)
MONO = dict(
    line="#000000", fur="#FFFFFF", fur2="#FFFFFF", belly="#FFFFFF", eye="#000000",
    shine="#FFFFFF", nose="#000000", paper="#FFFFFF", ink="#000000", bark="#FFFFFF",
    bark2="#000000", leaf="#FFFFFF", leaf2="#FFFFFF", node="#FFFFFF", bg="none",
    tailtip="#FFFFFF", rune="#000000",
)


def svg(w: int, h: int, body: str, title: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n'
        f"<title>{title}</title>\n{body}\n</svg>\n"
    )


def fat_stroke(d: str, width: float, fill: str, line: str, outline: float = 7) -> str:
    """A thick rounded stroke with an outline: drawn twice (outline, then fill)."""
    return (
        f'<path d="{d}" fill="none" stroke="{line}" stroke-width="{width + 2 * outline}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>\n'
        f'<path d="{d}" fill="none" stroke="{fill}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


# ------------------------------------------------------------------ Tosk

def tosk(p: dict, with_branch: bool = True, with_scroll: bool = True) -> str:
    """Tosk (Ratatosk) sitting on a branch of Yggdrasil, holding a message scroll.

    Coordinate space 512 x 512, facing right.
    """
    L = p["line"]
    sw = 7  # outline width
    parts: list[str] = []

    if with_branch:
        parts.append(branch_piece(p, "M 20 468 C 140 452, 300 462, 492 440", 34))
        parts.append(ash_leaf(p, 452, 436, -35, 1.0))
        parts.append(ash_leaf(p, 70, 470, 200, 0.8))

    # Tail: a fat spiral behind the body, with a lighter inner curl.
    tail = "M 222 412 C 96 418, 52 318, 82 230 C 110 150, 196 104, 252 140 C 296 168, 270 230, 222 214 C 196 205, 204 176, 226 178"
    parts.append(f'<path d="{tail}" fill="none" stroke="{L}" stroke-width="{78 + 2 * sw}" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(f'<ellipse cx="168" cy="292" rx="74" ry="96" fill="{p["fur"]}"/>')  # fills the curl's hollow
    parts.append(f'<path d="{tail}" fill="none" stroke="{p["fur"]}" stroke-width="78" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(
        f'<path d="M 120 330 C 104 280, 118 214, 160 178" fill="none" stroke="{p["fur2"]}" '
        f'stroke-width="16" stroke-linecap="round"/>'
    )
    parts.append(
        f'<path d="M 236 156 C 258 168, 258 196, 236 200" fill="none" stroke="{p["tailtip"]}" '
        f'stroke-width="12" stroke-linecap="round"/>'
    )
    # fur texture (visible in mono as well)
    for d in ("M 92 262 l 18 -6", "M 98 300 l 18 -2", "M 112 214 l 16 -10", "M 150 160 l 14 -14", "M 200 130 l 10 -16"):
        parts.append(f'<path d="{d}" stroke="{L}" stroke-width="5" stroke-linecap="round"/>')

    # Hind leg + foot
    parts.append(f'<ellipse cx="258" cy="402" rx="62" ry="44" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>')
    parts.append(f'<ellipse cx="312" cy="446" rx="50" ry="16" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>')

    # Body
    parts.append(
        f'<ellipse cx="292" cy="330" rx="82" ry="104" transform="rotate(12 292 330)" '
        f'fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>'
    )
    parts.append(
        f'<ellipse cx="320" cy="346" rx="46" ry="76" transform="rotate(12 320 346)" fill="{p["belly"]}"/>'
    )

    # Head
    parts.append(  # ear (back)
        f'<path d="M 300 168 L 296 108 L 330 150 Z" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>'
    )
    parts.append(
        f'<path d="M 296 108 l -8 -18 M 296 108 l 2 -20 M 296 108 l 10 -16" stroke="{L}" stroke-width="5" stroke-linecap="round"/>'
    )
    parts.append(f'<circle cx="338" cy="206" r="64" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>')
    parts.append(  # ear (front) with tuft
        f'<path d="M 336 156 L 348 96 L 372 152 Z" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>'
    )
    parts.append(f'<path d="M 344 142 L 350 112 L 362 146 Z" fill="{p["fur2"]}"/>')
    parts.append(
        f'<path d="M 348 96 l -10 -20 M 348 96 l 2 -24 M 348 96 l 12 -18" stroke="{L}" stroke-width="5" stroke-linecap="round"/>'
    )
    # muzzle
    parts.append(f'<ellipse cx="392" cy="226" rx="36" ry="28" fill="{p["belly"]}" stroke="{L}" stroke-width="{sw}"/>')
    parts.append(f'<ellipse cx="424" cy="214" rx="11" ry="9" fill="{p["nose"]}"/>')
    parts.append(f'<path d="M 404 238 q 10 8 22 0" fill="none" stroke="{L}" stroke-width="5" stroke-linecap="round"/>')
    # cheek
    parts.append(f'<path d="M 330 236 q 16 10 30 4" fill="none" stroke="{L}" stroke-width="5" stroke-linecap="round"/>')
    # eye
    parts.append(f'<circle cx="362" cy="196" r="11" fill="{p["eye"]}"/>')
    parts.append(f'<circle cx="366" cy="192" r="3.5" fill="{p["shine"]}"/>')

    if with_scroll:
        # The message scroll Ratatosk carries up and down the tree (a little rune on it).
        parts.append(
            f'<g transform="rotate(-16 384 312)">'
            f'<rect x="326" y="278" width="118" height="70" rx="8" fill="{p["paper"]}" stroke="{L}" stroke-width="{sw}"/>'
            f'<rect x="314" y="272" width="20" height="82" rx="10" fill="{p["paper"]}" stroke="{L}" stroke-width="{sw}"/>'
            f'<rect x="436" y="272" width="20" height="82" rx="10" fill="{p["paper"]}" stroke="{L}" stroke-width="{sw}"/>'
            # runes: ansuz (a message) and raido (a journey) and kenaz (knowledge)
            f'<path d="M 354 294 v 40 M 354 296 l 14 10 M 354 310 l 14 10 '
            f'M 384 294 v 40 M 384 294 l 14 9 l -14 9 l 14 16 '
            f'M 424 296 l -14 18 l 14 18" '
            f'fill="none" stroke="{p["rune"]}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'
            f"</g>"
        )
    # front paws over the scroll
    parts.append(f'<ellipse cx="340" cy="352" rx="19" ry="14" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>')
    parts.append(f'<ellipse cx="430" cy="322" rx="19" ry="14" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>')
    return "\n".join(parts)


# ------------------------------------------------------------------ branches

def branch_piece(p: dict, d: str, width: float) -> str:
    """A bark-textured branch along path d."""
    L = p["line"]
    return (
        fat_stroke(d, width, p["bark"], L, 6)
        + f'\n<path d="{d}" fill="none" stroke="{p["bark2"]}" stroke-width="3" '
        f'stroke-dasharray="26 18" stroke-linecap="round" transform="translate(0 -6)"/>'
    )


def ash_leaf(p: dict, x: float, y: float, angle: float, scale: float) -> str:
    """A pinnate ash leaf (Yggdrasil is an ash): a stem with leaflet pairs."""
    L = p["line"]
    leaflets = []
    for i, t in enumerate((0.25, 0.5, 0.75)):
        lx = 70 * t
        for side in (-1, 1):
            leaflets.append(
                f'<ellipse cx="{lx + 6}" cy="{side * 12}" rx="13" ry="6.5" '
                f'transform="rotate({side * -35} {lx + 6} {side * 12})" '
                f'fill="{p["leaf"] if i % 2 == 0 else p["leaf2"]}" stroke="{L}" stroke-width="3.5"/>'
            )
    leaflets.append(f'<ellipse cx="82" cy="0" rx="15" ry="7" fill="{p["leaf"]}" stroke="{L}" stroke-width="3.5"/>')
    return (
        f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">'
        f'<path d="M 0 0 L 70 0" stroke="{L}" stroke-width="3.5" stroke-linecap="round"/>'
        + "".join(leaflets)
        + "</g>"
    )


def map_branch_tile(p: dict) -> str:
    """Two branches forking from a skill node, as used between skills on the map."""
    stem = ((256, 512), (250, 420), (262, 330), (256, 256))
    left = ((256, 270), (210, 210), (150, 170), (96, 104))
    right = ((256, 270), (300, 210), (362, 170), (416, 104))
    parts = [tapered(p, left, 30, 16), tapered(p, right, 30, 16), tapered(p, stem, 46, 30),
             bark_lines(p, stem, 40, 2),
             ash_leaf(p, 168, 196, -150, 1.0), ash_leaf(p, 344, 192, -30, 1.0),
             node(p, 96, 96, 38, "1"), node(p, 416, 96, 38, "2"), node(p, 256, 256, 44, None, current=True)]
    return "\n".join(parts)


def node(p: dict, x: float, y: float, r: float, label: str | None, current: bool = False) -> str:
    L = p["line"]
    out = [f'<circle cx="{x}" cy="{y}" r="{r}" fill="{p["node"]}" stroke="{L}" stroke-width="7"/>']
    out.append(f'<circle cx="{x}" cy="{y}" r="{r - 12}" fill="none" stroke="{p["leaf"] if p is COLOR else L}" '
               f'stroke-width="6" stroke-dasharray="{(r - 12) * 2 * math.pi * 0.7:.1f} 999" '
               f'transform="rotate(-90 {x} {y})" stroke-linecap="round"/>')
    if current:
        out.append(f'<circle cx="{x}" cy="{y}" r="{r + 12}" fill="none" stroke="{L}" stroke-width="3" stroke-dasharray="6 8"/>')
    return "\n".join(out)


def _bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])


def _normal(pts, t):
    x2, y2 = _bez(*pts, min(1, t + 0.01))
    x1, y1 = _bez(*pts, max(0, t - 0.01))
    dx, dy = x2 - x1, y2 - y1
    ln = math.hypot(dx, dy) or 1
    return -dy / ln, dx / ln


def tapered(p: dict, pts, w0: float, w1: float, fill: str | None = None, n: int = 28) -> str:
    """A cubic Bezier (4 points) drawn as a filled shape, w0 wide at the start
    and w1 at the end, with an outline: an organic branch or root."""
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        x, y = _bez(*pts, t)
        nx, ny = _normal(pts, t)
        w = (w0 + (w1 - w0) * t) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in left + right[::-1]) + " Z"
    return f'<path d="{d}" fill="{fill or p["bark"]}" stroke="{p["line"]}" stroke-width="6" stroke-linejoin="round"/>'


def bark_lines(p: dict, pts, w: float, count: int = 3) -> str:
    """Short bark grain dashes along a branch (they carry the texture in B/W)."""
    out = []
    for k in range(count):
        off = (k - (count - 1) / 2) * w / (count + 1)
        for i in range(3 + k % 2, 25, 4):
            t0, t1 = i / 28, (i + 1.6) / 28
            pts2 = []
            for t in (t0, t1):
                x, y = _bez(*pts, t)
                nx, ny = _normal(pts, t)
                o = off * (1 - t * 0.6)
                pts2.append((x + nx * o, y + ny * o))
            (a, b), (c, d) = pts2
            out.append(f'<path d="M {a:.1f} {b:.1f} L {c:.1f} {d:.1f}" stroke="{p["bark2"]}" stroke-width="3.5" stroke-linecap="round"/>')
    return "\n".join(out)


def yggdrasil(p: dict) -> str:
    """The course tree: three roots, a tapering trunk (your path), unit branches
    ending in skill nodes, an ash crown, and Tosk running up the trunk with a
    message (Ratatosk carries words between the roots and the crown)."""
    parts = []
    for pts in (((400, 880), (330, 930), (240, 950), (130, 1010)),
                ((400, 880), (405, 950), (380, 990), (360, 1030)),
                ((400, 880), (470, 930), (570, 950), (680, 1000))):
        parts.append(tapered(p, pts, 70, 10))
    trunk = ((400, 940), (380, 700), (420, 420), (398, 120))
    specs = [((396, 800), (330, 790), (250, 780), (170, 720), -1),
             ((404, 690), (480, 680), (560, 660), (630, 600), 1),
             ((394, 570), (320, 560), (240, 530), (180, 460), -1),
             ((406, 460), (480, 440), (560, 410), (620, 340), 1),
             ((398, 350), (330, 330), (270, 300), (220, 230), -1),
             ((402, 250), (460, 230), (520, 200), (570, 140), 1)]
    tips = []
    # branches and twigs first, so the trunk covers where they join it
    for a, b, c, e, side in specs:
        pts = (a, b, c, e)
        mx, my = _bez(*pts, 0.55)
        twig = ((mx, my), (mx + side * 10, my - 30), (mx + side * 30, my - 50), (mx + side * 44, my - 70))
        parts.append(tapered(p, twig, 12, 4))
        parts.append(tapered(p, pts, 40, 16))
        tips.append((mx, my, e, side))
    parts.append(tapered(p, trunk, 120, 34))
    parts.append(bark_lines(p, trunk, 110, 3))
    for mx, my, e, side in tips:
        parts.append(ash_leaf(p, mx + side * 40, my - 66, -90 + side * 30, 1.0))
        parts.append(ash_leaf(p, e[0] - side * 36, e[1] + 38, 90 + side * 40, 0.9))
        parts.append(node(p, e[0], e[1], 34, None))
    for x, y, a, sc in ((398, 108, -90, 1.4), (350, 120, -135, 1.3), (446, 120, -45, 1.3),
                        (300, 165, 170, 1.2), (500, 165, 10, 1.2), (372, 66, -112, 1.1), (424, 66, -68, 1.1)):
        parts.append(ash_leaf(p, x, y, a, sc))
    parts.append(f'<g transform="translate(404 600) rotate(-8) scale(0.30) translate(-280 -300)">{tosk(p, with_branch=False)}</g>')
    return "\n".join(parts)


def icon(p: dict) -> str:
    """App icon: Tosk's head and tail curl on a round badge."""
    L = p["line"]
    return (
        f'<circle cx="256" cy="256" r="236" fill="{p["belly"]}" stroke="{L}" stroke-width="14"/>\n'
        + fat_stroke("M 270 430 C 120 440, 80 330, 108 250 C 134 176, 204 152, 240 192", 72, p["fur"], L, 8)
        + f'\n<g transform="translate(300 270) scale(1.42) translate(-350 -205)">{tosk_head(p)}</g>'
    )


def tosk_head(p: dict) -> str:
    L = p["line"]
    sw = 7
    return "\n".join([
        f'<path d="M 300 168 L 296 108 L 330 150 Z" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>',
        f'<circle cx="338" cy="206" r="64" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}"/>',
        f'<path d="M 336 156 L 348 96 L 372 152 Z" fill="{p["fur"]}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>',
        f'<path d="M 348 96 l -10 -20 M 348 96 l 2 -24 M 348 96 l 12 -18" stroke="{L}" stroke-width="5" stroke-linecap="round"/>',
        f'<ellipse cx="392" cy="226" rx="36" ry="28" fill="{p["belly"]}" stroke="{L}" stroke-width="{sw}"/>',
        f'<ellipse cx="424" cy="214" rx="11" ry="9" fill="{p["nose"]}"/>',
        f'<path d="M 404 238 q 10 8 22 0" fill="none" stroke="{L}" stroke-width="5" stroke-linecap="round"/>',
        f'<circle cx="362" cy="196" r="11" fill="{p["eye"]}"/>',
        f'<circle cx="366" cy="192" r="3.5" fill="{p["shine"]}"/>',
    ])


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for suffix, pal in (("", COLOR), ("-mono", MONO)):
        (OUT / f"tosk{suffix}.svg").write_text(svg(512, 512, tosk(pal), "Tosk"), encoding="utf8")
        (OUT / f"tosk-icon{suffix}.svg").write_text(svg(512, 512, icon(pal), "Tosk icon"), encoding="utf8")
        (OUT / f"branch-tile{suffix}.svg").write_text(svg(512, 512, map_branch_tile(pal), "Yggdrasil branch"), encoding="utf8")
        (OUT / f"yggdrasil{suffix}.svg").write_text(svg(800, 1040, yggdrasil(pal), "Yggdrasil"), encoding="utf8")
        (OUT / f"ash-leaf{suffix}.svg").write_text(
            svg(128, 64, ash_leaf(pal, 14, 32, 0, 1.15), "Ash leaf"), encoding="utf8")
    print("wrote", sorted(f.name for f in OUT.glob("*.svg")))


if __name__ == "__main__":
    main()
