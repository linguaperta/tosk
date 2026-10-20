"""tosk brand exploration: elegant MONOLINE style.

Everything is drawn with one line weight (round caps and joins) as long,
flowing strokes. The colour version adds a few soft flat colour blocks that sit
slightly offset from the line (a misregistered-print look); the mono version is
the pure line, for e-ink.

Run:  python make_monoline.py   -> writes the SVGs + sheet.html next to it.
Pure Python, no dependencies.
"""
from __future__ import annotations

from pathlib import Path

OUT = Path(__file__).resolve().parent

# ---------------------------------------------------------------- palettes
COLOR = dict(
    ink="#2B2622",      # warm near-black line
    rust="#E38A5C",     # Tosk's fur
    cream="#F5E6C6",    # belly, scroll, nodes
    sage="#A7BE92",     # ash leaves
    tan="#D4B48C",      # bark / branches
    gold="#EAC36E",     # skill nodes, runes
    paper="#F7F2E8",    # icon / sheet background
    sky="#CFE0DE",      # a whisper of sky in the tree
)
MONO = dict(
    ink="#000000", rust="none", cream="none", sage="none", tan="none",
    gold="none", paper="#FFFFFF", sky="none",
)

# misregistration offset of the colour blocks, in user units of a 512 canvas
DX, DY = 7, 6


# ---------------------------------------------------------------- helpers
def svg(w: int, h: int, body: str, title: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}">\n<title>{title}</title>\n{body}\n</svg>\n'
    )


def line(d: str, ink: str, w: float) -> str:
    return (
        f'<path d="{d}" fill="none" stroke="{ink}" stroke-width="{w}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def dot(cx: float, cy: float, r: float, ink: str) -> str:
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{ink}"/>'


def block(d: str, color: str) -> str:
    """A flat colour block with no outline (the misregistered print layer)."""
    if color == "none":
        return ""
    return f'<path d="{d}" fill="{color}"/>'


def blocks(parts: list[str], dx: float, dy: float) -> str:
    inner = "\n".join(p for p in parts if p)
    if not inner:
        return ""
    return f'<g transform="translate({dx} {dy})">\n{inner}\n</g>'


def circ_block(cx: float, cy: float, r: float, color: str) -> str:
    if color == "none":
        return ""
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/>'


# ---------------------------------------------------------------- ash leaf
def frond(x: float, y: float, ang: float, s: float, ink: str, w: float,
          leaf_color: str, n: int = 5) -> tuple[str, str]:
    """A pinnate ash leaf: a stem with n pointed leaflets (lens shapes), one
    terminal leaflet at the tip. Returns (lines, colour blocks). Local space:
    the stem runs along +x from 0 and droops a little.
    """
    length = 96
    stem = f"M 0 0 C {length*0.4:.0f} 2, {length*0.7:.0f} 6, {length} 14"
    lines = [stem]
    fills = []

    def lens(L: float, W: float) -> str:
        return (f"M 0 0 C {L*0.25:.1f} {-W:.1f}, {L*0.75:.1f} {-W*0.7:.1f}, {L:.1f} 0 "
                f"C {L*0.75:.1f} {W*0.7:.1f}, {L*0.25:.1f} {W:.1f}, 0 0 Z")

    # pairs along the stem
    for i in range(n - 1):
        t = 0.3 + 0.6 * i / max(1, n - 2)
        px = length * t
        py = 2 * t + 10 * t * t
        L = 36 * (1 - 0.3 * i / (n - 1))
        W = 9 * (1 - 0.25 * i / (n - 1))
        for side, a in ((-1, -52), (1, 52)):
            fills.append((px, py, a + 8 * t, L, W))
    # terminal leaflet
    fills.append((length, 14, 10, 34, 8))
    g_open = f'<g transform="translate({x} {y}) rotate({ang}) scale({s})">'
    parts = [line(stem, ink, w / s)]
    fparts = []
    for px, py, a, L, W in fills:
        d = lens(L, W)
        parts.append(f'<g transform="translate({px:.1f} {py:.1f}) rotate({a:.1f})">{line(d, ink, w / s)}</g>')
        if leaf_color != "none":
            fparts.append(f'<g transform="translate({px:.1f} {py:.1f}) rotate({a:.1f})">{block(d, leaf_color)}</g>')
    l = g_open + "\n".join(parts) + "</g>"
    f = g_open + "\n".join(fparts) + "</g>" if fparts else ""
    return l, f


def spiral(cx: float, cy: float, r0: float, r1: float, a0: float, turns: float,
           step_deg: float = 12.0) -> str:
    """Path data (no leading M) for a log spiral from radius r0 to r1 starting at
    angle a0 (degrees, screen clockwise), as a smooth Catmull-Rom -> Bezier chain."""
    import math
    total = turns * 360.0
    k = math.log(r1 / r0) / total
    pts = []
    n = int(total / step_deg) + 1
    for i in range(n + 1):
        a = a0 + total * i / n
        r = r0 * math.exp(k * (a - a0))
        pts.append((cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))))
    out = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        out.append(f"C {c1[0]:.1f} {c1[1]:.1f}, {c2[0]:.1f} {c2[1]:.1f}, {p2[0]:.1f} {p2[1]:.1f}")
    return " ".join(out)


# ---------------------------------------------------------------- Tosk
# Canvas 512 x 512, facing right, sitting on a bough, holding a message scroll.
T = dict(
    # nose -> forehead -> ear tuft -> back of head -> back -> rump -> tail outer edge -> spiral
    head_back_tail=(
        "M 398 250 "
        "C 390 220, 362 186, 334 180 "       # bridge of the nose up to the forehead
        "C 342 158, 350 132, 354 108 "       # ear: front edge up to the tuft tip
        "C 330 118, 310 150, 304 186 "       # ear: back edge down
        "C 296 206, 286 216, 278 226 "       # back of head to the neck
        "C 218 250, 184 312, 196 362 "       # rounded back
        "C 202 390, 210 408, 220 422 "       # rump sitting on the bough
        "C 118 440, 40 330, 56 222 "         # tail: outer edge sweeping up
        "C 70 108, 172 36, 258 56 "          # over the top of the plume
        "C 318 70, 330 148, 276 160 "        # curling forward and down
        "C 236 168, 228 118, 264 118 "       # the spiral tip
    ),
    # nose -> chin -> chest -> belly down to the foot
    front=(
        "M 398 250 "
        "C 404 268, 390 282, 372 280 "       # mouth / chin curl
        "C 376 312, 384 352, 362 390 "       # chest and belly bulge
        "C 352 408, 346 420, 346 432 "       # down to the top of the foot
    ),
    # thigh "C" from the belly down to the heel, then the hind foot forward
    haunch="M 346 356 C 290 346, 252 392, 266 430 C 290 440, 330 442, 372 432 C 384 429, 386 424, 378 420",
    # fore leg from the shoulder to the paws holding the scroll
    foreleg="M 318 292 C 332 300, 344 316, 350 334",
    paw2="M 332 320 C 340 326, 346 336, 350 348",
    # ear inner tuft line
    tuft="M 354 108 C 360 96, 366 90, 374 84",
    tuft2="M 354 108 C 352 96, 354 88, 358 78",
    brow="M 338 204 C 348 198, 360 200, 368 208",
    whisker1="M 386 262 L 408 270",
    whisker2="M 384 270 L 404 284",
)
TOSK_EYE = (356, 220, 7)
TOSK_NOSE = "M 398 250 C 406 246, 410 252, 404 258 C 400 262, 396 256, 398 250 Z"

# scroll held in the paws: a small rolled letter with a curl at each end
SCROLL = dict(
    body="M 354 328 C 376 322, 400 318, 424 322",
    body2="M 356 352 C 378 346, 402 342, 426 346",
    curl1="M 424 322 C 440 322, 442 346, 426 346 C 418 346, 418 334, 428 334",
    curl2="M 354 328 C 338 330, 338 352, 356 352",
    rune="M 390 332 L 390 344 M 384 336 L 390 331 L 396 336",
)
# colour blocks (closed silhouettes, approximate on purpose)
TOSK_FUR = (
    "M 398 250 C 390 220, 362 186, 334 180 C 342 158, 350 132, 354 108 "
    "C 330 118, 310 150, 304 186 C 296 206, 286 216, 278 226 "
    "C 218 250, 184 312, 196 362 C 202 390, 210 408, 220 422 "
    "C 118 440, 40 330, 56 222 C 70 108, 172 36, 258 56 C 318 70, 330 148, 276 160 "
    "C 262 176, 250 200, 246 230 C 240 290, 236 360, 256 430 "
    "C 300 442, 340 440, 372 432 L 346 432 C 346 420, 352 408, 362 390 "
    "C 384 352, 376 312, 372 280 C 390 282, 404 268, 398 250 Z"
)
TOSK_BELLY = (
    "M 372 282 C 376 312, 384 352, 362 390 C 352 408, 346 420, 346 432 "
    "L 316 432 C 300 400, 320 360, 330 330 C 338 310, 348 292, 372 282 Z"
)
TOSK_BOUGH_TOP = "M 0 448 C 140 436, 330 442, 512 422"
TOSK_BOUGH_BOT = "M 0 478 C 140 466, 330 472, 512 452"
TOSK_BOUGH_FILL = "M 0 448 C 140 436, 330 442, 512 422 L 512 452 C 330 472, 140 466, 0 478 Z"
SCROLL_FILL = "M 354 328 C 376 322, 400 318, 424 322 L 426 346 C 402 342, 378 346, 356 352 Z"


def tosk(p: dict, w: float = 7) -> str:
    ink = p["ink"]
    fills = blocks([
        block(TOSK_BOUGH_FILL, p["tan"]),
        block(TOSK_FUR, p["rust"]),
        block(TOSK_BELLY, p["cream"]),
        block(SCROLL_FILL, p["cream"]),
    ], DX, DY)
    leaf_l, leaf_f = frond(458, 428, -28, 0.75, ink, w, p["sage"])
    leaf2_l, leaf2_f = frond(74, 470, 196, 0.6, ink, w, p["sage"], n=4)
    out = [fills]
    if leaf_f:
        out.append(blocks([leaf_f, leaf2_f], DX, DY))
    out += [
        line(TOSK_BOUGH_TOP, ink, w), line(TOSK_BOUGH_BOT, ink, w),
        leaf_l, leaf2_l,
        line(T["head_back_tail"], ink, w),
        line(T["front"], ink, w),
        line(T["haunch"], ink, w),
        line(T["foreleg"], ink, w),
        line(T["paw2"], ink, w),
        line(T["tuft"], ink, w), line(T["tuft2"], ink, w),
        line(T["brow"], ink, w),
        line(T["whisker1"], ink, w),
        line(T["whisker2"], ink, w),
        line(SCROLL["body"], ink, w), line(SCROLL["body2"], ink, w),
        line(SCROLL["curl1"], ink, w), line(SCROLL["curl2"], ink, w),
        line(SCROLL["rune"], ink, w * 0.8),
        dot(*TOSK_EYE, ink),
        f'<path d="{TOSK_NOSE}" fill="{ink}"/>',
    ]
    return "\n".join(out)


# ---------------------------------------------------------------- icon mark
# One continuous line: nose, forehead, ear tuft, back of head, back, rump, then
# the tail as a log spiral curling in. Plus an eye dot and a chest line.
SP = dict(cx=190, cy=290, r0=140, r1=58, a0=62, turns=1.22)
MARK_BODY = (
    "M 438 246 "
    "C 430 200, 400 170, 364 166 "   # muzzle up to forehead
    "C 366 140, 374 110, 390 84 "    # ear front up to tuft
    "C 356 100, 334 132, 326 168 "   # ear back down
    "C 318 180, 314 190, 312 196 "   # back of head
    "C 318 260, 300 360, 256 414 "   # back down to the rump
)
MARK = MARK_BODY + spiral(**SP)
MARK_CHEST = "M 438 246 C 446 290, 428 350, 380 396 C 360 414, 330 426, 300 428"
MARK_EYE = (384, 212, 16)
MARK_FUR = (
    MARK_BODY + spiral(SP["cx"], SP["cy"], SP["r0"], SP["r0"] * 0.999, SP["a0"], 0.999)
    + " C 318 300, 400 380, 438 246 Z"
)


def icon(p: dict, w: float = 26, bg: bool = True) -> str:
    ink = p["ink"]
    out = []
    if bg:
        if p["rust"] == "none":
            out.append(f'<rect x="12" y="12" width="488" height="488" rx="110" fill="{p["paper"]}" '
                       f'stroke="{ink}" stroke-width="{w * 0.6}"/>')
        else:
            out.append(f'<rect width="512" height="512" rx="118" fill="{p["paper"]}"/>')
    out.append(blocks([block(MARK_FUR, p["rust"])], 12, 10))
    out += [line(MARK, ink, w), line(MARK_CHEST, ink, w), dot(*MARK_EYE, ink)]
    return "\n".join(out)


# ---------------------------------------------------------------- wordmark
def wordmark(x: float, y: float, ink: str, w: float = 18, s: float = 1.0) -> str:
    """'tosk' in lowercase monoline letters. Baseline at local y=130, x-height 100."""
    d = [
        "M 34 -10 L 34 96 C 34 124, 54 134, 76 124",   # t stem with hook
        "M 8 30 L 64 30",                              # t bar
        "M 182 80 m -52 0 a 52 52 0 1 0 104 0 a 52 52 0 1 0 -104 0",  # o
        "M 318 46 C 312 28, 262 26, 262 52 C 262 82, 322 72, 322 104 C 322 134, 266 134, 258 112",  # s
        "M 372 -10 L 372 130",                         # k stem
        "M 430 38 L 374 94 L 438 130",                 # k arms
    ]
    g = f'<g transform="translate({x} {y}) scale({s})">'
    return g + "\n".join(line(p, ink, w) for p in d) + "</g>"


def logo(p: dict) -> str:
    ink = p["ink"]
    out = [f'<g transform="translate(20 10) scale(0.5)">{icon(p, w=30, bg=False)}</g>']
    out.append(wordmark(300, 72, ink, w=16))
    return "\n".join(out)


# ---------------------------------------------------------------- runes
def runes(x: float, y: float, ink: str, w: float, s: float = 1.0) -> str:
    """t o s k in Elder Futhark: Tiwaz, Othala, Sowilo, Kenaz, stacked."""
    d = [
        "M 0 0 L 0 40 M -14 12 L 0 0 L 14 12",                 # Tiwaz
        "M -12 76 L 0 60 L 12 76 L 0 92 Z M -12 104 L 0 90 L 12 104",  # Othala-ish (diamond + legs)
        "M 10 120 L -8 136 L 10 150 L -8 166",                 # Sowilo zigzag
        "M 12 184 L -8 200 L 12 216",                          # Kenaz
    ]
    g = f'<g transform="translate({x} {y}) scale({s})">'
    return g + "\n".join(line(p, ink, w / s) for p in d) + "</g>"


# ---------------------------------------------------------------- Yggdrasil
YW, YH = 800, 1100
NODE_R = 26

# each branch: (trunk attach point, upper-edge path to node, lower edge that merges, node centre, side)
BRANCHES = [
    # (upper edge, lower edge, node)
    ("M 352 820 C 300 790, 230 770, 150 772", "M 346 856 C 300 830, 250 800, 200 790", (120, 772)),
    ("M 446 760 C 500 730, 570 700, 650 712", "M 450 796 C 500 770, 560 740, 600 724", (682, 714)),
    ("M 360 660 C 320 620, 250 580, 180 590", "M 356 696 C 320 660, 270 620, 230 606", (150, 590)),
    ("M 440 580 C 480 540, 540 500, 620 500", "M 442 616 C 480 580, 540 540, 580 516", (652, 500)),
    ("M 372 480 C 340 430, 290 400, 230 396", "M 368 516 C 340 470, 300 430, 268 410", (200, 396)),
    ("M 430 410 C 470 360, 520 330, 590 330", "M 432 446 C 470 400, 520 360, 560 344", (622, 330)),
]
TOP_NODE = (400, 150)
TRUNK_L = "M 318 960 C 350 820, 352 660, 368 500 C 378 400, 384 300, 388 200"
TRUNK_R = "M 482 960 C 452 820, 450 660, 436 500 C 426 400, 418 300, 412 200"
TRUNK_FILL = ("M 318 960 C 350 820, 352 660, 368 500 C 378 400, 384 300, 388 200 "
              "L 412 200 C 418 300, 426 400, 436 500 C 450 660, 452 820, 482 960 Z")
ROOTS = [
    # left root, two edges meeting at the tip
    ("M 318 960 C 300 1000, 230 1020, 110 1060", "M 352 990 C 310 1030, 240 1040, 110 1060"),
    # middle root
    ("M 372 985 C 380 1020, 390 1050, 404 1086", "M 428 985 C 420 1020, 412 1050, 404 1086"),
    # right root
    ("M 482 960 C 500 1000, 570 1020, 690 1060", "M 448 990 C 490 1030, 560 1040, 690 1060"),
]
ROOT_FILLS = [
    "M 318 960 C 300 1000, 230 1020, 110 1060 C 240 1040, 310 1030, 352 990 Z",
    "M 372 985 C 380 1020, 390 1050, 404 1086 C 412 1050, 420 1020, 428 985 Z",
    "M 482 960 C 500 1000, 570 1020, 690 1060 C 560 1040, 490 1030, 448 990 Z",
]
GROUND = ["M 40 1020 C 70 1012, 90 1016, 112 1012", "M 700 1030 C 730 1022, 750 1026, 772 1024"]
WELL = dict(rim="M 196 1032 C 196 1016, 300 1016, 300 1032 C 300 1048, 196 1048, 196 1032 Z",
            ripple="M 222 1030 C 236 1024, 262 1024, 276 1030", fill="M 196 1032 C 196 1016, 300 1016, 300 1032 C 300 1048, 196 1048, 196 1032 Z")
# Nidhoggr: a serpent coiled around the right root, head up
DRAGON = ("M 560 1082 C 590 1070, 596 1030, 572 1018 C 548 1006, 530 1030, 550 1044 "
          "C 575 1058, 610 1038, 628 1012 C 640 996, 630 984, 616 988")
DRAGON_HEAD = "M 616 988 C 606 980, 602 972, 612 968 L 626 972"
# eagle perched above the top node, wings half open
EAGLE = ("M 310 112 C 340 84, 372 86, 392 102 "    # left wing into the shoulder
         "C 392 86, 404 78, 414 84 L 428 90 "      # head and beak
         "C 420 94, 416 96, 410 98 "               # under the beak
         "C 430 84, 470 78, 500 110")              # right wing
EAGLE_BODY = "M 392 104 C 386 118, 396 128, 404 128 C 414 128, 418 118, 410 104"


def yggdrasil(p: dict, w: float = 7, with_tosk: bool = True) -> str:
    ink = p["ink"]
    fills: list[str] = [block(TRUNK_FILL, p["tan"])]
    for d in ROOT_FILLS:
        fills.append(block(d, p["tan"]))
    fills.append(block(WELL["fill"], p["sky"]))
    out = [blocks(fills, 9, 7)]

    # fronds: (x, y, angle, scale)
    fronds = [
        (150, 772, 200, 0.7), (160, 740, -150, 0.6),
        (650, 712, -20, 0.7), (640, 680, -40, 0.55),
        (180, 590, 190, 0.7), (190, 560, -160, 0.55),
        (620, 500, -15, 0.7), (600, 470, -50, 0.55),
        (230, 396, 205, 0.7), (250, 365, -140, 0.55),
        (590, 330, -25, 0.7), (570, 300, -60, 0.55),
        # crown
        (392, 196, -130, 0.75), (408, 196, -50, 0.75), (380, 230, 200, 0.6), (420, 230, -20, 0.6),
        (372, 262, 215, 0.55), (428, 262, -35, 0.55),
        # twigs off the trunk
        (384, 330, -100, 0.5), (420, 300, -80, 0.5),
    ]
    leaf_lines, leaf_fills = [], []
    for fx, fy, fa, fs in fronds:
        l, f = frond(fx, fy, fa, fs, ink, w, p["sage"])
        leaf_lines.append(l)
        leaf_fills.append(f)
    if p["sage"] != "none":
        out.append(blocks(leaf_fills, 9, 7))
    node_fill = p["gold"] if p["gold"] != "none" else "none"
    if node_fill != "none":
        out.append(blocks([circ_block(nx, ny, NODE_R, node_fill) for *_, (nx, ny) in BRANCHES]
                          + [circ_block(*TOP_NODE, NODE_R, node_fill)], 8, 7))

    out += [line(TRUNK_L, ink, w), line(TRUNK_R, ink, w)]
    for a, b in ROOTS:
        out += [line(a, ink, w), line(b, ink, w)]
    out += [line(g, ink, w) for g in GROUND]
    out += [line(WELL["rim"], ink, w), line(WELL["ripple"], ink, w)]
    out += [line(DRAGON, ink, w), line(DRAGON_HEAD, ink, w), dot(614, 972, 3.5, ink)]
    for up, lo, _ in BRANCHES:
        out += [line(up, ink, w), line(lo, ink, w)]
    # the trunk closes into the top node
    out += [line("M 388 200 C 390 186, 394 178, 400 176", ink, w),
            line("M 412 200 C 410 186, 406 178, 400 176", ink, w)]
    out += leaf_lines
    out += [line(EAGLE, ink, w), line(EAGLE_BODY, ink, w), dot(410, 86, 3.5, ink)]
    out.append(runes(400, 560, ink, w, 1.1))
    # skill nodes (paper fill hides the branch line underneath)
    for *_, (nx, ny) in BRANCHES:
        out.append(f'<circle cx="{nx}" cy="{ny}" r="{NODE_R}" fill="{p["paper"]}" stroke="{ink}" stroke-width="{w}"/>')
    out.append(f'<circle cx="{TOP_NODE[0]}" cy="{TOP_NODE[1]}" r="{NODE_R}" fill="{p["paper"]}" stroke="{ink}" stroke-width="{w}"/>')
    if with_tosk:
        # little Tosk running up the trunk (the icon mark, small)
        out.append(f'<g transform="translate(300 880) scale(0.22) rotate(-28 256 256)">{icon(p, w=30, bg=False)}</g>')
    return "\n".join(out)


# ---------------------------------------------------------------- branch tile
BW, BH = 400, 400
TILE = dict(
    bough_l="M 186 400 C 190 350, 196 300, 200 262",
    bough_r="M 214 400 C 210 350, 204 300, 200 262",
    bough_fill="M 186 400 C 190 350, 196 300, 200 262 C 204 300, 210 350, 214 400 Z",
    left_up="M 196 250 C 170 200, 130 150, 96 100",
    left_lo="M 188 262 C 168 230, 146 190, 120 150",
    right_up="M 204 250 C 230 200, 266 150, 304 104",
    right_lo="M 212 262 C 232 230, 254 190, 280 150",
    nodes=[(200, 262), (84, 84), (316, 88)],
)


def branch_tile(p: dict, w: float = 7) -> str:
    ink = p["ink"]
    out = [blocks([block(TILE["bough_fill"], p["tan"])], 6, 5)]
    fronds = [(140, 170, 160, 0.55), (262, 170, 20, 0.55), (120, 190, -120, 0.4), (280, 190, -60, 0.4)]
    leaf_lines, leaf_fills = [], []
    for fx, fy, fa, fs in fronds:
        l, f = frond(fx, fy, fa, fs, ink, w, p["sage"])
        leaf_lines.append(l)
        leaf_fills.append(f)
    if p["sage"] != "none":
        out.append(blocks(leaf_fills, 6, 5))
    if p["gold"] != "none":
        out.append(blocks([circ_block(x, y, NODE_R, p["gold"]) for x, y in TILE["nodes"]], 6, 5))
    for k in ("bough_l", "bough_r", "left_up", "left_lo", "right_up", "right_lo"):
        out.append(line(TILE[k], ink, w))
    out += leaf_lines
    for x, y in TILE["nodes"]:
        out.append(f'<circle cx="{x}" cy="{y}" r="{NODE_R}" fill="{p["paper"]}" stroke="{ink}" stroke-width="{w}"/>')
    return "\n".join(out)


# ---------------------------------------------------------------- sheet
SHEET = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>tosk - monoline exploration</title>
<style>
  body {{ margin: 0; padding: 28px 36px; background: #F3EEE4; color: #2B2622;
         font: 15px/1.4 Georgia, 'Times New Roman', serif; }}
  h1 {{ font-size: 40px; margin: 0 0 4px; letter-spacing: -0.5px; }}
  p.sub {{ margin: 0 0 22px; color: #5a514a; }}
  .grid {{ display: grid; grid-template-columns: repeat(12, 1fr); gap: 18px; }}
  .card {{ background: #FBF8F2; border: 1px solid #DDD4C6; border-radius: 14px; padding: 12px; }}
  .card.mono {{ background: #FFFFFF; }}
  .card h2 {{ font-size: 13px; font-weight: normal; text-transform: uppercase; letter-spacing: 1.5px;
             margin: 0 0 8px; color: #7a6f64; }}
  .card img.big {{ display: block; width: 100%; height: auto; }}
  .row img {{ display: block; }}
  .row {{ display: flex; gap: 14px; align-items: flex-end; flex-wrap: wrap; }}
  .sw {{ display: inline-block; width: 64px; margin: 0 8px 8px 0; font-size: 11px; text-align: center; }}
  .sw i {{ display: block; height: 44px; border-radius: 8px; border: 1px solid #DDD4C6; margin-bottom: 4px; }}
  .cap {{ font-size: 11px; color: #7a6f64; text-align: center; margin-top: 4px; }}
</style></head><body>
<h1>tosk <span style="font-size:16px;color:#7a6f64;font-weight:normal">&nbsp; monoline exploration</span></h1>
<p class="sub">One line weight, long flowing strokes. Colour blocks sit a touch off-register under the line; the e-ink version is the pure line.</p>
<div class="grid">
  <div class="card" style="grid-column: span 3"><h2>Tosk</h2><img class="big" src="tosk.svg"></div>
  <div class="card mono" style="grid-column: span 3"><h2>Tosk - e-ink</h2><img class="big" src="tosk-mono.svg"></div>
  <div class="card" style="grid-column: span 6"><h2>Logo</h2><img class="big" src="logo.svg" style="max-width:560px;margin:10px auto">
    <div class="row" style="margin-top:14px">
      <div><img src="icon.svg" width="48" height="48"><div class="cap">48</div></div>
      <div><img src="icon.svg" width="96" height="96"><div class="cap">96</div></div>
      <div><img src="icon-mono.svg" width="48" height="48"><div class="cap">48 e-ink</div></div>
      <div><img src="icon-mono.svg" width="96" height="96"><div class="cap">96 e-ink</div></div>
      <div><img src="icon.svg" width="192" height="192"><div class="cap">192</div></div>
      <div><img src="icon-mono.svg" width="192" height="192"><div class="cap">192 e-ink</div></div>
    </div>
    <h2 style="margin-top:16px">Palette</h2>
    <div>{swatches}</div>
  </div>
  <div class="card" style="grid-column: span 3"><h2>Yggdrasil - course tree</h2><img class="big" src="yggdrasil.svg"></div>
  <div class="card mono" style="grid-column: span 3"><h2>Yggdrasil - e-ink</h2><img class="big" src="yggdrasil-mono.svg"></div>
  <div class="card" style="grid-column: span 3"><h2>Branch tile</h2><img class="big" src="branch-tile.svg"><h2 style="margin-top:10px">Branch tile - e-ink</h2><img class="big" src="branch-tile-mono.svg" style="background:#fff;border-radius:8px"></div>
  <div class="card" style="grid-column: span 3"><h2>Tosk at 160 / 96</h2>
    <div class="row"><img src="tosk.svg" width="160" height="160"><img src="tosk-mono.svg" width="160" height="160" style="background:#fff"></div>
    <div class="row" style="margin-top:10px"><img src="tosk.svg" width="96" height="96"><img src="tosk-mono.svg" width="96" height="96" style="background:#fff"><img src="branch-tile.svg" width="96" height="96"><img src="branch-tile-mono.svg" width="96" height="96" style="background:#fff"></div>
    <div class="row" style="margin-top:10px"><img src="yggdrasil.svg" width="120"><img src="yggdrasil-mono.svg" width="120" style="background:#fff"></div>
  </div>
</div>
</body></html>
"""


def main() -> None:
    files = {
        "tosk.svg": svg(512, 512, tosk(COLOR), "Tosk"),
        "tosk-mono.svg": svg(512, 512, tosk(MONO), "Tosk (e-ink)"),
        "icon.svg": svg(512, 512, icon(COLOR), "tosk app icon"),
        "icon-mono.svg": svg(512, 512, icon(MONO), "tosk app icon (e-ink)"),
        "logo.svg": svg(800, 290, logo(COLOR), "tosk logo"),
        "yggdrasil.svg": svg(YW, YH, yggdrasil(COLOR), "Yggdrasil course tree"),
        "yggdrasil-mono.svg": svg(YW, YH, yggdrasil(MONO), "Yggdrasil course tree (e-ink)"),
        "branch-tile.svg": svg(BW, BH, branch_tile(COLOR), "Branch tile"),
        "branch-tile-mono.svg": svg(BW, BH, branch_tile(MONO), "Branch tile (e-ink)"),
    }
    for name, body in files.items():
        (OUT / name).write_text(body, encoding="utf-8")
    sw = "".join(f'<span class="sw"><i style="background:{v}"></i>{k} {v}</span>' for k, v in COLOR.items())
    (OUT / "sheet.html").write_text(SHEET.format(swatches=sw), encoding="utf-8")
    print("wrote", ", ".join(files), "and sheet.html")


if __name__ == "__main__":
    main()
