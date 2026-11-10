"""Story-mode character portraits: 48x48 RGBA busts built from a small parametric composer.

Every shape is a "blob": a polygon/superellipse mask filled with three tones and lit from the upper left
(top/left edge pixels light, right/bottom edge pixels dark). A final pass wraps the whole figure in a
1px dark outline and composites it over an opaque per-character backdrop. No randomness anywhere.
"""
import math
import os

import png

SIZE = 48
OUTLINE = (22, 14, 18)
WHITE = (250, 250, 244)


def H(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def tone(base):
    """(hi, base, sh) from one base colour."""
    base = H(base) if isinstance(base, str) else base
    hi = mix(base, (255, 246, 226), 0.30)
    sh = (int(base[0] * 0.64), int(base[1] * 0.60), int(base[2] * 0.70))
    return (hi, base, sh)


def poly_mask(pts):
    out = set()
    for y in range(SIZE):
        for x in range(SIZE):
            X, Y = x + 0.5, y + 0.5
            ins = False
            j = len(pts) - 1
            for i in range(len(pts)):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > Y) != (yj > Y) and X < (xj - xi) * (Y - yi) / (yj - yi) + xi:
                    ins = not ins
                j = i
            if ins:
                out.add((x, y))
    return out


def ell_mask(cx, cy, rx, ry, p=2.0):
    out = set()
    for y in range(SIZE):
        for x in range(SIZE):
            if abs((x + 0.5 - cx) / rx) ** p + abs((y + 0.5 - cy) / ry) ** p <= 1.0:
                out.add((x, y))
    return out


def rect_mask(x, y, w, h):
    return {(i, j) for i in range(x, x + w) for j in range(y, y + h)}


class Canvas:
    def __init__(self):
        self.fig = {}

    def put(self, x, y, col):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.fig[(x, y)] = col

    def blob(self, mask, cols, edge=True, side=0, cx=None):
        """Fill mask with (hi, base, sh). side>0: columns within `side` px of the right edge
        of the mask also take the shadow tone (cheek/arm turn)."""
        if isinstance(cols[0], int):
            cols = (cols, cols, cols)
        hi, base, sh = cols
        xmax = max(p[0] for p in mask) if mask else 0
        for (x, y) in mask:
            c = base
            if edge:
                if (x, y - 1) not in mask or (x - 1, y) not in mask:
                    c = hi
                if (x + 1, y) not in mask or (x, y + 1) not in mask:
                    c = sh
            if side and c == base and x > xmax - side:
                c = sh
            self.fig[(x, y)] = c

    def pts(self, pts, col):
        for x, y in pts:
            self.put(x, y, col)

    def hline(self, x, y, w, col):
        for i in range(w):
            self.put(x + i, y, col)

    def vline(self, x, y, h, col):
        for j in range(h):
            self.put(x, y + j, col)

    def line(self, x0, y0, x1, y1, col):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            self.put(int(round(x0 + (x1 - x0) * i / n)), int(round(y0 + (y1 - y0) * i / n)), col)

    def disc(self, cx, cy, r, col):
        for (x, y) in ell_mask(cx, cy, r, r):
            self.put(x, y, col)

    def render(self, backdrop):
        rows = []
        for y in range(SIZE):
            row = []
            for x in range(SIZE):
                if (x, y) in self.fig:
                    c = self.fig[(x, y)]
                elif any((x + dx, y + dy) in self.fig for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    c = OUTLINE
                else:
                    c = backdrop[y][x]
                row.append(c + (255,))
            rows.append(row)
        return rows


# ---------------------------------------------------------------- backdrops

def backdrop(top, bottom, glow=None, scan=False):
    """Vertical banded gradient with 2x2 ordered dither between bands (+ optional radial glow)."""
    top, bottom = H(top), H(bottom)
    bayer = ((0, 2), (3, 1))
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            t = y / (SIZE - 1)
            if glow:
                gx, gy, gr, gc = glow
                d = math.hypot(x - gx, (y - gy) * 1.1) / gr
                if d < 1.0:
                    t2 = (1.0 - d) ** 1.4
                    base = mix(mix(top, bottom, t), H(gc), t2)
                else:
                    base = mix(top, bottom, t)
                    t = 0
            else:
                base = mix(top, bottom, t)
            # dither: quantise to 6 steps with a bayer threshold
            q = []
            for k in range(3):
                step = 16.0
                v = base[k] / 255.0 * step
                lo = int(v)
                frac = v - lo
                if frac > (bayer[y & 1][x & 1] + 0.5) / 4.0:
                    lo += 1
                q.append(min(255, int(lo / step * 255)))
            c = tuple(q)
            if scan and y % 3 == 0:
                c = (int(c[0] * 0.9), int(c[1] * 0.9), int(c[2] * 0.9))
            row.append(c)
        rows.append(row)
    return rows


BG_COAL = ("#0e2a1d", "#1d4a32")
BG_SYN = ("#220e14", "#4a1a22")

# ---------------------------------------------------------------- composer pieces

SKINS = {
    "fair": "#ecc7a2", "tan": "#e0ab80", "ruddy": "#d29a74", "grey": "#a9acb4", "child": "#f0cfae", "pale": "#f2dcc4",
}

HX, HY = 24, 21  # head centre


def skin_cols(name):
    return tone(SKINS[name])


def head(c, sk, rx=10, ry=12, p=2.3, cy=HY, side=3):
    c.blob(ell_mask(HX, cy, rx, ry, p), sk, side=side)


def neck(c, sk, w=8, y0=31, y1=40):
    x0 = HX - w // 2
    c.blob(rect_mask(x0, y0, w, y1 - y0), sk, edge=False, side=2)
    c.hline(x0, y0 + 3, w, sk[2])  # chin shadow on the neck
    c.hline(x0, y0 + 4, w, sk[2])


def ears(c, sk, y=20, h=5, dx=10.5):
    for sx in (-1, 1):
        x = int(round(HX + sx * dx))
        x = x if sx > 0 else x - 1
        c.blob(rect_mask(x, y, 2, h), sk, edge=False)
        c.put(x + (0 if sx > 0 else 1), y + 2, sk[2])


def torso(c, cols, pts):
    c.blob(poly_mask(pts), cols, side=3)


def eye(c, x, y, kind, iris, left=True, sk=None):
    """4px-wide eye whose top-left is (x, y). kinds: wide, tired, steady, slit, sweet."""
    dk = H("#201418")
    if kind == "wide":
        c.hline(x, y, 4, dk)
        c.pts([(x, y + 1), (x + 3, y + 1), (x, y + 2), (x + 3, y + 2)], WHITE)
        c.pts([(x + 1, y + 1), (x + 2, y + 1), (x + 1, y + 2), (x + 2, y + 2)], iris)
        c.put(x + 1, y + 1, WHITE)
        c.put(x + 2, y + 2, dk)
    elif kind == "tired":
        c.hline(x, y, 4, dk)
        c.put(x if left else x + 3, y + 1, dk)  # drooping outer lid
        c.put(x + 3 if left else x, y + 1, WHITE)
        c.pts([(x + 1, y + 1), (x + 2, y + 1)], iris)
        c.put(x + (1 if left else 2), y + 1, dk)
        c.hline(x, y + 2, 4, sk[2])  # eye bag
    elif kind == "steady":
        c.hline(x, y, 4, dk)
        c.pts([(x, y + 1), (x + 3, y + 1)], WHITE)
        c.pts([(x + 1, y + 1), (x + 2, y + 1)], iris)
        c.put(x + 1, y + 1, dk)
    elif kind == "slit":
        c.hline(x, y, 4, dk)
        c.pts([(x, y + 1), (x + 3, y + 1)], WHITE)
        c.pts([(x + 1, y + 1), (x + 2, y + 1)], iris)
    elif kind == "sweet":  # unsettling: huge iris, tiny pupil, lash flick
        c.hline(x, y, 4, dk)
        c.put(x if left else x + 3, y - 1, dk)
        c.hline(x, y + 1, 4, iris)
        c.hline(x, y + 2, 4, iris)
        c.put(x + 1, y + 1, WHITE)
        c.put(x + 2, y + 2, dk)
        c.put(x + 1, y + 2, mix(iris, dk, 0.5))
        c.hline(x, y + 3, 4, mix(iris, dk, 0.35))


def brow(c, x, y, w, tilt, col, left=True, thick=1):
    """tilt>0: inner end lower (angry), tilt<0: inner end higher (sad). x = left px of the brow."""
    for i in range(w):
        inner = (w - 1 - i) if left else i  # 0 = outer, w-1 = inner
        yy = y + int(round(tilt * inner / max(1, w - 1)))
        for t in range(thick):
            c.put(x + i, yy + t, col)


def nose(c, sk, y=25):
    c.put(HX - 1, y + 1, sk[2])
    c.put(HX, y + 1, sk[2])
    c.put(HX, y, sk[2])
    c.put(HX - 1, y - 1, sk[0])


def mouth(c, kind, sk, y=29, lip=None):
    dk = H("#4a1e22")
    lip = lip or mix(H("#c46a62"), sk[1], 0.3)
    if kind == "flat":
        c.hline(HX - 2, y, 4, dk)
    elif kind == "frown":
        c.hline(HX - 2, y, 4, dk)
        c.pts([(HX - 3, y + 1), (HX + 2, y + 1)], dk)
    elif kind == "smirk":
        c.hline(HX - 2, y, 4, dk)
        c.pts([(HX + 2, y - 1), (HX + 3, y - 1)], dk)
    elif kind == "grin":
        c.hline(HX - 4, y - 1, 8, dk)
        c.hline(HX - 4, y, 8, WHITE)
        c.hline(HX - 3, y + 1, 6, WHITE)
        c.hline(HX - 3, y + 2, 6, dk)
        c.pts([(HX - 5, y - 2), (HX + 4, y - 2)], sk[2])
        c.vline(HX, y, 2, mix(WHITE, dk, 0.4))
    elif kind == "smile":
        c.hline(HX - 2, y + 1, 5, dk)
        c.pts([(HX - 3, y), (HX + 3, y)], dk)
    elif kind == "sweet":
        c.hline(HX - 2, y + 1, 5, lip)
        c.pts([(HX - 3, y), (HX + 3, y)], lip)
        c.hline(HX - 1, y + 2, 3, mix(lip, sk[2], 0.4))
        c.pts([(HX - 4, y - 1), (HX + 4, y - 1)], dk)
    elif kind == "snarl":
        c.hline(HX - 3, y, 6, dk)
        c.hline(HX - 2, y + 1, 4, WHITE)
        c.pts([(HX - 3, y + 1), (HX + 2, y + 1)], dk)


def blush(c, col, y=26):
    for x in (HX - 8, HX - 7, HX + 6, HX + 7):
        c.put(x, y, col)
        c.put(x, y + 1, col)


# ---------------------------------------------------------------- characters

OLIVE = tone("#667338")
KHAKI = tone("#a79c62")
AMBER = tone("#e8a830")
CHAR = tone("#34363e")
CRIM = tone("#b01e30")
GOLD = tone("#e8c050")
STEEL = tone("#8a929c")
BLACK = tone("#1e1f26")
LEON_HAIR = tone("#2c2536")
LEON_EYE = H("#5a6c92")


def standard_shoulders(c, cols, y=38, wide=0):
    torso(c, cols, [(3 - wide, 48), (5 - wide, 42), (14, y), (34, y), (43 + wide, 42), (45 + wide, 48)])


def leon_hair(c, hair, over_eye=True):
    c.blob(poly_mask([(12, 22), (11, 13), (15, 7), (22, 5), (30, 6), (36, 10), (37, 18), (36, 24), (34, 17), (28, 12), (22, 12), (17, 14), (14, 24)]), hair)
    for tri in ([(17, 9), (19, 2), (23, 8)], [(25, 7), (30, 2), (31, 9)], [(12, 14), (7, 10), (14, 18)], [(33, 12), (40, 10), (36, 18)]):
        c.blob(poly_mask(tri), hair)
    if over_eye:
        c.blob(poly_mask([(14, 12), (28, 11), (26, 17), (23, 23), (20, 28), (17, 23), (14, 19)]), hair)
        c.blob(poly_mask([(26, 11), (33, 13), (30, 17)]), hair)
    else:  # swept back, forehead clear
        c.blob(poly_mask([(14, 12), (33, 10), (30, 14), (22, 13), (16, 16)]), hair)


def leon(c):
    sk = skin_cols("pale")
    standard_shoulders(c, OLIVE)
    neck(c, mix_cols(sk, 0))
    # open collar, undershirt and amber epaulettes
    c.blob(poly_mask([(18, 38), (30, 38), (27, 42), (21, 42)]), tone("#8d8a7c"), edge=False)
    c.blob(poly_mask([(14, 36), (20, 36), (23, 44), (15, 41)]), tone("#7f8c46"))
    c.blob(poly_mask([(34, 36), (28, 36), (25, 44), (33, 41)]), tone("#58642e"))
    c.blob(rect_mask(5, 41, 8, 3), AMBER)
    c.blob(rect_mask(35, 41, 8, 3), AMBER)
    c.vline(24, 43, 5, OLIVE[2])
    ears(c, sk)
    head(c, sk)
    nose(c, sk)
    eye(c, 27, 21, "tired", LEON_EYE, left=False, sk=sk)
    brow(c, 27, 19, 4, -1, LEON_HAIR[2], left=False)
    mouth(c, "frown", sk, y=30)
    c.pts([(HX + 2, 24), (HX + 3, 24)], sk[2])
    leon_hair(c, LEON_HAIR)
    c.hline(18, 25, 3, sk[2])  # shadow cast by the fringe
    c.pts([(20, 21), (21, 22)], LEON_HAIR[2])  # hidden eye: a dark glint through the hair


def mix_cols(cols, t):
    return cols


def leon_child(c):
    sk = skin_cols("child")
    torso(c, tone("#8a7a62"), [(5, 48), (7, 42), (15, 39), (33, 39), (41, 42), (43, 48)])
    c.hline(10, 44, 3, tone("#8a7a62")[2])
    c.blob(poly_mask([(17, 39), (31, 39), (24, 44)]), tone("#5a4c3e"), edge=False)
    neck(c, sk, w=7, y0=33, y1=41)
    ears(c, sk, y=24, dx=10.0)
    head(c, sk, rx=10, ry=11, p=2.1, cy=24, side=3)
    hair = LEON_HAIR
    c.blob(poly_mask([(13, 24), (12, 17), (15, 11), (22, 8), (30, 9), (35, 13), (36, 20), (35, 25), (33, 18), (27, 15), (21, 15), (16, 18), (14, 26)]), hair)
    for tri in ([(17, 12), (19, 6), (23, 12)], [(26, 11), (30, 6), (31, 13)], [(13, 17), (9, 13), (15, 21)]):
        c.blob(poly_mask(tri), hair)
    c.blob(poly_mask([(15, 15), (28, 14), (26, 19), (22, 24), (18, 21), (15, 22)]), hair)
    # wide frightened eyes
    for ex in (16, 27):
        c.blob(rect_mask(ex, 22, 5, 5), WHITE, edge=False)
        c.hline(ex, 22, 5, H("#201418"))
        c.blob(rect_mask(ex + 1, 23, 3, 3), LEON_EYE, edge=False)
        c.put(ex + 2, 24, H("#101018"))
        c.pts([(ex + 1, 23), (ex + 2, 23)], WHITE)
        c.hline(ex + 1, 26, 3, sk[2])
    brow(c, 16, 20, 5, -2, hair[2], left=True)
    brow(c, 27, 20, 5, -2, hair[2], left=False)
    c.pts([(HX - 1, 28), (HX, 28)], sk[2])
    c.hline(HX - 2, 31, 4, H("#5a2428"))
    c.hline(HX - 1, 32, 2, H("#3a1418"))
    # soot smudges
    soot = H("#3c3430")
    sooty = H("#6a5a4c")
    c.pts([(15, 27), (16, 27), (16, 28), (15, 29), (28, 17), (29, 17), (31, 29), (32, 29), (31, 30), (23, 18), (24, 18)], soot)
    c.pts([(14, 28), (17, 29), (30, 28), (33, 28), (27, 31), (20, 18)], sooty)
    c.pts([(HX - 1, 27), (HX + 1, 26)], soot)
    # fire glow: warm rim light on every edge facing the flames (left) and a flicker on the cheek
    for (x, y), col in list(c.fig.items()):
        if (x - 1, y) not in c.fig:
            c.fig[(x, y)] = mix(col, H("#ff9a3a"), 0.55)
        elif (x - 2, y) not in c.fig:
            c.fig[(x, y)] = mix(col, H("#ff9a3a"), 0.22)


def mira(c):
    sk = skin_cols("fair")
    hair = tone("#a8431f")
    # ponytail behind the head (viewer right)
    c.blob(poly_mask([(33, 12), (42, 10), (46, 18), (44, 29), (40, 33), (39, 24), (35, 21)]), hair)
    c.blob(rect_mask(33, 14, 3, 3), tone("#e8a830"))
    standard_shoulders(c, OLIVE)
    neck(c, sk)
    c.blob(poly_mask([(15, 37), (33, 37), (28, 44), (20, 44)]), tone("#e8a830"), edge=True)  # amber scarf
    c.line(20, 41, 27, 41, AMBER[2])
    c.blob(rect_mask(5, 41, 8, 3), AMBER)
    c.blob(rect_mask(35, 41, 8, 3), AMBER)
    ears(c, sk)
    head(c, sk, rx=10, ry=11.5, p=2.3)
    # hair: cap, side locks, sharp fringe
    c.blob(poly_mask([(12, 24), (11, 14), (15, 7), (23, 5), (31, 6), (36, 11), (37, 20), (36, 27), (34, 18), (30, 14), (18, 14), (14, 18), (14, 27)]), hair)
    c.blob(poly_mask([(14, 13), (25, 12), (20, 18), (17, 17)]), hair)
    c.blob(poly_mask([(24, 12), (34, 12), (31, 17), (27, 15)]), hair)
    c.blob(poly_mask([(12, 17), (15, 17), (15, 30), (12, 29)]), hair)
    # goggles pushed up on the forehead
    c.blob(rect_mask(11, 12, 26, 2), tone("#34322e"), edge=False)
    for gx in (19, 29):
        c.disc(gx, 11, 4, tone("#c8963c")[1])
        c.disc(gx, 11, 3, H("#7ed0e8"))
        c.pts([(gx - 1, 10), (gx - 1, 9)], WHITE)
        c.put(gx + 1, 12, H("#3a86a4"))
    c.hline(23, 11, 2, tone("#34322e")[1])
    # angry, sharp eyes
    eye(c, 17, 21, "slit", H("#3c8a58"), left=True, sk=sk)
    eye(c, 27, 21, "slit", H("#3c8a58"), left=False, sk=sk)
    brow(c, 16, 18, 5, 3, hair[2], left=True)
    brow(c, 27, 18, 5, 3, hair[2], left=False)
    nose(c, sk)
    mouth(c, "snarl", sk, y=29)
    blush(c, H("#e69a88"), y=25)
    c.pts([(HX + 5, 28), (HX + 5, 29)], WHITE)  # tiny fang
    c.pts([(15, 30)], sk[2])


def chad(c):
    sk = skin_cols("tan")
    hair = tone("#efd25c")
    standard_shoulders(c, OLIVE, y=37, wide=2)
    # white tee under an open jacket
    c.blob(poly_mask([(16, 37), (32, 37), (29, 46), (19, 46)]), tone("#e8e8dc"))
    c.blob(poly_mask([(11, 37), (17, 37), (19, 46), (10, 46)]), tone("#7f8c46"))
    c.blob(poly_mask([(37, 37), (31, 37), (29, 46), (38, 46)]), tone("#58642e"))
    neck(c, sk, w=10, y0=31, y1=39)
    ears(c, sk, dx=11.5)
    head(c, sk, rx=11, ry=12, p=3.0, side=3)
    # flat-top
    c.blob(poly_mask([(12, 16), (12, 6), (14, 4), (34, 4), (36, 6), (36, 16), (34, 12), (30, 11), (18, 11), (14, 12)]), hair)
    c.hline(13, 8, 22, hair[0])
    for x in range(14, 34, 3):
        c.pts([(x, 5), (x + 1, 5)], hair[0])
    # aviators
    gold = tone("#d8b040")
    glass = [H("#7a8aa6"), H("#2a2e3c"), H("#14161e")]
    for x0 in (14, 25):
        c.blob(poly_mask([(x0, 19), (x0 + 9, 19), (x0 + 9, 23), (x0 + 6, 26), (x0 + 2, 26), (x0, 23)]), (glass[0], glass[1], glass[2]), edge=False)
        c.hline(x0, 19, 9, gold[1])
        c.pts([(x0 + 1, 20), (x0 + 2, 20), (x0 + 1, 21)], glass[0])
        c.pts([(x0 + 3, 20)], mix(glass[0], glass[1], 0.5))
    c.hline(23, 19, 2, gold[1])
    c.hline(10, 19, 4, gold[2])
    c.hline(34, 19, 4, gold[2])
    brow(c, 14, 17, 9, 0, hair[2])
    brow(c, 25, 17, 9, 0, hair[2])
    nose(c, sk, y=26)
    mouth(c, "grin", sk, y=30)
    # toothpick
    c.hline(HX + 4, 30, 6, H("#d8c07a"))
    c.put(HX + 10, 30, H("#8a6a3a"))
    c.pts([(HX - 6, 33), (HX - 5, 34), (HX + 5, 34), (HX + 6, 33)], sk[2])  # jaw shading
    c.pts([(15, 29), (33, 29)], sk[2])


def brann(c):
    sk = skin_cols("ruddy")
    white = tone("#f0eee4")
    # massive bare shoulders and neck
    torso(c, sk, [(0, 48), (0, 41), (8, 36), (17, 33), (31, 33), (40, 36), (48, 41), (48, 48)])
    c.blob(poly_mask([(17, 33), (31, 33), (35, 40), (13, 40)]), tone("#c88c68"), side=4)
    # pecs and collarbone
    c.hline(11, 41, 11, sk[2])
    c.hline(26, 41, 11, sk[2])
    c.pts([(23, 41), (24, 42), (24, 43), (24, 44), (24, 45), (24, 46), (24, 47)], sk[2])
    c.hline(12, 42, 10, sk[0])
    c.hline(27, 42, 10, sk[0])
    c.line(8, 37, 14, 40, sk[0])
    c.line(40, 37, 34, 40, sk[2])
    c.line(4, 44, 6, 47, sk[2])
    c.line(44, 44, 42, 47, sk[2])
    # suspenders and dog tags
    c.blob(rect_mask(8, 38, 4, 10), OLIVE, edge=False)
    c.blob(rect_mask(36, 38, 4, 10), OLIVE, edge=False)
    c.vline(8, 38, 10, OLIVE[0])
    c.line(19, 36, 24, 44, GOLD[1])
    c.line(29, 36, 24, 44, GOLD[1])
    c.blob(rect_mask(23, 44, 3, 3), GOLD)
    ears(c, sk, dx=11.5)
    head(c, sk, rx=11.5, ry=12, p=2.5, side=4)
    # white crew cut fringe
    c.blob(poly_mask([(13, 18), (12, 11), (16, 7), (24, 5), (32, 7), (36, 11), (35, 18), (34, 13), (30, 10), (18, 10), (14, 14)]), white)
    c.pts([(12, 19), (12, 20), (12, 21), (36, 19), (36, 20), (36, 21)], white[1])
    # scar over the viewer-right eye
    scar = H("#c06a60")
    c.line(30, 12, 28, 21, scar)
    c.line(28, 21, 30, 25, scar)
    c.pts([(29, 15), (28, 18), (29, 23)], H("#e8b0a0"))
    # eyes: narrow and stern
    eye(c, 16, 20, "slit", H("#4f6f94"), left=True, sk=sk)
    eye(c, 28, 20, "slit", H("#4f6f94"), left=False, sk=sk)
    c.blob(rect_mask(15, 17, 6, 2), white, edge=False)
    c.blob(rect_mask(27, 17, 6, 2), white, edge=False)
    c.pts([(20, 18), (21, 19), (27, 19), (28, 18)], white[2])
    nose(c, sk, y=24)
    c.blob(rect_mask(22, 23, 5, 3), tone("#c88c68"), edge=False)
    # monumental moustache and chin beard
    c.blob(poly_mask([(23, 25), (12, 25), (8, 28), (9, 33), (13, 31), (19, 31), (24, 29), (29, 31), (35, 31), (39, 33), (40, 28), (36, 25)]), white)
    c.blob(poly_mask([(13, 31), (35, 31), (33, 36), (28, 42), (24, 44), (20, 42), (15, 36)]), white)
    c.line(24, 30, 24, 40, white[2])
    c.line(19, 33, 20, 38, white[2])
    c.line(29, 33, 28, 38, white[2])
    c.pts([(16, 28), (32, 28), (14, 27), (34, 27)], white[0])


def wolfram(c):
    steel = tone("#6a727c")
    black = BLACK
    # shoulders with raised black collar
    torso(c, black, [(2, 48), (4, 42), (13, 38), (35, 38), (44, 42), (46, 48)])
    c.blob(rect_mask(4, 42, 9, 3), steel, edge=True)
    c.blob(rect_mask(35, 42, 9, 3), steel, edge=True)
    c.hline(5, 43, 7, CRIM[1])
    c.hline(36, 43, 7, CRIM[1])
    c.vline(24, 40, 8, CRIM[2])
    c.pts([(20, 44), (28, 44)], steel[0])
    c.blob(rect_mask(18, 32, 12, 8), tone("#14141a"), edge=False)
    # high collar flaring up around the jaw
    c.blob(poly_mask([(10, 38), (12, 26), (17, 24), (18, 36)]), black)
    c.blob(poly_mask([(38, 38), (36, 26), (31, 24), (30, 36)]), black)
    c.hline(11, 30, 5, CRIM[2])
    c.hline(32, 30, 5, CRIM[2])
    # mask: full-face steel with a single glowing lens
    c.blob(ell_mask(HX, 22, 9.5, 11.5, 2.6), steel, side=3)
    c.blob(poly_mask([(16, 22), (32, 22), (31, 31), (27, 34), (21, 34), (17, 31)]), tone("#4a5058"), side=2)
    c.vline(24, 12, 8, steel[2])
    c.pts([(17, 16), (31, 16), (17, 29), (31, 29)], steel[0])
    # eye slit + red lens
    c.blob(rect_mask(15, 19, 18, 4), H("#14080c"), edge=False)
    c.blob(rect_mask(27, 18, 6, 6), H("#7a0c18"), edge=False)
    c.blob(rect_mask(28, 19, 4, 4), H("#ff2a3a"), edge=False)
    c.pts([(29, 20), (30, 20)], H("#ffd0c8"))
    for p in ((26, 17), (33, 17), (26, 24), (33, 24), (27, 16), (32, 25)):
        c.put(p[0], p[1], H("#ff4a50") if p[1] in (17, 24) else H("#a01824"))
    c.pts([(14, 20), (14, 21)], H("#7a0c18"))
    # breathing grille
    for i, y in enumerate(range(27, 33, 2)):
        c.hline(20, y, 8, H("#14141a"))
    c.pts([(19, 28), (29, 28)], steel[0])
    # peaked cap
    c.blob(poly_mask([(12, 14), (13, 7), (18, 3), (30, 3), (35, 7), (36, 14)]), black)
    c.blob(rect_mask(11, 12, 26, 2), CRIM, edge=False)
    c.blob(poly_mask([(10, 14), (38, 14), (39, 17), (34, 18), (14, 18), (9, 17)]), tone("#101014"))
    c.hline(10, 14, 28, tone("#3a3c46")[1])
    c.blob(rect_mask(22, 7, 4, 4), steel)
    c.pts([(23, 8), (24, 9)], CRIM[1])
    c.hline(14, 5, 6, black[0])


def konrad(c):
    sk = skin_cols("pale")
    hair = LEON_HAIR
    grey = tone("#a29cae")
    # black greatcoat, crimson lapels, stand collar
    torso(c, BLACK, [(2, 48), (4, 42), (13, 38), (35, 38), (44, 42), (46, 48)])
    c.blob(rect_mask(4, 42, 9, 3), STEEL)
    c.blob(rect_mask(35, 42, 9, 3), STEEL)
    c.hline(5, 43, 7, CRIM[1])
    c.hline(36, 43, 7, CRIM[1])
    neck(c, sk)
    c.blob(poly_mask([(16, 37), (22, 37), (26, 47), (18, 47)]), CRIM, side=2)
    c.blob(poly_mask([(32, 37), (26, 37), (22, 47), (30, 47)]), tone("#8c1828"), side=2)
    c.blob(poly_mask([(14, 35), (19, 33), (22, 40), (16, 40)]), BLACK)
    c.blob(poly_mask([(34, 35), (29, 33), (26, 40), (32, 40)]), BLACK)
    c.pts([(21, 44), (22, 44)], GOLD[0])
    c.blob(rect_mask(33, 43, 3, 3), GOLD)
    ears(c, sk)
    head(c, sk, rx=10, ry=12, p=2.4)
    leon_hair(c, hair, over_eye=False)
    # greying temples
    for p in ((12, 19), (12, 20), (12, 21), (13, 17), (13, 18), (13, 22), (35, 17), (35, 18), (36, 19), (36, 20), (36, 21), (35, 22), (15, 14), (16, 14), (33, 12), (32, 12)):
        c.put(p[0], p[1], grey[1])
    c.pts([(14, 18), (14, 19), (34, 18), (34, 19), (17, 13), (31, 12)], grey[0])
    # same eyes as Leon, but steady and sure
    eye(c, 17, 21, "steady", LEON_EYE, left=True, sk=sk)
    eye(c, 27, 21, "steady", LEON_EYE, left=False, sk=sk)
    brow(c, 16, 19, 5, 1, hair[2], left=True, thick=2)
    brow(c, 27, 19, 5, 1, hair[2], left=False, thick=2)
    nose(c, sk)
    c.pts([(HX - 3, 33), (HX + 2, 33), (HX - 4, 32), (HX + 3, 32)], sk[2])  # firm jaw
    mouth(c, "smirk", sk, y=30)
    c.pts([(15, 26), (16, 27), (32, 26), (31, 27)], sk[2])  # age lines
    c.pts([(20, 32), (21, 32), (22, 32), (26, 32), (27, 32), (28, 32)], mix(sk[1], hair[1], 0.35))  # stubble


def ilse(c):
    sk = skin_cols("pale")
    hair = tone("#ece6d6")
    hair = (H("#fbf7ec"), H("#e4ddcc"), H("#a9a3bd"))
    # long hair behind the shoulders
    c.blob(poly_mask([(9, 14), (14, 6), (24, 3), (34, 6), (39, 14), (41, 30), (44, 46), (38, 48), (30, 48), (18, 48), (9, 48), (5, 44), (7, 30)]), hair)
    # uniform: black double-breasted jacket, crimson trim
    torso(c, BLACK, [(5, 48), (7, 42), (15, 38), (33, 38), (41, 42), (43, 48)])
    c.blob(poly_mask([(16, 38), (32, 38), (27, 47), (21, 47)]), tone("#ece8e0"), edge=False)
    c.blob(poly_mask([(14, 37), (21, 37), (24, 47), (15, 47)]), BLACK)
    c.blob(poly_mask([(34, 37), (27, 37), (24, 47), (33, 47)]), tone("#2a2b34"))
    c.vline(22, 38, 9, CRIM[1])
    c.vline(26, 38, 9, CRIM[1])
    c.pts([(23, 41), (23, 44), (25, 41), (25, 44)], GOLD[0])
    c.blob(rect_mask(7, 42, 7, 2), CRIM)
    c.blob(rect_mask(34, 42, 7, 2), CRIM)
    # chest contour
    c.pts([(17, 44), (18, 45), (19, 45), (29, 45), (30, 45), (31, 44)], BLACK[0])
    c.hline(16, 46, 4, BLACK[2])
    c.hline(28, 46, 4, BLACK[2])
    neck(c, sk, w=6, y0=31, y1=39)
    ears(c, sk, y=21, dx=10.0)
    head(c, sk, rx=9.5, ry=11.5, p=2.2)
    # parted bangs and long side locks falling over the shoulders
    c.blob(poly_mask([(12, 24), (11, 14), (15, 7), (23, 5), (31, 6), (36, 11), (37, 20), (36, 26), (34, 17), (28, 13), (24, 14), (19, 13), (14, 18)]), hair)
    c.blob(poly_mask([(13, 12), (24, 11), (21, 18), (17, 22), (15, 17)]), hair)
    c.blob(poly_mask([(24, 11), (35, 12), (33, 19), (28, 19)]), hair)
    c.blob(poly_mask([(10, 18), (14, 18), (15, 31), (13, 40), (8, 46), (6, 36)]), hair)
    c.blob(poly_mask([(34, 18), (38, 18), (42, 36), (40, 46), (35, 40), (33, 31)]), hair)
    # crimson ribbon
    c.blob(poly_mask([(30, 7), (36, 9), (34, 12), (29, 10)]), CRIM)
    # crimson, wide, unsettling eyes + sweet smile
    crim = H("#d81838")
    eye(c, 17, 21, "sweet", crim, left=True, sk=sk)
    eye(c, 27, 21, "sweet", crim, left=False, sk=sk)
    brow(c, 17, 18, 4, -1, hair[2], left=True)
    brow(c, 27, 18, 4, -1, hair[2], left=False)
    nose(c, sk, y=26)
    mouth(c, "sweet", sk, y=29, lip=H("#c83048"))
    blush(c, H("#f0a0a8"), y=26)


def grau(c):
    sk = skin_cols("grey")
    crim = tone("#a81c2c")
    # crimson marshal's tunic, gold embroidery, medals
    torso(c, crim, [(2, 48), (4, 43), (13, 39), (35, 39), (44, 43), (46, 48)])
    c.blob(rect_mask(4, 43, 9, 3), GOLD)
    c.blob(rect_mask(35, 43, 9, 3), GOLD)
    c.vline(24, 40, 8, crim[2])
    neck(c, sk, w=6, y0=33, y1=41)
    c.blob(poly_mask([(15, 36), (21, 36), (22, 42), (17, 41)]), tone("#7a1220"))
    c.blob(poly_mask([(33, 36), (27, 36), (26, 42), (31, 41)]), tone("#7a1220"))
    c.blob(rect_mask(14, 38, 20, 2), GOLD, edge=True)  # embroidered high collar
    for i, col in enumerate(("#e8c050", "#3a6ac0", "#e8c050", "#f4f0e0")):
        c.blob(rect_mask(8 + i * 3, 44, 3, 4), tone(col), edge=True)
    c.blob(rect_mask(32, 44, 5, 4), tone("#e8c050"))
    c.pts([(34, 45), (35, 46)], crim[2])
    c.line(13, 40, 17, 47, GOLD[1])
    ears(c, sk, y=24, dx=9.5)
    # gaunt head, pointed chin
    c.blob(poly_mask([(15, 15), (33, 15), (34, 24), (32, 30), (28, 35), (24, 37), (20, 35), (16, 30), (14, 24)]), sk, side=3)
    c.blob(ell_mask(HX, 22, 9.5, 8, 2.2), sk, edge=False, side=3)
    # hollow cheeks and brow ridge
    for p in ((17, 28), (18, 29), (19, 30), (31, 28), (30, 29), (29, 30), (16, 26), (32, 26)):
        c.put(p[0], p[1], sk[2])
    c.pts([(18, 27), (19, 28), (30, 27), (29, 28)], mix(sk[1], sk[2], 0.5))
    # tall ornate cap
    c.blob(poly_mask([(11, 15), (12, 3), (15, 0), (33, 0), (36, 3), (37, 15)]), crim)
    c.blob(poly_mask([(10, 14), (38, 14), (38, 18), (34, 19), (14, 19), (10, 18)]), tone("#14141a"))
    c.blob(rect_mask(11, 9, 26, 3), GOLD)
    for x in range(13, 36, 4):
        c.pts([(x, 10)], GOLD[2])
    c.hline(14, 1, 20, GOLD[0])
    c.hline(11, 16, 26, GOLD[1])
    c.blob(poly_mask([(24, 3), (28, 6), (24, 9), (20, 6)]), GOLD)
    c.put(24, 6, H("#e02a40"))
    c.pts([(19, 14), (29, 14)], crim[2])
    # eyes: cold left eye, monocle + mechanical lens on the right
    eye(c, 17, 22, "steady", H("#4a5870"), left=True, sk=sk)
    brow(c, 16, 20, 5, 2, H("#d8d8d8"), left=True)
    brow(c, 28, 20, 4, 2, H("#d8d8d8"), left=False)
    c.hline(27, 22, 4, H("#14141a"))
    c.hline(27, 23, 4, H("#8a0c18"))
    c.pts([(28, 23), (29, 23)], H("#ff3a48"))
    c.put(28, 23, H("#ffc8c8"))
    for (x, y) in ell_mask(29, 23, 4.2, 4.2) - ell_mask(29, 23, 2.9, 2.9):
        c.put(x, y, GOLD[1])
    c.pts([(26, 21), (27, 20)], GOLD[0])
    c.line(32, 26, 35, 37, GOLD[2])
    nose(c, sk, y=26)
    c.pts([(HX - 1, 26), (HX, 26)], sk[2])
    c.hline(HX - 3, 31, 6, H("#3a2a30"))
    c.pts([(HX - 4, 32), (HX + 3, 32)], H("#3a2a30"))
    # thin white hair wisps over the ears
    c.pts([(14, 20), (14, 21), (14, 22), (34, 20), (34, 21), (34, 22)], H("#dedede"))


def hq(c):
    sk = skin_cols("fair")
    hair = tone("#6a4a30")
    standard_shoulders(c, OLIVE)
    neck(c, sk)
    c.blob(poly_mask([(16, 37), (32, 37), (28, 42), (20, 42)]), tone("#55612d"), edge=False)
    c.blob(rect_mask(5, 41, 8, 3), AMBER)
    c.blob(rect_mask(35, 41, 8, 3), AMBER)
    c.blob(rect_mask(14, 40, 4, 2), AMBER)
    c.blob(rect_mask(30, 40, 4, 2), AMBER)
    ears(c, sk)
    head(c, sk, rx=10, ry=11.5, p=2.3)
    c.blob(poly_mask([(12, 22), (11, 13), (15, 7), (23, 5), (32, 7), (36, 13), (36, 22), (34, 16), (29, 12), (19, 12), (15, 16)]), hair)
    c.blob(poly_mask([(15, 12), (26, 11), (22, 16), (18, 16)]), hair)
    eye(c, 17, 21, "steady", H("#4a7a58"), left=True, sk=sk)
    eye(c, 27, 21, "steady", H("#4a7a58"), left=False, sk=sk)
    brow(c, 17, 19, 4, 0, hair[2], left=True)
    brow(c, 27, 19, 4, 0, hair[2], left=False)
    nose(c, sk)
    mouth(c, "smile", sk, y=29)
    # headset: band over the head, ear cup, mic boom
    band = tone("#2c2e34")
    c.line(12, 20, 12, 12, band[1])
    c.line(12, 12, 16, 6, band[1])
    c.line(16, 6, 24, 4, band[1])
    c.line(24, 4, 32, 6, band[1])
    c.line(32, 6, 36, 12, band[1])
    c.vline(36, 12, 8, band[1])
    c.blob(rect_mask(9, 18, 5, 9), tone("#5a606a"))
    c.blob(rect_mask(10, 20, 3, 5), band, edge=False)
    c.pts([(10, 20)], band[0])
    c.line(11, 27, 14, 31, band[1])
    c.line(14, 31, 19, 31, band[1])
    c.blob(rect_mask(19, 30, 3, 3), tone("#c8c8c8"), edge=True)
    c.put(20, 31, H("#303030"))


def syndikat(c):
    steel = tone("#58606a")
    # charcoal greatcoat, crimson tabs, crossed straps
    torso(c, CHAR, [(3, 48), (5, 42), (14, 38), (34, 38), (43, 42), (45, 48)])
    c.blob(poly_mask([(14, 38), (20, 38), (22, 44), (15, 43)]), tone("#2a2c33"))
    c.blob(poly_mask([(34, 38), (28, 38), (26, 44), (33, 43)]), tone("#2a2c33"))
    c.blob(rect_mask(16, 40, 4, 3), CRIM)
    c.blob(rect_mask(28, 40, 4, 3), CRIM)
    c.line(8, 44, 20, 47, tone("#5a4a38")[1])
    c.line(40, 44, 28, 47, tone("#5a4a38")[1])
    c.line(8, 43, 20, 46, tone("#6a5a46")[0])
    neck(c, tone("#2e3036"), w=8, y0=31, y1=39)
    # gas mask: rubber face, filter canister, red lenses
    rub = tone("#2c3034")
    c.blob(ell_mask(HX, 23, 9.5, 10.5, 2.3), rub, side=3)
    c.blob(poly_mask([(16, 26), (32, 26), (30, 34), (24, 37), (18, 34)]), rub, side=2)
    for gx in (18, 30):
        c.blob(ell_mask(gx, 20, 4.6, 4.2), H("#14161a"), edge=False)
        c.blob(ell_mask(gx, 20, 3.4, 3.2), H("#e02a30"), edge=False)
        c.pts([(gx - 2, 18), (gx - 1, 18), (gx - 2, 19)], H("#ffd0c8"))
        c.pts([(gx + 2, 22), (gx + 1, 22)], H("#7a0c14"))
    c.blob(rect_mask(21, 27, 6, 8), steel)
    for y in (29, 31, 33):
        c.hline(21, y, 6, steel[2])
    c.blob(rect_mask(22, 36, 4, 2), tone("#2a2c30"), edge=False)
    c.pts([(15, 29), (16, 31), (32, 31), (33, 29)], rub[0])
    c.line(13, 26, 18, 25, rub[2])
    c.line(35, 26, 30, 25, rub[2])
    # stahlhelm: domed, wide brim flaring over the neck
    c.blob(poly_mask([(10, 19), (11, 9), (16, 3), (24, 1), (32, 3), (37, 9), (38, 19), (41, 22), (36, 26), (36, 17), (12, 17), (12, 26), (7, 22)]), steel)
    c.blob(poly_mask([(9, 15), (39, 15), (40, 18), (36, 19), (12, 19), (8, 18)]), tone("#444c56"))
    c.hline(11, 7, 8, steel[0])
    c.blob(rect_mask(22, 5, 5, 6), CRIM)
    c.pts([(23, 7), (24, 8), (23, 9)], H("#d0d4d8"))
    c.vline(24, 1, 4, steel[0])


CHARS = {
    "leon": (leon, ("#15122a", "#2c3a2a"), None),
    "leon_child": (leon_child, ("#2a0a06", "#7a2a0c"), (24, 40, 30, "#f08a30")),
    "mira": (mira, BG_COAL, None),
    "chad": (chad, BG_COAL, None),
    "brann": (brann, BG_COAL, None),
    "wolfram": (wolfram, BG_SYN, None),
    "konrad": (konrad, BG_SYN, None),
    "ilse": (ilse, BG_SYN, None),
    "grau": (grau, ("#180a10", "#3c1620"), None),
    "hq": (hq, ("#0c2830", "#1a4a46"), None),
    "syndikat": (syndikat, BG_SYN, None),
}


def portrait_rows(name):
    fn, (top, bottom), glow = CHARS[name]
    c = Canvas()
    fn(c)
    return c.render(backdrop(top, bottom, glow=glow, scan=True))


def write_portraits(out):
    d = os.path.join(out, "portraits")
    os.makedirs(d, exist_ok=True)
    for name in CHARS:
        png.write_png(os.path.join(d, name + ".png"), SIZE, SIZE, portrait_rows(name))
