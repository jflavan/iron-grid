"""Chassis definitions. All sprites face RIGHT; coordinates are native pixels in the sprite cell.

Part forms: {"r":[x,y,w,h]}, {"c":[cx,cy,r]}, {"p":[[x,y],..]}; "k" = palette key
(hull, trim, metal, dark, glow, rear, brass, steam, lens). Optional: "pv"/"ph" panel-line
offsets, "rivet", "grp" ("gun" recoils fully, "turret" by a third), "only"/"not" variant flags.
{"leg": i} inserts leg i (re-solved with IK every pose) at that point in the draw order.

Anchors are in the rest pose (offset [0,0], gun 0) and unmirrored.
"""

# ---- KPZ-09 Sturmjäger: medium assault walker (approved mockup design) ----
VANGUARD = {
    "w": 112, "h": 100, "idle_ms": 150,
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
    "w": 128, "h": 116, "idle_ms": 210,
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
        # Reactive Shield Wall bricks (gone in the "spent" variant, leaving scorch scars)
        {"r": [52, 26, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [63, 26, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [74, 26, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [52, 37, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [63, 37, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [74, 37, 9, 8], "k": "dark", "rivet": True, "not": "spent"},
        {"r": [54, 29, 5, 2], "k": "rear", "only": "spent"}, {"r": [66, 39, 4, 3], "k": "rear", "only": "spent"},
        {"r": [76, 28, 5, 3], "k": "rear", "only": "spent"}, {"r": [56, 40, 3, 2], "k": "rear", "only": "spent"},
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

MOLOCH["anchors"]["bricks"] = [56, 30]

# ---- VK-100 Siegebreaker: super-heavy dreadnought, 210mm Mörser + quad flak ----
GOLIATH = {
    "w": 136, "h": 120, "idle_ms": 240,
    "idle": [[0, 0], [0, 1], [1, 2], [1, 4], [1, 3], [0, 1]],
    "legs": [
        {"hip": [46, 80], "knee": [51, 96], "ankle": [42, 112], "tw": 10, "sw": 9, "kr": 8, "k": "rear",
         "foot": [[24, 112], [60, 112], [64, 119], [20, 119]]},
        {"hip": [84, 80], "knee": [93, 97], "ankle": [86, 112], "tw": 10.5, "sw": 10, "kr": 9, "k": "hull", "piston": True,
         "foot": [[66, 112], [106, 112], [112, 119], [62, 119]], "toe": [108, 115, 6, 4]},
    ],
    "parts": [
        {"r": [20, 10, 7, 26], "k": "metal", "ph": [8, 18]}, {"r": [18, 7, 11, 4], "k": "dark"},
        {"r": [29, 14, 6, 22], "k": "metal", "ph": [8]}, {"r": [28, 12, 8, 3], "k": "dark"},
        {"leg": 0},
        {"r": [36, 74, 62, 11], "k": "metal", "rivet": True},
        {"r": [6, 44, 12, 28], "k": "dark", "ph": [9, 18]},
        {"p": [[16, 36], [104, 36], [118, 50], [116, 80], [20, 80], [12, 56]], "k": "hull", "rivet": True, "pv": [30, 62], "ph": [22]},
        {"r": [14, 74, 104, 7], "k": "dark", "rivet": True},
        {"r": [18, 62, 96, 3], "k": "trim"},
        {"p": [[28, 44], [38, 44], [33, 52]], "k": "trim"},
        # Mörser casemate
        {"p": [[44, 14], [90, 14], [100, 24], [100, 38], [42, 38], [38, 24]], "k": "hull", "rivet": True, "pv": [18, 36], "grp": "turret"},
        {"r": [52, 8, 14, 6], "k": "metal", "grp": "turret"}, {"r": [56, 5, 6, 3], "k": "dark", "grp": "turret"},
        {"r": [84, 22, 9, 3], "k": "glow", "grp": "turret"},
        {"r": [94, 18, 8, 16], "k": "metal", "ph": [6], "grp": "gun"},
        {"p": [[98, 19], [124, 8], [128, 16], [102, 29]], "k": "metal", "grp": "gun"},
        {"p": [[121, 5], [130, 2], [134, 14], [125, 18]], "k": "dark", "grp": "gun"},
        # Quad Flak-38 sponson
        {"r": [104, 52, 13, 15], "k": "metal", "rivet": True},
        {"r": [117, 53, 14, 2], "k": "metal"}, {"r": [117, 57, 14, 2], "k": "metal"},
        {"r": [117, 61, 14, 2], "k": "metal"}, {"r": [117, 65, 14, 2], "k": "metal"},
        {"leg": 1},
    ],
    "anchors": {
        "feet": [65, 119], "hull": [64, 56], "glacis": [110, 48], "viewport": [88, 23],
        "stacks": [[23, 7], [32, 12]],
        "muzzles": {"morser_210": {"p": [132, 9], "grp": "gun"}, "flak_38": {"p": [131, 59], "grp": ""}},
        "attach": {"slab": [128, 119]},
    },
}

# ---- Pz.Kpfw-X Ragnarök: Supreme Marshal Grau's super-heavy walker (twin siege barrels, command tower) ----
RAGNAROK = {
    "w": 152, "h": 128, "idle_ms": 260,
    "idle": [[0, 0], [0, 1], [1, 2], [1, 4], [1, 3], [0, 1]],
    "legs": [
        {"hip": [52, 88], "knee": [58, 104], "ankle": [48, 120], "tw": 12, "sw": 10, "kr": 9, "k": "rear",
         "foot": [[26, 120], [68, 120], [74, 127], [22, 127]]},
        {"hip": [94, 88], "knee": [104, 105], "ankle": [96, 120], "tw": 12.5, "sw": 11, "kr": 10, "k": "hull", "piston": True,
         "foot": [[72, 120], [118, 120], [126, 127], [68, 127]], "toe": [120, 123, 7, 4]},
    ],
    "parts": [
        # three exhaust stacks, staggered
        {"r": [14, 14, 7, 30], "k": "metal", "ph": [8, 18]}, {"r": [12, 11, 11, 4], "k": "dark"},
        {"r": [24, 20, 6, 26], "k": "metal", "ph": [8]}, {"r": [22, 17, 10, 3], "k": "dark"},
        {"r": [33, 26, 5, 20], "k": "metal"}, {"r": [31, 24, 9, 3], "k": "dark"},
        {"leg": 0},
        {"r": [40, 82, 72, 12], "k": "metal", "rivet": True},
        {"r": [4, 52, 13, 30], "k": "dark", "ph": [9, 19]},
        {"p": [[14, 44], [116, 44], [132, 58], [130, 88], [18, 88], [10, 64]], "k": "hull", "rivet": True, "pv": [34, 70], "ph": [24]},
        {"r": [12, 82, 118, 8], "k": "dark", "rivet": True},
        {"r": [16, 68, 110, 3], "k": "trim"},
        {"p": [[26, 52], [38, 52], [32, 60]], "k": "trim"}, {"p": [[44, 52], [56, 52], [50, 60]], "k": "trim"},
        # command tower
        {"r": [58, 0, 1, 6], "k": "metal", "grp": "turret"},
        {"p": [[50, 8], [72, 8], [76, 14], [76, 44], [46, 44], [46, 14]], "k": "hull", "rivet": True, "pv": [14], "grp": "turret"},
        {"r": [44, 4, 34, 5], "k": "dark", "grp": "turret"},
        {"r": [52, 16, 20, 3], "k": "glow", "grp": "turret"}, {"r": [52, 28, 20, 2], "k": "glow", "grp": "turret"},
        {"r": [62, 1, 8, 3], "k": "metal", "grp": "turret"},
        # siege casemate carrying the twin barrels
        {"p": [[76, 20], [108, 20], [116, 28], [116, 46], [74, 46], [74, 28]], "k": "hull", "rivet": True, "pv": [20], "grp": "turret"},
        {"r": [88, 26, 12, 3], "k": "glow", "grp": "turret"},
        {"r": [104, 24, 9, 22], "k": "metal", "ph": [8], "grp": "gun"},
        {"p": [[110, 22], [140, 10], [144, 18], [114, 30]], "k": "metal", "grp": "gun"},
        {"p": [[110, 34], [140, 24], [144, 32], [114, 44]], "k": "metal", "grp": "gun"},
        {"p": [[137, 7], [147, 4], [150, 20], [141, 22]], "k": "dark", "grp": "gun"},
        {"p": [[137, 21], [147, 18], [150, 34], [141, 36]], "k": "dark", "grp": "gun"},
        # Quad Flak-38 sponson
        {"r": [116, 58, 14, 18], "k": "metal", "rivet": True},
        {"r": [130, 59, 18, 2], "k": "metal"}, {"r": [130, 64, 18, 2], "k": "metal"},
        {"r": [130, 69, 18, 2], "k": "metal"}, {"r": [130, 74, 18, 2], "k": "metal"},
        {"leg": 1},
    ],
    "anchors": {
        "feet": [72, 127], "hull": [70, 64], "glacis": [122, 56], "viewport": [98, 27],
        "stacks": [[17, 11], [27, 17], [35, 24]],
        "muzzles": {"morser_210": {"p": [147, 12], "grp": "gun"}, "flak_38": {"p": [147, 68], "grp": ""}},
        "attach": {"slab": [140, 127]},
    },
}

# ---- Sd.Kfz-22 Spähfalke: light recon strider, 50mm autocannon, gyro thrusters ----
FALKE = {
    "w": 96, "h": 92, "idle_ms": 130,
    "legs": [
        {"hip": [38, 48], "knee": [41, 67], "ankle": [30, 86], "tw": 4.5, "sw": 4, "kr": 4, "k": "rear",
         "foot": [[20, 86], [40, 86], [42, 91], [18, 91]]},
        {"hip": [52, 48], "knee": [59, 67], "ankle": [54, 86], "tw": 5, "sw": 4.5, "kr": 5, "k": "hull", "piston": True,
         "foot": [[44, 86], [66, 86], [70, 91], [42, 91]], "toe": [68, 88, 3, 3]},
    ],
    "parts": [
        {"r": [28, 12, 4, 12], "k": "metal"}, {"r": [27, 10, 6, 2], "k": "dark"},
        {"r": [52, 1, 1, 12], "k": "metal", "grp": "turret"},
        {"leg": 0},
        {"r": [32, 44, 26, 6], "k": "metal", "rivet": True},
        # hip gyro thrusters
        {"r": [13, 32, 9, 12], "k": "metal", "ph": [5]},
        {"p": [[8, 34], [13, 33], [13, 44], [8, 43]], "k": "dark"},
        {"p": [[24, 22], [64, 20], [76, 30], [74, 44], [28, 46], [20, 34]], "k": "hull", "rivet": True, "pv": [22]},
        {"r": [24, 40, 48, 2], "k": "trim"},  # amphibious seal band
        {"p": [[30, 26], [36, 26], [33, 32]], "k": "trim"},
        # sensor head
        {"p": [[46, 12], [66, 12], [72, 18], [70, 25], [44, 25]], "k": "hull", "grp": "turret"},
        {"r": [62, 16, 8, 2], "k": "glow", "grp": "turret"},
        # 50mm autocannon
        {"r": [66, 30, 10, 8], "k": "metal", "ph": [4]},
        {"r": [76, 32, 15, 3], "k": "metal", "grp": "gun"},
        {"r": [89, 31, 5, 5], "k": "metal", "grp": "gun"},
        {"r": [72, 36, 6, 4], "k": "brass"},  # ammo drum
        {"leg": 1},
    ],
    "anchors": {
        "feet": [44, 91], "hull": [48, 32], "glacis": [70, 30], "viewport": [66, 17],
        "stacks": [[30, 10]],
        "muzzles": {"autocannon_50": {"p": [94, 33], "grp": "gun"}},
        "attach": {"rangefinder": [56, 12], "thruster": [9, 39]},
    },
}

# ---- SPG-88 Spinne: quadruped mountain walker, Nebelwerfer rocket pod ----
def _pad(ax, ay):
    return [[ax - 6, ay], [ax + 6, ay], [ax + 7, ay + 4], [ax - 7, ay + 4]]


DONNER = {
    "w": 128, "h": 96, "idle_ms": 170,
    "idle": [[0, 0], [0, 1], [0, 2], [1, 3], [0, 2], [0, 1]],
    "legs": [
        {"hip": [78, 46], "knee": [98, 30], "ankle": [110, 88], "tw": 3.5, "sw": 3, "kr": 3.5, "k": "rear", "forward": "up",
         "foot": _pad(110, 88)},
        {"hip": [50, 46], "knee": [30, 30], "ankle": [20, 88], "tw": 3.5, "sw": 3, "kr": 3.5, "k": "rear", "forward": "up",
         "foot": _pad(20, 88)},
        {"hip": [84, 52], "knee": [106, 36], "ankle": [118, 91], "tw": 4, "sw": 3.5, "kr": 4, "k": "hull", "forward": "up",
         "foot": _pad(118, 91)},
        {"hip": [44, 52], "knee": [22, 36], "ankle": [10, 91], "tw": 4, "sw": 3.5, "kr": 4, "k": "hull", "forward": "up",
         "foot": _pad(10, 91)},
    ],
    "parts": [
        {"leg": 0}, {"leg": 1},
        # far outrigger struts (braced variant only)
        {"p": [[48, 56], [52, 56], [46, 89], [42, 89]], "k": "dark", "only": "braced"},
        {"p": [[76, 56], [80, 56], [86, 89], [82, 89]], "k": "dark", "only": "braced"},
        {"r": [34, 26, 4, 12], "k": "metal"}, {"r": [33, 24, 6, 2], "k": "dark"},
        {"p": [[30, 38], [92, 36], [104, 46], [98, 60], [34, 62], [24, 50]], "k": "hull", "rivet": True, "pv": [24, 46]},
        {"r": [32, 56, 64, 5], "k": "dark", "rivet": True},
        {"r": [30, 48, 68, 2], "k": "trim"},
        {"p": [[40, 40], [48, 40], [44, 47]], "k": "trim"},
        {"p": [[96, 40], [110, 42], [113, 50], [98, 55]], "k": "hull"},
        {"r": [104, 44, 3, 2], "k": "glow"}, {"r": [109, 46, 2, 2], "k": "glow"},
        # Nebelwerfer pod
        {"r": [56, 33, 16, 5], "k": "dark", "grp": "turret"},
        {"r": [44, 16, 40, 18], "k": "metal", "rivet": True, "ph": [6, 12], "grp": "turret"},
        {"r": [82, 18, 3, 3], "k": "dark", "grp": "turret"}, {"r": [82, 23, 3, 3], "k": "dark", "grp": "turret"},
        {"r": [82, 28, 3, 3], "k": "dark", "grp": "turret"},
        {"leg": 2}, {"leg": 3},
        # near outrigger struts
        {"p": [[38, 58], [42, 58], [30, 89], [24, 89]], "k": "metal", "only": "braced"},
        {"p": [[88, 58], [92, 58], [108, 89], [102, 89]], "k": "metal", "only": "braced"},
        {"r": [20, 88, 14, 4], "k": "dark", "only": "braced"}, {"r": [99, 88, 14, 4], "k": "dark", "only": "braced"},
    ],
    "anchors": {
        "feet": [64, 95], "hull": [64, 48], "glacis": [100, 44], "viewport": [106, 45],
        "stacks": [[36, 24]],
        "muzzles": {"rocket_pod": {"p": [86, 24], "grp": "turret"}},
        "attach": {},
    },
}

# ---- Befehls-IV Kaiserstuhl: command walker, 105mm StuH, ECM dish, radio mast ----
KOMMANDANT = {
    "w": 112, "h": 106, "idle_ms": 160,
    "legs": [
        {"hip": [40, 64], "knee": [44, 82], "ankle": [36, 100], "tw": 7, "sw": 6, "kr": 6, "k": "rear",
         "foot": [[22, 100], [50, 100], [54, 105], [18, 105]]},
        {"hip": [66, 64], "knee": [74, 83], "ankle": [68, 100], "tw": 7.5, "sw": 7, "kr": 7, "k": "hull", "piston": True,
         "foot": [[54, 100], [84, 100], [90, 105], [50, 105]], "toe": [86, 102, 4, 3]},
    ],
    "parts": [
        {"r": [30, 0, 1, 24], "k": "metal"}, {"r": [36, 6, 1, 18], "k": "metal"},
        {"p": [[12, 10], [22, 5], [25, 22], [15, 21]], "k": "metal"}, {"r": [22, 12, 8, 4], "k": "dark"},
        {"r": [40, 10, 5, 18], "k": "metal"}, {"r": [39, 8, 7, 2], "k": "dark"},
        {"leg": 0},
        {"r": [32, 58, 46, 9], "k": "metal", "rivet": True},
        {"p": [[18, 26], [82, 26], [96, 40], [94, 62], [22, 62], [14, 40]], "k": "hull", "rivet": True, "pv": [24, 48], "ph": [18]},
        {"r": [20, 48, 72, 2], "k": "trim"},
        {"p": [[26, 32], [34, 32], [30, 40]], "k": "trim"},
        {"r": [24, 38, 12, 8], "k": "dark", "ph": [4]},
        {"r": [30, 22, 8, 6], "k": "dark"},
        {"p": [[44, 16], [66, 16], [70, 20], [70, 27], [42, 27]], "k": "hull", "rivet": True},
        {"r": [60, 20, 7, 2], "k": "glow"}, {"r": [48, 13, 3, 4], "k": "metal"}, {"r": [54, 13, 3, 4], "k": "metal"},
        # 105mm StuH in the casemate
        {"r": [92, 36, 8, 12], "k": "metal", "ph": [5], "grp": "gun"},
        {"r": [100, 40, 9, 4], "k": "metal", "grp": "gun"},
        {"r": [107, 38, 5, 8], "k": "dark", "grp": "gun"},
        {"leg": 1},
    ],
    "anchors": {
        "feet": [54, 105], "hull": [56, 44], "glacis": [88, 38], "viewport": [63, 21],
        "stacks": [[42, 8]],
        "muzzles": {"assault_105": {"p": [111, 42], "grp": "gun"}},
        "attach": {"mast": [34, 22], "ecm": [18, 13]},
    },
}

CHASSIS = {
    "vanguard": VANGUARD,
    "goliath": GOLIATH,
    "falke": FALKE,
    "donner": DONNER,
    "kommandant": KOMMANDANT,
    "moloch": MOLOCH,
    "ragnarok": RAGNAROK,  # boss-only; not one of the six playable chassis
}

# Extra palette sheets: (chassis, livery name in raster.FACTIONS)
LIVERIES = [("kommandant", "blackclaw")]

# Variant sheets: name -> (base chassis, flags, braced)
VARIANTS = {
    "moloch_spent": ("moloch", ("spent",), False),
    "donner_braced": ("donner", ("braced",), True),
}

# Battle attachments (rendered once per faction into fx/): name -> (w, h, parts)
ATTACHMENTS = {
    "slab": (40, 56, [
        {"p": [[4, 4], [34, 0], [38, 52], [2, 55]], "k": "hull", "rivet": True, "pv": [12, 24], "ph": [18, 36]},
        {"r": [6, 22, 30, 2], "k": "trim"},
        {"r": [0, 50, 40, 6], "k": "dark"},
    ]),
    "mast": (8, 42, [
        {"r": [2, 28, 4, 14], "k": "metal"}, {"r": [2, 15, 3, 14], "k": "metal"}, {"r": [3, 4, 2, 12], "k": "metal"},
        {"r": [1, 26, 6, 2], "k": "dark"}, {"r": [1, 13, 6, 2], "k": "dark"},
        {"r": [2, 0, 4, 4], "k": "glow"},
    ]),
    "rangefinder": (32, 9, [
        {"r": [3, 3, 26, 3], "k": "metal", "pv": [13]},
        {"r": [13, 5, 6, 4], "k": "dark"},
        {"r": [0, 1, 5, 6], "k": "metal"}, {"r": [27, 1, 5, 6], "k": "metal"},
        {"r": [1, 2, 2, 3], "k": "lens"}, {"r": [29, 2, 2, 3], "k": "lens"},
    ]),
}
