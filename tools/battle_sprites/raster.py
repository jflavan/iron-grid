"""Part rasterizer: shaded blocks/circles/polygons -> palette-keyed pixel buffer -> RGBA.

Ported from the approved mockup's buildSprite(): per-part edge shading lit from the
upper-left, dithered lower shadow, bevelled panel lines, rivets, then a 1px outline.
Pixels are stored as palette keys ((key, tone) or "OUT") so one raster serves both factions.
"""
import math

OUTLINE = "OUT"


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


SHARED = {
    "metal": ["#9aa0a8", "#5d636b", "#33373d"],
    "dark": ["#56594e", "#33362e", "#1f211c"],
}
FACTIONS = {
    "coalition": {"hull": ["#b4c46a", "#6f7f3c", "#434d22"], "trim": ["#f6cc6a", "#e0a030", "#9a6a18"], "glow": "#ffe070"},
    "syndikat": {"hull": ["#d4604c", "#8e2a26", "#541613"], "trim": ["#a8aeb6", "#6d737c", "#3e4248"], "glow": "#ff5040"},
}
OUTLINE_HEX = "#16120e"
SPECULAR_HEX = "#f0f0e8"


def palette_for(faction):
    f = FACTIONS[faction]
    pal = {
        "hull": f["hull"],
        "trim": f["trim"],
        "glow": [f["glow"]] * 3,
        "rear": [f["hull"][1], f["hull"][2], "#262a18"],
        "metal": SHARED["metal"],
        "dark": SHARED["dark"],
        "brass": ["#f0c060", "#d8a040", "#8a5a20"],
        "steam": ["#e8ecee", "#c4cacc", "#8e9496"],
        "lens": ["#d8f0ff", "#68a8d0", "#284860"],
    }
    return {k: [hex_rgb(c) for c in v] for k, v in pal.items()}


def _inside_fn(part):
    if "r" in part:
        rx, ry, rw, rh = part["r"]
        return lambda x, y: rx <= x < rx + rw and ry <= y < ry + rh
    if "c" in part:
        cx, cy, r = part["c"]
        r2 = r * r
        return lambda x, y: (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r2
    pts = part["p"]

    def inside(x, y):
        X, Y = x + 0.5, y + 0.5
        ins = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > Y) != (yj > Y) and X < (xj - xi) * (Y - yi) / (yj - yi) + xi:
                ins = not ins
            j = i
        return ins

    return inside


def _query_box(part, w, h):
    if "r" in part:
        x0, y0 = part["r"][0], part["r"][1]
        x1, y1 = x0 + part["r"][2], y0 + part["r"][3]
    elif "c" in part:
        cx, cy, r = part["c"]
        x0, y0, x1, y1 = cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1
    else:
        xs = [p[0] for p in part["p"]]
        ys = [p[1] for p in part["p"]]
        x0, y0, x1, y1 = min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1
    return (max(0, math.floor(x0)), max(0, math.floor(y0)), min(w - 1, math.ceil(x1)), min(h - 1, math.ceil(y1)))


def render(w, h, parts):
    """Rasterize parts in order. Returns a flat list of palette keys (None = transparent)."""
    px = [None] * (w * h)
    for part in parts:
        key = part["k"]
        inside = _inside_fn(part)
        qx0, qy0, qx1, qy1 = _query_box(part, w, h)
        mask = set()
        for y in range(qy0, qy1 + 1):
            for x in range(qx0, qx1 + 1):
                if inside(x, y):
                    mask.add((x, y))
        if not mask:
            continue
        bx0 = min(p[0] for p in mask)
        bx1 = max(p[0] for p in mask)
        by0 = min(p[1] for p in mask)
        by1 = max(p[1] for p in mask)
        ph = by1 - by0 + 1

        def m(x, y):
            return (x, y) in mask

        for (x, y) in mask:
            tone = 1
            fy = (y - by0) / ph
            if fy > 0.62 and (x + y) & 1:
                tone = 2
            if fy > 0.82:
                tone = 2
            if not m(x + 1, y):
                tone = 2
            if not m(x, y + 1) or not m(x, y + 2):
                tone = 2
            if not m(x - 1, y):
                tone = 0
            if not m(x, y - 1):
                tone = 0
            if "c" in part:
                cx, cy, r = part["c"]
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                tone = 0 if dx + dy < -r * 0.5 else (2 if dx + dy > r * 0.4 else 1)
                if round(dx) == -round(r * 0.4) and round(dy) == -round(r * 0.4) and r >= 3:
                    px[y * w + x] = "SPEC"
                    continue
            if 0 <= x < w and 0 <= y < h:
                px[y * w + x] = (key, tone)
        for o in part.get("pv", []):
            x = bx0 + o
            for y in range(by0 + 2, by1 - 1):
                if m(x, y) and m(x, y - 1) and m(x, y + 1):
                    px[y * w + x] = (key, 2)
                    if m(x + 1, y):
                        px[y * w + x + 1] = (key, 0)
        for o in part.get("ph", []):
            y = by0 + o
            for x in range(bx0 + 2, bx1 - 1):
                if m(x, y) and m(x - 1, y) and m(x + 1, y):
                    px[y * w + x] = (key, 2)
                    if m(x, y + 1):
                        px[(y + 1) * w + x] = (key, 0)
        if part.get("rivet"):
            for ry in (by0 + 3, by1 - 4):
                for x in range(bx0 + 3, bx1 - 2, 6):
                    if m(x, ry) and m(x + 1, ry + 1) and m(x - 1, ry) and m(x + 2, ry):
                        px[ry * w + x] = (key, 0)
                        px[(ry + 1) * w + x + 1] = (key, 2)
    out = list(px)
    for y in range(h):
        for x in range(w):
            if px[y * w + x] is not None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                X, Y = x + dx, y + dy
                if 0 <= X < w and 0 <= Y < h and px[Y * w + X] is not None:
                    out[y * w + x] = OUTLINE
                    break
    return out


def colorize(buf, w, h, pal):
    outline = hex_rgb(OUTLINE_HEX) + (255,)
    spec = hex_rgb(SPECULAR_HEX) + (255,)
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            v = buf[y * w + x]
            if v is None:
                row.append((0, 0, 0, 0))
            elif v == OUTLINE:
                row.append(outline)
            elif v == "SPEC":
                row.append(spec)
            else:
                row.append(pal[v[0]][v[1]] + (255,))
        rows.append(row)
    return rows


def hstack(frames, w, h):
    """frames: list of row-lists (each h x w) -> one sheet row-list (h x w*n)."""
    return [sum((f[y] for f in frames), []) for y in range(h)]
