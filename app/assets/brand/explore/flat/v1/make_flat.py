"""tosk brand exploration: FLAT MODERN MASCOT style.

Run:  python make_flat.py   -> writes the SVGs + sheet.html next to this file.

Pure Python, no dependencies. Every silhouette is a hand-placed point list
turned into a smooth Catmull-Rom/Bezier outline (organic, not stacked
primitives). Colour and mono (e-ink) versions come from the same geometry.
"""
from __future__ import annotations

import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- palette
PALETTE = {
    "fur": "#E8552E",      # Tosk red
    "fur2": "#B83A1C",     # Tosk shade
    "cream": "#FFF0D2",    # belly / paper
    "ink": "#26190F",      # ink (eyes, nose, line work)
    "bark": "#6B4A32",     # Yggdrasil bark
    "bark2": "#47301F",    # bark shade
    "leaf": "#5DA659",     # ash leaf
    "leaf2": "#3C7D3A",    # leaf shade
    "gold": "#F5B63A",     # skill node
    "gold2": "#D98A1F",    # node shade
    "well": "#6FA9BE",     # Urd's well
    "blush": "#FF8A66",    # cheek
}
MONO = {k: "#000000" for k in PALETTE}
MONO.update(fur="#ffffff", cream="#ffffff", bark="#ffffff", leaf="#ffffff",
            gold="#ffffff", well="#ffffff", blush="none",
            fur2="hatch", bark2="hatch", leaf2="hatch", gold2="hatch")


class Style:
    def __init__(self, mono: bool, line: float = 4.0):
        self.mono = mono
        self.p = MONO if mono else PALETTE
        self.line = line

    def c(self, key: str) -> str:
        return self.p[key]


# ------------------------------------------------------------- geometry
Pt = tuple


def _xy(p):
    return (float(p[0]), float(p[1]))


def _sharp(p):
    return len(p) > 2 and p[2] == "s"


def crom(pts, closed=True, tension=1.0) -> str:
    """Catmull-Rom spline through pts -> SVG path (cubic Beziers).
    A point (x, y, 's') is a sharp corner."""
    n = len(pts)
    out = []
    x0, y0 = _xy(pts[0])
    out.append(f"M{x0:.1f} {y0:.1f}")
    segs = n if closed else n - 1
    for i in range(segs):
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        x1, y1 = _xy(p1)
        x2, y2 = _xy(p2)
        if _sharp(p1):
            c1 = (x1, y1)
        else:
            c1 = (x1 + (x2 - _xy(p0)[0]) * tension / 6, y1 + (y2 - _xy(p0)[1]) * tension / 6)
        if _sharp(p2):
            c2 = (x2, y2)
        else:
            c2 = (x2 - (_xy(p3)[0] - x1) * tension / 6, y2 - (_xy(p3)[1] - y1) * tension / 6)
        out.append(f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {x2:.1f} {y2:.1f}")
    if closed:
        out.append("Z")
    return "".join(out)


def _bez(p1, c1, c2, p2, t):
    mt = 1 - t
    x = mt**3 * p1[0] + 3 * mt**2 * t * c1[0] + 3 * mt * t**2 * c2[0] + t**3 * p2[0]
    y = mt**3 * p1[1] + 3 * mt**2 * t * c1[1] + 3 * mt * t**2 * c2[1] + t**3 * p2[1]
    dx = 3 * mt**2 * (c1[0] - p1[0]) + 6 * mt * t * (c2[0] - c1[0]) + 3 * t**2 * (p2[0] - c2[0])
    dy = 3 * mt**2 * (c1[1] - p1[1]) + 6 * mt * t * (c2[1] - c1[1]) + 3 * t**2 * (p2[1] - c2[1])
    return x, y, dx, dy


def ribbon(center, widths, steps=14, tension=1.0, cap="round") -> str:
    """Closed outline of a tapering ribbon along an open Catmull-Rom centerline.
    widths: half-widths at each center point (interpolated)."""
    n = len(center)
    left, right = [], []
    for i in range(n - 1):
        p0 = _xy(center[max(i - 1, 0)])
        p1 = _xy(center[i])
        p2 = _xy(center[i + 1])
        p3 = _xy(center[min(i + 2, n - 1)])
        c1 = (p1[0] + (p2[0] - p0[0]) * tension / 6, p1[1] + (p2[1] - p0[1]) * tension / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) * tension / 6, p2[1] - (p3[1] - p1[1]) * tension / 6)
        for k in range(steps + (1 if i == n - 2 else 0)):
            t = k / steps
            x, y, dx, dy = _bez(p1, c1, c2, p2, t)
            ln = math.hypot(dx, dy) or 1
            nx, ny = -dy / ln, dx / ln
            # smoothstep width blend
            tt = t * t * (3 - 2 * t)
            w = widths[i] * (1 - tt) + widths[i + 1] * tt
            left.append((x + nx * w, y + ny * w))
            right.append((x - nx * w, y - ny * w))
    pts = left + right[::-1]
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
    return d


def ell(cx, cy, rx, ry, rot=0) -> str:
    """Ellipse as a path (so it can be used anywhere a path is)."""
    k = 0.5523
    pts = []
    for a in (0, 90, 180, 270):
        pts.append((cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a))))
    # approximate by 4 Catmull points (crom of 8 points on circle is near perfect)
    ps = []
    for a in range(0, 360, 45):
        x = rx * math.cos(math.radians(a))
        y = ry * math.sin(math.radians(a))
        r = math.radians(rot)
        ps.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return crom(ps, closed=True, tension=1.08)


def tf(x, y, s=1.0, rot=0.0) -> str:
    return f'transform="translate({x:.1f} {y:.1f}) rotate({rot:.1f}) scale({s:.3f})"'


# --------------------------------------------------------------- drawing
_uid = [0]


def uid(prefix="c"):
    _uid[0] += 1
    return f"{prefix}{_uid[0]}"


def shape(st: Style, d: str, fill_key: str, shade_d: str | None = None, shade_key: str | None = None,
          stroke: bool = True, extra: str = "", mono_fill: str | None = None, line: float | None = None) -> str:
    """Flat fill + one clipped shade layer. In mono: white fill + black outline,
    shade becomes a hatch pattern."""
    lw = line if line is not None else st.line
    fill = st.c(fill_key)
    if st.mono and mono_fill:
        fill = mono_fill
    out = []
    cid = uid()
    if shade_d and shade_key:
        sh = st.c(shade_key)
        out.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
    out.append(f'<path d="{d}" fill="{fill}" {extra}/>')
    if shade_d and shade_key:
        if sh == "hatch":
            out.append(f'<path d="{shade_d}" fill="url(#hatch)" clip-path="url(#{cid})"/>')
        elif sh != "none":
            out.append(f'<path d="{shade_d}" fill="{sh}" clip-path="url(#{cid})"/>')
    if st.mono and stroke:
        out.append(f'<path d="{d}" fill="none" stroke="#000" stroke-width="{lw}" stroke-linejoin="round"/>')
    return "\n".join(out)


def defs(st: Style, extra: str = "") -> str:
    hatch = ('<pattern id="hatch" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(-35)">'
             '<rect width="7" height="7" fill="#fff"/><rect width="2.4" height="7" fill="#000"/></pattern>')
    return f"<defs>{hatch if st.mono else ''}{extra}</defs>"


def svg(w, h, body, title, vb=None) -> str:
    vb = vb or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{w}" height="{h}">\n'
            f'<title>{title}</title>\n{body}\n</svg>\n')


# =============================================================== TOSK
def ash_sprig(st: Style, x, y, rot=0, s=1.0, leaflets=5) -> str:
    """A pinnate ash sprig: stem with paired leaflets and a terminal leaflet."""
    g = [f"<g {tf(x, y, s, rot)}>"]
    stem_len = 18 + leaflets * 20
    g.append(f'<path d="M0 0 Q {stem_len/2} -4 {stem_len} 0" fill="none" stroke="{"#000" if st.mono else st.c("leaf2")}" stroke-width="3.5" stroke-linecap="round"/>')

    def leaflet(px, py, ang, ln=30, wd=13):
        pts = [(0, 0), (ln * 0.45, -wd / 2), (ln, 0, "s"), (ln * 0.45, wd / 2)]
        d = crom(pts, closed=True, tension=1.0)
        sh = crom([(0, 0), (ln * 0.45, 0), (ln, 0), (ln * 0.5, wd), (0, wd)], closed=True)
        return f'<g {tf(px, py, 1, ang)}>' + shape(st, d, "leaf", sh, "leaf2", stroke=True, line=2.4) + \
            f'<path d="M3 0 L {ln - 6} 0" fill="none" stroke="{"#000" if st.mono else st.c("leaf2")}" stroke-width="1.8" stroke-linecap="round"/></g>'

    for i in range(leaflets):
        px = 14 + i * 20
        for side in (-1, 1):
            g.append(leaflet(px, 0, side * 48))
    g.append(leaflet(stem_len - 6, 0, 0, 34, 14))
    g.append("</g>")
    return "\n".join(g)


def cloud(cx, cy, rx, ry, lobes=9, bump=0.14, rot=0.0, seed=0):
    """A scalloped leaf clump: outward lobes smooth, inward notches sharp."""
    pts = []
    for i in range(lobes * 2):
        a = 2 * math.pi * i / (lobes * 2) + rot
        wob = 1 + 0.05 * math.sin(3.1 * i + seed)
        r = (1 + bump) if i % 2 == 0 else (1 - bump * 0.6)
        x = cx + rx * r * wob * math.cos(a)
        y = cy + ry * r * wob * math.sin(a)
        pts.append((x, y) if i % 2 == 0 else (x, y, "s"))
    return pts


def tosk_body(st: Style, scroll=True) -> str:
    """Tosk, mid-leap, carrying a message scroll. Space 0..400 x 0..400."""
    o = []
    L = st.line
    ink = st.c("ink")

    shade_key = "fur2"
    dark_fur = "fur2" if not st.mono else "fur"   # far limbs: darker in colour, plain in mono

    # ---- tail (behind everything): huge plume arching over the back,
    # outer edge scalloped with sharp fur notches
    tail = crom([
        (150, 292), (122, 288, "s"), (94, 268), (70, 246, "s"), (48, 212), (38, 176, "s"), (34, 140), (42, 104, "s"),
        (60, 70), (88, 48, "s"), (122, 32), (158, 28, "s"), (190, 34), (218, 50, "s"), (240, 72),
        (252, 104, "s"),          # tip
        (230, 106), (206, 86), (164, 78), (120, 100), (104, 150), (118, 206), (156, 252), (190, 274),
    ], closed=True)
    tail_shade = crom([
        (150, 300), (120, 266), (90, 214), (84, 150), (104, 100), (150, 70), (205, 70), (240, 100),
        (252, 114), (236, 116), (210, 94), (165, 88), (128, 108), (115, 150), (128, 204), (166, 252), (190, 278),
    ], closed=True)
    o.append(shape(st, tail, "fur", tail_shade, shade_key))
    # a few fur strokes
    o.append(f'<path d="M66 188 q 8 -10 10 -24 M78 116 q 10 -8 14 -20 M146 46 q 10 4 22 2" fill="none" '
             f'stroke="{ink if st.mono else st.c("fur2")}" stroke-width="3" stroke-linecap="round"/>')

    # ---- hind legs: big haunch, short shin trailing back, paw with toes
    def paw(x, y, rot, s=1.0, key="fur"):
        d = crom([(-16, -8), (6, -9), (16, -5, "s"), (18, 0), (16, 5, "s"), (6, 9), (-16, 8), (-20, 0)], closed=True)
        g = f'<g {tf(x, y, s, rot)}>' + shape(st, d, key, mono_fill="#fff") + \
            f'<path d="M6 -4 l 10 -1 M8 0 l 10 0 M6 4 l 10 1" fill="none" stroke="{ink}" stroke-width="2" stroke-linecap="round" opacity="0.6"/></g>'
        return g

    far_shin = ribbon([(160, 278), (128, 306), (104, 332)], [19, 15, 11])
    o.append(shape(st, far_shin, dark_fur, mono_fill="#fff"))
    o.append(paw(96, 344, 125, 1.1, dark_fur))
    near_shin = ribbon([(174, 292), (148, 322), (128, 352)], [21, 17, 12])
    o.append(shape(st, near_shin, "fur"))
    o.append(paw(122, 364, 125, 1.15))

    # ---- body: ONE silhouette from neck down to a big rounded haunch
    body = crom([
        (236, 150), (266, 174), (280, 214), (268, 256), (240, 286), (208, 302), (176, 310), (148, 294),
        (138, 260), (150, 226), (172, 200), (206, 166),
    ], closed=True)
    body_shade = crom([(140, 150), (200, 150), (170, 200), (168, 240), (182, 280), (230, 300), (240, 330), (130, 330)], closed=True)
    o.append(shape(st, body, "fur", body_shade, shade_key))
    belly = crom([(254, 186), (274, 216), (264, 254), (236, 282), (206, 284), (212, 246), (228, 206), (238, 186)],
                 closed=True)
    o.append(shape(st, belly, "cream", stroke=st.mono, line=2.4))
    # hip crease: the one line that says "haunch"
    o.append(f'<path d="M206 258 q -18 18 -8 44" fill="none" stroke="{ink if st.mono else st.c("fur2")}" stroke-width="3.2" stroke-linecap="round"/>')

    # ---- far arm (behind scroll)
    far_arm = ribbon([(240, 204), (262, 226), (286, 244)], [10, 9, 8])
    o.append(shape(st, far_arm, dark_fur, mono_fill="#fff"))

    # ---- far ear (behind head)
    far_ear = crom([(246, 100), (252, 72), (258, 60, "s"), (276, 98)], closed=True)
    o.append(shape(st, far_ear, dark_fur, mono_fill="#fff"))
    o.append(shape(st, "M253 70 L 256 48 L 262 66 Z", dark_fur, mono_fill="#fff", stroke=st.mono, line=2.4))

    # ---- head: 3/4 view, snout to the right
    head = crom([
        (266, 80), (300, 86), (322, 110), (338, 138), (334, 160), (318, 174), (286, 182), (252, 178),
        (230, 156), (228, 120), (242, 94),
    ], closed=True)
    head_shade = crom([(220, 150), (250, 150), (262, 170), (300, 182), (340, 170), (350, 200), (220, 200)], closed=True)
    o.append(shape(st, head, "fur", head_shade, shade_key))
    # near ear + soft two-point tuft
    ear = crom([(278, 94), (286, 66), (294, 48, "s"), (314, 92)], closed=True)
    o.append(shape(st, ear, "fur"))
    tuft = crom([(288, 58), (290, 30, "s"), (297, 50), (306, 26, "s"), (308, 60)], closed=True)
    o.append(shape(st, tuft, dark_fur, mono_fill="#fff", stroke=st.mono, line=2.4))
    inner = crom([(286, 90), (291, 70), (296, 58, "s"), (308, 90)], closed=True)
    o.append(shape(st, inner, "cream" if not st.mono else "fur", stroke=False))
    # muzzle cream patch
    snout = crom([(298, 140), (324, 134), (340, 150), (330, 170), (306, 180), (286, 172), (284, 154)], closed=True)
    o.append(shape(st, snout, "cream", stroke=False))

    # ---- face
    # far eye (3/4): a bit smaller, same sly lid
    o.append(f'<path d="{ell(250, 128, 10, 13, -4)}" fill="#fff"/>')
    o.append(f'<path d="{ell(253, 130, 6.5, 8.5)}" fill="{ink}"/>')
    o.append(f'<circle cx="256" cy="125" r="2.4" fill="#fff"/>')
    lid_fill = st.c("fur") if not st.mono else "#fff"
    lid2 = crom([(238, 122), (250, 112), (262, 120), (258, 125), (242, 126)], closed=True)
    o.append(f'<path d="{lid2}" fill="{lid_fill}"/>')
    o.append(f'<path d="M240 121 Q 250 113 261 119" fill="none" stroke="{ink}" stroke-width="3" stroke-linecap="round"/>')
    # near eye: big, with a cheeky lid
    o.append(f'<path d="{ell(294, 124, 15, 17, 6)}" fill="#fff"/>')
    o.append(f'<path d="{ell(297, 127, 9.5, 11)}" fill="{ink}"/>')
    o.append(f'<circle cx="301" cy="120" r="3.6" fill="#fff"/>')
    o.append(f'<circle cx="292" cy="132" r="1.8" fill="#fff"/>')
    lid = crom([(278, 114), (296, 102), (312, 114), (306, 120), (284, 120)], closed=True)
    o.append(f'<path d="{lid}" fill="{lid_fill}"/>')
    o.append(f'<path d="M280 114 Q 296 103 311 112" fill="none" stroke="{ink}" stroke-width="3.5" stroke-linecap="round"/>')
    # brow
    o.append(f'<path d="M284 100 Q 300 92 316 100" fill="none" stroke="{ink}" stroke-width="3.5" stroke-linecap="round"/>')
    # nose
    o.append(f'<path d="{crom([(332, 136), (346, 140), (342, 152), (328, 148)], closed=True)}" fill="{ink}"/>')
    # grin with a buck tooth
    o.append(f'<path d="M300 162 Q 318 180 338 160" fill="none" stroke="{ink}" stroke-width="3.5" stroke-linecap="round"/>')
    o.append(f'<path d="M313 168 l 0 8 q 5 3 9 0 l 0 -6 z" fill="#fff" stroke="{ink}" stroke-width="2"/>')
    # cheek blush
    if not st.mono:
        o.append(f'<circle cx="286" cy="154" r="7" fill="{st.c("blush")}" opacity="0.8"/>')

    # ---- scroll in the paws (white paper, gold rollers, always outlined)
    if scroll:
        o.append('<g transform="translate(312 248) rotate(-18)">')
        # unrolled banner with a gentle sag, rolled gold ends
        paper = "M-34 -17 Q 0 -11 34 -17 V 17 Q 0 11 -34 17 Z"
        o.append(f'<path d="{paper}" fill="{"#fff" if st.mono else "#FFFDF6"}" stroke="{ink}" stroke-width="2.6" stroke-linejoin="round"/>')
        for rx in (-36, 36):
            roll = f"M{rx-7} -23 H {rx+7} Q {rx+11} -23 {rx+11} -19 V 19 Q {rx+11} 23 {rx+7} 23 H {rx-7} Q {rx-11} 23 {rx-11} 19 V -19 Q {rx-11} -23 {rx-7} -23 Z"
            o.append(shape(st, roll, "gold", f"M{rx} -23 H {rx+11} V 23 H {rx} Z", "gold2", stroke=False))
            o.append(f'<path d="{roll}" fill="none" stroke="{ink}" stroke-width="2.6"/>')
            o.append(f'<path d="M{rx} -23 V 23" fill="none" stroke="{ink}" stroke-width="1.8" opacity="0.5"/>')
        # rune t (ᛏ) and two 'text' lines
        o.append(f'<path d="M-14 -8 V 9 M-14 -8 L -21 -1 M-14 -8 L -7 -1 M-1 -4 h 18 M-1 4 h 12" fill="none" '
                 f'stroke="{ink}" stroke-width="2.6" stroke-linecap="round"/>')
        o.append("</g>")

    # ---- near arm + paws (in front): paw grips the near roll
    near_arm = ribbon([(262, 208), (282, 232), (304, 258)], [12, 10, 9])
    o.append(shape(st, near_arm, "fur"))
    o.append(shape(st, ell(310, 264, 11, 9, -20), "fur"))
    o.append(shape(st, ell(280, 262, 10, 8, -20), dark_fur, mono_fill="#fff"))

    return "\n".join(o)


def tosk_svg(st: Style) -> str:
    body = [defs(st), tosk_body(st)]
    # a couple of motion leaves (he is leaping through the branches)
    body.append(ash_sprig(st, 300, 330, 20, 0.75, 4))
    body.append(ash_sprig(st, 40, 330, -160, 0.6, 3))
    body.append(f'<path d="M60 304 q 18 10 44 6 M48 322 q 10 8 26 8" fill="none" stroke="{st.c("ink") if st.mono else st.c("leaf2")}" stroke-width="3" stroke-linecap="round" opacity="0.6"/>')
    return svg(400, 400, "\n".join(body), "Tosk, the messenger squirrel of Yggdrasil")


# =============================================================== ICON
def icon_mark(st: Style) -> str:
    """Compact Tosk bust: head in profile + big tail curl. Space 0..512."""
    o = []
    ink = st.c("ink")
    # tail: comma curl framing the left and top
    tail = crom([
        (250, 440), (160, 420), (90, 350), (74, 250), (110, 150), (190, 96), (280, 92), (330, 120),
        (352, 160, "s"),
        (320, 160), (290, 140), (220, 140), (166, 180), (150, 250), (176, 330), (240, 380), (300, 395),
    ], closed=True)
    tail_sh = crom([
        (250, 460), (200, 440), (150, 380), (130, 300), (140, 200), (180, 150), (230, 120), (300, 120),
        (352, 170), (320, 175), (290, 150), (225, 150), (176, 185), (160, 250), (186, 330), (245, 385), (310, 405),
    ], closed=True)
    if st.mono:
        o.append(shape(st, tail, "fur", mono_fill="#000", line=10))
    else:
        o.append(shape(st, tail, "fur", tail_sh, "fur2", line=10))
    # body hint
    body = crom([(240, 300), (300, 280), (360, 300), (390, 360), (370, 430), (300, 460), (230, 440), (210, 380)], closed=True)
    o.append(shape(st, body, "fur", line=10))
    belly = crom([(300, 320), (350, 330), (372, 380), (350, 430), (300, 445), (280, 400), (282, 350)], closed=True)
    o.append(shape(st, belly, "cream", stroke=False))
    # head (scaled up a touch so the face carries the icon at 48 px)
    o.append('<g transform="translate(340 262) scale(1.26) translate(-340 -262)">')
    head = crom([(272, 190), (330, 190), (386, 220), (428, 268), (420, 312), (380, 336), (320, 340), (270, 316), (250, 270), (254, 220)], closed=True)
    o.append(shape(st, head, "fur", line=10))
    ear = crom([(284, 200), (300, 140), (312, 112, "s"), (350, 196)], closed=True)
    o.append(shape(st, ear, "fur", line=10))
    tuft = "M298 128 L 306 70 L 318 118 L 338 86 L 334 136 Z"
    o.append(shape(st, tuft, "fur2" if not st.mono else "fur", mono_fill="#000", stroke=False))
    snout = crom([(372, 262), (412, 264), (428, 290), (414, 322), (378, 334), (350, 316), (348, 286)], closed=True)
    o.append(shape(st, snout, "cream", stroke=False))
    # eye
    o.append(f'<path d="{ell(352, 254, 26, 28)}" fill="#fff"/>')
    o.append(f'<path d="{ell(356, 258, 16, 18)}" fill="{ink}"/>')
    o.append(f'<circle cx="362" cy="246" r="6" fill="#fff"/>')
    lid = crom([(324, 238), (352, 218), (380, 238), (372, 246), (334, 246)], closed=True)
    o.append(f'<path d="{lid}" fill="{st.c("fur") if not st.mono else "#fff"}"/>')
    o.append(f'<path d="M326 238 Q 352 220 378 236" fill="none" stroke="{ink}" stroke-width="7" stroke-linecap="round"/>')
    # nose + grin
    o.append(f'<path d="{crom([(420, 282), (438, 288), (432, 302), (414, 298)], closed=True)}" fill="{ink}"/>')
    o.append(f'<path d="M382 314 Q 404 334 428 310" fill="none" stroke="{ink}" stroke-width="7" stroke-linecap="round"/>')
    o.append("</g>")
    return "\n".join(o)


def icon_svg(st: Style) -> str:
    bg = "#26190F" if not st.mono else "#fff"
    o = [defs(st)]
    o.append(f'<rect width="512" height="512" rx="116" fill="{bg}"/>')
    if st.mono:
        o.append('<rect x="6" y="6" width="500" height="500" rx="112" fill="none" stroke="#000" stroke-width="12"/>')
    o.append(f'<g transform="translate(0 0) scale(1.0)">{icon_mark(st)}</g>')
    return svg(512, 512, "\n".join(o), "tosk app icon")


def wordmark(st: Style, x=0, y=0, h=120, color=None) -> str:
    """'tosk' lowercase, rounded monoline, drawn as strokes. Height h = cap height."""
    s = h / 120.0
    col = color or st.c("ink")
    sw = 26
    o = [f'<g transform="translate({x} {y}) scale({s})" fill="none" stroke="{col}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">']
    # t
    o.append('<path d="M34 0 V 86 Q 34 120 70 120"/>')
    o.append('<path d="M6 40 H 66"/>')
    # o
    o.append('<circle cx="146" cy="78" r="40"/>')
    # s
    spts = [(276, 50), (248, 36), (218, 54), (244, 76), (274, 98), (248, 122), (216, 108)]
    o.append(f'<path d="{crom(spts, closed=False, tension=1.0)}"/>')
    # k
    o.append('<path d="M322 0 V 120"/>')
    o.append('<path d="M324 86 L 374 36"/>')
    o.append('<path d="M340 72 L 382 120"/>')
    o.append("</g>")
    return "\n".join(o)


def logo_svg(st: Style) -> str:
    o = [defs(st)]
    o.append(f'<g transform="translate(10 4) scale(0.38)">{icon_mark(st)}</g>')
    o.append(wordmark(st, 232, 44, 120))
    return svg(640, 210, "\n".join(o), "tosk logo")


# =============================================================== YGGDRASIL
def node(st: Style, x, y, r=34, done=False) -> str:
    o = []
    ring = st.c("ink")
    fill = "gold" if not st.mono else "gold"
    d = ell(x, y, r, r)
    sh = ell(x + r * 0.15, y + r * 0.3, r * 0.95, r * 0.8)
    o.append(f'<circle cx="{x}" cy="{y}" r="{r + 5}" fill="{ring}"/>')
    if st.mono:
        o.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff"/>')
    else:
        cid = uid("n")
        o.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        o.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{st.c("gold")}"/>')
        o.append(f'<path d="{sh}" fill="{st.c("gold2")}" clip-path="url(#{cid})"/>')
    # a small rune-ish glyph (star) in the node
    o.append(f'<path d="M{x} {y-13} V {y+13} M{x-11} {y-7} L {x+11} {y+7} M{x+11} {y-7} L {x-11} {y+7}" '
             f'fill="none" stroke="{ring}" stroke-width="4" stroke-linecap="round"/>')
    return "\n".join(o)


def leaf_clump(st: Style, pts, shade_pts) -> str:
    return shape(st, crom(pts, closed=True), "leaf", crom(shade_pts, closed=True), "leaf2")


def yggdrasil_svg(st: Style) -> str:
    W, H = 800, 1100
    o = [defs(st)]
    ink = st.c("ink")

    # ------ roots (behind trunk): three great roots + Urd's well
    well = ell(400, 1030, 150, 40)
    o.append(shape(st, well, "well", stroke=True, line=5))
    o.append(f'<path d="M300 1030 q 20 -10 40 0 t 40 0 t 40 0 t 40 0 M330 1046 q 20 -10 40 0 t 40 0 t 40 0" '
             f'fill="none" stroke="{"#000" if st.mono else "#fff"}" stroke-width="4" stroke-linecap="round" opacity="0.7"/>')
    roots = [
        ([(400, 960), (300, 990), (190, 1010), (90, 1070)], [52, 34, 22, 8]),
        ([(400, 960), (400, 1010), (420, 1060), (410, 1098)], [48, 28, 16, 6]),
        ([(400, 960), (500, 990), (610, 1010), (720, 1060)], [52, 34, 22, 8]),
    ]
    for c, w in roots:
        d = ribbon(c, w)
        sh = ribbon([(p[0], p[1] + 14) for p in c], [ww * 0.9 for ww in w])
        o.append(shape(st, d, "bark", sh, "bark2"))

    # ------ Níðhöggr at the roots: a horned serpent coiled through the roots,
    # jaws on the left root. Ink silhouette with a pale belly stripe.
    o.append('<g transform="translate(200 1040) scale(1.35) translate(-200 -1040)">')
    serp_c = [(330, 1076), (270, 1092), (200, 1084), (146, 1058), (112, 1020), (140, 992), (190, 992), (228, 1006)]
    serp_w = [6, 12, 17, 19, 18, 16, 13, 9]
    o.append(f'<path d="{ribbon(serp_c, serp_w)}" fill="{ink}"/>')
    belly_c = [(c[0], c[1] + 10) for c in serp_c[:4]]
    o.append(f'<path d="{ribbon(belly_c, [1, 2.5, 3.5, 3.5])}" fill="{"#fff" if st.mono else st.c("cream")}" opacity="0.8"/>')
    # head: wedge with open jaw biting the root, horns, eye
    o.append('<g transform="translate(254 1006) scale(1.45) translate(-222 -1024)">')
    hd = crom([(196, 1012), (218, 1004), (248, 1010, "s"), (236, 1024), (250, 1040, "s"), (224, 1044), (204, 1040), (192, 1026)], closed=True)
    o.append(f'<path d="{hd}" fill="{ink}"/>')
    o.append(f'<path d="M206 1012 l -10 -22 l 20 10 z M222 1006 l 4 -24 l 12 18 z" fill="{ink}"/>')
    o.append(f'<circle cx="216" cy="1020" r="3.5" fill="#fff"/>')
    o.append(f'<path d="M236 1014 l 4 6 M242 1034 l -4 -6" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>')
    o.append('</g>')
    # back spines
    for (x, y) in [(284, 1080), (250, 1086), (176, 1066), (140, 1034)]:
        o.append(f'<path d="M{x} {y} l -3 -14 l 9 10 z" fill="{ink}"/>')
    o.append("</g>")

    # ------ trunk: slightly twisted, tapering
    trunk = crom([
        (348, 975), (352, 880), (342, 780), (352, 660), (344, 540), (356, 430), (350, 330), (366, 240),
        (400, 200), (434, 240), (446, 330), (440, 430), (452, 540), (446, 660), (456, 780), (448, 880), (452, 975),
        (400, 990),
    ], closed=True)
    trunk_sh = crom([(400, 1000), (408, 880), (396, 780), (408, 660), (398, 540), (412, 430), (404, 330), (410, 240),
                     (440, 220), (470, 240), (470, 1000)], closed=True)
    o.append(shape(st, trunk, "bark", trunk_sh, "bark2"))
    # long bark grain lines
    o.append(f'<path d="M372 940 C 360 820 376 700 364 560 M382 420 C 378 360 388 300 396 250 M420 900 C 428 820 418 760 426 680" '
             f'fill="none" stroke="{"#000" if st.mono else st.c("bark2")}" stroke-width="4" stroke-linecap="round" opacity="0.7"/>')
    # runes: t o s k carved on the trunk (ᛏ ᛟ ᛋ ᚲ)
    rune_col = ink if st.mono else st.c("cream")
    runes = [
        "M0 -14 V 14 M0 -14 L -10 -2 M0 -14 L 10 -2",          # ᛏ
        "M-9 14 L 0 2 L 9 14 M-9 -2 L 0 -14 L 9 -2 L 0 10 L -9 -2",  # ᛟ (simplified)
        "M-7 -14 L 7 -14 L -7 0 L 7 14 L -7 14",              # ᛋ-ish zig
        "M8 -14 L -6 0 L 8 14",                               # ᚲ
    ]
    for i, r in enumerate(runes):
        o.append(f'<g transform="translate(392 {452 + i * 44})"><path d="{r}" fill="none" stroke="{rune_col}" '
                 f'stroke-width="4" stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/></g>')

    # ------ boughs (units): alternate left / right, each carrying 2 skill nodes
    boughs = [
        # centerline, widths, node positions
        ([(380, 860), (300, 830), (220, 790), (150, 720)], [22, 16, 11, 6], [(265, 812), (150, 720)]),
        ([(420, 740), (500, 700), (580, 650), (650, 580)], [22, 16, 11, 6], [(540, 676), (650, 580)]),
        ([(380, 600), (300, 560), (220, 500), (160, 430)], [22, 15, 10, 6], [(262, 532), (160, 430)]),
        ([(420, 470), (500, 430), (570, 380), (630, 300)], [20, 14, 9, 5], [(535, 404), (630, 300)]),
    ]
    nodes = []
    for c, w, ns in boughs:
        d = ribbon(c, w)
        sh = ribbon([(p[0], p[1] + 9) for p in c], [ww * 0.85 for ww in w])
        o.append(shape(st, d, "bark", sh, "bark2"))
        nodes += ns
    # scalloped leaf clumps on the boughs + a big layered crown
    clumps = [
        (165, 690, 68, 54, 8, 0.3),
        (655, 565, 72, 56, 8, 1.1),
        (160, 400, 64, 52, 8, 2.0),
        (645, 275, 70, 54, 8, 0.7),
        # crown: three overlapping clouds
        (300, 210, 95, 72, 9, 1.4),
        (505, 200, 100, 76, 9, 2.6),
        (400, 150, 130, 88, 11, 0.2),
    ]
    for (cx, cy, rx, ry, lobes, seed) in clumps:
        c = cloud(cx, cy, rx, ry, lobes, 0.13, seed, seed)
        sh = cloud(cx + 14, cy + 30, rx, ry, lobes, 0.13, seed, seed)
        o.append(leaf_clump(st, c, sh))
    # pinnate ash sprigs for identity
    for (x, y, r, s) in [(120, 640, -120, 0.8), (700, 520, -50, 0.8), (110, 350, -115, 0.8), (700, 225, -55, 0.8),
                         (520, 110, -60, 0.9), (280, 120, -120, 0.9)]:
        o.append(ash_sprig(st, x, y, r, s, 3))

    # ------ the eagle, perched at the crown, facing left (ink silhouette)
    eagle = crom([
        (372, 14), (402, 8), (422, 24), (430, 54), (440, 90), (444, 124), (436, 150, "s"), (420, 142), (408, 154, "s"),
        (398, 140), (384, 150, "s"), (376, 128), (364, 96), (358, 64), (358, 38), (364, 22),
    ], closed=True)
    o.append(f'<path d="{eagle}" fill="{ink}"/>')
    # pale head (reads 'eagle' at a glance), hooked gold beak, fierce eye
    head = crom([(366, 16), (402, 8), (422, 26), (420, 48), (400, 60), (372, 58), (358, 42), (358, 28)], closed=True)
    o.append(shape(st, head, "cream", stroke=True, line=3))
    if not st.mono:
        o.append(f'<path d="{head}" fill="none" stroke="{ink}" stroke-width="3"/>')
    beak = "M364 30 L 336 40 Q 346 56 364 54 Z"
    o.append(f'<path d="{beak}" fill="{st.c("gold")}" stroke="{ink}" stroke-width="3" stroke-linejoin="round"/>')
    o.append(f'<path d="M372 28 l 14 4" fill="none" stroke="{ink}" stroke-width="4" stroke-linecap="round"/>')  # brow
    o.append(f'<circle cx="380" cy="37" r="5" fill="#fff"/><circle cx="381" cy="38" r="2.6" fill="{ink}"/>')
    # folded wing in bark tone with a few feather lines
    wing = crom([(404, 52), (430, 66), (442, 108), (434, 146, "s"), (418, 120), (404, 86)], closed=True)
    o.append(f'<path d="{wing}" fill="{"#fff" if st.mono else st.c("bark")}" stroke="{ink}" stroke-width="3"/>')
    o.append(f'<path d="M414 72 l 12 24 M410 92 l 10 26 M422 100 l 8 24" fill="none" stroke="{ink}" stroke-width="2.4" stroke-linecap="round"/>')
    # talons gripping the crown
    o.append(f'<path d="M384 146 l -10 8 M394 150 l -2 10 M404 148 l 8 8" fill="none" stroke="{st.c("gold") if not st.mono else "#000"}" stroke-width="4" stroke-linecap="round"/>')
    # crown node
    nodes.append((400, 200))

    for (x, y) in nodes:
        o.append(node(st, x, y, 34))

    # Tosk racing up the trunk with a message
    o.append(f'<g transform="translate(318 700) rotate(-30) scale(0.4) translate(-200 -220)">{tosk_body(st, scroll=True)}</g>')

    return svg(W, H, "\n".join(o), "Yggdrasil: the course tree")


def branch_tile_svg(st: Style) -> str:
    o = [defs(st)]
    # bark with a single shade layer along the lower-right side of each limb
    for c, w in (([(200, 360), (202, 290), (200, 230)], [26, 22, 20]),
                 ([(200, 236), (160, 180), (110, 120), (80, 60)], [20, 15, 10, 6]),
                 ([(200, 236), (242, 180), (290, 120), (320, 60)], [20, 15, 10, 6])):
        d = ribbon(c, w)
        sh = ribbon([(x + 9, y + 6) for x, y in c], [ww * 0.85 for ww in w])
        o.append(shape(st, d, "bark", sh, "bark2"))
    # leaves
    o.append(ash_sprig(st, 150, 160, -40, 0.7, 3))
    o.append(ash_sprig(st, 262, 150, 40, 0.7, 3))
    o.append(ash_sprig(st, 230, 300, 20, 0.6, 3))
    o.append(node(st, 200, 350, 30))
    o.append(node(st, 80, 60, 30))
    o.append(node(st, 320, 60, 30))
    return svg(400, 400, "\n".join(o), "Branch tile: a fork between skill nodes")


# =============================================================== SHEET
def sheet_html() -> str:
    sw = "".join(f'<div class="sw"><i style="background:{v}"></i><b>{k}</b><span>{v}</span></div>' for k, v in PALETTE.items())
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>tosk brand — flat modern mascot</title>
<style>
body{{margin:0;padding:28px;background:#F3EDE3;font:15px/1.4 "Segoe UI",system-ui,sans-serif;color:#26190F}}
h1{{font-size:34px;margin:0 0 4px}} p{{margin:0 0 18px;opacity:.75}}
.grid{{display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}}
.card{{background:#fff;border-radius:16px;padding:14px;box-shadow:0 1px 3px rgba(0,0,0,.08);text-align:center}}
.card img{{display:block;margin:0 auto}} .card small{{display:block;margin-top:8px;opacity:.7}}
.row{{display:flex;gap:16px;align-items:flex-end;justify-content:center}}
.eink{{background:#fafafa;border:1px solid #ccc}}
.pal{{display:flex;flex-wrap:wrap;gap:10px}} .sw{{display:flex;align-items:center;gap:6px;background:#fff;border-radius:10px;padding:6px 10px 6px 6px}}
.sw i{{width:30px;height:30px;border-radius:8px;display:block}} .sw span{{opacity:.6;font-size:12px}}
</style></head><body>
<h1>tosk</h1><p>flat modern mascot exploration — colour and e-ink side by side</p>
<div class="grid">
 <div class="card"><img src="tosk.svg" width="360" height="360"><small>Tosk</small></div>
 <div class="card eink"><img src="tosk-mono.svg" width="360" height="360"><small>Tosk · e-ink</small></div>
 <div class="card"><div class="row">
   <img src="icon.svg" width="192" height="192"><img src="icon.svg" width="96" height="96"><img src="icon.svg" width="48" height="48">
   <img src="icon-mono.svg" width="96" height="96"><img src="icon-mono.svg" width="48" height="48"></div><small>App icon · 192 / 96 / 48 px, colour and e-ink</small></div>
 <div class="card"><img src="logo.svg" width="480" height="158"><small>Logo</small></div>
 <div class="card"><img src="branch-tile.svg" width="240" height="240"><small>Branch tile</small></div>
 <div class="card eink"><img src="branch-tile-mono.svg" width="240" height="240"><small>Branch tile · e-ink</small></div>
 <div class="card"><img src="yggdrasil.svg" width="440" height="605"><small>Yggdrasil: the course tree</small></div>
 <div class="card eink"><img src="yggdrasil-mono.svg" width="440" height="605"><small>Yggdrasil · e-ink</small></div>
 <div class="card" style="width:460px"><div class="pal">{sw}</div><small>Palette</small></div>
</div>
</body></html>
"""


def main():
    C, M = Style(False), Style(True)
    files = {
        "tosk.svg": tosk_svg(C), "tosk-mono.svg": tosk_svg(M),
        "icon.svg": icon_svg(C), "icon-mono.svg": icon_svg(M),
        "logo.svg": logo_svg(C),
        "yggdrasil.svg": yggdrasil_svg(C), "yggdrasil-mono.svg": yggdrasil_svg(M),
        "branch-tile.svg": branch_tile_svg(C), "branch-tile-mono.svg": branch_tile_svg(M),
        "sheet.html": sheet_html(),
    }
    for name, content in files.items():
        (HERE / name).write_text(content, encoding="utf-8")
        print(f"{name:22s} {len(content.encode()) / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
