class_name BalanceProbe
extends RefCounted
## Balance-experiment knobs and recorders, driven by tests/balance.gd.
## Defaults match the shipped rules; per-skirmish recording only runs when `enabled` is set.

static var enabled: bool = false

# Entrenchment / City healing values, indexed by MechData.Faction (0 = PLAYER, 1 = AI)
static var def_pct: Array[int] = [15, 15]
static var card: Array[int] = [1, 1]
static var patch: Array[int] = [8, 8]
static var upkeep: Array[int] = [12, 12]

static var entrench_actions: Array[int] = [0, 0]
static var patch_healed: Array[int] = [0, 0]
static var upkeep_healed: Array[int] = [0, 0]
static var skirmishes: Array = []

static func reset() -> void:
	entrench_actions = [0, 0]
	patch_healed = [0, 0]
	upkeep_healed = [0, 0]
	skirmishes = []

static func record_skirmish(atk: MechData, dfn: MechData, from_tile: GridTileData, target_tile: GridTileData) -> void:
	if not enabled:
		return
	var rec := {
		"def_faction": int(dfn.faction), "atk_chassis": atk.chassis_id, "def_chassis": dfn.chassis_id,
		"terrain": target_tile.get_terrain_name(), "entrenched": dfn.is_entrenched,
	}
	var a1 := atk.duplicate_mech(); var d1 := dfn.duplicate_mech()
	var real := SkirmishEngine.resolve_skirmish(a1, d1, from_tile, target_tile, false)
	rec["dmg_def"] = real.total_dmg_to_defender; rec["dmg_atk"] = real.total_dmg_to_attacker
	rec["atk_won"] = real.attacker_won_clash; rec["def_dead"] = real.defender_destroyed; rec["atk_dead"] = real.attacker_destroyed
	if dfn.is_entrenched:
		var a2 := atk.duplicate_mech(); var d2 := dfn.duplicate_mech()
		d2.is_entrenched = false
		var cf := SkirmishEngine.resolve_skirmish(a2, d2, from_tile, target_tile, false)
		rec["cf_dmg_def"] = cf.total_dmg_to_defender; rec["cf_dmg_atk"] = cf.total_dmg_to_attacker
		rec["cf_atk_won"] = cf.attacker_won_clash; rec["cf_def_dead"] = cf.defender_destroyed; rec["cf_atk_dead"] = cf.attacker_destroyed
	skirmishes.append(rec)
