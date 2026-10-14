"""tosk brand exploration: "storybook ink" style.

Expressive pen lines (filled, tapered strokes whose weight follows the light),
procedural hatching / cross-hatching for shading, warm muted watercolour fills.
Everything is drawn once from Bezier silhouettes and rendered twice: colour and
pure black/white (e-ink).  Pure Python, no dependencies.

Run:  python make_storybook.py      -> *.svg + sheet.html in this folder
"""
from __future__ import annotations

import math
import random
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- palettes
COLOR = dict(
    ink="#3B2A1F",        # warm sepia ink
    paper="#F7F0E2",      # parchment
    fur="#C96A3B",        # russet
    fur_dk="#9C4C27",     # russet shadow
    fur_lt="#E8A872",     # sunlit fur
    cream="#F4E5C8",      # belly, muzzle, paper of scroll
    bark="#8E6C4E",
    bark_dk="#5B4333",
    leaf="#7E9B5F",
    leaf_dk="#55733F",
    gold="#D8B15C",
    water="#A9BFC0",
    hatch="#3B2A1F",
    hatch_op="0.62",
    mono=False,
)
MONO = dict(
    ink="#000000", paper="#FFFFFF", fur="#FFFFFF", fur_dk="#FFFFFF", fur_lt="#FFFFFF",
    cream="#FFFFFF", bark="#FFFFFF", bark_dk="#FFFFFF", leaf="#FFFFFF", leaf_dk="#FFFFFF",
    gold="#FFFFFF", water="#FFFFFF", hatch="#000000", hatch_op="1", mono=True,
)

LIGHT = (0.45, -0.89)  # light comes from the top right
STEP = [1.0]  # global sampling-step multiplier (coarser = smaller files)


# ----------------------------------------------------------------- geometry
def _bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1])


_NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def parse(d: str) -> list[tuple[list[tuple[float, float]], bool]]:
    """Absolute M/L/C/Q/Z path -> list of (polyline, closed)."""
    tokens = re.findall(r"[MLCQZ]|" + _NUM.pattern, d)
    subs, cur, closed = [], [], False
    i = 0
    cmd = None
    while i < len(tokens):
        t = tokens[i]
        if t in "MLCQZ":
            cmd = t
            i += 1
            if cmd == "Z":
                if cur:
                    subs.append((cur, True))
                cur, closed = [], False
            continue
        if cmd == "M":
            if cur:
                subs.append((cur, False))
            cur = [(float(tokens[i]), float(tokens[i + 1]))]
            i += 2
            cmd = "L"
        elif cmd == "L":
            cur.append((float(tokens[i]), float(tokens[i + 1])))
            i += 2
        elif cmd == "C":
            p0 = cur[-1]
            p1 = (float(tokens[i]), float(tokens[i + 1]))
            p2 = (float(tokens[i + 2]), float(tokens[i + 3]))
            p3 = (float(tokens[i + 4]), float(tokens[i + 5]))
            i += 6
            n = max(10, int(math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)) // 3)
            for k in range(1, n + 1):
                cur.append(_bez(p0, p1, p2, p3, k / n))
        elif cmd == "Q":
            p0 = cur[-1]
            c = (float(tokens[i]), float(tokens[i + 1]))
            p3 = (float(tokens[i + 2]), float(tokens[i + 3]))
            i += 4
            p1 = (p0[0] + 2 / 3 * (c[0] - p0[0]), p0[1] + 2 / 3 * (c[1] - p0[1]))
            p2 = (p3[0] + 2 / 3 * (c[0] - p3[0]), p3[1] + 2 / 3 * (c[1] - p3[1]))
            n = max(10, int(math.dist(p0, c) + math.dist(c, p3)) // 3)
            for k in range(1, n + 1):
                cur.append(_bez(p0, p1, p2, p3, k / n))
        else:
            raise ValueError(d)
    if cur:
        subs.append((cur, False))
    return subs


def poly(d: str):
    return parse(d)[0][0]


def resample(pts, step: float, closed: bool):
    if closed:
        pts = list(pts) + [pts[0]]
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        if seg == 0:
            continue
        pos = step - carry
        while pos <= seg:
            t = pos / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            pos += step
        carry = seg - (pos - step)
    if closed:
        if math.dist(out[-1], out[0]) < step * 0.5:
            out.pop()
    else:
        if math.dist(out[-1], pts[-1]) > 1e-6:
            out.append(pts[-1])
    return out


def area(pts):
    s = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        s += x1 * y2 - x2 * y1
    return s / 2


def inside(pt, pts):
    x, y = pt
    c = False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                c = not c
    return c


def fmt(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def pts_d(pts, closed=True) -> str:
    d = "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)
    return d + ("Z" if closed else "")


class Noise:
    """Smooth 1-D noise: a sum of sines with random phases."""

    def __init__(self, seed: int, scale: float = 40.0):
        r = random.Random(seed)
        self.ph = [r.random() * math.tau for _ in range(4)]
        self.f = [1 / scale * (1 + k * 0.7) for k in range(4)]

    def __call__(self, s: float) -> float:
        return sum(math.sin(s * f * math.tau + p) / (k + 1) for k, (f, p) in enumerate(zip(self.f, self.ph))) / 1.6


# ----------------------------------------------------------------- ink
def _normals(pts, closed, smooth=2):
    n = len(pts)
    sgn = 1 if (area(pts) > 0 or not closed) else -1
    nrm = []
    for i in range(n):
        if closed:
            a, b = pts[(i - smooth) % n], pts[(i + smooth) % n]
        else:
            a, b = pts[max(i - smooth, 0)], pts[min(i + smooth, n - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tx, ty) or 1.0
        nrm.append((sgn * ty / l, -sgn * tx / l))
    return nrm


def _band(pts, closed, widths, nrm):
    L, R = [], []
    for p, n, w in zip(pts, nrm, widths):
        h = w / 2
        L.append((p[0] + n[0] * h, p[1] + n[1] * h))
        R.append((p[0] - n[0] * h, p[1] - n[1] * h))
    if closed:
        return pts_d(L, True) + pts_d(R[::-1], True)
    return pts_d(L + R[::-1], True)


def ink_shape(d: str, p: dict, wmin=1.2, wmax=4.6, light=LIGHT, step=2.0, wobble=0.5, seed=1,
              smooth=4) -> str:
    """Outline a closed silhouette: heavy on the shadow side, light where lit."""
    out = []
    step *= STEP[0]
    for sub, closed in parse(d):
        pts = resample(sub, step, closed)
        nz = Noise(seed, 60)
        nz2 = Noise(seed + 7, 25)
        nrm = _normals(pts, closed, smooth)
        if wobble:
            pts = [(x + n[0] * nz(i * step) * wobble, y + n[1] * nz(i * step) * wobble)
                   for i, ((x, y), n) in enumerate(zip(pts, nrm))]
        widths = []
        for i, n in enumerate(nrm):
            shade = max(0.0, -(n[0] * light[0] + n[1] * light[1]))
            w = wmin + (wmax - wmin) * shade ** 0.8
            w *= 1 + 0.18 * nz2(i * step)
            widths.append(max(w, wmin * 0.6))
        out.append(f'<path d="{_band(pts, closed, widths, nrm)}" fill="{p["ink"]}"/>')
    return "\n".join(out)


def ink_line(d: str, p: dict, w=3.0, profile="taper", step=2.0, seed=3, wobble=0.35, color=None) -> str:
    """An open pen stroke.  profile: 'taper' (both ends), 'in' (fat start), 'out' (fat end), 'flat'."""
    out = []
    step *= STEP[0]
    for sub, closed in parse(d):
        pts = resample(sub, step, False)
        n = len(pts)
        nrm = _normals(pts, False, 2)
        nz = Noise(seed, 30)
        if wobble:
            pts = [(x + nn[0] * nz(i * step) * wobble, y + nn[1] * nz(i * step) * wobble)
                   for i, ((x, y), nn) in enumerate(zip(pts, nrm))]
        widths = []
        for i in range(n):
            s = i / max(n - 1, 1)
            if profile == "taper":
                k = math.sin(math.pi * s) ** 0.6
            elif profile == "in":
                k = (1 - s) ** 0.7
            elif profile == "out":
                k = s ** 0.7
            else:
                k = 1.0
            widths.append(max(0.3, w * k))
        out.append(f'<path d="{_band(pts, False, widths, nrm)}" fill="{color or p["ink"]}"/>')
    return "\n".join(out)


class _Clumps:
    """Irregular fur clumps along an edge: each clump has its own length and height."""

    def __init__(self, seed, period):
        self.r = random.Random(seed)
        self.period = period
        self.edges = [0.0]
        self.amps = [self.r.uniform(0.3, 1.0)]

    def __call__(self, s):
        while s >= self.edges[-1]:
            self.edges.append(self.edges[-1] + self.period * self.r.uniform(0.5, 1.6))
            self.amps.append(self.r.uniform(0.3, 1.0))
        i = 0
        while self.edges[i + 1] <= s:
            i += 1
        q = (s - self.edges[i]) / (self.edges[i + 1] - self.edges[i])
        # a soft clump: rises slowly, rounds over, drops in the last fifth
        if q < 0.8:
            v = math.sin(q / 0.8 * math.pi / 2) ** 1.4
        else:
            v = math.cos((q - 0.8) / 0.2 * math.pi / 2) ** 0.8
        return v * self.amps[i], q


def tapered_shape(d: str, profile, step=2.0, seed=5, fur=0.0, fur_period=14.0, back=0.9, peaks=None):
    """Filled silhouette along a centerline.  profile(s)->full width.
    fur>0 adds swept fur clumps (as a fraction of half-width) to both edges.
    peaks (a list) receives (point, outward normal, tangent, s) at every clump tip."""
    step *= STEP[0]
    pts = resample(poly(d), step, False)
    nrm = _normals(pts, False, 2)
    n = len(pts)
    L, R = [], []
    cl_l, cl_r = _Clumps(seed, fur_period), _Clumps(seed + 1, fur_period * 1.15)
    s_acc = 0.0
    prev_q = [0.0, 0.0]
    for i, (pt, nn) in enumerate(zip(pts, nrm)):
        s = i / max(n - 1, 1)
        h = profile(s) / 2
        tx, ty = -nn[1], nn[0]
        if fur:
            scale = 0.5 + 0.5 * min(1, h / 40)
            vl, ql = cl_l(s_acc * scale)
            vr, qr = cl_r(s_acc * scale)
            hl = h * (1 + fur * vl)
            hr = h * (1 + fur * vr)
            back_l = h * fur * back * vl
            back_r = h * fur * back * vr
        else:
            hl = hr = h
            back_l = back_r = 0
        L.append((pt[0] + nn[0] * hl - tx * back_l, pt[1] + nn[1] * hl - ty * back_l))
        R.append((pt[0] - nn[0] * hr - tx * back_r, pt[1] - nn[1] * hr - ty * back_r))
        if fur and peaks is not None:
            for side, q, pq, ring in ((1, ql, prev_q[0], L), (-1, qr, prev_q[1], R)):
                if pq < 0.8 <= q:
                    peaks.append((ring[-1], (nn[0] * side, nn[1] * side), (tx, ty), s))
            prev_q = [ql, qr]
        s_acc += step
    return L + R[::-1]


_CLIP = [0]


def clipped(d: str, clip_d: str, color: str, op: float | None = None) -> str:
    """Fill d, clipped to clip_d (for shadow washes that must stay inside a form)."""
    _CLIP[0] += 1
    cid = f"c{_CLIP[0]}"
    o = f' fill-opacity="{op}"' if op is not None else ""
    return (f'<clipPath id="{cid}"><path d="{clip_d}"/></clipPath>'
            f'<path d="{d}" fill="{color}"{o} clip-path="url(#{cid})"/>')


def hatch(polys, angle_deg, spacing, p: dict, width=1.3, seed=11, jitter=0.5, shrink=1.5,
          color=None, op=None, curve=0.0) -> str:
    """Parallel pen hatching clipped to the intersection of the given polygons."""
    polys = [poly(q) if isinstance(q, str) else q for q in polys]
    a = math.radians(angle_deg)
    u = (math.cos(a), math.sin(a))
    v = (-math.sin(a), math.cos(a))
    base = polys[0]
    ks = [x * v[0] + y * v[1] for x, y in base]
    kmin, kmax = min(ks), max(ks)
    rnd = random.Random(seed)
    segs = []
    k = kmin + spacing * rnd.random()
    while k < kmax:
        intervals = None
        for pl in polys:
            ts = []
            m = len(pl)
            for i in range(m):
                ax, ay = pl[i]
                bx, by = pl[(i + 1) % m]
                pa = ax * v[0] + ay * v[1] - k
                pb = bx * v[0] + by * v[1] - k
                if (pa > 0) != (pb > 0):
                    s = pa / (pa - pb)
                    x, y = ax + (bx - ax) * s, ay + (by - ay) * s
                    ts.append(x * u[0] + y * u[1])
            ts.sort()
            iv = [(ts[i], ts[i + 1]) for i in range(0, len(ts) - 1, 2)]
            if intervals is None:
                intervals = iv
            else:
                merged = []
                for a0, a1 in intervals:
                    for b0, b1 in iv:
                        lo, hi = max(a0, b0), min(a1, b1)
                        if hi > lo:
                            merged.append((lo, hi))
                intervals = merged
        for t0, t1 in intervals or []:
            t0 += shrink + rnd.random() * jitter * 2
            t1 -= shrink + rnd.random() * jitter * 2
            if t1 - t0 < 2:
                continue
            kk = k + (rnd.random() - 0.5) * jitter
            x0, y0 = u[0] * t0 + v[0] * kk, u[1] * t0 + v[1] * kk
            x1, y1 = u[0] * t1 + v[0] * kk, u[1] * t1 + v[1] * kk
            if curve:
                mx, my = (x0 + x1) / 2 + v[0] * curve, (y0 + y1) / 2 + v[1] * curve
                segs.append(f"M{fmt(x0)} {fmt(y0)}Q{fmt(mx)} {fmt(my)} {fmt(x1)} {fmt(y1)}")
            else:
                segs.append(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}")
        k += spacing * (0.85 + 0.3 * rnd.random())
    if not segs:
        return ""
    return (f'<path d="{"".join(segs)}" fill="none" stroke="{color or p["hatch"]}" '
            f'stroke-opacity="{op or p["hatch_op"]}" stroke-width="{width}" stroke-linecap="round"/>')


def fill(d: str, color: str, op: float | None = None) -> str:
    o = f' fill-opacity="{op}"' if op is not None else ""
    return f'<path d="{d}" fill="{color}"{o}/>'


def svg(w, h, body: str, title: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n'
            f"<title>{title}</title>\n{body}\n</svg>\n")


# ----------------------------------------------------------------- shared motifs
def ash_leaf(p: dict, x, y, angle, scale=1.0, seed=2, shade=True, simple=False) -> str:
    """Pinnate ash leaf: a stem with leaflet pairs and a terminal leaflet.
    simple=True draws cheap stroked leaflets for small, far-away foliage."""
    out = []
    rnd = random.Random(seed)
    stem = "M0 0C30 -4 60 -2 92 0"
    out.append(ink_line(stem, p, 2.2, "in", seed=seed))
    if simple:
        lf = "M0 0C8 -7 24 -8 36 0C24 8 8 7 0 0Z"
        for i, t in enumerate((22, 46, 70)):
            for side in (-1, 1):
                ang = side * (-52 + rnd.random() * 10)
                out.append(f'<g transform="translate({t} 0) rotate({fmt(ang)})"><path d="{lf}" fill="{p["leaf"]}" '
                           f'stroke="{p["ink"]}" stroke-width="1.7"/><path d="M3 0L26 0" stroke="{p["ink"]}" stroke-width="1"/></g>')
        out.append(f'<g transform="translate(92 0) rotate(-2)"><path d="{lf}" fill="{p["leaf"]}" '
                   f'stroke="{p["ink"]}" stroke-width="1.7"/><path d="M3 0L26 0" stroke="{p["ink"]}" stroke-width="1"/></g>')
        if shade:
            out.append(f'<path d="M30 2L34 7M36 2L40 7M42 1L45 5M78 2L82 7M84 2L88 7M100 2L104 7M106 2L110 7M112 1L115 5" '
                       f'stroke="{p["hatch"]}" stroke-opacity="{p["hatch_op"]}" stroke-width="0.9"/>')
        return f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">' + "\n".join(out) + "</g>"
    leaflets = []
    for i, t in enumerate((22, 46, 70)):
        for side in (-1, 1):
            ang = side * (-52 + rnd.random() * 10)
            leaflets.append((t, ang, 0.9 + 0.1 * i))
    leaflets.append((92, -2, 1.05))
    for lx, ang, sc in leaflets:
        d = "M0 0C8 -7 24 -8 36 0C24 8 8 7 0 0Z"
        tr = f'transform="translate({lx} 0) rotate({ang}) scale({sc})"'
        parts = [fill(d, p["leaf"])]
        if shade:
            parts.append(hatch([d, "M0 -2L40 -2L40 10L0 10Z"], 35, 3.2, p, 0.8, seed=seed + lx, shrink=1.0))
        parts.append(ink_shape(d, p, 0.9, 2.4, step=3.0, wobble=0.25, seed=seed + lx, smooth=2))
        parts.append(ink_line("M3 0L30 0", p, 0.9, "in", seed=seed))
        out.append(f"<g {tr}>" + "".join(parts) + "</g>")
    return f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">' + "\n".join(out) + "</g>"


RUNES = {  # elder futhark, unit box: x 0..0.6, y 0..1
    "t": "M.3 1L.3 0M0 .28L.3 0L.6 .28",
    "o": "M0 1L.3 .66L0 .33L.3 0L.6 .33L.3 .66L.6 1",
    "s": "M.5 0L.08 .36L.52 .64L.1 1",
    "k": "M.5 0L.1 .5L.5 1",
}


def rune(p: dict, ch: str, x, y, h, w=None, color=None) -> str:
    d = RUNES[ch]
    sub = re.sub(_NUM.pattern, lambda m: str(float(m.group(0))), d)
    out = []
    for pts, closed in parse(sub):
        pts2 = [(x + px * h, y + py * h) for px, py in pts]
        out.append(ink_line(pts_d(pts2, False), p, w or h * 0.11, "flat", wobble=0.15, seed=int(x + y), color=color))
    return "\n".join(out)


def node(p: dict, x, y, r, state="locked", glyph=None, seed=4) -> str:
    """A skill node: a round rune-stone medallion hanging on the branch."""
    out = []
    circ = (f"M{x + r} {y}C{x + r} {y + r * 0.55} {x + r * 0.55} {y + r} {x} {y + r}"
            f"C{x - r * 0.55} {y + r} {x - r} {y + r * 0.55} {x - r} {y}"
            f"C{x - r} {y - r * 0.55} {x - r * 0.55} {y - r} {x} {y - r}"
            f"C{x + r * 0.55} {y - r} {x + r} {y - r * 0.55} {x + r} {y}Z")
    ri = r * 0.78
    inner = (f"M{x + ri} {y}C{x + ri} {y + ri * 0.55} {x + ri * 0.55} {y + ri} {x} {y + ri}"
             f"C{x - ri * 0.55} {y + ri} {x - ri} {y + ri * 0.55} {x - ri} {y}"
             f"C{x - ri} {y - ri * 0.55} {x - ri * 0.55} {y - ri} {x} {y - ri}"
             f"C{x + ri * 0.55} {y - ri} {x + ri} {y - ri * 0.55} {x + ri} {y}Z")
    base = p["gold"] if state == "done" else p["cream"]
    out.append(fill(circ, base))
    # shadow crescent on the lower-left
    out.append(hatch([circ, f"M{x - r} {y - r * 0.3}L{x + r * 0.3} {y + r}L{x - r} {y + r}Z"],
                     40, max(2.6, r * 0.11), p, max(0.8, r * 0.035), seed=seed))
    if state == "done":
        out.append(hatch([inner], -40, max(3.0, r * 0.16), p, max(0.8, r * 0.035), seed=seed + 1, op="0.35"))
    out.append(ink_shape(circ, p, r * 0.05, r * 0.16, step=1.5, wobble=0.3, seed=seed))
    out.append(ink_shape(inner, p, r * 0.035, r * 0.06, step=1.5, wobble=0.25, seed=seed + 2))
    if state == "current":
        halo = (f"M{x + r * 1.3} {y}C{x + r * 1.3} {y + r * 0.72} {x + r * 0.72} {y + r * 1.3} {x} {y + r * 1.3}"
                f"C{x - r * 0.72} {y + r * 1.3} {x - r * 1.3} {y + r * 0.72} {x - r * 1.3} {y}"
                f"C{x - r * 1.3} {y - r * 0.72} {x - r * 0.72} {y - r * 1.3} {x} {y - r * 1.3}"
                f"C{x + r * 0.72} {y - r * 1.3} {x + r * 1.3} {y - r * 0.72} {x + r * 1.3} {y}Z")
        out.append(f'<path d="{halo}" fill="none" stroke="{p["ink"]}" stroke-width="{r * 0.05}" '
                   f'stroke-dasharray="{r * 0.18} {r * 0.22}" stroke-linecap="round"/>')
    if glyph:
        gh = r * 0.9
        out.append(rune(p, glyph, x - gh * 0.3, y - gh * 0.5, gh, color=p["bark_dk"] if not p["mono"] else None))
    return "\n".join(out)


def bough(p: dict, d: str, w0, w1, seed=6, bark=True, light_side=True) -> str:
    """A branch: tapered bark silhouette with grain hatching on its shadow side."""
    prof = lambda s: w0 + (w1 - w0) * s
    pts = tapered_shape(d, prof, seed=seed)
    out = [fill(pts_d(pts), p["bark"])]
    if bark:
        # grain: long strokes along the branch on the lower/left half
        cl = resample(poly(d), 2.0, False)
        nrm = _normals(cl, False, 2)
        n = len(cl)
        rnd = random.Random(seed)
        segs = []
        for k in range(3):
            off = -(0.18 + k * 0.17)
            start = rnd.random() * 0.25
            while start < 0.95:
                ln = 0.12 + rnd.random() * 0.2
                i0, i1 = int(start * (n - 1)), int(min(0.999, start + ln) * (n - 1))
                sub = []
                for i in range(i0, i1 + 1):
                    h = prof(i / max(n - 1, 1)) / 2 * off
                    sub.append((cl[i][0] + nrm[i][0] * h, cl[i][1] + nrm[i][1] * h))
                if len(sub) > 2:
                    segs.append(ink_line(pts_d(sub, False), p, 1.4 + k * 0.2, "taper", seed=seed + k, wobble=0.2))
                start += ln + 0.08 + rnd.random() * 0.2
        out += segs
        out.append(hatch([pts, _half_poly(cl, nrm, prof, -1)], _dir_angle(cl) + 70, 5.5, p, 1.0, seed=seed, shrink=2))
    out.append(ink_shape(pts_d(pts), p, 1.3, 4.2, seed=seed, smooth=3))
    return "\n".join(out)


def _half_poly(cl, nrm, prof, side):
    a = [(c[0] + n[0] * prof(i / max(len(cl) - 1, 1)) * 0.65 * side, c[1] + n[1] * prof(i / max(len(cl) - 1, 1)) * 0.65 * side)
         for i, (c, n) in enumerate(zip(cl, nrm))]
    b = [(c[0] + n[0] * prof(i / max(len(cl) - 1, 1)) * 0.12 * side, c[1] + n[1] * prof(i / max(len(cl) - 1, 1)) * 0.12 * side)
         for i, (c, n) in enumerate(zip(cl, nrm))]
    return a + b[::-1]


def _dir_angle(cl):
    dx, dy = cl[-1][0] - cl[0][0], cl[-1][1] - cl[0][1]
    return math.degrees(math.atan2(dy, dx))


# ----------------------------------------------------------------- Tosk
def tosk(p: dict, scroll=True, branch=True, detail=1.0) -> str:
    """Ratatosk, sitting up on an ash bough, scroll in his paws. 512 x 512, facing right."""
    sp = 1 / detail  # hatch spacing multiplier for small renderings
    out = []

    if branch:
        out.append(bough(p, "M6 476C130 452 300 466 506 436", 34, 26, seed=21))
        out.append(ash_leaf(p, 462, 444, -48, 0.9, seed=31))
        out.append(ash_leaf(p, 60, 478, 196, 0.75, seed=32))

    # ---- tail: a great plume, S-curve rising behind the body and curling over the head
    # The plume rises in an S behind the back and its tip flicks forward over the head.
    tail_cl = "M180 412C112 410 56 340 64 250C72 166 132 104 198 88C238 78 258 82 270 66C276 58 280 54 284 50"
    tail_prof = lambda s: _interp(s, [(0, 28), (0.12, 62), (0.3, 88), (0.55, 124), (0.72, 116), (0.84, 80), (0.93, 44), (1.0, 8)])
    peaks = []
    tail = tapered_shape(tail_cl, tail_prof, seed=8, fur=0.24, fur_period=26, back=0.6, peaks=peaks)
    tail_d = pts_d(tail)
    out.append(fill(tail_d, p["fur"]))
    # washes, clipped to the plume: shadow on the inner curve, soft light inside the outer rim
    shade1 = "M36 430C0 330 40 220 120 180C96 240 100 330 180 410Z"
    shade2 = "M200 70C260 56 300 76 320 130L280 150C280 110 250 90 200 70Z"
    shade3 = "M120 360C100 320 100 290 130 250C150 300 170 340 196 400Z"
    light = ("M30 400C14 300 40 190 120 120C170 78 220 72 258 76C236 86 222 96 204 100C188 104 176 112 160 126"
             "C140 144 128 170 112 196C100 216 96 250 88 280C82 310 80 340 82 370C78 390 74 400 70 410Z")
    if not p["mono"]:
        out.append(clipped(light, tail_d, p["fur_lt"], 0.42))
        out.append(clipped(shade1, tail_d, p["fur_dk"], 0.35))
        out.append(clipped(shade2, tail_d, p["fur_dk"], 0.25))
    out.append(hatch([tail, shade1], -62, 6.5 * sp, p, 1.3, seed=12))
    out.append(hatch([tail, shade3], 20, 8 * sp, p, 1.0, seed=13))
    out.append(hatch([tail, shade2], 30, 6.5 * sp, p, 1.2, seed=14))
    # small tufts at the clump tips: two or three short hairs lying back along the edge
    rnd0 = random.Random(19)
    for k, (pt, nn, (tx, ty), s_) in enumerate(peaks):
        if s_ < 0.05 or rnd0.random() < 0.25:
            continue
        for j, (ln, ang) in enumerate(((12, 0.42), (17, 0.58), (10, 0.72))):
            if j == 2 and rnd0.random() < 0.5:
                continue
            ln *= 0.7 + 0.6 * rnd0.random()
            if s_ > 0.85:
                ln *= 1.5
            x0 = pt[0] - nn[0] * 1.5 + tx * 2.5 * (j - 1)
            y0 = pt[1] - nn[1] * 1.5 + ty * 2.5 * (j - 1)
            x1 = x0 + (nn[0] * (1 - ang) - tx * ang) * ln
            y1 = y0 + (nn[1] * (1 - ang) - ty * ang) * ln
            cx, cy = (x0 + x1) / 2 + nn[0] * 2.5, (y0 + y1) / 2 + nn[1] * 2.5
            out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", p, 2.0, "in", seed=k * 3 + j, wobble=0.15))
    # fur strands drawn as pen strokes sweeping with the plume
    cl = resample(poly(tail_cl), 2.0, False)
    nrm = _normals(cl, False, 2)
    rnd = random.Random(9)
    n = len(cl)
    for k in range(int(34 * detail)):
        s = 0.08 + rnd.random() * 0.88
        i = int(s * (n - 1))
        side = 1 if rnd.random() < 0.55 else -1
        h = tail_prof(s) / 2
        r0 = 0.15 + rnd.random() * 0.5
        ln = 0.35 + rnd.random() * 0.4
        c, nn = cl[i], nrm[i]
        tx, ty = -nn[1], nn[0]
        x0, y0 = c[0] + nn[0] * h * r0 * side, c[1] + nn[1] * h * r0 * side
        x1, y1 = (c[0] + nn[0] * h * (r0 + ln) * side - tx * h * 0.45,
                  c[1] + nn[1] * h * (r0 + ln) * side - ty * h * 0.45)
        cx, cy = (x0 + x1) / 2 + nn[0] * 5 * side, (y0 + y1) / 2 + nn[1] * 5 * side
        out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", p, 1.4 + rnd.random(), "in", seed=k, wobble=0.2))
    out.append(ink_shape(tail_d, p, 0.9, 3.0, seed=8, smooth=6, wobble=0.3, step=2.5))

    # ---- hind foot on the bough
    foot = "M200 426C236 428 272 436 302 440C322 444 320 454 298 454C262 456 226 452 204 446Z"
    out.append(fill(foot, p["fur"]))
    out.append(hatch([foot], 15, 5 * sp, p, 1.0, seed=15))
    out.append(ink_shape(foot, p, 1.0, 3.2, seed=16))
    for tx_ in (276, 288, 300):
        out.append(ink_line(f"M{tx_} 440C{tx_ + 4} 445 {tx_ + 6} 449 {tx_ + 8} 452", p, 1.4, "in", seed=tx_))

    # ---- body: sitting up, back arched, weight on the haunches
    body = ("M300 200C258 198 218 224 198 268C178 312 170 392 206 430C240 454 302 452 334 420"
            "C354 400 352 340 346 300C342 270 336 230 330 205Z")
    out.append(fill(body, p["fur"]))
    belly = "M334 420C300 450 246 452 216 436C264 420 300 390 326 338C346 360 348 400 334 420Z"
    out.append(fill(belly, p["cream"]))
    bshade = "M198 268C178 312 170 392 206 430C240 454 302 452 334 420C290 432 236 420 220 380C204 346 200 300 198 268Z"
    if not p["mono"]:
        out.append(clipped(bshade, body, p["fur_dk"], 0.26))
    out.append(hatch([body, bshade], -35, 6 * sp, p, 1.2, seed=17))
    out.append(hatch([body, "M198 268C178 312 170 392 206 430C212 400 206 340 202 300Z"], 50, 7 * sp, p, 1.0, seed=18))
    neck_sh = "M286 210C312 222 338 226 346 300C330 262 304 240 284 220Z"
    out.append(hatch([body, neck_sh], -60, 6 * sp, p, 1.1, seed=19))
    # haunch: an open contour for the strong hind leg, and a crease where it meets the belly
    out.append(ink_line("M212 432C184 406 186 350 226 326", p, 2.8, "taper", seed=20))
    out.append(ink_line("M292 404C292 388 286 374 274 364", p, 2.0, "taper", seed=21))
    out.append(hatch([body, "M196 440C182 404 200 374 236 372C272 370 300 398 296 440Z"], 25, 7.5 * sp, p, 1.0, seed=22))
    out.append(ink_shape(body, p, 1.2, 4.6, seed=23, smooth=5))

    # ---- scroll + forepaws
    if scroll:
        g = ['<g transform="rotate(-14 372 300)">']
        sheet = "M340 268L404 268L404 334L340 334Z"
        g.append(fill(sheet, p["cream"]))
        g.append(hatch([sheet, "M340 300L404 300L404 334L340 334Z"], 0, 4.2 * sp, p, 0.8, seed=24, op="0.35"))
        g.append(ink_shape(sheet, p, 1.0, 3.0, seed=25, wobble=0.3, smooth=2))
        for ch, rx in zip("tosk", (348, 361, 375, 389)):
            g.append(rune(p, ch, rx, 288, 22, 2.0, color=p["bark_dk"] if not p["mono"] else None))
        # rolled ends
        for yy in (268, 334):
            roll = f"M334 {yy - 6}L410 {yy - 6}C416 {yy - 6} 416 {yy + 6} 410 {yy + 6}L334 {yy + 6}C328 {yy + 6} 328 {yy - 6} 334 {yy - 6}Z"
            g.append(fill(roll, p["cream"]))
            g.append(hatch([roll], 90, 3.5 * sp, p, 0.8, seed=26 + yy, op="0.4", shrink=0.5))
            g.append(ink_shape(roll, p, 1.0, 2.8, seed=27 + yy, wobble=0.2, smooth=2))
        g.append("</g>")
        out += g
        # forepaws gripping the scroll
        for paw, arm in (("M336 282C352 272 366 282 360 296C352 306 334 300 336 282Z", "M332 262C330 272 332 280 338 286"),
                         ("M344 318C360 310 374 318 368 332C360 342 342 336 344 318Z", "M334 300C336 310 338 318 346 322")):
            out.append(ink_line(arm, p, 5.5, "flat", color=p["fur"], wobble=0))
            out.append(fill(paw, p["fur"]))
            out.append(ink_shape(paw, p, 1.0, 2.8, seed=28, smooth=2, wobble=0.2))
            out.append(ink_line(arm, p, 2.0, "taper", seed=29))

    # ---- head
    head = ("M280 118C305 100 346 104 366 128C380 143 386 160 398 176C406 184 404 192 396 195"
            "C380 206 362 204 348 210C330 218 305 218 288 206C272 194 266 150 280 118Z")
    ear_b = "M290 124C284 104 290 84 304 76C318 84 326 104 322 120Z"
    ear_f = "M334 114C332 94 340 76 354 70C366 78 370 98 362 116Z"
    for ear, inner in ((ear_b, "M298 120C296 106 300 94 305 86C312 94 316 108 316 118Z"),
                       (ear_f, "M342 113C341 100 346 90 353 82C359 90 362 104 357 113Z")):
        out.append(fill(ear, p["fur"]))
        out.append(fill(inner, p["cream"]))
        out.append(hatch([inner], 80, 3.5 * sp, p, 0.9, seed=30, op="0.45"))
        out.append(ink_shape(ear, p, 1.0, 3.6, seed=33, smooth=3, wobble=0.3))
    # ear tufts: wispy strands flicking up from each tip
    for base, tip, ctl, w in (((302, 77), (290, 48), (290, 66), 3.0), ((306, 75), (304, 44), (308, 58), 3.2),
                              ((310, 76), (320, 52), (318, 62), 2.4),
                              ((352, 71), (340, 42), (340, 60), 3.0), ((356, 70), (356, 38), (360, 52), 3.2),
                              ((360, 72), (372, 48), (368, 58), 2.4)):
        out.append(ink_line(f"M{base[0]} {base[1]}Q{ctl[0]} {ctl[1]} {tip[0]} {tip[1]}", p, w, "in", seed=base[0]))
    out.append(fill(head, p["fur"]))
    muzzle = "M346 166C368 160 396 172 398 190C390 206 360 206 342 198Z"
    out.append(fill(muzzle, p["cream"]))
    hshade = "M288 206C272 194 266 150 280 118C286 160 300 196 348 210C330 218 305 218 288 206Z"
    if not p["mono"]:
        out.append(clipped(hshade, head, p["fur_dk"], 0.25))
    out.append(hatch([head, hshade], -50, 5.5 * sp, p, 1.1, seed=34))
    out.append(hatch([head, "M300 196C320 212 350 214 372 204L376 220L300 220Z"], 10, 5 * sp, p, 1.0, seed=35))
    out.append(ink_shape(head, p, 1.2, 4.4, seed=36, smooth=5))
    # eye: large, dark, with a lively highlight and an arched brow
    eye = "M340 150C350 140 364 142 368 152C364 162 350 163 340 150Z"
    out.append(fill(eye, p["ink"]))
    out.append(f'<circle cx="358" cy="148" r="3.4" fill="{p["paper"]}"/>')
    out.append(f'<circle cx="349" cy="156" r="1.4" fill="{p["paper"]}"/>')
    out.append(ink_line("M338 150C348 138 364 139 370 150", p, 3.2, "taper", seed=37))
    out.append(ink_line("M336 134C348 126 362 128 370 136", p, 2.6, "taper", seed=38))
    # nose, mouth, whiskers
    out.append(fill("M396 174C404 174 408 180 406 186C403 192 396 192 392 186C390 180 392 175 396 174Z", p["ink"]))
    out.append(ink_line("M398 190C396 198 388 202 380 198", p, 1.8, "taper", seed=39))
    out.append(ink_line("M380 198C376 202 372 202 368 198", p, 1.4, "taper", seed=40))
    for d in ("M380 186C396 184 412 182 428 182", "M378 192C396 194 410 198 424 204", "M376 196C388 204 400 212 410 220"):
        out.append(ink_line(d, p, 1.5, "in", seed=41, wobble=0.3))
    # paw toes
    for d in ("M350 290L356 286", "M352 296L358 293", "M358 326L364 322", "M360 332L366 329"):
        out.append(ink_line(d, p, 1.4, "in", seed=43))
    return "\n".join(o for o in out if o)


def _interp(s, pts):
    for (s0, v0), (s1, v1) in zip(pts, pts[1:]):
        if s <= s1:
            t = (s - s0) / (s1 - s0) if s1 > s0 else 0
            t = t * t * (3 - 2 * t)
            return v0 + (v1 - v0) * t
    return pts[-1][1]


# ----------------------------------------------------------------- icon
def icon_figure(p: dict, bold=1.0) -> str:
    """Simplified Tosk for the app icon: head + plume, reads at 48 px.  512 space."""
    out = []
    tail_cl = "M226 396C120 396 76 290 104 206C130 130 206 88 282 100C340 110 362 160 330 196"
    prof = lambda s: _interp(s, [(0, 40), (0.15, 96), (0.45, 156), (0.7, 140), (0.88, 86), (1.0, 10)])
    tail = tapered_shape(tail_cl, prof, seed=50, fur=0.2, fur_period=70)
    out.append(fill(pts_d(tail), p["fur"]))
    out.append(hatch([tail, "M60 430C30 320 60 220 150 180C110 250 120 330 220 420Z"], -60, 11, p, 3.2 * bold, seed=51))
    out.append(hatch([tail, "M240 70C310 60 370 110 370 200L320 210C320 150 290 110 240 70Z"], 30, 11, p, 3.0 * bold, seed=52))
    if not p["mono"]:
        out.append(ink_line("M108 330C90 250 120 180 190 140", p, 22, "taper", color=p["fur_lt"], wobble=0))
    out.append(ink_shape(pts_d(tail), p, 3.0 * bold, 9.0 * bold, seed=53, smooth=6, wobble=0.4, step=2.5))
    # body (small, tucked) + hind leg
    body = "M300 230C250 236 212 290 220 350C226 400 290 428 350 412C396 400 392 320 372 270C362 246 334 232 300 230Z"
    out.append(fill(body, p["fur"]))
    out.append(fill("M350 412C300 426 240 408 236 370C260 370 320 360 356 320C380 356 380 396 350 412Z", p["cream"]))
    out.append(hatch([body, "M220 350C226 400 290 428 350 412C290 418 250 400 236 350Z"], -35, 11, p, 3.0 * bold, seed=54))
    out.append(ink_shape(body, p, 3.0 * bold, 9.5 * bold, seed=55, smooth=6, step=2.5))
    out.append(ink_line("M256 410C220 370 240 310 300 310", p, 6 * bold, "taper", seed=56))
    # head, facing right, slightly up
    head = ("M278 196C300 160 358 150 396 176C416 190 428 214 446 236C458 250 454 262 440 266"
            "C416 274 398 272 380 278C350 288 310 284 290 262C270 240 266 216 278 196Z")
    ear_b = "M292 190C282 160 292 128 310 112C330 126 340 164 332 190Z"
    ear_f = "M348 170C344 138 360 104 380 94C396 108 404 146 396 176Z"
    for ear, inner in ((ear_b, "M302 188C296 164 302 144 310 130C320 146 326 170 324 186Z"),
                       (ear_f, "M358 170C354 148 364 126 380 112C388 130 392 154 388 172Z")):
        out.append(fill(ear, p["fur"]))
        out.append(fill(inner, p["cream"]))
        out.append(ink_shape(ear, p, 3.0 * bold, 8.0 * bold, seed=57, smooth=4, step=2.5))
    for base, tip, ctl in (((308, 114), (292, 76), (290, 100)), ((314, 112), (320, 72), (324, 92)),
                           ((378, 96), (364, 56), (362, 80)), ((384, 95), (396, 60), (398, 78))):
        out.append(ink_line(f"M{base[0]} {base[1]}Q{ctl[0]} {ctl[1]} {tip[0]} {tip[1]}", p, 8 * bold, "in", seed=base[0]))
    out.append(fill(head, p["fur"]))
    out.append(fill("M380 236C410 226 442 238 446 254C436 270 400 276 376 266Z", p["cream"]))
    out.append(hatch([head, "M290 262C270 240 266 216 278 196C284 236 306 262 360 278C330 288 306 282 290 262Z"], -50, 10, p, 2.8 * bold, seed=58))
    out.append(ink_shape(head, p, 3.0 * bold, 9.5 * bold, seed=59, smooth=6, step=2.5))
    eye = "M366 212C380 196 406 198 412 216C404 232 380 232 366 212Z"
    out.append(fill(eye, p["ink"]))
    out.append(f'<circle cx="398" cy="210" r="6.5" fill="{p["paper"]}"/>')
    out.append(ink_line("M362 212C378 190 408 192 416 212", p, 7 * bold, "taper", seed=60))
    out.append(ink_line("M360 186C378 172 404 174 414 186", p, 5.5 * bold, "taper", seed=61))
    out.append(fill("M440 230C452 230 460 240 456 250C452 258 442 258 436 250C432 242 434 232 440 230Z", p["ink"]))
    out.append(ink_line("M446 258C442 268 430 272 420 266", p, 3.5 * bold, "taper", seed=62))
    for d in ("M424 246C448 244 468 244 486 248", "M422 254C446 260 464 268 478 278"):
        out.append(ink_line(d, p, 3.2 * bold, "in", seed=63))
    return "\n".join(o for o in out if o)


def icon(p: dict) -> str:
    out = []
    r = 112
    out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["paper"]}"/>')
    if not p["mono"]:
        out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["cream"]}" fill-opacity="0.6"/>')
    # a bookplate double rule
    out.append(f'<rect x="22" y="22" width="468" height="468" rx="{r - 20}" fill="none" stroke="{p["ink"]}" stroke-width="5"/>')
    out.append(f'<rect x="34" y="34" width="444" height="444" rx="{r - 30}" fill="none" stroke="{p["ink"]}" stroke-width="2"/>')
    out.append(f'<g transform="translate(-6 20) scale(0.98)">{icon_figure(p)}</g>')
    return "\n".join(out)


def logo(p: dict) -> str:
    out = [f'<g transform="translate(0 -10) scale(0.56)">{icon_figure(p, bold=0.9)}</g>']
    out.append(f'<text x="286" y="206" font-family="Georgia, \'Palatino Linotype\', \'Book Antiqua\', \'Iowan Old Style\', serif" '
               f'font-size="188" font-weight="700" letter-spacing="-4" fill="{p["ink"]}">tosk</text>')
    out.append(ash_leaf(p, 300, 236, -6, 0.78, seed=70))
    return "\n".join(out)


# ----------------------------------------------------------------- Yggdrasil
def yggdrasil(p: dict) -> str:
    """The course tree: ancient ash, three roots over the well, serpent, eagle, rune-stone nodes.  800 x 1100."""
    out = []
    sp = 1.0
    STEP[0] = 2.6

    # ---- well of Urd between the roots
    well = "M212 1032C260 996 540 996 592 1032C550 1070 254 1072 212 1032Z"
    out.append(fill(well, p["water"]))
    out.append(hatch([well], 0, 6, p, 1.0, seed=80, op="0.5"))
    out.append(hatch([well, "M212 1032L400 1032L400 1080L212 1080Z"], 0, 5, p, 0.9, seed=180, op="0.5"))
    out.append(ink_shape(well, p, 1.0, 3.4, seed=81, smooth=4))
    for d in ("M300 1030C340 1040 440 1044 520 1032", "M330 1046C380 1054 440 1054 490 1046", "M250 1020C300 1012 360 1010 400 1012"):
        out.append(ink_line(d, p, 1.4, "taper", seed=82))
    # stones around the rim
    for cx, cy, rr in ((232, 1046, 15), (270, 1062, 12), (560, 1052, 14), (530, 1066, 11), (420, 1070, 12), (340, 1072, 10), (480, 1074, 9)):
        st = f"M{cx - rr} {cy}C{cx - rr} {cy - rr} {cx + rr} {cy - rr} {cx + rr} {cy}C{cx + rr} {cy + rr * 0.6} {cx - rr} {cy + rr * 0.6} {cx - rr} {cy}Z"
        out.append(fill(st, p["cream"]))
        out.append(hatch([st, f"M{cx - rr} {cy}L{cx + rr} {cy}L{cx + rr} {cy + rr}L{cx - rr} {cy + rr}Z"], 30, 3.5, p, 0.8, seed=cx))
        out.append(ink_shape(st, p, 0.9, 2.6, seed=cx, smooth=3))

    # ---- roots (three), sinuous and knuckled, the trunk flares into them
    roots = (("M336 866C316 900 270 904 236 930C200 958 210 996 160 1004C120 1010 90 996 70 1030", 96, 12),
             ("M398 870C380 910 420 940 404 972C396 990 398 1000 396 1010", 66, 22),
             ("M464 866C490 900 540 904 574 930C612 958 600 996 650 1004C690 1010 716 998 740 1030", 96, 12),
             ("M300 890C250 900 200 930 150 936", 34, 8),
             ("M500 890C540 904 580 930 620 936", 30, 8))
    for d, w0, w1 in roots:
        out.append(bough(p, d, w0, w1, seed=83 + w0 + w1))
    # small root tendrils
    for d in ("M236 930C216 960 190 980 160 990", "M574 930C590 960 606 980 640 990",
              "M396 1000C376 1012 350 1016 330 1026", "M150 936C130 946 110 950 90 950", "M620 936C640 950 660 952 690 956"):
        out.append(ink_line(d, p, 7, "in", color=p["bark"], wobble=0))
        out.append(ink_line(d, p, 2.0, "in", seed=84))

    # ---- Nidhogg, coiled on the right root, gnawing
    serp = "M744 1060C700 1064 666 1040 652 1006C640 972 676 944 712 960C748 978 724 1018 694 1012C664 1006 626 994 596 1002"
    sprof = lambda s: _interp(s, [(0, 8), (0.25, 32), (0.6, 32), (0.85, 26), (1.0, 24)])
    body_pts = tapered_shape(serp, sprof, seed=85)
    body_d = pts_d(body_pts)
    sc = p["leaf_dk"] if not p["mono"] else p["paper"]
    out.append(fill(body_d, sc))
    if not p["mono"]:
        out.append(clipped("M600 1000L760 1000L760 1070L600 1070Z", body_d, p["ink"], 0.18))
    out.append(hatch([body_pts, "M580 1004L760 1004L760 1070L580 1070Z"], 40, 4.5, p, 1.0, seed=86))
    out.append(hatch([body_pts, "M580 940L760 940L760 1010L580 1010Z"], -30, 6, p, 0.9, seed=186, op="0.5"))
    out.append(ink_shape(body_d, p, 1.0, 3.6, seed=87, smooth=4))
    cl = resample(poly(serp), 2.0, False)
    nrm = _normals(cl, False, 2)
    for i in range(10, len(cl) - 30, 16):  # a low crest of back spines
        c, n = cl[i], nrm[i]
        h = sprof(i / (len(cl) - 1)) / 2
        out.append(ink_line(f"M{fmt(c[0] + n[0] * h * 0.8)} {fmt(c[1] + n[1] * h * 0.8)}"
                            f"Q{fmt(c[0] + n[0] * (h + 4) - 3)} {fmt(c[1] + n[1] * (h + 4))} {fmt(c[0] + n[0] * (h + 7) + 1)} {fmt(c[1] + n[1] * (h + 7))}", p, 2.6, "in", seed=i))
    # head: jaws open on the root
    head = ("M600 1000C590 980 566 974 544 982C534 986 530 994 536 1000C528 1006 536 1016 552 1020"
            "C572 1024 596 1018 600 1000Z")
    out.append(fill(head, sc))
    out.append(hatch([head, "M530 1000L600 1000L600 1030L530 1030Z"], 30, 4, p, 0.9, seed=191))
    out.append(ink_shape(head, p, 1.0, 3.4, seed=88, smooth=3))
    out.append(ink_line("M560 978Q552 966 560 954", p, 3.4, "in", seed=188))  # horns
    out.append(ink_line("M580 980Q580 966 592 958", p, 3.4, "in", seed=189))
    out.append(f'<circle cx="578" cy="992" r="3.6" fill="{p["paper"]}"/>')
    out.append(f'<circle cx="577" cy="992" r="1.8" fill="{p["ink"]}"/>')
    out.append(ink_line("M536 1000C552 1004 572 1006 596 1006", p, 1.8, "taper", seed=89))
    for d in ("M544 1000L542 1008", "M554 1002L553 1010", "M548 1012L550 1006"):  # teeth
        out.append(ink_line(d, p, 1.8, "in", seed=190, color=p["paper"] if not p["mono"] else None))

    # ---- trunk: wide, gnarled, leaning a little, flaring into the roots
    trunk = ("M296 884C324 800 344 700 348 600C352 520 346 440 362 380C372 346 386 320 398 296"
             "C414 320 430 348 438 386C454 450 446 540 454 620C462 720 482 800 506 884"
             "C456 900 346 900 296 884Z")
    out.append(fill(trunk, p["bark"]))
    tshade = "M296 884C324 800 344 700 348 600C352 520 346 440 362 380C372 346 386 320 398 296C384 400 384 620 392 884Z"
    if not p["mono"]:
        out.append(clipped(tshade, trunk, p["bark_dk"], 0.3))
    out.append(hatch([trunk, tshade], 84, 7 * sp, p, 1.3, seed=90, curve=6))
    out.append(hatch([trunk, "M296 884C312 820 330 760 340 700L380 700C376 760 380 820 392 884Z"], 30, 7, p, 1.1, seed=91))
    out.append(hatch([trunk, "M438 300C442 400 448 600 456 760L506 884L400 884L400 300Z"], 96, 12, p, 1.0, seed=92, op="0.4", curve=4))
    # bark ridges: long sinuous strokes
    rnd = random.Random(93)
    for k in range(18):
        x = 320 + rnd.random() * 160
        y0 = 320 + rnd.random() * 500
        ln = 50 + rnd.random() * 120
        dx = (x - 400) * 0.1
        out.append(ink_line(f"M{fmt(x)} {fmt(y0)}C{fmt(x + dx - 6)} {fmt(y0 + ln * 0.4)} {fmt(x + dx * 1.5 + 6)} {fmt(y0 + ln * 0.7)} {fmt(x + dx * 2)} {fmt(y0 + ln)}", p, 1.7, "taper", seed=k))
    # knot hole
    knot = "M426 650C440 638 458 644 460 660C458 678 442 686 428 676C418 668 416 658 426 650Z"
    out.append(fill(knot, p["bark_dk"] if not p["mono"] else p["paper"]))
    out.append(hatch([knot], 60, 3.5, p, 1.0, seed=94))
    out.append(hatch([knot, "M416 660L470 660L470 690L416 690Z"], -30, 3.5, p, 1.0, seed=194))
    out.append(ink_shape(knot, p, 1.2, 3.2, seed=95, smooth=3))
    out.append(ink_shape(trunk, p, 1.4, 5.2, seed=96, smooth=6, wobble=1.6))
    # carved runes t o s k down the trunk
    for i, ch in enumerate("tosk"):
        y = 520 + i * 46
        if not p["mono"]:
            out.append(rune(p, ch, 382, y, 32, 3.0, color=p["paper"]))
        out.append(rune(p, ch, 380, y - 2, 32, 2.6))

    # ---- boughs and nodes
    boughs = [  # (path, w0, w1, node x, y, state, glyph)
        ("M372 772C330 800 270 770 220 776C190 780 164 798 146 806", 42, 12, 146, 806, "done", "t"),
        ("M436 702C480 724 540 690 590 708C620 718 640 730 654 740", 40, 12, 654, 740, "done", "o"),
        ("M362 604C320 630 250 580 190 590C160 594 136 598 118 604", 38, 12, 118, 604, "done", "s"),
        ("M438 524C480 540 540 486 600 488C626 488 644 484 656 480", 38, 12, 656, 480, "current", "k"),
        ("M382 432C340 420 310 376 270 356C250 346 236 332 228 324", 38, 12, 228, 324, "locked", None),
        ("M418 418C460 400 500 350 550 326C570 316 584 304 594 296", 38, 12, 594, 296, "locked", None),
        ("M400 322C390 286 412 256 398 226C394 212 398 202 400 194", 34, 14, 400, 190, "locked", None),
        ("M400 300C370 270 330 262 300 232", 20, 6, None, None, None, None),  # leaf-only limbs for the crown
        ("M404 300C436 270 476 258 506 236", 20, 6, None, None, None, None),
    ]
    twigs = {
        0: [("M270 784C250 760 226 744 196 738", 11, 4), ("M214 790C200 806 186 816 168 826", 10, 4), ("M300 776C292 758 280 748 262 742", 8, 3)],
        1: [("M530 704C546 680 568 666 596 660", 11, 4), ("M580 714C590 732 606 746 626 752", 10, 4), ("M490 706C494 688 504 676 518 670", 8, 3)],
        2: [("M250 598C236 574 216 560 186 554", 11, 4), ("M200 598C186 614 170 624 150 632", 10, 4), ("M300 602C296 586 286 574 270 566", 8, 3)],
        3: [("M520 504C534 482 556 472 584 466", 11, 4), ("M570 496C588 508 606 516 626 522", 10, 4), ("M480 508C486 490 496 480 512 474", 8, 3)],
        4: [("M320 392C300 370 290 356 272 342", 10, 4), ("M292 372C282 390 270 402 252 410", 10, 4), ("M340 404C330 388 320 380 304 372", 8, 3)],
        5: [("M500 360C508 338 520 322 540 310", 10, 4), ("M536 338C552 350 568 358 586 364", 10, 4), ("M470 382C470 364 476 352 488 342", 8, 3)],
        6: [("M400 270C380 250 360 236 334 226", 11, 4), ("M400 250C420 232 440 220 466 212", 11, 4),
            ("M340 226C320 212 300 206 280 206", 8, 3), ("M466 212C486 200 506 196 526 196", 8, 3)],
    }
    leaves = {
        0: [(196, 738, -150, 0.85), (168, 826, 160, 0.8), (262, 742, -120, 0.7), (110, 840, 175, 0.7)],
        1: [(596, 660, -25, 0.85), (626, 752, 30, 0.8), (518, 670, -60, 0.7), (696, 756, 15, 0.7)],
        2: [(186, 554, -160, 0.85), (150, 632, 165, 0.8), (270, 566, -120, 0.7), (76, 622, -178, 0.7)],
        3: [(584, 466, -20, 0.85), (626, 522, 25, 0.8), (512, 474, -60, 0.7), (696, 494, 12, 0.7)],
        4: [(272, 342, -140, 0.85), (252, 410, 150, 0.8), (304, 372, -110, 0.7), (190, 312, -160, 0.7)],
        5: [(540, 310, -40, 0.85), (586, 364, 20, 0.8), (488, 342, -70, 0.7), (634, 290, -12, 0.7)],
        6: [(334, 226, -140, 0.85), (466, 212, -40, 0.85), (280, 206, -165, 0.75), (526, 196, -20, 0.75),
            (330, 150, -110, 0.7), (470, 148, -70, 0.7), (396, 140, -90, 0.6)],
        7: [(300, 232, -150, 0.8), (320, 250, -175, 0.7), (250, 250, -140, 0.7), (262, 200, -120, 0.7)],
        8: [(506, 236, -30, 0.8), (486, 254, -5, 0.7), (556, 254, -40, 0.7), (544, 200, -60, 0.7)],
    }
    for i, (d, w0, w1, nx, ny, state, glyph) in enumerate(boughs):
        out.append(bough(p, d, w0, w1, seed=100 + i))
        for td, tw0, tw1 in twigs.get(i, []):
            out.append(bough(p, td, tw0, tw1, seed=110 + i, bark=False))
        for lx, ly, la, ls in leaves.get(i, []):
            out.append(ash_leaf(p, lx, ly, la, ls, seed=120 + i + int(lx), shade=(int(lx) % 2 == 0), simple=True))
    # Tosk himself, sitting on the left bough with a message for the eagle
    STEP[0] = 4.0
    out.append(f'<g transform="translate(206 486) scale(0.24)">{tosk(p, scroll=True, branch=False, detail=0.45)}</g>')
    STEP[0] = 2.6
    for i, (d, w0, w1, nx, ny, state, glyph) in enumerate(boughs):
        if nx is not None:
            out.append(node(p, nx, ny, 32, state, glyph, seed=130 + i))

    # ---- the eagle in the crown
    out.append(f'<g transform="translate(400 76) scale(1.25)">{eagle(p, 0, 0)}</g>')
    STEP[0] = 1.0
    return "\n".join(o for o in out if o)


def eagle(p: dict, x, y) -> str:
    """Perched eagle, facing left, folded wings.  Centred near (x, y)."""
    out = [f'<g transform="translate({x} {y})">']
    out.append(ink_line("M-60 60C-20 56 20 56 60 60", p, 6, "flat", color=p["bark"], wobble=0))
    out.append(ink_line("M-60 60C-20 56 20 56 60 60", p, 2.2, "taper", seed=140))
    wing = "M-8 -20C20 -40 46 -28 50 10C52 40 30 60 6 62C-4 50 -12 10 -8 -20Z"
    body = "M-30 -30C-12 -46 10 -40 16 -16C22 10 10 48 -6 60C-22 52 -36 20 -30 -30Z"
    out.append(fill(body, p["bark_dk"] if not p["mono"] else p["paper"]))
    out.append(hatch([body], 70, 4.5, p, 1.0, seed=141))
    out.append(ink_shape(body, p, 1.0, 3.2, seed=142, smooth=4))
    out.append(fill(wing, p["bark"] if not p["mono"] else p["paper"]))
    out.append(hatch([wing, "M-8 20L50 10L50 62L0 62Z"], 60, 4.5, p, 1.0, seed=143))
    for d in ("M6 -4C16 10 24 30 24 50", "M-2 10C8 24 14 40 14 56"):
        out.append(ink_line(d, p, 1.4, "taper", seed=144))
    out.append(ink_shape(wing, p, 1.0, 3.4, seed=145, smooth=4))
    head = "M-42 -48C-32 -62 -8 -58 -4 -40C-2 -28 -12 -20 -26 -22C-38 -24 -46 -36 -42 -48Z"
    out.append(fill(head, p["cream"]))
    out.append(ink_shape(head, p, 1.0, 3.0, seed=146, smooth=3))
    beak = "M-44 -46C-56 -44 -64 -34 -58 -26C-54 -24 -50 -28 -48 -32C-46 -36 -44 -40 -42 -44Z"
    out.append(fill(beak, p["gold"]))
    out.append(ink_shape(beak, p, 0.9, 2.6, seed=147, smooth=2))
    out.append(ink_line("M-56 -36C-52 -34 -48 -34 -46 -36", p, 1.2, "taper", seed=150))
    out.append(f'<circle cx="-30" cy="-44" r="3.4" fill="{p["ink"]}"/>')
    out.append(f'<circle cx="-29" cy="-45" r="1.2" fill="{p["paper"]}"/>')
    out.append(ink_line("M-38 -50C-32 -54 -24 -54 -18 -50", p, 2.2, "taper", seed=148))  # the stern brow
    for d in ("M-14 58L-20 68", "M-8 60L-6 70", "M-18 60L-26 64"):  # talons
        out.append(ink_line(d, p, 2.4, "in", seed=149))
    out.append("</g>")
    return "\n".join(out)


# ----------------------------------------------------------------- branch tile
def branch_tile(p: dict) -> str:
    """A fork between skill nodes for the course map.  400 x 400."""
    out = []
    out.append(bough(p, "M200 352C216 310 190 270 200 222", 40, 32, seed=150))
    out.append(bough(p, "M200 226C196 180 120 170 92 104", 30, 12, seed=151))
    out.append(bough(p, "M200 226C210 170 290 160 310 112", 30, 12, seed=152))
    out.append(bough(p, "M150 166C134 150 124 150 108 158", 9, 4, seed=153, bark=False))
    out.append(bough(p, "M254 158C266 138 276 134 294 132", 9, 4, seed=154, bark=False))
    out.append(bough(p, "M196 290C180 282 170 280 160 284", 8, 3, seed=161, bark=False))
    out.append(ash_leaf(p, 108, 158, 196, 0.85, seed=155))
    out.append(ash_leaf(p, 294, 132, -28, 0.85, seed=156))
    out.append(ash_leaf(p, 160, 284, 200, 0.7, seed=157))
    out.append(node(p, 200, 352, 40, "done", "t", seed=158))
    out.append(node(p, 92, 100, 34, "current", "o", seed=159))
    out.append(node(p, 310, 108, 34, "locked", None, seed=160))
    return "\n".join(out)


# ----------------------------------------------------------------- sheet
def sheet_html() -> str:
    pal = [(k, v) for k, v in COLOR.items() if isinstance(v, str) and v.startswith("#")]
    sw = "".join(f'<div class="sw"><div class="chip" style="background:{v}"></div><b>{k}</b><span>{v}</span></div>' for k, v in pal)
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk: storybook ink</title>
<style>
body{{margin:0;padding:28px 36px;background:#F7F0E2;color:#3B2A1F;font-family:Georgia,'Palatino Linotype',serif;width:1520px}}
h1{{margin:0 0 4px;font-size:44px;letter-spacing:-1px}} p.sub{{margin:0 0 18px;font-size:15px;opacity:.8}}
.row{{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;margin-bottom:18px}}
figure{{margin:0}}
.card{{background:#FBF7EE;border:1.5px solid #3B2A1F;border-radius:14px;padding:12px 14px 8px;box-shadow:3px 4px 0 #3B2A1F22}}
.card.w{{background:#fff}} .card img{{display:block}} .card figcaption{{text-align:center;font-size:13px;margin-top:6px;opacity:.85}}
.icons{{display:flex;gap:16px;align-items:flex-end}} .icons div{{text-align:center;font-size:12px}}
.pal{{display:flex;gap:8px;flex-wrap:wrap}} .sw{{width:66px;font-size:10px;text-align:center}} .sw b{{display:block;margin-top:3px}}
.chip{{height:44px;border-radius:8px;border:1px solid #3B2A1F55}}
</style></head><body>
<h1>tosk</h1>
<p class="sub">Ratatosk, the messenger squirrel of Yggdrasil. Storybook ink: tapered pen lines, hatching, warm watercolour. Colour and e-ink side by side.</p>
<div class="row">
 <figure class="card"><img src="tosk.svg" width="340"><figcaption>Tosk</figcaption></figure>
 <figure class="card w"><img src="tosk-mono.svg" width="340"><figcaption>Tosk, e-ink</figcaption></figure>
 <figure class="card"><div class="icons">
   <div><img src="icon.svg" width="128"><br>128</div><div><img src="icon.svg" width="96"><br>96</div><div><img src="icon.svg" width="48"><br>48</div>
   <div><img src="icon-mono.svg" width="96"><br>96 e-ink</div><div><img src="icon-mono.svg" width="48"><br>48</div></div>
   <figcaption>App icon</figcaption>
   <img src="logo.svg" width="440" style="margin-top:10px"><figcaption>Logo</figcaption></figure>
</div>
<div class="row">
 <figure class="card"><img src="yggdrasil.svg" width="380"><figcaption>Yggdrasil: the course tree</figcaption></figure>
 <figure class="card w"><img src="yggdrasil-mono.svg" width="380"><figcaption>Yggdrasil, e-ink</figcaption></figure>
 <div style="width:520px">
  <div class="row"><figure class="card"><img src="branch-tile.svg" width="210"><figcaption>Map branch tile</figcaption></figure>
  <figure class="card w"><img src="branch-tile-mono.svg" width="210"><figcaption>e-ink</figcaption></figure></div>
  <figure class="card" style="margin:0"><div class="pal">{sw}</div><figcaption>Palette</figcaption></figure>
 </div>
</div>
</body></html>
"""


def main():
    files = {
        "tosk": (512, 512, tosk, "Tosk, the messenger squirrel of Yggdrasil"),
        "icon": (512, 512, icon, "tosk app icon"),
        "yggdrasil": (800, 1100, yggdrasil, "Yggdrasil, the course tree"),
        "branch-tile": (400, 400, branch_tile, "Map branch tile: a fork between skills"),
    }
    for name, (w, h, fn, title) in files.items():
        (HERE / f"{name}.svg").write_text(svg(w, h, fn(COLOR), title), encoding="utf-8")
        (HERE / f"{name}-mono.svg").write_text(svg(w, h, fn(MONO), title + " (e-ink)"), encoding="utf-8")
    (HERE / "logo.svg").write_text(svg(760, 300, logo(COLOR), "tosk logo"), encoding="utf-8")
    (HERE / "sheet.html").write_text(sheet_html(), encoding="utf-8")
    for f in sorted(HERE.glob("*.svg")):
        print(f"{f.name:24s} {f.stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
