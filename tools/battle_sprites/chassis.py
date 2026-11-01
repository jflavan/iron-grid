"""Chassis definitions. All sprites face RIGHT; coordinates are native pixels in the sprite cell.

Part forms: {"r":[x,y,w,h]}, {"c":[cx,cy,r]}, {"p":[[x,y],..]}; "k" = palette key
(hull, trim, metal, dark, glow, rear, brass, steam, lens). Optional: "pv"/"ph" panel-line
offsets, "rivet", "grp" ("gun" recoils fully, "turret" by a third), "only"/"not" variant flags.
{"leg": i} inserts leg i (re-solved with IK every pose) at that point in the draw order.

Anchors are in the rest pose (offset [0,0], gun 0) and unmirrored.
"""

# ---- KPZ-09 Sturmjäger: medium assault walker (approved mockup design) ----
VANGUARD = {
    "w": 112, "h": 100, "idle_ms": 150, "basic_weapon": "kwk_88",
    "legs": [
        {"hip": [42, 57], "knee": [41, 77], "ankle": [32, 94], "tw": 6, "sw": 5, "kr": 5, "k": "rear",
         "foot": [[18, 94], [42, 94], [45, 99], [15, 99]]},
        {"hip": [60, 57], "knee": [68, 78], "ankle": [64, 94], "tw": 6.5, "sw": 6, "kr": 6, "k": "hull", "piston": True,
         "foot": [[52, 94], [80, 94], [86, 99], [50, 99]], "toe": [84, 96, 4, 3]},
    ],
    "parts": [
        {"r": [40, 0, 1, 11], "k": "metal", "grp": "turret"},
        {"r": [14, 8, 5, 22], "k": "metal", "ph": [6]}, {"r": [12, 5, 9, 3], "k": "dark"},
        {"r": [21, 12, 4, 16], "k": "metal"}, {"r": [20, 10, 6, 2], "k": "dark"},
        {"leg": 0},
        {"r": [34, 52, 38, 9], "k": "metal", "rivet": True},
        {"r": [10, 32, 9, 14], "k": "dark", "ph": [6]},
        {"p": [[22, 26], [74, 26], [88, 40], [86, 54], [20, 54], [17, 34]], "k": "hull", "rivet": True, "pv": [20, 40]},
        {"r": [19, 50, 66, 6], "k": "dark", "rivet": True},
        {"r": [22, 41, 58, 2], "k": "trim"},
        {"p": [[28, 30], [34, 30], [31, 36]], "k": "trim"},
        {"p": [[38, 10], [66, 10], [73, 16], [73, 25], [36, 25], [33, 16]], "k": "hull", "rivet": True, "pv": [14], "grp": "turret"},
        {"r": [45, 7, 11, 3], "k": "metal", "grp": "turret"}, {"r": [60, 3, 3, 7], "k": "metal", "grp": "turret"},
        {"r": [59, 2, 5, 2], "k": "dark", "grp": "turret"},
        {"r": [64, 17, 6, 2], "k": "glow", "grp": "turret"},
        {"r": [72, 13, 7, 11], "k": "metal", "ph": [5], "grp": "gun"},
        {"r": [79, 16, 26, 4], "k": "metal", "grp": "gun"},
        {"r": [103, 13, 8, 10], "k": "metal", "pv": [3], "grp": "gun"},
        {"r": [84, 42, 8, 6], "k": "metal"}, {"r": [92, 43, 11, 2], "k": "metal"}, {"r": [92, 46, 9, 1], "k": "dark"},
        {"leg": 1},
    ],
    "anchors": {
        "feet": [50, 99], "hull": [54, 38], "glacis": [80, 34], "viewport": [67, 18],
        "stacks": [[16, 5], [22, 10]],
        "muzzles": {"kwk_88": {"p": [111, 18], "grp": "gun"}, "coax_mg": {"p": [103, 44], "grp": ""}},
        "attach": {},
    },
}

# ---- Sturm-V Brenner: heavy urban brawler (approved mockup design) ----
MOLOCH = {
    "w": 128, "h": 116, "idle_ms": 210, "basic_weapon": "thermite_lance",
    "idle": [[0, 0], [0, 1], [1, 2], [1, 4], [1, 3], [0, 1]],
    "legs": [
        {"hip": [38, 72], "knee": [43, 88], "ankle": [36, 107], "tw": 8, "sw": 7.5, "kr": 7, "k": "rear",
         "foot": [[18, 108], [50, 108], [54, 115], [14, 115]]},
        {"hip": [70, 72], "knee": [77, 89], "ankle": [72, 107], "tw": 8.5, "sw": 8, "kr": 8, "k": "hull", "piston": True,
         "foot": [[54, 108], [90, 108], [96, 115], [50, 115]], "toe": [92, 111, 5, 4]},
    ],
    "parts": [
        {"r": [26, 2, 6, 24], "k": "metal", "ph": [8, 16]}, {"r": [24, 0, 10, 3], "k": "dark"},
        {"r": [35, 6, 5, 20], "k": "metal"}, {"r": [34, 4, 7, 2], "k": "dark"},
        {"r": [3, 26, 11, 36], "k": "metal", "ph": [8, 26]}, {"r": [13, 28, 9, 32], "k": "metal", "ph": [8, 24]},
        {"r": [2, 33, 21, 2], "k": "trim"},
        {"leg": 0},
        {"r": [14, 60, 40, 2], "k": "dark"},
        {"r": [30, 64, 54, 10], "k": "metal", "rivet": True},
        {"p": [[18, 22], [92, 22], [100, 34], [98, 66], [22, 66], [16, 40]], "k": "hull", "rivet": True, "pv": [24, 52], "ph": [20]},
        {"r": [20, 49, 76, 3], "k": "trim"},
        {"p": [[30, 28], [38, 28], [34, 36]], "k": "trim"},
        {"p": [[44, 6], [68, 6], [73, 12], [73, 22], [42, 22], [39, 12]], "k": "hull", "rivet": True},
        {"r": [60, 12, 10, 3], "k": "glow"}, {"r": [48, 13, 7, 1], "k": "dark"},
        {"r": [70, 40, 12, 14], "k": "rear"},
        {"r": [80, 51, 40, 5], "k": "metal", "pv": [10, 22]},
        {"r": [117, 49, 7, 9], "k": "dark"},
        {"r": [124, 52, 2, 3], "k": "glow"},
        {"p": [[78, 16], [106, 18], [111, 34], [80, 36]], "k": "hull", "rivet": True},
        {"r": [96, 30, 14, 12], "k": "hull"},
        {"r": [99, 40, 19, 26], "k": "metal", "rivet": True, "ph": [12]},
        {"r": [95, 44, 4, 18], "k": "metal"},
        {"p": [[118, 57], [127, 61], [118, 65]], "k": "metal"},
        {"leg": 1},
    ],
    "anchors": {
        "feet": [55, 115], "hull": [58, 42], "glacis": [92, 36], "viewport": [64, 13],
        "stacks": [[29, 1], [37, 4]],
        "muzzles": {"thermite_lance": {"p": [124, 53], "grp": ""}, "pile_bunker": {"p": [127, 61], "grp": ""}},
        "attach": {},
    },
}

CHASSIS = {
    "vanguard": VANGUARD,
    "moloch": MOLOCH,
}

# Variant sheets: name -> (base chassis, flags, braced)
VARIANTS = {}
