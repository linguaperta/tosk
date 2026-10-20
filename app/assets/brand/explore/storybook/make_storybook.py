"""tosk brand exploration: "storybook ink" style, round 2 (v1 kept in v1/).

Expressive pen lines (filled, tapered strokes whose weight follows the light),
procedural hatching / cross-hatching for shading, warm muted watercolour fills.
Everything is drawn once from Bezier silhouettes and rendered twice: colour and
pure black/white (e-ink).  Pure Python; fontTools is used only for the wordmark
(outlining fonts/Gelasio-Bold.ttf) and is optional.

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
    silver="#B9BDBD",
    bronze="#B5713E",
    water="#A9BFC0",
    hatch="#3B2A1F",
    hatch_op="0.62",
    mono=False,
)
MONO = dict(
    ink="#000000", paper="#FFFFFF", fur="#FFFFFF", fur_dk="#FFFFFF", fur_lt="#FFFFFF",
    cream="#FFFFFF", bark="#FFFFFF", bark_dk="#FFFFFF", leaf="#FFFFFF", leaf_dk="#FFFFFF",
    gold="#FFFFFF", silver="#FFFFFF", bronze="#FFFFFF", water="#FFFFFF", hatch="#000000", hatch_op="1", mono=True,
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
    subs, cur = [], []
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
                cur = []
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


def fmt(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def pts_d(pts, closed=True) -> str:
    d = "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)
    return d + ("Z" if closed else "")


def circle_d(x, y, r) -> str:
    k = 0.5523 * r
    return (f"M{fmt(x + r)} {fmt(y)}C{fmt(x + r)} {fmt(y + k)} {fmt(x + k)} {fmt(y + r)} {fmt(x)} {fmt(y + r)}"
            f"C{fmt(x - k)} {fmt(y + r)} {fmt(x - r)} {fmt(y + k)} {fmt(x - r)} {fmt(y)}"
            f"C{fmt(x - r)} {fmt(y - k)} {fmt(x - k)} {fmt(y - r)} {fmt(x)} {fmt(y - r)}"
            f"C{fmt(x + k)} {fmt(y - r)} {fmt(x + r)} {fmt(y - k)} {fmt(x + r)} {fmt(y)}Z")


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


def stroke(d: str, p: dict, w=1.4, color=None, op=None) -> str:
    """A cheap plain stroke (for grain and far detail where a taper is invisible)."""
    o = f' stroke-opacity="{op}"' if op else ""
    return f'<path d="{d}" fill="none" stroke="{color or p["ink"]}" stroke-width="{w}" stroke-linecap="round"{o}/>'


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
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n<title>{title}</title>\n{body}\n</svg>\n')


def _interp(s, pts):
    for (s0, v0), (s1, v1) in zip(pts, pts[1:]):
        if s <= s1:
            t = (s - s0) / (s1 - s0) if s1 > s0 else 0
            t = t * t * (3 - 2 * t)
            return v0 + (v1 - v0) * t
    return pts[-1][1]


# ----------------------------------------------------------------- shared motifs
LEAFLET = "M0 0C8 -7 24 -8 36 0C24 8 8 7 0 0Z"


def leaf_defs(p: dict) -> str:
    """Symbols for cheap far-away foliage (<use> per leaflet)."""
    return (f'<defs><g id="lf"><path d="{LEAFLET}" fill="{p["leaf"]}" stroke="{p["ink"]}" stroke-width="1.7"/>'
            f'<path d="M3 0L26 0" stroke="{p["ink"]}" stroke-width="1"/></g>'
            f'<g id="lfs"><path d="{LEAFLET}" fill="{p["leaf"]}" stroke="{p["ink"]}" stroke-width="1.7"/>'
            f'<path d="M3 0L26 0M10 1L13 5M16 1L19 5M22 1L24 4" stroke="{p["ink"]}" stroke-width="1"/></g></defs>')


def ash_leaf(p: dict, x, y, angle, scale=1.0, seed=2, shade=True, simple=False) -> str:
    """Pinnate ash leaf: a stem with leaflet pairs and a terminal leaflet.
    simple=True uses the <use> symbols from leaf_defs for small, far-away foliage."""
    out = []
    rnd = random.Random(seed)
    stem = "M0 0C30 -4 60 -2 92 0"
    if simple:
        out.append(stroke(stem, p, 2.0))
        for i, t in enumerate((22, 46, 70)):
            for side in (-1, 1):
                ang = side * (-52 + rnd.random() * 10)
                ref = "lfs" if (shade and (i + side) % 2 == 0) else "lf"
                out.append(f'<use xlink:href="#{ref}" transform="translate({t} 0) rotate({fmt(ang)})"/>')
        out.append('<use xlink:href="#lf" transform="translate(92 0) rotate(-2)"/>')
        return f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">' + "".join(out) + "</g>"
    out.append(ink_line(stem, p, 2.2, "in", seed=seed))
    leaflets = []
    for i, t in enumerate((22, 46, 70)):
        for side in (-1, 1):
            ang = side * (-52 + rnd.random() * 10)
            leaflets.append((t, ang, 0.9 + 0.1 * i))
    leaflets.append((92, -2, 1.05))
    for lx, ang, sc in leaflets:
        tr = f'transform="translate({lx} 0) rotate({ang}) scale({sc})"'
        parts = [fill(LEAFLET, p["leaf"])]
        if shade:
            parts.append(hatch([LEAFLET, "M0 -2L40 -2L40 10L0 10Z"], 35, 3.2, p, 0.8, seed=seed + lx, shrink=1.0))
        parts.append(ink_shape(LEAFLET, p, 0.9, 2.4, step=3.0, wobble=0.25, seed=seed + lx, smooth=2))
        parts.append(ink_line("M3 0L30 0", p, 0.9, "in", seed=seed))
        out.append(f"<g {tr}>" + "".join(parts) + "</g>")
    return f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">' + "\n".join(out) + "</g>"


RUNES = {  # elder futhark, unit box: x 0..0.6, y 0..1
    "t": "M.3 1L.3 0M0 .28L.3 0L.6 .28",
    "o": "M0 1L.3 .66L0 .33L.3 0L.6 .33L.3 .66L.6 1",
    "s": "M.5 0L.08 .36L.52 .64L.1 1",
    "k": "M.5 0L.1 .5L.5 1",
    "r": "M.1 1L.1 0L.5 .25L.1 .5L.5 1",
    "a": "M.1 1L.1 0L.5 .25M.1 .3L.5 .55",
}


def rune(p: dict, ch: str, x, y, h, w=None, color=None) -> str:
    d = RUNES[ch]
    sub = re.sub(_NUM.pattern, lambda m: str(float(m.group(0))), d)
    out = []
    for pts, closed in parse(sub):
        pts2 = [(x + px * h, y + py * h) for px, py in pts]
        out.append(ink_line(pts_d(pts2, False), p, w or h * 0.11, "flat", wobble=0.15, seed=int(x + y), color=color))
    return "\n".join(out)


# ----------------------------------------------------------------- skill nodes
NODE_STATES = ("locked", "available", "progress", "bronze", "silver", "gold")


def node(p: dict, x, y, r, state="available", glyph=None, progress=0.4, seed=4) -> str:
    """A skill node: a round rune-stone medallion.  States:
    locked (hatched grey, faint rune) / available (clean stone, bold ring) /
    progress (stone + strength ring, filled fraction) / bronze, silver, gold
    (metal fill; one, two, three rings; gold also gets rays).  Mono keeps the
    hierarchy with ring count, hatch texture and rays only."""
    out = []
    circ = circle_d(x, y, r)
    inner = circle_d(x, y, r * 0.78)
    mono = p["mono"]
    base = {"locked": p["paper"], "available": p["cream"], "progress": p["cream"],
            "bronze": p["bronze"], "silver": p["silver"], "gold": p["gold"]}[state]
    out.append(fill(circ, base))
    hw = max(0.8, r * 0.035)
    if state == "locked":
        out.append(hatch([circ], 45, max(3.0, r * 0.14), p, hw, seed=seed, op="0.45" if not mono else "1"))
    elif state == "bronze":
        out.append(hatch([inner], 45, max(3.0, r * 0.17), p, hw, seed=seed, op="0.35" if not mono else "1"))
    elif state == "silver":
        out.append(hatch([inner], 25, max(3.0, r * 0.17), p, hw, seed=seed, op="0.25" if not mono else "0.9"))
        out.append(hatch([inner], 115, max(3.0, r * 0.34), p, hw * 0.7, seed=seed + 5, op="0.2" if not mono else "0.55"))
    # shadow crescent on the lower-left (not on locked: it should look flat and quiet)
    if state != "locked":
        out.append(hatch([circ, f"M{x - r} {y - r * 0.3}L{x + r * 0.3} {y + r}L{x - r} {y + r}Z"],
                         40, max(2.6, r * 0.11), p, hw, seed=seed + 1))
    # rings
    out.append(ink_shape(circ, p, r * (0.03 if state == "locked" else 0.05), r * (0.08 if state == "locked" else 0.16),
                         step=1.5, wobble=0.3, seed=seed))
    if state in ("available", "progress", "bronze", "silver", "gold"):
        out.append(ink_shape(inner, p, r * 0.035, r * 0.06, step=1.5, wobble=0.25, seed=seed + 2))
    if state in ("silver", "gold"):
        out.append(ink_shape(circle_d(x, y, r * 0.66), p, r * 0.03, r * 0.045, step=1.5, wobble=0.2, seed=seed + 3))
    if state == "gold":
        for k in range(8):
            a = math.radians(k * 45 + 22.5)
            x0, y0 = x + math.cos(a) * r * 1.12, y + math.sin(a) * r * 1.12
            x1, y1 = x + math.cos(a) * r * 1.34, y + math.sin(a) * r * 1.34
            out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}", p, r * 0.08, "in", seed=seed + k, wobble=0))
    if state == "progress":
        # strength ring: the filled fraction heavy, the rest a dotted trace
        R = r * 1.24
        out.append(f'<path d="{circle_d(x, y, R)}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(r * 0.045)}" '
                   f'stroke-dasharray="{fmt(r * 0.08)} {fmt(r * 0.16)}" stroke-linecap="round"/>')
        a0 = -math.pi / 2
        a1 = a0 + math.tau * max(0.02, min(0.999, progress))
        pts = [(x + math.cos(a0 + (a1 - a0) * i / 40) * R, y + math.sin(a0 + (a1 - a0) * i / 40) * R) for i in range(41)]
        out.append(ink_line(pts_d(pts, False), p, r * 0.16, "flat", color=p["leaf_dk"] if not mono else None, wobble=0))
        out.append(ink_line(pts_d(pts, False), p, r * 0.05, "flat", wobble=0.2, seed=seed + 9))
        ex, ey = pts[-1]
        out.append(fill(circle_d(ex, ey, r * 0.11), p["ink"]))
    if state == "available":
        # a little sprouting leaf: this one is ready to start
        out.append(f'<g transform="translate({fmt(x + r * 0.62)} {fmt(y - r * 0.86)}) rotate(-50) scale({fmt(r / 60)})">'
                   + fill(LEAFLET, p["leaf"]) + ink_shape(LEAFLET, p, 1.2, 2.6, step=3, wobble=0.2, smooth=2) + "</g>")
    if glyph:
        gh = r * 0.9
        col = None
        if state == "locked":
            col = p["bark"] if not mono else None
        elif not mono and state in ("available", "progress"):
            col = p["bark_dk"]
        out.append(rune(p, glyph, x - gh * 0.3, y - gh * 0.5, gh, w=gh * (0.07 if state == "locked" else 0.11), color=col))
    return "\n".join(out)


def node_states(p: dict) -> str:
    out = []
    for i, st in enumerate(NODE_STATES):
        out.append(node(p, 70 + i * 120, 70, 40, st, None, progress=0.6, seed=200 + i))
    return "\n".join(out)


# ----------------------------------------------------------------- boughs
def bough(p: dict, d: str, w0, w1, seed=6, bark=True, knuckles=True) -> str:
    """A branch: tapered bark silhouette with knuckles at its bends and grain on the shadow side."""
    rnd = random.Random(seed)
    bumps = []
    if knuckles:
        for k in range(rnd.randint(1, 2)):
            bumps.append((0.25 + rnd.random() * 0.5, 0.18 + rnd.random() * 0.2, 0.05 + rnd.random() * 0.04))

    def prof(s):
        w = w0 + (w1 - w0) * s
        for c, amp, wd in bumps:
            w *= 1 + amp * math.exp(-((s - c) / wd) ** 2)
        return w

    pts = tapered_shape(d, prof, seed=seed)
    out = [fill(pts_d(pts), p["bark"])]
    cl = resample(poly(d), 2.0, False)
    nrm = _normals(cl, False, 2)
    n = len(cl)
    if bark:
        segs = []
        for k in range(3):
            off = -(0.18 + k * 0.17)
            start = rnd.random() * 0.25
            while start < 0.95:
                ln = 0.12 + rnd.random() * 0.2
                i0, i1 = int(start * (n - 1)), int(min(0.999, start + ln) * (n - 1))
                sub = []
                for i in range(i0, i1 + 1, 3):
                    h = prof(i / max(n - 1, 1)) / 2 * off
                    sub.append((cl[i][0] + nrm[i][0] * h, cl[i][1] + nrm[i][1] * h))
                if len(sub) > 2:
                    segs.append(pts_d(sub, False))
                start += ln + 0.08 + rnd.random() * 0.2
        out.append(stroke("".join(segs), p, 1.5, op="0.85"))
        out.append(hatch([pts, _half_poly(cl, nrm, prof, -1)], _dir_angle(cl) + 70, 6, p, 1.0, seed=seed, shrink=2))
    # knuckle creases: short curved strokes across the bough where it swells
    for c, amp, wd in bumps:
        i = int(c * (n - 1))
        h = prof(c) / 2
        for side, f in ((1, 0.55), (-1, 0.55)):
            cx, cy = cl[i][0] + nrm[i][0] * h * f * side, cl[i][1] + nrm[i][1] * h * f * side
            tx, ty = -nrm[i][1], nrm[i][0]
            out.append(ink_line(f"M{fmt(cx - tx * h * 0.5)} {fmt(cy - ty * h * 0.5)}Q{fmt(cx + nrm[i][0] * 3 * side)} "
                                f"{fmt(cy + nrm[i][1] * 3 * side)} {fmt(cx + tx * h * 0.5)} {fmt(cy + ty * h * 0.5)}",
                                p, 1.6, "taper", seed=seed + i))
    out.append(ink_shape(pts_d(pts), p, 1.3, 4.2, seed=seed, smooth=3))
    return "\n".join(out)


def _half_poly(cl, nrm, prof, side):
    m = max(len(cl) - 1, 1)
    a = [(c[0] + n[0] * prof(i / m) * 0.65 * side, c[1] + n[1] * prof(i / m) * 0.65 * side) for i, (c, n) in enumerate(zip(cl, nrm))]
    b = [(c[0] + n[0] * prof(i / m) * 0.12 * side, c[1] + n[1] * prof(i / m) * 0.12 * side) for i, (c, n) in enumerate(zip(cl, nrm))]
    return a + b[::-1]


def _dir_angle(cl):
    dx, dy = cl[-1][0] - cl[0][0], cl[-1][1] - cl[0][1]
    return math.degrees(math.atan2(dy, dx))


# ----------------------------------------------------------------- Tosk (variants a..d)
VARIANTS = {  # small steps toward a friendlier cartoon squirrel, same rendering
    "a": dict(head=1.00, eye=1.00, upright=False, round=0.0),  # just the face fixed
    "b": dict(head=1.08, eye=1.15, upright=False, round=0.0),  # + slightly bigger head and eye
    "c": dict(head=1.08, eye=1.15, upright=True, round=0.0),   # + upright, confident pose
    "d": dict(head=1.16, eye=1.30, upright=True, round=1.0),   # the furthest: rounder, bigger eye
}


def tosk(p: dict, variant="b", scroll=True, branch=True, detail=1.0, bold=1.0) -> str:
    """Ratatosk sitting up on an ash bough, the message scroll in his paws.  512 x 512, facing right."""
    v = VARIANTS[variant]
    sp = 1 / detail
    mono = p["mono"]
    out = []

    def ink(d, wmin, wmax, **kw):
        return ink_shape(d, p, wmin * bold, wmax * bold, **kw)

    def line(d, w, prof="taper", **kw):
        return ink_line(d, p, w * bold, prof, **kw)

    if branch:
        out.append(bough(p, "M6 476C130 452 300 466 506 436", 34, 26, seed=21))
        out.append(ash_leaf(p, 462, 444, -48, 0.9, seed=31))
        out.append(ash_leaf(p, 60, 478, 196, 0.75, seed=32))

    # ---- tail: hugs the back, flares at the top, tip flicking up behind the ears
    up = v["upright"]
    tail_cl = ("M196 414C126 412 76 348 84 264C90 180 148 112 212 92C248 80 268 84 280 68C286 60 290 54 294 48" if up else
               "M184 414C118 410 70 346 78 262C86 178 144 110 208 90C246 78 266 82 278 66C284 58 288 52 292 46")
    tail_prof = lambda s: _interp(s, [(0, 30), (0.12, 60), (0.3, 78), (0.55, 130), (0.72, 122), (0.84, 84), (0.93, 46), (1.0, 8)])
    peaks = []
    tail = tapered_shape(tail_cl, tail_prof, seed=8, fur=0.24, fur_period=26, back=0.6, peaks=peaks)
    tail_d = pts_d(tail)
    out.append(fill(tail_d, p["fur"]))
    shade1 = "M60 440C30 330 70 220 150 180C120 240 126 330 206 410Z"
    shade2 = "M220 70C290 56 330 80 350 140L300 160C300 120 260 90 220 70Z"
    light = "M150 120C180 92 220 80 262 80C236 92 214 104 190 124C160 150 140 180 126 220C120 190 128 150 150 120Z"
    cheap = detail < 0.5
    if not mono and not cheap:
        out.append(clipped(light, tail_d, p["fur_lt"], 0.45))
        out.append(clipped(shade1, tail_d, p["fur_dk"], 0.35))
        out.append(clipped(shade2, tail_d, p["fur_dk"], 0.25))
    out.append(hatch([tail, shade1], -62, 6.5 * sp, p, 1.3, seed=12))
    out.append(hatch([tail, shade2], 30, 6.5 * sp, p, 1.2, seed=14))
    cl = resample(poly(tail_cl), 2.0, False)
    nrm = _normals(cl, False, 2)
    rnd = random.Random(9)
    n = len(cl)
    for k in range(0 if cheap else int(30 * detail)):
        s = 0.08 + rnd.random() * 0.88
        i = int(s * (n - 1))
        side = 1 if rnd.random() < 0.55 else -1
        h = tail_prof(s) / 2
        r0 = 0.15 + rnd.random() * 0.5
        ln = 0.35 + rnd.random() * 0.4
        c, nn = cl[i], nrm[i]
        tx, ty = -nn[1], nn[0]
        x0, y0 = c[0] + nn[0] * h * r0 * side, c[1] + nn[1] * h * r0 * side
        x1, y1 = (c[0] + nn[0] * h * (r0 + ln) * side - tx * h * 0.45, c[1] + nn[1] * h * (r0 + ln) * side - ty * h * 0.45)
        cx, cy = (x0 + x1) / 2 + nn[0] * 5 * side, (y0 + y1) / 2 + nn[1] * 5 * side
        out.append(line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", 1.4 + rnd.random(), "in", seed=k, wobble=0.2))
    out.append(ink(tail_d, 0.9, 3.0, seed=8, smooth=6, wobble=0.3, step=2.5))
    rnd0 = random.Random(19)
    for k, (pt, nn, (tx, ty), s_) in enumerate([] if cheap else peaks):
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
            out.append(line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", 2.0, "in", seed=k * 3 + j, wobble=0.15))

    # ---- hind foot on the bough
    foot = "M200 426C236 428 272 436 302 440C322 444 320 454 298 454C262 456 226 452 204 446Z"
    out.append(fill(foot, p["fur"]))
    out.append(hatch([foot], 15, 5 * sp, p, 1.0, seed=15))
    out.append(ink(foot, 1.0, 3.2, seed=16))
    for tx_ in (276, 288, 300):
        out.append(line(f"M{tx_} 440C{tx_ + 4} 445 {tx_ + 6} 449 {tx_ + 8} 452", 1.4, "in", seed=tx_))

    # ---- body: pear-shaped, sitting on the haunches; upright = chest lifted, back straighter
    if up:
        body = ("M306 198C262 196 228 222 214 262C198 304 192 392 220 430C250 454 308 452 340 420"
                "C360 398 360 330 354 290C350 262 342 226 334 204Z")
        belly = "M340 420C306 450 250 452 222 436C270 420 306 390 332 338C352 360 354 400 340 420Z"
        bshade = "M214 262C198 304 192 392 220 430C250 454 308 452 340 420C296 432 244 420 228 380C212 346 210 300 214 262Z"
        haunch = "M226 432C198 406 200 350 240 326"
        crease = "M300 404C300 388 294 374 282 364"
        thigh = "M210 440C196 404 214 374 250 372C286 370 312 398 308 440Z"
    else:
        body = ("M300 200C258 198 218 224 198 268C178 312 170 392 206 430C240 454 302 452 334 420"
                "C354 400 352 340 346 300C342 270 336 230 330 205Z")
        belly = "M334 420C300 450 246 452 216 436C264 420 300 390 326 338C346 360 348 400 334 420Z"
        bshade = "M198 268C178 312 170 392 206 430C240 454 302 452 334 420C290 432 236 420 220 380C204 346 200 300 198 268Z"
        haunch = "M212 432C184 406 186 350 226 326"
        crease = "M292 404C292 388 286 374 274 364"
        thigh = "M196 440C182 404 200 374 236 372C272 370 300 398 296 440Z"
    out.append(fill(body, p["fur"]))
    out.append(fill(belly, p["cream"]))
    if not mono:
        out.append(clipped(bshade, body, p["fur_dk"], 0.26))
    out.append(hatch([body, bshade], -35, 6.5 * sp, p, 1.2, seed=17))
    out.append(hatch([body, thigh], 25, 9 * sp, p, 1.0, seed=22))
    out.append(line(haunch, 2.8, seed=20))
    out.append(line(crease, 2.0, seed=21))
    out.append(ink(body, 1.2, 4.6, seed=23, smooth=5))

    # ---- scroll held in both paws at the chest
    if scroll:
        dy = -22 if up else 0
        g = [f'<g transform="translate(0 {dy}) rotate(-14 372 300)">']
        sheet = "M340 268L404 268L404 334L340 334Z"
        g.append(fill(sheet, p["cream"]))
        g.append(hatch([sheet, "M340 300L404 300L404 334L340 334Z"], 0, 4.2 * sp, p, 0.8, seed=24, op="0.35"))
        g.append(ink(sheet, 1.0, 3.0, seed=25, wobble=0.3, smooth=2))
        # a few lines of handwriting: neutral squiggles, no script
        for i, yy in enumerate((284, 296, 308, 320)):
            x1 = 396 if i % 2 == 0 else 386
            g.append(line(f"M348 {yy}C356 {yy - 3} 362 {yy + 3} 370 {yy}C378 {yy - 3} 386 {yy + 3} {x1} {yy}", 1.4, "flat",
                          wobble=0.6, seed=50 + i, color=p["bark_dk"] if not mono else None))
        for yy in (268, 334):
            roll = f"M334 {yy - 6}L410 {yy - 6}C416 {yy - 6} 416 {yy + 6} 410 {yy + 6}L334 {yy + 6}C328 {yy + 6} 328 {yy - 6} 334 {yy - 6}Z"
            g.append(fill(roll, p["cream"]))
            g.append(hatch([roll], 90, 3.5 * sp, p, 0.8, seed=26 + yy, op="0.4", shrink=0.5))
            g.append(ink(roll, 1.0, 2.8, seed=27 + yy, wobble=0.2, smooth=2))
        g.append("</g>")
        out += g
        # tidy paws: two small hands gripping the scroll's edge, short arms from the chest
        ps = 1 + 0.15 * v["round"]
        for (px, py), arm in (((344, 286 + dy), f"M334 266C330 274 332 280 338 {284 + dy}"),
                              ((354, 324 + dy), f"M336 298C336 308 340 316 348 {322 + dy}")):
            out.append(line(arm, 7, "flat", color=p["fur"], wobble=0))
            # a little hand: a bean laid along the scroll edge, three fingers curling over
            paw = f"M{px - 9 * ps} {py - 6 * ps}C{px - 4 * ps} {py - 14 * ps} {px + 10 * ps} {py - 12 * ps} {px + 13 * ps} {py - 2 * ps}" \
                  f"C{px + 15 * ps} {py + 6 * ps} {px + 6 * ps} {py + 12 * ps} {px - 4 * ps} {py + 9 * ps}C{px - 12 * ps} {py + 6 * ps} {px - 13 * ps} {py - 1 * ps} {px - 9 * ps} {py - 6 * ps}Z"
            out.append(fill(paw, p["fur"]))
            out.append(hatch([paw, f"M{px - 14 * ps} {py + 2 * ps}L{px + 16 * ps} {py + 2 * ps}L{px + 16 * ps} {py + 14 * ps}L{px - 14 * ps} {py + 14 * ps}Z"], 20, 3.5 * sp, p, 0.8, seed=31))
            out.append(ink(paw, 1.0, 2.8, seed=28, smooth=3, wobble=0.2))
            out.append(line(arm, 2.0, "taper", seed=29))
            for k in range(3):
                fx = px + (k - 1) * 6 * ps + 2
                out.append(line(f"M{fmt(fx)} {fmt(py - 4 * ps)}C{fmt(fx + 2)} {fmt(py + 2 * ps)} {fmt(fx + 1)} {fmt(py + 7 * ps)} {fmt(fx - 2)} {fmt(py + 9 * ps)}", 1.3, "taper", seed=30 + k))

    # ---- head (scaled about the neck for the bigger-head variants)
    hs, es = v["head"], v["eye"]
    pivot = (300, 214)
    out.append(f'<g transform="translate({pivot[0]} {pivot[1]}) scale({hs}) translate({-pivot[0]} {-pivot[1]})">')
    head = ("M284 116C310 96 352 100 372 124C386 138 392 154 400 168C406 178 404 188 394 193"
            "C380 203 362 203 348 210C330 218 304 218 288 206C272 194 268 148 284 116Z")
    if v["round"]:
        head = ("M284 116C312 92 356 98 376 124C390 140 394 156 400 168C406 178 404 188 394 193"
                "C380 205 360 205 346 212C326 220 302 220 286 206C270 192 266 146 284 116Z")
    ear_b = "M290 124C284 104 290 84 304 76C318 84 326 104 322 120Z"
    ear_f = "M334 114C332 94 340 76 354 70C366 78 370 98 362 116Z"
    for ear, inner in ((ear_b, "M298 120C296 106 300 94 305 86C312 94 316 108 316 118Z"),
                       (ear_f, "M342 113C341 100 346 90 353 82C359 90 362 104 357 113Z")):
        out.append(fill(ear, p["fur"]))
        out.append(fill(inner, p["cream"]))
        out.append(hatch([inner], 80, 3.5 * sp, p, 0.9, seed=30, op="0.45"))
        out.append(ink(ear, 1.0, 3.6, seed=33, smooth=3, wobble=0.3))
    for base, tip, ctl, w in (((302, 77), (290, 48), (290, 66), 3.0), ((306, 75), (304, 44), (308, 58), 3.2),
                              ((310, 76), (320, 52), (318, 62), 2.4),
                              ((352, 71), (340, 42), (340, 60), 3.0), ((356, 70), (356, 38), (360, 52), 3.2),
                              ((360, 72), (372, 48), (368, 58), 2.4)):
        out.append(line(f"M{base[0]} {base[1]}Q{ctl[0]} {ctl[1]} {tip[0]} {tip[1]}", w, "in", seed=base[0]))
    out.append(fill(head, p["fur"]))
    muzzle = "M342 164C366 156 394 168 398 184C392 200 362 203 340 196Z"
    out.append(fill(muzzle, p["cream"]))
    hshade = "M288 206C272 194 268 148 284 116C288 160 302 196 348 210C330 218 304 218 288 206Z"
    if not mono:
        out.append(clipped(hshade, head, p["fur_dk"], 0.25))
    out.append(hatch([head, hshade], -50, 5.5 * sp, p, 1.1, seed=34))
    out.append(ink(head, 1.2, 4.4, seed=36, smooth=5))
    # eye: big, round, a touch forward and low on the head, lid heavy at the top, brow gently up
    ex, ey = 356, 156
    rx, ry = 12.5 * es, 10.5 * es
    out.append(f'<ellipse cx="{ex}" cy="{ey}" rx="{fmt(rx)}" ry="{fmt(ry)}" transform="rotate(-6 {ex} {ey})" fill="{p["ink"]}"/>')
    out.append(f'<circle cx="{fmt(ex + rx * 0.3)}" cy="{fmt(ey - ry * 0.35)}" r="{fmt(3.4 * es)}" fill="{p["paper"]}"/>')
    out.append(f'<circle cx="{fmt(ex - rx * 0.4)}" cy="{fmt(ey + ry * 0.35)}" r="{fmt(1.4 * es)}" fill="{p["paper"]}"/>')
    out.append(line(f"M{fmt(ex - rx * 1.05)} {fmt(ey + 1)}C{fmt(ex - rx * 0.6)} {fmt(ey - ry * 1.25)} {fmt(ex + rx * 0.6)} {fmt(ey - ry * 1.3)} {fmt(ex + rx * 1.05)} {fmt(ey - 2)}", 3.2, seed=37))
    out.append(line(f"M{fmt(ex - rx * 1.1)} {fmt(ey - ry * 1.9)}C{fmt(ex - rx * 0.4)} {fmt(ey - ry * 2.5)} {fmt(ex + rx * 0.5)} {fmt(ey - ry * 2.45)} {fmt(ex + rx * 1.1)} {fmt(ey - ry * 1.85)}", 2.4, seed=38))
    # nose, cheerful mouth, whiskers
    out.append(fill("M392 168C400 168 404 174 402 180C399 186 392 186 388 180C386 174 388 169 392 168Z", p["ink"]))
    out.append(line("M395 186C392 194 384 198 376 194", 1.8, seed=39))
    out.append(line("M376 194C372 198 367 198 363 193", 1.5, seed=40))
    for d in ("M380 180C396 178 410 176 424 176", "M378 186C394 188 408 192 420 198", "M376 190C388 198 398 206 408 214"):
        out.append(line(d, 1.5, "in", seed=41, wobble=0.3))
    out.append("</g>")
    return "\n".join(o for o in out if o)


# ----------------------------------------------------------------- icons (head crop of a variant)
def head_crop(p: dict, variant="b", bold=1.4, detail=0.6, rule=True) -> str:
    """Tosk's head and shoulders, plume behind, in the rounded app-icon frame.  512 space."""
    _CLIP[0] += 1
    cid = f"icon{_CLIP[0]}"
    r = 112
    out = [f'<clipPath id="{cid}"><rect x="0" y="0" width="512" height="512" rx="{r}"/></clipPath>']
    out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["paper"]}"/>')
    if not p["mono"]:
        out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["cream"]}" fill-opacity="0.6"/>')
    sc = 1.7
    hx, hy = 338, 162  # head centre in figure space -> (304, 262)
    out.append(f'<g clip-path="url(#{cid})"><g transform="translate({fmt(304 - sc * hx)} {fmt(262 - sc * hy)}) scale({sc})">'
               f'{tosk(p, variant, scroll=False, branch=False, detail=detail, bold=bold)}</g></g>')
    if rule:
        out.append(f'<rect x="22" y="22" width="468" height="468" rx="{r - 20}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(5 * bold / 1.4)}"/>')
        out.append(f'<rect x="34" y="34" width="444" height="444" rx="{r - 30}" fill="none" stroke="{p["ink"]}" stroke-width="2"/>')
    return "\n".join(out)


def icon(p: dict) -> str:
    return head_crop(p, "b", bold=1.4, detail=0.6)


def icon_small(p: dict) -> str:
    """Dedicated small-size variant: heavier ink, no hatching, single rule."""
    out = head_crop(p, "b", bold=2.6, detail=0.001, rule=False)
    return out + f'\n<rect x="18" y="18" width="476" height="476" rx="96" fill="none" stroke="{p["ink"]}" stroke-width="10"/>'


def icon_figure(p: dict, bold=1.0) -> str:
    """Mark for the logo: the (b) head crop."""
    return head_crop(p, "b", bold=1.2, detail=0.6, rule=False)


# ----------------------------------------------------------------- wordmark (Gelasio Bold outlines)
FONT = HERE / "fonts" / "Gelasio-Bold.ttf"


def wordmark_glyphs(text="tosk", size=188, kern=None):
    """Outline the wordmark with fontTools from the local Gelasio Bold TTF.
    Returns (list of (path d, advance), units scale) or None when the font is absent."""
    if not FONT.exists():
        return None
    try:
        from fontTools.ttLib import TTFont
        from fontTools.pens.svgPathPen import SVGPathPen
        from fontTools.pens.transformPen import TransformPen
    except ImportError:
        return None
    f = TTFont(str(FONT))
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    upm = f["head"].unitsPerEm
    sc = size / upm
    out = []
    x = 0.0
    kern = kern or {}
    for i, ch in enumerate(text):
        gname = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        tp = TransformPen(pen, (sc, 0, 0, -sc, x, 0))
        gs[gname].draw(tp)
        adv = gs[gname].width * sc
        out.append((pen.getCommands(), x, adv))
        x += adv + kern.get(text[i:i + 2], 0) * sc
    return out, x


def wordmark(p: dict, touched=False, x0=0, y0=0, size=188) -> str:
    """The lowercase 'tosk' wordmark: Gelasio Bold outlines (the look the owner liked),
    with light optical kerning.  touched=True adds the one custom detail: an ash leaflet
    sprouting from the top of the k's ascender."""
    res = wordmark_glyphs("tosk", size, kern={"to": -30, "os": -10, "sk": -10})
    out = [f'<g transform="translate({x0} {y0})">']
    if res is None:
        out.append(f'<text x="0" y="0" font-family="Gelasio, Georgia, serif" font-weight="700" font-size="{size}" '
                   f'letter-spacing="-4" fill="{p["ink"]}">tosk</text>')
        out.append(f'<text x="0" y="{size * 0.22}" font-family="Georgia, serif" font-size="{size * 0.09}" fill="{p["ink"]}" '
                   f'fill-opacity="0.6">(live text: fonts/Gelasio-Bold.ttf not present)</text>')
        width = size * 2.1
    else:
        glyphs, width = res
        out.append(f'<path d="{"".join(g[0] for g in glyphs)}" fill="{p["ink"]}"/>')
        if touched:
            kx = glyphs[3][1]
            out.append(f'<g transform="translate({fmt(kx + size * 0.19)} {fmt(-size * 0.74)}) rotate(-62) scale({fmt(size / 150)})">'
                       + fill(LEAFLET, p["leaf"]) + ink_shape(LEAFLET, p, 1.2, 2.6, step=3, wobble=0.2, smooth=2)
                       + ink_line("M3 0L28 0", p, 0.9, "in") + "</g>")
    out.append("</g>")
    return "\n".join(out), width


def logo(p: dict, touched=False) -> str:
    out = [f'<g transform="translate(10 20) scale(0.5)">{icon_figure(p)}</g>']
    wm, width = wordmark(p, touched, 296, 206)
    out.append(wm)
    out.append(ash_leaf(p, 310, 236, -6, 0.78, seed=70))
    return "\n".join(out)


def wordmark_svg(p: dict, touched=False) -> str:
    wm, width = wordmark(p, touched, 20, 170, 200)
    return svg(int(width + 60), 230, wm, "tosk wordmark")


# ----------------------------------------------------------------- Yggdrasil
def yggdrasil(p: dict) -> str:
    """The course tree: an ancient storybook ash, three roots, knuckled boughs, skill nodes.  800 x 1100."""
    out = [leaf_defs(p)]
    sp = 1.0
    STEP[0] = 4.8

    # ---- roots (three), sinuous and knuckled, the trunk flares into them
    roots = (("M336 866C316 900 270 904 236 930C200 958 210 996 160 1004C120 1010 90 996 70 1030", 96, 12),
             ("M398 870C380 910 420 940 404 972C396 990 398 1000 396 1010", 66, 22),
             ("M464 866C490 900 540 904 574 930C612 958 600 996 650 1004C690 1010 716 998 740 1030", 96, 12),
             ("M300 890C250 900 200 930 150 936", 34, 8),
             ("M500 890C540 904 580 930 620 936", 30, 8))
    for d, w0, w1 in roots:
        out.append(bough(p, d, w0, w1, seed=83 + w0 + w1))
    for d in ("M236 930C216 960 190 980 160 990", "M574 930C590 960 606 980 640 990",
              "M396 1000C376 1012 350 1016 330 1026", "M150 936C130 946 110 950 90 950", "M620 936C640 950 660 952 690 956"):
        out.append(ink_line(d, p, 7, "in", color=p["bark"], wobble=0))
        out.append(ink_line(d, p, 2.0, "in", seed=84))

    # ---- trunk: wide, gnarled, leaning a little, flaring into the roots
    trunk = ("M296 884C324 800 344 700 348 600C352 520 346 440 362 380C372 346 386 320 398 296"
             "C414 320 430 348 438 386C454 450 446 540 454 620C462 720 482 800 506 884"
             "C456 900 346 900 296 884Z")
    out.append(fill(trunk, p["bark"]))
    tshade = "M296 884C324 800 344 700 348 600C352 520 346 440 362 380C372 346 386 320 398 296C384 400 384 620 392 884Z"
    if not p["mono"]:
        out.append(clipped(tshade, trunk, p["bark_dk"], 0.3))
    out.append(hatch([trunk, tshade], 84, 9.5 * sp, p, 1.3, seed=90, curve=6))
    out.append(hatch([trunk, "M296 884C312 820 330 760 340 700L380 700C376 760 380 820 392 884Z"], 30, 8, p, 1.1, seed=91))
    out.append(hatch([trunk, "M438 300C442 400 448 600 456 760L506 884L400 884L400 300Z"], 96, 13, p, 1.0, seed=92, op="0.4", curve=4))
    rnd = random.Random(93)
    ridges = []
    for k in range(18):
        x = 320 + rnd.random() * 160
        y0 = 320 + rnd.random() * 500
        ln = 50 + rnd.random() * 120
        dx = (x - 400) * 0.1
        ridges.append(f"M{fmt(x)} {fmt(y0)}C{fmt(x + dx - 6)} {fmt(y0 + ln * 0.4)} {fmt(x + dx * 1.5 + 6)} {fmt(y0 + ln * 0.7)} {fmt(x + dx * 2)} {fmt(y0 + ln)}")
    out.append(stroke("".join(ridges), p, 1.6, op="0.9"))
    knot = "M426 650C440 638 458 644 460 660C458 678 442 686 428 676C418 668 416 658 426 650Z"
    out.append(fill(knot, p["bark_dk"] if not p["mono"] else p["paper"]))
    out.append(hatch([knot], 60, 3.5, p, 1.0, seed=94))
    out.append(hatch([knot, "M416 660L470 660L470 690L416 690Z"], -30, 3.5, p, 1.0, seed=194))
    out.append(ink_shape(knot, p, 1.2, 3.2, seed=95, smooth=3))
    out.append(ink_shape(trunk, p, 1.4, 5.2, seed=96, smooth=6, wobble=1.6))
    # ---- boughs and nodes: the course path, foundations at the bottom, the crown still ahead
    boughs = [  # (path, w0, w1, node x, y, state, glyph)
        ("M372 772C330 800 270 770 220 776C190 780 164 798 146 806", 42, 12, 146, 806, "gold", None),
        ("M436 702C480 724 540 690 590 708C620 718 640 730 654 740", 40, 12, 654, 740, "silver", None),
        ("M362 604C320 630 250 580 190 590C160 594 136 598 118 604", 38, 12, 118, 604, "bronze", None),
        ("M438 524C480 540 540 486 600 488C626 488 644 484 656 480", 38, 12, 656, 480, "progress", None),
        ("M382 432C340 420 310 376 270 356C250 346 236 332 228 324", 38, 12, 228, 324, "available", None),
        ("M418 418C460 400 500 350 550 326C570 316 584 304 594 296", 38, 12, 594, 296, "locked", None),
        ("M400 322C390 286 412 256 398 226C394 212 398 202 400 194", 34, 14, 400, 190, "locked", None),
        ("M400 300C370 270 330 262 300 232", 20, 6, None, None, None, None),
        ("M404 300C436 270 476 258 506 236", 20, 6, None, None, None, None),
        ("M330 640C290 650 250 630 200 660", 16, 5, None, None, None, None),   # side limbs that carry the canopy
        ("M470 560C530 580 580 560 630 580", 16, 5, None, None, None, None),
        ("M340 500C300 480 250 470 200 450", 16, 5, None, None, None, None),
        ("M460 640C520 650 560 620 610 630", 16, 5, None, None, None, None),
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
        0: [(196, 738, -150, 0.85), (168, 826, 160, 0.8), (262, 742, -120, 0.7), (110, 840, 175, 0.7), (90, 770, -170, 0.7)],
        1: [(596, 660, -25, 0.85), (626, 752, 30, 0.8), (518, 670, -60, 0.7), (696, 756, 15, 0.7), (710, 700, -10, 0.7)],
        2: [(186, 554, -160, 0.85), (150, 632, 165, 0.8), (270, 566, -120, 0.7), (76, 622, -178, 0.7), (70, 560, 170, 0.7)],
        3: [(584, 466, -20, 0.85), (626, 522, 25, 0.8), (512, 474, -60, 0.7), (696, 494, 12, 0.7), (710, 440, -20, 0.7)],
        4: [(272, 342, -140, 0.85), (252, 410, 150, 0.8), (304, 372, -110, 0.7), (190, 312, -160, 0.7), (150, 350, 175, 0.7), (190, 270, -130, 0.7)],
        5: [(540, 310, -40, 0.85), (586, 364, 20, 0.8), (488, 342, -70, 0.7), (634, 290, -12, 0.7), (650, 340, 10, 0.7), (600, 250, -50, 0.7)],
        6: [(334, 226, -140, 0.85), (466, 212, -40, 0.85), (280, 206, -165, 0.75), (526, 196, -20, 0.75),
            (330, 150, -110, 0.7), (470, 148, -70, 0.7), (396, 140, -90, 0.6)],
        7: [(300, 232, -150, 0.8), (320, 250, -175, 0.7), (250, 250, -140, 0.7), (262, 200, -120, 0.7), (230, 290, -165, 0.7)],
        8: [(506, 236, -30, 0.8), (486, 254, -5, 0.7), (556, 254, -40, 0.7), (544, 200, -60, 0.7), (580, 290, -15, 0.7)],
        9: [(200, 660, 170, 0.75), (240, 640, -150, 0.7), (160, 690, 165, 0.7), (150, 640, -175, 0.7)],
        10: [(630, 580, 10, 0.75), (590, 556, -30, 0.7), (670, 600, 15, 0.7), (670, 540, -5, 0.7)],
        11: [(200, 450, -170, 0.75), (240, 462, 160, 0.7), (150, 430, -160, 0.7), (150, 480, 175, 0.7)],
        12: [(610, 630, 5, 0.75), (560, 618, -25, 0.7), (660, 660, 20, 0.7), (660, 600, -10, 0.7)],
    }
    for i, (d, w0, w1, nx, ny, state, glyph) in enumerate(boughs):
        out.append(bough(p, d, w0, w1, seed=100 + i, bark=(i < 7)))
        for td, tw0, tw1 in twigs.get(i, []):
            out.append(bough(p, td, tw0, tw1, seed=110 + i, bark=False, knuckles=False))
        for lx, ly, la, ls in leaves.get(i, []):
            out.append(ash_leaf(p, lx, ly, la, ls, seed=120 + i + int(lx), shade=True, simple=True))
    # Tosk himself, scampering down the lower-left bough with a message for the roots
    STEP[0] = 7.0
    out.append(f'<g transform="translate(486 596) scale(0.22)">{tosk(p, "b", scroll=True, branch=False, detail=0.3)}</g>')
    STEP[0] = 4.8
    for i, (d, w0, w1, nx, ny, state, glyph) in enumerate(boughs):
        if nx is not None:
            out.append(node(p, nx, ny, 32, state, glyph, progress=0.55, seed=130 + i))

    STEP[0] = 1.0
    return "\n".join(o for o in out if o)


# ----------------------------------------------------------------- branch tile
def branch_tile(p: dict) -> str:
    """A fork between skill nodes for the course map.  400 x 400.
    Bottom: gold (done well); left: in progress; right: available."""
    out = [leaf_defs(p)]
    out.append(bough(p, "M200 352C216 310 190 270 200 222", 40, 32, seed=150))
    out.append(bough(p, "M200 226C196 180 120 170 92 104", 30, 12, seed=151))
    out.append(bough(p, "M200 226C210 170 290 160 310 112", 30, 12, seed=152))
    out.append(bough(p, "M150 166C134 150 124 150 108 158", 9, 4, seed=153, bark=False, knuckles=False))
    out.append(bough(p, "M254 158C266 138 276 134 294 132", 9, 4, seed=154, bark=False, knuckles=False))
    out.append(bough(p, "M196 290C180 282 170 280 160 284", 8, 3, seed=161, bark=False, knuckles=False))
    out.append(ash_leaf(p, 108, 158, 196, 0.85, seed=155))
    out.append(ash_leaf(p, 294, 132, -28, 0.85, seed=156))
    out.append(ash_leaf(p, 160, 284, 200, 0.7, seed=157))
    out.append(node(p, 200, 352, 40, "gold", None, seed=158))
    out.append(node(p, 92, 100, 34, "progress", None, progress=0.4, seed=159))
    out.append(node(p, 310, 108, 34, "available", None, seed=160))
    return "\n".join(out)


# ----------------------------------------------------------------- sheet
def sheet_html(font_ok: bool) -> str:
    pal = [(k, v) for k, v in COLOR.items() if isinstance(v, str) and v.startswith("#")]
    sw = "".join(f'<div class="sw"><div class="chip" style="background:{v}"></div><b>{k}</b><span>{v}</span></div>' for k, v in pal)
    states = "".join(f"<span>{s}</span>" for s in NODE_STATES)
    font_note = ("Wordmark: Gelasio Bold outlines (SIL OFL)." if font_ok else
                 "Wordmark: fonts/Gelasio-Bold.ttf not present yet, so live text is shown; the generator outlines it automatically once the TTF is in place.")
    labels = {"a": "a: face fixed", "b": "b: + bigger head and eye", "c": "c: + upright pose", "d": "d: furthest (rounder)"}
    vrow = "".join(f'<figure class="card"><img src="tosk-{k}.svg" width="270"><figcaption>{labels[k]}</figcaption></figure>' for k in "abcd")
    mrow = "".join(f'<figure class="card w"><img src="tosk-{k}-mono.svg" width="270"><figcaption>{k}, e-ink</figcaption></figure>' for k in "abcd")
    hrow = "".join(f'<div><img src="head-{k}.svg" width="96"> <img src="head-{k}.svg" width="48"> <img src="head-{k}-mono.svg" width="48"><br>{k}</div>' for k in "abcd")
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk: storybook ink, round 2</title>
<style>
body{{margin:0;padding:24px 32px;background:#F7F0E2;color:#3B2A1F;font-family:Georgia,'Palatino Linotype',serif;width:1540px}}
h1{{margin:0 0 2px;font-size:40px;letter-spacing:-1px}} h2{{font-size:17px;margin:14px 0 8px;font-weight:normal;opacity:.75;border-bottom:1px solid #3B2A1F44}}
p.sub{{margin:0 0 6px;font-size:14px;opacity:.8}}
.row{{display:flex;gap:14px;align-items:flex-start;flex-wrap:wrap;margin-bottom:14px}}
figure{{margin:0}}
.card{{background:#FBF7EE;border:1.5px solid #3B2A1F;border-radius:14px;padding:10px 12px 6px;box-shadow:3px 4px 0 #3B2A1F22}}
.card.w{{background:#fff}} .card img{{display:block}} .card figcaption{{text-align:center;font-size:12px;margin-top:5px;opacity:.85}}
.v1 .card{{opacity:.85;padding:6px 8px 4px}} .v1 figcaption{{font-size:11px}}
.icons{{display:flex;gap:16px;align-items:flex-end}} .icons div{{text-align:center;font-size:11px}} .icons img{{display:inline-block;vertical-align:bottom}}
.pal{{display:flex;gap:7px;flex-wrap:wrap}} .sw{{width:62px;font-size:10px;text-align:center}} .sw b{{display:block;margin-top:3px}}
.chip{{height:40px;border-radius:8px;border:1px solid #3B2A1F55}}
.states{{display:flex;justify-content:space-around;font-size:11px;width:670px;margin:2px auto 0}}
.note{{font-size:11px;opacity:.7;text-align:center}}
</style></head><body>
<h1>tosk <span style="font-size:18px;opacity:.6">storybook ink, round 2</span></h1>
<p class="sub">Ratatosk, the messenger squirrel. Tapered pen lines, hatching, warm watercolour. Colour and e-ink side by side.</p>

<h2>Tosk: v1 and four small steps toward a friendlier cartoon squirrel</h2>
<div class="row v1">
 <figure class="card"><img src="v1/tosk.svg" width="270"><figcaption>v1 (previous round)</figcaption></figure>{vrow}
</div>
<div class="row">
 <figure class="card w"><img src="v1/tosk-mono.svg" width="270"><figcaption>v1, e-ink</figcaption></figure>{mrow}
</div>
<div class="row">
 <figure class="card"><div class="icons">{hrow}</div><figcaption>Each variant's head as an icon crop: 96, 48, 48 e-ink</figcaption></figure>
 <figure class="card"><div class="icons">
   <div><img src="icon.svg" width="128"><br>icon (face b) 128</div><div><img src="icon.svg" width="64"><br>64</div>
   <div><img src="icon-48.svg" width="96"><br>icon-48 at 96</div><div><img src="icon-48.svg" width="48"><br>48</div><div><img src="icon-48.svg" width="32"><br>32</div>
   <div><img src="icon-48-mono.svg" width="48"><br>48 e-ink</div><div><img src="icon-mono.svg" width="64"><br>64 e-ink</div>
   <div><img src="v1/icon.svg" width="48"><br>v1 48</div></div>
   <figcaption>App icon: default (face b) and the dedicated small variant</figcaption></figure>
</div>

<h2>Logo and wordmark</h2>
<div class="row">
 <figure class="card"><img src="logo.svg" width="380"><figcaption>logo, plain</figcaption></figure>
 <figure class="card"><img src="logo-touched.svg" width="380"><figcaption>logo, touched (leaflet on the k)</figcaption></figure>
 <figure class="card"><img src="wordmark.svg" width="230"><img src="wordmark-mono.svg" width="230" style="background:#fff;margin-top:6px"><figcaption>wordmark.svg, wordmark-mono.svg</figcaption></figure>
 <figure class="card"><img src="v1/logo.svg" width="300"><figcaption>v1 logo (live Georgia text)</figcaption></figure>
</div>
<div class="note" style="text-align:left">{font_note}</div>

<h2>Yggdrasil, the course tree, and the map pieces</h2>
<div class="row">
 <figure class="card"><img src="yggdrasil.svg" width="370"><figcaption>Yggdrasil: the course tree</figcaption></figure>
 <figure class="card w"><img src="yggdrasil-mono.svg" width="370"><figcaption>Yggdrasil, e-ink</figcaption></figure>
 <div style="width:700px">
  <figure class="card"><img src="node-states.svg" width="670"><div class="states">{states}</div>
   <img src="node-states-mono.svg" width="670" style="background:#fff;margin-top:6px"><div class="states">{states}</div>
   <figcaption>Skill node states, colour and e-ink</figcaption></figure>
  <div class="row" style="margin-top:14px"><figure class="card"><img src="branch-tile.svg" width="210"><figcaption>Map branch tile</figcaption></figure>
  <figure class="card w"><img src="branch-tile-mono.svg" width="210"><figcaption>e-ink</figcaption></figure>
  <figure class="card v1"><img src="v1/yggdrasil.svg" width="150"><figcaption>v1 tree</figcaption></figure></div>
  <figure class="card"><div class="pal">{sw}</div><figcaption>Palette</figcaption></figure>
 </div>
</div>
</body></html>
"""


def main():
    files = {
        "icon": (512, 512, icon, "tosk app icon"),
        "icon-48": (512, 512, icon_small, "tosk app icon, small-size variant"),
        "yggdrasil": (800, 1100, yggdrasil, "Yggdrasil, the course tree"),
        "branch-tile": (400, 400, branch_tile, "Map branch tile: a fork between skills"),
        "node-states": (720, 140, node_states, "Skill node states"),
    }
    for k in "abcd":
        files[f"tosk-{k}"] = (512, 512, (lambda q, k=k: tosk(q, k)), f"Tosk, variant {k}")
        files[f"head-{k}"] = (512, 512, (lambda q, k=k: head_crop(q, k)), f"Tosk head crop, variant {k}")
    for name, (w, h, fn, title) in files.items():
        (HERE / f"{name}.svg").write_text(svg(w, h, fn(COLOR), title), encoding="utf-8")
        (HERE / f"{name}-mono.svg").write_text(svg(w, h, fn(MONO), title + " (e-ink)"), encoding="utf-8")
    (HERE / "logo.svg").write_text(svg(760, 300, logo(COLOR), "tosk logo"), encoding="utf-8")
    (HERE / "logo-touched.svg").write_text(svg(760, 300, logo(COLOR, True), "tosk logo (touched)"), encoding="utf-8")
    (HERE / "wordmark.svg").write_text(wordmark_svg(COLOR), encoding="utf-8")
    (HERE / "wordmark-mono.svg").write_text(wordmark_svg(MONO), encoding="utf-8")
    (HERE / "wordmark-touched.svg").write_text(wordmark_svg(COLOR, True), encoding="utf-8")
    (HERE / "sheet.html").write_text(sheet_html(FONT.exists()), encoding="utf-8")
    for f in sorted(HERE.glob("*.svg")):
        print(f"{f.name:24s} {f.stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
