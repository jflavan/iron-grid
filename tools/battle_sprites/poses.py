"""Named poses shared by every chassis: (name, body offset [lean, sink], gun recoil px)."""

DEFAULT_IDLE = [[0, 0], [0, 1], [1, 2], [1, 3], [1, 2], [0, 1]]

POSES = [
    ("brace", [0, 1], 0),
    ("chamber", [0, 1], -1),
    ("recoil0", [-3, 3], -6),
    ("recoil1", [-2, 2], -4),
    ("recoil2", [-1, 2], -2),
    ("recoil3", [0, 1], -1),
    ("hit", [0, 2], 0),
    ("stagger", [1, 4], 0),
    ("lunge", [6, 1], 0),
    ("angle", [-2, 2], 0),
]


def pose_table(defn, braced=False):
    """Ordered [(name, off, gun)] for one chassis (idle cycle first)."""
    idle = defn.get("idle", DEFAULT_IDLE)
    table = [("idle%d" % i, list(o), 0) for i, o in enumerate(idle)] + [(n, list(o), g) for n, o, g in POSES]
    if braced:
        # outriggers planted: the body is locked low, idle no longer bobs, recoil barely moves it
        table = [(n, [max(-1, min(1, o[0])), 3], g) for n, o, g in table]
    return table
