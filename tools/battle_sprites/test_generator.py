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

import chassis  # noqa: E402
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
        cls.tmp_story = tempfile.mkdtemp()
        generate.generate_story(cls.tmp_story)

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

    def test_portraits(self):
        ids = ["leon", "leon_child", "mira", "chad", "brann", "wolfram", "konrad", "ilse", "grau", "hq", "syndikat"]
        files = sorted(os.listdir(os.path.join(self.tmp_story, "portraits")))
        self.assertEqual(files, sorted(i + ".png" for i in ids))
        for i in ids:
            p = os.path.join(self.tmp_story, "portraits", i + ".png")
            self.assertEqual(png_size(p), (48, 48), i)
            rows = generate._png_payload(p)[1]
            # RGBA, filter byte 0 per row: every alpha must be 255
            stride = 1 + 48 * 4
            alphas = {rows[r * stride + 1 + x * 4 + 3] for r in range(48) for x in range(48)}
            self.assertEqual(alphas, {255}, i)
        self.assertNotEqual(generate._png_payload(os.path.join(self.tmp_story, "portraits", "leon.png")),
                            generate._png_payload(os.path.join(self.tmp_story, "portraits", "konrad.png")))

    def test_story_backdrops(self):
        ids = ["briefing_room", "village_fire", "memorial", "motor_pool", "records_room", "office",
               "field_camp", "snow_pass", "causeway", "capital_street", "throne_gate", "parade_court"]
        d = os.path.join(self.tmp_story, "backdrops")
        self.assertEqual(sorted(os.listdir(d)), sorted(i + ".png" for i in ids))
        seen = set()
        for i in ids:
            p = os.path.join(d, i + ".png")
            self.assertEqual(png_size(p), (354, 142), i)
            raw = generate._png_payload(p)[1]
            seen.add(raw)
            stride = 1 + 354 * 4
            for r in range(142):
                row = raw[r * stride + 1:(r + 1) * stride]
                self.assertEqual(set(row[3::4]), {255}, i)
                self.assertLess(max(max(row[0::4]), max(row[1::4]), max(row[2::4])), 235, i)  # no pure-white areas
        self.assertEqual(len(seen), len(ids))

    def test_ragnarok_mirrors_goliath(self):
        g, r = chassis.GOLIATH["anchors"], chassis.RAGNAROK["anchors"]
        self.assertEqual(set(r), set(g))
        self.assertEqual(set(r["muzzles"]), set(g["muzzles"]))
        self.assertEqual(set(r["attach"]), set(g["attach"]))
        for k in ("muzzles", "attach"):
            for name in g[k]:
                if k == "muzzles":
                    self.assertEqual(r[k][name]["grp"], g[k][name]["grp"])
        self.assertLessEqual(chassis.RAGNAROK["w"], 152)
        self.assertLessEqual(chassis.RAGNAROK["h"], 128)
        self.assertGreater(chassis.RAGNAROK["w"] * chassis.RAGNAROK["h"], max(d["w"] * d["h"] for n, d in chassis.CHASSIS.items() if n != "ragnarok"))
        with open(os.path.join(self.tmp, "mechs", "ragnarok.json")) as f:
            meta = json.load(f)
        with open(os.path.join(self.tmp, "mechs", "goliath.json")) as f:
            self.assertEqual(meta["poses"], json.load(f)["poses"])
        for suffix in ("coalition", "syndikat", "white"):
            self.assertEqual(png_size(os.path.join(self.tmp, "mechs", "ragnarok_%s.png" % suffix)), (meta["w"] * len(meta["poses"]), meta["h"]))

    def test_blackclaw_livery(self):
        a = os.path.join(self.tmp, "mechs", "kommandant_blackclaw.png")
        b = os.path.join(self.tmp, "mechs", "kommandant_syndikat.png")
        self.assertEqual(png_size(a), png_size(b))
        self.assertNotEqual(generate._png_payload(a)[1], generate._png_payload(b)[1])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "mechs", "vanguard_blackclaw.png")))

    def test_backdrops_and_font(self):
        for t in ("plain", "road", "river", "forest", "city", "mountain"):
            self.assertEqual(png_size(os.path.join(self.tmp, "backdrops", t + ".png")), (360, 152), t)
        with open(os.path.join(self.tmp, "font", "font5x7.json"), encoding="utf-8") as f:
            meta = json.load(f)
        self.assertEqual(meta["advance"], 6)
        self.assertIn("Ä", meta["chars"])
        self.assertIn("9", meta["chars"])
        w, h = png_size(os.path.join(self.tmp, "font", "font5x7.png"))
        self.assertEqual((w, h), (6 * len(meta["chars"]), 8))

    def test_output_is_platform_independent(self):
        """Emulate Windows text-mode defaults (CRLF newlines, cp1252 encoding): output must not change."""
        import builtins
        import font

        real_open = builtins.open

        def windows_open(file, mode="r", *args, **kwargs):
            if "b" not in mode:
                kwargs.setdefault("newline", "\r\n")
                kwargs.setdefault("encoding", "cp1252")
            return real_open(file, mode, *args, **kwargs)

        with tempfile.TemporaryDirectory() as d:
            generate.open = font.open = windows_open
            try:
                generate.generate_all(d)
            finally:
                del generate.open
                del font.open
            self.assertEqual(all_files(d), all_files(self.tmp))

    def test_deterministic(self):
        with tempfile.TemporaryDirectory() as d:
            generate.generate_all(d)
            self.assertEqual(all_files(d), all_files(self.tmp))
        with tempfile.TemporaryDirectory() as d:
            generate.generate_story(d)
            self.assertEqual(all_files(d), all_files(self.tmp_story))


if __name__ == "__main__":
    unittest.main()
