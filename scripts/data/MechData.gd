class_name MechData
extends RefCounted

## Core Data Structure for an Armored Fighting Walker (AFW / Mech).
## Tracks name, grid position, faction, hull integrity (HP), reactor energy (EN/MP),
## armor rating (DEF), firepower (ATK), speed (SPD), evasion (EVA), crit chance (CRIT),
## fuel capacity & fuel usage profile, and the 3-ability TECH Loadout.

## WAIT / REFUEL order and City Depot resupply (applied by Battlefield; read by the HUD advice and the
## Rules of Engagement page so the numbers never drift).
const WAIT_FUEL: int = 5
const WAIT_ENERGY: int = 4
const CITY_FUEL: int = 4
const CITY_ENERGY: int = 3

enum Faction {
	PLAYER = 0, # 8th Iron Coalition (Olive / Amber)
	AI = 1      # Kriegs-Syndikat Red (Crimson / Gunmetal)
}

var unit_id: String = ""
var unit_name: String = ""
var callsign: String = ""
var chassis_id: String = "vanguard" # vanguard, goliath, falke, donner, kommandant, moloch
var chassis_class: String = "Medium Assault Walker"
var faction: Faction = Faction.PLAYER

var grid_pos: Vector2i = Vector2i.ZERO
var facing: Vector2i = Vector2i(1, 0) # Cardinal isometric facing: (1,0)=SE, (0,1)=SW, (-1,0)=NW, (0,-1)=NE

# Core RPG Combat & Engineering Ratings
var max_armor: int = 100       # Total hull structural points (HP)
var current_armor: int = 100   # Current remaining structural integrity
var armor_rating: int = 28     # Armor plating mitigation & defense power rating (DEF)
var firepower: int = 32        # Primary weapons offensive rating (ATK)
var speed: int = 22            # Initiative, turn order & escape speed rating (SPD)
var evasion: int = 8           # Base evasion percentage (EVA %)
var crit_chance: int = 10      # Base critical hit percentage (CRIT %)

# Reactor Energy Pool (MP-style resource for TECH/SYSTEMS abilities)
var max_energy: int = 14
var current_energy: int = 14
var passive_energy_regen: int = 3

# Fuel & Map Mobility System
var max_fuel: int = 14         # Maximum diesel-turbine fuel capacity
var current_fuel: int = 14     # Remaining fuel for movement
var fuel_efficiency_mod: int = 0 # -1 = Light All-Terrain, 0 = Standard, +1 = Heavy Surcharge on rough ground
var passive_refuel: int = 4    # Diesel generator recharge at start of each turn
var fuel_usage: int = 2        # Diesel fuel usage multiplier (doubled from 1 to 2)
var amphibious_gear: bool = false # Reduces River fuel penalty
var mountain_gear: bool = false   # Reduces Mountain climb fuel penalty

# Basic Weapon Animation ID + 3 Special TECH Abilities
var basic_weapon_id: String = "kwk_88"
var abilities: Array[CombatAbility] = []

# Turn State Flags
var has_moved: bool = false
var has_attacked: bool = false
var is_entrenched: bool = false
var lore_blurb: String = ""

func _init(
	p_id: String = "",
	p_name: String = "",
	p_callsign: String = "",
	p_chassis: String = "vanguard",
	p_class: String = "Medium Walker",
	p_faction: Faction = Faction.PLAYER,
	p_pos: Vector2i = Vector2i.ZERO,
	p_max_armor: int = 100,
	p_armor_rating: int = 28,
	p_firepower: int = 32,
	p_max_fuel: int = 12,
	p_fuel_mod: int = 0,
	p_refuel: int = 4,
	p_lore: String = "",
	p_speed: int = 22,
	p_evasion: int = 8,
	p_crit: int = 10,
	p_max_energy: int = 14,
	p_energy_regen: int = 3,
	p_basic_weapon: String = "kwk_88",
	p_facing: Vector2i = Vector2i(1, 0)
) -> void:
	unit_id = p_id
	unit_name = p_name
	callsign = p_callsign
	chassis_id = p_chassis
	chassis_class = p_class
	faction = p_faction
	grid_pos = p_pos
	max_armor = p_max_armor
	current_armor = p_max_armor
	armor_rating = p_armor_rating
	firepower = p_firepower
	max_fuel = p_max_fuel
	current_fuel = p_max_fuel
	fuel_efficiency_mod = p_fuel_mod
	passive_refuel = p_refuel
	lore_blurb = p_lore
	speed = p_speed
	evasion = p_evasion
	crit_chance = p_crit
	max_energy = p_max_energy
	current_energy = p_max_energy
	passive_energy_regen = p_energy_regen
	basic_weapon_id = p_basic_weapon
	facing = p_facing

## Calculates exact fuel needed for this mech to step from `from_tile` to `to_tile`.
## Hot path (every Dijkstra edge): plain ints, no Dictionary.
func get_step_fuel_cost(from_tile: GridTileData, to_tile: GridTileData) -> int:
	var t := _step_terms(from_tile, to_tile)
	return maxi(1, t.x + t.y + t.z) * fuel_usage

## The step cost split into the terms the HUD and Rules page show. base + chassis + climb == total.
## chassis_label: "HEAVY" / "LIGHT" (fuel_efficiency_mod off-road), "AMPHIB" (river with
## amphibious_gear), "CLIMB GEAR" (mountain with mountain_gear) or "" when no adjustment applies.
func get_step_fuel_breakdown(from_tile: GridTileData, to_tile: GridTileData) -> Dictionary:
	var t := _step_terms(from_tile, to_tile)
	var single_total: int = maxi(1, t.x + t.y + t.z)
	var total: int = single_total * fuel_usage
	var label: String = ""
	if to_tile.terrain_type == GridTileData.TerrainType.RIVER and amphibious_gear:
		label = "AMPHIB"
	elif to_tile.terrain_type == GridTileData.TerrainType.MOUNTAIN and mountain_gear:
		label = "CLIMB GEAR"
	elif t.y != 0:
		label = "HEAVY" if fuel_efficiency_mod > 0 else "LIGHT"
	var base_cost: int = t.x * fuel_usage
	var chassis_cost: int = (t.y + single_total - (t.x + t.y + t.z)) * fuel_usage
	var climb_cost: int = t.z * fuel_usage
	return {
		"base": base_cost, "terrain": to_tile.get_terrain_short_code(),
		# The 1-fuel floor is credited to the chassis term so the parts still add up to the total.
		"chassis": chassis_cost, "chassis_label": label,
		"climb": climb_cost, "total": total,
	}

## (terrain base, chassis adjustment, climb) before the 1-fuel floor.
func _step_terms(from_tile: GridTileData, to_tile: GridTileData) -> Vector3i:
	var base: int = to_tile.get_base_fuel_cost()
	var chassis: int = 0
	# Chassis-specific terrain adaptations
	if to_tile.terrain_type == GridTileData.TerrainType.RIVER and amphibious_gear:
		chassis = -2
	elif to_tile.terrain_type == GridTileData.TerrainType.MOUNTAIN and mountain_gear:
		chassis = -2
	elif to_tile.terrain_type != GridTileData.TerrainType.ROAD:
		chassis = fuel_efficiency_mod
	# Elevation climb penalty (+1 fuel per 100m of upward climb); mountain gear absorbs one level
	var climb_diff: int = maxi(0, to_tile.elevation - from_tile.elevation)
	var climb: int = maxi(0, climb_diff - 1) if mountain_gear else climb_diff
	return Vector3i(base, chassis, climb)

## Fuel the WAIT / REFUEL order adds right now (capped by the tank).
func wait_fuel_gain(fuel_now: int) -> int:
	return mini(WAIT_FUEL, max_fuel - fuel_now)

## Fuel regained at the start of this walker's next turn while standing on `tile`.
func upkeep_refuel(tile: GridTileData) -> int:
	var city: bool = tile != null and tile.terrain_type == GridTileData.TerrainType.CITY
	return passive_refuel + (CITY_FUEL if city else 0)

## Fuel this walker will have at the start of its next turn if it ends this turn on `tile` with
## `fuel_now`, optionally after a WAIT / REFUEL order. Battlefield applies exactly these rules.
func next_turn_fuel(fuel_now: int, tile: GridTileData, waited: bool) -> int:
	var f: int = fuel_now + (wait_fuel_gain(fuel_now) if waited else 0)
	return mini(max_fuel, f + upkeep_refuel(tile))

func is_alive() -> bool:
	return current_armor > 0

func is_order_complete() -> bool:
	return has_moved and has_attacked

func get_armor_ratio() -> float:
	return clampf(float(current_armor) / float(maxi(1, max_armor)), 0.0, 1.0)

func get_fuel_ratio() -> float:
	return clampf(float(current_fuel) / float(maxi(1, max_fuel)), 0.0, 1.0)

func get_energy_ratio() -> float:
	return clampf(float(current_energy) / float(maxi(1, max_energy)), 0.0, 1.0)

## Script variable names (everything declared with `var` above), read once from the property list so
## a field added to MechData is copied by duplicate_mech() without anyone remembering to update it.
static var _state_props: PackedStringArray = PackedStringArray()

static func _state_prop_names() -> PackedStringArray:
	if _state_props.is_empty():
		for prop in MechData.new().get_property_list():
			if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["name"] != "_state_props":
				_state_props.append(String(prop["name"]))
	return _state_props

## Independent copy of every field; the abilities are copied too (not shared).
func duplicate_mech() -> MechData:
	var copy := MechData.new()
	for n in _state_prop_names():
		if n != "abilities":
			copy.set(n, get(n))
	for a in abilities:
		copy.abilities.append(a.duplicate_ability())
	return copy

func get_facing_name() -> String:
	match facing:
		Vector2i(1, 0): return "SE"
		Vector2i(0, 1): return "SW"
		Vector2i(-1, 0): return "NW"
		Vector2i(0, -1): return "NE"
	return "SE"

func get_facing_arrow() -> String:
	match facing:
		Vector2i(1, 0): return "SE >"
		Vector2i(0, 1): return "SW v"
		Vector2i(-1, 0): return "NW <"
		Vector2i(0, -1): return "NE ^"
	return "SE >"

func set_facing(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	if absi(dir.x) >= absi(dir.y):
		facing = Vector2i(1 if dir.x > 0 else -1, 0)
	else:
		facing = Vector2i(0, 1 if dir.y > 0 else -1)
