extends Node

## Dev-only battle screen preview (not reachable from the main menu).
## Run: godot --path . res://scenes/dev/BattlePreview.tscn
##   Left/Right  attacker chassis      Up/Down  defender chassis
##   T  terrain    E  elevation (attacker high/level/low)    F  swap factions
##   D  low-hull defender (destruction ending)    I  toggle interactive vs playback
##   S  1x/2x speed (BattleScreen)    A  Auto-Pilot    Space  skip / confirm

const CHASSIS := ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]
const TERRAINS := [
	GridTileData.TerrainType.PLAIN, GridTileData.TerrainType.ROAD, GridTileData.TerrainType.RIVER,
	GridTileData.TerrainType.FOREST, GridTileData.TerrainType.CITY, GridTileData.TerrainType.MOUNTAIN,
]

var atk_i := 0
var def_i := 5
var terrain_i := 0
var elev_mode := 1 # 0 attacker high, 1 level, 2 attacker low
var atk_faction := 0
var low_hull := false
var interactive_mode := true
var screen: BattleScreen
var _hud: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	screen = BattleScreen.new()
	layer.add_child(screen)
	screen.resolution_confirmed.connect(func(_r): _replay())
	_hud = Label.new()
	_hud.position = Vector2(8, 4)
	_hud.add_theme_color_override("font_color", Color("#3ad06a"))
	layer.add_child(_hud)
	_replay()

func _replay(jump_to: int = -1) -> void:
	var fac := atk_faction as MechData.Faction
	var atk := GlobalState.create_mech_instance(CHASSIS[atk_i], fac, "PREV-1 (Attacker)", Vector2i(3, 2), "pa")
	var dfn := GlobalState.create_mech_instance(CHASSIS[def_i], (1 - atk_faction) as MechData.Faction, "PREV-2 (Defender)", Vector2i(4, 2), "pd")
	if low_hull:
		dfn.current_armor = 6
	var elev_from: int = [3, 1, 1][elev_mode]
	var elev_to: int = [1, 1, 3][elev_mode]
	var from := GridTileData.new(Vector2i(3, 2), TERRAINS[terrain_i], elev_from)
	var target := GridTileData.new(Vector2i(4, 2), TERRAINS[terrain_i], elev_to)
	if interactive_mode and jump_to < 0:
		screen.start_session(SkirmishEngine.create_session(atk, dfn, from, target, true))
	else:
		screen.start_showdown(SkirmishEngine.resolve_skirmish(atk, dfn, from, target, false))
	if jump_to >= 0:
		var guard := 0
		while screen.stage.beat_idx < jump_to and not screen.stage.finished and guard < 20000:
			screen.stage.advance(1.0 / 60.0)
			guard += 1
	_hud.text = "ATK %s  DEF %s  TERRAIN %s  ELEV %s  ATK-FACTION %s%s  MODE:%s   [←→ ↑↓ T E F D I 1-6 S A Space]" % [
		CHASSIS[atk_i], CHASSIS[def_i], BattleLayout.BACKDROP_BY_TERRAIN[TERRAINS[terrain_i]],
		["high", "level", "low"][elev_mode], ["coalition", "syndikat"][atk_faction],
		"  LOW-HULL" if low_hull else "", "INTERACTIVE" if interactive_mode else "PLAYBACK"]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_LEFT:
			atk_i = (atk_i + CHASSIS.size() - 1) % CHASSIS.size()
		KEY_RIGHT:
			atk_i = (atk_i + 1) % CHASSIS.size()
		KEY_UP:
			if screen.stage.phase == BattleStage.PHASE_COMMAND_SELECT:
				return
			def_i = (def_i + CHASSIS.size() - 1) % CHASSIS.size()
		KEY_DOWN:
			if screen.stage.phase == BattleStage.PHASE_COMMAND_SELECT:
				return
			def_i = (def_i + 1) % CHASSIS.size()
		KEY_T:
			terrain_i = (terrain_i + 1) % TERRAINS.size()
		KEY_E:
			elev_mode = (elev_mode + 1) % 3
		KEY_F:
			atk_faction = 1 - atk_faction
		KEY_D:
			low_hull = not low_hull
		KEY_I:
			interactive_mode = not interactive_mode
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_replay(int(event.keycode - KEY_1))
			get_viewport().set_input_as_handled()
			return
		_:
			return
	_replay()
	get_viewport().set_input_as_handled()
