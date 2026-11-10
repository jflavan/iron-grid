"""Story cutscene backdrops (354x142, opaque). Deterministic: every scene seeds its own random.Random.

Same painting vocabulary as backdrops.py (dithered bands, silhouettes, speckle) on a richer canvas
(alpha blends for glow/smoke/light cones, polygons) plus walker sprites reused from the chassis renderer.
Composition rule: focal subject in the middle third; the lower ~72x72 corners hold only low-value filler.
"""
import math
import os
import random

import chassis as chassis_mod
import png
import poses
import raster
import rig

W, H = 354, 142
BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def C(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _c(c):
    return C(c) if isinstance(c, str) else c


def lerp(a, b, t):
    a, b = _c(a), _c(b)
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, f):
    c = _c(c)
    return tuple(max(0, min(255, int(v * f))) for v in c)


class Cv:
    def __init__(self):
        self.px = [[(0, 0, 0)] * W for _ in range(H)]

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.px[y][x] = _c(c)

    def blend(self, x, y, c, a):
        if 0 <= x < W and 0 <= y < H and a > 0:
            self.px[y][x] = lerp(self.px[y][x], c, a)

    def rect(self, x, y, w, h, c, a=1.0):
        c = _c(c)
        for yy in range(max(0, y), min(H, y + h)):
            for xx in range(max(0, x), min(W, x + w)):
                if a >= 1.0:
                    self.px[yy][xx] = c
                else:
                    self.px[yy][xx] = lerp(self.px[yy][xx], c, a)

    def poly(self, pts, c, a=1.0):
        c = _c(c)
        ys = [p[1] for p in pts]
        for y in range(max(0, int(math.floor(min(ys)))), min(H, int(math.ceil(max(ys))) + 1)):
            Y = y + 0.5
            xs = []
            j = len(pts) - 1
            for i in range(len(pts)):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > Y) != (yj > Y):
                    xs.append((xj - xi) * (Y - yi) / (yj - yi) + xi)
                j = i
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for x in range(int(math.floor(xs[k] + 0.5)), int(math.floor(xs[k + 1] + 0.5))):
                    if 0 <= x < W:
                        self.px[y][x] = c if a >= 1.0 else lerp(self.px[y][x], c, a)

    def disc(self, cx, cy, r, c, a=1.0):
        self.ellipse(cx, cy, r, r, c, a)

    def ellipse(self, cx, cy, rx, ry, c, a=1.0):
        c = _c(c)
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    if a >= 1.0:
                        self.put(x, y, c)
                    else:
                        self.blend(x, y, c, a)

    def line(self, x0, y0, x1, y1, c, a=1.0):
        n = int(max(abs(x1 - x0), abs(y1 - y0), 1))
        for i in range(n + 1):
            x = int(round(x0 + (x1 - x0) * i / n))
            y = int(round(y0 + (y1 - y0) * i / n))
            if a >= 1.0:
                self.put(x, y, c)
            else:
                self.blend(x, y, c, a)

    def bands(self, y0, y1, c0, c1, steps, x0=0, x1=W):
        hh = max(1, y1 - y0)
        for y in range(y0, y1):
            f = (y - y0) / hh * steps
            b = int(f)
            fr = f - b
            for x in range(x0, x1):
                nx = fr > 0.75 and ((x + y) & 1)
                self.put(x, y, lerp(c0, c1, min(1.0, (b + (1 if nx else 0)) / steps)))

    def glow(self, cx, cy, r, c, k=0.6, ry=None):
        ry = ry or r
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                d = math.hypot((x + 0.5 - cx) / r, (y + 0.5 - cy) / ry)
                if d < 1.0:
                    t = (1.0 - d) ** 1.6 * k * 5
                    lv = int(t)
                    if t - lv > (BAYER[y & 3][x & 3] + 0.5) / 16.0:
                        lv += 1
                    self.blend(x, y, c, min(k, lv / 5.0))

    def speckle(self, rng, n, x0, y0, x1, y1, cols):
        for _ in range(n):
            self.put(rng.randrange(x0, x1), rng.randrange(y0, y1), cols[rng.randrange(len(cols))])

    def cone(self, x, y, wtop, wbot, ybot, c, a=0.16):
        """Light cone from (x,y) widening to wbot at ybot (dithered by two stacked alphas)."""
        self.poly([(x - wtop, y), (x + wtop, y), (x + wbot, ybot), (x - wbot, ybot)], c, a)
        self.poly([(x - wtop * 0.5, y), (x + wtop * 0.5, y), (x + wbot * 0.55, ybot), (x - wbot * 0.55, ybot)], c, a * 0.8)

    def finish(self, cap=226):
        rows = []
        for row in self.px:
            rows.append([(min(cap, r), min(cap, g), min(cap, b), 255) for r, g, b in row])
        return rows


# ---------------------------------------------------------------- shared props

def smoke(cv, rng, x, y, n=9, dark="#2c2624", spread=2.0, a=0.42, grow=1.0):
    for k in range(n):
        r = 4 + k * grow * 1.3
        cv.disc(x + int(rng.uniform(-2, 2) * (k + 1) * 0.4 + k * spread), y - k * 7, int(r), dark, a * (1.0 - k / (n + 2)))


def flame(cv, rng, x, by, w, h, glow=True):
    n = max(2, w // 4)
    for layer, (col, sc) in enumerate((("#8a1c10", 1.0), ("#d8581a", 0.78), ("#f0a238", 0.5), ("#f4d27a", 0.24))):
        for i in range(n):
            fx = x + int((i + 0.5) / n * w - w / 2) + rng.randint(-1, 1)
            fh = int(h * sc * rng.uniform(0.6, 1.1))
            fw = max(2, int(w / n * (0.9 if layer < 2 else 0.6)))
            cv.poly([(fx - fw, by), (fx + fw, by), (fx + rng.randint(-2, 2), by - fh)], col)
    if glow:
        cv.glow(x, by - h // 2, w * 1.6 + 8, "#ff8a30", 0.45, ry=h * 1.2 + 6)


def embers(cv, rng, n, x0, y0, x1, y1):
    for _ in range(n):
        x, y = rng.randrange(x0, x1), rng.randrange(y0, y1)
        cv.put(x, y, "#f4a43a" if rng.random() < 0.7 else "#ffd27a")


def snowfall(cv, rng, n, a=0.7):
    for _ in range(n):
        x, y = rng.randrange(0, W), rng.randrange(0, H)
        cv.blend(x, y, "#d4dce4", a)
        if rng.random() < 0.25:
            cv.blend(x - 1, y - 1, "#d4dce4", a * 0.5)


def window_grid(cv, x, y, cols, rows, cw, ch, gx, gy, lit, dark, rng, p_lit=0.2):
    for r in range(rows):
        for c in range(cols):
            col = lit if rng.random() < p_lit else dark
            cv.rect(x + c * gx, y + r * gy, cw, ch, col)


# ---------------------------------------------------------------- walker sprites (chassis renderer)

_CACHE = {}


def sprite(name, pal, key=0, flags=()):
    """Rendered idle0 frame of a chassis as {(x,y): rgb}, plus (w,h)."""
    k = (name if isinstance(name, str) else "custom", pal if isinstance(pal, str) else "custom", key)
    if k in _CACHE:
        return _CACHE[k]
    defn = chassis_mod.CHASSIS[name] if isinstance(name, str) else name
    table = poses.pose_table(defn)
    _, off, gun = table[0]
    buf = raster.render(defn["w"], defn["h"], rig.frame_parts(defn, off, gun, flags))
    p = raster.palette_for(pal) if isinstance(pal, str) else pal
    rows = raster.colorize(buf, defn["w"], defn["h"], p)
    out = {}
    for y, row in enumerate(rows):
        for x, px in enumerate(row):
            if px[3]:
                out[(x, y)] = px[:3]
    _CACHE[k] = (out, defn["w"], defn["h"])
    return _CACHE[k]


def blit(cv, spr, x, y, num=1, den=1, mirror=False, recolor=None, flip_rot=False):
    """Nearest-neighbour scale num/den, top-left at (x, y)."""
    px, w, h = spr
    ow, oh = w * num // den, h * num // den
    for yy in range(oh):
        for xx in range(ow):
            sx = (ow - 1 - xx if mirror else xx) * den // num
            sy = yy * den // num
            c = px.get((sx, sy))
            if c is None:
                continue
            cv.put(x + xx, y + yy, recolor(c) if recolor else c)


def grey_pal():
    p = raster.palette_for("coalition")
    p["hull"] = [raster.hex_rgb(c) for c in ("#a6aab0", "#6a6f78", "#3c4048")]
    p["rear"] = [p["hull"][1], p["hull"][2], raster.hex_rgb("#202226")]
    p["trim"] = [raster.hex_rgb(c) for c in ("#c8c0a0", "#8e8668", "#544e3a")]
    p["glow"] = [raster.hex_rgb("#d8c070")] * 3
    return p


def silhouette(col, lens=None):
    col = _c(col)

    def f(c):
        if lens and c[0] > 200 and c[1] < 120:  # glow / lens pixels stay lit
            return _c(lens)
        return col
    return f


def soot(f=0.5):
    def g(c):
        return tuple(int(v * f) for v in c)
    return g


# front-view walker (the chassis sprites are all side views)

def walker_front(cv, cx, by, s, hull, trim="#c8a040", lens="#ffd070", damaged=False, rng=None):
    """hull = (hi, base, sh). s scales a 60x66 figure standing with feet at by."""
    hi, base, sh = [_c(c) for c in hull]
    dk = lerp(sh, "#14161a", 0.5)
    metal, metal_d = C("#7a7f88"), C("#3c4048")

    def X(v):
        return int(round(cx + v * s))

    def Y(v):
        return int(round(by - v * s))

    def box(x0, y0, x1, y1, c):
        cv.rect(X(x0), Y(y1), max(1, X(x1) - X(x0)), max(1, Y(y0) - Y(y1)), c)

    cv.ellipse(cx, by, int(34 * s), max(2, int(4 * s)), "#101214", 0.45)
    # legs
    for lx in (-21, 7):
        box(lx, 4, lx + 14, 28, base)
        box(lx, 4, lx + 3, 28, hi)
        box(lx + 11, 4, lx + 14, 28, sh)
        box(lx - 1, 15, lx + 15, 21, metal_d)
        box(lx - 1, 15, lx + 15, 16, metal)
        box(lx - 4, 0, lx + 18, 5, dk)
        box(lx - 4, 4, lx + 18, 5, metal_d)
    # pelvis
    box(-19, 28, 19, 35, dk)
    for rx in (-14, -4, 6, 14):
        cv.put(X(rx), Y(31), metal)
    # torso
    cv.poly([(X(-23), Y(35)), (X(23), Y(35)), (X(27), Y(49)), (X(19), Y(58)), (X(-19), Y(58)), (X(-27), Y(49))], base)
    cv.poly([(X(-23), Y(35)), (X(-14), Y(35)), (X(-17), Y(58)), (X(-19), Y(58)), (X(-27), Y(49))], hi)
    cv.poly([(X(14), Y(35)), (X(23), Y(35)), (X(27), Y(49)), (X(19), Y(58)), (X(16), Y(58))], sh)
    box(-23, 46, 23, 48, trim)
    box(-1, 35, 1, 46, sh)
    box(-12, 38, -4, 44, dk)
    box(4, 38, 12, 44, dk)
    # shoulder cannons pointed at the viewer
    for sx, sgn in ((-36, -1), (24, 1)):
        box(sx, 44, sx + 12, 58, metal_d)
        box(sx, 56, sx + 12, 58, metal)
        mx = X(sx + 6)
        cv.disc(mx, Y(50), max(2, int(4 * s)), "#16181c")
        cv.disc(mx, Y(50), max(1, int(2 * s)), "#07080a")
        cv.rect(mx - 1, Y(53), 1, 1, metal)
    # head / cockpit
    box(-10, 58, 10, 68, dk)
    box(-10, 66, 10, 68, base)
    box(-7, 61, 7, 63, lens)
    cv.glow(cx, Y(62), int(12 * s), lens, 0.35, ry=int(6 * s))
    box(-1, 68, 1, 74, metal_d)
    if damaged:
        rng = rng or random.Random(1)
        for _ in range(26):
            cv.put(X(rng.uniform(-24, 24)), Y(rng.uniform(36, 57)), "#16120e")
        box(8, 40, 14, 46, "#0a0808")
        cv.line(X(-20), Y(40), X(-12), Y(52), "#2a2218")
        cv.line(X(-12), Y(52), X(-14), Y(57), "#2a2218")
        box(-18, 28, -12, 32, "#2a2218")


# ---------------------------------------------------------------- scenes

def briefing_room(cv, rng):
    cv.bands(0, 98, "#1c2216", "#3a4228", 8)
    for x in range(0, W, 12):  # panel seams
        cv.rect(x, 0, 1, 98, "#171c12", 0.5)
    cv.rect(0, 70, W, 2, "#59492c")
    cv.rect(0, 72, W, 26, "#2a3020")
    for x in range(0, W, 12):
        cv.rect(x, 72, 1, 26, "#20261a")
    cv.rect(0, 97, W, 2, "#59492c")
    cv.bands(99, H, "#2b2218", "#403020", 5)
    for i in range(0, W + 80, 18):  # floor boards in perspective
        cv.line(177 + (i - 177) * 0.3, 99, i - 40, H, "#1c150e")
    # wall map
    cv.rect(104, 8, 146, 66, "#2a2418")
    cv.rect(107, 11, 140, 60, "#b4a676")
    cv.rect(107, 11, 140, 60, "#6e6240", 0.18)
    for gx in range(107, 247, 14):
        cv.rect(gx, 11, 1, 60, "#8c7e56")
    for gy in range(11, 71, 12):
        cv.rect(107, gy, 140, 1, "#8c7e56")
    cv.poly([(110, 40), (130, 24), (160, 20), (176, 32), (170, 52), (146, 64), (120, 60)], "#6c7a48")
    cv.poly([(186, 18), (230, 16), (242, 34), (226, 56), (200, 62), (190, 44)], "#7a8454")
    cv.poly([(150, 26), (160, 24), (166, 40), (156, 46)], "#5a6a3c")
    cv.line(176, 30, 190, 44, "#4a6070")
    cv.line(176, 34, 192, 46, "#4a6070")
    pins = [(128, 32), (150, 44), (168, 28), (196, 26), (214, 40), (226, 24), (205, 54), (140, 54)]
    for i in range(len(pins) - 1):
        a, b = pins[i], pins[(i * 3 + 2) % len(pins)]
        cv.line(a[0], a[1], b[0], b[1], "#a02a22", 0.8)
    for i, p in enumerate(pins):
        cv.rect(p[0] - 1, p[1] - 1, 3, 3, "#c83a2a" if i % 3 else "#e0a030")
        cv.put(p[0] - 1, p[1] - 1, "#e8c8a0")
    cv.rect(0, 0, W, 8, "#12160e")
    # hanging lamps with light cones
    for lx in (62, 177, 292):
        cv.rect(lx, 0, 1, 12, "#14160f")
        cv.cone(lx, 14, 5, 40 if lx == 177 else 34, 100, "#f0b050", 0.10)
        cv.poly([(lx - 7, 20), (lx + 7, 20), (lx + 3, 13), (lx - 3, 13)], "#4a4a30")
        cv.rect(lx - 7, 19, 15, 2, "#c89838")
        cv.rect(lx - 3, 21, 7, 2, "#ffd890")
        cv.glow(lx, 24, 30, "#f0b050", 0.4, ry=22)
    # radio sets (left)
    cv.rect(6, 30, 66, 4, "#4a3a22")
    cv.rect(6, 62, 66, 4, "#4a3a22")
    for i, rx in enumerate((8, 30, 52)):
        cv.rect(rx, 36, 18, 26, "#35402a")
        cv.rect(rx, 36, 18, 2, "#566444")
        cv.rect(rx + 3, 40, 12, 8, "#14180e")
        cv.rect(rx + 4, 42, 10, 1, "#6a8a50")
        cv.rect(rx + 4, 44, 6, 1, "#6a8a50")
        cv.disc(rx + 5, 54, 2, "#20241a")
        cv.disc(rx + 13, 54, 2, "#20241a")
        cv.put(rx + 14, 41, "#f0a030")
    cv.rect(10, 8, 1, 22, "#14160f")
    cv.rect(8, 10, 5, 1, "#14160f")
    cv.rect(48, 4, 1, 26, "#14160f")
    # chalkboard (right)
    cv.rect(278, 16, 66, 46, "#4a3820")
    cv.rect(281, 19, 60, 40, "#243a2c")
    for i in range(7):
        cv.line(285, 24 + i * 5, 285 + rng.randint(14, 48), 24 + i * 5 + rng.randint(-1, 1), "#a8b0a0", 0.75)
    cv.rect(312, 44, 22, 10, "#243a2c")
    cv.line(314, 52, 330, 46, "#a8b0a0", 0.8)
    cv.rect(283, 58, 10, 2, "#c0b8a0")
    # map table in perspective (centre)
    cv.poly([(86, 92), (268, 92), (292, 116), (62, 116)], "#6a5a38")
    cv.poly([(92, 94), (262, 94), (282, 112), (72, 112)], "#a89c6c")
    cv.glow(177, 100, 110, "#f0b050", 0.38, ry=20)
    for gx in range(-4, 5):
        cv.line(177 + gx * 18, 94, 177 + gx * 22, 112, "#7e7248", 0.7)
    for gy in (100, 106):
        cv.line(82, gy, 272, gy, "#7e7248", 0.7)
    cv.poly([(120, 98), (150, 96), (156, 104), (126, 106)], "#6e7c48", 0.8)
    for bx, col in ((140, "#8a2a20"), (186, "#8a2a20"), (212, "#3a5a78"), (160, "#3a5a78"), (234, "#3a5a78")):
        cv.rect(bx, 99, 5, 3, col)
        cv.rect(bx, 99, 5, 1, lerp(col, "#f0e0b0", 0.4))
    cv.rect(62, 116, 230, 5, "#3a2c18")
    cv.rect(62, 116, 230, 1, "#7a6a42")
    for lx in (70, 100, 250, 280):
        cv.rect(lx, 121, 6, 21, "#2a2012")
    # chairs
    for cx in (100, 177, 254):
        cv.rect(cx - 9, 124, 18, 4, "#241a10")
        cv.rect(cx - 9, 128, 2, 14, "#241a10")
        cv.rect(cx + 7, 128, 2, 14, "#241a10")


def village_fire(cv, rng):
    cv.bands(0, 92, "#241418", "#cc6a24", 12)
    cv.glow(262, 88, 150, "#ff8a30", 0.35, ry=60)
    for k in range(3):
        smoke(cv, rng, 70 + k * 100, 92, 10, "#1e1614", 3.0, 0.5, 1.5)
    cv.poly([(0, 90), (0, 70), (40, 62), (90, 74), (150, 66), (210, 76), (260, 60), (354, 70), (354, 92)], "#3a2220")
    # ridge, upper right, with the command walker
    cv.poly([(238, 142), (238, 60), (262, 54), (290, 50), (320, 46), (354, 44), (354, 142)], "#140c0c")
    cv.poly([(238, 66), (262, 54), (290, 50), (320, 46), (354, 44), (354, 48), (320, 52), (290, 56), (262, 60)], "#2a1a16")
    spr = sprite("kommandant", "blackclaw")
    blit(cv, spr, 276, 49 - 52 + 4, 1, 2, recolor=silhouette("#0c0808", "#ff3a34"))
    cv.glow(276 + 33, 49 - 52 + 4 + 11, 12, "#ff3030", 0.5)
    # village
    cv.rect(0, 100, W, 42, "#22150f")
    cv.bands(100, H, "#3a2416", "#1a100c", 5)
    cv.poly([(100, 142), (254, 142), (200, 100), (160, 100)], "#4a3220", 0.55)

    def house(x, by, w, h, roof, col, fire):
        cv.rect(x, by - h, w, h, col)
        cv.rect(x, by - h, w, 2, shade(col, 0.6))
        for bx in range(x, x + w + 1, max(8, w // 3)):
            cv.rect(bx, by - h, 2, h, "#22140c")
        cv.line(x, by - h, x + w // 3, by, "#22140c")
        cv.line(x + w, by - h, x + w * 2 // 3, by, "#22140c")
        cv.poly([(x - 4, by - h), (x + w + 4, by - h), (x + w // 2, by - h - roof)], "#2e1a12")
        cv.poly([(x - 4, by - h), (x + w // 2, by - h - roof), (x + w // 2, by - h - roof + 3), (x - 1, by - h)], "#4a2a1a")
        for wx in (x + 5, x + w - 12):
            cv.rect(wx, by - h + 6, 7, 8, "#ffb040" if fire else "#4a3a2a")
            cv.glow(wx + 3, by - h + 10, 14, "#ff8a30", 0.45) if fire else None
        cv.rect(x + w // 2 - 3, by - 14, 7, 14, "#120a06")
    house(14, 124, 46, 30, 22, "#6e4a30", True)
    house(64, 130, 40, 26, 18, "#5e4430", False)
    house(252, 126, 54, 32, 24, "#6a4630", True)
    house(312, 124, 36, 28, 20, "#5a4030", True)
    # centre house: roof caving in
    cv.rect(128, 82, 98, 50, "#5e3e28")
    cv.rect(128, 82, 98, 2, "#3a2418")
    for bx in range(128, 226, 14):
        cv.rect(bx, 82, 2, 50, "#1e120a")
    cv.line(128, 82, 150, 132, "#1e120a")
    cv.line(226, 82, 204, 132, "#1e120a")
    for wx in (138, 196):
        cv.rect(wx, 94, 11, 12, "#ffb040")
        cv.rect(wx, 94, 11, 1, "#c0501a")
        cv.rect(wx + 5, 94, 1, 12, "#4a2a14")
    cv.rect(170, 112, 14, 20, "#0e0804")
    cv.poly([(122, 82), (150, 82), (160, 50), (140, 58)], "#2e1a12")  # left roof half, still up
    cv.poly([(232, 82), (210, 82), (212, 72), (230, 78)], "#2e1a12")  # right slumped
    cv.poly([(150, 82), (214, 82), (200, 96), (176, 90), (160, 96)], "#0c0604")  # hole
    for i, (x0, y0, x1, y1) in enumerate(((158, 52, 188, 92), (190, 66, 214, 96), (172, 60, 196, 88), (200, 58, 220, 82))):
        cv.line(x0, y0, x1, y1, "#100804")
        cv.line(x0 + 1, y0, x1 + 1, y1, "#2a1a10")
    flame(cv, rng, 176, 96, 54, 56)
    flame(cv, rng, 140, 64, 18, 24)
    flame(cv, rng, 34, 96, 26, 30)
    flame(cv, rng, 276, 96, 30, 36)
    flame(cv, rng, 330, 98, 16, 22)
    for sx, sy in ((176, 40), (34, 70), (276, 66), (330, 80)):
        smoke(cv, rng, sx, sy, 8, "#201a18", 2.0, 0.55, 1.4)
    embers(cv, rng, 90, 20, 10, 340, 100)
    # fence and well in front
    for x in range(20, 120, 9):
        cv.rect(x, 126, 2, 10, "#1a0e08")
    cv.rect(20, 129, 100, 1, "#1a0e08")
    cv.speckle(rng, 200, 0, 108, W, H, ("#2a1810", "#5a3a20", "#7a4a22"))


def memorial(cv, rng):
    cv.bands(0, 82, "#5a82b0", "#b4cad0", 10)
    cv.disc(52, 22, 8, "#e8dca8", 0.8)
    for cx, cy, rw in ((90, 20, 26), (250, 30, 34), (300, 14, 20), (170, 12, 22)):
        cv.ellipse(cx, cy, rw, 5, "#c8d4d6", 0.8)
        cv.ellipse(cx - 4, cy - 3, rw * 0.6, 4, "#d6dcd8", 0.8)
    cv.poly([(0, 84), (0, 66), (60, 58), (130, 70), (200, 60), (280, 68), (354, 58), (354, 84)], "#6a8a74")
    cv.poly([(0, 88), (0, 74), (80, 68), (160, 76), (260, 70), (354, 76), (354, 88)], "#5a7a50")
    # square
    cv.bands(88, H, "#a89a78", "#8a7c5c", 5)
    for y in range(90, H, 5):
        off = (y // 5) % 2 * 6
        for x in range(-off, W, 12):
            cv.put(x, y, "#6e6248")
        cv.rect(0, y, W, 1, "#6e6248", 0.35)
    cv.speckle(rng, 260, 0, 90, W, H, ("#c4b890", "#76694e"))

    def house(x, by, w, h, wall, roof, awning=None):
        cv.rect(x, by - h, w, h, wall)
        cv.rect(x + w - 6, by - h, 6, h, shade(wall, 0.84))
        cv.poly([(x - 4, by - h), (x + w + 4, by - h), (x + w - 6, by - h - 16), (x + 6, by - h - 16)], roof)
        cv.rect(x - 4, by - h, w + 8, 2, shade(roof, 0.65))
        for ry in range(by - h - 14, by - h, 4):
            cv.rect(x + 8, ry, w - 16, 1, shade(roof, 0.8))
        return by - h
    # bakery (left-middle)
    top = house(24, 108, 78, 40, "#d0b078", "#a84a30")
    cv.rect(46, 78, 34, 22, "#3a2a1c")
    cv.rect(48, 80, 30, 18, "#9ab4bc")
    for bx in (52, 60, 68):
        cv.ellipse(bx, 96, 4, 2, "#c88838")
    for i in range(8):
        cv.rect(42 + i * 5, 70, 5, 8, "#b83a2c" if i % 2 else "#e0d4b0")
    cv.rect(42, 78, 40, 1, "#6a3a20")
    cv.rect(88, 84, 10, 24, "#5a3a22")
    cv.rect(30, 80, 9, 12, "#9ab4bc")
    cv.rect(35, 80, 1, 12, "#6a4a30")
    cv.rect(26, 56, 18, 8, "#e8dcb0")
    cv.rect(26, 56, 18, 1, "#6a4a30")
    cv.rect(28, 59, 14, 1, "#8a4a30")
    cv.rect(31, 61, 8, 1, "#8a4a30")
    house(262, 106, 70, 36, "#c8b890", "#8a3a2c")
    house(228, 100, 36, 28, "#b8a278", "#a84a30")
    for wx in (270, 300):
        cv.rect(wx, 84, 10, 12, "#9ab4bc")
        cv.rect(wx - 1, 96, 12, 2, "#5a3a22")
        cv.speckle(rng, 4, wx, 96, wx + 10, 97, ("#d8586a", "#e8c838"))
    # tree
    cv.rect(128, 78, 4, 22, "#4a3420")
    cv.disc(130, 70, 13, "#3a6a3a")
    cv.disc(125, 66, 8, "#4a8046")
    cv.disc(137, 74, 7, "#2e5a30")
    # memorial stone
    cv.ellipse(177, 108, 38, 5, "#6e6248", 0.45)
    cv.rect(155, 100, 44, 4, "#8e8e88")
    cv.rect(159, 96, 36, 4, "#a4a49c")
    cv.poly([(164, 96), (190, 96), (188, 58), (180, 54), (166, 58)], "#9a9c98")
    cv.poly([(164, 96), (170, 96), (170, 58), (166, 58)], "#b4b6b0")
    cv.poly([(184, 96), (190, 96), (188, 58), (184, 56)], "#767a78")
    for i in range(7):
        cv.rect(169, 64 + i * 4, 6 + (i * 5) % 9, 1, "#5a5e5c")
    cv.rect(173, 60, 3, 1, "#4a4e4c")
    cv.rect(176, 59, 1, 4, "#4a4e4c")
    for fx in range(150, 206, 4):
        cv.put(fx + rng.randint(-1, 1), 103 + rng.randint(0, 5), rng.choice(("#d8586a", "#e8c838", "#b06ac0", "#e0e0c0")))
    for fx in range(152, 204, 5):
        cv.rect(fx, 104, 1, 2, "#3a6a30")
    cv.poly([(199, 106), (236, 136), (200, 136), (192, 106)], "#6e6248", 0.35)
    cv.speckle(rng, 30, 140, 112, 220, 140, ("#d8586a", "#e8c838"))


def motor_pool(cv, rng):
    cv.bands(0, 96, "#141a22", "#2c3640", 8)
    for x in range(0, W, 8):  # corrugated wall
        cv.rect(x, 0, 1, 96, "#10151b", 0.6)
        cv.rect(x + 4, 0, 1, 96, "#3a4650", 0.35)
    for x in range(0, W, 59):  # roof trusses
        cv.rect(x, 0, 3, 96, "#0e1218")
    cv.rect(0, 14, W, 3, "#0e1218")
    for i in range(0, W, 24):
        cv.line(i, 14, i + 24, 3, "#0e1218")
    cv.rect(110, 28, 134, 68, "#1a2028")  # big hangar door
    for yy in range(28, 96, 8):
        cv.rect(110, yy, 134, 1, "#0e1218")
    cv.rect(110, 28, 134, 2, "#4a5560")
    cv.rect(300, 40, 40, 30, "#10151b")  # tool rack
    cv.rect(300, 40, 40, 2, "#6a5a3a")
    for i in range(9):
        tx = 303 + i * 4
        cv.rect(tx, 44, 1, 14 - (i % 3) * 3, "#9aa2aa")
        cv.rect(tx - 1, 44 + 14 - (i % 3) * 3, 3, 2, "#6a727a")
    cv.rect(300, 62, 40, 2, "#6a5a3a")
    for i in range(4):
        cv.rect(304 + i * 9, 54, 6, 6, "#5a4a2a")
    cv.rect(24, 34, 18, 18, "#10151b")  # wall clock
    cv.disc(33, 43, 7, "#c8c0a0", 0.85)
    cv.line(33, 43, 33, 38, "#14161a")
    cv.line(33, 43, 36, 45, "#14161a")
    # floor
    cv.bands(96, H, "#2e363c", "#161c22", 6)
    for i in range(-6, 14):
        cv.line(177 + (i - 4) * 14, 96, 177 + (i - 4) * 56, H, "#10151b", 0.7)
    for y in (108, 122, 138):
        cv.rect(0, y, W, 1, "#10151b", 0.5)
    # long shadows from the lamps, thrown across the floor
    cv.poly([(150, 128), (210, 128), (354, 140), (270, 142), (200, 134)], "#06080a", 0.55)
    # gantry on the left
    for gx in (54, 98):
        cv.rect(gx, 40, 3, 90, "#6a5a38")
        cv.rect(gx, 40, 1, 90, "#a08850")
    for gy in (40, 66, 92, 118):
        cv.rect(54, gy, 47, 3, "#6a5a38")
        cv.rect(54, gy, 47, 1, "#a08850")
    for gy in (40, 66, 92):
        cv.line(54, gy + 3, 98, gy + 26, "#4a3e26")
        cv.line(98, gy + 3, 54, gy + 26, "#4a3e26")
    cv.rect(98, 62, 22, 3, "#6a5a38")
    # walker, centre
    spr = sprite("vanguard", grey_pal(), key="grey")
    blit(cv, spr, 177 - 56 + 6, 127 - 100 + 2)
    # work lamps
    for lx, dirn in ((150, 1), (262, -1)):
        pass
    for lx in (136, 232):
        cv.rect(lx, 70, 2, 56, "#14161a")
        cv.line(lx + 1, 126, lx - 8, 140, "#14161a")
        cv.line(lx + 1, 126, lx + 10, 140, "#14161a")
        cv.rect(lx - 5, 62, 12, 9, "#2a2e32")
        cv.rect(lx - 3, 64, 8, 5, "#f0d890")
        cv.cone(lx + 1, 68, 5, 46, 126, "#e8d8a0", 0.09)
        cv.glow(lx + 1, 66, 28, "#f0d890", 0.45)
    # fuel drums, right
    for dx, dy, col in ((270, 124, "#5a6a3a"), (290, 126, "#7a4a2a"), (280, 112, "#5a6a3a"), (306, 128, "#5a6a3a")):
        cv.rect(dx - 8, dy - 18, 16, 20, col)
        cv.rect(dx - 8, dy - 18, 3, 20, lerp(col, "#e8e0c0", 0.25))
        cv.rect(dx + 5, dy - 18, 3, 20, shade(col, 0.6))
        for ry in (dy - 14, dy - 4):
            cv.rect(dx - 8, ry, 16, 1, shade(col, 0.55))
        cv.rect(dx - 8, dy - 18, 16, 1, "#20262a")
        cv.rect(dx - 8, dy + 1, 16, 1, "#10151b")
    cv.speckle(rng, 90, 0, 98, W, H, ("#3a444c", "#0c1014"))
    cv.rect(0, 0, W, H, "#0a1018", 0.0)


def records_room(cv, rng):
    cv.bands(0, 100, "#22221e", "#3a3a32", 8)
    for x in range(0, W, 30):
        cv.rect(x, 0, 1, 100, "#1a1a16", 0.6)
    cv.rect(0, 0, W, 10, "#161612")
    # soot stains, ceiling and walls
    for cx, cy, rx, ry in ((70, 10, 60, 30), (250, 6, 80, 36), (170, 30, 40, 40), (320, 60, 30, 40)):
        cv.ellipse(cx, cy, rx, ry, "#0a0908", 0.42)
        cv.ellipse(cx, cy, rx * 0.65, ry * 0.65, "#0a0908", 0.32)
    for x in (92, 214, 300):
        cv.poly([(x, 0), (x + 10, 0), (x + 22, 100), (x + 6, 100)], "#0a0908", 0.2)
    cv.bands(100, H, "#2e2a22", "#1a1814", 5)
    cv.rect(0, 100, W, 2, "#14120e")
    # pipe and collapsed beam
    cv.rect(0, 20, W, 5, "#30302a")
    cv.rect(0, 20, W, 1, "#5a5a50")
    cv.poly([(232, 0), (250, 0), (150, 60), (136, 52)], "#2a1c10")
    cv.line(234, 0, 138, 52, "#4a3420")
    cv.line(150, 60, 160, 66, "#1a120a")

    def cabinet(x, by, w, h, tilt=0, burnt=0.0, open_drawer=-1):
        col = "#4a5448"
        pts = [(x, by - h), (x + w, by - h), (x + w + tilt, by), (x + tilt, by)]
        cv.poly(pts, col)
        cv.poly([(x, by - h), (x + 3, by - h), (x + 3 + tilt, by), (x + tilt, by)], "#6a7466")
        cv.poly([(x + w - 3, by - h), (x + w, by - h), (x + w + tilt, by), (x + w - 3 + tilt, by)], "#2e362c")
        dh = h // 4
        for i in range(4):
            yy = by - h + i * dh
            cv.rect(x + 2 + int(tilt * (i + 0.5) / 4), yy, w - 4, 1, "#20261e")
            cv.rect(x + w // 2 - 3 + int(tilt * (i + 0.5) / 4), yy + dh // 2, 6, 1, "#a8a888")
            if i == open_drawer:
                cv.rect(x + 2, yy + 1, w - 4, dh - 1, "#12140f")
                cv.rect(x + 3, yy + 1, w - 6, 2, "#bcb496")
        if burnt:
            cv.poly([(x, by - h), (x + w, by - h), (x + w, by - h * (1 - burnt)), (x, by - h * (1 - burnt) + 4)], "#0c0a08", 0.8)
    cabinet(6, 112, 28, 62)
    cabinet(36, 112, 28, 54, tilt=0, burnt=0.45, open_drawer=1)
    cabinet(66, 106, 26, 40, burnt=0.7)
    cabinet(292, 112, 28, 62, burnt=0.4, open_drawer=2)
    cabinet(322, 112, 28, 56, tilt=5, burnt=0.55)
    # safe, centre
    cv.rect(142, 56, 70, 56, "#3a3c3a")
    cv.rect(142, 56, 70, 2, "#6a6c68")
    cv.rect(142, 56, 2, 56, "#5a5c58")
    cv.rect(146, 60, 62, 48, "#0c0c0a")
    cv.rect(150, 66, 54, 1, "#26261f")
    cv.rect(150, 80, 54, 1, "#26261f")
    for i in range(7):
        cv.rect(152 + i * 7, 68, 5, 12, "#b8b090")
        cv.rect(152 + i * 7, 68, 5, 1, "#d8d0b0")
    cv.rect(160, 84, 36, 20, "#a89c78")
    cv.rect(160, 84, 36, 1, "#c8bc98")
    cv.poly([(208, 56), (240, 66), (240, 120), (208, 112)], "#4a4c4a")  # door swung open
    cv.poly([(208, 56), (212, 58), (212, 112), (208, 112)], "#6a6c68")
    cv.disc(228, 90, 6, "#2a2c2a")
    cv.disc(228, 90, 3, "#8a8c88")
    cv.line(228, 90, 232, 86, "#c8c8c0")
    cv.rect(142, 110, 74, 3, "#20201c")
    # papers on the floor
    for _ in range(34):
        px, py = rng.randint(96, 258), rng.randint(114, 140)
        w = rng.randint(6, 12)
        cv.poly([(px, py), (px + w, py + rng.randint(-2, 2)), (px + w - 1, py + 4), (px - 1, py + 3)], rng.choice(("#b4ac90", "#a49c80", "#c4bca0")))
        cv.line(px + 1, py + 1, px + w - 3, py + 1, "#6a6450", 0.8)
    cv.speckle(rng, 60, 0, 102, W, H, ("#0c0b09", "#4a4438"))
    # the one lamp
    cv.rect(120, 25, 1, 14, "#0c0b09")
    cv.poly([(113, 46), (127, 46), (123, 38), (117, 38)], "#5a5a40")
    cv.rect(116, 45, 8, 2, "#ffd890")
    cv.cone(120, 46, 6, 70, 130, "#f0c060", 0.10)
    cv.glow(120, 48, 40, "#f0c060", 0.5, ry=32)
    # smoke wisps
    for sx in (60, 270):
        smoke(cv, rng, sx, 100, 7, "#1a1816", 1.0, 0.3, 1.4)


def office(cv, rng):
    cv.bands(0, 100, "#3a2c1a", "#5a4428", 8)
    for x in range(0, W, 22):
        cv.rect(x, 0, 1, 100, "#2a1e10", 0.7)
        cv.rect(x + 1, 0, 1, 100, "#7a5c36", 0.25)
    cv.rect(0, 62, W, 3, "#2a1e10")
    cv.rect(0, 65, W, 35, "#4a3822")
    cv.rect(0, 98, W, 3, "#241a0c")
    cv.bands(101, H, "#3a2c1c", "#241a10", 5)
    for i in range(-8, 16):
        cv.line(177 + (i - 4) * 12, 101, 177 + (i - 4) * 50, H, "#1a1208", 0.7)
    cv.poly([(40, 142), (110, 142), (140, 104), (90, 104)], "#2a3a28", 0.0)
    # rug
    cv.poly([(80, 142), (274, 142), (246, 114), (108, 114)], "#5a2a24")
    cv.poly([(88, 140), (266, 140), (242, 117), (112, 117)], "#6e3a2c")
    cv.poly([(98, 138), (256, 138), (236, 120), (118, 120)], "#4e2620", 0.6)
    # banner, centre, behind desk
    cv.rect(138, 4, 78, 3, "#6a5a2a")
    cv.rect(137, 3, 2, 3, "#c8a040")
    cv.rect(215, 3, 2, 3, "#c8a040")
    cv.poly([(144, 7), (210, 7), (210, 64), (177, 74), (144, 64)], "#5e6a34")
    cv.poly([(144, 7), (152, 7), (152, 66), (144, 64)], "#7a8644")
    cv.poly([(202, 7), (210, 7), (210, 64), (202, 68)], "#3e4822")
    cv.poly([(177, 20), (194, 42), (177, 56), (160, 42)], "#d8a838")
    cv.poly([(177, 26), (188, 42), (177, 50), (166, 42)], "#5e6a34")
    cv.rect(175, 30, 4, 18, "#d8a838")
    cv.rect(168, 38, 18, 3, "#d8a838")
    for fx in range(146, 210, 4):
        cv.rect(fx, 64 + int(abs(fx - 177) * 0.1 * -1) + 3, 1, 4, "#c8a040")
    # maps (left and right)
    for mx in (24, 262):
        cv.rect(mx - 3, 14, 70, 46, "#2a1e10")
        cv.rect(mx, 17, 64, 40, "#b4a676")
        cv.rect(mx, 17, 64, 40, "#6e6240", 0.2)
        cv.poly([(mx + 4, 40), (mx + 20, 24), (mx + 40, 28), (mx + 36, 50), (mx + 10, 54)], "#6c7a48")
        for gx in range(mx, mx + 64, 13):
            cv.rect(gx, 17, 1, 40, "#8c7e56")
        cv.rect(mx + 22, 30, 3, 3, "#c83a2a")
        cv.rect(mx + 44, 40, 3, 3, "#c83a2a")
        cv.line(mx + 23, 31, mx + 45, 41, "#a02a22", 0.8)
    # stove, right
    cv.rect(296, 70, 32, 36, "#22221f")
    cv.rect(296, 70, 32, 2, "#4a4a44")
    cv.rect(296, 70, 3, 36, "#3a3a34")
    cv.rect(304, 84, 16, 12, "#0e0b08")
    cv.rect(306, 86, 12, 8, "#e0782a")
    cv.rect(308, 90, 8, 4, "#f4c060")
    cv.rect(310, 20, 8, 50, "#22221f")
    cv.rect(310, 20, 2, 50, "#4a4a44")
    cv.rect(296, 106, 6, 6, "#14120e")
    cv.rect(322, 106, 6, 6, "#14120e")
    cv.glow(312, 92, 46, "#f09038", 0.42, ry=36)
    # desk
    cv.poly([(100, 100), (254, 100), (270, 118), (84, 118)], "#8a5e34")
    cv.poly([(106, 102), (248, 102), (260, 114), (94, 114)], "#a47444")
    cv.rect(84, 118, 186, 5, "#4a3018")
    cv.rect(84, 118, 186, 1, "#6a4a28")
    cv.rect(90, 123, 22, 19, "#38240f")
    cv.rect(242, 123, 22, 19, "#38240f")
    cv.rect(112, 123, 130, 6, "#2a1a0a")
    for dx in (96, 248):
        cv.rect(dx, 128, 8, 2, "#c8a040")
    # lamp + key on the desk
    cv.rect(134, 90, 2, 11, "#14120e")
    cv.poly([(126, 92), (144, 92), (140, 84), (130, 84)], "#3a5a38")
    cv.cone(135, 92, 5, 26, 112, "#f0c060", 0.10)
    cv.glow(177, 108, 60, "#f0c060", 0.4, ry=14)
    cv.glow(177, 107, 14, "#f8e0a0", 0.5, ry=5)
    cv.disc(171, 107, 3, "#8a6a18")
    cv.disc(171, 107, 2, "#f0d060")
    cv.put(171, 107, "#5a3a14")
    cv.rect(173, 106, 16, 2, "#f0d060")
    cv.rect(173, 108, 16, 1, "#8a6a18")
    cv.rect(183, 108, 2, 3, "#f0d060")
    cv.rect(187, 108, 2, 2, "#f0d060")
    cv.put(170, 105, "#fff0b0")
    # dumbbells + rack, left
    cv.rect(22, 108, 60, 3, "#2a2a28")
    cv.rect(24, 108, 3, 18, "#2a2a28")
    cv.rect(77, 108, 3, 18, "#2a2a28")
    for i, wgt in enumerate((5, 7)):
        by = 104 + i * 10
        cv.rect(30, by, 44, 3, "#6a6e72")
        cv.rect(30, by - 3, wgt, 9, "#3a3e42")
        cv.rect(30, by - 3, 1, 9, "#7a7e82")
        cv.rect(74 - wgt, by - 3, wgt, 9, "#3a3e42")
    cv.rect(22, 124, 60, 2, "#14120e", 0.4)
    # chair
    cv.rect(165, 78, 24, 22, "#241a10")
    cv.rect(166, 79, 22, 2, "#4a3420")
    cv.glow(60, 40, 40, "#f0c060", 0.15)


def field_camp(cv, rng):
    cv.bands(0, 86, "#3a2c4e", "#e0903c", 14)
    cv.disc(250, 80, 16, "#f0c070", 0.85)
    cv.bands(80, 90, "#e0903c", "#b05a30", 3)
    cv.ellipse(250, 82, 40, 10, "#f0a050", 0.3)
    for cx, cy, rw in ((70, 30, 40), (150, 18, 30), (300, 36, 36)):
        cv.ellipse(cx, cy, rw, 3, "#6a4a64", 0.7)
    cv.poly([(0, 90), (0, 76), (50, 72), (110, 80), (190, 74), (280, 82), (354, 72), (354, 90)], "#3a2a3a")
    # parked walkers, silhouettes against the sunset
    for name, x, by, num, den in (("goliath", 40, 92, 1, 2), ("vanguard", 214, 92, 1, 2), ("falke", 288, 92, 1, 2), ("donner", 118, 92, 1, 2)):
        spr = sprite(name, "coalition")
        px, w, h = spr
        blit(cv, spr, x, by - h * num // den, num, den, recolor=silhouette("#241a2a"))
    cv.bands(90, H, "#4a4a2c", "#1c2014", 6)
    cv.speckle(rng, 320, 0, 92, W, H, ("#2a3018", "#6a6a3c", "#14180e"))

    def tent(cx, by, w, h, col):
        cv.poly([(cx - w // 2, by), (cx + w // 2, by), (cx, by - h)], col)
        cv.poly([(cx + 2, by), (cx + w // 2, by), (cx, by - h)], shade(col, 0.62))
        cv.poly([(cx - w // 2, by), (cx - w // 2 + 4, by), (cx, by - h)], lerp(col, "#e8d8a8", 0.25))
        cv.poly([(cx - 5, by), (cx + 5, by), (cx, by - h * 0.55)], "#10120a")
        cv.rect(cx, int(by - h), 1, 1, "#2a2418")
        cv.line(cx - w // 2, by, cx - w // 2 - 8, by + 4, "#241e14")
        cv.line(cx + w // 2, by, cx + w // 2 + 8, by + 4, "#241e14")
    tent(70, 124, 62, 40, "#6a7440")
    tent(284, 122, 64, 42, "#8a8052")
    tent(44, 108, 40, 26, "#5a6438")
    tent(318, 106, 40, 26, "#6a6a44")
    # camp stove glowing in the middle
    cv.glow(177, 116, 70, "#f08a30", 0.48, ry=36)
    cv.rect(163, 122, 28, 3, "#14140e")
    cv.rect(166, 108, 22, 14, "#2a2a26")
    cv.rect(166, 108, 22, 2, "#5a5a50")
    cv.rect(170, 114, 14, 8, "#0e0a06")
    cv.rect(172, 116, 10, 6, "#e0782a")
    cv.rect(174, 118, 6, 4, "#f4c060")
    cv.rect(185, 100, 3, 8, "#2a2a26")
    cv.rect(168, 102, 12, 6, "#44443c")
    cv.rect(168, 102, 12, 1, "#7a7a6c")
    smoke(cv, rng, 187, 98, 7, "#3a3030", 1.0, 0.45, 0.9)
    for lx in (148, 206):
        cv.rect(lx, 124, 12, 5, "#3a2a18")
        cv.rect(lx, 124, 12, 1, "#6a4a28")
    cv.speckle(rng, 20, 160, 100, 200, 112, ("#f4a43a",))
    cv.poly([(150, 142), (205, 142), (190, 128), (166, 128)], "#f09038", 0.18)


def snow_pass(cv, rng):
    cv.bands(0, 80, "#56626e", "#a8b4be", 10)
    cv.poly([(0, 96), (0, 40), (34, 24), (60, 46), (84, 30), (130, 62), (150, 80), (150, 96)], "#6a7886")
    cv.poly([(354, 96), (354, 36), (320, 20), (290, 44), (262, 28), (222, 64), (204, 80), (204, 96)], "#6a7886")
    for (px, py) in ((34, 24), (84, 30), (320, 20), (262, 28)):
        cv.poly([(px - 10, py + 12), (px, py), (px + 10, py + 12), (px + 4, py + 8), (px, py + 14), (px - 4, py + 8)], "#c0cad4")
    cv.poly([(0, 110), (0, 70), (40, 62), (80, 78), (130, 96), (150, 104), (150, 110)], "#4e5c6a")
    cv.poly([(354, 110), (354, 66), (310, 58), (270, 76), (230, 96), (204, 104), (204, 110)], "#4e5c6a")
    cv.poly([(130, 96), (150, 82), (177, 78), (204, 82), (226, 96), (226, 106), (130, 106)], "#7a8896")
    # pines
    for tx, ty, s in ((12, 108, 1.2), (34, 112, 1.0), (60, 106, 0.8), (330, 110, 1.2), (306, 112, 1.0), (284, 104, 0.8)):
        for k in range(4):
            w = int((18 - k * 3) * s)
            cv.poly([(tx - w // 2, ty - k * int(9 * s)), (tx + w // 2, ty - k * int(9 * s)), (tx, ty - (k + 1) * int(11 * s))], "#1e2e2a")
        cv.rect(tx - 1, ty, 3, 5, "#1a1612")
    # snowfield
    cv.bands(104, H, "#a4b0bc", "#76828e", 6)
    cv.poly([(0, 142), (0, 120), (50, 112), (120, 118), (200, 112), (300, 120), (354, 114), (354, 142)], "#8c98a6", 0.5)
    cv.speckle(rng, 200, 0, 106, W, H, ("#c6d0d8", "#6a7684"))
    # the fallen walker, lying on its side: render without the far leg, rotate 90 degrees
    d = dict(chassis_mod.VANGUARD)
    d["legs"] = [chassis_mod.VANGUARD["legs"][1]]
    d["parts"] = [p for p in chassis_mod.VANGUARD["parts"] if p.get("leg") != 0]
    d["parts"] = [dict(p, leg=0) if p.get("leg") == 1 else p for p in d["parts"]]
    px, w, h = sprite(d, grey_pal(), key="fallen")
    th, sc = math.radians(160), 0.7
    ct, st = math.cos(th), math.sin(th)
    pcx, pcy = 176, 97

    def fwd(px_, py_):
        dx, dy = (px_ - w / 2) * sc, (py_ - h / 2) * sc
        return pcx + dx * ct - dy * st, pcy + dx * st + dy * ct
    cv.ellipse(182, 124, 58, 6, "#3e4a56", 0.6)
    cv.poly([(100, 128), (150, 122), (150, 128), (96, 134)], "#7a8692", 0.7)  # skid furrow
    for Y in range(0, H):
        for X in range(60, 300):
            rx, ry = X - pcx, Y - pcy
            sx = int(w / 2 + (rx * ct + ry * st) / sc)
            sy = int(h / 2 + (-rx * st + ry * ct) / sc)
            c = px.get((sx, sy))
            if c:
                cv.put(X, Y, c)
    # torn stump where the far leg should be (hip at sprite 42,57)
    sx, sy = fwd(42, 57)
    sx, sy = int(sx), int(sy)
    cv.poly([(sx - 5, sy - 4), (sx + 5, sy - 3), (sx + 6, sy + 4), (sx + 2, sy + 2), (sx - 1, sy + 6), (sx - 5, sy + 3)], "#14161a")
    cv.rect(sx - 3, sy - 2, 5, 3, "#8a4a1c")
    cv.glow(sx, sy, 14, "#f0a040", 0.55)
    for dx, dy in ((-7, -6), (-9, 1), (-4, 8), (-11, 5)):
        cv.put(sx + dx, sy + dy, "#f4d27a")
    ox, oy = 150, 60
    # the torn-off lower leg, lying in the snow to the right
    cv.poly([(222, 120), (250, 126), (249, 131), (221, 126)], "#6a6f78")
    cv.poly([(222, 120), (250, 126), (250, 127), (222, 121)], "#9aa0a8")
    cv.poly([(250, 123), (264, 128), (262, 134), (248, 131)], "#3c4048")
    cv.rect(219, 120, 4, 7, "#14161a")
    cv.rect(220, 122, 2, 3, "#8a4a1c")
    smoke(cv, rng, sx + 4, sy - 4, 6, "#4e5660", 1.0, 0.45, 1.0)
    snowfall(cv, rng, 420, 0.75)
    for _ in range(70):
        x, y = rng.randrange(0, W), rng.randrange(0, H)
        cv.line(x, y, x - 3, y + 3, "#c6d0d8", 0.6)


def causeway(cv, rng):
    cv.bands(0, 74, "#7c8aa0", "#e0b890", 12)
    cv.disc(250, 62, 10, "#f0d8a8", 0.75)
    cv.poly([(0, 78), (0, 60), (60, 54), (120, 62), (240, 58), (300, 64), (354, 56), (354, 78)], "#6a7686")
    # river bands both sides + mist
    cv.bands(74, H, "#8a9cac", "#2e3e4a", 8)
    for y in range(78, H, 3):
        for x in range(rng.randrange(0, 6), W, 9):
            cv.put(x, y, "#a4b4bc")
    for y0, a in ((70, 0.5), (84, 0.38), (100, 0.25)):
        cv.rect(0, y0, W, 8, "#b8c2c6", a)
    # fort at the end of the causeway
    cv.rect(110, 46, 134, 30, "#5a5e62")
    cv.rect(110, 46, 134, 2, "#8a8e90")
    for x in range(110, 244, 6):
        cv.rect(x, 42, 4, 4, "#5a5e62")
    for tx in (96, 230):
        cv.rect(tx, 28, 28, 50, "#50545a")
        cv.rect(tx, 28, 4, 50, "#767a7e")
        cv.rect(tx + 24, 28, 4, 50, "#3a3e44")
        for x in range(tx, tx + 28, 7):
            cv.rect(x, 24, 5, 4, "#50545a")
        cv.rect(tx + 11, 38, 6, 10, "#14161a")
    cv.poly([(160, 76), (160, 56), (168, 48), (186, 48), (194, 56), (194, 76)], "#14161a")
    cv.poly([(166, 76), (166, 58), (172, 52), (182, 52), (188, 58), (188, 76)], "#e0a050", 0.5)
    cv.rect(0, 74, W, 3, "#9aa6ae", 0.35)
    # causeway road, perspective
    cv.poly([(150, 76), (204, 76), (320, 142), (34, 142)], "#6e6a60")
    cv.poly([(150, 76), (204, 76), (260, 142), (94, 142)], "#8a8678")
    cv.poly([(150, 76), (154, 76), (110, 142), (94, 142)], "#a29c88")
    for i in range(1, 12):
        t = i / 12.0
        y = 76 + (142 - 76) * t * t
        wx = 27 + 26 * t * 4
        cv.rect(int(177 - 27 - 100 * t * t), int(y), int(54 + 200 * t * t), 1, "#5e5a50", 0.6)
    for i in range(0, 16):
        t = (i + 1) / 16.0
        y = int(76 + 66 * t * t)
        for s in (-1, 1):
            xs = 177 + s * (27 + 120 * t * t)
            cv.rect(int(xs) - (3 if s < 0 else 0), y - 3, 3, 3 + int(5 * t), "#3a3c3c")
    cv.line(150, 76, 34, 142, "#3a3c3c")
    cv.line(204, 76, 320, 142, "#3a3c3c")
    # puddles and shell craters on the road
    cv.ellipse(150, 118, 14, 3, "#5a6a76", 0.8)
    cv.ellipse(214, 108, 10, 2, "#5a6a76", 0.8)
    cv.speckle(rng, 120, 100, 80, 260, H, ("#5e5a50", "#aaa690"))
    # battered heavy walker striding toward the viewer
    walker_front(cv, 177, 136, 0.95, ("#a8aa8c", "#6a6e58", "#3a3e30"), trim="#a08a40", lens="#ffb060", damaged=True, rng=rng)
    smoke(cv, rng, 160, 74, 5, "#3a3834", 1.0, 0.4, 0.8)
    cv.rect(0, 118, W, 24, "#2e3e4a", 0.0)


def capital_street(cv, rng):
    cv.bands(0, 80, "#2e2420", "#a8643a", 10)
    cv.glow(177, 70, 90, "#f09040", 0.35, ry=30)
    for x in (150, 214, 90, 270):
        smoke(cv, rng, x, 76, 8, "#241c1a", 2.0, 0.55, 1.6)
    vx, vy = 177, 72
    # distant skyline
    cv.poly([(110, 100), (110, 70), (130, 66), (140, 78), (160, 60), (176, 62), (180, 50), (200, 54), (210, 70), (232, 64), (244, 100)], "#3a2a26")
    # road
    cv.bands(100, H, "#4a4036", "#2a241e", 5)
    cv.poly([(vx - 14, 96), (vx + 14, 96), (354, 142), (0, 142)], "#554a3e")
    cv.poly([(vx - 14, 96), (vx + 14, 96), (260, 142), (94, 142)], "#665a4a")
    for off in (-10, 10):  # tram rails
        cv.line(vx + off * 0.6, 96, vx + off * 14, 142, "#8a8478", 0.9)
    for i in range(0, 12):
        t = (i + 1) / 12.0
        y = int(96 + 46 * t * t)
        cv.rect(int(vx - 70 * t * t - 6), y, int(140 * t * t + 12), 1, "#3a3228", 0.8)
    # facades in perspective (left and right)
    for s in (-1, 1):
        xs = [0, 56, 100, 140] if s < 0 else [354, 298, 254, 214]
        tops = [8, 24, 44, 64]
        for i in range(3):
            xa, xb = xs[i], xs[i + 1]
            ta, tb = tops[i], tops[i + 1]
            ba, bb = 142 - i * 8, 96 + 0
            base_a = 142 if i == 0 else 100 + (2 - i) * 6
            ba = [150, 128, 112, 98][i]
            bb = [150, 128, 112, 98][i + 1]
            col = ("#4a3e3a", "#54483e", "#4a3e3a")[i]
            cv.poly([(xa, ta), (xb, tb), (xb, bb), (xa, ba)], col)
            cv.poly([(xa, ta), (xb, tb), (xb, tb + 4), (xa, ta + 4)], shade(col, 1.3))
            # window grid following the perspective
            n = 5 - i
            for c in range(n):
                f0 = (c + 0.25) / n
                f1 = (c + 0.7) / n
                x0 = xa + (xb - xa) * f0
                x1 = xa + (xb - xa) * f1
                for r in range(7 - i):
                    g0 = (r + 0.8) / (8.0 - i)
                    g1 = (r + 1.3) / (8.0 - i)
                    yt0 = ta + (tb - ta) * f0 + (ba - ta + (bb - ba) * f0 - (tb - ta) * f0 + (ta - ta)) * 0
                    top0 = ta + (tb - ta) * f0
                    bot0 = ba + (bb - ba) * f0
                    top1 = ta + (tb - ta) * f1
                    bot1 = ba + (bb - ba) * f1
                    ya0 = top0 + (bot0 - top0) * g0 * 0.9
                    ya1 = top1 + (bot1 - top1) * g0 * 0.9
                    yb0 = top0 + (bot0 - top0) * g1 * 0.9
                    yb1 = top1 + (bot1 - top1) * g1 * 0.9
                    lit = rng.random() < 0.14
                    cv.poly([(x0, ya0), (x1, ya1), (x1, yb1), (x0, yb0)], "#d88a3a" if lit else "#17110f")
            for k in range(2):  # pilasters
                fx = xa + (xb - xa) * k
                cv.line(fx, ta if k == 0 else tb, fx, ba if k == 0 else bb, "#2a2220")
        # torn crimson banners
        bx = xs[1] + (xs[0] - xs[1]) * 0.0 + s * -22
        for (bxx, byy, bl) in ((xs[0] + s * 18 * -1 + (-s * 0), 22, 44), (xs[1] + (xs[2] - xs[1]) * 0.35, 44, 30)):
            wd = 9
            pts = [(bxx - wd, byy), (bxx + wd, byy), (bxx + wd, byy + bl), (bxx + 3, byy + bl - 8), (bxx, byy + bl + 4), (bxx - 4, byy + bl - 6), (bxx - wd, byy + bl - 2)]
            cv.poly(pts, "#8a1c2a")
            cv.poly([(bxx - wd, byy), (bxx - wd + 3, byy), (bxx - wd + 3, byy + bl - 2), (bxx - wd, byy + bl - 2)], "#b02a3a")
            cv.rect(int(bxx) - 2, byy + 8, 5, 5, "#2a1a18")
    # tram wires and poles
    for sx in (-1, 1):
        px = 177 + sx * 58
        cv.rect(px, 50, 2, 70, "#1a1412")
        cv.rect(px - 10 * sx, 52, 12, 1, "#1a1412")
    for dy in (0, 5):
        cv.line(0, 28 + dy, 177, 40 + dy, "#14100e", 0.9)
        cv.line(177, 40 + dy, 354, 28 + dy, "#14100e", 0.9)
    cv.line(60, 56, 177, 66, "#14100e", 0.8)
    cv.line(177, 66, 300, 56, "#14100e", 0.8)
    # rubble piles
    for rx, ry, rw in ((120, 128, 30), (240, 126, 34), (180, 112, 22), (160, 136, 24)):
        for _ in range(rw):
            cx = rx + rng.randint(-rw, rw)
            cy = ry + rng.randint(-rw // 4, 3)
            cv.rect(cx, cy, rng.randint(2, 5), rng.randint(2, 4), rng.choice(("#2a221e", "#5a4e42", "#3a3028", "#74685a")))
    cv.line(255, 80, 262, 110, "#2a221e")
    cv.line(262, 110, 250, 112, "#2a221e")
    cv.rect(228, 118, 1, 24, "#1a1412")
    cv.speckle(rng, 60, 0, 0, W, 90, ("#f4a43a",))


def throne_gate(cv, rng):
    cv.bands(0, 90, "#58587c", "#e8a47a", 14)
    cv.glow(177, 70, 100, "#f8c890", 0.4, ry=40)
    for cx, cy, rw in ((60, 22, 44), (290, 30, 50), (190, 12, 30)):
        cv.ellipse(cx, cy, rw, 4, "#a08090", 0.55)
    # fortress wall and flanking towers
    cv.rect(0, 62, W, 44, "#4a4048")
    for x in range(0, W, 9):
        cv.rect(x, 56, 6, 6, "#4a4048")
    for tx, w in ((6, 52), (296, 52)):
        cv.rect(tx, 20, w, 86, "#40363e")
        cv.rect(tx, 20, 5, 86, "#5e5260")
        for x in range(tx, tx + w, 10):
            cv.rect(x, 12, 7, 8, "#40363e")
        for wy in (36, 58):
            cv.rect(tx + 20, wy, 8, 14, "#14101a")
    # gate arch (centre), pale dawn through it
    cv.poly([(124, 106), (124, 52), (134, 36), (177, 28), (220, 36), (230, 52), (230, 106)], "#34303a")
    cv.poly([(134, 106), (134, 54), (142, 42), (177, 36), (212, 42), (220, 54), (220, 106)], "#e0a888")
    cv.rect(134, 70, 86, 36, "#c88a70", 0.5)
    cv.poly([(134, 54), (142, 42), (150, 40), (150, 60), (142, 106), (134, 106)], "#3a323a")  # broken door leaf
    cv.poly([(220, 54), (212, 42), (204, 40), (204, 56), (214, 90), (220, 100)], "#3a323a")
    cv.line(150, 40, 150, 100, "#5a4a52")
    for gx in range(140, 216, 8):
        cv.rect(gx, 98, 3, 8, "#1a1618")
    cv.rect(170, 22, 14, 14, "#8a1c2a")
    cv.rect(173, 25, 8, 8, "#c8a040")
    # banners on the towers
    for bx in (36, 322):
        cv.poly([(bx - 6, 24), (bx + 6, 24), (bx + 6, 66), (bx, 60), (bx - 6, 66)], "#8a1c2a")
    for sx in (60, 292):
        smoke(cv, rng, sx, 60, 7, "#4a4048", 1.0, 0.4, 1.2)
    # courtyard
    cv.bands(106, H, "#6a5a58", "#2e2628", 6)
    for y in range(108, H, 5):
        off = (y // 5) % 2 * 7
        for x in range(-off, W, 14):
            cv.put(x, y, "#3a2e30")
        cv.rect(0, y, W, 1, "#3a2e30", 0.3)
    cv.speckle(rng, 200, 0, 108, W, H, ("#8a7a76", "#2a2024"))
    # long shadows toward the viewer (sun is behind the gate)
    cv.poly([(130, 136), (176, 136), (200, 142), (120, 142)], "#14101a", 0.4)
    # grey and black walkers side by side
    walker_front(cv, 138, 136, 0.85, ("#b0b4bc", "#767c88", "#464a54"), trim="#c8b890", lens="#ffe090", damaged=True, rng=rng)
    walker_front(cv, 218, 138, 0.9, ("#585c68", "#2a2c34", "#121318"), trim="#c01c30", lens="#ff3040", damaged=False)
    cv.glow(177, 70, 40, "#fff0c0", 0.0)
    cv.rect(0, 100, W, 6, "#e8a47a", 0.06)


def parade_court(cv, rng):
    cv.bands(0, 80, "#1c1410", "#7a3a1c", 12)
    cv.glow(177, 70, 110, "#e8782a", 0.4, ry=50)
    for x in (20, 90, 260, 330):
        smoke(cv, rng, x, 90, 10, "#150f0d", 2.0, 0.6, 2.0)
    # fortress back wall, towers, flagpoles
    cv.rect(0, 62, W, 36, "#2c2220")
    for x in range(0, W, 10):
        cv.rect(x, 56, 6, 6, "#2c2220")
    for tx in (30, 150, 270):
        cv.rect(tx, 28, 40, 70, "#241a1a")
        cv.rect(tx, 28, 4, 70, "#3c2e2c")
        for x in range(tx, tx + 40, 10):
            cv.rect(x, 22, 7, 6, "#241a1a")
        cv.rect(tx + 16, 44, 7, 12, "#0c0808")
    cv.rect(0, 96, W, 2, "#5a3a2a", 0.5)
    for fx in (100, 254):
        cv.rect(fx, 40, 2, 62, "#14100e")
        cv.poly([(fx + 2, 42), (fx + 16, 46), (fx + 12, 52), (fx + 2, 56)], "#6a1420")
    # parade ground in perspective
    cv.bands(98, H, "#5a4038", "#221816", 8)
    for i in range(-10, 12):
        cv.line(177 + (i - 0.5) * 10, 98, 177 + (i - 0.5) * 70, H, "#2a1e1c", 0.7)
    for k in range(1, 7):
        y = int(98 + 44 * (k / 6.0) ** 1.8)
        cv.rect(0, y, W, 1, "#2a1e1c", 0.7)
    cv.speckle(rng, 240, 0, 100, W, H, ("#74564a", "#1a1210"))
    # burning wreck of the super-heavy walker (Ragnarok sprite, scorched, listing)
    spr = sprite("ragnarok", "syndikat")
    cv.glow(177, 96, 84, "#ff7a2a", 0.3, ry=48)
    for fx, fy, fw, fh in ((168, 52, 16, 26), (196, 54, 18, 30), (138, 56, 10, 20)):
        flame(cv, rng, fx, fy + 10, fw, fh, glow=False)  # behind the hull
    blit(cv, spr, 177 - 57, 134 - 96, 3, 4, recolor=soot(0.62))
    for hx, hy, hr in ((150, 92, 5), (204, 98, 5), (178, 84, 4), (222, 90, 3)):
        cv.disc(hx, hy, hr, "#0a0605")
        flame(cv, rng, hx, hy + 1, hr * 2, hr * 3 + 4, glow=False)
    flame(cv, rng, 168, 58, 22, 34)
    flame(cv, rng, 196, 62, 24, 34)
    flame(cv, rng, 140, 66, 12, 22)
    flame(cv, rng, 160, 126, 28, 18)
    flame(cv, rng, 214, 124, 22, 14)
    for sx, sy in ((150, 40), (190, 36), (216, 50), (136, 46)):
        smoke(cv, rng, sx, sy, 10, "#120d0b", 2.5, 0.6, 2.0)
    embers(cv, rng, 140, 100, 0, 260, 110)
    # the smaller black walker, dark and still, at the right
    blit(cv, sprite("kommandant", "blackclaw"), 262, 140 - 53, 1, 2, recolor=soot(0.75))
    cv.disc(262 + 33, 140 - 53 + 11, 1, "#ff3a34")
    cv.glow(262 + 33, 140 - 53 + 11, 8, "#ff3030", 0.45)
    cv.poly([(262, 142), (320, 142), (354, 142), (300, 138)], "#08060a", 0.4)
    cv.ellipse(150, 140, 70, 5, "#d8681a", 0.18)
    # wreckage on the ground
    for _ in range(40):
        cv.rect(rng.randint(100, 260), rng.randint(130, 141), rng.randint(2, 6), rng.randint(1, 3), rng.choice(("#1a1210", "#3a2a24", "#5a4034")))


SCENES = {
    "briefing_room": briefing_room,
    "village_fire": village_fire,
    "memorial": memorial,
    "motor_pool": motor_pool,
    "records_room": records_room,
    "office": office,
    "field_camp": field_camp,
    "snow_pass": snow_pass,
    "causeway": causeway,
    "capital_street": capital_street,
    "throne_gate": throne_gate,
    "parade_court": parade_court,
}


def scene_rows(name):
    cv = Cv()
    seed = sum(ord(ch) * (i + 1) for i, ch in enumerate(name))
    SCENES[name](cv, random.Random(seed))
    return cv.finish()


def write_backdrops(out):
    d = os.path.join(out, "backdrops")
    os.makedirs(d, exist_ok=True)
    for name in SCENES:
        png.write_png(os.path.join(d, name + ".png"), W, H, scene_rows(name))
