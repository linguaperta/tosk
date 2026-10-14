"""tosk brand exploration: Norse woodcut / linocut style.

Run:  python make_woodcut.py   -> writes the SVGs + sheet.html next to this file.

Pure Python, no dependencies. Everything is built from organic Catmull-Rom
silhouettes, "ribbons" (tapered strokes computed as closed shapes, optionally
with a fur-spiked edge) and "gouges" (tapered lens cuts), so the pieces look
carved rather than assembled from primitives. Two blocks per print: a flat
colour block underneath and a black key block on top. The mono version is the
key block printed alone.
"""
from __future__ import annotations

import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- palette
COLOUR = dict(
    ink="#1C1814",    # ink black (warm)
    paper="#F3EAD6",  # birch cream
    rust="#B8452A",   # rust red
    moss="#5C7A3B",   # moss green
    umber="#5E3F2B",  # bark umber
    ochre="#D8A23B",  # ochre (eye, seeds)
)
MONO = dict(ink="#000000", paper="#FFFFFF", rust="#FFFFFF", moss="#FFFFFF",
            umber="#FFFFFF", ochre="#FFFFFF")


# ----------------------------------------------------------------- helpers
def f(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


class Rnd:
    """Tiny deterministic LCG so the gouge jitter is stable between runs."""

    def __init__(self, seed: int):
        self.s = seed & 0x7FFFFFFF

    def r(self) -> float:
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x7FFFFFFF

    def u(self, a: float, b: float) -> float:
        return a + (b - a) * self.r()


def _k(p):
    return p[2] if len(p) > 2 else 1.0


def _beziers(pts, closed):
    n = len(pts)

    def get(i):
        return pts[i % n] if closed else pts[max(0, min(n - 1, i))]

    def tan(i):
        a, b = get(i - 1), get(i + 1)
        k = _k(get(i))
        return ((b[0] - a[0]) / 2 * k, (b[1] - a[1]) / 2 * k)

    segs = n if closed else n - 1
    for i in range(segs):
        p0, p1 = get(i), get(i + 1)
        t0, t1 = tan(i), tan(i + 1)
        yield (p0[0], p0[1]), (p0[0] + t0[0] / 3, p0[1] + t0[1] / 3), (p1[0] - t1[0] / 3, p1[1] - t1[1] / 3), (p1[0], p1[1])


def spline(pts, closed=True) -> str:
    """Catmull-Rom through pts -> cubic Bézier path. A point may be (x, y, k)
    where k scales the tangent (0 = sharp corner)."""
    out = [f"M {f(pts[0][0])} {f(pts[0][1])}"]
    for (_, c1, c2, p1) in _beziers(pts, closed):
        out.append(f"C {f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p1[0])} {f(p1[1])}")
    if closed:
        out.append("Z")
    return " ".join(out)


def sample(pts, closed=False, per=8):
    """Dense polyline along the spline."""
    out = [(pts[0][0], pts[0][1])]
    for (p0, c1, c2, p1) in _beziers(pts, closed):
        for j in range(1, per + 1):
            t = j / per
            u = 1 - t
            x = u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p1[0]
            y = u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p1[1]
            out.append((x, y))
    return out


def centre(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def polyline(pts) -> str:
    return " ".join(f"{'M' if i == 0 else 'L'} {f(p[0])} {f(p[1])}" for i, p in enumerate(pts))


def ribbon_sides(pts, widths):
    n = len(pts)
    left, right = [], []
    for i in range(n):
        a = pts[max(0, i - 1)]
        b = pts[min(n - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        L = math.hypot(tx, ty) or 1
        nx, ny = -ty / L, tx / L
        w = widths[i] / 2
        left.append((pts[i][0] + nx * w, pts[i][1] + ny * w))
        right.append((pts[i][0] - nx * w, pts[i][1] - ny * w))
    return left, right


def fur(side, outward, amp, step, rnd, k_on=0.5):
    """Resample a side curve and push every other sample out into a fur spike.
    `outward` is +1/-1: which way the side's normal points out of the shape."""
    dense = sample(side, False, 10)
    # arc-length resample
    out = []
    acc = 0.0
    nxt = step * 0.5
    for i in range(1, len(dense)):
        a, b = dense[i - 1], dense[i]
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        while acc + seg >= nxt:
            t = (nxt - acc) / seg if seg else 0
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            tx, ty = (b[0] - a[0]) / (seg or 1), (b[1] - a[1]) / (seg or 1)
            out.append((x, y, tx, ty))
            nxt += step * rnd.u(0.8, 1.2)
        acc += seg
    res = []
    m = max(1, len(out) - 1)
    for j, (x, y, tx, ty) in enumerate(out):
        nx, ny = -ty * outward, tx * outward
        if j % 2 == 1:
            # tufts grow along the plume: short at the root, long towards the tip,
            # with a slow wave so the edge is not a saw blade
            env = 0.45 + 0.55 * math.sin(math.pi * min(1.0, j / m * 1.15)) + 0.25 * math.sin(j * 1.7)
            a = amp * env * rnd.u(0.75, 1.25)
            lean = rnd.u(0.3, 0.9)
            res.append((x + nx * a + tx * a * lean, y + ny * a + ty * a * lean, 0))
        else:
            res.append((x, y, k_on))
    return res


def ribbon(pts, widths, tip="round", root="round", fur_left=None, fur_right=None, rnd=None):
    """Closed outline points for a tapered stroke along a centreline.
    fur_left / fur_right = (amp, step) to serrate that side."""
    left, right = ribbon_sides(pts, widths)
    if fur_left:
        left = fur(left, +1, fur_left[0], fur_left[1], rnd or Rnd(1))
    if fur_right:
        right = fur(right, -1, fur_right[0], fur_right[1], rnd or Rnd(2))
    pts_out = list(left)
    right_rev = list(reversed(right))
    if tip == "sharp":
        pts_out[-1] = (left[-1][0], left[-1][1], 0)
        right_rev[0] = (right_rev[0][0], right_rev[0][1], 0)
    pts_out += right_rev
    if root == "sharp":
        pts_out[0] = (pts_out[0][0], pts_out[0][1], 0)
        pts_out[-1] = (pts_out[-1][0], pts_out[-1][1], 0)
    return pts_out


def along(pts, s):
    n = len(pts)
    s = max(0, min(n - 1 - 1e-6, s))
    i = int(s)
    t = s - i
    a, b = pts[i], pts[i + 1]
    x = a[0] + (b[0] - a[0]) * t
    y = a[1] + (b[1] - a[1]) * t
    tx, ty = b[0] - a[0], b[1] - a[1]
    L = math.hypot(tx, ty) or 1
    return (x, y), (tx / L, ty / L)


def gouge(p0, p1, w, bend=0.0) -> str:
    """A tapered lens cut from p0 to p1, max thickness ~w, optional sideways bend."""
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy / L, dx / L
    mx += nx * bend
    my += ny * bend
    return (f"M {f(p0[0])} {f(p0[1])} Q {f(mx + nx * w)} {f(my + ny * w)} {f(p1[0])} {f(p1[1])} "
            f"Q {f(mx - nx * w)} {f(my - ny * w)} {f(p0[0])} {f(p0[1])} Z")


def path(d, fill, extra="") -> str:
    return f'<path d="{d}" fill="{fill}"{extra}/>\n'


def stroke(d, colour, w, cap="round", join="round") -> str:
    return (f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{f(w)}" '
            f'stroke-linecap="{cap}" stroke-linejoin="{join}"/>\n')


def carved(pts, pal, colour_key, scale=0.93, sy=None, dx=0.0, dy=0.0, edge=2.5, closed=True) -> str:
    """Key block: black silhouette; colour block: the same shape a little
    smaller and shifted, so the black edge has a hand-cut thick/thin line."""
    d = spline(pts, closed)
    cx, cy = centre(pts)
    sy = scale if sy is None else sy
    out = path(d, pal["ink"])
    tr = f' transform="translate({f(cx + dx)} {f(cy + dy)}) scale({f(scale)} {f(sy)}) translate({f(-cx)} {f(-cy)})"'
    out += path(d, pal[colour_key], tr)
    if edge:
        out += stroke(d, pal["ink"], edge)
    return out


def carved_ribbon(pts, widths, pal, colour_key, shrink=0.72, dx=0.0, dy=0.0, edge=2.5, tip="round",
                  root="round", trim=0.0, **kw) -> str:
    """Ribbon with an exact narrower colour ribbon inside (no end artefacts)."""
    outer = ribbon(pts, widths, tip=tip, root=root, **kw)
    d = spline(outer)
    out = path(d, pal["ink"])
    inner_pts = [(p[0] + dx, p[1] + dy) for p in pts]
    inner_w = [w * shrink for w in widths]
    if trim:
        # pull the inner tip back along the centreline
        (x, y), (tx, ty) = along(pts, len(pts) - 1)
        inner_pts[-1] = (inner_pts[-1][0] - tx * trim, inner_pts[-1][1] - ty * trim)
    inner = ribbon(inner_pts, inner_w, tip=tip, root=root)
    out += path(spline(inner), pal[colour_key])
    if edge:
        out += stroke(d, pal["ink"], edge)
    return out


def gouges_along(pts, widths, rnd, n, colour, length=(10, 22), thick=(1.4, 2.6),
                 spread=0.8, bend=0.0, skew=0.0, side=None) -> str:
    """Scatter gouges following a ribbon's direction (fur / bark / feathers).
    side=+1/-1 restricts the cuts to one half of the ribbon."""
    out = ""
    m = len(pts) - 1
    for _ in range(n):
        s = rnd.u(0.05, m - 0.05)
        (x, y), (tx, ty) = along(pts, s)
        i = int(s)
        w = widths[i] + (widths[min(i + 1, m)] - widths[i]) * (s - i)
        off = rnd.u(-spread, spread) * w / 2
        if side:
            off = abs(off) * side
        nx, ny = -ty, tx
        ln = rnd.u(*length)
        c, sn = math.cos(skew), math.sin(skew)
        dxx, dyy = tx * c - ty * sn, tx * sn + ty * c
        p0 = (x + nx * off - dxx * ln / 2, y + ny * off - dyy * ln / 2)
        p1 = (x + nx * off + dxx * ln / 2, y + ny * off + dyy * ln / 2)
        out += path(gouge(p0, p1, rnd.u(*thick), bend * rnd.u(0.5, 1.5)), colour)
    return out


# ----------------------------------------------------------------- runes
RUNES = {
    "f": [[(0, 0), (0, 1)], [(0, 0.22), (0.6, 0.0)], [(0, 0.5), (0.6, 0.28)]],
    "u": [[(0, 1), (0, 0), (0.6, 0.32), (0.6, 1)]],
    "th": [[(0, 0), (0, 1)], [(0, 0.2), (0.55, 0.5), (0, 0.8)]],
    "a": [[(0, 0), (0, 1)], [(0, 0.1), (0.6, 0.36)], [(0, 0.42), (0.6, 0.68)]],
    "r": [[(0, 1), (0, 0), (0.55, 0.25), (0, 0.5), (0.6, 1)]],
    "k": [[(0.55, 0), (0, 0.5), (0.55, 1)]],
    "g": [[(0, 0), (0.6, 1)], [(0.6, 0), (0, 1)]],
    "t": [[(0.3, 0), (0.3, 1)], [(0, 0.3), (0.3, 0), (0.6, 0.3)]],
    "o": [[(0.3, 0), (0.6, 0.4), (0.15, 1)], [(0.3, 0), (0, 0.4), (0.45, 1)]],
    "s": [[(0.6, 0), (0, 0.33), (0.6, 0.66), (0, 1)]],
}


def rune(name, cx, cy, h, colour, w=None) -> str:
    w = w or h * 0.17
    out = ""
    for poly in RUNES[name]:
        d = polyline([(cx + (x - 0.3) * h, cy + (y - 0.5) * h) for (x, y) in poly])
        out += stroke(d, colour, w, cap="square", join="miter")
    return out


# ----------------------------------------------------------------- leaves
def ash_leaf(pal, x, y, angle, size=1.0, n=7) -> str:
    """Pinnate ash leaf: a stalk with almond leaflets, cut black with a moss
    inset and a carved midrib."""
    out = ""
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))

    def tr(px, py):
        return (x + (px * c - py * s) * size, y + (px * s + py * c) * size)

    out += stroke(polyline([tr(*p) for p in [(0, 0), (24, -2), (50, -1), (76, 2)]]), pal["ink"], 3.2 * size)
    leaflets = []
    for i in range(n):
        if i == n - 1:
            leaflets.append((66, 0, 0))
        else:
            k = i // 2
            side = -1 if i % 2 == 0 else 1
            leaflets.append((16 + k * 20, side * 10, side))
    for (lx, ly, side) in leaflets:
        ang = -0.62 * side if side else -0.03
        L, W = 26, 12
        ca, sa = math.cos(ang), math.sin(ang)
        pts = []
        for (px, py, *k) in [(0, 0, 0.3), (L * 0.4, -W / 2), (L, 0, 0), (L * 0.4, W / 2)]:
            qx, qy = px * ca - py * sa, px * sa + py * ca
            pts.append(tr(lx + qx, ly + qy) + tuple(k))
        out += carved(pts, pal, "moss", scale=0.74, dx=0, dy=0, edge=1.5 * size)
        (ax, ay), (bx, by) = pts[0][:2], pts[2][:2]
        out += path(gouge((ax + (bx - ax) * 0.15, ay + (by - ay) * 0.15),
                          (ax + (bx - ax) * 0.85, ay + (by - ay) * 0.85), 1.4 * size), pal["ink"])
    return out


# ----------------------------------------------------------------- Tosk
def tosk_figure(pal) -> str:
    """Full-body Tosk in a 400x400 space: sitting up on a branch, facing
    right, alert, the rune-letter in the paws, plume tail curling overhead."""
    rnd = Rnd(3)
    out = ""

    # --- branch (under everything)
    br = [(0, 354), (90, 342), (200, 338), (310, 324), (400, 306)]
    bw = [40, 42, 38, 36, 34]
    out += carved_ribbon(br, bw, pal, "umber", shrink=0.72, dy=-3, edge=2.5)
    out += gouges_along(br, bw, rnd, 24, pal["ink"], length=(14, 44), thick=(1.2, 2.4), spread=0.7)
    out += path(spline([(60, 348), (76, 340), (92, 347), (78, 358)]), pal["ink"])
    out += path(spline([(66, 348), (76, 344), (86, 348), (77, 353)]), pal["umber"])
    out += ash_leaf(pal, 326, 322, -30, 1.15)

    # --- tail (behind the body): a big S plume with a spiked outer edge
    tc = [(150, 300), (104, 270), (70, 214), (66, 144), (94, 88), (150, 60), (210, 60), (250, 80), (258, 108)]
    tw = [36, 60, 80, 90, 88, 76, 56, 30, 8]
    tail = ribbon(tc, tw, tip="sharp", fur_right=(10, 21), rnd=Rnd(5))
    out += carved(tail, pal, "rust", scale=0.92, sy=0.92, dx=2, dy=4, edge=2.4)
    out += gouges_along(tc, tw, rnd, 44, pal["ink"], length=(12, 30), thick=(1.4, 3.0), spread=0.9, bend=2.0,
                        skew=-0.35)
    out += gouges_along(tc, tw, rnd, 22, pal["ink"], length=(18, 38), thick=(2.0, 3.6), spread=0.95, bend=3.0,
                        skew=-0.3, side=+1)

    # --- body + head silhouette
    body = [
        (298, 40, 0),      # ear tip
        (286, 78),         # ear back edge
        (272, 98),         # back of skull
        (254, 116),        # nape
        (230, 134),        # neck
        (200, 154),        # shoulder
        (166, 186),        # upper back
        (144, 230),        # mid back
        (136, 276),        # rump
        (148, 314),        # rump bottom
        (192, 328),        # under haunch
        (246, 330),        # belly bottom
        (270, 324),        # in front of the haunch
        (280, 300),        # low belly
        (294, 262),        # belly
        (306, 226),        # chest
        (314, 198),        # throat
        (330, 180),        # chin
        (344, 166),        # under the nose
        (352, 152, 0.4),   # nose
        (342, 134),        # snout bridge
        (326, 118),        # brow
        (310, 106),        # forehead
        (308, 92),         # ear front base
    ]
    bd = spline(body)
    out += carved(body, pal, "rust", scale=0.975, dx=-1.5, dy=-1.5, edge=0)
    # deliberate heavy shadow cuts on the back and under the belly
    out += stroke(spline([(254, 116), (230, 134), (200, 154), (166, 186), (144, 230), (136, 276), (148, 314)],
                         closed=False), pal["ink"], 8, cap="butt")
    out += stroke(spline([(148, 314), (192, 328), (246, 330)], closed=False), pal["ink"], 7, cap="butt")

    # cream belly / throat patch (kept inside the outline), fur ticks on its edge
    belly = [(312, 206), (310, 240), (300, 272), (286, 300), (268, 316), (236, 318, 0.5), (246, 300),
             (260, 276), (270, 246), (282, 218), (296, 204)]
    out += path(spline(belly), pal["paper"])
    for (a, b) in [((246, 298), (234, 306)), ((260, 274), (248, 282)), ((270, 248), (258, 254)),
                   ((282, 220), (270, 224)), ((296, 206), (286, 208))]:
        out += path(gouge(a, b, 2.2), pal["ink"])
    # cheek / chin cream
    out += path(spline([(336, 172), (346, 164), (342, 178), (328, 190), (314, 196), (316, 184)]), pal["paper"])
    # the key line of the whole silhouette on top of the colour patches
    out += stroke(bd, pal["ink"], 3.2)

    # haunch: a carved curve and fur following the thigh
    out += stroke(spline([(176, 226), (168, 268), (190, 304), (236, 320)], closed=False), pal["ink"], 4.5)
    out += gouges_along([(162, 200), (150, 240), (150, 290)], [36, 40, 40], rnd, 16, pal["ink"],
                        length=(10, 26), thick=(1.2, 2.4), spread=0.9, bend=1.5)
    out += gouges_along([(200, 236), (196, 280)], [40, 44], rnd, 8, pal["ink"], length=(10, 22),
                        thick=(1.2, 2.2), spread=0.9, bend=-2)
    out += gouges_along([(196, 158), (236, 134)], [26, 26], rnd, 7, pal["ink"], length=(8, 18),
                        thick=(1.2, 2.0), spread=0.9)
    out += gouges_along([(262, 112), (292, 100)], [16, 16], rnd, 4, pal["ink"], length=(6, 12),
                        thick=(1.0, 1.8), spread=0.9)
    # small fur spikes along the back
    for (x, y, a) in [(212, 146, -2.2), (184, 170, -2.4), (158, 204, -2.7), (142, 250, -3.0)]:
        out += path(f"M {f(x)} {f(y)} L {f(x + 9 * math.cos(a))} {f(y + 9 * math.sin(a))} L {f(x + 6 * math.cos(a + 0.9))} {f(y + 6 * math.sin(a + 0.9))} Z", pal["ink"])

    # ear: inner cut + tuft hairs
    out += path(spline([(296, 54, 0), (290, 76), (300, 94), (308, 78)]), pal["paper"])
    for (a, b) in [((298, 40), (290, 22)), ((298, 40), (308, 24)), ((292, 56), (278, 48))]:
        out += stroke(polyline([a, b]), pal["ink"], 3.2)

    # eye: cream almond, pupil, highlight cut, a bold brow
    out += path(spline([(302, 132, 0), (316, 118), (334, 124), (338, 136, 0), (326, 148), (308, 144)]), pal["paper"])
    out += path(spline([(310, 134), (320, 123), (332, 128), (332, 141), (320, 146)]), pal["ink"])
    out += path(spline([(322, 126), (328, 128), (326, 133), (320, 131)]), pal["paper"])
    out += stroke(spline([(300, 128), (314, 112), (336, 118)], closed=False), pal["ink"], 4.5)
    # nose, mouth, whisker cuts
    out += path(spline([(354, 152, 0), (346, 142), (338, 150), (346, 160)]), pal["ink"])
    out += stroke(spline([(344, 164), (336, 172), (326, 172)], closed=False), pal["ink"], 2.6)
    for (a, b) in [((332, 158), (310, 154)), ((336, 166), (314, 166))]:
        out += path(gouge(a, b, 1.4), pal["ink"])

    # the rune letter: a little scroll with rolled ends, held up in both paws
    # (an open parchment with the ends rolled inwards; the rune Tiwaz = t)
    sc = [(296, 220, 0), (352, 206, 0), (360, 240, 0), (304, 254, 0)]
    out += carved(sc, pal, "paper", scale=0.92, edge=2.4)
    for (cx, cy, s) in [(303, 237, 1), (353, 224, -1)]:
        roll = [(cx - 5, cy - 14), (cx + 5, cy - 16), (cx + 7, cy), (cx + 5, cy + 16), (cx - 5, cy + 14), (cx - 7, cy)]
        out += path(spline(roll), pal["ink"])
        out += path(spline([(cx - 2, cy - 10), (cx + 2, cy - 12), (cx + 4, cy), (cx + 2, cy + 12), (cx - 2, cy + 10), (cx - 4, cy)]), pal["paper"])
        out += stroke(spline([(cx + 2 * s, cy - 4), (cx - 2 * s, cy - 1), (cx + 1 * s, cy + 3)], closed=False), pal["ink"], 1.5)
    out += rune("t", 328, 230, 22, pal["ink"], w=3.4)
    # one arm from the chest with the paw gripping the lower edge; the other
    # paw shows only its fingertips over the top edge
    arm = [(288, 228), (300, 236), (312, 246), (322, 250, 0.4), (326, 258), (316, 264), (304, 262), (294, 254),
           (286, 244)]
    out += carved(arm, pal, "rust", scale=0.8, dx=-1, dy=-1, edge=2.3)
    for (a, b) in [((310, 250), (316, 260)), ((318, 248), (322, 258))]:
        out += path(gouge(a, b, 1.4), pal["ink"])
    out += carved([(330, 206), (342, 202), (348, 208), (344, 216), (332, 218), (326, 212)], pal, "rust",
                  scale=0.72, edge=2.0)
    for (a, b) in [((334, 208), (336, 216)), ((340, 206), (342, 214))]:
        out += path(gouge(a, b, 1.2), pal["ink"])
    # hind foot on the branch, toes spread
    foot = [(252, 316), (286, 306), (320, 310, 0), (326, 318, 0), (316, 326), (300, 332, 0), (262, 334)]
    out += carved(foot, pal, "rust", scale=0.84, edge=2.4)
    for (a, b) in [((290, 316), (308, 312)), ((292, 322), (312, 320)), ((290, 328), (306, 328))]:
        out += path(gouge(a, b, 1.6), pal["ink"])
    return out


def tosk_svg(pal) -> str:
    return svg(400, 400, tosk_figure(pal), "Tosk")


# ----------------------------------------------------------------- icon figure
def squirrel_mark(pal, fill_key="paper", edge=2.2, tail_fur=True, halo=0) -> str:
    """Compact Tosk for the icon / logo, 100x100 space: a sitting squirrel
    facing left, plume tail rising up the right and curling over the head."""
    out = ""
    ink = pal["ink"]
    tc = [(70, 86), (88, 66), (90, 38), (74, 12), (48, 6), (32, 12)]
    tw = [18, 28, 32, 28, 18, 6]
    tail = ribbon(tc, tw, tip="sharp", fur_right=(5.5, 15) if tail_fur else None, rnd=Rnd(8))
    body = [
        (30, 8, 0),    # ear tip
        (40, 30),      # ear back base
        (50, 40),      # nape
        (62, 54),      # back
        (72, 72),      # rump
        (68, 88),      # rump bottom
        (50, 94),      # bottom
        (22, 92, 0),   # toes
        (26, 84),      # foot top
        (30, 72),      # belly
        (34, 60),      # chest
        (22, 58),      # chin
        (10, 52, 0),   # nose
        (18, 42),      # snout
        (22, 34),      # forehead
        (26, 30),      # ear front base
    ]
    if halo:
        out += stroke(spline(tail), pal["paper"], halo)
        out += stroke(spline(body), pal["paper"], halo)
    out += carved(tail, pal, fill_key, scale=0.9, sy=0.91, dx=1.5, dy=2.5, edge=edge)
    out += carved(body, pal, fill_key, scale=0.88, dx=-1, dy=-1, edge=edge)
    # eye, ear cut, haunch line, mouth nick, tail hair cuts
    out += path(spline([(20, 46), (26, 42), (30, 47), (24, 52)]), ink)
    out += path(spline([(30, 14, 0), (28, 26), (32, 30), (34, 24)]), ink)
    out += stroke(spline([(50, 60), (46, 74), (52, 86)], closed=False), ink, 2.4)
    for (a, b, w, bd) in [((76, 76), (84, 62), 2.4, 2), ((84, 56), (86, 42), 2.4, 2), ((82, 34), (72, 22), 2.4, -2),
                          ((66, 18), (54, 16), 2.0, -1)]:
        out += path(gouge(a, b, w, bd), ink)
    return out


def icon_svg(pal, mono=False) -> str:
    out = ""
    bg = pal["ink"] if mono else pal["rust"]
    out += f'<rect x="2" y="2" width="96" height="96" rx="24" fill="{pal["ink"]}"/>\n'
    out += f'<rect x="6" y="6" width="88" height="88" rx="21" fill="{bg}"/>\n'
    if mono:
        out += f'<rect x="8.5" y="8.5" width="83" height="83" rx="19" fill="none" stroke="{pal["paper"]}" stroke-width="1.6"/>\n'
    out += f'<g transform="translate(5 7) scale(0.84)">\n{squirrel_mark(pal, "paper", edge=2.4)}</g>\n'
    return svg(100, 100, out, "tosk icon")


# ----------------------------------------------------------------- logo
def wordmark(pal, x, y, h=100) -> str:
    """'tosk' lowercase, carved: bold strokes with cream nicks."""
    ink = pal["ink"]
    s = h / 100
    out = ""

    def T(px, py):
        return (x + px * s, y + py * s)

    def L(points, w=16):
        return stroke(polyline([T(*p) for p in points]), ink, w * s, cap="butt", join="miter")

    # t
    out += stroke(f"M {f(T(10, 16)[0])} {f(T(10, 16)[1])} L {f(T(10, 80)[0])} {f(T(10, 80)[1])} "
                  f"Q {f(T(10, 98)[0])} {f(T(10, 98)[1])} {f(T(30, 94)[0])} {f(T(30, 94)[1])}", ink, 16 * s, cap="butt")
    out += L([(-6, 44), (30, 44)])
    # o
    out += path(spline([T(72, 40), T(94, 50), T(94, 80), T(72, 98), T(50, 86), T(48, 56)]), ink)
    out += path(spline([T(72, 56), T(80, 62), T(78, 80), T(70, 84), T(62, 78), T(62, 62)]), pal["paper"])
    # s
    sd = (f"M {f(T(146, 54)[0])} {f(T(146, 54)[1])} C {f(T(142, 38)[0])} {f(T(142, 38)[1])} {f(T(112, 36)[0])} {f(T(112, 36)[1])} {f(T(112, 56)[0])} {f(T(112, 56)[1])} "
          f"C {f(T(112, 70)[0])} {f(T(112, 70)[1])} {f(T(148, 68)[0])} {f(T(148, 68)[1])} {f(T(148, 84)[0])} {f(T(148, 84)[1])} "
          f"C {f(T(148, 100)[0])} {f(T(148, 100)[1])} {f(T(116, 102)[0])} {f(T(116, 102)[1])} {f(T(110, 86)[0])} {f(T(110, 86)[1])}")
    out += stroke(sd, ink, 15 * s, cap="butt")
    # k
    out += L([(174, 12), (174, 98)])
    out += L([(206, 44), (176, 72), (208, 98)])
    # carved nicks
    for (a, b) in [((8, 28), (12, 36)), ((68, 44), (76, 44)), ((114, 46), (118, 52)), ((172, 26), (176, 36)),
                   ((16, 90), (26, 94)), ((190, 86), (196, 92))]:
        out += path(gouge(T(*a), T(*b), 1.6 * s), pal["paper"])
    return out


def logo_svg(pal) -> str:
    out = ""
    out += f'<g transform="translate(4 8) scale(1.1)">\n{squirrel_mark(pal, "rust", edge=2.4)}</g>\n'
    out += wordmark(pal, 140, 10, h=100)
    for i, r in enumerate(["t", "o", "s", "k"]):
        out += rune(r, 170 + i * 24, 122, 13, pal["ink"], w=2.4)
    return svg(380, 136, out, "tosk logo")


# ----------------------------------------------------------------- Yggdrasil
def node(pal, x, y, r, rn=None) -> str:
    """Skill node: a carved medallion with a notched (rope) rim and a rune."""
    out = f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{pal["ink"]}"/>\n'
    out += f'<circle cx="{f(x - r * 0.05)}" cy="{f(y - r * 0.05)}" r="{f(r * 0.76)}" fill="{pal["paper"]}"/>\n'
    out += f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r * 0.66)}" fill="none" stroke="{pal["ink"]}" stroke-width="{f(r * 0.06)}"/>\n'
    for i in range(14):
        a = i / 14 * 2 * math.pi
        rr = r * 0.9
        c, s = math.cos(a), math.sin(a)
        p0 = (x + c * rr - s * r * 0.08, y + s * rr + c * r * 0.08)
        p1 = (x + c * rr * 1.0 + s * r * 0.12, y + s * rr * 1.0 - c * r * 0.12)
        out += path(gouge(p0, p1, r * 0.05), pal["paper"])
    if rn:
        out += rune(rn, x, y, r * 0.78, pal["ink"])
    return out


def eagle(pal, cx, cy, s=1.0) -> str:
    """Heraldic eagle in the crown, wings raised, looking right."""
    pts = [
        (0, -66, 0.6), (18, -64), (38, -52, 0), (24, -46), (20, -34), (30, -36),          # head, hooked beak
        (64, -62), (104, -96), (146, -128, 0),                                            # leading edge up
        (134, -100), (152, -98, 0), (126, -74), (146, -68, 0), (114, -48), (130, -38, 0), # primaries
        (96, -22), (106, -10, 0), (72, -2), (50, 12), (44, 40), (48, 60, 0), (36, 54), (30, 68, 0), (16, 60),
        (10, 74, 0), (0, 64), (-10, 74, 0), (-16, 60), (-30, 68, 0), (-36, 54), (-48, 60, 0), (-44, 40),
        (-50, 12), (-72, -2), (-106, -10, 0), (-96, -22), (-130, -38, 0), (-114, -48), (-146, -68, 0),
        (-126, -74), (-152, -98, 0), (-134, -100), (-146, -128, 0), (-104, -96), (-64, -62), (-30, -36),
        (-20, -34), (-22, -52),
    ]
    tr = [(cx + x * s, cy + y * s) + tuple(k) for (x, y, *k) in pts]
    out = path(spline(tr), pal["ink"])
    cuts = [((-120, -96), (-70, -62)), ((-116, -74), (-66, -46)), ((-104, -50), (-62, -32)), ((-86, -24), (-56, -14)),
            ((120, -96), (70, -62)), ((116, -74), (66, -46)), ((104, -50), (62, -32)), ((86, -24), (56, -14)),
            ((-8, -8), (-6, 34)), ((8, -8), (6, 34)), ((-22, 44), (-18, 58)), ((22, 44), (18, 58)), ((0, 46), (0, 60))]
    for (a, b) in cuts:
        out += path(gouge((cx + a[0] * s, cy + a[1] * s), (cx + b[0] * s, cy + b[1] * s), 2.6 * s, 1.5), pal["paper"])
    out += path(spline([(cx + 6 * s, cy - 56 * s), (cx + 16 * s, cy - 58 * s), (cx + 16 * s, cy - 50 * s), (cx + 7 * s, cy - 50 * s)]), pal["paper"])
    return out


def dragon(pal, rnd) -> str:
    """Nidhoggr: an Urnes-style ribbon beast coiled in front of the roots."""
    out = ""
    sc = [(750, 1000), (700, 1046), (630, 1078), (560, 1066), (505, 1030), (450, 1008), (395, 1022), (345, 1052),
          (290, 1064), (230, 1046), (170, 1024), (116, 1008)]
    sw = [6, 16, 24, 28, 30, 30, 30, 30, 30, 30, 28, 26]
    body = ribbon(sc, sw, tip="round", root="sharp")
    out += stroke(spline(body), pal["paper"], 10)
    out += path(spline(body), pal["ink"])
    out += gouges_along(sc, sw, rnd, 40, pal["paper"], length=(5, 11), thick=(1.6, 3.0), spread=0.6, skew=1.3)
    # a long spine ridge of small cuts
    out += gouges_along(sc, [w * 0.2 for w in sw], rnd, 16, pal["paper"], length=(8, 16), thick=(1.0, 1.8), spread=0.5)
    # the head: long jaws open, biting at the root tip
    head = [(124, 1000), (100, 984), (72, 982), (42, 988, 0), (60, 1000), (80, 1004), (46, 1022, 0),
            (78, 1024), (108, 1028), (128, 1022)]
    out += stroke(spline(head), pal["paper"], 10)
    out += path(spline(head), pal["ink"])
    out += path(spline([(98, 994), (110, 992), (110, 1001), (98, 1001)]), pal["paper"])  # eye
    for (a, b) in [((60, 994), (64, 1002)), ((72, 996), (76, 1004))]:
        out += path(gouge(a, b, 1.6), pal["paper"])  # teeth
    # Urnes lappet curling back from the head
    out += stroke(spline([(116, 990), (104, 970), (122, 958), (140, 972)], closed=False), pal["ink"], 5)
    # tail tip curl
    out += stroke(spline([(750, 1000), (760, 984), (748, 972), (734, 982)], closed=False), pal["ink"], 4)
    return out


def spiral(cx, cy, r0, turns, w0, w1, pal, flip=1) -> str:
    """A Norse wind curl: a tapering spiral ribbon."""
    pts, ws = [], []
    n = int(turns * 12)
    for i in range(n + 1):
        t = i / n
        a = flip * t * turns * 2 * math.pi
        r = r0 * (1 - t * 0.9)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        ws.append(w0 + (w1 - w0) * t)
    return path(spline(ribbon(pts, ws, tip="sharp")), pal["ink"])


def yggdrasil_figure(pal) -> str:
    rnd = Rnd(42)
    out = ""

    # soil: carved horizon ticks
    for i in range(15):
        xx = 30 + i * 52
        out += path(gouge((xx, 1086 + (i % 3) * 4), (xx + 34, 1090 + (i % 3) * 4), 1.6), pal["ink"])

    # wind curls in the sky (Norse spirals) framing the crown
    out += spiral(140, 120, 50, 1.6, 8, 1.5, pal, flip=1)
    out += spiral(660, 120, 50, 1.6, 8, 1.5, pal, flip=-1)
    out += stroke(spline([(140, 170), (100, 182), (60, 166)], closed=False), pal["ink"], 4)
    out += stroke(spline([(660, 170), (700, 182), (740, 166)], closed=False), pal["ink"], 4)
    out += stroke(spline([(92, 100), (66, 92), (44, 104)], closed=False), pal["ink"], 3)
    out += stroke(spline([(708, 100), (734, 92), (756, 104)], closed=False), pal["ink"], 3)

    # --- boughs first so their roots hide under the trunk
    boughs = [
        ([(400, 880), (340, 866), (296, 852), (250, 824), (206, 782), (176, 742)], [60, 48, 40, 30, 22, 14], (166, 722), "f"),
        ([(400, 790), (460, 772), (520, 752), (574, 724), (616, 680), (646, 632)], [60, 48, 40, 30, 22, 14], (656, 612), "u"),
        ([(400, 670), (344, 650), (296, 630), (246, 598), (206, 556), (180, 514)], [54, 44, 36, 28, 20, 13], (170, 494), "th"),
        ([(400, 566), (456, 552), (512, 536), (564, 506), (604, 464), (632, 420)], [54, 44, 36, 28, 20, 13], (640, 400), "a"),
        ([(400, 456), (356, 438), (316, 418), (272, 386), (240, 344), (218, 302)], [48, 38, 32, 24, 18, 12], (208, 282), "r"),
        ([(400, 372), (448, 352), (498, 330), (540, 300), (568, 256), (584, 208)], [46, 36, 30, 22, 16, 12], (590, 188), "k"),
    ]
    twigs = [
        ([(290, 848), (262, 820), (250, 790)], [16, 10, 5]), ([(236, 810), (236, 780), (248, 756)], [12, 8, 4]),
        ([(530, 746), (546, 714), (540, 688)], [16, 10, 5]), ([(600, 700), (614, 672), (608, 650)], [12, 8, 4]),
        ([(292, 624), (264, 600), (254, 572)], [16, 10, 5]), ([(500, 532), (500, 500), (486, 478)], [16, 10, 5]),
        ([(300, 412), (282, 386), (286, 358)], [14, 9, 4]), ([(520, 322), (530, 292), (548, 272)], [14, 9, 4]),
        ([(384, 300), (350, 270), (326, 232)], [22, 12, 5]), ([(418, 300), (454, 268), (476, 232)], [22, 12, 5]),
    ]
    for (bc, bw, _, _) in boughs:
        out += carved_ribbon(bc, bw, pal, "umber", shrink=0.7, dy=3, edge=3, tip="sharp", trim=6)
        out += gouges_along(bc, bw, rnd, 14, pal["ink"], length=(16, 48), thick=(1.4, 2.8), spread=0.7)
    for (tcn, twn) in twigs:
        out += carved_ribbon(tcn, twn, pal, "umber", shrink=0.6, dy=2, edge=2.4, tip="sharp", trim=3)

    # --- trunk: a hand-drawn outline with a flared, rooty base
    left = [(276, 980, 0), (300, 920), (316, 850), (324, 760), (336, 670), (346, 580), (350, 490), (354, 400),
            (362, 320), (376, 260), (386, 236)]
    right = [(418, 236), (426, 260), (436, 320), (446, 400), (456, 490), (462, 580), (466, 670), (468, 760),
             (478, 850), (498, 920), (526, 980, 0)]
    trunk = left + right
    d = spline(trunk)
    out += path(d, pal["ink"])
    inner = [(p[0] + (8 if i < len(left) else -22), p[1]) for i, p in enumerate(trunk)]
    inner[0] = (inner[0][0], inner[0][1] - 3)
    inner[-1] = (inner[-1][0], inner[-1][1] - 3)
    out += path(spline(inner), pal["umber"])
    out += stroke(d, pal["ink"], 3.5)
    tc = [(400, 980), (400, 880), (400, 760), (400, 640), (404, 520), (408, 400), (402, 300), (400, 240)]
    tw = [200, 170, 140, 130, 116, 100, 80, 40]
    out += gouges_along(tc, tw, rnd, 60, pal["ink"], length=(40, 130), thick=(1.6, 3.8), spread=0.8, bend=4)
    out += gouges_along(tc, tw, rnd, 30, pal["ink"], length=(20, 70), thick=(1.4, 2.6), spread=0.9, bend=2,
                        side=+1)
    # the hollow with Tiwaz carved in the bark
    out += path(spline([(378, 700), (404, 676), (432, 690), (438, 742), (410, 772), (380, 752)]), pal["ink"])
    out += path(spline([(388, 706), (404, 690), (424, 700), (428, 738), (408, 758), (390, 744)]), pal["paper"])
    out += rune("t", 408, 724, 38, pal["ink"], w=5)

    # --- the three roots, then Nidhoggr coiled in front of them
    roots = [
        ([(400, 962), (330, 982), (250, 1000), (176, 1030), (110, 1072)], [180, 96, 58, 32, 8]),
        ([(380, 968), (320, 1012), (268, 1050), (232, 1092)], [70, 36, 20, 6]),
        ([(400, 966), (412, 1010), (398, 1050), (410, 1094)], [120, 54, 28, 8]),
        ([(420, 968), (482, 1012), (530, 1050), (560, 1092)], [70, 36, 20, 6]),
        ([(400, 962), (470, 982), (550, 1000), (624, 1030), (690, 1072)], [180, 96, 58, 32, 8]),
    ]
    for (rc, rw) in roots:
        out += carved_ribbon(rc, rw, pal, "umber", shrink=0.72, dx=4, dy=2, edge=3, tip="sharp", trim=5)
        out += gouges_along(rc, rw, rnd, 16, pal["ink"], length=(14, 50), thick=(1.4, 2.8), spread=0.8)
    out += dragon(pal, rnd)
    # the well of Urdr at the foot of the trunk
    well = [(112, 1058), (156, 1050), (198, 1058), (190, 1084), (152, 1092), (114, 1082), (100, 1070)]
    out += stroke(spline(well), pal["paper"], 8)
    out += path(spline(well), pal["ink"])
    out += path(spline([(122, 1062), (156, 1056), (188, 1063), (182, 1078), (152, 1084), (124, 1076), (114, 1068)]), pal["paper"])
    for (a, b) in [((126, 1066), (156, 1062)), ((142, 1074), (180, 1069)), ((126, 1077), (148, 1078))]:
        out += path(gouge(a, b, 1.6, 1.5), pal["ink"])

    # --- leaves on the twigs and boughs (bigger clusters near the nodes)
    leaves = [
        (250, 790, -112, 1.3), (248, 756, -80, 1.2), (540, 688, -62, 1.3), (608, 650, -82, 1.2),
        (254, 572, -118, 1.3), (486, 478, -68, 1.3), (286, 358, -104, 1.2), (548, 272, -52, 1.2),
        (326, 232, -126, 1.25), (476, 232, -54, 1.25), (228, 806, -150, 1.0), (598, 702, -24, 1.0),
        (226, 582, -152, 1.0), (590, 488, -28, 1.0), (254, 368, -150, 1.0), (556, 278, -30, 1.0),
    ]
    for (lx, ly, la, ls) in leaves:
        out += ash_leaf(pal, lx, ly, la, ls)

    # --- eagle in the crown
    out += eagle(pal, 400, 144, 1.0)

    # --- skill nodes
    for (_, _, (nx, ny), rn) in boughs:
        out += node(pal, nx, ny, 36, rn)
    out += node(pal, 400, 226, 40, "g")

    # --- Tosk sitting on a bough by the trunk
    out += (f'<g transform="translate(258 536) scale(0.95)">\n'
            f'{squirrel_mark(pal, "rust", edge=2.4, halo=7)}</g>\n')
    return out


def yggdrasil_svg(pal) -> str:
    return svg(800, 1100, yggdrasil_figure(pal), "Yggdrasil course tree")


# ----------------------------------------------------------------- branch tile
def branch_tile_figure(pal) -> str:
    rnd = Rnd(9)
    out = ""
    main = ([(150, 262), (152, 214), (148, 172), (116, 134), (80, 98), (58, 64)], [38, 34, 32, 24, 18, 10])
    right = ([(150, 180), (184, 140), (222, 102), (242, 64)], [30, 24, 18, 10])
    out += carved_ribbon(*right, pal, "umber", shrink=0.7, dy=3, edge=3, tip="sharp", trim=4)
    out += gouges_along(*right, rnd, 10, pal["ink"], length=(12, 36), thick=(1.4, 2.6), spread=0.7)
    out += carved_ribbon(*main, pal, "umber", shrink=0.7, dy=3, edge=3, tip="sharp", trim=4)
    out += gouges_along(*main, rnd, 18, pal["ink"], length=(12, 40), thick=(1.4, 2.6), spread=0.7)
    out += ash_leaf(pal, 104, 122, -140, 1.15)
    out += ash_leaf(pal, 196, 126, -40, 1.15)
    out += ash_leaf(pal, 150, 214, 162, 0.9)
    out += node(pal, 150, 262, 30)
    out += node(pal, 56, 50, 30)
    out += node(pal, 244, 50, 30)
    return out


def branch_tile_svg(pal) -> str:
    return svg(300, 300, branch_tile_figure(pal), "Branch tile")


# ----------------------------------------------------------------- svg + sheet
def svg(w, h, body, title) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n'
            f"<title>{title}</title>\n{body}</svg>\n")


SHEET = """<!doctype html>
<html><head><meta charset="utf-8"><title>tosk: woodcut</title>
<style>
 body{margin:0;background:#E9DFC8;font-family:Georgia,serif;color:#1C1814;padding:28px 32px}
 h1{font-size:40px;margin:0 0 4px;letter-spacing:-1px}
 p.sub{margin:0 0 20px;font-size:15px;color:#4a3f33}
 .row{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;margin-bottom:18px}
 .col{display:flex;flex-direction:column;gap:18px}
 .card{background:#F3EAD6;border:3px solid #1C1814;border-radius:10px;padding:12px;text-align:center;box-shadow:4px 4px 0 #1C1814}
 .card.mono{background:#fff}
 .card .cap{font-size:13px;margin-top:8px}
 .icons{display:flex;gap:16px;align-items:flex-end;justify-content:center}
 .icons img{display:block}
 .pal{display:flex;gap:10px}
 .sw{width:66px;height:66px;border:3px solid #1C1814;border-radius:8px;display:flex;align-items:flex-end;justify-content:center;font-size:11px;padding-bottom:4px;box-sizing:border-box;box-shadow:3px 3px 0 #1C1814}
 .sw span{background:#F3EAD6;border-radius:3px;padding:1px 4px}
</style></head><body>
<h1>tosk</h1>
<p class="sub">Norse woodcut / linocut exploration. A black key block over a flat colour block; the key block alone is the e-ink version.</p>
<div class="row">
 <div class="card"><img src="tosk.svg" width="330" height="330"><div class="cap">Tosk</div></div>
 <div class="card mono"><img src="tosk-mono.svg" width="330" height="330"><div class="cap">Tosk (e-ink)</div></div>
 <div class="col">
  <div class="card"><div class="icons"><img src="icon.svg" width="48" height="48"><img src="icon.svg" width="96" height="96"><img src="icon-mono.svg" width="48" height="48"><img src="icon-mono.svg" width="96" height="96"><img src="icon.svg" width="180" height="180"></div><div class="cap">Icon at 48 / 96 px (colour, e-ink) and large</div></div>
  <div class="card"><img src="logo.svg" width="380" height="136"><div class="cap">Logo</div></div>
 </div>
</div>
<div class="row">
 <div class="card"><img src="yggdrasil.svg" width="380" height="522"><div class="cap">Yggdrasil: the course tree</div></div>
 <div class="card mono"><img src="yggdrasil-mono.svg" width="380" height="522"><div class="cap">Yggdrasil (e-ink)</div></div>
 <div class="col">
  <div class="row"><div class="card"><img src="branch-tile.svg" width="196" height="196"><div class="cap">Branch tile</div></div>
  <div class="card mono"><img src="branch-tile-mono.svg" width="196" height="196"><div class="cap">Branch tile (e-ink)</div></div></div>
  <div class="card"><div class="pal">
   <div class="sw" style="background:#1C1814"><span>#1C1814</span></div>
   <div class="sw" style="background:#F3EAD6"><span>#F3EAD6</span></div>
   <div class="sw" style="background:#B8452A"><span>#B8452A</span></div>
   <div class="sw" style="background:#5C7A3B"><span>#5C7A3B</span></div>
   <div class="sw" style="background:#5E3F2B"><span>#5E3F2B</span></div>
   <div class="sw" style="background:#D8A23B"><span>#D8A23B</span></div>
  </div><div class="cap">Palette: ink, birch cream, rust, moss, umber, ochre</div></div>
 </div>
</div>
</body></html>
"""


def main():
    files = {
        "tosk.svg": tosk_svg(COLOUR), "tosk-mono.svg": tosk_svg(MONO),
        "icon.svg": icon_svg(COLOUR), "icon-mono.svg": icon_svg(MONO, mono=True),
        "logo.svg": logo_svg(COLOUR),
        "yggdrasil.svg": yggdrasil_svg(COLOUR), "yggdrasil-mono.svg": yggdrasil_svg(MONO),
        "branch-tile.svg": branch_tile_svg(COLOUR), "branch-tile-mono.svg": branch_tile_svg(MONO),
        "sheet.html": SHEET,
    }
    for name, content in files.items():
        (HERE / name).write_text(content, encoding="utf-8")
        print(f"{name}: {len(content) // 1024} KB")


if __name__ == "__main__":
    main()
