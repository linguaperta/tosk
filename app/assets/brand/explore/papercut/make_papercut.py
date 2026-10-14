"""tosk brand exploration: Scandinavian papercut style.

Generates hand-crafted-looking layered cut-paper SVGs (no dependencies).
Run:  python make_papercut.py
Writes tosk.svg, tosk-mono.svg, icon.svg, icon-mono.svg, logo.svg,
yggdrasil.svg, yggdrasil-mono.svg, branch-tile.svg, branch-tile-mono.svg,
sheet.html into this folder.
"""
from __future__ import annotations

import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- palette
PAPER = "#F3EBDC"   # cream paper (background / top light layer)
INK = "#1E2A30"     # deep night-teal (back layer, roots, trunk)
RUST = "#C8502A"    # Tosk, red squirrel
RUSTD = "#9E3A1C"   # darker rust (tail, shadowed layer)
OCHRE = "#E2A94E"   # skill nodes / accents
SAGE = "#5F8A5A"    # ash leaves
BLACK = "#000000"
WHITE = "#FFFFFF"

PALETTE = [
    ("paper", PAPER), ("night", INK), ("rust", RUST), ("rust dark", RUSTD),
    ("ochre", OCHRE), ("sage", SAGE),
]


# ---------------------------------------------------------------- geometry helpers
def fmt(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def _bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1])


def _segments(points, closed, tension):
    pts, flags = [], []
    for p in points:
        pts.append((float(p[0]), float(p[1])))
        flags.append(p[2] if len(p) > 2 else None)
    n = len(pts)

    def P(i):
        return pts[i % n] if closed else pts[max(0, min(n - 1, i))]

    def tens(i):
        f = flags[i % n] if closed else flags[max(0, min(n - 1, i))]
        if f == "sharp":
            return 0.0
        if isinstance(f, (int, float)):
            return float(f)
        return tension

    segs = []
    for i in range(n if closed else n - 1):
        p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        t1, t2 = tens(i), tens(i + 1)
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * t1, p1[1] + (p2[1] - p0[1]) / 6 * t1)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * t2, p2[1] - (p3[1] - p1[1]) / 6 * t2)
        segs.append((p1, c1, c2, p2))
    return segs


def smooth(points, closed=True, tension=1.0):
    """Catmull-Rom spline through points -> cubic Bezier path string.

    Each point is (x, y) or (x, y, flag) where flag 'sharp' makes a corner,
    or a float tension override for that point's handles."""
    segs = _segments(points, closed, tension)
    out = [f"M{fmt(segs[0][0][0])},{fmt(segs[0][0][1])}"]
    for (_, c1, c2, p2) in segs:
        out.append(f"C{fmt(c1[0])},{fmt(c1[1])} {fmt(c2[0])},{fmt(c2[1])} {fmt(p2[0])},{fmt(p2[1])}")
    if closed:
        out.append("Z")
    return " ".join(out)


def sample(points, step=3.0, tension=1.0):
    """Sample an open spline into dense points (with tangents)."""
    segs = _segments(points, False, tension)
    out = []
    for (p1, c1, c2, p2) in segs:
        # approx length
        L = 0
        prev = p1
        for k in range(1, 9):
            q = _bez(p1, c1, c2, p2, k / 8)
            L += math.hypot(q[0] - prev[0], q[1] - prev[1])
            prev = q
        m = max(2, int(L / step))
        for k in range(m):
            t = k / m
            q = _bez(p1, c1, c2, p2, t)
            q2 = _bez(p1, c1, c2, p2, min(1, t + 0.01))
            out.append((q, (q2[0] - q[0], q2[1] - q[1])))
    out.append((segs[-1][3], out[-1][1]))
    return out


def fur(points, pitch=14.0, depth=7.0, side=1, lean=0.4, tension=1.0, taper=True):
    """Turn an open spline into a serrated fur edge: a list of sharp points.

    side=+1 puts the valleys to the right of the direction of travel."""
    samp = sample(points, step=2.0, tension=tension)
    # cumulative length
    cum = [0.0]
    for i in range(1, len(samp)):
        a, b = samp[i - 1][0], samp[i][0]
        cum.append(cum[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = cum[-1]
    n = max(2, int(total / pitch))
    pitch = total / n

    def at(d):
        d = max(0, min(total, d))
        lo, hi = 0, len(cum) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if cum[mid] < d:
                lo = mid + 1
            else:
                hi = mid
        p, t = samp[lo]
        L = math.hypot(t[0], t[1]) or 1
        return p, (t[0] / L, t[1] / L)

    out = []
    for i in range(n + 1):
        d = i * pitch
        # scale depth down at both ends when tapering
        f = 1.0
        if taper:
            f = min(1.0, min(d, total - d) / (pitch * 2.5))
        p, t = at(d)
        nx, ny = -t[1] * side, t[0] * side
        out.append((p[0] + nx * depth * f, p[1] + ny * depth * f, "sharp"))   # valley
        if i < n:
            q, _ = at(d + pitch * (0.5 + lean * 0.5))
            out.append((q[0], q[1], "sharp"))                                   # tip
    return out


def lens(p0, p1, w, bulge=0.0):
    """A pointed slit (papercut cut) from p0 to p1 of visual half-width w.

    bulge bends the slit sideways (signed, in px)."""
    (x0, y0), (x1, y1) = p0, p1
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / L, dx / L
    bx, by = mx + nx * bulge, my + ny * bulge
    k = 2.0 * w
    ca = (bx + nx * k, by + ny * k)
    cb = (bx - nx * k, by - ny * k)
    return (f"M{fmt(x0)},{fmt(y0)} Q{fmt(ca[0])},{fmt(ca[1])} {fmt(x1)},{fmt(y1)} "
            f"Q{fmt(cb[0])},{fmt(cb[1])} {fmt(x0)},{fmt(y0)} Z")


def drop(p0, p1, w):
    """Teardrop cut: round at p0, pointed at p1."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / L, dx / L
    a = (x0 + nx * w, y0 + ny * w)
    b = (x0 - nx * w, y0 - ny * w)
    return (f"M{fmt(x1)},{fmt(y1)} Q{fmt(a[0] + dx * 0.3)},{fmt(a[1] + dy * 0.3)} {fmt(a[0])},{fmt(a[1])} "
            f"A{fmt(w)},{fmt(w)} 0 1 0 {fmt(b[0])},{fmt(b[1])} "
            f"Q{fmt(b[0] + dx * 0.3)},{fmt(b[1] + dy * 0.3)} {fmt(x1)},{fmt(y1)} Z")


def leaf(cx, cy, length, width, angle_deg, vein=True, leaflets=0):
    """Ash leaflet: lens body, vein slit (and optional side leaflet cuts)."""
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    p0 = (cx - dx * length / 2, cy - dy * length / 2)
    p1 = (cx + dx * length / 2, cy + dy * length / 2)
    body = lens(p0, p1, width)
    cuts = []
    if vein:
        q0 = (cx - dx * length * 0.36, cy - dy * length * 0.36)
        q1 = (cx + dx * length * 0.42, cy + dy * length * 0.42)
        cuts.append(lens(q0, q1, width * 0.14))
    nx, ny = -dy, dx
    for k in range(leaflets):
        t = -0.25 + 0.5 * k / max(1, leaflets - 1)
        bx, by = cx + dx * length * t, cy + dy * length * t
        for sgn in (-1, 1):
            e = (bx + (dx * 0.55 + nx * sgn) * width * 0.75, by + (dy * 0.55 + ny * sgn) * width * 0.75)
            cuts.append(lens((bx + nx * sgn * width * 0.18, by + ny * sgn * width * 0.18), e, width * 0.12))
    return body, cuts


def circle(cx, cy, r):
    return (f"M{fmt(cx - r)},{fmt(cy)} a{fmt(r)},{fmt(r)} 0 1 0 {fmt(2 * r)},0 "
            f"a{fmt(r)},{fmt(r)} 0 1 0 {fmt(-2 * r)},0 Z")


def ring(cx, cy, r_out, r_in):
    return circle(cx, cy, r_out) + " " + circle(cx, cy, r_in)


def scallop(cx, cy, r, n, depth, tension=1.1, phase=0.0):
    pts = []
    for i in range(n * 2):
        a = 2 * math.pi * i / (n * 2) - math.pi / 2 + phase
        rr = r if i % 2 == 0 else r - depth
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return smooth(pts, tension=tension)


class XF:
    """Similarity transform: translate + uniform scale + rotation (degrees)."""

    def __init__(self, dx=0.0, dy=0.0, s=1.0, deg=0.0):
        self.dx, self.dy, self.s = dx, dy, s
        a = math.radians(deg)
        self.c, self.sn = math.cos(a), math.sin(a)

    def p(self, x, y):
        return (self.dx + self.s * (x * self.c - y * self.sn),
                self.dy + self.s * (x * self.sn + y * self.c))

    def pts(self, points):
        return [self.p(p[0], p[1]) + tuple(p[2:]) for p in points]

    def lens(self, p0, p1, w, bulge=0.0):
        return lens(self.p(*p0), self.p(*p1), w * self.s, bulge * self.s)

    def drop(self, p0, p1, w):
        return drop(self.p(*p0), self.p(*p1), w * self.s)

    def circle(self, cx, cy, r):
        x, y = self.p(cx, cy)
        return circle(x, y, r * self.s)


def mirror_x(points, axis):
    return [(2 * axis - p[0], p[1]) + tuple(p[2:]) for p in points]


# ---------------------------------------------------------------- paper layer model
class Layer:
    """One sheet of paper: fills (the paper) and cuts (holes to the layer below)."""

    def __init__(self, colour, shadow=True, mono="black", opacity=0.3, blur=3.0):
        self.colour = colour
        self.shadow = shadow
        self.mono = mono          # 'black' | 'white' | 'skip'
        self.opacity = opacity
        self.blur = blur
        self.fills = []
        self.cuts = []
        self.extra = []
        self.extra_mono = []

    def fill(self, d):
        self.fills.append(d)
        return self

    def cut(self, d):
        if isinstance(d, list):
            self.cuts.extend(d)
        else:
            self.cuts.append(d)
        return self


_uid = [0]


def render_layers(layers, w, h, mono=False, bg=None):
    """Compose layers into an svg string.

    Colour: each layer = union of fills with cuts punched out (mask), with a
    soft drop shadow.  Mono: one flat black papercut: black layers fill black,
    white layers become cut-outs; no shadows."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">']
    if bg:
        out.append(f'<rect width="{w}" height="{h}" fill="{bg}"/>')
    for L in layers:
        if mono and L.mono == "skip":
            continue
        d = " ".join(L.fills)
        if not d and not L.extra:
            continue
        if mono:
            col = BLACK if L.mono == "black" else WHITE
            if d:
                out.append(f'<path d="{d}" fill="{col}"/>')
            if L.cuts:
                cutcol = WHITE if L.mono == "black" else BLACK
                out.append(f'<path d="{" ".join(L.cuts)}" fill="{cutcol}"/>')
            out.extend(L.extra_mono or L.extra)
        else:
            _uid[0] += 1
            uid = _uid[0]
            filt = ""
            if L.shadow:
                out.append(f'<filter id="f{uid}" x="-10%" y="-10%" width="125%" height="130%">'
                           f'<feDropShadow dx="0" dy="{fmt(L.blur)}" stdDeviation="{fmt(L.blur)}" '
                           f'flood-color="#1E1A14" flood-opacity="{L.opacity}"/></filter>')
                filt = f' filter="url(#f{uid})"'
            if L.cuts:
                out.append(f'<mask id="m{uid}"><rect width="{w}" height="{h}" fill="#fff"/>'
                           f'<path d="{" ".join(L.cuts)}" fill="#000"/></mask>')
                out.append(f'<g{filt}><path d="{d}" fill="{L.colour}" mask="url(#m{uid})"/></g>')
            else:
                out.append(f'<g{filt}><path d="{d}" fill="{L.colour}"/></g>')
            out.extend(L.extra)
    out.append("</svg>")
    return "\n".join(out)


# ================================================================ TOSK (reusable)
# Local coordinates: Tosk sits facing right, roughly in x 40..310, y 40..350.
TAIL_OUTER = [(150, 330), (108, 340), (66, 318), (42, 268), (40, 206), (56, 148),
              (90, 96), (138, 60), (194, 46), (238, 58), (256, 84)]
TAIL_TIP = (252, 100)
TAIL_INNER = [(226, 80), (190, 70), (148, 86), (116, 122), (104, 176), (108, 236),
              (122, 288), (144, 314)]

BODY = [
    (304, 152, "sharp"),                     # nose tip
    (292, 140), (276, 118), (262, 100),      # muzzle, forehead
    (254, 94),                               # ear front base
    (264, 44, "sharp"), (250, 64), (238, 42, "sharp"),  # tufted ear
    (232, 100),                              # ear back base
    (218, 112), (204, 134),                  # back of head, neck
    (180, 164), (156, 206), (140, 250),      # back
    (130, 296), (134, 326), (152, 342),      # haunch, rump
    (190, 348), (222, 346, "sharp"), (228, 336),  # hind foot & toes
    (230, 312), (234, 282), (240, 254),      # belly
    (252, 240), (284, 232, "sharp"), (276, 220),  # front paw holding the letter
    (254, 206), (254, 186), (266, 170), (288, 162),  # chest, throat, chin
]
BELLY = [(268, 184), (252, 204), (244, 232), (240, 262), (236, 296), (232, 322),
         (222, 336), (206, 326), (210, 296), (218, 258), (230, 220), (248, 192)]
EYE = [(272, 126), (284, 118), (298, 126), (286, 138)]
EYE_C = (285, 128)
NOSE_C = (301, 151)


def tosk_layers(xf: XF, detail=2, light_mono="white"):
    """Return layers for Tosk under transform xf. detail 0..2."""
    # --- tail
    outer = fur(TAIL_OUTER, pitch=16 if detail else 24, depth=8 if detail else 6, side=1, lean=0.5)
    tail_pts = outer + [(*TAIL_TIP, "sharp")] + TAIL_INNER
    tail = Layer(RUSTD)
    tail.fill(smooth(xf.pts(tail_pts), tension=1.0))
    if detail >= 1:
        tail.cut(xf.lens((70, 296), (88, 190), 3.0, bulge=-12))
        tail.cut(xf.lens((62, 236), (120, 110), 3.4, bulge=-20))
        tail.cut(xf.lens((100, 140), (178, 72), 3.0, bulge=-12))
        tail.cut(xf.lens((150, 100), (226, 92), 2.4, bulge=-6))
    if detail >= 2:
        tail.cut(xf.lens((96, 300), (74, 262), 2.2, bulge=6))
        tail.cut(xf.lens((128, 128), (156, 110), 2.0, bulge=-3))
        tail.cut(xf.lens((206, 100), (236, 110), 1.8, bulge=-3))
        tail.cut(xf.lens((86, 214), (100, 160), 2.0, bulge=-5))
    # --- body
    body = Layer(RUST)
    body.fill(smooth(xf.pts(BODY), tension=1.0))
    if detail >= 1:
        body.cut(xf.lens((236, 96), (250, 56), 2.6, bulge=-3))             # inner ear
        body.cut(xf.lens((146, 258), (190, 232), 2.6, bulge=10))           # haunch crescent
    if detail >= 2:
        body.cut(xf.lens((160, 300), (198, 282), 2.4, bulge=8))
        body.cut(xf.lens((164, 186), (186, 160), 2.0, bulge=4))
        body.cut(xf.lens((148, 220), (172, 196), 2.0, bulge=4))
        body.cut(xf.lens((292, 160), (276, 168), 1.4, bulge=-2))           # smile
        body.cut(xf.circle(272, 112, 1.6))
    # --- light paper: belly patch (colour only), eye, letter
    belly = Layer(PAPER, shadow=False, mono="skip")
    if detail >= 1:
        belly.fill(smooth(xf.pts(BELLY)))
    light = Layer(PAPER, shadow=False, mono=light_mono)
    light.fill(smooth(xf.pts(EYE), tension=1.3))
    if detail >= 1:
        # rolled letter: a scroll held in the paws
        scroll = [(0, 0, "sharp"), (54, 0, "sharp"), (54, 26, "sharp"), (0, 26, "sharp")]
        sx = XF(0, 0, 1, -22)
        pts = [(x + 236, y + 220) for (x, y, *_r) in sx.pts(scroll)]
        pts = [(p[0], p[1], "sharp") for p in pts]
        light.fill(smooth(xf.pts(pts)))
        # tyr rune cut into the letter
        base = XF(0, 0, 1, -22)

        def L(p):
            q = base.p(*p)
            return (q[0] + 236, q[1] + 220)
        light.cut(xf.lens(L((22, 5)), L((22, 22)), 1.4))
        light.cut(xf.lens(L((22, 6)), L((13, 13)), 1.2))
        light.cut(xf.lens(L((22, 6)), L((31, 13)), 1.2))
        light.cut(xf.lens(L((36, 5)), L((44, 22)), 1.2))
        light.cut(xf.lens(L((44, 5)), L((36, 22)), 1.2))
    # --- ink: pupil + nose; paper highlight dot
    ink = Layer(INK, shadow=False)
    ink.fill(xf.circle(*EYE_C, 5.2 if detail else 7))
    ink.fill(xf.circle(*NOSE_C, 3.6))
    glint = Layer(PAPER, shadow=False, mono=light_mono)
    glint.fill(xf.circle(EYE_C[0] - 1.8, EYE_C[1] - 2, 1.9))
    return [tail, body, belly, light, ink, glint]


def tosk_svg(mono=False):
    xf = XF(26, 10, 1.0, 0)
    branch = Layer(INK)
    br = [(16, 352), (90, 346), (200, 352), (300, 342), (404, 330, "sharp"),
          (406, 344, "sharp"), (300, 360), (200, 370), (90, 366), (14, 370, "sharp")]
    branch.fill(smooth(br, tension=0.9))
    for (cx, cy, ang) in [(318, 318, -62), (342, 316, -36), (362, 330, -14), (338, 346, 28), (306, 336, 62)]:
        b, cuts = leaf(cx, cy, 30, 8, ang, leaflets=2)
        branch.fill(b)
        branch.cut(cuts)
    for (cx, cy, ang) in [(70, 376, 200), (50, 388, 158), (92, 388, 122)]:
        b, cuts = leaf(cx, cy, 26, 7, ang, leaflets=1)
        branch.fill(b)
        branch.cut(cuts)
    branch.cut(lens((60, 362), (170, 360), 1.6, bulge=3))
    branch.cut(lens((230, 356), (340, 346), 1.6, bulge=3))
    layers = [branch] + tosk_layers(xf, detail=2)
    return render_layers(layers, 440, 410, mono=mono)


# ================================================================ NODES
def node_layers(positions, r=34, runes=None, mono_runes=True):
    """Skill nodes: ochre scalloped medallion, cream centre, cut rune."""
    nodes = Layer(OCHRE, opacity=0.22, blur=2.5)
    light = Layer(PAPER, shadow=False, mono="white")
    for i, (nx, ny) in enumerate(positions):
        nodes.fill(scallop(nx, ny, r, 12, r * 0.14))
        nodes.cut(ring(nx, ny, r * 0.72, r * 0.64))
        light.fill(circle(nx, ny, r * 0.5))
        if runes:
            rn = runes[i % len(runes)]
            light.extra.append(
                f'<text x="{fmt(nx)}" y="{fmt(ny + r * 0.27)}" text-anchor="middle" font-size="{fmt(r * 0.78)}" '
                f'font-family="Segoe UI Symbol, Segoe UI Historic, Noto Sans Runic, sans-serif" fill="{INK}">{rn}</text>')
            light.extra_mono.append(
                f'<text x="{fmt(nx)}" y="{fmt(ny + r * 0.27)}" text-anchor="middle" font-size="{fmt(r * 0.78)}" '
                f'font-family="Segoe UI Symbol, Segoe UI Historic, Noto Sans Runic, sans-serif" fill="{BLACK}">{rn}</text>')
    return [nodes, light]


# ================================================================ ICON
def icon_layers():
    S = 512
    back = Layer(INK, shadow=False)
    r = 112
    back.fill(f"M{r},0 H{S - r} Q{S},0 {S},{r} V{S - r} Q{S},{S} {S - r},{S} H{r} Q0,{S} 0,{S - r} V{r} Q0,0 {r},0 Z")
    med = Layer(PAPER, mono="white", opacity=0.35)
    med.fill(scallop(256, 256, 218, 16, 14))
    for i in range(16):
        a = 2 * math.pi * (i + 0.5) / 16 - math.pi / 2
        med.cut(circle(256 + 190 * math.cos(a), 256 + 190 * math.sin(a), 5))
    # Tosk, scaled to fill the medallion: local bbox ~ (40..310, 40..350)
    s = 1.12
    xf = XF(256 - 174 * s, 256 - 198 * s + 4, s, 0)
    tosk = tosk_layers(xf, detail=1, light_mono="black")
    # in mono the medallion is white and Tosk black -> his eye must be white.
    for L in tosk:
        if L.colour == PAPER:
            L.mono = "white"
        if L.colour == INK:
            L.mono = "black"
    return [back, med] + tosk


def icon_svg(mono=False):
    return render_layers(icon_layers(), 512, 512, mono=mono)


# ================================================================ LOGO
def logo_svg():
    inner = render_layers(icon_layers(), 512, 512)
    body = inner.split("\n", 1)[1].rsplit("</svg>", 1)[0]
    parts = [f'<g transform="translate(16,16) scale(0.33)">{body}</g>']
    letters = (
        "M234,62 V150 Q234,172 256,172 Q268,172 274,166 "
        "M218,96 H262 "
        "M330,170 C302,170 292,146 292,128 C292,104 310,88 334,88 C360,88 372,108 372,130 C372,154 356,170 330,170 Z "
        "M452,100 C444,90 428,88 414,92 C396,98 394,116 408,124 C420,130 440,132 450,140 C464,152 454,174 428,174 C412,174 404,170 396,162 "
        "M492,60 V172 M542,94 L498,138 M504,130 L546,172"
    )
    stroke = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
    parts.append(f'<g filter="url(#sh)"><path d="{letters}" {stroke} stroke="{INK}" stroke-width="22"/></g>')
    parts.append(f'<path d="{letters}" {stroke} stroke="{RUST}" stroke-width="12"/>')
    head = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 580 200" width="580" height="200">'
            '<defs><filter id="sh" x="-10%" y="-10%" width="125%" height="130%">'
            '<feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#1E1A14" flood-opacity="0.30"/>'
            '</filter></defs>')
    return head + "\n".join(parts) + "</svg>"


# ================================================================ YGGDRASIL
def ygg_layers(W=800, H=1100):
    cx = W / 2
    # ---- canopy dome (sage, openwork) behind everything
    canopy = Layer(SAGE, opacity=0.25)
    dome_c = (cx, 330)
    canopy.fill(scallop(dome_c[0], dome_c[1], 300, 28, 16))
    # radial frond cut-outs (ash leaves as negative space)
    for ringi, (rr, cnt, ln) in enumerate([(240, 22, 60), (170, 15, 54), (100, 9, 46)]):
        for j in range(cnt):
            a = 2 * math.pi * j / cnt - math.pi / 2 + (0.5 * ringi * 2 * math.pi / cnt)
            lx, ly = dome_c[0] + rr * math.cos(a), dome_c[1] + rr * math.sin(a)
            ang = math.degrees(a)
            canopy.cut(lens((lx - math.cos(a) * ln / 2, ly - math.sin(a) * ln / 2),
                            (lx + math.cos(a) * ln / 2, ly + math.sin(a) * ln / 2), 4.2))
            for sgn in (-1, 1):
                for t in (-0.18, 0.08):
                    bx, by = lx + math.cos(a) * ln * t, ly + math.sin(a) * ln * t
                    ex = bx + math.cos(a + sgn * 1.0) * 16
                    ey = by + math.sin(a + sgn * 1.0) * 16
                    canopy.cut(lens((bx + math.cos(a + sgn * 1.0) * 5, by + math.sin(a + sgn * 1.0) * 5), (ex, ey), 1.6))
    canopy.cut(circle(cx, 330, 30))

    # ---- the tree (ink)
    tree = Layer(INK)
    trunk_left = [
        (82, 1016, "sharp"), (150, 964), (230, 932), (296, 898), (336, 846),
        (354, 770), (360, 680), (358, 580), (352, 480), (344, 400), (330, 330),
        (306, 262), (300, 210, "sharp"), (332, 232), (360, 262), (380, 300),
    ]
    trunk_top = [(cx, 320)]
    trunk_right = [(2 * cx - x, y) + tuple(r) for (x, y, *r) in reversed(trunk_left)]
    # bottom edge: three roots with arches between them (right -> left)
    bottom = [
        (686, 1002), (620, 982), (560, 972), (520, 988), (486, 1024), (452, 1064, "sharp"),
        (430, 1040), (400, 1030), (370, 1040), (348, 1064, "sharp"), (314, 1024), (280, 988),
        (240, 972), (180, 982), (114, 1002),
    ]
    tree.fill(smooth(trunk_left + trunk_top + trunk_right + bottom, tension=1.0))
    # ---- branches: three tiers each side, curving up, plus crown node
    tiers = [  # (y attach, length, rise, thickness)
        (770, 300, 230, 30), (610, 270, 230, 26), (470, 230, 220, 22),
    ]
    positions = []
    for (y, L, rise, th) in tiers:
        for s in (-1, 1):
            x0 = cx + s * 36
            pts = [
                (x0, y - 8), (x0 + s * L * 0.3, y - rise * 0.1), (x0 + s * L * 0.62, y - rise * 0.45),
                (x0 + s * L * 0.88, y - rise * 0.85), (x0 + s * L, y - rise - 10, "sharp"),
                (x0 + s * L * 0.86, y - rise * 0.85 + th * 0.7), (x0 + s * L * 0.6, y - rise * 0.45 + th),
                (x0 + s * L * 0.28, y - rise * 0.1 + th * 1.3), (x0, y + th + 30),
            ]
            tree.fill(smooth(pts, tension=0.9))
            # a twig with leaves under the branch
            for k in range(2):
                t = 0.42 + k * 0.26
                bx = x0 + s * L * t
                by = y - rise * (0.1 + (t - 0.3) * 0.9) + th * 1.1
                b, cuts = leaf(bx, by + 18, 36, 9, 90 - s * 30 + k * s * 10, leaflets=2)
                tree.fill(b)
                tree.cut(cuts)
            positions.append((x0 + s * L, y - rise - 12))
    positions.append((cx, 330))
    # bark slits
    for yy in (800, 700, 600, 500, 420):
        tree.cut(lens((cx - 26, yy + 50), (cx - 16, yy), 2.0, bulge=-4))
        tree.cut(lens((cx + 16, yy), (cx + 26, yy + 50), 2.0, bulge=4))
    # runes cut into the trunk (Tiwaz, Ansuz, Raido, Othala)
    def rune(kind, x, y, h=36):
        w = h * 0.36
        c = []
        if kind == "t":
            c += [lens((x, y - h / 2), (x, y + h / 2), 1.6), lens((x, y - h / 2), (x - w, y - h / 6), 1.4),
                  lens((x, y - h / 2), (x + w, y - h / 6), 1.4)]
        elif kind == "a":
            c += [lens((x - w / 2, y - h / 2), (x - w / 2, y + h / 2), 1.6),
                  lens((x - w / 2, y - h / 2), (x + w / 2, y - h / 5), 1.4),
                  lens((x - w / 2, y - h / 6), (x + w / 2, y + h / 6), 1.4)]
        elif kind == "r":
            c += [lens((x - w / 2, y - h / 2), (x - w / 2, y + h / 2), 1.6),
                  lens((x - w / 2, y - h / 2), (x + w / 2, y - h / 4), 1.4),
                  lens((x + w / 2, y - h / 4), (x - w / 2, y), 1.4),
                  lens((x - w / 2, y), (x + w / 2, y + h / 2), 1.4)]
        elif kind == "o":
            c += [lens((x, y - h / 2), (x - w, y), 1.4), lens((x, y - h / 2), (x + w, y), 1.4),
                  lens((x - w, y), (x, y + h / 2), 1.4), lens((x + w, y), (x, y + h / 2), 1.4),
                  lens((x - w * 0.45, y + h * 0.1), (x - w * 1.1, y + h / 2), 1.4),
                  lens((x + w * 0.45, y + h * 0.1), (x + w * 1.1, y + h / 2), 1.4)]
        return c
    tree.cut(rune("t", cx, 740))
    tree.cut(rune("a", cx, 860))
    tree.cut(rune("o", cx, 960, 30))
    # knot eye
    tree.cut(ring(cx + 2, 540, 22, 14))
    tree.cut(circle(cx + 2, 540, 5))

    # ---- the eagle perched on the crown
    eagle = [
        (cx - 60, 40, "sharp"), (cx - 30, 56), (cx - 4, 86), (cx + 6, 120), (cx + 4, 150),
        (cx - 10, 166), (cx - 30, 168, "sharp"), (cx - 12, 156), (cx - 10, 130), (cx - 20, 104),
        (cx - 42, 90), (cx - 58, 102), (cx - 70, 92, "sharp"), (cx - 62, 84), (cx - 54, 66),
    ]
    # body/wing to the right; head left with hooked beak
    eagle2 = [
        (cx - 36, 60), (cx - 10, 50), (cx + 30, 48), (cx + 70, 60), (cx + 96, 90), (cx + 108, 130),
        (cx + 96, 160, "sharp"), (cx + 120, 150), (cx + 150, 158, "sharp"), (cx + 126, 170),
        (cx + 100, 176), (cx + 60, 172), (cx + 24, 160), (cx + 2, 150), (cx - 6, 120), (cx - 10, 86),
    ]
    bird = Layer(INK)
    bird.fill(smooth(eagle2, tension=0.9))
    bird.fill(smooth(eagle, tension=0.9))
    bird.cut(circle(cx - 46, 64, 4))
    bird.cut(lens((cx + 20, 80), (cx + 70, 150), 2.4, bulge=-8))
    bird.cut(lens((cx + 44, 70), (cx + 94, 140), 2.2, bulge=-8))
    bird.cut(lens((cx + 2, 100), (cx + 44, 158), 2.0, bulge=-6))
    bird.cut(lens((cx + 100, 162), (cx + 136, 162), 1.4))

    # ---- Níðhöggr coiling around the right root
    serp = [
        (548, 1006), (590, 1030), (640, 1060), (700, 1072), (746, 1050), (760, 1012),
        (746, 982), (716, 968), (692, 950, "sharp"), (706, 940, "sharp"), (688, 930),
        (664, 946), (650, 976), (666, 1008), (700, 1030), (730, 1030), (736, 1010),
        (720, 996), (700, 1004), (690, 1024), (650, 1016), (610, 992), (566, 972),
        (540, 980),
    ]
    dragon = Layer(INK)
    dragon.fill(smooth(serp, tension=0.9))
    dragon.cut(circle(696, 946, 3.2))
    for k in range(6):
        x = 580 + k * 26
        dragon.cut(lens((x, 1036 + k * 4), (x + 10, 1016 + k * 4), 1.6, bulge=2))
    # horns
    dragon.fill(smooth([(690, 932), (700, 904, "sharp"), (704, 936)], tension=0.8))
    dragon.fill(smooth([(676, 936), (676, 908, "sharp"), (688, 938)], tension=0.8))

    # ---- the well (Urðarbrunnr) under the left root arch
    well = Layer(INK)
    well.fill(circle(230, 1036, 30))
    well.cut(circle(230, 1036, 22))
    well.cut(lens((214, 1040), (246, 1040), 1.0, bulge=3))
    wellw = Layer(PAPER, shadow=False, mono="white")
    wellw.fill(circle(230, 1036, 22))
    wellw.cut(lens((214, 1040), (246, 1040), 1.2, bulge=3))
    wellw.cut(lens((218, 1031), (242, 1031), 1.2, bulge=3))
    # stones: two little rocks
    tree.fill(smooth([(176, 1050), (196, 1040), (216, 1052), (198, 1064)]))

    # ---- Tosk climbing the trunk (rust in colour; a white window in mono)
    s = 0.46
    xf = XF(cx - 22, 598, s, -32)
    tosk = tosk_layers(xf, detail=1, light_mono="black")
    for L in tosk:
        if L.colour in (RUST, RUSTD):
            L.mono = "white"
            L.shadow = False
        if L.colour == PAPER:
            L.mono = "black"

    # ---- skill nodes
    runes = ["ᚠ", "ᚢ", "ᚦ", "ᚨ", "ᚱ", "ᚲ", "ᚷ"]
    nodes = node_layers(positions, r=36, runes=runes)
    return [canopy, tree, bird, dragon, well, wellw] + tosk + nodes


def ygg_svg(mono=False):
    return render_layers(ygg_layers(), 800, 1100, mono=mono, bg=None if mono else PAPER)


# ================================================================ BRANCH TILE
def tile_layers(W=400, H=400):
    cx = W / 2
    wood = Layer(INK)
    fork = [
        (cx - 20, 352), (cx - 24, 300), (cx - 30, 250), (cx - 60, 196), (cx - 110, 150),
        (cx - 140, 96), (cx - 150, 60, "sharp"), (cx - 118, 100), (cx - 76, 152), (cx - 30, 200),
        (cx, 214), (cx + 30, 196), (cx + 80, 150), (cx + 124, 100), (cx + 150, 62, "sharp"),
        (cx + 140, 100), (cx + 110, 152), (cx + 62, 200), (cx + 32, 254), (cx + 24, 300), (cx + 20, 352),
    ]
    wood.fill(smooth(fork, tension=0.9))
    for (lx, ly, ang) in [(cx - 112, 84, -70), (cx - 136, 128, -10), (cx + 110, 86, 70), (cx + 136, 130, 10),
                          (cx - 66, 236, -130), (cx + 66, 236, 130), (cx - 108, 176, 20), (cx + 108, 176, -20)]:
        b, cuts = leaf(lx, ly, 44, 11, ang, leaflets=2)
        wood.fill(b)
        wood.cut(cuts)
    wood.cut(lens((cx - 8, 330), (cx - 4, 262), 1.8, bulge=-3))
    wood.cut(lens((cx + 8, 300), (cx + 10, 250), 1.5, bulge=2))
    wood.cut(lens((cx - 40, 190), (cx - 90, 140), 1.6, bulge=4))
    wood.cut(lens((cx + 40, 190), (cx + 90, 140), 1.6, bulge=-4))
    nodes = node_layers([(cx - 150, 60), (cx + 150, 62), (cx, 352)], r=34)
    return [wood] + nodes


def tile_svg(mono=False):
    return render_layers(tile_layers(), 400, 400, mono=mono)


# ================================================================ SHEET
def sheet_html():
    sw = "".join(
        f'<div class="sw"><div class="chip" style="background:{hexv}"></div><div>{name}<br><code>{hexv}</code></div></div>'
        for name, hexv in PALETTE)
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>tosk - papercut</title>
<style>
body{{margin:0;background:{PAPER};font-family:Georgia,serif;color:{INK};padding:24px}}
h1{{margin:0 0 4px;font-size:40px;letter-spacing:-1px}} p{{margin:0 0 18px}}
.row{{display:flex;gap:18px;flex-wrap:wrap;align-items:flex-start;margin-bottom:18px}}
.card{{background:#fff8ec;border:2px solid {INK};border-radius:14px;padding:12px;text-align:center}}
.card.mono{{background:#fff}}
.card img{{display:block}} .cap{{font-size:14px;margin-top:6px}}
.icons img{{display:inline-block;margin:4px;vertical-align:middle;background:#fff}}
.sw{{display:flex;gap:8px;align-items:center;font-size:13px;margin-right:16px}}
.chip{{width:34px;height:34px;border-radius:8px;border:2px solid {INK}}}
</style></head><body>
<h1>tosk</h1>
<p>Scandinavian papercut: layered cut paper with soft shadows in colour; a single sheet of black paper for e-ink.</p>
<div class="row">
 <div class="card"><img src="tosk.svg" width="320"><div class="cap">Tosk</div></div>
 <div class="card mono"><img src="tosk-mono.svg" width="320"><div class="cap">Tosk - e-ink</div></div>
 <div class="card"><img src="icon.svg" width="160"><div class="cap">App icon</div></div>
 <div class="card mono"><img src="icon-mono.svg" width="160"><div class="cap">Icon - e-ink</div></div>
 <div class="card icons"><img src="icon.svg" width="96"><img src="icon.svg" width="48"><br><img src="icon-mono.svg" width="96"><img src="icon-mono.svg" width="48"><div class="cap">96 / 48 px</div></div>
</div>
<div class="row">
 <div class="card"><img src="logo.svg" width="480"><div class="cap">Logo</div></div>
 <div class="card" style="display:flex;flex-wrap:wrap;align-items:center;max-width:520px">{sw}</div>
</div>
<div class="row">
 <div class="card"><img src="yggdrasil.svg" width="380"><div class="cap">Yggdrasil - course tree</div></div>
 <div class="card mono"><img src="yggdrasil-mono.svg" width="380"><div class="cap">Yggdrasil - e-ink</div></div>
 <div>
  <div class="card" style="margin-bottom:18px"><img src="branch-tile.svg" width="260"><div class="cap">Branch tile</div></div>
  <div class="card mono"><img src="branch-tile-mono.svg" width="260"><div class="cap">Branch tile - e-ink</div></div>
 </div>
</div>
</body></html>"""


def main():
    files = {
        "tosk.svg": tosk_svg(False), "tosk-mono.svg": tosk_svg(True),
        "icon.svg": icon_svg(False), "icon-mono.svg": icon_svg(True),
        "logo.svg": logo_svg(),
        "yggdrasil.svg": ygg_svg(False), "yggdrasil-mono.svg": ygg_svg(True),
        "branch-tile.svg": tile_svg(False), "branch-tile-mono.svg": tile_svg(True),
        "sheet.html": sheet_html(),
    }
    for name, content in files.items():
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
            f.write(content)
        print(f"{name:22s} {len(content.encode('utf-8')) / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
