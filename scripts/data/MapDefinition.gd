class_name MapDefinition
extends RefCounted

## Defines a complete Battle Arena map including its strategic mode (Offense, Defense, Pitched Battle),
## grid layout of terrain & elevations, objective nodes, and starting unit deployments.

enum StrategyMode {
	PITCHED_BATTLE = 0,
	DEFENSE = 1,
	OFFENSE = 2
}

var map_id: String = ""
var map_name: String = ""
var subtitle: String = ""
var strategy_mode: StrategyMode = StrategyMode.PITCHED_BATTLE
var turn_limit: int = 10
var briefing_text: String = ""
var tactical_tip: String = ""

var width: int = 10
var height: int = 8

# 2D arrays or dictionaries indexed by Vector2i
var terrain_codes: PackedStringArray = PackedStringArray() # Row strings e.g. "P P R C M ..."
var elevation_rows: PackedStringArray = PackedStringArray() # Row strings e.g. "1 1 0 2 3 ..."

# Array of Dictionary: { "pos": Vector2i, "label": String, "owner": int }
var objectives: Array[Dictionary] = []

# Array of Dictionary: { "chassis": String, "callsign": String, "pos": Vector2i, "faction": int }
var spawns: Array[Dictionary] = []

# OFFENSE maps: objective nodes whose capture (held through the enemy turn) wins the mission
var hq_positions: Array[Vector2i] = []

func get_strategy_name() -> String:
	match strategy_mode:
		StrategyMode.PITCHED_BATTLE:
			return "PITCHED BATTLE"
		StrategyMode.DEFENSE:
			return "FORTIFIED DEFENSE"
		StrategyMode.OFFENSE:
			return "BLITZKRIEG OFFENSE"
	return "TACTICAL ENGAGEMENT"

func get_victory_condition_text() -> String:
	match strategy_mode:
		StrategyMode.PITCHED_BATTLE:
			return "Destroy all Syndicate mechs, hold every Objective City at turn end, OR control the majority when Turn %d ends." % turn_limit
		StrategyMode.DEFENSE:
			return "Hold at least one Citadel node until Turn %d ends OR eliminate all attackers." % turn_limit
		StrategyMode.OFFENSE:
			return "Capture a Syndicate HQ Bunker and hold it through the enemy turn, OR destroy all defenders within %d Turns." % turn_limit
	return "Eliminate enemy forces."


# Row string -> split tokens, so terrain_at / elevation_at do not re-split a row for every cell.
var _row_cache: Dictionary = {}

func _tokens(row: String) -> PackedStringArray:
	var t: Variant = _row_cache.get(row)
	if t == null:
		t = row.split(" ", false)
		_row_cache[row] = t
	return t

## Terrain at (x, y); cells missing from the row strings default to PLAIN.
func terrain_at(x: int, y: int) -> GridTileData.TerrainType:
	if y < 0 or y >= terrain_codes.size():
		return GridTileData.TerrainType.PLAIN
	var row: PackedStringArray = _tokens(terrain_codes[y])
	if x < 0 or x >= row.size():
		return GridTileData.TerrainType.PLAIN
	return TerrainDefs.parse_code(row[x])

## Elevation at (x, y) as written (GridTileData clamps it); missing cells default to 1.
func elevation_at(x: int, y: int) -> int:
	if y < 0 or y >= elevation_rows.size():
		return 1
	var row: PackedStringArray = _tokens(elevation_rows[y])
	if x < 0 or x >= row.size():
		return 1
	return int(row[x])

## Data problems of this map, one message each; empty when the map is well-formed.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var label: String = map_id if map_id != "" else map_name
	if width <= 0 or height <= 0:
		errs.append("%s: size %dx%d" % [label, width, height])
		return errs
	if terrain_codes.size() != height:
		errs.append("%s: %d terrain rows for height %d" % [label, terrain_codes.size(), height])
	if elevation_rows.size() != height:
		errs.append("%s: %d elevation rows for height %d" % [label, elevation_rows.size(), height])
	for y in mini(terrain_codes.size(), height):
		var codes: PackedStringArray = _tokens(terrain_codes[y])
		if codes.size() != width:
			errs.append("%s: terrain row %d has %d cells, width is %d" % [label, y, codes.size(), width])
		for code in codes:
			if not TerrainDefs.is_known_code(code):
				errs.append("%s: terrain row %d has unknown code '%s'" % [label, y, code])
	for y in mini(elevation_rows.size(), height):
		var elevs: PackedStringArray = _tokens(elevation_rows[y])
		if elevs.size() != width:
			errs.append("%s: elevation row %d has %d cells, width is %d" % [label, y, elevs.size(), width])
		for e in elevs:
			if not e.is_valid_int() or int(e) < 0 or int(e) > GridTileData.MAX_ELEVATION:
				errs.append("%s: elevation row %d has bad value '%s'" % [label, y, e])
	for obj in objectives:
		var p: Vector2i = obj.get("pos", Vector2i(-1, -1))
		if not _in_bounds(p):
			errs.append("%s: objective at %s out of bounds" % [label, p])
	for p in hq_positions:
		if not _in_bounds(p):
			errs.append("%s: HQ at %s out of bounds" % [label, p])
	var seen: Dictionary = {}
	for sp in spawns:
		var p: Vector2i = sp.get("pos", Vector2i(-1, -1))
		if not _in_bounds(p):
			errs.append("%s: spawn at %s out of bounds" % [label, p])
		elif seen.has(p):
			errs.append("%s: duplicate spawn at %s" % [label, p])
		seen[p] = true
	return errs

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < width and p.y >= 0 and p.y < height
