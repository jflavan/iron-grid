"""Terrain backdrops for the battle area (360x152), one per GridTileData.TerrainType.

Same style as the approved Open Plain: quantized dithered sky bands, layered silhouettes,
dithered ground bands and a few props. Deterministic (seeded random.Random).
"""
import math
import os
import random

import png
from raster import hex_rgb

W, H = 360, 152


class Canvas:
    def __init__(self):
        self.px = [[(0, 0, 0)] * W for _ in range(H)]

    def set(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        c = _c(c)
        for yy in range(max(0, y), min(H, y + h)):
            row = self.px[yy]
            for xx in range(max(0, x), min(W, x + w)):
                row[xx] = c

    def disc(self, cx, cy, r, c):
        c = _c(c)
        for dy in range(-r, r + 1):
            w = int(round(math.sqrt(max(0, r * r - dy * dy))))
            self.rect(cx - w, cy + dy, w * 2, 1, c)

    def ellipse(self, cx, cy, rw, rh, c_top, c_bot=None):
        for dy in range(-rh, rh + 1):
            w = int(round(rw * math.sqrt(max(0.0, 1 - (dy * dy) / float(rh * rh)))))
            self.rect(cx - w, cy + dy, w * 2, 1, c_top if dy < 0 or c_bot is None else c_bot)

    def bands(self, y0, y1, c0, c1, steps):
        c0, c1 = _c(c0), _c(c1)
        hh = y1 - y0
        for y in range(y0, y1):
            f = (y - y0) / hh * steps
            b = int(f)
            fr = f - b
            for x in range(W):
                nx = fr > 0.75 and ((x + y) & 1)
                self.px[y][x] = _lerp(c0, c1, min(1.0, (b + (1 if nx else 0)) / steps))

    def ridge(self, fn, bottom, c):
        c = _c(c)
        for x in range(W):
            top = int(round(fn(x)))
            for y in range(max(0, top), min(H, bottom)):
                self.px[y][x] = c

    def rows(self):
        return [[p + (255,) for p in row] for row in self.px]


def _c(c):
    return hex_rgb(c) if isinstance(c, str) else c


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _smoke(cv, r, sx, sy):
    for k in range(9):
        cv.disc(sx + k * 3 + int(r.random() * 3), sy - k * 6, int(3 + k * 0.8), "#5e5a54" if k % 2 else "#6c675f")


def _crater(cv, cx, cy, rw):
    rh = max(1, int(round(rw / 3.2)))
    cv.ellipse(cx, cy, rw, rh, "#2f2a1c", "#3d3624")
    cv.rect(cx - rw + 2, cy + rh, rw * 2 - 4, 1, "#9a9a60")


def _speckle(cv, r, n, y0, y1, cols):
    for _ in range(n):
        x = int(r.random() * W)
        y = y0 + int((r.random() ** 0.7) * (y1 - y0))
        cv.set(x, y, _c(cols[0] if r.random() < 0.5 else cols[1]))


def plain(cv, r):
    cv.bands(0, 82, "#3c4858", "#d6aa70", 10)
    cv.disc(180, 36, 9, "#f4dcaa")
    _smoke(cv, r, 120, 60)
    _smoke(cv, r, 250, 64)
    cv.ridge(lambda x: 66 + 5 * math.sin(x * 0.021) + 3 * math.sin(x * 0.07 + 1), 80, "#626a5a")
    cv.ridge(lambda x: 74 + 3 * math.sin(x * 0.035 + 2) + 2 * math.sin(x * 0.11), 84, "#4b5640")
    cv.bands(82, 152, "#7c8648", "#465426", 6)
    for x in range(4, W, 16):
        cv.rect(x, 86, 1, 5, "#2e3022")
    cv.rect(0, 87, W, 1, "#55583e")
    _speckle(cv, r, 420, 88, 150, ("#3c4820", "#8e9854"))
    _crater(cv, 180, 146, 16)
    _crater(cv, 178, 104, 9)


def road(cv, r):
    cv.bands(0, 82, "#4a5060", "#beb6a4", 9)
    cv.ridge(lambda x: 70 + 4 * math.sin(x * 0.018 + 0.5), 82, "#666a60")
    for x in range(10, W, 46):  # telegraph poles
        cv.rect(x, 62, 1, 20, "#33352c")
        cv.rect(x - 3, 64, 7, 1, "#33352c")
    cv.rect(0, 65, W, 1, "#4a4c42")
    cv.bands(82, 152, "#808a50", "#4e5a2c", 5)
    _speckle(cv, r, 260, 84, 150, ("#3c4820", "#8e9854"))
    # paved transit road receding across the field
    cv.rect(0, 108, W, 30, "#5a5a56")
    cv.rect(0, 108, W, 2, "#7a7a72")
    cv.rect(0, 136, W, 2, "#3a3a36")
    for x in range(0, W, 2):
        for y in range(110, 136):
            if (x * 7 + y * 13) % 29 == 0:
                cv.set(x, y, _c("#4a4a46"))
    for x in range(6, W, 28):
        cv.rect(x, 122, 14, 2, "#d8b040")
    for x in (40, 300):  # tank-trap hedgehogs
        cv.rect(x, 92, 7, 1, "#2a2a26")
        cv.rect(x + 3, 88, 1, 6, "#2a2a26")
        cv.rect(x + 1, 90, 5, 1, "#3c3c36")


def river(cv, r):
    cv.bands(0, 82, "#405870", "#d0c098", 9)
    cv.ridge(lambda x: 64 + 6 * math.sin(x * 0.02 + 1) + 2 * math.sin(x * 0.09), 80, "#5a6458")
    cv.ridge(lambda x: 74 + 3 * math.sin(x * 0.03), 84, "#46523c")
    cv.bands(82, 100, "#76804a", "#5c6834", 3)
    cv.bands(100, 140, "#3c6478", "#1e3a4a", 6)
    for _ in range(90):  # ripples
        x = int(r.random() * (W - 8))
        y = 102 + int(r.random() * 36)
        cv.rect(x, y, 3 + int(r.random() * 6), 1, "#8cb4c4" if r.random() < 0.6 else "#5c8ca0")
    cv.rect(0, 100, W, 1, "#b0c8c8")
    cv.bands(140, 152, "#4a4030", "#3a3022", 2)
    for x in range(0, W, 7):  # reeds on the far bank
        if r.random() < 0.6:
            h = 3 + int(r.random() * 5)
            cv.rect(x, 100 - h, 1, h, "#3e4a26")


def forest(cv, r):
    cv.bands(0, 84, "#2c3038", "#927a5c", 9)
    for layer, (base, col, step) in enumerate(((58, "#323a2c", 9), (66, "#262e22", 12))):
        for x0 in range(-6, W + 6, step):
            h = 14 + int(r.random() * 12) - layer * 2
            cx = x0 + int(r.random() * 4)
            for k in range(h):
                w = int(k * 0.45) + 1
                cv.rect(cx - w, base - h + k + layer * 4, w * 2 + 1, 1, col)
    cv.rect(0, 69, W, 15, "#262e22")
    cv.bands(84, 152, "#5a4c34", "#3a3022", 5)
    _speckle(cv, r, 300, 86, 150, ("#2e261a", "#6e5e40"))
    for y, x0, x1 in ((98, 0, W), (128, 0, W)):  # trench lines with sandbags
        cv.rect(x0, y, x1 - x0, 4, "#1e1810")
        for x in range(x0, x1, 5):
            cv.rect(x, y - 2, 4, 2, "#8a7a54")
            cv.set(x + 3, y - 1, _c("#5a4c34"))
    for x in range(8, W, 22):  # stakes + wire
        cv.rect(x, 86, 1, 7, "#3a2c1c")
    cv.rect(0, 88, W, 1, "#6a6458")


def city(cv, r):
    cv.bands(0, 84, "#3a3640", "#b48462", 9)
    _smoke(cv, r, 70, 54)
    _smoke(cv, r, 280, 50)
    x = 0
    while x < W:  # ruined skyline
        w = 18 + int(r.random() * 26)
        h = 22 + int(r.random() * 38)
        top = 84 - h
        cv.rect(x, top, w, h, "#2c2a2e")
        if r.random() < 0.5:  # broken roofline
            for k in range(0, w, 3):
                cv.rect(x + k, top - int(r.random() * 5), 3, 5, "#2c2a2e")
        for wy in range(top + 4, 80, 7):
            for wx in range(x + 3, x + w - 3, 6):
                c = "#e0a040" if r.random() < 0.12 else ("#1a181c" if r.random() < 0.7 else "#3c3a40")
                cv.rect(wx, wy, 2, 3, c)
        x += w + int(r.random() * 6)
    cv.bands(84, 152, "#6a6660", "#3e3c38", 5)
    for y in range(90, 152, 6):  # cobbles
        off = 3 if (y // 6) % 2 else 0
        for xx in range(off, W, 8):
            cv.set(xx, y, _c("#4a4844"))
    for cx, cy, rw in ((60, 100, 18), (300, 96, 14), (190, 146, 20)):  # rubble piles
        cv.ellipse(cx, cy, rw, max(2, rw // 4), "#5a5650", "#46423e")
        for _ in range(12):
            cv.rect(cx - rw + int(r.random() * 2 * rw), cy - 2 + int(r.random() * 3), 2, 2, "#7a766e")


def mountain(cv, r):
    cv.bands(0, 90, "#283860", "#a8b8d0", 9)

    def peaks(x, base, amp, f, ph):
        return base - amp * abs(math.sin(x * f + ph)) - 6 * math.sin(x * f * 3.1 + ph)

    cv.ridge(lambda x: peaks(x, 74, 40, 0.012, 0.6), 96, "#6a7088")
    for x in range(W):  # snow caps
        top = int(round(peaks(x, 74, 40, 0.012, 0.6)))
        for y in range(top, min(top + 8, 96)):
            if y < 50:
                cv.set(x, y, _c("#e8eef4"))
    cv.ridge(lambda x: peaks(x, 88, 18, 0.02, 2.0), 100, "#4e5262")
    cv.bands(96, 152, "#7a7064", "#4a4238", 5)
    _speckle(cv, r, 260, 98, 150, ("#3a342c", "#9a9080"))
    for cx, cy, rw in ((40, 112, 12), (320, 104, 9), (200, 144, 16), (110, 136, 7)):  # boulders
        cv.ellipse(cx, cy, rw, max(2, rw // 2), "#8a8478", "#5a544a")
        cv.rect(cx - rw // 2, cy - rw // 3, rw // 2, 1, "#b0aa9c")
    for x0 in (80, 250):  # cracks
        y = 120
        x = x0
        for _ in range(14):
            cv.set(x, y, _c("#2e2a24"))
            x += 1
            y += 1 if r.random() < 0.4 else 0


TERRAINS = {"plain": plain, "road": road, "river": river, "forest": forest, "city": city, "mountain": mountain}


def write_backdrops(out):
    os.makedirs(os.path.join(out, "backdrops"), exist_ok=True)
    for i, (name, fn) in enumerate(TERRAINS.items()):
        cv = Canvas()
        fn(cv, random.Random(7 + i))
        png.write_png(os.path.join(out, "backdrops", name + ".png"), W, H, cv.rows())
