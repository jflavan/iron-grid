class_name MechView
extends RefCounted

## One walker's presentation state inside BattleStage (replaces the 25-key Dictionary the stage and
## the weapon/support animations used to pass around).

var side: String = "atk"
var data: MechData
var chassis: String = ""
var sheet: String = ""              # lasting sprite sheet (a support TECH may switch to a variant)
var faction: int = 0
var mirrored: bool = false
var dir: int = 1                    # +1 faces right, -1 faces left
var base: Vector2 = Vector2.ZERO
var pose: String = ""
var offset: Vector2 = Vector2.ZERO
var white: bool = false
var idle_shift_ms: float = 0.0

# lasting state for the rest of the fight
var slab: bool = false
var armed: bool = false
var rangefinder_on: bool = false
var mast_on: bool = false
var jammed: bool = false
var dark: bool = false
var sink: float = 0.0
var end_offset: Vector2 = Vector2.ZERO

# per-frame effect state (reset every frame by BattleStage._animate)
var glitch: float = 0.0
var ghosts: Array = []
var glow: Color = Color(0, 0, 0, 0)
var attach: Dictionary = {}
var bricks_glow: float = 0.0
var sheet_vis: String = ""
