#!/usr/bin/env python3
"""Battle screen art generator (stdlib only, deterministic).

Writes PNG sheets + JSON metadata under assets/battle/:
  mechs/<sheet>_<faction>.png   one row of pose cells (w x h each)
  mechs/<sheet>.json            pose order, per-pose body/gun offsets, anchors

Also writes story portraits (48x48) under assets/story/portraits/ and cutscene backdrops (354x142) under assets/story/backdrops/.

Usage:
  python3 tools/battle_sprites/generate.py                    # regenerate assets/battle + assets/story
  python3 tools/battle_sprites/generate.py --out DIR          # battle art elsewhere
  python3 tools/battle_sprites/generate.py --story-out DIR    # story art elsewhere
  python3 tools/battle_sprites/generate.py --check            # exit 1 if committed assets differ
                                                              # (PNGs compared by decoded content, not zlib bytes)
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
import portraits  # noqa: E402
import story_backdrops  # noqa: E402
import poses  # noqa: E402
import raster  # noqa: E402
import rig  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "assets", "battle")
DEFAULT_STORY_OUT = os.path.join(REPO, "assets", "story")
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


def write_livery(out, sheet_name, defn, livery):
    """One extra palette sheet (same layout as <sheet>_<faction>.png); the json/white sheet are shared."""
    table, bufs = render_sheet(defn)
    w, h = defn["w"], defn["h"]
    pal = raster.palette_for(livery)
    frames = [raster.colorize(b, w, h, pal) for b in bufs]
    png.write_png(os.path.join(out, "mechs", "%s_%s.png" % (sheet_name, livery)), w * len(frames), h, raster.hstack(frames, w, h))


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
    for sheet, livery in chassis_mod.LIVERIES:
        write_livery(out, sheet, chassis_mod.CHASSIS[sheet], livery)


def generate_story(out):
    portraits.write_portraits(out)
    story_backdrops.write_backdrops(out)


def _png_payload(path):
    """IHDR + decompressed pixel data: identical across zlib builds (zlib vs zlib-ng emit different bytes)."""
    import struct
    import zlib
    with open(path, "rb") as f:
        data = f.read()
    pos, idat, ihdr = 8, b"", b""
    while pos < len(data):
        n, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if tag == b"IHDR":
            ihdr = body
        elif tag == b"IDAT":
            idat += body
        pos += 12 + n
    return ihdr, zlib.decompress(idat)


def _same_file(a, b):
    if a.endswith(".png") and b.endswith(".png"):
        try:
            return _png_payload(a) == _png_payload(b)
        except Exception:
            return False
    return filecmp.cmp(a, b, shallow=False)


def _same_tree(a, b):
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.funny_files:
        return False
    for f in cmp.common_files:
        if not _same_file(os.path.join(a, f), os.path.join(b, f)):
            return False
    return all(_same_tree(os.path.join(a, d), os.path.join(b, d)) for d in cmp.common_dirs)


def _strip_imports(root):
    """Godot writes *.import sidecars next to PNGs; they are not generator output."""
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith(".import"):
                os.remove(os.path.join(d, f))


def _sync(fresh, dest):
    """Copy generated files into dest, leaving unchanged ones untouched (no zlib-build churn in git)."""
    import shutil
    for d, _, files in os.walk(fresh):
        for f in files:
            src = os.path.join(d, f)
            dst = os.path.join(dest, os.path.relpath(src, fresh))
            if os.path.exists(dst) and _same_file(src, dst):
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--story-out", default=DEFAULT_STORY_OUT)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        import shutil
        ok = True
        for gen, src in ((generate_all, args.out), (generate_story, args.story_out)):
            with tempfile.TemporaryDirectory() as fresh, tempfile.TemporaryDirectory() as committed:
                gen(fresh)
                if os.path.isdir(src):
                    shutil.copytree(src, committed, dirs_exist_ok=True)
                _strip_imports(committed)
                ok = _same_tree(fresh, committed) and ok
            print("assets up to date" if ok else "assets differ from generator output; re-run generate.py")
            sys.exit(0 if ok else 1)
    for gen, dest in ((generate_all, args.out), (generate_story, args.story_out)):
        with tempfile.TemporaryDirectory() as fresh:
            gen(fresh)
            _sync(fresh, dest)
    print("wrote", args.out, "and", args.story_out)


if __name__ == "__main__":
    main()
