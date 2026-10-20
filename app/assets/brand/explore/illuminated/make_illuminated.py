#!/usr/bin/env python3
"""tosk brand exploration: illuminated-manuscript / Norse-Celtic marginalia style.

Writes, next to this script:
  tosk.svg, tosk-mono.svg, icon.svg, icon-mono.svg, logo.svg,
  yggdrasil.svg, yggdrasil-mono.svg, branch-tile.svg, branch-tile-mono.svg, sheet.html

No dependencies. Every form is a hand-written Bezier silhouette; the "mono" variants are
pure #000 / #fff with pattern fills (hatching, stipple) standing in for the pigments.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- palette
COLOUR = dict(
    ink="#1F1813",      # iron-gall ink
    red="#C4361B",      # vermilion
    blue="#2B4C8C",     # ultramarine
    green="#3F8C6B",    # verdigris
    gold="#D9A441",     # gold ochre (gold leaf)
    golddark="#A6762B", # shaded gold / bark
    cream="#FBF3E1",    # lead-white highlight
    paper="#F2E7D0",    # vellum
    ribbon="#D9A441",   # ribbon fill inside interlace
)
MONO = dict(
    ink="#000000",
    red="url(#hatch)",
    blue="url(#cross)",
    green="#ffffff",
    gold="url(#stipple)",
    golddark="url(#hatchv)",
    cream="#ffffff",
    paper="#ffffff",
    ribbon="#ffffff",
)


def mono_defs():
    """Pattern fills that stand in for pigments on e-ink. Pure black on white."""
    return """<defs>
<pattern id="hatch" patternUnits="userSpaceOnUse" width="7" height="7" patternTransform="rotate(45)">
  <rect width="7" height="7" fill="#fff"/><line x1="0" y1="0" x2="0" y2="7" stroke="#000" stroke-width="1.6"/></pattern>
<pattern id="hatchv" patternUnits="userSpaceOnUse" width="6" height="6">
  <rect width="6" height="6" fill="#fff"/><line x1="3" y1="0" x2="3" y2="6" stroke="#000" stroke-width="1.3"/></pattern>
<pattern id="cross" patternUnits="userSpaceOnUse" width="6" height="6">
  <rect width="6" height="6" fill="#fff"/><line x1="0" y1="3" x2="6" y2="3" stroke="#000" stroke-width="1.2"/>
  <line x1="3" y1="0" x2="3" y2="6" stroke="#000" stroke-width="1.2"/></pattern>
<pattern id="stipple" patternUnits="userSpaceOnUse" width="6" height="6">
  <rect width="6" height="6" fill="#fff"/><circle cx="1.5" cy="1.5" r="1" fill="#000"/><circle cx="4.5" cy="4.5" r="1" fill="#000"/></pattern>
</defs>
"""


# ---------------------------------------------------------------- geometry helpers
def bez(s, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = s
    mt = 1 - t
    return (mt ** 3 * x0 + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t ** 3 * x3,
            mt ** 3 * y0 + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t ** 3 * y3)


def bez_d(s, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = s
    mt = 1 - t
    return (3 * mt * mt * (x1 - x0) + 6 * mt * t * (x2 - x1) + 3 * t * t * (x3 - x2),
            3 * mt * mt * (y1 - y0) + 6 * mt * t * (y2 - y1) + 3 * t * t * (y3 - y2))


def segs(pts):
    """[(x,y), c1, c2, p, c1, c2, p, ...] -> list of cubic segments."""
    out = []
    for i in range(1, len(pts) - 2, 3):
        out.append((pts[i - 1], pts[i], pts[i + 1], pts[i + 2]))
    return out


def path_d(pts):
    d = "M%.1f,%.1f" % pts[0]
    for s in segs(pts):
        d += " C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (s[1] + s[2] + s[3])
    return d


def ribbon(pts, w0, w1, n=14, power=1.0, cap="flat"):
    """Closed outline around a cubic chain, width tapering from w0 to w1."""
    ss = segs(pts)
    samples = []
    N = len(ss)
    for i, s in enumerate(ss):
        for k in range(n + 1):
            if i > 0 and k == 0:
                continue
            t = k / n
            u = (i + t) / N
            p = bez(s, t)
            dx, dy = bez_d(s, t)
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L, dx / L
            w = w0 + (w1 - w0) * (u ** power)
            samples.append((p, (nx, ny), w))
    left = [(p[0] + nx * w / 2, p[1] + ny * w / 2) for p, (nx, ny), w in samples]
    right = [(p[0] - nx * w / 2, p[1] - ny * w / 2) for p, (nx, ny), w in samples]
    d = "M" + " L".join("%.1f,%.1f" % q for q in left)
    if cap == "round":
        p, (nx, ny), w = samples[-1]
        d += " A%.1f,%.1f 0 0 1 %.1f,%.1f" % (w / 2, w / 2, right[-1][0], right[-1][1])
    d += " L" + " L".join("%.1f,%.1f" % q for q in reversed(right)) + " Z"
    return d


def centre(pts, t_abs):
    """point on a cubic chain at global parameter t in [0, nsegs]"""
    ss = segs(pts)
    i = min(int(t_abs), len(ss) - 1)
    return bez(ss[i], t_abs - i)


def tangent(pts, t_abs):
    ss = segs(pts)
    i = min(int(t_abs), len(ss) - 1)
    dx, dy = bez_d(ss[i], t_abs - i)
    return math.degrees(math.atan2(dy, dx))


def P(d, fill, stroke=None, sw=None, extra=""):
    a = ' fill="%s"' % fill
    if stroke:
        a += ' stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"' % (stroke, sw)
    return '<path d="%s"%s %s/>\n' % (d, a, extra)


def S(d, stroke, sw, extra="", cap="round"):
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round" %s/>\n' % (d, stroke, sw, cap, extra)


# ---------------------------------------------------------------- runes (Elder Futhark, 10 x 16 cell)
RUNES = {
    "t": [[(5, 0), (5, 16)], [(0, 5), (5, 0), (10, 5)]],
    "o": [[(5, 0), (10, 6)], [(5, 0), (0, 6)], [(10, 6), (0, 16)], [(0, 6), (10, 16)]],
    "s": [[(8, 0), (2, 5), (8, 10), (2, 16)]],
    "k": [[(8, 0), (2, 8), (8, 16)]],
    "r": [[(2, 0), (2, 16)], [(2, 0), (8, 4), (2, 8), (8, 16)]],
    "a": [[(2, 0), (2, 16)], [(2, 2), (9, 6)], [(2, 7), (9, 11)]],
}


def runes(text, x, y, size, ink, sw):
    """Draw runes left to right, cell height = size."""
    k = size / 16.0
    out = ""
    for ch in text:
        for stroke in RUNES[ch]:
            d = "M" + " L".join("%.1f,%.1f" % (x + px * k, y + py * k) for px, py in stroke)
            out += S(d, ink, sw)
        x += 14 * k
    return out


# ---------------------------------------------------------------- interlace (two-strand braid)
def braid(x0, x1, y, period, amp, C, sw_ink=3.0, w_rib=7.0):
    """Horizontal two-strand braid from x0 to x1 at height y. Ribbons with ink edges,
    over/under alternating. Returns svg string."""
    out = ""
    n = max(1, int(round((x1 - x0) / period)))
    period = (x1 - x0) / n
    h = period / 2
    k = 0.42 * h  # handle length for cosine-ish arcs

    def strand(sign):
        pts = [(x0, y + sign * amp)]
        for i in range(2 * n):
            xa = x0 + i * h
            xb = xa + h
            sgn = sign * (1 if i % 2 == 0 else -1)
            pts += [(xa + k, y + sgn * amp), (xb - k, y - sgn * amp), (xb, y - sgn * amp)]
        return pts

    A, B = strand(1), strand(-1)
    ribw = w_rib + 2 * sw_ink

    def draw(pts):
        return (S(path_d(pts), C["ink"], ribw) + S(path_d(pts), C["ribbon"], w_rib))

    out += draw(A) + draw(B)
    # over-passes: crossings at xa + h/2 for each half period; alternate which strand is on top
    for i in range(2 * n):
        top = A if i % 2 == 0 else B
        seg = segs(top)[i]
        sub = split(seg, 0.28, 0.72)
        d = "M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (sub[0] + sub[1] + sub[2] + sub[3])
        out += S(d, C["ink"], ribw, cap="butt") + S(d, C["ribbon"], w_rib, cap="butt")
    return out


def split(s, t0, t1):
    """sub-cubic of s between t0 and t1 (de Casteljau)."""
    def cut_right(s, t):
        p0, p1, p2, p3 = s
        q0 = lerp(p0, p1, t); q1 = lerp(p1, p2, t); q2 = lerp(p2, p3, t)
        r0 = lerp(q0, q1, t); r1 = lerp(q1, q2, t)
        s0 = lerp(r0, r1, t)
        return (s0, r1, q2, p3)

    def cut_left(s, t):
        p0, p1, p2, p3 = s
        q0 = lerp(p0, p1, t); q1 = lerp(p1, p2, t); q2 = lerp(p2, p3, t)
        r0 = lerp(q0, q1, t); r1 = lerp(q1, q2, t)
        s0 = lerp(r0, r1, t)
        return (p0, q0, r0, s0)

    right = cut_right(s, t0)
    return cut_left(right, (t1 - t0) / (1 - t0))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def knot_frame(x, y, w, h, C, band=26, sw=3.0):
    """Rectangular interlace border with corner roundels."""
    out = ""
    rib = band * 0.26
    amp = band * 0.22
    period = band * 1.5
    ci = band / 2
    # outer and inner ink rules
    out += '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="%s" stroke-width="%.1f"/>\n' % (x, y, w, h, C["ink"], sw)
    out += '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="%s" stroke-width="%.1f"/>\n' % (x + band, y + band, w - 2 * band, h - 2 * band, C["ink"], sw * 0.6)
    # braids
    out += braid(x + band, x + w - band, y + ci, period, amp, C, sw, rib)
    out += braid(x + band, x + w - band, y + h - ci, period, amp, C, sw, rib)
    out += '<g transform="translate(%.1f,%.1f) rotate(90)">' % (x + ci, y + band) + braid(0, h - 2 * band, 0, period, amp, C, sw, rib) + "</g>\n"
    out += '<g transform="translate(%.1f,%.1f) rotate(90)">' % (x + w - ci, y + band) + braid(0, h - 2 * band, 0, period, amp, C, sw, rib) + "</g>\n"
    # corner roundels with a four-petal knot
    for cx, cy in [(x + ci, y + ci), (x + w - ci, y + ci), (x + ci, y + h - ci), (x + w - ci, y + h - ci)]:
        out += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (cx, cy, band * 0.62, C["red"], C["ink"], sw)
        out += quatrefoil(cx, cy, band * 0.42, C, sw * 0.8)
    return out


def quatrefoil(cx, cy, r, C, sw):
    d = ""
    for a in (0, 90, 180, 270):
        d += '<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" transform="rotate(%d %.1f %.1f)" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (
            cx, cy - r * 0.55, r * 0.3, r * 0.5, a, cx, cy, C["cream"], C["ink"], sw)
    d += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>\n' % (cx, cy, r * 0.22, C["ink"])
    return d


# ---------------------------------------------------------------- ash leaf sprig
def leaf_sprig(x, y, angle, length, C, sw=2.4, n=3, scale=1.0, flip=1):
    """Pinnate ash leaf: a stem with n pairs of lanceolate leaflets and a terminal leaflet."""
    out = '<g transform="translate(%.1f,%.1f) rotate(%.1f) scale(%.2f)">\n' % (x, y, angle, scale)
    out += S("M0,0 C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (length * 0.3, -length * 0.08 * flip, length * 0.7, -length * 0.15 * flip, length, -length * 0.2 * flip), C["ink"], sw)
    lw = length * 0.11
    ll = length * 0.34

    def leaflet(px, py, ang):
        return '<g transform="translate(%.1f,%.1f) rotate(%.1f)">' % (px, py, ang) + \
            P("M0,0 C%.1f,%.1f %.1f,%.1f %.1f,0 C%.1f,%.1f %.1f,%.1f 0,0 Z" % (ll * 0.3, -lw, ll * 0.8, -lw * 0.9, ll, ll * 0.8, lw * 0.9, ll * 0.3, lw), C["green"], C["ink"], sw) + \
            S("M%.1f,0 L%.1f,0" % (ll * 0.15, ll * 0.85), C["ink"], sw * 0.6) + "</g>\n"

    for i in range(n):
        u = (i + 0.6) / (n + 0.6)
        px = length * u
        py = -length * 0.2 * flip * (u * 0.6)
        out += leaflet(px, py, -55 * flip)
        out += leaflet(px, py, 55 * flip)
    out += leaflet(length, -length * 0.2 * flip, -10 * flip)
    out += "</g>\n"
    return out


# ---------------------------------------------------------------- TOSK, the mascot (400x400 space)
def tosk_figure(C, sw=5.0, vine=True):
    """Ratatosk leaping to the right along a vine, scroll in his paws, plume tail high."""
    ink = C["ink"]
    o = ""
    if vine:
        # the vine he runs along: an interlaced tendril with a curl, ash sprigs
        vine_pts = [(8, 352), (90, 330), (170, 352), (250, 332), (330, 312), (372, 318), (392, 292), (412, 266), (388, 248), (372, 262), (362, 278), (376, 290), (388, 284)]
        o += P(ribbon(vine_pts, 16, 6, power=0.8, cap="round"), C["golddark"], ink, sw * 0.8)
        o += leaf_sprig(60, 338, -150, 56, C, sw * 0.5, n=2, flip=-1)
        o += leaf_sprig(300, 318, 20, 60, C, sw * 0.5, n=2, flip=1)
    # --- tail: one great plume, built as a flame-like silhouette with scalloped outer edge
    tail = ("M156,268 "
            "C120,284 84,262 84,226 "
            "C82,196 100,172 112,152 "
            "C90,128 98,86 134,72 "
            "C150,52 184,46 206,62 "
            "C238,68 252,102 232,126 "
            "C222,114 206,110 196,116 "
            "C190,134 198,150 180,166 "
            "C160,182 148,206 150,232 "
            "C150,248 152,260 156,268 Z")
    o += P(tail, C["red"], ink, sw)
    # tail inner (cream) stripe following the inner curve
    tail_in = ("M162,252 C150,214 160,180 184,160 C200,146 206,128 206,118 "
               "C214,118 220,124 218,132 C214,146 204,160 192,172 C172,192 166,222 170,250 Z")
    o += P(tail_in, C["cream"], ink, sw * 0.6)
    # tail fur ticks
    for d in ["M96,250 l-12,10", "M94,190 l-14,2", "M118,100 l-14,-6", "M156,66 l-4,-14", "M208,70 l8,-12", "M240,98 l14,-2"]:
        o += S(d, ink, sw * 0.6)
    # --- hind leg (far) trailing
    o += P("M150,262 C132,286 114,306 118,330 C122,338 136,338 146,330 C144,310 152,292 164,278 Z", C["red"], ink, sw)
    # --- torso: arched back, chest forward and up
    torso = ("M236,128 "
             "C196,140 160,192 150,246 "
             "C146,276 164,300 194,296 "
             "C226,290 252,250 262,208 "
             "C268,190 260,172 250,160 Z")
    o += P(torso, C["red"], ink, sw)
    # belly (cream) patch
    o += P("M258,200 C246,236 224,272 196,286 C184,284 180,272 186,262 C208,250 232,222 246,196 Z", C["cream"], ink, sw * 0.6)
    # --- hind leg (near) planted on the vine, pushing off
    o += P("M176,286 C170,304 172,318 180,330 L214,328 C206,318 196,304 198,290 Z", C["red"], ink, sw)
    o += S("M186,329 L184,338 M196,329 L196,338 M206,329 L208,338", ink, sw * 0.7)
    # --- far fore-arm (behind the scroll)
    o += P("M242,186 C252,196 264,214 268,228 C266,236 256,236 250,230 C244,216 236,200 230,192 Z", C["red"], ink, sw)
    # --- scroll of words, held in the paws
    o += '<g transform="rotate(-28 284 224)">\n'
    o += P("M258,212 L310,212 L310,236 L258,236 Z", C["cream"], ink, sw * 0.7)
    o += runes("tosk", 263, 217, 13, ink, sw * 0.4)
    o += '<circle cx="258" cy="224" r="8" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (C["gold"], ink, sw * 0.7)
    o += '<circle cx="310" cy="224" r="8" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (C["gold"], ink, sw * 0.7)
    o += '<circle cx="258" cy="224" r="3" fill="%s"/>\n<circle cx="310" cy="224" r="3" fill="%s"/>\n' % (ink, ink)
    o += "</g>\n"
    # --- near fore-arm over the scroll
    o += P("M250,176 C266,184 286,200 296,216 C300,226 290,232 282,228 C270,216 254,202 242,194 Z", C["red"], ink, sw)
    o += S("M292,222 l6,6 M286,226 l4,8", ink, sw * 0.6)
    # --- head (profile, facing right, slightly up: alert messenger)
    head = ("M240,150 "
            "C232,116 256,96 286,98 "
            "C308,100 320,116 322,132 "
            "C332,138 338,154 330,166 "
            "C322,176 308,178 298,176 "
            "C284,190 258,190 244,176 "
            "C238,168 238,158 240,150 Z")
    o += P(head, C["red"], ink, sw)
    # cheek / muzzle cream
    o += P("M296,146 C312,146 326,154 328,164 C324,174 310,178 298,176 C286,176 278,166 282,156 C286,150 290,146 296,146 Z", C["cream"], ink, sw * 0.6)
    # ear with the red-squirrel tuft
    o += P("M252,112 C254,96 260,82 268,74 L270,58 L278,74 L290,64 L286,82 L298,82 C292,92 286,104 280,112 Z", C["red"], ink, sw)
    o += P("M262,108 C264,98 268,90 274,84 C280,92 280,100 276,108 Z", C["cream"], ink, sw * 0.5)
    # eye: large, bright, mischievous
    o += '<ellipse cx="300" cy="134" rx="11" ry="12" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (C["cream"], ink, sw * 0.7)
    o += '<circle cx="303" cy="136" r="7" fill="%s"/>\n' % ink
    o += '<circle cx="300" cy="131" r="2.6" fill="%s"/>\n' % C["cream"]
    o += S("M288,118 C296,112 308,114 314,120", ink, sw * 0.8)  # raised brow
    # nose and smirk
    o += '<circle cx="333" cy="160" r="4.5" fill="%s"/>\n' % ink
    o += S("M326,170 C320,178 310,180 304,174", ink, sw * 0.7)
    o += S("M306,176 C306,180 310,182 314,180", ink, sw * 0.5)
    # whisker ticks + fur ticks on the back
    o += S("M318,156 l12,-2 M316,162 l12,2", ink, sw * 0.4)
    for d in ["M204,146 l-10,8", "M186,170 l-10,8", "M172,200 l-10,6"]:
        o += S(d, ink, sw * 0.6)
    return o


def svg(w, h, body, C, mono, extra_defs=""):
    bg = ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n' % (w, h, w, h)
            + (mono_defs() if mono else "") + extra_defs + bg + body + "</svg>\n")


def make_tosk(C, mono):
    return svg(400, 400, tosk_figure(C), C, mono)


# ---------------------------------------------------------------- ICON (512 space)
def make_icon(C, mono):
    ink = C["ink"]
    o = ""
    # gold-leaf ground in a rounded square, with an ink ring (reads at 48 px)
    o += '<rect x="0" y="0" width="512" height="512" rx="112" fill="%s"/>\n' % (C["gold"] if not mono else "#ffffff")
    if mono:
        o += '<rect x="10" y="10" width="492" height="492" rx="104" fill="none" stroke="#000" stroke-width="16"/>\n'
    o += '<circle cx="256" cy="256" r="214" fill="%s" stroke="%s" stroke-width="14"/>\n' % (C["cream"], ink)
    if not mono:
        o += '<circle cx="256" cy="256" r="196" fill="none" stroke="%s" stroke-width="5"/>\n' % C["golddark"]
    sw = 11
    red = C["red"] if not mono else "#000000"
    # tail: big plume, sweeping from bottom-left up over the head
    tail = ("M232,392 C150,420 84,360 100,284 C84,250 104,210 128,196 "
            "C116,150 150,108 196,118 C216,80 282,84 294,130 "
            "C300,150 290,162 280,164 C258,150 234,160 224,186 "
            "C206,222 204,270 220,322 C226,350 232,372 232,392 Z")
    o += P(tail, red, ink, sw)
    if not mono:
        o += P("M236,340 C222,290 226,236 248,196 C258,180 272,172 282,172 C286,182 284,190 280,194 C264,196 252,214 246,234 C236,266 238,300 248,336 Z", C["cream"], ink, sw * 0.5)
    # body: a compact crouch under the head
    body = "M300,250 C330,250 356,290 356,336 C356,384 316,410 262,406 C222,402 206,370 220,330 C236,286 266,250 300,250 Z"
    o += P(body, red, ink, sw)
    if not mono:
        o += P("M342,336 C342,372 312,392 272,390 C252,388 244,372 254,356 C284,348 314,340 342,336 Z", C["cream"], ink, sw * 0.5)
    # head: profile facing right
    head = ("M268,252 C256,206 290,172 334,176 C364,180 380,200 384,222 "
            "C398,232 404,254 392,270 C380,284 360,286 348,282 "
            "C330,296 296,292 282,276 C272,268 268,260 268,252 Z")
    o += P(head, red if not mono else "#ffffff", ink, sw)
    # muzzle cream
    if not mono:
        o += P("M346,232 C368,232 388,244 390,262 C384,278 364,284 350,282 C334,282 322,270 326,254 C330,242 338,232 346,232 Z", C["cream"], ink, sw * 0.5)
    # ear tuft
    o += P("M286,198 C288,176 296,160 306,150 L310,126 L322,150 L344,138 L336,160 L352,162 C344,174 334,190 326,200 Z", red if not mono else "#ffffff", ink, sw)
    # eye
    o += '<ellipse cx="352" cy="222" rx="17" ry="18" fill="%s" stroke="%s" stroke-width="7"/>\n' % (C["cream"], ink)
    o += '<circle cx="356" cy="225" r="11" fill="%s"/>\n' % ink
    o += '<circle cx="351" cy="218" r="4" fill="%s"/>\n' % C["cream"]
    o += S("M334,200 C346,192 364,194 372,204", ink, 8)
    o += '<circle cx="396" cy="256" r="7" fill="%s"/>\n' % ink
    o += S("M388,270 C382,282 368,284 360,278", ink, 7)
    # paw holding a small gold scroll at the chest
    o += '<g transform="rotate(-20 318 318)">\n'
    o += P("M292,306 L344,306 L344,330 L292,330 Z", C["cream"], ink, 7)
    o += '<circle cx="292" cy="318" r="9" fill="%s" stroke="%s" stroke-width="6"/>\n<circle cx="344" cy="318" r="9" fill="%s" stroke="%s" stroke-width="6"/>\n' % (C["gold"] if not mono else "#fff", ink, C["gold"] if not mono else "#fff", ink)
    o += "</g>\n"
    o += P("M306,282 C322,286 336,298 342,308 C344,316 336,320 330,316 C318,308 306,298 298,292 Z", red if not mono else "#ffffff", ink, sw * 0.8)
    return svg(512, 512, o, C, mono)


# ---------------------------------------------------------------- LOGO (decorated initial + wordmark)
def make_logo(C):
    ink = C["ink"]
    o = ""
    # decorated initial block
    bx, by, bs = 16, 16, 208
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="4"/>\n' % (bx, by, bs, bs, C["gold"], ink)
    o += braid(bx + 18, bx + bs - 18, by + 11, 24, 3.4, C, 2.2, 4.2)
    o += braid(bx + 18, bx + bs - 18, by + bs - 11, 24, 3.4, C, 2.2, 4.2)
    o += '<g transform="translate(%d,%d) rotate(90)">' % (bx + 11, by + 18) + braid(0, bs - 36, 0, 24, 3.4, C, 2.2, 4.2) + "</g>\n"
    o += '<g transform="translate(%d,%d) rotate(90)">' % (bx + bs - 11, by + 18) + braid(0, bs - 36, 0, 24, 3.4, C, 2.2, 4.2) + "</g>\n"
    o += '<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="2.5"/>\n' % (bx + 22, by + 22, bs - 44, bs - 44, C["cream"], ink)
    # the uncial "t": a broad crossbar and a stem that curls at the foot
    t = ("M60,74 C70,66 86,64 112,66 L176,66 C186,66 188,76 180,82 L146,84 L146,150 "
         "C146,166 158,170 172,160 C180,156 184,162 178,170 C166,186 138,190 124,176 "
         "C116,168 114,158 114,146 L114,86 L72,88 C60,88 54,80 60,74 Z")
    o += P(t, C["blue"], ink, 4)
    o += S("M124,92 L124,150", C["cream"], 2.5)
    # Tosk perched on the crossbar, tail curling up the stem
    o += '<g transform="translate(118,-2) scale(0.33) translate(-200,-20)">' + tosk_figure(C, sw=7, vine=False) + "</g>\n"
    # wordmark "osk" in heavy uncial strokes
    sw = 24
    o += S("M310,166 C274,166 258,142 258,112 C258,82 278,62 310,62 C346,62 360,86 360,116 C360,146 342,166 310,166 Z", ink, sw)
    o += S("M466,82 C454,64 408,60 400,86 C394,110 440,112 462,120 C488,130 486,170 440,170 C416,170 400,160 394,150", ink, sw)
    o += S("M520,20 L520,170", ink, sw)
    o += S("M598,64 C560,96 540,108 524,122", ink, sw)
    o += S("M540,110 C566,128 588,152 604,172", ink, sw)
    return svg(640, 240, o, C, False)


# ---------------------------------------------------------------- YGGDRASIL (800 x 1100)
def node(cx, cy, r, C, sw, glyph=None, state="gold"):
    fill = C["gold"] if state == "gold" else C["cream"]
    o = '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (cx, cy, r, fill, C["ink"], sw)
    o += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (cx, cy, r * 0.76, C["cream"], C["ink"], sw * 0.5)
    if glyph:
        o += runes(glyph, cx - r * 0.3, cy - r * 0.5, r, C["ink"], sw * 0.7)
    return o


def eagle(cx, cy, C, sw):
    ink = C["ink"]
    o = '<g transform="translate(%.1f,%.1f)">\n' % (cx, cy)
    wing = ("M-6,10 C-40,-22 -92,-34 -132,-12 C-120,-8 -112,0 -108,8 C-96,2 -84,4 -74,12 "
            "C-66,6 -52,8 -44,18 C-36,12 -22,14 -16,24 Z")
    for sx in (1, -1):
        o += '<g transform="scale(%d,1)">' % sx + P(wing, C["gold"], ink, sw) + \
            S("M-20,6 C-50,-8 -80,-14 -112,-6", ink, sw * 0.5) + "</g>\n"
    o += P("M0,-14 C16,-14 24,10 18,42 C14,58 -14,58 -18,42 C-24,10 -16,-14 0,-14 Z", C["gold"], ink, sw)
    o += P("M-14,52 L-22,78 L-8,70 L0,82 L8,70 L22,78 L14,52 Z", C["gold"], ink, sw)
    o += '<circle cx="0" cy="-22" r="15" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (C["cream"], ink, sw)
    o += P("M-12,-20 L-28,-14 L-12,-10 Z", C["gold"], ink, sw * 0.8)
    o += '<circle cx="-2" cy="-25" r="3.2" fill="%s"/>\n' % ink
    o += "</g>\n"
    return o


def dragon(C, sw):
    """Nidhoggr, coiled among the roots, biting the left root."""
    ink = C["ink"]
    body = [(130, 1006), (170, 1040), (230, 1040), (270, 1010), (300, 988), (260, 960), (236, 976), (222, 988), (236, 1006), (258, 1000)]
    o = P(ribbon(body, 28, 10, power=0.9, cap="round"), C["green"], ink, sw)
    # spine ticks
    for t in (0.5, 1.2, 1.8, 2.4):
        x, y = centre(body, t)
        a = tangent(body, t)
        o += '<g transform="translate(%.1f,%.1f) rotate(%.1f)">' % (x, y, a) + P("M-6,-11 L0,-24 L6,-11 Z", C["red"], ink, sw * 0.6) + "</g>\n"
    # head: open jaw on the root
    head = "M134,1008 C110,1004 98,990 104,980 L124,986 L140,974 L146,992 C160,994 164,1010 150,1018 C142,1024 130,1020 126,1014 Z"
    o += P(head, C["green"], ink, sw)
    o += P("M106,982 L96,970 L118,980 Z", C["cream"], ink, sw * 0.5)
    o += P("M128,1016 L118,1030 L136,1022 Z", C["cream"], ink, sw * 0.5)
    o += '<circle cx="136" cy="990" r="4" fill="%s"/>\n' % ink
    o += P("M122,984 L116,968 L130,980 Z", C["red"], ink, sw * 0.5)
    return o


def well(cx, cy, C, sw):
    """Urdarbrunnr: the well at the roots."""
    ink = C["ink"]
    o = '<g transform="translate(%.1f,%.1f)">' % (cx, cy)
    o += P("M-40,-6 C-36,24 36,24 40,-6 L44,-10 C38,-18 -38,-18 -44,-10 Z", C["golddark"], ink, sw)
    o += "</g>\n"
    o += '<ellipse cx="%.1f" cy="%.1f" rx="34" ry="8" fill="%s" stroke="%s" stroke-width="%.1f"/>\n' % (cx, cy - 10, C["blue"], ink, sw * 0.7)
    o += S("M%.1f,%.1f c4,-3 8,-3 12,0 s8,3 12,0" % (cx - 14, cy - 10), C["cream"], sw * 0.5)
    o += S("M%.1f,%.1f L%.1f,%.1f M%.1f,%.1f L%.1f,%.1f" % (cx - 24, cy - 2, cx - 22, cy + 16, cx + 24, cy - 2, cx + 22, cy + 16), ink, sw * 0.5)
    return o


def make_yggdrasil(C, mono):
    ink = C["ink"]
    sw = 4.0
    o = '<rect width="800" height="1100" fill="%s"/>\n' % C["paper"]
    o += knot_frame(18, 18, 764, 1064, C, band=30, sw=3)
    # runes in the lower margin: r a t a t o s k
    o += runes("ratatosk", 302, 1058, 20, ink, 2.2)

    # ---- roots (three), drawn as tapering ribbons, interlaced by draw order
    root_l = [(372, 900), (330, 930), (250, 920), (190, 960), (150, 992), (110, 1010), (96, 982), (84, 958), (112, 950), (124, 970)]
    root_c = [(400, 905), (420, 950), (370, 970), (360, 1000), (352, 1026), (384, 1032), (400, 1012), (414, 996), (382, 990), (380, 1006)]
    root_r = [(428, 900), (470, 930), (560, 916), (620, 960), (660, 990), (700, 1000), (716, 970), (732, 940), (700, 936), (696, 958)]
    small_root_l = [(380, 918), (360, 960), (320, 980), (296, 1016)]
    small_root_r = [(420, 918), (450, 964), (500, 986), (520, 1020)]
    o += P(ribbon(small_root_l, 22, 6, power=0.8, cap="round"), C["golddark"], ink, sw)
    o += P(ribbon(small_root_r, 22, 6, power=0.8, cap="round"), C["golddark"], ink, sw)
    o += P(ribbon(root_c, 40, 10, power=0.7, cap="round"), C["golddark"], ink, sw)
    o += P(ribbon(root_r, 48, 10, power=0.7, cap="round"), C["golddark"], ink, sw)
    o += P(ribbon(root_l, 48, 10, power=0.7, cap="round"), C["golddark"], ink, sw)
    o += well(600, 1008, C, sw)
    o += dragon(C, sw)

    # ---- trunk
    trunk = ("M330,918 C350,840 352,700 360,560 C364,470 370,380 384,300 C392,260 408,260 416,300 "
             "C430,380 436,470 440,560 C448,700 450,840 470,918 Z")
    o += P(trunk, C["golddark"], ink, sw)
    # bark lines and a knot-hole roundel
    for d in ["M372,860 C380,760 378,640 384,540", "M422,860 C416,740 420,640 414,540", "M400,470 C398,420 400,360 404,320"]:
        o += S(d, ink, sw * 0.5)
    # runes down the trunk: t o s k
    for i, ch in enumerate("tosk"):
        o += runes(ch, 391, 600 + i * 44, 30, C["cream"] if not mono else "#fff", 3.2)

    # ---- branches, each a tapering ribbon that curls at the tip (Celtic spiral)
    branches = {
        "l1": [(352, 780), (300, 760), (240, 760), (196, 730), (160, 706), (164, 668), (190, 668), (206, 668), (206, 690), (190, 692)],
        "r1": [(448, 760), (500, 740), (560, 740), (604, 710), (640, 686), (636, 648), (610, 648), (594, 648), (594, 670), (610, 672)],
        "l2": [(362, 600), (320, 580), (266, 572), (226, 540), (196, 516), (200, 480), (226, 478), (242, 478), (242, 500), (226, 502)],
        "r2": [(438, 580), (480, 560), (534, 552), (574, 520), (604, 496), (600, 460), (574, 458), (558, 458), (558, 480), (574, 482)],
        "l3": [(380, 440), (350, 420), (300, 410), (268, 380), (244, 358), (246, 326), (270, 324), (286, 324), (286, 346), (270, 348)],
        "r3": [(420, 440), (450, 420), (500, 410), (532, 380), (556, 358), (554, 326), (530, 324), (514, 324), (514, 346), (530, 348)],
        "top": [(400, 300), (396, 260), (402, 230), (400, 200)],
    }
    widths = {"l1": 34, "r1": 32, "l2": 30, "r2": 28, "l3": 26, "r3": 24, "top": 30}
    # side twigs with leaves on each branch
    for key, pts in branches.items():
        o += P(ribbon(pts, widths[key], 7, power=0.6, cap="round"), C["golddark"], ink, sw)
    # leaves: sprigs along branches
    sprigs = [
        (280, 752, -150, 54, -1), (236, 746, -110, 46, 1), (160, 690, 160, 44, 1),
        (520, 736, -30, 54, 1), (574, 724, -70, 46, -1), (650, 690, 20, 44, 1),
        (300, 572, -150, 52, -1), (240, 540, -100, 44, 1), (196, 500, 170, 40, 1),
        (500, 552, -30, 52, 1), (560, 520, -80, 44, -1), (604, 480, 10, 40, 1),
        (330, 414, -150, 48, -1), (276, 380, -100, 40, 1),
        (470, 414, -30, 48, 1), (524, 380, -80, 40, -1),
        (396, 236, -120, 44, 1), (404, 236, -60, 44, -1),
    ]
    for x, y, a, L, f in sprigs:
        o += leaf_sprig(x, y, a, L, C, sw * 0.55, n=3, flip=f)

    # ---- Tosk running up the trunk
    o += '<g transform="translate(404,706) rotate(-72) scale(0.34) translate(-240,-230)">' + tosk_figure(C, sw=7, vine=False) + "</g>\n"

    # ---- eagle in the crown
    o += eagle(400, 150, C, sw)

    # ---- skill nodes (roundels) on the branches. root node = foundations.
    nodes = [
        (400, 936, "r", "gold"),
        (190, 680, "a", "gold"), (610, 660, "t", "gold"),
        (226, 490, "a", "gold"), (574, 470, "t", "cream"),
        (270, 336, "o", "cream"), (530, 336, "s", "cream"),
        (400, 250, "k", "cream"),
    ]
    for x, y, g, st in nodes:
        o += node(x, y, 30, C, sw, g, st)
    return svg(800, 1100, o, C, mono)


# ---------------------------------------------------------------- BRANCH TILE (400 x 400)
def make_tile(C, mono):
    ink = C["ink"]
    sw = 4.0
    o = ""
    stem = [(200, 340), (200, 300), (196, 270), (200, 236)]
    left = [(200, 236), (196, 200), (150, 190), (130, 150), (114, 118), (90, 100), (84, 84)]
    right = [(200, 236), (204, 200), (250, 190), (270, 150), (286, 118), (310, 100), (316, 84)]
    # interlace: the two arms cross once above the fork (left goes under right)
    cross_l = [(200, 236), (230, 206), (190, 170), (150, 150), (120, 136), (96, 112), (84, 84)]
    cross_r = [(200, 236), (170, 206), (210, 170), (250, 150), (280, 136), (304, 112), (316, 84)]
    o += P(ribbon(stem, 36, 28, cap="flat"), C["golddark"], ink, sw)
    o += P(ribbon(cross_l, 28, 10, power=0.8, cap="round"), C["golddark"], ink, sw)
    o += P(ribbon(cross_r, 28, 10, power=0.8, cap="round"), C["golddark"], ink, sw)
    # re-draw the fork knot so the join is clean
    o += S("M200,236 C200,246 204,256 210,264", ink, sw * 0.5)
    o += leaf_sprig(154, 158, -140, 48, C, sw * 0.55, n=2, flip=-1)
    o += leaf_sprig(246, 158, -40, 48, C, sw * 0.55, n=2, flip=1)
    o += leaf_sprig(118, 118, -200, 40, C, sw * 0.55, n=2, flip=1)
    o += leaf_sprig(282, 118, 20, 40, C, sw * 0.55, n=2, flip=1)
    o += node(200, 340, 30, C, sw, "t", "gold")
    o += node(84, 70, 30, C, sw, "o", "cream")
    o += node(316, 70, 30, C, sw, "s", "cream")
    return svg(400, 400, o, C, mono)


# ---------------------------------------------------------------- sheet
SHEET = """<!doctype html>
<html><head><meta charset="utf-8"><title>tosk - illuminated</title>
<style>
body{margin:0;padding:28px 36px;background:%(paper)s;color:%(ink)s;font-family:Georgia,'Times New Roman',serif}
h1{margin:0 0 4px;font-size:38px;letter-spacing:.5px} .sub{margin:0 0 18px;font-size:15px;color:#5a4a3a}
.row{display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;margin-bottom:18px}
.card{border:2px solid %(ink)s;border-radius:6px;padding:10px 12px 8px;background:%(paper)s;text-align:center}
.card.white{background:#fff}
.card img{display:block;margin:0 auto}
.cap{font-size:13px;margin-top:6px;letter-spacing:.3px}
.sw{display:inline-block;width:76px;margin:0 4px 6px 0;text-align:center;font-size:11px}
.sw i{display:block;height:44px;border:1.5px solid %(ink)s;border-radius:4px;margin-bottom:3px}
.icons img{vertical-align:bottom;margin:0 8px}
</style></head><body>
<h1><img src="logo.svg" height="92" alt="tosk"></h1>
<p class="sub">Ratatosk, the messenger squirrel of Yggdrasil, drawn as a beast from the margin of an illuminated manuscript. Colour and e-ink (pure black and white) side by side.</p>
<div class="row">
  <div class="card"><img src="tosk.svg" width="330"><div class="cap">Tosk</div></div>
  <div class="card white"><img src="tosk-mono.svg" width="330"><div class="cap">Tosk, e-ink</div></div>
  <div class="card"><img src="icon.svg" width="200"><div class="cap">App icon</div>
    <div class="icons"><img src="icon.svg" width="96"><img src="icon.svg" width="48"></div></div>
  <div class="card white"><img src="icon-mono.svg" width="200"><div class="cap">Icon, e-ink</div>
    <div class="icons"><img src="icon-mono.svg" width="96"><img src="icon-mono.svg" width="48"></div></div>
  <div class="card"><div style="margin:6px 0 4px">%(swatches)s</div><div class="cap">Palette</div>
    <div style="margin-top:12px"><img src="logo.svg" width="340"></div><div class="cap">Logo: decorated initial + wordmark</div></div>
</div>
<div class="row">
  <div class="card"><img src="yggdrasil.svg" width="400"><div class="cap">Yggdrasil, the course tree</div></div>
  <div class="card white"><img src="yggdrasil-mono.svg" width="400"><div class="cap">Yggdrasil, e-ink</div></div>
  <div>
    <div class="card" style="margin-bottom:18px"><img src="branch-tile.svg" width="240"><div class="cap">Map tile: skill fork</div></div>
    <div class="card white"><img src="branch-tile-mono.svg" width="240"><div class="cap">Skill fork, e-ink</div></div>
  </div>
</div>
</body></html>
"""


def make_sheet():
    names = [("ink", "ink"), ("red", "vermilion"), ("blue", "ultramarine"), ("green", "verdigris"), ("gold", "gold ochre"), ("golddark", "shaded gold"), ("cream", "lead white"), ("paper", "vellum")]
    sws = "".join('<span class="sw"><i style="background:%s"></i>%s<br>%s</span>' % (COLOUR[k], n, COLOUR[k]) for k, n in names)
    return SHEET % dict(paper=COLOUR["paper"], ink=COLOUR["ink"], swatches=sws)


def write(name, text):
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        f.write(text)
    print("%-22s %6.1f KB" % (name, len(text.encode("utf-8")) / 1024))


if __name__ == "__main__":
    write("tosk.svg", make_tosk(COLOUR, False))
    write("tosk-mono.svg", make_tosk(MONO, True))
    write("icon.svg", make_icon(COLOUR, False))
    write("icon-mono.svg", make_icon(MONO, True))
    write("logo.svg", make_logo(COLOUR))
    write("yggdrasil.svg", make_yggdrasil(COLOUR, False))
    write("yggdrasil-mono.svg", make_yggdrasil(MONO, True))
    write("branch-tile.svg", make_tile(COLOUR, False))
    write("branch-tile-mono.svg", make_tile(MONO, True))
    write("sheet.html", make_sheet())
