"""Two-bone leg IK and per-pose part assembly.

Feet/ankles stay planted; hips move with the body offset; each frame re-solves the knee so
thighs rotate, knees push forward (toward +x, the facing direction) and shins tilt.
"""
import math


def dist(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def _norm(v):
    l = math.hypot(v[0], v[1]) or 1.0
    return (v[0] / l, v[1] / l)


def _perp(v):
    return (-v[1], v[0])


def solve_knee(hip, ankle, lt, ls, forward=1):
    d0 = (ankle[0] - hip[0], ankle[1] - hip[1])
    d = min(math.hypot(*d0), lt + ls - 0.01)
    u = _norm(d0)
    a = (lt * lt - ls * ls + d * d) / (2 * d)
    hh = math.sqrt(max(0.0, lt * lt - a * a))
    p = (hip[0] + u[0] * a, hip[1] + u[1] * a)
    n = _perp(u)
    k1 = (p[0] + n[0] * hh, p[1] + n[1] * hh)
    k2 = (p[0] - n[0] * hh, p[1] - n[1] * hh)
    if forward > 0:
        return k1 if k1[0] > k2[0] else k2
    return k1 if k1[0] < k2[0] else k2


def bone(p1, p2, w1, w2, ext):
    u = _norm((p2[0] - p1[0], p2[1] - p1[1]))
    n = _perp(u)
    a = (p1[0] - u[0] * ext, p1[1] - u[1] * ext)
    b = (p2[0] + u[0] * ext, p2[1] + u[1] * ext)
    return [
        [a[0] + n[0] * w1, a[1] + n[1] * w1],
        [b[0] + n[0] * w2, b[1] + n[1] * w2],
        [b[0] - n[0] * w2, b[1] - n[1] * w2],
        [a[0] - n[0] * w1, a[1] - n[1] * w1],
    ]


def leg_parts(leg, off):
    hip = (leg["hip"][0] + off[0], leg["hip"][1] + off[1])
    lt = dist(leg["hip"], leg["knee"])
    ls = dist(leg["knee"], leg["ankle"])
    ankle = tuple(leg["ankle"])
    knee = solve_knee(hip, ankle, lt, ls, leg.get("forward", 1))
    out = [{"p": leg["foot"], "k": "dark"}]
    if leg.get("toe"):
        out.append({"r": leg["toe"], "k": "metal"})
    out.append({"p": bone(knee, ankle, leg["sw"], leg["sw"] + 1, 1), "k": leg["k"]})
    out.append({"c": [ankle[0], ankle[1] - 1, 3], "k": "dark"})
    out.append({"p": bone(hip, knee, leg["tw"], leg["tw"] - 1, 2), "k": leg["k"]})
    if leg.get("piston"):
        tu = _norm((knee[0] - hip[0], knee[1] - hip[1]))
        su = _norm((ankle[0] - knee[0], ankle[1] - knee[1]))
        tn, sn = _perp(tu), _perp(su)
        fw = leg.get("forward", 1)
        ft = tn if tn[0] * fw > 0 else (-tn[0], -tn[1])
        fs = sn if sn[0] * fw > 0 else (-sn[0], -sn[1])
        p1 = (hip[0] + (knee[0] - hip[0]) * 0.35 + ft[0] * (leg["tw"] + 1.5),
              hip[1] + (knee[1] - hip[1]) * 0.35 + ft[1] * (leg["tw"] + 1.5))
        p2 = (knee[0] + (ankle[0] - knee[0]) * 0.55 + fs[0] * (leg["sw"] + 1.5),
              knee[1] + (ankle[1] - knee[1]) * 0.55 + fs[1] * (leg["sw"] + 1.5))
        out.append({"p": bone(p1, p2, 1, 1, 0), "k": "metal"})
        out.append({"c": [p1[0], p1[1], 1.6], "k": "dark"})
    out.append({"c": [knee[0], knee[1], leg["kr"]], "k": "metal"})
    return out


def shift_part(p, o):
    q = dict(p)
    if "r" in p:
        q["r"] = [p["r"][0] + o[0], p["r"][1] + o[1], p["r"][2], p["r"][3]]
    elif "c" in p:
        q["c"] = [p["c"][0] + o[0], p["c"][1] + o[1], p["c"][2]]
    else:
        q["p"] = [[x + o[0], y + o[1]] for x, y in p["p"]]
    return q


def group_offset(grp, off, gun):
    if grp == "gun":
        return (off[0] + gun, off[1])
    if grp == "turret":
        return (off[0] + round(gun / 3), off[1])
    return (off[0], off[1])


def part_enabled(p, flags):
    if "only" in p and p["only"] not in flags:
        return False
    if "not" in p and p["not"] in flags:
        return False
    return True


def frame_parts(defn, off, gun=0, flags=()):
    out = []
    for p in defn["parts"]:
        if not part_enabled(p, flags):
            continue
        if "leg" in p:
            out.extend(leg_parts(defn["legs"][p["leg"]], off))
        else:
            out.append(shift_part(p, group_offset(p.get("grp"), off, gun)))
    return out
