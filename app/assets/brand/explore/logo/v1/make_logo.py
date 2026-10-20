"""tosk brand exploration, "logo first".

Run:  python make_logo.py   -> writes the SVGs + sheet.html next to this file.

Pure Python, no dependencies. Every piece is drawn from hand-written Bezier
paths through one of two palettes (COLOR / MONO) so the e-ink versions stay
in sync with the colour ones.
"""
from __future__ import annotations

import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

COLOR = dict(
    ink="#2A1C14",      # outlines, text
    rust="#C4502A",     # Tosk's fur, the brand red
    rust2="#E07A3E",    # lighter fur / tail highlight
    cream="#F6ECD8",    # belly, paper, node faces
    bark="#6A4631",
    bark2="#8B6246",
    leaf="#5E8C4A",
    leaf2="#86B063",
    gold="#E0A64A",     # node rings, well water glint
    water="#6E9DB3",
    bg="#FBF6EC",
)
MONO = dict(
    ink="#000000", rust="#000000", rust2="#000000", cream="#FFFFFF", bark="#FFFFFF",
    bark2="#000000", leaf="#FFFFFF", leaf2="#FFFFFF", gold="#000000", water="#FFFFFF",
    bg="#FFFFFF",
)


def svg(w: float, h: float, body: str, title: str, vb: str | None = None) -> str:
    vb = vb or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{w}" height="{h}">\n'
            f"<title>{title}</title>\n{body}\n</svg>\n")


# ====================================================================== MARK
# The mark lives in a 100 x 100 box. Tosk sits upright, facing right, the
# plume tail rising behind him and curling forward over his head so that the
# whole silhouette is one compact, rounded "comma" shape. The tail tip is a
# small ash sprig: the messenger carries a piece of the world tree with him.

# Body + head (clockwise from the nose). The eye is a hole (evenodd).
MARK_BODY = (
    "M 86 50 "
    "C 83 43, 77 39, 71 39 "        # snout up to the forehead
    "C 72 34, 74 28, 77 21 "        # ear 1 front edge to tuft tip
    "C 74 27, 70 32, 66 35 "        # ear 1 back edge down to the head top
    "C 64 35, 63 34, 62 32 "        # dip between the ears
    "C 62 28, 63 23, 65 18 "        # ear 2 front edge to tuft tip
    "C 61 24, 57 31, 56 37 "        # ear 2 back edge to the back of the head
    "C 48 41, 42 50, 41 60 "        # neck into the upper back
    "C 40 68, 40 76, 43 84 "        # back down to the rump
    "C 46 92, 54 97, 64 97 "        # rump round to the bottom
    "C 72 97, 80 97, 85 95 "        # hind foot along the ground
    "C 88 94, 88 91, 85 90 "        # toe
    "C 80 89, 78 85, 78 79 "        # front of the thigh up to the belly
    "C 78 72, 78 67, 78 64 "        # belly up to the paws
    "C 82 64, 86 61, 85 57 "        # paws
    "C 84 55, 82 53, 81 52 "        # under the chin
    "C 83 52, 86 52, 86 50 Z "      # chin to the nose
    # eye (hole)
    "M 74 46 a 3.2 3.2 0 1 0 0.01 0 Z"
)
# Tail (clockwise from the rump). Outer edge = left/top, inner edge comes back.
MARK_TAIL = (
    "M 56 96 "
    "C 44 100, 28 100, 20 92 "      # outer: lower sweep (thin base)
    "C 16 90, 14 87, 14 83 "        # notch between fur lobes
    "C 2 70, 0 46, 10 32 "          # outer: rising, the plume at its fattest
    "C 8 30, 8 26, 10 24 "          # notch
    "C 18 8, 38 0, 56 2 "           # outer: over the top
    "C 68 2, 78 6, 80 11 "          # tip, curling forward above the ears
    "C 81 16, 77 20, 71 17 "        # tip end: a small downward flick
    "C 62 12, 50 12, 40 16 "        # inner: under the overhang
    "C 28 22, 22 34, 24 50 "        # inner: descending, a bay behind the back
    "C 26 64, 32 78, 42 86 "        # inner: towards the rump
    "C 46 90, 50 93, 56 96 Z"
)
# Ash sprig growing from the tail tip (one of the concept variants).
MARK_SPRIG = (
    "M 74 14 C 78 8, 84 5, 92 6 C 88 12, 82 16, 76 16 Z "     # leaflet hanging from the tail tip
    "M 75 17 C 80 18, 86 22, 88 28 C 82 26, 77 23, 74 19 Z"
)
def mark(p: dict, variant: str = "plain") -> str:
    """The Tosk mark in a 100x100 box, one colour."""
    c = p["rust"]
    out = [f'<g fill="{c}">',
           f'<path d="{MARK_TAIL}"/>',
           f'<path d="{MARK_BODY}" fill-rule="evenodd"/>']
    if variant == "sprig":
        out.append(f'<path d="{MARK_SPRIG}"/>')
    out.append("</g>")
    return "\n".join(out)


# ----------------------------------------------------------- concept sketches
def concept_bubble(p: dict) -> str:
    """Concept B: the tail is a speech bubble (pointer at the rump)."""
    c = p["rust"]
    bubble = ("M 52 92 C 44 88, 36 82, 30 80 C 14 78, 4 62, 8 42 C 12 20, 34 8, 56 12 "
              "C 66 14, 70 20, 66 26 C 60 30, 50 28, 44 34 C 36 42, 36 54, 40 64 C 42 72, 46 80, 52 92 Z")
    return (f'<g fill="{c}"><path d="{bubble}"/>'
            f'<path d="{MARK_BODY}" fill-rule="evenodd"/></g>')


def concept_tree(p: dict) -> str:
    """Concept C: squirrel-as-tree. Tail up = canopy, body = trunk, three roots."""
    c = p["rust"]
    canopy = ("M 46 58 C 34 50, 20 44, 16 30 C 12 16, 26 4, 42 6 C 54 7, 60 2, 70 6 "
              "C 84 10, 86 28, 78 40 C 72 48, 60 52, 56 58 Z")
    body = ("M 52 58 C 48 70, 48 80, 46 88 C 40 90, 32 92, 24 96 C 36 94, 44 94, 50 95 "
            "C 50 97, 52 98, 56 98 C 60 98, 62 97, 62 95 C 68 94, 76 94, 86 96 C 78 92, 70 90, 64 88 "
            "C 62 80, 62 70, 60 60 "
            "C 66 60, 72 56, 76 52 C 72 50, 70 46, 72 42 C 74 38, 76 32, 74 30 "   # head/snout stub
            "C 70 34, 66 36, 62 40 C 60 36, 58 30, 58 24 C 56 30, 54 36, 54 42 Z "
            "M 66 46 a 2.6 2.6 0 1 0 0.01 0 Z")
    return f'<g fill="{c}"><path d="{canopy}"/><path d="{body}" fill-rule="evenodd"/></g>'


def concept_rune(p: dict) -> str:
    """Concept D: monogram. Tiwaz (the t-rune) as a branch, Tosk perched on it."""
    c = p["rust"]
    ring = f'<circle cx="50" cy="50" r="46" fill="none" stroke="{c}" stroke-width="6"/>'
    rune = (f'<path d="M 50 92 L 50 22 M 50 22 L 28 44 M 50 22 L 72 44" fill="none" stroke="{c}" '
            f'stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>')
    small = (f'<g transform="translate(53 26) scale(0.42)">'
             f'<path d="{MARK_TAIL}"/><path d="{MARK_BODY}" fill-rule="evenodd"/></g>')
    return f'<g fill="{c}">{ring}{rune}{small}</g>'


def concept_t(p: dict) -> str:
    """Concept E: the tail sweeps up into the ascender of a lowercase t."""
    c = p["rust"]
    t = (f'<path d="M 40 10 L 40 72 C 40 84, 48 90, 60 86 M 26 34 L 56 34" fill="none" stroke="{c}" '
         f'stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>')
    small = (f'<g transform="translate(44 44) scale(0.52)">'
             f'<path d="{MARK_TAIL}"/><path d="{MARK_BODY}" fill-rule="evenodd"/></g>')
    return f'<g fill="{c}">{t}{small}</g>'


def concepts_svg(p: dict) -> str:
    cells = [
        ("A  plume", mark(p, "plain")),
        ("A'  plume + ash sprig", mark(p, "sprig")),
        ("B  tail = speech bubble", concept_bubble(p)),
        ("C  squirrel-tree, 3 roots", concept_tree(p)),
        ("D  Tiwaz-rune monogram", concept_rune(p)),
        ("E  tail into the t", concept_t(p)),
    ]
    out = []
    for i, (label, g) in enumerate(cells):
        x = 20 + i * 150
        out.append(f'<rect x="{x}" y="20" width="130" height="130" rx="18" fill="{p["cream"]}" '
                   f'stroke="{p["ink"]}" stroke-opacity="0.15"/>')
        out.append(f'<g transform="translate({x + 15} 35)">{g}</g>')
        out.append(f'<text x="{x + 65}" y="178" text-anchor="middle" font-family="Georgia, serif" '
                   f'font-size="12" fill="{p["ink"]}">{label}</text>')
    return svg(920, 200, "\n".join(out), "tosk mark concepts")


# ================================================================== WORDMARK
# Monoline lowercase "tosk" as stroked paths: round caps, x-height 40 units,
# stroke 11, drawn in the same rounded language as the mark.
def wordmark(p: dict, x: float = 0, y: float = 0, scale: float = 1.0, color: str | None = None) -> str:
    c = color or p["ink"]
    w = 11.5
    # baseline y=90, x-height top y=50, ascender top y=22
    t = "M 16 26 L 16 76 C 16 86, 22 91, 34 88 M 4 50 L 30 50"
    o = "M 72 70 m -20 0 a 20 20 0 1 0 40 0 a 20 20 0 1 0 -40 0"
    s = "M 127 57 C 123 49, 105 49, 105 58 C 105 68, 127 66, 127 78 C 127 90, 107 92, 103 83"
    k = "M 145 26 L 145 88 M 171 52 L 147 72 M 153 68 L 173 88"
    return (f'<g transform="translate({x} {y}) scale({scale})" fill="none" stroke="{c}" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="{t}"/><path d="{o}"/><path d="{s}"/><path d="{k}"/></g>')


def logo_svg(p: dict) -> str:
    body = (f'<g transform="translate(20 10) scale(1.1)">{mark(p, "plain")}</g>'
            f'{wordmark(p, 150, 10, 1.1)}')
    return svg(360, 130, body, "tosk logo")


# ====================================================================== ICON
def icon_svg(p: dict, mono: bool = False) -> str:
    """Android adaptive-icon friendly: 108 box, the mark inside the 66-dp safe circle."""
    if mono:
        bg = (f'<rect x="4" y="4" width="100" height="100" rx="24" fill="#FFFFFF" stroke="#000000" stroke-width="4"/>')
        m = f'<g transform="translate(15 15) scale(0.78)">{mark(MONO, "plain")}</g>'
    else:
        bg = f'<rect width="108" height="108" fill="{p["rust"]}"/>'
        inner = f'<rect x="4" y="4" width="100" height="100" rx="24" fill="{p["rust"]}"/>'
        m = f'<g transform="translate(15 15) scale(0.78)">{mark(dict(p, rust=p["cream"]), "plain")}</g>'
        bg = bg + inner
    return svg(108, 108, bg + m, "tosk app icon")


# =================================================================== MASCOT
def tosk_svg(p: dict) -> str:
    """Tosk the messenger: leaning forward on an ash branch, letter in paw, plume up. 512 box."""
    L = p["ink"]
    sw = 6
    fur = "#FFFFFF" if p is MONO else p["rust"]   # e-ink: line art, not a black blob
    parts: list[str] = []

    # ---- branch of Yggdrasil he stands on
    br = ((0, 486), (120, 470), (330, 486), (512, 458))
    parts.append(tapered(p, br, 46, 30, sw=5, wobble=0.08))
    parts.append(bark_grain(p, br, 44))
    parts.append(ash_sprig(p, 466, 454, -40, 0.9))
    parts.append(ash_sprig(p, 60, 500, 200, 0.75))

    # ---- tail: one big plume rising behind the back, tip curling forward above the head
    tail = (
        "M 250 462 "
        "C 210 468, 160 456, 128 424 "      # lower sweep, thin base
        "C 118 426, 108 418, 108 408 "      # notch (fur lobe)
        "C 72 366, 62 310, 76 260 "         # rising, the plume at its fattest
        "C 64 254, 62 236, 74 228 "         # notch
        "C 92 170, 128 118, 182 88 "        # rising to the top
        "C 178 76, 186 66, 200 66 "         # notch
        "C 250 44, 300 48, 326 70 "         # over the top, forward
        "C 340 82, 342 100, 328 110 "       # tip curling down just behind the ears
        "C 318 118, 304 112, 300 102 "      # tip underside
        "C 280 94, 250 92, 226 100 "        # inner edge under the overhang
        "C 200 110, 196 160, 206 220 "      # inner edge descending behind the nape
        "C 214 290, 230 360, 240 420 "      # ... touching the rump
        "C 244 436, 248 450, 250 462 Z"
    )
    parts.append(f'<path d="{tail}" fill="{fur}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>')
    if p is COLOR:  # lighter inner plume
        inner = ("M 140 410 C 110 350, 110 270, 136 210 C 160 150, 210 104, 270 86 C 290 80, 312 84, 320 94 "
                 "C 300 100, 260 104, 230 118 C 180 142, 160 200, 154 260 C 148 320, 156 370, 174 404 Z")
        parts.append(f'<path d="{inner}" fill="{p["rust2"]}"/>')
    for d in ("M 104 380 C 114 368, 126 362, 140 362", "M 92 300 C 102 288, 114 282, 128 282",
              "M 112 206 C 122 196, 136 192, 150 192", "M 196 100 C 208 92, 222 90, 236 92",
              "M 276 66 C 290 66, 304 72, 312 84",
              *(("M 214 190 C 208 230, 210 270, 218 310", "M 226 340 C 232 370, 240 396, 246 416",
                 "M 150 420 C 136 390, 128 350, 130 310") if p is MONO else ())):
        parts.append(f'<path d="{d}" fill="none" stroke="{L}" stroke-width="4" stroke-linecap="round" opacity="0.85"/>')

    # ---- body + head silhouette (leaning forward, nose to the right)
    body = (
        "M 438 214 "
        "C 424 196, 404 184, 382 180 "      # snout bridge up to the forehead
        "C 384 156, 388 132, 396 112 "      # ear 1 front edge to the tuft
        "C 388 130, 374 148, 360 160 "      # ear 1 back edge down to the head top
        "C 354 162, 348 160, 344 158 "      # dip
        "C 344 140, 348 126, 356 114 "      # ear 2 front edge to the tuft
        "C 344 128, 330 148, 322 168 "      # ear 2 back edge
        "C 302 180, 290 198, 288 218 "      # back of the head into the nape
        "C 266 240, 246 280, 246 330 "      # upper back: a shoulder hump, leaning forward
        "C 246 372, 230 408, 232 440 "      # lower back curving into the haunch
        "C 232 456, 244 464, 262 464 "
        "L 392 464 "                        # along the branch (the foot is drawn on top)
        "C 404 452, 404 428, 394 406 "      # front of the thigh / knee
        "C 388 370, 390 330, 388 300 "      # belly rising
        "C 386 270, 392 246, 404 234 "      # chest to the chin
        "C 416 228, 428 222, 436 220 "
        "C 440 218, 440 216, 438 214 Z"
    )
    parts.append(f'<path d="{body}" fill="{fur}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>')
    belly = ("M 404 240 C 372 262, 356 300, 354 346 C 352 380, 364 404, 386 408 "
             "C 392 390, 394 360, 392 330 C 390 290, 394 258, 404 240 Z")
    parts.append(f'<path d="{belly}" fill="{p["cream"]}" stroke="{L if p is MONO else "none"}" stroke-width="2.5" stroke-dasharray="1 6" stroke-linecap="round"/>')
    # ear insides
    parts.append(f'<path d="M 392 124 C 388 138, 380 152, 370 160 C 380 158, 390 142, 392 124 Z" fill="{p["cream"]}"/>')
    # ear tufts
    for d in ("M 396 112 l -8 -14 M 396 112 l 4 -16 M 396 112 l 10 -10",
              "M 356 114 l -8 -12 M 356 114 l 2 -16 M 356 114 l 10 -10"):
        parts.append(f'<path d="{d}" fill="none" stroke="{L}" stroke-width="4" stroke-linecap="round"/>')
    # cheek fur
    parts.append(f'<path d="M 356 214 l -12 5 l 12 4" fill="none" stroke="{L}" stroke-width="3.5" '
                 f'stroke-linecap="round" stroke-linejoin="round"/>')
    # haunch crease and hind foot
    parts.append(f'<path d="M 394 406 C 356 404, 318 424, 302 462" fill="none" stroke="{L}" stroke-width="5" stroke-linecap="round"/>')
    parts.append(f'<path d="M 266 464 C 280 452, 320 448, 356 450 C 380 452, 394 456, 398 466 C 364 468, 320 468, 266 466 Z" '
                 f'fill="{fur}" stroke="{L}" stroke-width="{sw}" stroke-linejoin="round"/>')
    parts.append(f'<path d="M 372 454 l 6 10 M 384 456 l 4 8" fill="none" stroke="{L}" stroke-width="3.5" stroke-linecap="round"/>')

    # ---- eye (big, sly: lid line + highlight), brow, nose, smirk, whiskers
    parts.append(f'<ellipse cx="396" cy="202" rx="13" ry="14" fill="#FFFFFF" stroke="{L}" stroke-width="4"/>')
    parts.append(f'<circle cx="400" cy="204" r="7.5" fill="{L}"/>')
    parts.append(f'<circle cx="403" cy="200" r="2.6" fill="#FFFFFF"/>')
    parts.append(f'<path d="M 382 190 C 392 180, 406 182, 414 192" fill="none" stroke="{L}" stroke-width="5" stroke-linecap="round"/>')
    parts.append(f'<path d="M 378 176 C 390 168, 406 170, 416 178" fill="none" stroke="{L}" stroke-width="4" stroke-linecap="round"/>')
    parts.append(f'<path d="M 440 208 C 446 210, 446 218, 438 220 C 432 218, 432 210, 440 208 Z" fill="{L}"/>')
    parts.append(f'<path d="M 434 232 C 426 242, 414 242, 408 236" fill="none" stroke="{L}" stroke-width="4" stroke-linecap="round"/>')
    parts.append(f'<path d="M 440 202 l 24 -6 M 442 212 l 26 0 M 440 222 l 22 6" fill="none" stroke="{L}" stroke-width="2.5" stroke-linecap="round"/>')

    # ---- arms holding the letter
    parts.append(fat_stroke("M 374 280 C 396 282, 420 296, 434 316", 26, fur, L, 5))
    parts.append(f'<g transform="rotate(-18 460 334)">'
                 f'<rect x="428" y="312" width="66" height="46" rx="5" fill="{p["cream"]}" stroke="{L}" stroke-width="5"/>'
                 f'<path d="M 428 312 L 461 340 L 494 312" fill="none" stroke="{L}" stroke-width="4" stroke-linejoin="round"/>'
                 f'<circle cx="461" cy="342" r="5" fill="{fur}" stroke="{L}" stroke-width="2.5"/></g>')
    parts.append(fat_stroke("M 382 304 C 404 308, 426 320, 446 340", 26, fur, L, 5))
    parts.append(f'<circle cx="448" cy="342" r="13" fill="{fur}" stroke="{L}" stroke-width="5"/>')
    parts.append(f'<path d="M 450 330 l 8 -3 M 456 336 l 10 -1 M 456 344 l 9 3" fill="none" stroke="{L}" stroke-width="3" stroke-linecap="round"/>')
    return svg(512, 512, "\n".join(parts), "Tosk, the messenger")


def fat_stroke(d: str, width: float, fill: str, line: str, outline: float = 5) -> str:
    return (f'<path d="{d}" fill="none" stroke="{line}" stroke-width="{width + 2 * outline}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="{fill}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')


# ================================================================ BRANCHES
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


def tapered(p: dict, pts, w0: float, w1: float, sw: float = 6, fill: str | None = None, n: int = 30,
            wobble: float = 0.0) -> str:
    """A cubic Bezier drawn as a filled, tapering shape with an outline."""
    d = tapered_d(pts, w0, w1, n, wobble)
    return f'<path d="{d}" fill="{fill or p["bark"]}" stroke="{p["ink"]}" stroke-width="{sw}" stroke-linejoin="round"/>'


def wood(p: dict, ds: list[str], sw: float = 6) -> str:
    """Several wooden shapes drawn as one: outlines first, then all fills on top,
    so branches grow out of the trunk without seams."""
    out = [f'<path d="{d}" fill="{p["bark"]}" stroke="{p["ink"]}" stroke-width="{sw}" stroke-linejoin="round"/>' for d in ds]
    out += [f'<path d="{d}" fill="{p["bark"]}"/>' for d in ds]
    return "\n".join(out)


def tapered_d(pts, w0: float, w1: float, n: int = 30, wobble: float = 0.0) -> str:
    """A cubic Bezier as a filled, tapering shape. A little 'wobble' makes the
    edges knotty rather than mechanical."""
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        x, y = _bez(*pts, t)
        nx, ny = _normal(pts, t)
        w = (w0 + (w1 - w0) * t) / 2
        wl = w * (1 + wobble * math.sin(t * 9.3 + 1.0))
        wr = w * (1 + wobble * math.sin(t * 7.1 + 2.3))
        left.append((x + nx * wl, y + ny * wl))
        right.append((x - nx * wr, y - ny * wr))
    return smooth_path(left + right[::-1])


def smooth_path(pts) -> str:
    """Catmull-Rom through points -> cubic Bezier path (closed)."""
    n = len(pts)
    out = [f"M {pts[0][0]:.1f} {pts[0][1]:.1f}"]
    for i in range(n):
        p0 = pts[(i - 1) % n]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        out.append(f"C {c1[0]:.1f} {c1[1]:.1f}, {c2[0]:.1f} {c2[1]:.1f}, {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(out) + " Z"


def bark_grain(p: dict, pts, w: float, count: int = 2, sw: float = 3) -> str:
    out = []
    for k in range(count):
        off = (k - (count - 1) / 2) * w / (count + 1.5)
        for i in range(2 + k, 27, 5):
            t0, t1 = i / 30, (i + 2.2) / 30
            x0, y0 = _bez(*pts, t0)
            x1, y1 = _bez(*pts, t1)
            n0 = _normal(pts, t0)
            n1 = _normal(pts, t1)
            out.append(f"M {x0 + n0[0] * off:.1f} {y0 + n0[1] * off:.1f} L {x1 + n1[0] * off:.1f} {y1 + n1[1] * off:.1f}")
    return f'<path d="{" ".join(out)}" stroke="{p["bark2"]}" stroke-width="{sw}" stroke-linecap="round" fill="none"/>'


LEAFLET = "M 0 0 C 10 -9, 26 -9, 36 0 C 26 8, 10 8, 0 0 Z"   # ash leaflet (lanceolate)


def ash_sprig(p: dict, x: float, y: float, angle: float, scale: float = 1.0) -> str:
    """A pinnate ash leaf: a stem with leaflet pairs and a terminal leaflet."""
    L = p["ink"]
    out = [f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">',
           f'<path d="M 0 0 C 30 -4, 60 -4, 90 0" fill="none" stroke="{L}" stroke-width="3.5" stroke-linecap="round"/>']
    for i, t in enumerate((20, 46, 70)):
        for side in (-1, 1):
            fill = p["leaf"] if (i + (side > 0)) % 2 == 0 else p["leaf2"]
            out.append(f'<path d="{LEAFLET}" transform="translate({t} {-2 * (1 - i * 0.1)}) rotate({side * -42})" '
                       f'fill="{fill}" stroke="{L}" stroke-width="3" stroke-linejoin="round"/>')
            out.append(f'<path d="M 4 0 L 30 0" transform="translate({t} {-2}) rotate({side * -42})" '
                       f'stroke="{L}" stroke-width="1.5" stroke-linecap="round" opacity="0.7"/>')
    out.append(f'<path d="{LEAFLET}" transform="translate(88 -1) rotate(-8)" fill="{p["leaf"]}" stroke="{L}" '
               f'stroke-width="3" stroke-linejoin="round"/>')
    out.append("</g>")
    return "".join(out)


RUNES = {  # Elder Futhark, first aett (stroke paths in a 24x32 box, origin top-left)
    "f": "M 12 2 V 30 M 12 8 L 22 2 M 12 16 L 22 10",
    "u": "M 4 30 V 2 L 20 10 V 30",
    "th": "M 6 2 V 30 M 6 8 L 18 16 L 6 24",
    "a": "M 12 2 V 30 M 12 6 L 2 12 M 12 14 L 2 20",
    "r": "M 6 30 V 2 L 18 10 L 6 16 L 18 30",
    "k": "M 18 2 L 6 16 L 18 30",
    "g": "M 2 2 L 22 30 M 22 2 L 2 30",
    "w": "M 6 30 V 2 L 18 10 L 6 18",
}


def node(p: dict, x: float, y: float, r: float, rune: str | None = None, done: bool = False, current: bool = False) -> str:
    L = p["ink"]
    face = p["gold"] if (done and p is COLOR) else p["cream"]
    if done and p is MONO:
        face = "#000000"
    out = [f'<circle cx="{x}" cy="{y}" r="{r}" fill="{face}" stroke="{L}" stroke-width="5"/>']
    if rune:
        col = "#FFFFFF" if (done and p is MONO) else L
        s = r / 24
        out.append(f'<path d="{RUNES[rune]}" transform="translate({x - 12 * s} {y - 16 * s}) scale({s})" fill="none" '
                   f'stroke="{col}" stroke-width="{4 / s:.1f}" stroke-linecap="round" stroke-linejoin="round"/>')
    if current:
        out.append(f'<circle cx="{x}" cy="{y}" r="{r + 9}" fill="none" stroke="{L}" stroke-width="3" stroke-dasharray="5 7"/>')
    return "\n".join(out)


# ================================================================ YGGDRASIL
def yggdrasil_svg(p: dict) -> str:
    L = p["ink"]
    W, H = 800, 1100
    parts: list[str] = []
    scale_fill = p["bark"] if p is COLOR else "#FFFFFF"

    # --- Urðarbrunnr, the well at the roots: a ring of stones, drawn behind the trunk
    parts.append(f'<ellipse cx="400" cy="1016" rx="170" ry="44" fill="{p["bark2"] if p is COLOR else "#FFFFFF"}" stroke="{L}" stroke-width="5"/>')
    # stone blocks on the rim
    for i in range(14):
        a0 = i / 14 * 2 * math.pi
        a1 = (i + 0.85) / 14 * 2 * math.pi
        x0, y0 = 400 + 170 * math.cos(a0), 1016 + 44 * math.sin(a0)
        x1, y1 = 400 + 170 * math.cos(a1), 1016 + 44 * math.sin(a1)
        if y0 > 1016 or y1 > 1016:   # front half only
            parts.append(f'<path d="M {x0:.0f} {y0:.0f} L {x1:.0f} {y1:.0f}" fill="none" stroke="{L}" stroke-width="3" stroke-linecap="round" opacity="0.6"/>')
    parts.append(f'<ellipse cx="400" cy="1006" rx="138" ry="28" fill="{p["water"]}" stroke="{L}" stroke-width="4"/>')
    parts.append(f'<path d="M 300 1004 C 320 996, 346 998, 362 1006 M 420 996 C 444 990, 470 994, 492 1004 M 350 1018 C 370 1012, 390 1014, 404 1020" '
                 f'fill="none" stroke="{L}" stroke-width="3" stroke-linecap="round" opacity="0.7"/>')

    # --- Níðhöggr, coiled behind the right root (body) ...
    body1 = ((460, 1044), (560, 1090), (730, 1080), (762, 990))
    parts.append(tapered(p, body1, 14, 42, fill=scale_fill, wobble=0.0))
    for x, y in ((520, 1064), (562, 1078), (606, 1084), (650, 1082), (694, 1070), (730, 1046), (754, 1010)):
        parts.append(f'<path d="M {x} {y} l 7 -16 l 7 16" fill="{scale_fill}" stroke="{L}" stroke-width="3" stroke-linejoin="round"/>')

    # --- three roots (drawn with the trunk and branches below, as one piece of wood)
    roots = [((320, 900), (260, 950), (140, 940), (90, 1050)),
             ((400, 905), (396, 940), (404, 980), (400, 1040)),
             ((480, 900), (560, 950), (680, 940), (720, 1050))]

    # --- trunk: an ancient ash, flared knotty base, a lean, a burl
    trunk = ("M 286 908 C 298 860, 316 800, 322 720 C 326 660, 316 600, 330 540 "
             "C 342 490, 336 430, 350 380 C 360 330, 366 290, 376 250 "
             "L 428 248 C 440 290, 446 330, 456 380 C 470 430, 466 490, 474 540 "
             "C 488 600, 478 660, 482 720 C 488 800, 504 860, 516 908 "
             "C 476 936, 326 936, 286 908 Z")
    detail: list[str] = []
    for d in ("M 330 880 C 340 790, 348 700, 356 600", "M 372 890 C 372 800, 376 700, 386 560",
              "M 450 880 C 446 780, 440 680, 432 580", "M 486 890 C 480 830, 472 780, 470 720",
              "M 362 470 C 370 420, 380 350, 392 290", "M 436 480 C 430 420, 424 350, 416 300",
              "M 402 840 C 404 780, 408 720, 410 660"):
        detail.append(f'<path d="{d}" fill="none" stroke="{p["bark2"]}" stroke-width="3" stroke-linecap="round"/>')
    # burl + knot-hole
    detail.append(f'<path d="M 418 700 C 440 686, 462 706, 450 732 C 438 752, 410 740, 418 700 Z" fill="{L}" opacity="0.9"/>')
    # carved runes on the trunk
    for i, rn in enumerate(("a", "r", "th")):
        detail.append(f'<g transform="translate({392 + i * 6} {770 + i * 44}) scale(1.2)"><path d="{RUNES[rn]}" fill="none" stroke="{L}" '
                     f'stroke-width="3" stroke-linecap="round" stroke-linejoin="round" opacity="0.8"/></g>')
    trunk_detail = "\n".join(detail)

    # --- branches: out, then sweeping upward (ash habit), with twigs
    branches = [
        ((330, 585), (240, 612), (120, 570), (110, 475)),   # 1 left low
        ((472, 545), (570, 575), (700, 560), (700, 430)),   # 2 right low
        ((346, 450), (260, 458), (160, 430), (150, 305)),   # 3 left mid
        ((458, 410), (550, 420), (650, 395), (650, 265)),   # 4 right mid
        ((372, 300), (320, 300), (236, 280), (230, 160)),   # 5 left high
        ((432, 290), (490, 280), (560, 260), (560, 135)),   # 6 right high
        ((400, 250), (410, 200), (392, 150), (400, 95)),    # 7 crown
    ]
    twigs = [
        ((206, 596), (196, 570), (176, 548), (160, 500)), ((600, 566), (614, 540), (636, 510), (650, 470)),
        ((228, 444), (226, 410), (244, 384), (260, 350)), ((585, 400), (588, 370), (574, 348), (560, 320)),
        ((282, 288), (290, 260), (300, 230), (320, 200)), ((520, 268), (506, 240), (492, 210), (480, 170)),
        ((160, 560), (150, 540), (134, 530), (120, 520)), ((656, 540), (662, 522), (676, 512), (690, 500)),
    ]
    ds = [trunk] + [tapered_d(r, 76, 26, wobble=0.14) for r in roots]
    ds += [tapered_d(b, 50, 18, wobble=0.12) for b in branches]
    ds += [tapered_d(t, 16, 8, wobble=0.1) for t in twigs]
    parts.append(wood(p, ds))
    for r in roots:
        parts.append(bark_grain(p, r, 60, 2))
    parts.append(trunk_detail)

    # --- ... and in front of the root: Níðhöggr's neck and head, gnawing at it
    neck = ((762, 990), (800, 910), (740, 870), (676, 896))
    parts.append(tapered(p, neck, 42, 30, fill=scale_fill, wobble=0.0))
    head = ("M 690 886 C 664 870, 622 880, 606 908 C 624 906, 640 912, 648 926 "
            "C 634 936, 622 948, 628 964 C 648 958, 668 954, 682 946 C 708 932, 712 902, 690 886 Z")
    parts.append(f'<path d="{head}" fill="{scale_fill}" stroke="{L}" stroke-width="5" stroke-linejoin="round"/>')
    parts.append(f'<path d="M 610 908 l 4 10 l 6 -10 l 5 10 l 6 -9 l 5 10 l 6 -8" fill="none" stroke="{L}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>')  # teeth
    parts.append(f'<circle cx="674" cy="902" r="5" fill="{L}"/>')
    parts.append(f'<path d="M 684 884 l 6 -20 M 696 890 l 16 -12" fill="none" stroke="{L}" stroke-width="4" stroke-linecap="round"/>')  # horns
    parts.append(f'<path d="M 700 920 l 14 2 M 696 932 l 12 6" fill="none" stroke="{L}" stroke-width="3" stroke-linecap="round"/>')  # jaw ridges
    sprigs = [  # leaf clusters: (x, y, angle, scale)
        (150, 498, 190, 0.9), (112, 440, -120, 0.9), (170, 520, 230, 0.7),
        (650, 470, -10, 0.9), (690, 400, -60, 0.9), (630, 540, -20, 0.7),
        (260, 350, -70, 0.8), (150, 290, -120, 0.9), (190, 330, 200, 0.8),
        (560, 320, -100, 0.8), (650, 240, -60, 0.9), (620, 300, 10, 0.8),
        (320, 200, -60, 0.8), (228, 150, -110, 0.9), (260, 200, 190, 0.8),
        (480, 170, -110, 0.8), (560, 120, -60, 0.9), (520, 170, 20, 0.8),
        (380, 110, -120, 0.9), (420, 110, -60, 0.9), (350, 150, 200, 0.7), (450, 150, -20, 0.7),
        (120, 520, 160, 0.8), (690, 500, 20, 0.8), (200, 480, -150, 0.7), (600, 440, -40, 0.7),
        (300, 230, -40, 0.7), (500, 220, -140, 0.7), (190, 420, -100, 0.7), (610, 380, -80, 0.7),
    ]
    for x, y, a, s in sprigs:
        parts.append(ash_sprig(p, x, y, a, s * 1.15))

    # --- the eagle in the crown (wings half-open)
    eagle = ("M 400 100 C 376 96, 336 80, 300 70 C 326 60, 362 64, 386 78 "
             "C 386 64, 394 50, 410 48 C 420 48, 428 54, 430 62 C 438 60, 446 62, 452 66 "
             "C 446 70, 438 72, 430 72 C 430 84, 422 96, 412 102 "
             "C 446 98, 488 108, 512 124 C 476 118, 436 118, 408 108 "
             "C 412 116, 408 124, 400 128 C 392 124, 388 116, 392 108 Z")
    parts.append(f'<path d="{eagle}" fill="{L}"/>')
    parts.append(f'<circle cx="414" cy="58" r="2.4" fill="{p["cream"]}"/>')

    # --- skill nodes at the branch tips (7)
    nodes = [(110, 478, "f", True), (700, 432, "u", True), (150, 306, "th", True), (650, 266, "a", False),
             (230, 160, "r", False), (560, 136, "k", False), (400, 176, "g", False)]
    for i, (x, y, rn, done) in enumerate(nodes):
        parts.append(node(p, x, y, 30, rn, done=done, current=(i == 3)))

    # --- Tosk running up the trunk (the mark, small)
    parts.append(f'<g transform="translate(500 470) scale(0.75)">{mark(p, "plain")}</g>')

    return svg(W, H, "\n".join(parts), "Yggdrasil, the course tree")


# ============================================================== BRANCH TILE
def branch_tile_svg(p: dict) -> str:
    stem = ((256, 500), (236, 440), (278, 360), (256, 270))
    left = ((256, 274), (200, 256), (134, 220), (96, 122))
    right = ((256, 274), (312, 252), (380, 220), (416, 118))
    parts = [wood(p, [tapered_d(left, 34, 16, wobble=0.12), tapered_d(right, 34, 16, wobble=0.12),
                      tapered_d(stem, 50, 32, wobble=0.1),
                      tapered_d(((170, 236), (166, 210), (178, 196), (186, 170)), 12, 6),
                      tapered_d(((340, 232), (346, 206), (334, 192), (326, 166)), 12, 6)]),
             bark_grain(p, stem, 40, 2),
             ash_sprig(p, 186, 170, -70, 0.8), ash_sprig(p, 326, 166, -110, 0.8),
             ash_sprig(p, 130, 214, -160, 0.9), ash_sprig(p, 384, 212, -20, 0.9),
             ash_sprig(p, 210, 262, 160, 0.7), ash_sprig(p, 306, 258, 20, 0.7),
             node(p, 96, 110, 38, "f"), node(p, 416, 106, 38, "u"),
             node(p, 256, 270, 44, "th", done=True, current=True)]
    return svg(512, 512, "\n".join(parts), "branch fork between skills")


# ===================================================================== SHEET
def sheet_html(files: dict[str, str]) -> str:
    def inl(name: str, w: str) -> str:
        return f'<div class="piece" style="width:{w}">{files[name]}<div class="cap">{name}</div></div>'

    def sized(name: str, size: int) -> str:
        return f'<div class="sz"><div style="width:{size}px;height:{size}px">{files[name]}</div><span>{size}</span></div>'

    pal = [("ink", COLOR["ink"]), ("rust", COLOR["rust"]), ("rust 2", COLOR["rust2"]), ("cream", COLOR["cream"]),
           ("bark", COLOR["bark"]), ("leaf", COLOR["leaf"]), ("leaf 2", COLOR["leaf2"]), ("gold", COLOR["gold"]),
           ("water", COLOR["water"]), ("bg", COLOR["bg"])]
    swatches = "".join(f'<div class="sw"><i style="background:{hx}"></i><b>{n}</b><code>{hx}</code></div>' for n, hx in pal)
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk brand sheet: logo first</title>
<style>
 body{{margin:0;padding:28px 36px;background:{COLOR['bg']};color:{COLOR['ink']};font:15px/1.4 Georgia,serif}}
 h1{{font-size:36px;margin:0 0 4px}} h2{{font-size:18px;margin:26px 0 8px;border-bottom:1px solid #d9cdb8;padding-bottom:4px}}
 .row{{display:flex;gap:16px;align-items:flex-start;flex-wrap:wrap}}
 .piece{{background:#fff;border:1px solid #d9cdb8;border-radius:12px;padding:10px;box-sizing:border-box}}
 .piece.dark{{background:{COLOR['bg']}}}
 .piece svg{{width:100%;height:auto;display:block}}
 .cap{{font-size:12px;color:#6b5a48;margin-top:6px;text-align:center}}
 .sz{{display:inline-flex;flex-direction:column;align-items:center;gap:4px;margin-right:22px;vertical-align:bottom}}
 .sz svg{{width:100%;height:100%;display:block}} .sz span{{font-size:11px;color:#6b5a48}}
 .sw{{display:inline-flex;flex-direction:column;align-items:center;margin-right:14px;font-size:12px}}
 .sw i{{display:block;width:56px;height:56px;border-radius:10px;border:1px solid #c8bba6}} .sw code{{font-size:11px}}
 .type{{display:flex;gap:30px;font-size:14px}} .type b{{display:block}}
 .mono{{background:#fff}}
</style></head><body>
<h1>tosk</h1>
<div>Logo-first exploration. Ratatosk, the messenger squirrel of Yggdrasil, carrying words between languages. Org: linguaperta.</div>

<h2>1. Mark concepts</h2>
<div class="piece" style="width:940px">{files['concepts.svg']}</div>

<h2>2. The mark, refined, at size</h2>
<div class="row">
 <div class="piece" style="width:160px">{files['mark.svg']}<div class="cap">mark.svg</div></div>
 <div class="piece" style="width:160px">{files['mark-mono.svg']}<div class="cap">mark-mono.svg</div></div>
 <div class="piece" style="padding:18px 22px">
  {sized('mark.svg',16)}{sized('mark.svg',32)}{sized('mark.svg',48)}{sized('mark.svg',96)}
  <div style="height:14px"></div>
  {sized('icon.svg',16)}{sized('icon.svg',32)}{sized('icon.svg',48)}{sized('icon.svg',96)}
  <div style="height:14px"></div>
  {sized('icon-mono.svg',16)}{sized('icon-mono.svg',32)}{sized('icon-mono.svg',48)}{sized('icon-mono.svg',96)}
 </div>
 <div class="piece" style="width:150px">{files['icon.svg']}<div class="cap">icon.svg</div></div>
 <div class="piece" style="width:150px">{files['icon-mono.svg']}<div class="cap">icon-mono.svg</div></div>
</div>

<h2>3. Lockup</h2>
<div class="row">
 <div class="piece" style="width:420px">{files['logo.svg']}<div class="cap">logo.svg</div></div>
 <div class="piece" style="width:420px;background:{COLOR['rust']}">{files['logo-reverse.svg']}<div class="cap" style="color:#fff">on rust</div></div>
</div>

<h2>4. Tosk, the mascot</h2>
<div class="row">
 {inl('tosk.svg', '330px')}{inl('tosk-mono.svg', '330px')}
 {inl('branch-tile.svg', '240px')}{inl('branch-tile-mono.svg', '240px')}
</div>

<h2>5. Yggdrasil, the course tree</h2>
<div class="row">
 {inl('yggdrasil.svg', '400px')}{inl('yggdrasil-mono.svg', '400px')}
 <div style="width:420px">
  <h2 style="margin-top:0">Palette</h2>
  <div>{swatches}</div>
  <div style="margin-top:8px;font-size:12px">Mono / e-ink: pure #000000 on #FFFFFF, no greys.</div>
  <h2>Type</h2>
  <div class="type">
   <div><b>Wordmark</b>custom monoline lowercase, round terminals (paths in logo.svg)</div>
   <div><b>UI</b>Atkinson Hyperlegible (OFL): e-ink friendly, open counters</div>
   <div><b>Reading</b>Literata (OFL): for pack text and books</div>
  </div>
 </div>
</div>
</body></html>
"""


def main() -> None:
    files: dict[str, str] = {
        "concepts.svg": concepts_svg(COLOR),
        "mark.svg": svg(100, 100, mark(COLOR, "plain"), "tosk mark"),
        "mark-mono.svg": svg(100, 100, mark(MONO, "plain"), "tosk mark (mono)"),
        "logo.svg": logo_svg(COLOR),
        "logo-reverse.svg": svg(360, 130, f'<g transform="translate(20 10) scale(1.1)">{mark(dict(COLOR, rust=COLOR["cream"]), "plain")}</g>'
                                f'{wordmark(COLOR, 150, 10, 1.1, COLOR["cream"])}', "tosk logo, reversed"),
        "icon.svg": icon_svg(COLOR),
        "icon-mono.svg": icon_svg(MONO, mono=True),
        "tosk.svg": tosk_svg(COLOR),
        "tosk-mono.svg": tosk_svg(MONO),
        "yggdrasil.svg": yggdrasil_svg(COLOR),
        "yggdrasil-mono.svg": yggdrasil_svg(MONO),
        "branch-tile.svg": branch_tile_svg(COLOR),
        "branch-tile-mono.svg": branch_tile_svg(MONO),
    }
    for name, content in files.items():
        (HERE / name).write_text(content, encoding="utf-8")
    (HERE / "sheet.html").write_text(sheet_html(files), encoding="utf-8")
    print("wrote", len(files) + 1, "files to", HERE)


if __name__ == "__main__":
    main()
