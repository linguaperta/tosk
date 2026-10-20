"""tosk brand art kit: Tosk the red squirrel (storybook ink, variant c) and the map pieces.

Promoted from app/assets/brand/explore/storybook/make_storybook.py (the archive keeps the
explorations).  Expressive pen lines (filled, tapered strokes whose weight follows the
light), procedural hatching for shading, warm muted watercolour washes.  Everything is
drawn once from Bezier silhouettes and rendered twice: colour and pure black/white
(e-ink).  Pure Python; fontTools is needed only for the wordmark (Gelasio Bold outlines),
Pillow and headless Edge only for the PNG exports.

Run from anywhere:
  python app/tool/brand/make_tosk.py          -> app/assets/brand/*.svg (+ branch-style.json)
  python app/tool/brand/make_tosk.py png      -> also the PNG exports (png/, icon/) via headless Edge
  python app/tool/brand/make_tosk.py sheet    -> also docs/brand-sheet.png from app/tool/brand/sheet.html
  python app/tool/brand/make_tosk.py all      -> everything

The canvas convention: Tosk lives in a 512 x 512 figure space, facing right, light from
the top right; the neck pivot is NECK = (300, 214).  Every pose reuses the same head,
plume, limb and paw helpers so the character stays consistent.
"""
from __future__ import annotations

import json
import math
import os
import random
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "assets" / "brand"

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
    gold="#E3B23C",       # warm yellow: polished, radiant
    silver="#ADB8C3",     # cool blue-grey: shiny
    bronze="#9C5A30",     # copper brown: matte
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


# ================================================================= Tosk: shared parts
FONT = OUT / "fonts" / "Gelasio-Bold.ttf"  # SIL OFL; outlined by wordmark_glyphs()
NECK = (300, 214)                  # head pivot in figure space (512 x 512, facing right)
HEAD_SCALE, EYE_SCALE = 1.08, 1.15  # variant c: slightly bigger head and eye than v1
HEAD_CENTRE = (341, 158)           # the eye/face centre after HEAD_SCALE (for crops)


def ellipse_d(x, y, rx, ry) -> str:
    k = 0.5523
    return (f"M{fmt(x + rx)} {fmt(y)}C{fmt(x + rx)} {fmt(y + k * ry)} {fmt(x + k * rx)} {fmt(y + ry)} {fmt(x)} {fmt(y + ry)}"
            f"C{fmt(x - k * rx)} {fmt(y + ry)} {fmt(x - rx)} {fmt(y + k * ry)} {fmt(x - rx)} {fmt(y)}"
            f"C{fmt(x - rx)} {fmt(y - k * ry)} {fmt(x - k * rx)} {fmt(y - ry)} {fmt(x)} {fmt(y - ry)}"
            f"C{fmt(x + k * rx)} {fmt(y - ry)} {fmt(x + rx)} {fmt(y - k * ry)} {fmt(x + rx)} {fmt(y)}Z")


def tosk_head(p: dict, expr=None, bold=1.0, detail=1.0, transform="") -> str:
    """Tosk's head (variant c), facing right, drawn in figure space around NECK.
    expr: eye 'open' | 'closed' | 'happy'; gaze (dx, dy) in -1..1 moves the pupil highlight;
    lid 0..1 lowers a heavy upper lid; mouth 'smile' | 'grin' | 'soft'; brow (px, + = lower);
    whisk scales the whiskers.  transform is applied outside the head's own scale."""
    e = dict(eye="open", gaze=(0.0, 0.0), lid=0.0, mouth="smile", brow=0.0, whisk=1.0)
    e.update(expr or {})
    sp = 1 / detail
    mono = p["mono"]
    cheap = detail < 0.5
    out = []

    def ink(d, wmin, wmax, **kw):
        return ink_shape(d, p, wmin * bold, wmax * bold, **kw)

    def line(d, w, prof="taper", **kw):
        return ink_line(d, p, w * bold, prof, **kw)

    px, py = NECK
    out.append(f'<g transform="{transform} translate({px} {py}) scale({HEAD_SCALE}) translate({-px} {-py})">')
    head = ("M284 116C310 96 352 100 372 124C386 138 392 154 400 168C406 178 404 188 394 193"
            "C380 203 362 203 348 210C330 218 304 218 288 206C272 194 268 148 284 116Z")
    ear_b = "M290 124C284 104 290 84 304 76C318 84 326 104 322 120Z"
    ear_f = "M334 114C332 94 340 76 354 70C366 78 370 98 362 116Z"
    for ear, inner in ((ear_b, "M298 120C296 106 300 94 305 86C312 94 316 108 316 118Z"),
                       (ear_f, "M342 113C341 100 346 90 353 82C359 90 362 104 357 113Z")):
        out.append(fill(ear, p["fur"]))
        out.append(fill(inner, p["cream"]))
        if not cheap:
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
    if not mono and not cheap:
        out.append(clipped(hshade, head, p["fur_dk"], 0.25))
    if not cheap:
        out.append(hatch([head, hshade], -50, 5.5 * sp, p, 1.1, seed=34))
    out.append(ink(head, 1.2, 4.4, seed=36, smooth=5))
    # ---- eye: big and round, a touch forward and low, lid heavy at the top, brow gently up
    ex, ey = 356, 156
    es = EYE_SCALE
    rx, ry = 12.5 * es, 10.5 * es
    gx, gy = e["gaze"]
    if e["eye"] == "open":
        out.append(f'<ellipse cx="{ex}" cy="{ey}" rx="{fmt(rx)}" ry="{fmt(ry)}" transform="rotate(-6 {ex} {ey})" fill="{p["ink"]}"/>')
        hx, hy = ex + rx * (0.3 + 0.35 * gx), ey - ry * (0.35 - 0.55 * gy)
        out.append(f'<circle cx="{fmt(hx)}" cy="{fmt(hy)}" r="{fmt(3.4 * es)}" fill="{p["paper"]}"/>')
        out.append(f'<circle cx="{fmt(ex - rx * 0.4 + 0.3 * rx * gx)}" cy="{fmt(ey + ry * 0.35 + 0.3 * ry * gy)}" r="{fmt(1.4 * es)}" fill="{p["paper"]}"/>')
        if e["lid"] > 0:
            ly = ey - ry + 2 * ry * e["lid"]
            cap = f"M{fmt(ex - rx - 2)} {fmt(ey - ry - 3)}L{fmt(ex + rx + 2)} {fmt(ey - ry - 3)}L{fmt(ex + rx + 2)} {fmt(ly)}L{fmt(ex - rx - 2)} {fmt(ly)}Z"
            out.append(clipped(cap, ellipse_d(ex, ey, rx + 0.6, ry + 0.6), p["fur"]))
            out.append(line(f"M{fmt(ex - rx * 1.05)} {fmt(ly + 1)}C{fmt(ex - rx * 0.5)} {fmt(ly - 2)} {fmt(ex + rx * 0.5)} {fmt(ly - 2.5)} {fmt(ex + rx * 1.05)} {fmt(ly - 1)}", 3.2, seed=37))
        else:
            out.append(line(f"M{fmt(ex - rx * 1.05)} {fmt(ey + 1)}C{fmt(ex - rx * 0.6)} {fmt(ey - ry * 1.25)} {fmt(ex + rx * 0.6)} {fmt(ey - ry * 1.3)} {fmt(ex + rx * 1.05)} {fmt(ey - 2)}", 3.2, seed=37))
    elif e["eye"] == "closed":
        out.append(line(f"M{fmt(ex - rx * 1.05)} {fmt(ey - 3)}C{fmt(ex - rx * 0.5)} {fmt(ey + ry * 0.9)} {fmt(ex + rx * 0.5)} {fmt(ey + ry * 0.9)} {fmt(ex + rx * 1.05)} {fmt(ey - 2)}", 3.0, seed=37))
        for k, (dx, dy) in enumerate(((0.95, 0.35), (0.7, 0.75))):
            out.append(line(f"M{fmt(ex + rx * dx)} {fmt(ey + ry * dy)}L{fmt(ex + rx * (dx + 0.3))} {fmt(ey + ry * (dy + 0.4))}", 1.8, "in", seed=60 + k))
    else:  # happy: a squinting smile-eye
        out.append(line(f"M{fmt(ex - rx * 1.05)} {fmt(ey + 3)}C{fmt(ex - rx * 0.5)} {fmt(ey - ry * 1.15)} {fmt(ex + rx * 0.5)} {fmt(ey - ry * 1.15)} {fmt(ex + rx * 1.05)} {fmt(ey + 2)}", 3.4, seed=37))
    b = e["brow"]
    out.append(line(f"M{fmt(ex - rx * 1.1)} {fmt(ey - ry * 1.9 + b)}C{fmt(ex - rx * 0.4)} {fmt(ey - ry * 2.5 + b)} {fmt(ex + rx * 0.5)} {fmt(ey - ry * 2.45 + b)} {fmt(ex + rx * 1.1)} {fmt(ey - ry * 1.85 + b)}", 2.4, seed=38))
    # ---- nose, mouth, whiskers
    out.append(fill("M392 168C400 168 404 174 402 180C399 186 392 186 388 180C386 174 388 169 392 168Z", p["ink"]))
    if e["mouth"] == "smile":
        out.append(line("M395 186C392 194 384 198 376 194", 1.8, seed=39))
        out.append(line("M376 194C372 198 367 198 363 193", 1.5, seed=40))
    elif e["mouth"] == "grin":
        grin = "M397 187C395 205 374 211 362 195C374 191 386 189 397 187Z"
        out.append(fill(grin, p["ink"]))
        out.append(fill("M389 201C390 208 378 210 372 203C378 201 384 200 389 201Z", p["fur_lt"] if not p["mono"] else p["paper"]))
        out.append(line("M362 196C370 190 386 188 398 186", 1.6, seed=39))
    else:  # soft: a small content curve
        out.append(line("M394 186C391 192 385 195 378 193", 1.8, seed=39))
    wk = e["whisk"]
    for x0, y0, pts in ((380, 180, (16, -2, 30, -4, 44, -4)), (378, 186, (16, 2, 30, 6, 42, 12)), (376, 190, (12, 8, 22, 16, 32, 24))):
        c1x, c1y, c2x, c2y, exx, eyy = pts
        out.append(line(f"M{x0} {y0}C{fmt(x0 + c1x * wk)} {fmt(y0 + c1y * wk)} {fmt(x0 + c2x * wk)} {fmt(y0 + c2y * wk)} {fmt(x0 + exx * wk)} {fmt(y0 + eyy * wk)}", 1.5, "in", seed=41, wobble=0.3))
    out.append("</g>")
    return "\n".join(out)


def plume(p: dict, cl: str, prof, shades, light=None, seed=8, detail=1.0, bold=1.0, fur=0.24, period=26, back=0.6) -> str:
    """The big tail.  cl: centerline; prof(s) -> full width; shades: [(wash poly, hatch angle, opacity)]
    on the shadow side; light: a highlight wash poly.  Fur clumps along the edges, loose fur
    strokes inside, tufts at the clump tips."""
    sp = 1 / detail
    mono = p["mono"]
    cheap = detail < 0.5
    out = []
    peaks = []
    tail = tapered_shape(cl, prof, seed=seed, fur=fur, fur_period=period, back=back, peaks=peaks)
    tail_d = pts_d(tail)
    out.append(fill(tail_d, p["fur"]))
    if not mono and not cheap:
        if light:
            out.append(clipped(light, tail_d, p["fur_lt"], 0.45))
        for sd, _ang, op in shades:
            out.append(clipped(sd, tail_d, p["fur_dk"], op))
    for i, (sd, ang, _op) in enumerate(shades):
        out.append(hatch([tail, sd], ang, 6.5 * sp, p, 1.3 - 0.1 * i, seed=12 + 2 * i))
    cl_pts = resample(poly(cl), 2.0, False)
    nrm = _normals(cl_pts, False, 2)
    rnd = random.Random(9)
    n = len(cl_pts)
    for k in range(0 if cheap else int(30 * detail)):
        s = 0.08 + rnd.random() * 0.88
        i = int(s * (n - 1))
        side = 1 if rnd.random() < 0.55 else -1
        h = prof(s) / 2
        r0 = 0.15 + rnd.random() * 0.5
        ln = 0.35 + rnd.random() * 0.4
        c, nn = cl_pts[i], nrm[i]
        tx, ty = -nn[1], nn[0]
        x0, y0 = c[0] + nn[0] * h * r0 * side, c[1] + nn[1] * h * r0 * side
        x1, y1 = (c[0] + nn[0] * h * (r0 + ln) * side - tx * h * 0.45, c[1] + nn[1] * h * (r0 + ln) * side - ty * h * 0.45)
        cx, cy = (x0 + x1) / 2 + nn[0] * 5 * side, (y0 + y1) / 2 + nn[1] * 5 * side
        out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", p, (1.4 + rnd.random()) * bold, "in", seed=k, wobble=0.2))
    out.append(ink_shape(tail_d, p, 0.9 * bold, 3.0 * bold, seed=seed, smooth=6, wobble=0.3, step=2.5))
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
            out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}Q{fmt(cx)} {fmt(cy)} {fmt(x1)} {fmt(y1)}", p, 2.0 * bold, "in", seed=k * 3 + j, wobble=0.15))
    return "\n".join(out)


C_TAIL = "M196 414C126 412 76 348 84 264C90 180 148 112 212 92C248 80 268 84 280 68C286 60 290 54 294 48"
C_TAIL_PROF = lambda s: _interp(s, [(0, 30), (0.12, 60), (0.3, 78), (0.55, 130), (0.72, 122), (0.84, 84), (0.93, 46), (1.0, 8)])
C_TAIL_SHADES = [("M60 440C30 330 70 220 150 180C120 240 126 330 206 410Z", -62, 0.35),
                 ("M220 70C290 56 330 80 350 140L300 160C300 120 260 90 220 70Z", 30, 0.25)]
C_TAIL_LIGHT = "M150 120C180 92 220 80 262 80C236 92 214 104 190 124C160 150 140 180 126 220C120 190 128 150 150 120Z"


def shifted(d: str, dx: float, dy: float) -> str:
    """Translate an absolute M/L/C/Q/Z path by (dx, dy) by rewriting its numbers."""
    nums = []

    def rep(m):
        v = float(m.group(0))
        nums.append(v)
        return fmt(v + (dx if len(nums) % 2 == 1 else dy))

    return re.sub(_NUM.pattern, rep, d)


def limb(p: dict, cl: str, w0, w1, seed=40, bold=1.0, detail=1.0, shade=None, angle=20) -> str:
    """An arm or leg: tapered fur silhouette along a centerline (ends hidden under body/paw)."""
    pts = tapered_shape(cl, lambda s: w0 + (w1 - w0) * s, seed=seed)
    d = pts_d(pts)
    out = [fill(d, p["fur"])]
    if shade and detail >= 0.5:
        out.append(hatch([pts, shade], angle, 5.5 / detail, p, 1.0, seed=seed))
    out.append(ink_shape(d, p, 1.0 * bold, 3.2 * bold, seed=seed, smooth=3))
    return "\n".join(out)


def paw(p: dict, x, y, rot=0.0, scale=1.0, fingers="curl", bold=1.0, detail=1.0, seed=28) -> str:
    """A small hand (local space: a bean ~26 wide; 'curl' fingers fold over the bottom edge,
    'spread' fingers fan out of the top, 'point' extends an index finger to the right)."""
    bean = "M-9 -6C-4 -14 10 -12 13 -2C15 6 6 12 -4 9C-12 6 -13 -1 -9 -6Z"
    out = [f'<g transform="translate({fmt(x)} {fmt(y)}) rotate({fmt(rot)}) scale({fmt(scale)})">']
    if fingers == "spread":
        for k, (fx, ang) in enumerate(((-7, -36), (0, -8), (7, 20))):
            a = math.radians(ang)
            x1, y1 = fx + math.sin(a) * 13, -6 - math.cos(a) * 13
            out.append(limb(p, f"M{fx} -2L{fmt(x1)} {fmt(y1)}", 7.5, 5, seed=seed + 10 + k, bold=bold, detail=0.1))
    elif fingers == "point":
        out.append(limb(p, "M4 -4C14 -8 22 -10 32 -12", 7, 4.5, seed=seed + 10, bold=bold, detail=0.1))
    out.append(fill(bean, p["fur"]))
    if detail >= 0.5:
        out.append(hatch([bean, "M-14 2L16 2L16 14L-14 14Z"], 20, 3.5 / detail, p, 0.8, seed=seed))
    out.append(ink_shape(bean, p, 1.0 * bold, 2.8 * bold, seed=seed, smooth=3, wobble=0.2))
    if fingers in ("curl", "point"):
        ks = range(3) if fingers == "curl" else range(2)
        for k in ks:
            fx = (k - 1) * 6 + 2 - (4 if fingers == "point" else 0)
            out.append(ink_line(f"M{fx} -4C{fx + 2} 2 {fx + 1} 7 {fx - 2} 9", p, 1.3 * bold, "taper", seed=seed + k))
    out.append("</g>")
    return "\n".join(out)


def scroll_sheet(p: dict, dx=0.0, dy=0.0, bold=1.0, detail=1.0, rot=-14) -> str:
    """The message scroll: a sheet with neutral handwriting squiggles and two rolled ends."""
    sp = 1 / detail
    mono = p["mono"]

    def ink(d, wmin, wmax, **kw):
        return ink_shape(d, p, wmin * bold, wmax * bold, **kw)

    g = [f'<g transform="translate({fmt(dx)} {fmt(dy)}) rotate({rot} 372 300)">']
    sheet = "M340 268L404 268L404 334L340 334Z"
    g.append(fill(sheet, p["cream"]))
    g.append(hatch([sheet, "M340 300L404 300L404 334L340 334Z"], 0, 4.2 * sp, p, 0.8, seed=24, op="0.35"))
    g.append(ink(sheet, 1.0, 3.0, seed=25, wobble=0.3, smooth=2))
    for i, yy in enumerate((284, 296, 308, 320)):
        x1 = 396 if i % 2 == 0 else 386
        g.append(ink_line(f"M348 {yy}C356 {yy - 3} 362 {yy + 3} 370 {yy}C378 {yy - 3} 386 {yy + 3} {x1} {yy}", p, 1.4 * bold, "flat",
                          wobble=0.6, seed=50 + i, color=p["bark_dk"] if not mono else None))
    for yy in (268, 334):
        roll = f"M334 {yy - 6}L410 {yy - 6}C416 {yy - 6} 416 {yy + 6} 410 {yy + 6}L334 {yy + 6}C328 {yy + 6} 328 {yy - 6} 334 {yy - 6}Z"
        g.append(fill(roll, p["cream"]))
        g.append(hatch([roll], 90, 3.5 * sp, p, 0.8, seed=26 + yy, op="0.4", shrink=0.5))
        g.append(ink(roll, 1.0, 2.8, seed=27 + yy, wobble=0.2, smooth=2))
    g.append("</g>")
    return "\n".join(g)


def c_body(p: dict, bold=1.0, detail=1.0) -> str:
    """Variant c's sitting body: pear-shaped on the haunches, chest lifted, back straight."""
    sp = 1 / detail
    mono = p["mono"]
    body = ("M306 198C262 196 228 222 214 262C198 304 192 392 220 430C250 454 308 452 340 420"
            "C360 398 360 330 354 290C350 262 342 226 334 204Z")
    belly = "M340 420C306 450 250 452 222 436C270 420 306 390 332 338C352 360 354 400 340 420Z"
    bshade = "M214 262C198 304 192 392 220 430C250 454 308 452 340 420C296 432 244 420 228 380C212 346 210 300 214 262Z"
    thigh = "M210 440C196 404 214 374 250 372C286 370 312 398 308 440Z"
    out = [fill(body, p["fur"]), fill(belly, p["cream"])]
    if not mono:
        out.append(clipped(bshade, body, p["fur_dk"], 0.26))
    if detail >= 0.5:
        out.append(hatch([body, bshade], -35, 6.5 * sp, p, 1.2, seed=17))
        out.append(hatch([body, thigh], 25, 9 * sp, p, 1.0, seed=22))
    out.append(ink_line("M226 432C198 406 200 350 240 326", p, 2.8 * bold, "taper", seed=20))
    out.append(ink_line("M300 404C300 388 294 374 282 364", p, 2.0 * bold, "taper", seed=21))
    out.append(ink_shape(body, p, 1.2 * bold, 4.6 * bold, seed=23, smooth=5))
    return "\n".join(out)


def hind_foot(p: dict, d: str, toes, bold=1.0, detail=1.0, seed=16) -> str:
    out = [fill(d, p["fur"])]
    if detail >= 0.5:
        out.append(hatch([d], 15, 5 / detail, p, 1.0, seed=seed - 1))
    out.append(ink_shape(d, p, 1.0 * bold, 3.2 * bold, seed=seed))
    for tx_, ty_ in toes:
        out.append(ink_line(f"M{tx_} {ty_}C{tx_ + 4} {ty_ + 5} {tx_ + 6} {ty_ + 9} {tx_ + 8} {ty_ + 12}", p, 1.4 * bold, "in", seed=tx_))
    return "\n".join(out)


C_FOOT = ("M200 426C236 428 272 436 302 440C322 444 320 454 298 454C262 456 226 452 204 446Z", ((276, 440), (288, 440), (300, 440)))


def c_bough(p: dict) -> str:
    return "\n".join((bough(p, "M6 476C130 452 300 466 506 436", 34, 26, seed=21),
                      ash_leaf(p, 462, 444, -48, 0.9, seed=31), ash_leaf(p, 60, 478, 196, 0.75, seed=32)))


def c_paws_on_scroll(p: dict, dx=0.0, dy=0.0, bold=1.0, detail=1.0, which=(0, 1)) -> str:
    """Two small hands gripping the scroll's edge, short arms from the chest."""
    out = []
    arms = (((344, 286), "M334 266C330 274 332 280 338 284"), ((354, 324), "M336 298C336 308 340 316 348 322"))
    for i in which:
        (px, py), arm = arms[i]
        arm = shifted(arm, dx, dy)
        out.append(ink_line(arm, p, 7 * bold, "flat", color=p["fur"], wobble=0))
        out.append(paw(p, px + dx, py + dy, 0, 1.0, "curl", bold, detail, seed=28 + i))
        out.append(ink_line(arm, p, 2.0 * bold, "taper", seed=29))
    return "\n".join(out)


# ================================================================= Tosk: poses
def tosk(p: dict, variant="c", scroll_=True, branch=True, detail=1.0, bold=1.0, scroll=None) -> str:
    """Variant c: Ratatosk sitting up on an ash bough, the message scroll in his paws.  512 x 512."""
    if scroll is not None:
        scroll_ = scroll
    out = []
    if branch:
        out.append(c_bough(p))
    out.append(plume(p, C_TAIL, C_TAIL_PROF, C_TAIL_SHADES, C_TAIL_LIGHT, seed=8, detail=detail, bold=bold))
    out.append(hind_foot(p, C_FOOT[0], C_FOOT[1], bold, detail))
    out.append(c_body(p, bold, detail))
    if scroll_:
        out.append(scroll_sheet(p, 0, -22, bold, detail))
        out.append(c_paws_on_scroll(p, 0, -22, bold, detail))
    out.append(tosk_head(p, None, bold, detail))
    return "\n".join(o for o in out if o)


def tosk_pointing(p: dict, detail=1.0, bold=1.0) -> str:
    """Pointing / explaining: the sitting pose, the far paw keeps the scroll, the near arm
    points off to the right, one eyebrow up."""
    out = [c_bough(p),
           plume(p, C_TAIL, C_TAIL_PROF, C_TAIL_SHADES, C_TAIL_LIGHT, seed=8, detail=detail, bold=bold),
           hind_foot(p, C_FOOT[0], C_FOOT[1], bold, detail),
           c_body(p, bold, detail),
           scroll_sheet(p, -28, 12, bold, detail, rot=-10),
           c_paws_on_scroll(p, -28, 12, bold, detail, which=(0,)),
           limb(p, "M330 262C366 258 402 244 438 226", 27, 18, seed=44, bold=bold, detail=detail,
                shade="M330 268L440 240L440 260L330 290Z", angle=-10),
           paw(p, 442, 223, -24, 1.18, "point", bold, detail, seed=45),
           tosk_head(p, dict(brow=-3, whisk=0.8), bold, detail, transform="rotate(-4 300 214)")]
    return "\n".join(o for o in out if o)


def tosk_celebrate(p: dict, detail=1.0, bold=1.0) -> str:
    """Lesson complete: up on his hind feet, both arms thrown up, a big grin, tail up in a
    flourish, leaflets and twinkles in the air."""
    tail_cl = "M212 420C124 418 66 352 76 262C86 184 134 134 180 104C210 86 234 78 252 62C262 54 268 48 272 42"
    prof = lambda s: _interp(s, [(0, 30), (0.12, 60), (0.3, 80), (0.55, 128), (0.72, 116), (0.84, 76), (0.93, 40), (1.0, 6)])
    shades = [("M40 440C10 330 50 220 130 180C100 240 106 330 186 410Z", -62, 0.35),
              ("M190 70C260 56 300 80 320 140L270 160C270 120 230 90 190 70Z", 30, 0.25)]
    light = "M120 120C150 92 190 80 232 80C206 92 184 104 160 124C130 150 110 180 96 220C90 190 98 150 120 120Z"
    sp = 1 / detail
    mono = p["mono"]
    out = [c_bough(p), plume(p, tail_cl, prof, shades, light, seed=8, detail=detail, bold=bold)]
    # far hind foot peeking out behind, then the near one
    out.append(hind_foot(p, "M214 420C232 420 254 426 266 432C274 436 272 446 258 446C240 444 222 440 210 436Z", ((244, 434),), bold, detail, seed=18))
    body = ("M298 212C260 210 234 236 226 280C218 330 220 392 238 428C262 452 318 452 342 426"
            "C356 400 354 332 348 286C342 252 332 224 326 210Z")
    belly = "M342 426C318 452 262 452 238 428C280 426 318 400 336 336C350 364 352 400 342 426Z"
    bshade = "M226 280C218 330 220 392 238 428C262 452 318 452 342 426C300 436 252 424 240 384C228 346 224 310 226 280Z"
    out.append(hind_foot(p, "M238 428C272 428 306 436 328 440C346 444 344 454 324 454C292 456 258 452 240 446Z", ((300, 440), (312, 440), (322, 441)), bold, detail))
    out.append(fill(body, p["fur"]))
    out.append(fill(belly, p["cream"]))
    if not mono:
        out.append(clipped(bshade, body, p["fur_dk"], 0.26))
    if detail >= 0.5:
        out.append(hatch([body, bshade], -35, 6.5 * sp, p, 1.2, seed=17))
    out.append(ink_line("M244 430C222 404 226 350 262 330", p, 2.8 * bold, "taper", seed=20))
    out.append(ink_shape(body, p, 1.2 * bold, 4.6 * bold, seed=23, smooth=5))
    # arms up: the far one first (over the tail, under the head), then the near one
    out.append(limb(p, "M270 252C236 238 212 196 206 150", 27, 18, seed=46, bold=bold, detail=detail,
                    shade="M200 150L230 150L250 260L210 260Z", angle=70))
    out.append(paw(p, 204, 139, -20, 1.2, "spread", bold, detail, seed=47))
    out.append(limb(p, "M338 256C392 250 432 212 454 152", 27, 18, seed=48, bold=bold, detail=detail,
                    shade="M420 150L470 150L470 270L390 270Z", angle=70))
    out.append(paw(p, 458, 141, 22, 1.2, "spread", bold, detail, seed=49))
    out.append(tosk_head(p, dict(mouth="grin", brow=-4, gaze=(0.0, -0.1), whisk=0.8), bold, detail, transform="rotate(-8 300 214)"))
    # tossed leaflets and twinkles
    for (lx, ly, la, ls) in ((150, 78, 30, 0.9), (420, 54, -25, 0.85), (482, 112, 60, 0.75), (116, 150, -70, 0.7)):
        out.append(f'<g transform="translate({lx} {ly}) rotate({la}) scale({ls})">' + fill(LEAFLET, p["leaf"])
                   + ink_shape(LEAFLET, p, 1.2, 2.6, step=3, wobble=0.2, smooth=2) + ink_line("M3 0L28 0", p, 0.9, "in") + "</g>")
    for (tx, ty, tr) in ((186, 44, 12), (396, 28, 10), (486, 72, 8), (90, 110, 7), (470, 190, 6)):
        out.append(twinkle(p, tx, ty, tr, bold=bold))
    return "\n".join(o for o in out if o)


def tosk_reading(p: dict, detail=1.0, bold=1.0) -> str:
    """Thinking / reading: sitting, head bowed over an open book held in both paws."""
    mono = p["mono"]
    sp = 1 / detail
    out = [c_bough(p),
           plume(p, C_TAIL, C_TAIL_PROF, C_TAIL_SHADES, C_TAIL_LIGHT, seed=8, detail=detail, bold=bold),
           hind_foot(p, C_FOOT[0], C_FOOT[1], bold, detail),
           c_body(p, bold, detail)]
    # arms from the chest down to the book, drawn before it (the paws come after)
    for arm in ("M330 272C324 292 326 318 338 338", "M342 296C346 318 362 334 392 344"):
        out.append(ink_line(arm, p, 7 * bold, "flat", color=p["fur"], wobble=0))
        out.append(ink_line(arm, p, 2.0 * bold, "taper", seed=29))
    # the open book: a bark cover, two cream pages meeting at the spine, squiggle text
    g = ['<g transform="rotate(-10 372 326)">']
    cover = "M324 298C344 288 362 292 372 304C382 292 402 288 422 298L422 358C402 348 382 350 372 360C362 350 344 348 324 358Z"
    g.append(fill(cover, p["bark_dk"] if not mono else p["paper"]))
    if mono:
        g.append(hatch([cover], 60, 3.5, p, 0.8, seed=71))
    g.append(ink_shape(cover, p, 1.0 * bold, 3.0 * bold, seed=70, smooth=2, wobble=0.3))
    pl = "M330 300C346 292 362 294 372 304L372 354C362 346 346 346 330 352Z"
    pr = "M372 304C382 294 400 292 416 300L416 352C400 346 382 346 372 354Z"
    for i, pg in enumerate((pl, pr)):
        g.append(fill(pg, p["cream"]))
        g.append(hatch([pg, "M326 332L420 332L420 360L326 360Z"], 0, 4 * sp, p, 0.8, seed=72 + i, op="0.35"))
        g.append(ink_shape(pg, p, 0.9 * bold, 2.4 * bold, seed=74 + i, smooth=2, wobble=0.25))
    g.append(ink_line("M372 304L372 354", p, 2.2 * bold, "flat", seed=76))
    for i, yy in enumerate((312, 322, 332)):
        for x0, x1 in ((338, 364), (380, 406)):
            x1 = x1 - (6 if i == 2 else 0)
            g.append(ink_line(f"M{x0} {yy}C{x0 + 6} {yy - 3} {x0 + 12} {yy + 3} {x0 + 18} {yy}C{x0 + 22} {yy - 2} {x0 + 26} {yy + 2} {x1} {yy}", p, 1.3 * bold, "flat",
                              wobble=0.6, seed=80 + i, color=p["bark_dk"] if not mono else None))
    g.append("</g>")
    out.append("\n".join(g))
    out.append(paw(p, 338, 346, 10, 1.0, "curl", bold, detail, seed=28))
    out.append(paw(p, 400, 346, -6, 1.0, "curl", bold, detail, seed=29))
    out.append(tosk_head(p, dict(gaze=(0.15, 0.6), lid=0.26, mouth="soft", brow=1, whisk=0.9), bold, detail, transform="rotate(14 300 214)"))
    return "\n".join(o for o in out if o)


def tosk_sleeping(p: dict, detail=1.0, bold=1.0) -> str:
    """Nothing due today: curled up on the bough, the tail pulled over him like a blanket,
    eye shut, three z's drifting up."""
    mono = p["mono"]
    sp = 1 / detail
    out = [bough(p, "M6 444C130 424 300 438 506 414", 36, 28, seed=21),
           ash_leaf(p, 470, 424, -40, 0.9, seed=31), ash_leaf(p, 52, 448, 198, 0.75, seed=32)]
    body = "M150 404C112 372 118 296 178 258C236 224 322 228 364 266C398 298 398 372 358 404C300 432 200 436 150 404Z"
    belly = "M358 404C300 432 200 436 150 404C220 412 300 404 348 356C368 372 368 392 358 404Z"
    bshade = "M150 404C112 372 118 296 178 258C154 300 150 350 184 392C210 418 280 420 358 404C300 432 200 436 150 404Z"
    out.append(fill(body, p["fur"]))
    out.append(fill(belly, p["cream"]))
    if not mono:
        out.append(clipped(bshade, body, p["fur_dk"], 0.26))
    if detail >= 0.5:
        out.append(hatch([body, bshade], -35, 6.5 * sp, p, 1.2, seed=17))
    out.append(ink_line("M196 406C176 380 180 340 214 320", p, 2.6 * bold, "taper", seed=20))
    out.append(ink_shape(body, p, 1.2 * bold, 4.6 * bold, seed=23, smooth=5))
    # a hind foot tucked out at the bottom right, under the chin's side
    out.append(hind_foot(p, "M318 410C340 410 362 412 378 416C392 420 390 430 372 430C348 430 330 426 318 422Z", ((352, 418), (364, 418)), bold, detail, seed=18))
    # the tail wraps over the body
    tail_cl = "M150 400C92 390 78 312 124 272C170 232 250 234 304 256C334 268 354 292 358 318"
    prof = lambda s: _interp(s, [(0, 26), (0.1, 58), (0.3, 88), (0.55, 98), (0.75, 82), (0.9, 52), (1.0, 12)])
    shades = [("M100 420C60 320 120 240 240 240C200 260 160 300 180 400Z", -62, 0.35),
              ("M300 300C340 280 380 300 380 340L330 340C330 320 316 310 300 300Z", 30, 0.25)]
    light = "M110 290C150 230 240 220 320 250C260 240 190 250 150 300Z"
    out.append(plume(p, tail_cl, prof, shades, light, seed=8, detail=detail, bold=bold, period=24))
    # paws tucked under the chin, then the head resting on them
    out.append(paw(p, 398, 392, 6, 1.0, "curl", bold, detail, seed=28))
    out.append(paw(p, 418, 386, -2, 0.95, "curl", bold, detail, seed=29))
    cx, cy = HEAD_CENTRE
    out.append(tosk_head(p, dict(eye="closed", mouth="soft", brow=3, whisk=0.85), bold, detail,
                         transform=f"translate({fmt(372 - cx)} {fmt(346 - cy)}) rotate(24 {cx} {cy}) scale(0.98) "
                                   f"translate({fmt(cx * 0.02 / 0.98)} {fmt(cy * 0.02 / 0.98)})"))
    for (zx, zy, zs) in ((428, 262, 11), (452, 230, 15), (482, 190, 19)):
        out.append(ink_line(f"M{zx} {zy}L{zx + zs} {zy}L{zx} {zy + zs}L{zx + zs} {zy + zs}", p, zs * 0.17 * bold, "flat", wobble=0.2, seed=zx))
    return "\n".join(o for o in out if o)


POSES = {"tosk": tosk, "tosk-celebrate": tosk_celebrate, "tosk-reading": tosk_reading,
         "tosk-sleeping": tosk_sleeping, "tosk-pointing": tosk_pointing}


# ================================================================= twinkles and skill nodes
def twinkle_d(x, y, r, rot=0.0) -> str:
    """A four-point twinkle star with pinched (concave) sides."""
    pts = []
    for k in range(4):
        a = math.radians(rot + k * 90)
        pts.append((x + math.cos(a) * r, y + math.sin(a) * r))
    d = f"M{fmt(pts[0][0])} {fmt(pts[0][1])}"
    for k in range(4):
        nx, ny = pts[(k + 1) % 4]
        d += f"Q{fmt(x)} {fmt(y)} {fmt(nx)} {fmt(ny)}"
    return d + "Z"


def twinkle(p: dict, x, y, r, rot=0.0, bold=1.0, fill_color=None) -> str:
    d = twinkle_d(x, y, r, rot)
    return (fill(d, fill_color or p["paper"]) + "\n" +
            f'<path d="{d}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(max(0.8, r * 0.11) * bold)}" stroke-linejoin="round"/>')


NODE_STATES = ("locked", "available", "progress", "bronze", "silver", "gold")

# Sparkle spec per tier, in units of the node radius r.  angle: degrees, 0 = right, positive =
# clockwise on screen (SVG y down).  Mirrored into branch-style.json for the Dart painter.
SPARKLE = {
    "bronze": dict(twinkles=[(-52, 1.24, 0.17, 0)], rays=0, dots=[]),
    "silver": dict(twinkles=[(-50, 1.30, 0.24, 0), (-152, 1.26, 0.14, 15)], rays=0, dots=[(-100, 1.42, 0.035)]),
    "gold": dict(twinkles=[(-48, 1.46, 0.30, 0), (-150, 1.40, 0.19, 15), (-98, 1.58, 0.14, 10), (-6, 1.52, 0.12, 0)],
                 rays=7, dots=[(-122, 1.62, 0.04), (-72, 1.66, 0.035), (-176, 1.52, 0.03)], laurel=True),
}
# Gold's rays: 7 long ones over the top half (the laurel takes the bottom), a short one between each pair.
RAYS = dict(count=7, start_deg=22.5, arc_deg=[-180, 0], r0=1.12, r1=1.36, short_r1=1.24, width=0.08)
# Gold's laurel: two sprigs along the lower rim (the left one; the right mirrors it).
LAUREL = dict(from_deg=100, to_deg=172, radius=1.12, leaves=4, size=0.34)
# Decay cracks the stone: hairline cracks from the rim from `start` decay on (up to `max`), a chip
# knocked out of the rim at each crack level in `chips_at`, a fragment breaking off from level 0.5.
CRACKS = dict(start=0.2, max=4, chips_at=[0.3, 0.6, 0.85], width=[0.035, 0.07],
              rule="level = (decay - start) / (1 - start); cracks = min(max, 1 + floor(level * max)); "
                   "length 0.3 + 0.6 level r, zig-zag steps of 0.1-0.17 r; a side branch from level 0.35")
NODE_SPEC = dict(
    rings={"locked": 1, "available": 2, "progress": 2, "bronze": 2, "silver": 3, "gold": 3},
    outer_ring_width=[0.05, 0.16], locked_ring_width=[0.03, 0.08], inner_ring=dict(radius=0.78, width=[0.035, 0.06]),
    third_ring=dict(radius=0.66, width=[0.03, 0.045]),
    shadow_crescent=dict(angle=40, spacing=0.11, width=0.035, side="lower-left"),
    hatch={"locked": dict(angle=45, spacing=0.14, opacity=0.45),
           "silver": dict(angle=25, spacing=0.17, opacity=0.25, inner=True, cross=dict(angle=115, spacing=0.34, opacity=0.2))},
    texture={"bronze": dict(kind="stipple", note="matte: ink dots on the inner disc (0.72 r), about 1.1 per px of r (10-44), "
                                                 "0.03 r each, opacity 0.5; a darker patina low on the left; no gleam"),
             "silver": dict(kind="shine", bands=[[0.3, 0.1], [0.52, 0.042]],
                            note="two bright bands perpendicular to the light, offset toward it by 0.3 / 0.52 r, half widths "
                                 "0.1 / 0.042 r, clipped to 0.74 r; paper-white in mono (they cut through the hatching)"),
             "gold": dict(kind="polished", note="a lighter centre (0.62 r), the gleam arc, rays and the laurel")},
    gleam=dict(tiers=["gold"], radius=0.56, arc_deg=[-120, -40], width=0.07, opacity=0.75, colour="paper"),
    progress_ring=dict(radius=1.24, track_width=0.045, track_dash=[0.08, 0.16], fill_width=0.16, fill_colour="leaf_dk", cap_dot=0.11),
    available_sprout=dict(at=[0.62, -0.86], rotate=-50, scale="r/60", shape="LEAFLET"),
    cracks=CRACKS,
    extent=1.75,
)


def _ray_angles():
    """Gold's ray angles (degrees), long and short alternating: long ones spread over arc_deg."""
    a0, a1 = RAYS["arc_deg"]
    step = (a1 - a0) / RAYS["count"]
    long_ = [a0 + (k + 0.5) * step for k in range(RAYS["count"])]
    out = []
    for k, a in enumerate(long_):
        out.append(a)
        if k + 1 < len(long_):
            out.append((a + long_[k + 1]) / 2)
    return out


def _polar(x, y, a, d):
    return (x + math.cos(a) * d, y + math.sin(a) * d)


def _rot(px, py, a):
    return (px * math.cos(a) - py * math.sin(a), px * math.sin(a) + py * math.cos(a))


def crack_pattern(level: float, seed: int):
    """The cracks of a decaying node at crack level 0..1, in unit coordinates (the same rules as
    the app's CrackPattern; the randomness differs).  Returns (lines, chips, shards): lines run
    from the rim (or a chip) inward; a chip is (cut polygon, broken edge); a shard a polygon."""
    if level <= 0:
        return [], [], []
    rnd = random.Random(seed * 7 + 13)
    n = min(CRACKS["max"], 1 + int(level * CRACKS["max"]))
    n_chips = min(n, sum(1 for t in CRACKS["chips_at"] if level >= t))
    a0 = rnd.random() * math.tau
    lines, chips, shards = [], [], []
    for k in range(n):
        a = a0 + k * math.tau / n + (rnd.random() - 0.5) * 0.9
        start = _polar(0, 0, a, 0.99)
        if k < n_chips:
            d = 0.17 + rnd.random() * 0.09 + 0.05 * level
            j1 = _polar(0, 0, a - d * 0.45, 0.86 + rnd.random() * 0.04)
            j2 = _polar(0, 0, a + (rnd.random() - 0.5) * d * 0.3, 0.79 - 0.04 * level)
            j3 = _polar(0, 0, a + d * 0.5, 0.85 + rnd.random() * 0.05)
            r0, r1 = _polar(0, 0, a - d, 0.995), _polar(0, 0, a + d, 0.995)
            chips.append(([_polar(0, 0, a - d * 1.05, 1.4), r0, j1, j2, j3, r1, _polar(0, 0, a + d * 1.05, 1.4)], [r0, j1, j2, j3, r1]))
            start = j2
            if k == 0 and level >= 0.5:
                piece = [_polar(0, 0, a - d + 2 * d * i / 6, 1.0) for i in range(7)] + [j3, j2, j1]
                cx = sum(q[0] for q in piece) / len(piece)
                cy = sum(q[1] for q in piece) / len(piece)
                ox, oy = _polar(0, 0, a, 0.2 + 0.08 * level)
                oy += 0.06
                turn = (1 if rnd.random() < 0.5 else -1) * (0.3 + 0.2 * level)
                shards.append([(cx + ox + rx, cy + oy + ry) for rx, ry in
                               (_rot((qx - cx) * 0.8, (qy - cy) * 0.8, turn) for qx, qy in piece)])
        hx, hy = _rot(-math.cos(a), -math.sin(a), (rnd.random() - 0.5) * 0.6)
        length = min(1.05, 0.3 + 0.6 * level + rnd.random() * 0.12)
        pts = [start]
        dx, dy = hx, hy
        px, py = start
        went = 0.0
        while went < length:
            dx, dy = _rot(dx * 0.6 + hx * 0.4, dy * 0.6 + hy * 0.4, (rnd.random() - 0.5) * 1.1)
            m = math.hypot(dx, dy) or 1
            dx, dy = dx / m, dy / m
            step = 0.1 + rnd.random() * 0.07
            nx, ny = px + dx * step, py + dy * step
            if math.hypot(nx, ny) > 0.95:
                break
            pts.append((nx, ny))
            px, py = nx, ny
            went += step
        if len(pts) >= 2:
            lines.append(pts)
        if level > 0.35 and len(pts) >= 3:
            bx, by = pts[1 + rnd.randrange(len(pts) - 2)]
            ddx, ddy = _rot(hx, hy, (1 if rnd.random() < 0.5 else -1) * (0.7 + rnd.random() * 0.4))
            branch = [(bx, by)]
            for _ in range(2 + (1 if level > 0.7 else 0)):
                ddx, ddy = _rot(ddx, ddy, (rnd.random() - 0.5) * 0.9)
                s = 0.08 + rnd.random() * 0.06
                nx, ny = bx + ddx * s, by + ddy * s
                if math.hypot(nx, ny) > 0.95:
                    break
                branch.append((nx, ny))
                bx, by = nx, ny
            if len(branch) >= 2:
                lines.append(branch)
    return lines, chips, shards


def laurel(p: dict, x, y, r, seed=1) -> str:
    """Gold's laurel: two sprigs of leaflets hugging the lower rim."""
    out = []
    a0, a1 = math.radians(LAUREL["from_deg"]), math.radians(LAUREL["to_deg"])
    R = r * LAUREL["radius"]
    sc = LAUREL["size"] * r / 36
    for side in (1, -1):
        def pt(a):
            px, py = math.cos(a) * R, math.sin(a) * R
            return (x + px * side, y + py)
        stem = [pt(a0 + (a1 - a0) * i / 14) for i in range(15)]
        out.append(ink_line(pts_d(stem, False), p, max(0.8, r * 0.05), "taper", seed=seed, wobble=0))
        leaves = []
        for i in range(LAUREL["leaves"]):
            a = a0 + (a1 - a0) * (i + 0.45) / LAUREL["leaves"]
            tx, ty = -math.sin(a), math.cos(a)
            ox, oy = math.cos(a), math.sin(a)
            s = 1 if i % 2 == 0 else -1
            lx, ly = tx * math.cos(0.6) + ox * s * math.sin(0.6), ty * math.cos(0.6) + oy * s * math.sin(0.6)
            leaves.append((pt(a), math.degrees(math.atan2(ly, lx * side))))
        leaves.append((pt(a1), math.degrees(math.atan2(math.cos(a1), -math.sin(a1) * side))))
        for (lx, ly), deg in leaves:
            out.append(f'<g transform="translate({fmt(lx)} {fmt(ly)}) rotate({fmt(deg)}) scale({fmt(sc)})">'
                       + fill(LEAFLET, p["leaf"])
                       + f'<path d="{LEAFLET}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(max(0.7, r * 0.03) / sc)}" stroke-linejoin="round"/>'
                       + f'<path d="M4 0L26 0" stroke="{p["ink"]}" stroke-width="{fmt(max(0.7, r * 0.03) / sc * 0.6)}"/></g>')
    return "\n".join(out)


def node(p: dict, x, y, r, state="available", glyph=None, progress=0.4, seed=4, sparkle=True, decay=0.0) -> str:
    """A skill node: a round medallion.  locked (hatched, faint ring) / available (clean,
    bold ring, a sprouting leaflet) / progress (strength ring, filled fraction) / bronze (copper,
    matte: stippled, two rings, one glint) / silver (cool grey, shiny: cross-hatched with two bright
    bands, three rings, two twinkles) / gold (warm yellow, radiant: polished with a gleam, three
    rings, rays over the top, a laurel round the bottom, four twinkles).  Mono keeps the hierarchy
    with texture, ring count, rays, laurel and twinkle shapes.  `decay` (0..1) cracks the stone."""
    out = []
    circ = circle_d(x, y, r)
    inner = circle_d(x, y, r * 0.78)
    mono = p["mono"]
    base = {"locked": p["paper"], "available": p["cream"], "progress": p["cream"],
            "bronze": p["bronze"], "silver": p["silver"], "gold": p["gold"]}[state]
    hw = max(0.8, r * 0.035)
    level = 0.0 if state in ("locked", "available") or decay < CRACKS["start"] else min(1.0, (decay - CRACKS["start"]) / (1 - CRACKS["start"]))
    lines, chips, shards = crack_pattern(level, seed)
    clip = ""
    if chips:
        _CLIP[0] += 1
        clip = f"k{_CLIP[0]}"
        cut = "".join(pts_d([(x + qx * r, y + qy * r) for qx, qy in c], True) for c, _ in chips)
        out.append(f'<clipPath id="{clip}"><path clip-rule="evenodd" d="M{fmt(x - 2 * r)} {fmt(y - 2 * r)}h{fmt(4 * r)}v{fmt(4 * r)}h{fmt(-4 * r)}Z{cut}"/></clipPath><g clip-path="url(#{clip})">')
    out.append(fill(circ, base))
    if state == "locked":
        out.append(hatch([circ], 45, max(3.0, r * 0.14), p, hw, seed=seed, op="0.45" if not mono else "1"))
    elif state == "bronze":
        if not mono:
            out.append(clipped(f"M{fmt(x - r)} {fmt(y - r * 0.1)}L{fmt(x + r * 0.5)} {fmt(y + r)}L{fmt(x - r)} {fmt(y + r)}Z", circ, p["bark_dk"], 0.3))
        rnd = random.Random(seed * 3 + 1)
        for _ in range(max(10, min(44, round(r * 1.1)))):
            a, d = rnd.random() * math.tau, math.sqrt(rnd.random()) * r * 0.72
            out.append(fill(circle_d(x + math.cos(a) * d, y + math.sin(a) * d, max(0.55, r * 0.03) * (0.7 + rnd.random() * 0.6)),
                            p["ink"], None if mono else 0.5))
    elif state == "silver":
        out.append(hatch([inner], 25, max(3.0, r * 0.17), p, hw, seed=seed, op="0.25" if not mono else "0.9"))
        out.append(hatch([inner], 115, max(3.0, r * 0.34), p, hw * 0.7, seed=seed + 5, op="0.2" if not mono else "0.55"))
        lx, ly = LIGHT
        ax, ay = -ly, lx
        bands = ""
        for off, half in NODE_SPEC["texture"]["silver"]["bands"]:
            mx, my = x + lx * r * off, y + ly * r * off
            q = [(mx - ax * r + lx * r * half, my - ay * r + ly * r * half), (mx + ax * r + lx * r * half, my + ay * r + ly * r * half),
                 (mx + ax * r - lx * r * half, my + ay * r - ly * r * half), (mx - ax * r - lx * r * half, my - ay * r - ly * r * half)]
            bands += pts_d(q, True)
        out.append(clipped(bands, circle_d(x, y, r * 0.74), p["paper"] if mono else "#F4F7FA", None if mono else 0.9))
    elif state == "gold" and not mono:
        out.append(fill(circle_d(x, y, r * 0.62), "#E8BE5B"))
    if state != "locked":
        out.append(hatch([circ, f"M{x - r} {y - r * 0.3}L{x + r * 0.3} {y + r}L{x - r} {y + r}Z"],
                         40, max(2.6, r * 0.11), p, hw, seed=seed + 1))
    if state in NODE_SPEC["gleam"]["tiers"] and not mono:
        # a gleam: a short paper-coloured arc on the lit side of the polished metal
        g = NODE_SPEC["gleam"]
        a0, a1 = math.radians(g["arc_deg"][0]), math.radians(g["arc_deg"][1])
        R = r * g["radius"]
        pts = [(x + math.cos(a0 + (a1 - a0) * i / 12) * R, y + math.sin(a0 + (a1 - a0) * i / 12) * R) for i in range(13)]
        out.append(ink_line(pts_d(pts, False), p, r * g["width"], "taper", color=p["paper"], wobble=0))
        out.append(f'<path d="{pts_d(pts, False)}" fill="none" stroke="{p["paper"]}" stroke-opacity="{g["opacity"]}" stroke-width="{fmt(r * g["width"] * 0.5)}" stroke-linecap="round"/>')
    out.append(ink_shape(circ, p, r * (0.03 if state == "locked" else 0.05), r * (0.08 if state == "locked" else 0.16),
                         step=1.5, wobble=0.3, seed=seed))
    if state != "locked":
        out.append(ink_shape(inner, p, r * 0.035, r * 0.06, step=1.5, wobble=0.25, seed=seed + 2))
    if state in ("silver", "gold"):
        out.append(ink_shape(circle_d(x, y, r * 0.66), p, r * 0.03, r * 0.045, step=1.5, wobble=0.2, seed=seed + 3))
    w = max(0.8, r * (CRACKS["width"][0] + (CRACKS["width"][1] - CRACKS["width"][0]) * level))
    for ln in lines:
        d = pts_d([(x + qx * r, y + qy * r) for qx, qy in ln], False)
        out.append(ink_line(d, p, w * 1.1, "in", seed=seed + 30, wobble=0.1))
    if chips:
        out.append("</g>")
        for _, edge in chips:
            out.append(ink_line(pts_d([(x + qx * r, y + qy * r) for qx, qy in edge], False), p, max(0.9, r * 0.06), "flat", seed=seed + 20, wobble=0.1))
        for s in shards:
            d = pts_d([(x + qx * r, y + qy * r) for qx, qy in s], True)
            out.append(fill(d, base) + f'<path d="{d}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(max(0.8, r * 0.045))}" stroke-linejoin="round"/>')
    if state == "gold" and sparkle:
        for k, deg in enumerate(_ray_angles()):
            a = math.radians(deg)
            long_ = k % 2 == 0
            x0, y0 = x + math.cos(a) * r * RAYS["r0"], y + math.sin(a) * r * RAYS["r0"]
            r1 = RAYS["r1"] if long_ else RAYS["short_r1"]
            x1, y1 = x + math.cos(a) * r * r1, y + math.sin(a) * r * r1
            out.append(ink_line(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}", p, r * RAYS["width"], "in", seed=seed + k, wobble=0))
        out.append(laurel(p, x, y, r, seed=seed + 40))
    if state == "progress":
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
        out.append(f'<g transform="translate({fmt(x + r * 0.62)} {fmt(y - r * 0.86)}) rotate(-50) scale({fmt(r / 60)})">'
                   + fill(LEAFLET, p["leaf"]) + ink_shape(LEAFLET, p, 1.2, 2.6, step=3, wobble=0.2, smooth=2) + "</g>")
    if state in SPARKLE and sparkle:
        sp_ = SPARKLE[state]
        for ang, dist, size, rot in sp_["twinkles"]:
            a = math.radians(ang)
            out.append(twinkle(p, x + math.cos(a) * r * dist, y + math.sin(a) * r * dist, r * size, rot))
        for ang, dist, size in sp_["dots"]:
            a = math.radians(ang)
            out.append(fill(circle_d(x + math.cos(a) * r * dist, y + math.sin(a) * r * dist, r * size), p["ink"]))
    return "\n".join(out)


def node_states(p: dict) -> str:
    out = []
    for i, st in enumerate(NODE_STATES):
        out.append(node(p, 70 + i * 120, 70, 40, st, None, progress=0.6, seed=200 + i))
    return "\n".join(out)


def node_single(p: dict, state: str) -> str:
    return node(p, 70, 70, 40, state, None, progress=0.6, seed=200 + NODE_STATES.index(state))


DECAY_STEPS = (0.0, 0.3, 0.5, 0.75, 1.0)


def node_decay(p: dict) -> str:
    """Decay on a silver node: whole, hairline cracks, a chip, a fragment breaking off, crumbling."""
    return "\n".join(node(p, 70 + i * 120, 70, 40, "silver", None, seed=31, decay=d) for i, d in enumerate(DECAY_STEPS))


def twinkle_sprite(p: dict) -> str:
    return twinkle(p, 32, 32, 28, 0, bold=1.4)


# ================================================================= leaf sprites
def leaf_sprite(p: dict, kind: str) -> str:
    """Ash leaf sprites in a 128 x 72 box: 'a' pinnate with three pairs, 'b' two pairs on a
    curved stem, 'c' a single leaflet."""
    if kind == "a":
        return ash_leaf(p, 14, 36, 0, 1.05, seed=2)
    if kind == "b":
        out = [ink_line("M0 0C22 -10 44 -8 66 -2", p, 2.0, "in", seed=5)]
        rnd = random.Random(5)
        for i, t in enumerate((18, 40)):
            for side in (-1, 1):
                ang = side * (-56 + rnd.random() * 10)
                parts = [fill(LEAFLET, p["leaf"]),
                         hatch([LEAFLET, "M0 -2L40 -2L40 10L0 10Z"], 35, 3.2, p, 0.8, seed=5 + t, shrink=1.0),
                         ink_shape(LEAFLET, p, 0.9, 2.4, step=3.0, wobble=0.25, seed=5 + t, smooth=2), ink_line("M3 0L30 0", p, 0.9, "in", seed=5)]
                out.append(f'<g transform="translate({t} {fmt(-3 - t * 0.09)}) rotate({fmt(ang)}) scale({0.95 + 0.1 * i})">' + "".join(parts) + "</g>")
        parts = [fill(LEAFLET, p["leaf"]), hatch([LEAFLET, "M0 -2L40 -2L40 10L0 10Z"], 35, 3.2, p, 0.8, seed=9, shrink=1.0),
                 ink_shape(LEAFLET, p, 0.9, 2.4, step=3.0, wobble=0.25, seed=9, smooth=2), ink_line("M3 0L30 0", p, 0.9, "in", seed=5)]
        out.append('<g transform="translate(64 -2) rotate(-6) scale(1.1)">' + "".join(parts) + "</g>")
        return '<g transform="translate(16 40) rotate(-8)">' + "\n".join(out) + "</g>"
    parts = [fill(LEAFLET, p["leaf"]), hatch([LEAFLET, "M0 -2L40 -2L40 10L0 10Z"], 35, 3.0, p, 0.9, seed=13, shrink=1.0),
             ink_shape(LEAFLET, p, 1.1, 3.0, step=3.0, wobble=0.25, seed=13, smooth=2), ink_line("M3 0L30 0", p, 1.1, "in", seed=5)]
    return '<g transform="translate(14 36) rotate(-12) scale(2.6)">' + "".join(parts) + "</g>"


# ================================================================= crops, icons, marker
def bust(p: dict, cx, cy, sc, bold=1.4, detail=0.6) -> str:
    """The figure (no scroll, no bough) scaled so the face centre lands on (cx, cy)."""
    hx, hy = HEAD_CENTRE
    return (f'<g transform="translate({fmt(cx - sc * hx)} {fmt(cy - sc * hy)}) scale({fmt(sc)})">'
            f'{tosk(p, scroll_=False, branch=False, detail=detail, bold=bold)}</g>')


def head_crop(p: dict, bold=1.4, detail=0.6, rule=True, square=False) -> str:
    """Tosk's head and shoulders, plume behind, in the rounded bookplate frame.  512 space.
    square=True fills the whole square (launcher PNGs: iOS wants no transparency)."""
    _CLIP[0] += 1
    cid = f"icon{_CLIP[0]}"
    r = 0 if square else 112
    out = [f'<clipPath id="{cid}"><rect x="0" y="0" width="512" height="512" rx="{r}"/></clipPath>']
    out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["paper"]}"/>')
    if not p["mono"]:
        out.append(f'<rect x="0" y="0" width="512" height="512" rx="{r}" fill="{p["cream"]}" fill-opacity="0.6"/>')
    out.append(f'<g clip-path="url(#{cid})">{bust(p, 308, 256, 1.7, bold, detail)}</g>')
    if rule:
        out.append(f'<rect x="22" y="22" width="468" height="468" rx="{max(r - 20, 28)}" fill="none" stroke="{p["ink"]}" stroke-width="{fmt(5 * bold / 1.4)}"/>')
        out.append(f'<rect x="34" y="34" width="444" height="444" rx="{max(r - 30, 20)}" fill="none" stroke="{p["ink"]}" stroke-width="2"/>')
    return "\n".join(out)


def icon(p: dict) -> str:
    return head_crop(p, 1.4, 0.6, True)


def icon_square(p: dict) -> str:
    return head_crop(p, 1.4, 0.6, True, square=True)


def marker(p: dict, bold=2.4, detail=0.001, ring=18) -> str:
    """Map marker: Tosk's head in a round paper badge, heavy ink, no hatching, for 40-56 px."""
    _CLIP[0] += 1
    cid = f"mk{_CLIP[0]}"
    R = 236
    out = [f'<clipPath id="{cid}"><circle cx="256" cy="256" r="{R - ring / 2}"/></clipPath>',
           f'<circle cx="256" cy="256" r="{R}" fill="{p["paper"]}"/>']
    if not p["mono"]:
        out.append(f'<circle cx="256" cy="256" r="{R}" fill="{p["cream"]}" fill-opacity="0.7"/>')
    out.append(f'<g clip-path="url(#{cid})">{bust(p, 292, 286, 1.72, bold, detail)}</g>')
    out.append(f'<circle cx="256" cy="256" r="{R}" fill="none" stroke="{p["ink"]}" stroke-width="{ring}"/>')
    return "\n".join(out)


def adaptive_fg(p: dict, ink_only=False) -> str:
    """Android adaptive-icon foreground (512 space, scaled to 1024): the bust in a round cream
    badge inside the 66/108 safe zone; everything else transparent."""
    _CLIP[0] += 1
    cid = f"af{_CLIP[0]}"
    R = 150
    out = [f'<clipPath id="{cid}"><circle cx="256" cy="256" r="{R - 3}"/></clipPath>']
    if not ink_only:
        out.append(f'<circle cx="256" cy="256" r="{R}" fill="{p["cream"]}"/>')
    out.append(f'<g clip-path="url(#{cid})">{bust(p, 282, 268, 1.02, 1.8, 0.001)}</g>')
    out.append(f'<circle cx="256" cy="256" r="{R}" fill="none" stroke="{p["ink"]}" stroke-width="7"/>')
    return "\n".join(out)


def logo(p: dict) -> str:
    out = [f'<g transform="translate(10 20) scale(0.5)">{head_crop(p, 1.2, 0.6, rule=False)}</g>']
    wm, width = wordmark(p, False, 296, 206)
    out.append(wm)
    out.append(ash_leaf(p, 310, 236, -6, 0.78, seed=70))
    return "\n".join(out)


def wordmark_svg(p: dict) -> str:
    wm, width = wordmark(p, False, 20, 170, 200)
    return svg(int(width + 60), 230, wm, "tosk wordmark")


def splash(p: dict, dark=False) -> str:
    """Splash image, 1200 x 1200, transparent: Tosk on his bough above the wordmark."""
    q = dict(p)
    out = [f'<g transform="translate(260 120) scale(1.3)">{tosk(p)}</g>']
    if dark:
        q["ink"] = p["paper"]
    wm, width = wordmark(q, False, 0, 0, 230)
    out.append(f'<g transform="translate({fmt(600 - width / 2)} 1030)">{wm}</g>')
    return "\n".join(out)


def splash_android12(p: dict) -> str:
    """Android 12+ splash icon: 1152 x 1152, content inside the centre 768 circle."""
    return f'<g transform="translate(226 226) scale(1.3671875)">{marker(p, 2.0, 0.6, 14)}</g>'


# ================================================================= branch style spec
def branch_style() -> dict:
    return {
        "_about": "Storybook branch painter spec for tosk's course map. Lengths are in logical px unless noted as a fraction of r (node radius) or of the branch length. Generated by app/tool/brand/make_tosk.py; the reference art is app/assets/brand/branch-tile.svg and node-states.svg.",
        "palette": {k: v for k, v in COLOR.items() if isinstance(v, str) and v.startswith("#")},
        "mono": {"rule": "every fill becomes paper (#FFFFFF) and every stroke ink (#000000); opacities become 1 (hatch) - nothing grey",
                 "ink": "#000000", "paper": "#FFFFFF"},
        "light": {"direction": list(LIGHT), "note": "unit vector the light comes from (top right); ink outlines are heavy where the surface faces away from it"},
        "ink_outline": {"min_width": 1.3, "max_width": 4.2, "exponent": 0.8, "wobble_px": 0.5,
                        "rule": "width = min + (max - min) * max(0, -(n . light))^exponent, n = outward normal; a slow +-18% noise along the path"},
        "bough": {
            "width_main": [40, 12], "width_twig": [10, 4], "width_trunk_segment": [42, 32],
            "taper": "linear from width[0] at the start to width[1] at the end, times the knuckle bumps",
            "knuckles": {"count": [1, 2], "centre": [0.25, 0.75], "amplitude": [0.18, 0.38], "sigma": [0.05, 0.09],
                         "rule": "w *= 1 + amp * exp(-((s - centre) / sigma)^2); a short curved crease stroke across the bough at each bump, on both sides, width 1.6"},
            "fill": "bark",
            "grain": {"lines": 3, "offsets": [-0.18, -0.35, -0.52], "offset_unit": "fraction of the half-width on the shadow side",
                      "dash_length": [0.12, 0.32], "gap": [0.08, 0.28], "unit": "fraction of the branch length",
                      "stroke_width": 1.5, "opacity": 0.85, "colour": "ink"},
            "hatch": {"where": "shadow half (between 0.12 and 0.65 of the half-width)", "angle": "branch direction + 70 deg",
                      "spacing": 6, "width": 1.0, "opacity": 0.62, "colour": "ink", "jitter": 0.5, "shrink": 2},
            "twigs": {"per_120px": 1, "length": [40, 70], "angle_from_bough_deg": [35, 60], "no_grain": True, "no_knuckles": True},
        },
        "leaves": {
            "sprites": ["leaf-a.svg (3 pairs + tip, 128x72)", "leaf-b.svg (2 pairs on a curved stem)", "leaf-c.svg (single leaflet)"],
            "leaflet_path": LEAFLET, "leaflet_fill": "leaf", "leaflet_outline": [0.9, 2.4], "midrib_width": 0.9,
            "leaflet_hatch": {"angle": 35, "spacing": 3.2, "width": 0.8, "where": "lower half, every other leaflet"},
            "pinnate": {"stem": "M0 0C30 -4 60 -2 92 0", "pairs_at": [22, 46, 70], "pair_angle_deg": [-57, -47], "tip_at": 92, "scale_per_pair": [0.9, 1.0, 1.1]},
            "placement": {"at": "twig ends and 1-2 per bough side", "scale": [0.7, 0.85], "angle": "twig direction +- 15 deg, leaflets pointing away from the trunk"},
        },
        "nodes": {
            "radius_px": {"map": 32, "reference_sheet": 40},
            "states": list(NODE_STATES),
            "base_fill": {"locked": "paper", "available": "cream", "progress": "cream", "bronze": "bronze", "silver": "silver", "gold": "gold"},
            **NODE_SPEC,
            "sparkle": {k: {"twinkles": [dict(angle=a, dist=d, size=s, rotate=r) for a, d, s, r in v["twinkles"]],
                            "dots": [dict(angle=a, dist=d, size=s) for a, d, s in v["dots"]],
                            "rays": RAYS if v["rays"] else None,
                            "laurel": LAUREL if v.get("laurel") else None} for k, v in SPARKLE.items()},
            "twinkle": {"shape": "4-point star: tips at r on the axes, sides are quadratic curves with the control point at the centre",
                        "path_for_r1": twinkle_d(0, 0, 1, 0), "fill": "paper", "stroke": "ink", "stroke_width": "max(0.8, 0.11 * size)",
                        "motion": "when motion is on (one shared ticker for the map): silver breathes (scale 1 +- 0.14, opacity 0.82-1, 2.4 s, phases offset) "
                                  "with a flare every 6.5 s; gold breathes (scale 1 +- 0.18, opacity 0.75-1, 2.0 s) with a flare every 4.5 s; bronze's glint "
                                  "rests and flares (scale to 1.45, a 34 deg turn) for 0.7 s every 5.2 s; static with reduceMotion or in mono"},
            "angles": "degrees, 0 = right, positive = clockwise on screen (SVG y down)",
        },
    }


# ================================================================= sheet, exports
SIZES = dict(tosk=(512, 512), head=(512, 512), icon=(512, 512), marker=(512, 512), nodes=(720, 140), node=(140, 140),
             twinkle=(64, 64), leaf=(128, 72), tile=(400, 400), ygg=(800, 1100), logo=(760, 300), splash=(1200, 1200),
             a12=(1152, 1152))

MONO_LAYER = {**MONO, "fur": "none", "fur_dk": "none", "fur_lt": "none", "cream": "none", "paper": "none", "bark": "none",
              "bark_dk": "none", "leaf": "none", "leaf_dk": "none"}


def files() -> dict:
    """name -> (w, h, fn, title).  Each is written as name.svg and name-mono.svg."""
    f = {}
    for name, fn in POSES.items():
        f[name] = (512, 512, fn, {"tosk": "Tosk (variant c)"}.get(name, name.replace("tosk-", "Tosk, ")))
    f["tosk-head"] = (512, 512, lambda q: head_crop(q, 1.4, 0.6, rule=False), "Tosk head crop")
    f["tosk-marker"] = (512, 512, marker, "Tosk map marker")
    f["icon"] = (512, 512, icon, "tosk app icon")
    f["node-states"] = (720, 140, node_states, "Skill node states")
    for st in NODE_STATES:
        f[f"node-{st}"] = (140, 140, (lambda q, st=st: node_single(q, st)), f"Skill node: {st}")
    f["node-decay"] = (600, 140, node_decay, "Skill node decay: whole to crumbling")
    f["twinkle"] = (64, 64, twinkle_sprite, "Twinkle")
    for k in "abc":
        f[f"leaf-{k}"] = (128, 72, (lambda q, k=k: leaf_sprite(q, k)), f"Ash leaf {k}")
    f["branch-tile"] = (400, 400, branch_tile, "Map branch tile: a fork between skills")
    f["yggdrasil"] = (800, 1100, yggdrasil, "The course tree (optional decoration)")
    f["logo"] = (760, 300, logo, "tosk logo")
    return f


# PNG exports the app shows as raster: (svg name, logical 1x size)  -> png/<name>.png, png/2.0x, png/3.0x
RASTER = [("tosk", 224), ("tosk-celebrate", 224), ("tosk-reading", 224), ("tosk-sleeping", 224), ("tosk-pointing", 224),
          ("tosk-head", 160), ("tosk-marker", 56)]
SCALES = ((1.0, ""), (2.0, "2.0x/"), (3.0, "3.0x/"))

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"


def render_png(svg_text: str, w: int, h: int, out_png: Path, work: Path, transparent=True, timeout=30.0) -> None:
    """Render an SVG document to a PNG with headless Edge (the launcher returns at once, so
    poll for the file)."""
    import subprocess
    import time
    work.mkdir(parents=True, exist_ok=True)
    page = work / "page.html"
    body = re.sub(r'<svg([^>]*)\swidth="[^"]*"\sheight="[^"]*"', r'<svg\1', svg_text, count=1)
    bg = "transparent" if transparent else COLOR["paper"]
    page.write_text(f'<!doctype html><html><head><meta charset="utf-8"><style>html,body{{margin:0;background:{bg}}}'
                    f'svg{{display:block;width:{w}px;height:{h}px}}</style></head><body>{body}</body></html>', encoding="utf-8", newline="\n")
    if out_png.exists():
        out_png.unlink()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    args = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--user-data-dir={work / 'edgeprof'}", f"--window-size={w},{h}", f"--screenshot={out_png}",
            "file:///" + str(page).replace("\\", "/")]
    if transparent:
        args.insert(4, "--default-background-color=00000000")
    subprocess.run(args, capture_output=True)
    t0 = time.time()
    last = -1
    while True:
        if out_png.exists():
            size = out_png.stat().st_size
            if size and size == last:
                break
            last = size
        if time.time() - t0 > timeout:
            raise RuntimeError(f"Edge did not write {out_png}")
        time.sleep(0.15)


def shrink_png(path: Path, mono: bool) -> None:
    """Colour: 128-colour palette with alpha.  Mono: pure black / white / transparent, no greys."""
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    if mono:
        a = im.getchannel("A")
        lum = im.convert("RGB").convert("L")
        idx = lum.point(lambda v: 1 if v > 150 else 0)          # 0 black, 1 white
        idx.paste(2, mask=a.point(lambda v: 255 if v < 110 else 0))  # 2 transparent
        out = Image.frombytes("P", im.size, idx.tobytes())
        out.putpalette([0, 0, 0, 255, 255, 255, 0, 0, 0])
        out.save(path, optimize=True, transparency=bytes([255, 255, 0]))
    else:
        q = im.quantize(colors=128, method=Image.Quantize.FASTOCTREE)
        q.save(path, optimize=True)


def export_pngs(only=None) -> None:
    import shutil
    work = Path(os.environ.get("TEMP", str(HERE))) / "tosk-render"
    pngdir = OUT / "png"
    icondir = OUT / "icon"
    for d in (pngdir, pngdir / "2.0x", pngdir / "3.0x", icondir):
        d.mkdir(parents=True, exist_ok=True)
    for name, base in RASTER:
        if only and name not in only:
            continue
        for mono in (False, True):
            src = (OUT / f"{name}{'-mono' if mono else ''}.svg").read_text(encoding="utf-8")
            for sc, sub in SCALES:
                out = pngdir / sub / f"{name}{'-mono' if mono else ''}.png"
                render_png(src, int(base * sc), int(base * sc), out, work)
                shrink_png(out, mono)
                print(f"  {out.relative_to(OUT)}  {out.stat().st_size / 1024:5.1f} KB")
    if not only or "icon" in only:
        jobs = [("icon-1024.png", svg(512, 512, icon_square(COLOR), ""), 1024, False),
                ("icon-rounded-1024.png", svg(512, 512, icon(COLOR), ""), 1024, True),
                ("adaptive-foreground.png", svg(512, 512, adaptive_fg(COLOR), ""), 1024, True),
                ("adaptive-monochrome.png", svg(512, 512, adaptive_fg(MONO_LAYER, ink_only=True), ""), 1024, True),
                ("adaptive-background.png", svg(512, 512, f'<rect width="512" height="512" fill="{COLOR["paper"]}"/>', ""), 1024, False),
                ("splash.png", svg(1200, 1200, splash(COLOR), ""), 1200, True),
                ("splash-dark.png", svg(1200, 1200, splash(COLOR, dark=True), ""), 1200, True),
                ("splash-android12.png", svg(1152, 1152, splash_android12(COLOR), ""), 1152, True)]
        for fname, doc, size, transparent in jobs:
            out = icondir / fname
            render_png(doc, size, size, out, work, transparent=transparent)
            if fname.startswith("adaptive-monochrome"):
                from PIL import Image
                im = Image.open(out).convert("RGBA")
                a = im.getchannel("A")
                Image.merge("RGBA", (Image.new("L", im.size, 0),) * 3 + (a,)).save(out, optimize=True)
            elif not fname.startswith("splash") and "adaptive-background" not in fname:
                from PIL import Image
                im = Image.open(out)
                im.quantize(colors=192, method=Image.Quantize.FASTOCTREE).save(out, optimize=True)
            else:
                from PIL import Image
                Image.open(out).quantize(colors=160, method=Image.Quantize.FASTOCTREE).save(out, optimize=True)
            print(f"  icon/{fname}  {out.stat().st_size / 1024:5.1f} KB")
    shutil.rmtree(work, ignore_errors=True)


def render_sheet() -> None:
    import shutil
    import subprocess
    import time
    page = HERE / "sheet.html"
    out = HERE.parents[2] / "docs" / "brand-sheet.png"
    work = Path(os.environ.get("TEMP", str(HERE))) / "tosk-render"
    work.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--user-data-dir={work / 'edgeprof'}", "--window-size=1600,2980", f"--screenshot={out}",
                    "file:///" + str(page).replace("\\", "/")], capture_output=True)
    t0 = time.time()
    last = -1
    while True:
        if out.exists():
            size = out.stat().st_size
            if size and size == last:
                break
            last = size
        if time.time() - t0 > 40:
            raise RuntimeError("sheet render timed out")
        time.sleep(0.2)
    from PIL import Image
    Image.open(out).convert("RGB").quantize(colors=224).save(out, optimize=True)
    shutil.rmtree(work, ignore_errors=True)
    print(f"  docs/brand-sheet.png  {out.stat().st_size / 1024:.0f} KB")


def sheet_html() -> str:
    A = "../../assets/brand"
    pal = [(k, v) for k, v in COLOR.items() if isinstance(v, str) and v.startswith("#")]
    sw = "".join(f'<div class="sw"><div class="chip" style="background:{v}"></div><b>{k}</b><span>{v}</span></div>' for k, v in pal)
    states = "".join(f"<span>{s}</span>" for s in NODE_STATES)
    poses = [("tosk", "Tosk (variant c)"), ("tosk-celebrate", "celebrating"), ("tosk-reading", "thinking / reading"),
             ("tosk-sleeping", "sleeping"), ("tosk-pointing", "pointing")]
    prow = "".join(f'<figure class="card"><img src="{A}/{n}.svg" width="256"><figcaption>{t}</figcaption></figure>' for n, t in poses)
    mrow = "".join(f'<figure class="card w"><img src="{A}/{n}-mono.svg" width="256"><figcaption>{t}, e-ink</figcaption></figure>' for n, t in poses)
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk: brand kit</title>
<style>
body{{margin:0;padding:24px 32px;background:#F7F0E2;color:#3B2A1F;font-family:Gelasio,Georgia,'Palatino Linotype',serif;width:1536px}}
h1{{margin:0 0 2px;font-size:40px;letter-spacing:-1px}} h2{{font-size:17px;margin:14px 0 8px;font-weight:normal;opacity:.75;border-bottom:1px solid #3B2A1F44}}
p.sub{{margin:0 0 6px;font-size:14px;opacity:.8}}
.row{{display:flex;gap:14px;align-items:flex-start;flex-wrap:wrap;margin-bottom:14px}}
figure{{margin:0}}
.card{{background:#FBF7EE;border:1.5px solid #3B2A1F;border-radius:14px;padding:10px 12px 6px;box-shadow:3px 4px 0 #3B2A1F22}}
.card.w{{background:#fff}} .card.d{{background:#2B1F17}} .card img{{display:block}} .card figcaption{{text-align:center;font-size:12px;margin-top:5px;opacity:.85}}
.card.d figcaption{{color:#F7F0E2}}
.icons{{display:flex;gap:16px;align-items:flex-end}} .icons div{{text-align:center;font-size:11px}} .icons img{{display:inline-block;vertical-align:bottom}}
.pal{{display:flex;gap:7px;flex-wrap:wrap}} .sw{{width:62px;font-size:10px;text-align:center}} .sw b{{display:block;margin-top:3px}}
.chip{{height:40px;border-radius:8px;border:1px solid #3B2A1F55}}
.states{{display:flex;justify-content:space-around;font-size:11px;width:670px;margin:2px auto 0}}
.circ{{border-radius:50%;overflow:hidden;display:inline-block;background:#F7F0E2}}
</style></head><body>
<h1>tosk <span style="font-size:18px;opacity:.6">brand kit</span></h1>
<p class="sub">Ratatosk, the messenger squirrel. Storybook ink: tapered pen lines, hatching, warm watercolour. Colour and e-ink side by side. Generated by app/tool/brand/make_tosk.py.</p>

<h2>Tosk: variant c and the UI poses</h2>
<div class="row">{prow}</div>
<div class="row">{mrow}</div>

<h2>Head crop, map marker, app icon</h2>
<div class="row">
 <figure class="card"><div class="icons"><div><img src="{A}/tosk-head.svg" width="128"><br>head crop 128</div><div><img src="{A}/tosk-head-mono.svg" width="128"><br>e-ink</div></div><figcaption>tosk-head.svg</figcaption></figure>
 <figure class="card"><div class="icons">
   <div><img src="{A}/tosk-marker.svg" width="96"><br>96</div><div><img src="{A}/tosk-marker.svg" width="56"><br>56</div><div><img src="{A}/tosk-marker.svg" width="40"><br>40</div>
   <div><img src="{A}/tosk-marker-mono.svg" width="56"><br>56 e-ink</div><div><img src="{A}/tosk-marker-mono.svg" width="40"><br>40 e-ink</div>
   <div><img src="{A}/png/tosk-marker.png" width="56"><br>png 1x</div><div><img src="{A}/png/tosk-marker-mono.png" width="56"><br>png mono</div></div>
   <figcaption>tosk-marker.svg: the map marker at 96 / 56 / 40 px</figcaption></figure>
 <figure class="card"><div class="icons">
   <div><img src="{A}/icon.svg" width="128"><br>icon 128</div><div><img src="{A}/icon.svg" width="64"><br>64</div><div><img src="{A}/icon.svg" width="48"><br>48</div><div><img src="{A}/icon-mono.svg" width="64"><br>64 e-ink</div>
   <div><span class="circ"><img src="{A}/icon/adaptive-foreground.png" width="108" style="background:#F7F0E2"></span><br>adaptive (circle)</div>
   <div><img src="{A}/icon/adaptive-monochrome.png" width="108" style="background:#9C4C27;border-radius:24px"><br>themed (mono layer)</div>
   <div><img src="{A}/icon/splash-android12.png" width="108"><br>android 12 splash</div></div>
   <figcaption>icon.svg (bookplate frame) and the launcher sources in icon/</figcaption></figure>
</div>

<h2>Logo, wordmark, splash</h2>
<div class="row">
 <figure class="card"><img src="{A}/logo.svg" width="380"><figcaption>logo.svg (mark + Gelasio Bold wordmark)</figcaption></figure>
 <figure class="card"><img src="{A}/wordmark.svg" width="230"><img src="{A}/wordmark-mono.svg" width="230" style="background:#fff;margin-top:6px"><figcaption>wordmark.svg, wordmark-mono.svg</figcaption></figure>
 <figure class="card"><img src="{A}/icon/splash.png" width="260"><figcaption>splash.png on paper</figcaption></figure>
 <figure class="card d"><img src="{A}/icon/splash-dark.png" width="260"><figcaption>splash-dark.png on #2B1F17</figcaption></figure>
</div>

<h2>Skill nodes with the sparkly tiers, leaves, branches</h2>
<div class="row">
 <div style="width:700px">
  <figure class="card"><img src="{A}/node-states.svg" width="670"><div class="states">{states}</div>
   <img src="{A}/node-states-mono.svg" width="670" style="background:#fff;margin-top:6px"><div class="states">{states}</div>
   <figcaption>node-states.svg: locked, available, in progress, bronze (copper, matte, one glint), silver (cool grey, shine, two twinkles), gold (warm yellow, rays, laurel, four twinkles)</figcaption>
   <img src="{A}/node-decay.svg" width="560" style="margin-top:8px"><img src="{A}/node-decay-mono.svg" width="560" style="background:#fff;margin-top:4px">
   <figcaption>node-decay.svg: decay cracks the stone (0, 0.3, 0.5, 0.75, 1): hairline cracks, a chip, a fragment breaking off, crumbling</figcaption></figure>
  <div class="row" style="margin-top:14px">
   <figure class="card"><div class="icons"><img src="{A}/node-gold.svg" width="48"><img src="{A}/node-silver.svg" width="48"><img src="{A}/node-bronze.svg" width="48"><img src="{A}/node-gold-mono.svg" width="48" style="background:#fff"><img src="{A}/node-silver-mono.svg" width="48" style="background:#fff"><img src="{A}/node-bronze-mono.svg" width="48" style="background:#fff"></div><figcaption>tiers at map size (48 px)</figcaption></figure>
   <figure class="card"><div class="icons"><img src="{A}/leaf-a.svg" width="128"><img src="{A}/leaf-b.svg" width="128"><img src="{A}/leaf-c.svg" width="128"><img src="{A}/twinkle.svg" width="48"></div>
    <div class="icons" style="margin-top:6px;background:#fff"><img src="{A}/leaf-a-mono.svg" width="128"><img src="{A}/leaf-b-mono.svg" width="128"><img src="{A}/leaf-c-mono.svg" width="128"><img src="{A}/twinkle-mono.svg" width="48"></div>
    <figcaption>leaf-a / b / c.svg, twinkle.svg</figcaption></figure>
  </div>
  <div class="row"><figure class="card"><img src="{A}/branch-tile.svg" width="210"><figcaption>branch-tile.svg</figcaption></figure>
  <figure class="card w"><img src="{A}/branch-tile-mono.svg" width="210"><figcaption>e-ink</figcaption></figure>
  <figure class="card"><div class="pal">{sw}</div><figcaption>Palette (branch-style.json)</figcaption></figure></div>
 </div>
 <figure class="card"><img src="{A}/yggdrasil.svg" width="330"><figcaption>yggdrasil.svg (optional decoration)</figcaption></figure>
 <figure class="card w"><img src="{A}/yggdrasil-mono.svg" width="330"><figcaption>e-ink</figcaption></figure>
</div>
</body></html>
"""


def write_svgs(only=None) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (w, h, fn, title) in files().items():
        if only and name not in only:
            continue
        (OUT / f"{name}.svg").write_text(svg(w, h, fn(COLOR), title), encoding="utf-8", newline="\n")
        (OUT / f"{name}-mono.svg").write_text(svg(w, h, fn(MONO), title + " (e-ink)"), encoding="utf-8", newline="\n")
    if not only:
        (OUT / "wordmark.svg").write_text(wordmark_svg(COLOR), encoding="utf-8", newline="\n")
        (OUT / "wordmark-mono.svg").write_text(wordmark_svg(MONO), encoding="utf-8", newline="\n")
        (OUT / "branch-style.json").write_text(json.dumps(branch_style(), indent=1) + "\n", encoding="utf-8", newline="\n")
        (HERE / "sheet.html").write_text(sheet_html(), encoding="utf-8", newline="\n")
    total = 0
    for f in sorted(OUT.glob("*.svg")):
        total += f.stat().st_size
        print(f"{f.name:26s} {f.stat().st_size / 1024:6.1f} KB")
    print(f"svg total {total / 1024:.0f} KB")


def main(argv) -> None:
    what = argv[1] if len(argv) > 1 else "svg"
    only = set(argv[2:]) or None
    if what in ("svg", "all", "png", "sheet"):
        write_svgs(only if what == "svg" else None)
    if what in ("png", "all"):
        export_pngs(only)
    if what in ("sheet", "all"):
        render_sheet()


if __name__ == "__main__":
    import sys
    main(sys.argv)
