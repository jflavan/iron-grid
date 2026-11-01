"""Unit tests for the battle sprite generator.

Run: python3 -m unittest discover -s tools/battle_sprites -v
"""
import json
import os
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import generate  # noqa: E402
import png  # noqa: E402
import rig  # noqa: E402


def png_size(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    w, h = struct.unpack(">II", data[16:24])
    return w, h


def all_files(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            with open(p, "rb") as fh:
                out[os.path.relpath(p, root)] = fh.read()
    return out


class GeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        generate.generate_all(cls.tmp)

    def test_knee_is_forward(self):
        hip, knee, ankle = (42, 57), (41, 77), (32, 94)
        lt = rig.dist(hip, knee)
        ls = rig.dist(knee, ankle)
        k = rig.solve_knee(hip, ankle, lt, ls)
        # the straight hip->ankle line at the knee's height is x~37.6; knee must be ahead of it
        self.assertGreater(k[0], 37.6)

    def test_png_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.png")
            rows = [[(255, 0, 0, 255)] * 3, [(0, 0, 0, 0)] * 3]
            png.write_png(p, 3, 2, rows)
            self.assertEqual(png_size(p), (3, 2))
            with open(p, "rb") as f:
                raw = f.read()
            idat = raw[raw.index(b"IDAT") + 4:]
            self.assertTrue(zlib.decompress(idat[: struct.unpack(">I", raw[raw.index(b"IDAT") - 4: raw.index(b"IDAT")])[0]]))

    def test_sheet_dimensions(self):
        with open(os.path.join(self.tmp, "mechs", "vanguard.json")) as f:
            meta = json.load(f)
        w, h = png_size(os.path.join(self.tmp, "mechs", "vanguard_coalition.png"))
        self.assertEqual(w, meta["w"] * len(meta["poses"]))
        self.assertEqual(h, meta["h"])
        for pose in ("idle0", "idle5", "brace", "chamber", "recoil0", "recoil3", "hit", "stagger", "lunge", "angle"):
            self.assertIn(pose, meta["poses"])

    def test_all_chassis_present(self):
        weapons = {
            "vanguard": ["kwk_88", "coax_mg"], "goliath": ["morser_210", "flak_38"],
            "falke": ["autocannon_50"], "donner": ["rocket_pod"],
            "kommandant": ["assault_105"], "moloch": ["thermite_lance", "pile_bunker"],
        }
        sheets = list(weapons) + ["moloch_spent", "donner_braced"]
        for name in sheets:
            for fac in ("coalition", "syndikat"):
                self.assertTrue(os.path.exists(os.path.join(self.tmp, "mechs", "%s_%s.png" % (name, fac))), name)
            with open(os.path.join(self.tmp, "mechs", name + ".json")) as f:
                meta = json.load(f)
            base = name.split("_")[0]
            for card in weapons[base]:
                self.assertIn(card, meta["anchors"]["muzzles"], name)
            self.assertIn(meta["basic_weapon"], weapons[base])
        with open(os.path.join(self.tmp, "mechs", "moloch.json")) as f:
            self.assertEqual(json.load(f)["variants"], {"spent": "moloch_spent"})
        with open(os.path.join(self.tmp, "mechs", "donner_braced.json")) as f:
            braced = json.load(f)
        self.assertEqual({tuple(braced["pose_off"]["idle%d" % i])[1] for i in range(braced["idle_frames"])}, {3})
        for att in ("slab", "mast", "rangefinder"):
            for fac in ("coalition", "syndikat"):
                self.assertTrue(os.path.exists(os.path.join(self.tmp, "fx", "%s_%s.png" % (att, fac))), att)
        with open(os.path.join(self.tmp, "mechs", "kommandant.json")) as f:
            self.assertIn("mast", json.load(f)["anchors"]["attach"])
        with open(os.path.join(self.tmp, "mechs", "falke.json")) as f:
            self.assertIn("rangefinder", json.load(f)["anchors"]["attach"])

    def test_deterministic(self):
        with tempfile.TemporaryDirectory() as d:
            generate.generate_all(d)
            self.assertEqual(all_files(d), all_files(self.tmp))


if __name__ == "__main__":
    unittest.main()
