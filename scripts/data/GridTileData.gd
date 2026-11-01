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
	elevation = clampi(p_elevation, 0, 4)
	is_objective = p_objective
	objective_label = p_label

func get_terrain_name() -> String:
	match terrain_type:
		TerrainType.PLAIN:
			return "Open Plain"
		TerrainType.ROAD:
			return "Transit Road"
		TerrainType.RIVER:
			return "River Ford"
		TerrainType.FOREST:
			return "Trench Timber"
		TerrainType.CITY:
			return "Fortified City"
		TerrainType.MOUNTAIN:
			return "Mountain Crag"
	return "Unknown"

func get_terrain_short_code() -> String:
	match terrain_type:
		TerrainType.PLAIN: return "PLN"
		TerrainType.ROAD: return "ROD"
		TerrainType.RIVER: return "RIV"
		TerrainType.FOREST: return "TRN"
		TerrainType.CITY: return "CTY"
		TerrainType.MOUNTAIN: return "MTN"
	return "???"

## Base fuel required to enter this terrain (before elevation climb & mech chassis efficiency).
func get_base_fuel_cost() -> int:
	match terrain_type:
		TerrainType.ROAD:
			return 1 # Paved highway / rail bed allows rapid movement
		TerrainType.PLAIN:
			return 2 # Standard open ground
		TerrainType.CITY:
			return 2 # Paved urban sector
		TerrainType.FOREST:
			return 3 # Rubble, timber & trench lines slow walkers
		TerrainType.RIVER:
			return 4 # Deep mud & water drag heavily on diesel turbines
		TerrainType.MOUNTAIN:
			return 5 # Steep rocky crags require maximum torque
	return 2

## Defense modifier (%) granted to a unit occupying this terrain.
func get_defense_modifier_pct() -> int:
	match terrain_type:
		TerrainType.ROAD:
			return 0 # Exposed transit lane
		TerrainType.PLAIN:
			return 5 # Minor hull-down depression
		TerrainType.RIVER:
			return -15 # Bogged down in water, exposed hull & reduced mobility
		TerrainType.FOREST:
			return 15 # Concealment & timber revetments
		TerrainType.CITY:
			return 25 # Reinforced concrete bunkers & ferro-steel ruins
		TerrainType.MOUNTAIN:
			return 30 # Heavy granite cover & turret-down slopes
	return 0

## Attack modifier (%) granted when initiating or fighting from this terrain.
func get_attack_modifier_pct() -> int:
	match terrain_type:
		TerrainType.ROAD:
			return 5 # Stable firing platform
		TerrainType.PLAIN:
			return 0
		TerrainType.RIVER:
			return -15 # Unstable footing & water spray degrades targeting
		TerrainType.FOREST:
			return 5 # Ambush firing lanes
		TerrainType.CITY:
			return 10 # Elevated firing ports & bracing struts
		TerrainType.MOUNTAIN:
			return 15 # Commanding observation & artillery vantage
	return 0

## Evasion modifier (%) granted by this terrain in combat.
func get_evasion_modifier_pct() -> int:
	match terrain_type:
		TerrainType.RIVER:
			return -10
		TerrainType.FOREST:
			return 8
		TerrainType.CITY, TerrainType.MOUNTAIN:
			return 10
		_:
			return 0

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
