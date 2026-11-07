class_name Rules
extends RefCounted

## Shipped turn-economy rules: the values a walker gains by entrenching, being patched up in a City
## or sitting out a turn, and the upkeep / WAIT arithmetic that applies them. The engine, Battlefield,
## the HUD and the Rules page all read the values through the accessors below, which let
## tests/balance.gd swap in experimental values per faction via BalanceProbe without production code
## depending on a test harness for its defaults. BalanceProbe counters are bumped here, in the same
## order as when this code lived in Battlefield.

## DEF bonus (%) an entrenched defender gets in a skirmish.
const ENTRENCH_DEF_PCT: int = 15
## Armor repaired by a WAIT / REFUEL order while holding a City (the field "patch").
const PATCH_ARMOR: int = 8
## Armor repaired by start-of-turn upkeep on a City tile.
const UPKEEP_ARMOR: int = 12

static func entrench_def_pct(faction: int) -> int:
	return BalanceProbe.def_pct[faction]

static func patch_armor(faction: int) -> int:
	return BalanceProbe.patch[faction]

static func upkeep_armor(faction: int) -> int:
	return BalanceProbe.upkeep[faction]

## Start-of-phase upkeep for one walker on `tile`: clears last turn's orders, then (optionally)
## applies passive diesel refuel, reactor energy regen, plus City Depot resupply (+CITY_ENERGY) and
## repairs (+UPKEEP_ARMOR).
static func apply_upkeep(m: MechData, tile: GridTileData, include_refuel: bool) -> void:
	m.has_moved = false
	m.has_attacked = false
	m.is_entrenched = false
	if not include_refuel:
		return
	var refuel_amt: int = m.upkeep_refuel(tile)
	var energy_amt: int = m.passive_energy_regen
	if tile != null and tile.terrain_type == GridTileData.TerrainType.CITY:
		energy_amt += MechData.CITY_ENERGY
		var healed: int = mini(upkeep_armor(int(m.faction)), m.max_armor - m.current_armor)
		m.current_armor += healed
		BalanceProbe.upkeep_healed[int(m.faction)] += healed
		if healed > 0:
			GlobalState.add_log("%s repaired +%d Armor at City Depot." % [m.callsign, healed])
	m.current_fuel = mini(m.max_fuel, m.current_fuel + refuel_amt)
	m.current_energy = mini(m.max_energy, m.current_energy + energy_amt)

## WAIT / REFUEL order shared by both factions: ends the walker's turn entrenched (+ENTRENCH_DEF_PCT
## DEF), restores up to WAIT_FUEL Fuel and WAIT_ENERGY Energy, and patches +PATCH_ARMOR when holding
## a City (`tile`). Returns fuel gained.
static func entrench(m: MechData, tile: GridTileData) -> int:
	m.has_moved = true
	m.has_attacked = true
	m.is_entrenched = true
	var gained_fuel: int = m.wait_fuel_gain(m.current_fuel)
	m.current_fuel += gained_fuel
	m.current_energy = mini(m.max_energy, m.current_energy + MechData.WAIT_ENERGY)
	BalanceProbe.entrench_actions[int(m.faction)] += 1
	if tile != null and tile.terrain_type == GridTileData.TerrainType.CITY:
		var before: int = m.current_armor
		m.current_armor = mini(m.max_armor, m.current_armor + patch_armor(int(m.faction)))
		BalanceProbe.patch_healed[int(m.faction)] += m.current_armor - before
	return gained_fuel
