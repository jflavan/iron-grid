class_name Rules
extends RefCounted

## Turn-economy rule arithmetic shared by both factions (upkeep and the WAIT / REFUEL order), kept
## out of Battlefield so the node only orchestrates. BalanceProbe counters are updated here, in the
## same order as before the move.

## Start-of-phase upkeep for one walker on `tile`: clears last turn's orders, then (optionally)
## applies passive diesel refuel, reactor energy regen, plus City Depot resupply (+4 Fuel, +3 EN)
## and repairs (+12 Armor).
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
		var healed: int = mini(BalanceProbe.upkeep[int(m.faction)], m.max_armor - m.current_armor)
		m.current_armor += healed
		BalanceProbe.upkeep_healed[int(m.faction)] += healed
		if healed > 0:
			GlobalState.add_log("%s repaired +%d Armor at City Depot." % [m.callsign, healed])
	m.current_fuel = mini(m.max_fuel, m.current_fuel + refuel_amt)
	m.current_energy = mini(m.max_energy, m.current_energy + energy_amt)

## WAIT / REFUEL order shared by both factions: ends the walker's turn entrenched (+15% DEF),
## restores up to 5 Fuel and +4 Energy, and patches +8 Armor when holding a City (`tile`).
## Returns fuel gained.
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
		m.current_armor = mini(m.max_armor, m.current_armor + BalanceProbe.patch[int(m.faction)])
		BalanceProbe.patch_healed[int(m.faction)] += m.current_armor - before
	return gained_fuel
