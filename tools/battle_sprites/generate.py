#!/usr/bin/env python3
"""Battle screen art generator (stdlib only, deterministic).

Writes PNG sheets + JSON metadata under assets/battle/:
  mechs/<sheet>_<faction>.png   one row of pose cells (w x h each)
  mechs/<sheet>.json            pose order, per-pose body/gun offsets, anchors

Usage:
  python3 tools/battle_sprites/generate.py            # regenerate into assets/battle
  python3 tools/battle_sprites/generate.py --out DIR  # generate elsewhere
  python3 tools/battle_sprites/generate.py --check    # exit 1 if committed assets differ
"""
import argparse
import filecmp
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import backdrops  # noqa: E402
import chassis as chassis_mod  # noqa: E402
import font  # noqa: E402
import png  # noqa: E402
import poses  # noqa: E402
import raster  # noqa: E402
import rig  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "assets", "battle")
FACTIONS = ("coalition", "syndikat")


def render_sheet(defn, flags=(), braced=False):
    table = poses.pose_table(defn, braced)
    w, h = defn["w"], defn["h"]
    bufs = [raster.render(w, h, rig.frame_parts(defn, off, gun, flags)) for _, off, gun in table]
    return table, bufs


def write_mech(out, sheet_name, defn, flags=(), braced=False, variants=None):
    table, bufs = render_sheet(defn, flags, braced)
    w, h = defn["w"], defn["h"]
    for fac in FACTIONS:
        pal = raster.palette_for(fac)
        frames = [raster.colorize(b, w, h, pal) for b in bufs]
        png.write_png(os.path.join(out, "mechs", "%s_%s.png" % (sheet_name, fac)), w * len(frames), h, raster.hstack(frames, w, h))
    # white silhouette for hit flashes (faction-independent)
    whites = [[[(255, 255, 255, 255) if b[y * w + x] is not None else (0, 0, 0, 0) for x in range(w)] for y in range(h)] for b in bufs]
    png.write_png(os.path.join(out, "mechs", "%s_white.png" % sheet_name), w * len(whites), h, raster.hstack(whites, w, h))
    meta = {
        "w": w, "h": h,
        "idle_ms": defn["idle_ms"],
        "idle_frames": len(defn.get("idle", poses.DEFAULT_IDLE)),
        "poses": [n for n, _, _ in table],
        "pose_off": {n: o for n, o, _ in table},
        "pose_gun": {n: g for n, _, g in table},
        "anchors": defn["anchors"],
        "variants": variants or {},
        "braced": braced,
    }
    with open(os.path.join(out, "mechs", "%s.json" % sheet_name), "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write("\n")


def write_attachments(out):
    os.makedirs(os.path.join(out, "fx"), exist_ok=True)
    for name, (w, h, parts) in chassis_mod.ATTACHMENTS.items():
        buf = raster.render(w, h, parts)
        for fac in FACTIONS:
            png.write_png(os.path.join(out, "fx", "%s_%s.png" % (name, fac)), w, h, raster.colorize(buf, w, h, raster.palette_for(fac)))


def generate_all(out):
    os.makedirs(os.path.join(out, "mechs"), exist_ok=True)
    write_attachments(out)
    backdrops.write_backdrops(out)
    font.write_font(out)
    variant_map = {}
    for vname, (base, _flags, _braced) in chassis_mod.VARIANTS.items():
        variant_map.setdefault(base, {})[vname.split("_", 1)[1]] = vname
    for name, defn in chassis_mod.CHASSIS.items():
        write_mech(out, name, defn, variants=variant_map.get(name, {}))
    for vname, (base, flags, braced) in chassis_mod.VARIANTS.items():
        write_mech(out, vname, chassis_mod.CHASSIS[base], flags, braced)


def _same_tree(a, b):
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
        return False
    for f in cmp.common_files:
        if not filecmp.cmp(os.path.join(a, f), os.path.join(b, f), shallow=False):
            return False
    return all(_same_tree(os.path.join(a, d), os.path.join(b, d)) for d in cmp.common_dirs)


def _strip_imports(root):
    """Godot writes *.import sidecars next to PNGs; they are not generator output."""
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith(".import"):
                os.remove(os.path.join(d, f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory() as fresh, tempfile.TemporaryDirectory() as committed:
            generate_all(fresh)
            import shutil
            shutil.copytree(args.out, committed, dirs_exist_ok=True)
            _strip_imports(committed)
            ok = _same_tree(fresh, committed)
            print("assets up to date" if ok else "assets differ from generator output; re-run generate.py")
            sys.exit(0 if ok else 1)
    generate_all(args.out)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
