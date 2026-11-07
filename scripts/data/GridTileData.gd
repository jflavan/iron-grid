class_name GridTileData
extends RefCounted

## Represents a single grid cell on the dieselpunk tactical battlefield.
## Includes Terrain Type, Elevation (0..4), Fuel Cost, and Attack/Defense Combat Modifiers.

enum TerrainType {
	PLAIN = 0,
	ROAD = 1,
	RIVER = 2,
	FOREST = 3,
	CITY = 4,
	MOUNTAIN = 5
}

## Highest supported elevation level (4 = 400 m peak).
const MAX_ELEVATION: int = 4

var coords: Vector2i = Vector2i.ZERO
var terrain_type: TerrainType = TerrainType.PLAIN
var elevation: int = 1 # 0 = Riverbed/Basin, 1 = Lowland, 2 = Hill/Plateau, 3 = High Ridge, 4 = Peak
var is_objective: bool = false
var objective_label: String = ""
var controlled_by: int = -1 # -1 = Neutral, 0 = Player, 1 = AI

func _init(
	p_coords: Vector2i = Vector2i.ZERO,
	p_terrain: TerrainType = TerrainType.PLAIN,
	p_elevation: int = 1,
	p_objective: bool = false,
	p_label: String = ""
) -> void:
	coords = p_coords
	terrain_type = p_terrain
	elevation = clampi(p_elevation, 0, MAX_ELEVATION)
	is_objective = p_objective
	objective_label = p_label

func get_terrain_name() -> String:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("name", "Unknown")

func get_terrain_short_code() -> String:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("short", "???")

## Base fuel required to enter this terrain (before elevation climb & mech chassis efficiency).
func get_base_fuel_cost() -> int:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("fuel", 2)

## Defense modifier (%) granted to a unit occupying this terrain.
func get_defense_modifier_pct() -> int:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("def", 0)

## Attack modifier (%) granted when initiating or fighting from this terrain.
func get_attack_modifier_pct() -> int:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("atk", 0)

## Evasion modifier (%) granted by this terrain in combat.
func get_evasion_modifier_pct() -> int:
	return TerrainDefs.TABLE.get(terrain_type, {}).get("eva", 0)

func get_elevation_meters() -> int:
	return elevation * 100

func get_tactical_summary() -> String:
	var def_str := "%+d%%" % get_defense_modifier_pct()
	var atk_str := "%+d%%" % get_attack_modifier_pct()
	return "%s (Elev %dm) | Fuel: %d | ATK %s | DEF %s" % [
		get_terrain_name(),
		get_elevation_meters(),
		get_base_fuel_cost(),
		atk_str,
		def_str
	]
