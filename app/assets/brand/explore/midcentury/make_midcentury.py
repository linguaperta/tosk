"""tosk brand exploration: mid-century Scandinavian / retro print.

Run:  python make_midcentury.py   -> writes the SVGs + sheet.html next to this file.

No dependencies. Shapes are built from hand-placed Bezier centre-lines that are
turned into tapered, organic silhouettes numerically (see `plume`), so nothing
is a stacked ellipse. Every piece has a colour and a pure black/white version.
"""
from __future__ import annotations

import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- palette
PAL = dict(
    paper="#F4E8D1",   # warm cream paper
    orange="#E2602F",  # tomato / red-squirrel orange
    rust="#A8381B",    # deep rust (shadow ink)
    mustard="#E8B338", # mustard
    teal="#2C6B68",    # teal
    olive="#7C963C",   # olive leaf
    ink="#2A2119",     # warm near-black ink
    sky="#9BB7B4",     # pale mist (well, water)
)
MONO = dict(paper="#FFFFFF", orange="#000000", rust="#000000", mustard="#FFFFFF",
            teal="#000000", olive="#000000", ink="#000000", sky="#FFFFFF")

W, K = "#FFFFFF", "#000000"


def f(x: float) -> str:
    s = f"{x:.1f}"
    return s[:-2] if s.endswith(".0") else s


def svg(w: float, h: float, body: str, title: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(w)} {f(h)}" width="{f(w)}" height="{f(h)}">\n'
        f"<title>{title}</title>\n{body}\n</svg>\n"
    )


# ------------------------------------------------------------- geometry
def cubic(p0, p1, p2, p3, t):
    mt = 1 - t
    return (
        mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
        mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1],
    )


def chain(ctrl, n_per=28):
    """ctrl = [P0, C, C, P1, C, C, P2 ...] -> list of (point, unit tangent)."""
    segs = (len(ctrl) - 1) // 3
    out = []
    for s in range(segs):
        p0, p1, p2, p3 = ctrl[3 * s: 3 * s + 4]
        for i in range(n_per + (1 if s == segs - 1 else 0)):
            t = i / n_per
            p = cubic(p0, p1, p2, p3, t)
            q = cubic(p0, p1, p2, p3, min(1, t + 1e-3))
            r = cubic(p0, p1, p2, p3, max(0, t - 1e-3))
            tx, ty = q[0] - r[0], q[1] - r[1]
            L = math.hypot(tx, ty) or 1
            out.append((p, (tx / L, ty / L)))
    return out


def width_at(widths, u):
    """widths = [(u, w), ...] piecewise-linear, smoothed with a cosine ease."""
    for (u0, w0), (u1, w1) in zip(widths, widths[1:]):
        if u0 <= u <= u1:
            k = (u - u0) / (u1 - u0) if u1 > u0 else 0
            k = (1 - math.cos(k * math.pi)) / 2
            return w0 + (w1 - w0) * k
    return widths[-1][1]


def plume(ctrl, widths, n_per=28, round_end=True, round_start=False, offset=0.0):
    """Tapered organic silhouette along a Bezier chain. Returns a path 'd'."""
    pts = chain(ctrl, n_per)
    n = len(pts)
    left, right = [], []
    for i, (p, t) in enumerate(pts):
        u = i / (n - 1)
        w = width_at(widths, u) / 2
        nx, ny = -t[1], t[0]
        left.append((p[0] + nx * (w + offset), p[1] + ny * (w + offset)))
        right.append((p[0] - nx * (w - offset), p[1] - ny * (w - offset)))
    d = "M " + " L ".join(f"{f(x)},{f(y)}" for x, y in left)
    we = width_at(widths, 1) / 2
    if round_end and we > 0.5:
        d += f" A {f(we)},{f(we)} 0 0 1 {f(right[-1][0])},{f(right[-1][1])}"
    else:
        d += f" L {f(right[-1][0])},{f(right[-1][1])}"
    d += " L " + " L ".join(f"{f(x)},{f(y)}" for x, y in reversed(right))
    ws = width_at(widths, 0) / 2
    if round_start and ws > 0.5:
        d += f" A {f(ws)},{f(ws)} 0 0 1 {f(left[0][0])},{f(left[0][1])}"
    return d + " Z"


def offset_line(ctrl, widths, frac, n_per=28, u0=0.0, u1=1.0):
    """A polyline that runs inside a plume at `frac` of the half-width (-1..1)."""
    pts = chain(ctrl, n_per)
    n = len(pts)
    out = []
    for i, (p, t) in enumerate(pts):
        u = i / (n - 1)
        if u < u0 or u > u1:
            continue
        w = width_at(widths, u) / 2 * frac
        out.append((p[0] - t[1] * w, p[1] + t[0] * w))
    return "M " + " L ".join(f"{f(x)},{f(y)}" for x, y in out)


def point_at(ctrl, u, n_per=28):
    pts = chain(ctrl, n_per)
    i = min(len(pts) - 1, int(round(u * (len(pts) - 1))))
    return pts[i]


def lens(cx, cy, length, width, angle, fill, extra=""):
    """A leaf / petal lens shape, pointed at both ends, rotated by `angle` deg."""
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)

    def T(x, y):
        return f"{f(cx + x * ca - y * sa)},{f(cy + x * sa + y * ca)}"

    L, w = length / 2, width / 2
    d = (f"M {T(-L, 0)} C {T(-L * 0.45, -w * 1.25)} {T(L * 0.45, -w * 1.25)} {T(L, 0)} "
         f"C {T(L * 0.45, w * 1.25)} {T(-L * 0.45, w * 1.25)} {T(-L, 0)} Z")
    return f'<path d="{d}" fill="{fill}" {extra}/>'


def lens_vein(cx, cy, length, angle, stroke, sw=2.0):
    a = math.radians(angle)
    L = length / 2 * 0.8
    return (f'<path d="M {f(cx - L * math.cos(a))},{f(cy - L * math.sin(a))} '
            f'L {f(cx + L * math.cos(a))},{f(cy + L * math.sin(a))}" '
            f'stroke="{stroke}" stroke-width="{f(sw)}" stroke-linecap="round" fill="none"/>')


def circle(cx, cy, r, fill, extra=""):
    return f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="{fill}" {extra}/>'


def stroke_path(d, color, sw, extra=""):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{f(sw)}" '
            f'stroke-linecap="round" stroke-linejoin="round" {extra}/>')


# ---------------------------------------------------------------- ash leaf
def ash_frond(x, y, angle, length, p, mono, scale=1.0, n_pairs=3, leaf_cols=None):
    """A pinnate ash leaf: a stem with pairs of lens leaflets + a terminal one."""
    out = []
    a = math.radians(angle)
    ex, ey = x + length * math.cos(a), y + length * math.sin(a)
    stem_col = p["ink"] if not mono else K
    out.append(stroke_path(f"M {f(x)},{f(y)} L {f(ex)},{f(ey)}", stem_col, 2.2 * scale))
    cols = leaf_cols or [p["olive"], p["teal"], p["mustard"]]
    ll, lw = 26 * scale, 11 * scale
    for i in range(n_pairs):
        u = (i + 0.6) / (n_pairs + 0.5)
        px, py = x + length * u * math.cos(a), y + length * u * math.sin(a)
        for side in (-1, 1):
            la = angle + side * 48
            ra = math.radians(la)
            cx, cy = px + ll * 0.5 * math.cos(ra), py + ll * 0.5 * math.sin(ra)
            col = cols[(i + (0 if side < 0 else 1)) % len(cols)]
            if mono:
                out.append(lens(cx, cy, ll, lw, la, K))
                out.append(lens_vein(cx, cy, ll, la, W, 1.6 * scale))
            else:
                out.append(lens(cx, cy, ll, lw, la, col, 'fill-opacity="0.9"'))
    # terminal leaflet
    cx, cy = ex + ll * 0.45 * math.cos(a), ey + ll * 0.45 * math.sin(a)
    if mono:
        out.append(lens(cx, cy, ll, lw, angle, K))
        out.append(lens_vein(cx, cy, ll, angle, W, 1.6 * scale))
    else:
        out.append(lens(cx, cy, ll, lw, angle, cols[n_pairs % len(cols)], 'fill-opacity="0.9"'))
    return "\n".join(out)


# ------------------------------------------------------------------- Tosk
# Coordinate space 400 x 400, facing right, sitting up on a branch.
TAIL_CTRL = [(205, 320), (110, 326), (56, 250), (70, 170),
             (82, 96), (150, 40), (222, 56),
             (262, 66), (284, 100), (270, 136)]
TAIL_W = [(0, 36), (0.22, 82), (0.55, 100), (0.82, 70), (1.0, 30)]


def fur_ticks(ctrl, widths, color, fracs=(-0.5, 0.0, 0.5), step=5, length=9, sw=3.2, skew=0.55, u0=0.05, u1=0.95):
    """Rhythmic short strokes inside a plume, angled off the tangent: fur as pattern."""
    pts = chain(ctrl)
    n = len(pts)
    o = []
    for j, frac in enumerate(fracs):
        for k in range(2 + j * (step // 2), n - 2, step):
            u = k / (n - 1)
            if u < u0 or u > u1:
                continue
            (px, py), (tx, ty) = pts[k]
            w = width_at(widths, u) / 2 * frac
            cx, cy = px - ty * w, py + tx * w
            dx, dy = -tx * length - ty * length * skew, -ty * length + tx * length * skew
            o.append(stroke_path(f"M {f(cx)},{f(cy)} L {f(cx + dx)},{f(cy + dy)}", color, sw))
    return "\n".join(o)


def tosk(p, mono=False, with_branch=True, scale=1.0, ox=0.0, oy=0.0, letter=True):
    o = []
    ink = K if mono else p["ink"]
    fur = W if mono else p["orange"]
    rust = K if mono else p["rust"]
    cream = W if mono else p["paper"]
    must = W if mono else p["mustard"]
    sw = 4.5  # mono outline

    if with_branch:
        bctrl = [(0, 352), (120, 332), (260, 350), (400, 318)]
        bw = [(0, 30), (1, 24)]
        o.append(f'<path d="{plume(bctrl, bw, round_end=False)}" fill="{ink}"/>')
        # bark rhythm: short cream dashes
        for k in range(12):
            u = 0.04 + k * 0.08
            (px, py), (tx, ty) = point_at(bctrl, u)
            frac = (-0.45, 0.1, 0.45)[k % 3]
            w = width_at(bw, u) / 2 * frac
            cx, cy = px - ty * w, py + tx * w
            d = f"M {f(cx - tx * 7)},{f(cy - ty * 7)} L {f(cx + tx * 7)},{f(cy + ty * 7)}"
            o.append(stroke_path(d, cream if not mono else W, 2.4))
        o.append(ash_frond(372, 330, -28, 44, p, mono, 0.95))
        o.append(ash_frond(42, 346, 196, 40, p, mono, 0.85))

    # ---- tail: big plume behind the body, patterned
    tail_d = plume(TAIL_CTRL, TAIL_W)
    o.append(f'<path d="{tail_d}" fill="{K if mono else p["orange"]}"/>')
    # fur as pattern: a rust core band + rhythmic ticks (cream in colour, white in mono)
    if mono:
        o.append(fur_ticks(TAIL_CTRL, TAIL_W, W, fracs=(-0.62, -0.2, 0.22, 0.64), step=4, length=11, sw=3.4))
    else:
        o.append(stroke_path(offset_line(TAIL_CTRL, TAIL_W, 0.08, u0=0.03, u1=0.96), p["rust"], 26))
        o.append(fur_ticks(TAIL_CTRL, TAIL_W, p["paper"], fracs=(-0.6, 0.62), step=5, length=10, sw=3))
        o.append(fur_ticks(TAIL_CTRL, TAIL_W, p["mustard"], fracs=(0.1,), step=5, length=10, sw=3.2))

    # ---- body: one organic silhouette, back curled in a C, chest pushed forward
    body = ("M 262,188 C 304,182 338,212 342,254 C 348,292 330,326 290,330 "
            "L 230,330 C 196,332 164,318 158,284 C 152,246 176,210 218,196 "
            "C 232,191 248,189 262,188 Z")
    o.append(f'<path d="{body}" fill="{fur}" stroke="{ink if mono else "none"}" stroke-width="{sw}"/>')
    # belly
    belly = "M 306,220 C 330,242 336,288 316,318 C 300,330 266,330 260,310 C 252,274 272,232 306,220 Z"
    o.append(f'<path d="{belly}" fill="{cream}" stroke="{ink if mono else "none"}" stroke-width="{sw * 0.7}"/>')
    # hind leg: a solid rust haunch that runs down into the foot (reads as a limb, not a sticker)
    thigh = ("M 206,246 C 244,244 264,276 256,306 C 250,330 224,340 198,334 "
             "C 168,326 160,286 174,262 C 182,250 194,246 206,246 Z")
    foot = "M 230,322 C 262,316 298,320 306,332 C 310,340 298,344 278,342 L 232,340 C 222,338 222,326 230,322 Z"
    if mono:
        o.append(f'<path d="{thigh}" fill="{K}"/>')
        o.append(f'<path d="{foot}" fill="{K}" stroke="{W}" stroke-width="2.5"/>')
        tc = [(176, 262), (190, 250), (236, 250), (256, 290), (250, 330)]
        o.append(fur_ticks(tc, [(0, 50), (1, 50)], W, fracs=(-0.5, 0.0, 0.5), step=4, length=9, sw=3, u0=0.08, u1=0.92))
    else:
        o.append(f'<path d="{thigh}" fill="{p["rust"]}"/>')
        o.append(f'<path d="{foot}" fill="{p["rust"]}"/>')
        for d in ("M 186,270 L 198,264", "M 182,290 L 196,284", "M 192,312 L 206,306"):
            o.append(stroke_path(d, p["paper"], 3))

    # ---- head: organic, snout right, cheeky tilt
    head = ("M 248,170 C 244,124 276,100 308,104 C 334,108 350,126 356,150 "
            "C 366,158 372,170 358,178 C 346,190 322,202 296,202 C 266,202 250,194 248,170 Z")
    o.append(f'<path d="{head}" fill="{fur}" stroke="{ink if mono else "none"}" stroke-width="{sw}"/>')
    # cheek / muzzle in cream
    muzzle = "M 312,160 C 330,152 356,160 358,176 C 350,186 330,196 310,194 C 300,188 300,168 312,160 Z"
    o.append(f'<path d="{muzzle}" fill="{cream}"/>')
    # ears: tall with tufts (the red-squirrel signature)
    for d in ("M 268,116 C 264,96 268,76 280,56 C 290,80 296,98 294,118 Z",
              "M 300,114 C 300,94 306,78 318,62 C 324,84 326,100 322,118 Z"):
        o.append(f'<path d="{d}" fill="{rust}" stroke="{ink if mono else "none"}" stroke-width="{sw * 0.7}"/>')
    # eye: big, bright, mischievous
    o.append(circle(322, 146, 13, cream, f'stroke="{ink if mono else "none"}" stroke-width="{sw * 0.6}"'))
    o.append(circle(326, 147, 8, ink))
    o.append(circle(329, 143, 3, W if not mono else W))
    # eyebrow
    o.append(stroke_path("M 306,126 C 316,120 330,122 338,128", ink, 4))
    # nose + mouth + tooth
    o.append(f'<path d="M 364,170 C 372,168 374,178 366,180 C 360,180 358,172 364,170 Z" fill="{ink}"/>')
    o.append(stroke_path("M 356,183 C 350,190 342,190 336,186", ink, 3))
    o.append(f'<rect x="338" y="186" width="7" height="8" rx="1.5" fill="{W if not mono else W}" stroke="{ink}" stroke-width="1.5"/>')

    # ---- arm + letter (the message)
    # arm reaching forward and up: "here, a message for you"
    o.append(f'<path d="M 304,236 C 322,226 346,218 364,224 C 372,230 368,242 356,242 C 338,240 318,248 302,250 Z" '
             f'fill="{fur}" stroke="{ink if mono else "none"}" stroke-width="{sw * 0.7}"/>')
    if letter:
        o.append('<g transform="translate(372,228) rotate(-14)">')
        o.append(f'<rect x="-22" y="-14" width="44" height="30" rx="3" fill="{cream}" stroke="{ink}" stroke-width="3"/>')
        o.append(stroke_path("M -22,-14 L 0,2 L 22,-14", ink, 3))
        o.append(circle(0, 6, 4.5, rust if not mono else K))
        o.append("</g>")
        # paw over the letter
        o.append(circle(362, 236, 7, fur, f'stroke="{ink if mono else "none"}" stroke-width="{sw * 0.6}"'))

    g = f'<g transform="translate({f(ox)},{f(oy)}) scale({f(scale)})">\n' + "\n".join(o) + "\n</g>"
    return g


def tosk_svg(mono):
    p = MONO if mono else PAL
    return svg(400, 400, tosk(p, mono), "tosk — Ratatosk the messenger squirrel")


# ------------------------------------------------------------------- icon
ICON_TAIL = [(34, 90), (6, 66), (8, 20), (46, 12), (76, 6), (94, 28), (82, 46)]
ICON_W = [(0, 16), (0.3, 30), (0.65, 34), (1.0, 16)]


def icon(mono, size=100):
    p = MONO if mono else PAL
    o = []
    bg = K if mono else p["teal"]
    o.append(f'<rect x="0" y="0" width="100" height="100" rx="22" fill="{bg}"/>')
    fur = W if mono else p["orange"]
    cream = W if mono else p["paper"]
    ink = K if mono else p["ink"]
    # tail
    o.append(f'<path d="{plume(ICON_TAIL, ICON_W)}" fill="{fur}"/>')
    if mono:
        for frac in (-0.42, 0.42):
            o.append(stroke_path(offset_line(ICON_TAIL, ICON_W, frac, u0=0.1, u1=0.9), K, 2.4))
    else:
        o.append(stroke_path(offset_line(ICON_TAIL, ICON_W, 0.0, u0=0.06, u1=0.94), p["rust"], 8))
        o.append(stroke_path(offset_line(ICON_TAIL, ICON_W, -0.55, u0=0.14, u1=0.88), p["mustard"], 2.4))
    # body (small, behind head)
    o.append(f'<path d="M 54,58 C 70,56 86,70 84,86 C 82,94 70,96 56,96 C 42,96 32,88 34,74 C 36,62 44,58 54,58 Z" fill="{fur}"/>')
    o.append(f'<path d="M 72,68 C 80,76 80,88 72,94 C 64,96 58,92 60,82 C 62,74 66,68 72,68 Z" fill="{cream}" '
             f'stroke="{K if mono else "none"}" stroke-width="2"/>')
    # head (scaled up a touch so it carries at 48 px)
    o.append('<g transform="translate(70,48) scale(1.18) translate(-70,-48)">')
    o.append(f'<path d="M 46,52 C 44,32 60,22 74,24 C 84,26 90,36 92,46 C 96,50 96,56 90,58 C 82,66 66,70 54,66 C 48,64 46,58 46,52 Z" fill="{fur}"/>')
    # ears
    for d in ("M 54,36 C 52,28 54,20 60,12 C 64,22 66,30 64,38 Z",
              "M 70,34 C 70,26 74,18 80,12 C 82,22 82,30 80,36 Z"):
        o.append(f'<path d="{d}" fill="{p["rust"] if not mono else W}"/>')
    # eye
    o.append(circle(78, 46, 7.5, cream, f'stroke="{K if mono else "none"}" stroke-width="1.2"'))
    o.append(circle(80, 47, 4.6, ink))
    o.append(circle(81.6, 45, 1.6, W))
    # nose
    o.append(circle(93, 54, 2.8, ink))
    o.append("</g>")
    return svg(size, size, "\n".join(o), "tosk icon")


# ------------------------------------------------------------------- logo
def wordmark(x, y, color, h=1.0):
    """'tosk' as monoline rounded letters (hand-drawn paths, no font)."""
    sw = 12.5 * h
    g = []

    def P(d):
        g.append(stroke_path(d, color, sw))

    # t
    P("M 18,8 L 18,58 C 18,72 26,76 40,74")
    P("M 4,28 L 36,28")
    # o
    g.append(f'<circle cx="78" cy="52" r="22" fill="none" stroke="{color}" stroke-width="{f(sw)}"/>')
    # s
    P("M 140,36 C 136,28 126,28 120,32 C 112,37 114,46 124,49 C 136,52 142,58 138,67 C 133,76 118,76 112,68")
    # k
    P("M 160,6 L 160,74")
    P("M 188,30 L 162,52")
    P("M 170,46 L 190,74")
    return f'<g transform="translate({f(x)},{f(y)}) scale({f(h)})">\n' + "\n".join(g) + "\n</g>"


def logo_svg():
    o = []
    o.append(f'<rect x="0" y="0" width="360" height="120" fill="{PAL["paper"]}"/>')
    # mark: the icon at 88 px
    o.append('<g transform="translate(16,16) scale(0.88)">')
    ic = icon(False)
    inner = ic.split("<title>tosk icon</title>\n", 1)[1].rsplit("</svg>", 1)[0]
    o.append(inner)
    o.append("</g>")
    o.append(wordmark(124, 24, PAL["ink"], 1.0))
    return svg(360, 120, "\n".join(o), "tosk logo")


# -------------------------------------------------------------- Yggdrasil
TRUNK = [(400, 1000), (388, 860), (418, 700), (404, 560), (392, 440), (412, 300), (400, 190)]
TRUNK_W = [(0, 130), (0.3, 92), (0.7, 64), (1.0, 40)]

# branches: arching up from the trunk, each ending in a skill node
BRANCHES = [
    # [ctrl points absolute], (twig u, twig side)
    ([(404, 262), (340, 262), (236, 262), (196, 176)], 0.5),   # left top
    ([(404, 316), (470, 310), (574, 300), (610, 214)], 0.5),   # right top
    ([(404, 452), (330, 452), (190, 470), (142, 362)], 0.55),  # left mid
    ([(404, 536), (486, 536), (600, 560), (650, 440)], 0.55),  # right mid
    ([(404, 686), (310, 696), (180, 720), (124, 596)], 0.55),  # left low
    ([(404, 760), (480, 780), (610, 800), (676, 672)], 0.5),   # right low
]
CROWN = (400, 180)
CANOPY_NODE = (400, 118)


def nodes_for(mono, p):
    return (W if mono else p["mustard"], K if mono else p["rust"])


def rune(x, y, kind, color, s=1.0, sw=3.2):
    """A handful of elder-futhark-ish strokes, drawn as lines."""
    forms = {
        "f": "M 0,-10 L 0,10 M 0,-8 L 8,-13 M 0,-2 L 8,-7",       # ᚠ fehu
        "u": "M -6,10 L -6,-10 C -2,-4 4,-2 6,10",                 # ᚢ uruz
        "th": "M -4,-10 L -4,10 M -4,-5 L 5,0 L -4,5",              # ᚦ thurisaz
        "a": "M 0,-10 L 0,10 M 0,-9 L 8,-4 M 0,-3 L 8,2",           # ᚨ ansuz
        "r": "M -4,-10 L -4,10 M -4,-10 L 4,-6 L -4,-1 L 5,10",     # ᚱ raido
        "k": "M -5,-10 L 4,0 L -5,10",                              # ᚲ kenaz
        "g": "M -7,-8 L 7,8 M 7,-8 L -7,8",                         # ᚷ gebo
        "o": "M -7,10 L 0,-9 L 7,10 M -7,10 L -2,4 M 7,10 L 2,4",   # ᛟ-ish
    }
    return (f'<g transform="translate({f(x)},{f(y)}) scale({f(s)})">'
            f'<path d="{forms[kind]}" fill="none" stroke="{color}" stroke-width="{f(sw / s)}" '
            f'stroke-linecap="round" stroke-linejoin="round"/></g>')


def skill_node(x, y, r, p, mono, kind, big=False):
    fill, ring = nodes_for(mono, p)
    o = [circle(x, y, r + 5, p["paper"] if not mono else W),  # halo so leaves don't crowd it
         circle(x, y, r, fill, f'stroke="{ring}" stroke-width="{f(5 if big else 4)}"'),
         rune(x, y + 1, kind, ring if not mono else K, s=r / 20)]
    return "\n".join(o)


def eagle(x, y, p, mono, s=1.0):
    """Stylised eagle in the crown: one body lens and two big scalloped wings."""
    ink = K if mono else p["ink"]
    cream = W if mono else p["paper"]
    must = W if mono else p["mustard"]
    o = [f'<g transform="translate({f(x)},{f(y)}) scale({f(s)})">']
    wing = ("M 6,10 C 30,-10 60,-40 96,-72 C 108,-82 118,-74 112,-60 "
            "C 100,-30 70,0 40,14 L 24,18 Q 14,22 6,10 Z")
    body = "M 0,-26 C 12,-22 16,0 12,22 C 10,32 6,40 0,48 C -6,40 -10,32 -12,22 C -16,0 -12,-22 0,-26 Z"
    # paper halo so the bird separates from the canopy (and from black leaves in mono)
    for sgn in (-1, 1):
        o.append(f'<path d="{wing}" transform="scale({sgn},1)" fill="{cream}" stroke="{cream}" stroke-width="10" stroke-linejoin="round"/>')
    o.append(f'<path d="{body}" fill="{cream}" stroke="{cream}" stroke-width="10" stroke-linejoin="round"/>')
    o.append(f'<path d="M -14,34 L 0,62 L 14,34 Z" fill="{cream}" stroke="{cream}" stroke-width="10" stroke-linejoin="round"/>')
    o.append(circle(2, -30, 22, cream))
    # wings raised in a V, as two big lens feathers with scalloped trailing edge
    for sgn in (-1, 1):
        o.append(f'<g transform="scale({sgn},1)">')
        o.append(f'<path d="{wing}" fill="{ink}"/>')
        # feather rhythm: cream strokes fanning from the body
        for (ax, ay, bx, by) in ((28, 4, 56, -22), (40, 0, 76, -40), (52, -8, 92, -60)):
            o.append(stroke_path(f"M {ax},{ay} L {bx},{by}", cream, 2.6))
        # scallops at the trailing edge
        for (cx, cy) in ((34, 14), (52, 4), (70, -10), (86, -28), (100, -46)):
            o.append(circle(cx, cy, 4, cream))
        o.append("</g>")
    # body, tail fan
    o.append(f'<path d="{body}" fill="{ink}"/>')
    o.append(f'<path d="M -14,34 L 0,62 L 14,34 Z" fill="{ink}"/>')
    o.append(stroke_path("M -8,36 L 0,54 L 8,36", cream, 2))
    # head, beak, eye
    o.append(f'<path d="M -10,-24 C -10,-38 2,-44 12,-40 C 20,-36 20,-26 14,-20 C 6,-14 -6,-14 -10,-24 Z" fill="{cream}" stroke="{ink}" stroke-width="3"/>')
    o.append(f'<path d="M 14,-36 L 30,-30 L 14,-24 Z" fill="{must if not mono else K}" stroke="{ink}" stroke-width="2.5"/>')
    o.append(circle(6, -33, 2.6, ink))
    o.append("</g>")
    return "\n".join(o)


def dragon(p, mono):
    """Nidhoggr: a serpent coiled through the roots, gnawing."""
    teal = K if mono else p["teal"]
    cream = W if mono else p["paper"]
    must = W if mono else p["mustard"]
    ink = K if mono else p["ink"]
    ctrl = [(560, 1060), (500, 1090), (430, 1050), (470, 1010),
            (505, 982), (585, 1000), (610, 1036)]
    wd = [(0, 10), (0.5, 28), (1, 30)]
    o = [f'<path d="{plume(ctrl, wd, round_start=True, round_end=False)}" fill="{teal}"/>']
    o.append(stroke_path(offset_line(ctrl, wd, -0.35, u0=0.1, u1=0.95), cream if not mono else W, 3.5, 'stroke-dasharray="7 7"'))
    # spines
    pts = chain(ctrl)
    for k in range(10, len(pts) - 6, 6):
        (px, py), (tx, ty) = pts[k]
        w = width_at(wd, k / (len(pts) - 1)) / 2
        bx, by = px - ty * w, py + tx * w
        o.append(f'<path d="M {f(bx - tx * 5)},{f(by - ty * 5)} L {f(bx - ty * 10)},{f(by + tx * 10)} L {f(bx + tx * 5)},{f(by + ty * 5)} Z" fill="{teal}"/>')
    # head
    o.append(f'<path d="M 596,1024 C 616,1010 646,1016 654,1032 C 660,1044 648,1056 630,1054 L 610,1052 C 598,1048 592,1034 596,1024 Z" fill="{teal}"/>')
    o.append(circle(628, 1032, 5.5, cream))
    o.append(circle(630, 1033, 3, ink))
    o.append(f'<path d="M 648,1046 L 656,1058 L 640,1052 Z" fill="{cream}"/>')  # fang
    o.append(f'<path d="M 606,1018 L 612,1002 L 620,1018 Z" fill="{must if not mono else K}"/>')  # horn
    return "\n".join(o)


def yggdrasil(mono):
    p = MONO if mono else PAL
    ink = K if mono else p["ink"]
    cream = W if mono else p["paper"]
    o = []
    o.append(f'<rect width="800" height="1100" fill="{W if mono else p["paper"]}"/>')
    # ground mist
    if not mono:
        o.append(f'<ellipse cx="400" cy="1020" rx="360" ry="52" fill="{p["sky"]}" fill-opacity="0.4"/>')
    # well of Urd, under the left root
    o.append(circle(286, 1042, 46, p["sky"] if not mono else W, f'stroke="{ink}" stroke-width="5"'))
    for d, sw_ in (("M 252,1040 C 266,1030 280,1050 296,1038 C 306,1030 314,1034 320,1040", 3.2),
                   ("M 258,1058 C 272,1050 288,1066 306,1056 C 312,1052 316,1054 318,1058", 2.6)):
        o.append(stroke_path(d, ink, sw_))
    # ---- roots: three heavy curling roots
    roots = [
        ([(400, 985), (340, 1000), (230, 990), (150, 1050), (120, 1072), (150, 1092), (180, 1080)], [(0, 76), (0.6, 30), (1, 10)]),
        ([(400, 990), (408, 1030), (380, 1060), (396, 1096)], [(0, 70), (1, 14)]),
        ([(410, 985), (470, 1005), (560, 1000), (650, 1046), (690, 1066), (700, 1090), (666, 1088)], [(0, 76), (0.6, 30), (1, 10)]),
    ]
    for ctrl, wd in roots:
        o.append(f'<path d="{plume(ctrl, wd)}" fill="{ink}"/>')
        o.append(stroke_path(offset_line(ctrl, wd, -0.1, u0=0.08, u1=0.85), cream, 2.8, 'stroke-dasharray="12 10"'))
    # dragon in the roots
    o.append(f'<g transform="translate(-128,-220) scale(1.22)">{dragon(p, mono)}</g>')
    # ---- trunk
    o.append(f'<path d="{plume(TRUNK, TRUNK_W, round_end=True)}" fill="{ink}"/>')
    # bark rhythm: offset dashes (Marimekko stripe feel)
    pts = chain(TRUNK, 40)
    n = len(pts)
    for col_i, frac in enumerate((-0.66, -0.3, 0.06, 0.4, 0.72)):
        for k in range(6 + col_i * 3, n - 8, 12):
            (px, py), (tx, ty) = pts[k]
            w = width_at(TRUNK_W, k / (n - 1)) / 2 * frac
            cx, cy = px - ty * w, py + tx * w
            L = 12
            o.append(stroke_path(f"M {f(cx - tx * L)},{f(cy - ty * L)} L {f(cx + tx * L)},{f(cy + ty * L)}", cream, 3))
    # runes carved up the trunk
    for i, (u, kind) in enumerate(((0.1, "f"), (0.24, "u"), (0.48, "th"), (0.64, "a"), (0.86, "g"))):
        (px, py), _ = point_at(TRUNK, u, 40)
        o.append(circle(px, py, 15, ink))  # clear the bark dashes
        o.append(rune(px, py, kind, p["mustard"] if not mono else W, s=1.3, sw=4))
    # ---- branches + twigs + leaf fronds + nodes
    kinds = ["r", "k", "g", "o", "f", "u"]
    nodes = []
    wd = [(0, 54), (0.55, 30), (1, 14)]
    for i, (ctrl, tu) in enumerate(BRANCHES):
        right = ctrl[-1][0] > 400
        o.append(f'<path d="{plume(ctrl, wd)}" fill="{ink}"/>')
        o.append(stroke_path(offset_line(ctrl, wd, 0.05, u0=0.1, u1=0.86), cream, 2.8, 'stroke-dasharray="11 9"'))
        # one twig forking off the branch, curling up
        (px, py), (tx, ty) = point_at(ctrl, tu)
        up = (-tx * 0.3, -1) if right else (tx * 0.3, -1)
        twig = [(px, py), (px + tx * 40, py + ty * 40 - 10), (px + tx * 60 - up[0] * 10, py - 60), (px + tx * 70 + (30 if right else -30), py - 95)]
        tw_ = [(0, 20), (1, 7)]
        o.append(f'<path d="{plume(twig, tw_)}" fill="{ink}"/>')
        # fronds: at the twig tip, and under the branch
        (ex, ey), (etx, ety) = point_at(twig, 1.0)
        o.append(ash_frond(ex, ey, math.degrees(math.atan2(ety, etx)) + (18 if right else -18), 50, p, mono, 1.05))
        (ex, ey), (etx, ety) = point_at(twig, 0.6)
        o.append(ash_frond(ex, ey, math.degrees(math.atan2(ety, etx)) + (-70 if right else 70), 40, p, mono, 0.9))
        (bx, by), (btx, bty) = point_at(ctrl, 0.8)
        w = width_at(wd, 0.8) / 2
        o.append(ash_frond(bx - bty * w * (1 if right else -1) * -1, by + btx * w * (1 if right else -1) * -1,
                           math.degrees(math.atan2(bty, btx)) + (60 if right else -60), 44, p, mono, 0.95))
        nodes.append((ctrl[-1], kinds[i]))
    # canopy: a dome of big overlapping lens leaves (translucent print feel)
    cols = [p["olive"], p["teal"], p["mustard"], p["olive"], p["teal"]]
    leaves = []
    rng = 17
    for ring_i, (rx, ry, count, L, Wd) in enumerate(((186, 96, 15, 92, 36), (124, 64, 11, 80, 32), (56, 30, 6, 64, 28))):
        for k in range(count):
            a = math.pi + math.pi * (k + 0.5) / count  # upper half only
            cx, cy = CROWN[0] + rx * math.cos(a), CROWN[1] + ry * math.sin(a) + 10
            ang = math.degrees(math.atan2(ry * math.sin(a), rx * math.cos(a)))
            rng = (rng * 1103515245 + 12345) % (2 ** 31)
            col = cols[(k + ring_i + rng % 2) % len(cols)]
            leaves.append((cx, cy, L, Wd, ang, col))
    # lower, darker fringe hanging under the dome
    for k in range(9):
        cx = CROWN[0] - 170 + k * 42
        cy = CROWN[1] + 86 + (k % 2) * 14
        leaves.append((cx, cy, 60, 26, 90 + (k - 4) * 12, cols[k % 3]))
    for (cx, cy, L, Wd, ang, col) in leaves:
        if mono:
            o.append(lens(cx, cy, L, Wd, ang, K, f'stroke="{W}" stroke-width="3"'))
            o.append(lens_vein(cx, cy, L, ang, W, 2.2))
        else:
            o.append(lens(cx, cy, L, Wd, ang, col, 'fill-opacity="0.82"'))
    # nodes (after leaves so they sit on top)
    for (x, y), kind in nodes:
        o.append(skill_node(x, y, 26, p, mono, kind))
    o.append(skill_node(CANOPY_NODE[0], CANOPY_NODE[1] + 56, 30, p, mono, "a", big=True))
    o.append(eagle(400, 74, p, mono, 1.25))
    # Tosk sitting on the right-mid branch, carrying the message
    ctrl = BRANCHES[3][0]
    (bx, by), _ = point_at(ctrl, 0.22)
    s = 0.3
    o.append(f'<g transform="translate({f(bx - 250 * s)},{f(by - width_at(wd, 0.22) / 2 - 330 * s)}) scale({f(s)})">'
             f'{tosk(p, mono, with_branch=False)}</g>')
    return svg(800, 1100, "\n".join(o), "Yggdrasil — the course tree")


# ------------------------------------------------------------ branch tile
def branch_tile(mono):
    p = MONO if mono else PAL
    ink = K if mono else p["ink"]
    cream = W if mono else p["paper"]
    o = [f'<rect width="300" height="300" fill="{W if mono else p["paper"]}"/>']
    trunk = [(150, 300), (152, 250), (146, 210), (150, 170)]
    tw = [(0, 40), (1, 30)]
    o.append(f'<path d="{plume(trunk, tw, round_end=False)}" fill="{ink}"/>')
    arms = [
        [(150, 175), (140, 140), (100, 110), (62, 62)],
        [(150, 175), (166, 140), (206, 112), (238, 62)],
    ]
    aw = [(0, 30), (0.7, 16), (1, 10)]
    for ctrl in arms:
        o.append(f'<path d="{plume(ctrl, aw)}" fill="{ink}"/>')
        o.append(stroke_path(offset_line(ctrl, aw, 0.0, u0=0.15, u1=0.85), cream, 2.4, 'stroke-dasharray="9 8"'))
    o.append(stroke_path(offset_line(trunk, tw, -0.3, u0=0.05, u1=0.95), cream, 2.6, 'stroke-dasharray="11 9"'))
    o.append(stroke_path(offset_line(trunk, tw, 0.35, u0=0.0, u1=0.9), cream, 2.6, 'stroke-dasharray="9 11"'))
    # fronds
    o.append(ash_frond(118, 128, 200, 40, p, mono, 0.9))
    o.append(ash_frond(186, 128, -20, 40, p, mono, 0.9))
    o.append(ash_frond(96, 96, -120, 34, p, mono, 0.8))
    o.append(ash_frond(206, 100, -60, 34, p, mono, 0.8))
    # nodes
    o.append(skill_node(62, 56, 24, p, mono, "k"))
    o.append(skill_node(238, 56, 24, p, mono, "g"))
    o.append(skill_node(150, 230, 26, p, mono, "r", big=True))
    return svg(300, 300, "\n".join(o), "branch tile")


# ------------------------------------------------------------------ sheet
def sheet():
    sw = "".join(
        f'<div class="sw"><i style="background:{v}"></i><b>{k}</b><code>{v}</code></div>' for k, v in PAL.items()
    )
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk — mid-century</title>
<style>
 body{{margin:0;padding:28px;background:{PAL['paper']};color:{PAL['ink']};font:15px/1.4 Georgia,serif}}
 h1{{font:700 44px/1 Georgia,serif;margin:0 0 4px;letter-spacing:-1px}}
 p.sub{{margin:0 0 20px;color:#6b5b4c}}
 .row{{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;margin-bottom:18px}}
 .card{{background:#fff;border:2px solid {PAL['ink']};border-radius:14px;padding:12px;text-align:center}}
 .card.mono{{background:#fff}}
 .card figcaption{{margin-top:6px;font-size:13px;color:#6b5b4c}}
 img{{display:block}}
 .icons img{{display:inline-block;vertical-align:bottom;margin:0 8px}}
 .pal{{display:flex;gap:10px;flex-wrap:wrap}}
 .sw{{width:118px;text-align:center;font-size:12px}}
 .sw i{{display:block;height:46px;border-radius:8px;border:2px solid {PAL['ink']}}}
 .sw b{{display:block;margin-top:4px}} .sw code{{color:#6b5b4c}}
</style></head><body>
<h1>tosk</h1>
<p class="sub">Mid-century Scandinavian / retro print exploration. Ratatosk carries words up and down Yggdrasil. Colour and e-ink side by side.</p>
<div class="row">
 <figure class="card" style="margin:0"><img src="tosk.svg" width="360" height="360"><figcaption>Tosk</figcaption></figure>
 <figure class="card mono" style="margin:0"><img src="tosk-mono.svg" width="360" height="360"><figcaption>Tosk, e-ink</figcaption></figure>
 <div>
  <figure class="card icons" style="margin:0 0 12px"><img src="icon.svg" width="96" height="96"><img src="icon.svg" width="48" height="48"><img src="icon-mono.svg" width="96" height="96"><img src="icon-mono.svg" width="48" height="48"><figcaption>App icon at 96 and 48 px, colour and e-ink</figcaption></figure>
  <figure class="card" style="margin:0 0 12px"><img src="logo.svg" width="360" height="120"><figcaption>Logo</figcaption></figure>
  <figure class="card" style="margin:0"><div class="pal">{sw}</div><figcaption>Palette</figcaption></figure>
 </div>
</div>
<div class="row">
 <figure class="card" style="margin:0"><img src="yggdrasil.svg" width="400" height="550"><figcaption>Yggdrasil, the course tree</figcaption></figure>
 <figure class="card mono" style="margin:0"><img src="yggdrasil-mono.svg" width="400" height="550"><figcaption>Yggdrasil, e-ink</figcaption></figure>
 <div>
  <figure class="card" style="margin:0 0 12px"><img src="branch-tile.svg" width="240" height="240"><figcaption>Branch tile</figcaption></figure>
  <figure class="card mono" style="margin:0"><img src="branch-tile-mono.svg" width="240" height="240"><figcaption>Branch tile, e-ink</figcaption></figure>
 </div>
</div>
</body></html>
"""


def main():
    files = {
        "tosk.svg": tosk_svg(False), "tosk-mono.svg": tosk_svg(True),
        "icon.svg": icon(False), "icon-mono.svg": icon(True),
        "logo.svg": logo_svg(),
        "yggdrasil.svg": yggdrasil(False), "yggdrasil-mono.svg": yggdrasil(True),
        "branch-tile.svg": branch_tile(False), "branch-tile-mono.svg": branch_tile(True),
        "sheet.html": sheet(),
    }
    for name, content in files.items():
        (HERE / name).write_text(content, encoding="utf-8")
        print(f"{name:22s} {len(content.encode()) / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
