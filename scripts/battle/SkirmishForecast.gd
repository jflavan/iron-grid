class_name SkirmishForecast
extends RefCounted

## Deterministic tactical forecasts with a cache. The HUD asks on every hover and the AI once per
## reachable tile x adjacent enemy, each a full simulated battle, so identical inputs are served from
## a two-generation cache (current + previous): hot entries survive a rotation, cold ones age out.
## SkirmishEngine.compute_forecast / forecast_shared / clear_forecast_cache forward here.

const FORECAST_CACHE_LIMIT: int = 4096  # entries per generation

## Current generation (new entries land here) and the one before it.
static var _forecast_cache: Dictionary = {}
static var _forecast_old: Dictionary = {}

static func clear_forecast_cache() -> void:
	_forecast_cache.clear()
	_forecast_old.clear()

## Every MechData field the simulation reads (and nothing it does not, so identical walkers share an
## entry); a per-unit stat change can never serve a stale forecast. Abilities are keyed by id: a
## CombatAbility's numbers come from the catalog, so one id is one definition.
## NOTE: must list every MechData/GridTileData field BattleSession reads (see _forecast_key for the
## tile and formation side); a field the engine reads that is missing here serves stale forecasts.
static func _mech_key(m: MechData) -> Array:
	var ability_ids: Array = []
	for ab in m.abilities:
		ability_ids.append(ab.ability_id)
	return [
		m.chassis_id, m.basic_weapon_id, int(m.faction), m.is_entrenched,
		m.current_armor, m.max_armor, m.current_energy, m.max_energy,
		m.firepower, m.armor_rating, m.speed, m.evasion, m.crit_chance, ability_ids,
	]

static func _forecast_key(attacker: MechData, defender: MechData, from_tile: GridTileData, target_tile: GridTileData, formation_context: Dictionary = {}) -> Array:
	var approach: Vector2i = target_tile.coords - from_tile.coords
	return [
		_mech_key(attacker), _mech_key(defender),
		int(from_tile.terrain_type), from_tile.elevation, int(target_tile.terrain_type), target_tile.elevation, target_tile.is_objective,
		Rules.entrench_def_pct(int(defender.faction)),
		approach, defender.facing,
		int(formation_context.get("atk_allies_adj", 0)),
		int(formation_context.get("def_allies_adj", 0)),
		bool(formation_context.get("is_pincer", false)),
		int(formation_context.get("atk_suppression", 0)),
	]

## Computes a fast, deterministic tactical forecast before committing to an engagement.
static func compute_forecast(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData,
	formation_context: Dictionary = {}
) -> Dictionary:
	var copy: Dictionary = forecast_shared(attacker, defender, from_tile, target_tile, formation_context).duplicate()
	copy["tactical_tags"] = (copy["tactical_tags"] as Array).duplicate()
	return copy

static func _store(key: Array, forecast: Dictionary) -> void:
	if _forecast_cache.size() >= FORECAST_CACHE_LIMIT:
		_forecast_old = _forecast_cache
		_forecast_cache = {}
	_forecast_cache[key] = forecast

## compute_forecast without the defensive copy: returns the cached dictionary itself, so the caller
## must treat it as read-only. For hot read-only loops (AI scoring runs one per launch x target).
static func forecast_shared(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData,
	formation_context: Dictionary = {}
) -> Dictionary:
	var key: Array = _forecast_key(attacker, defender, from_tile, target_tile, formation_context)
	var cached: Variant = _forecast_cache.get(key)
	if cached != null:
		return cached
	cached = _forecast_old.get(key)
	if cached != null:
		_store(key, cached) # promote: still hot
		return cached
	# A deterministic, non-applying session only reads the walkers (every write goes to its own
	# CombatantState copies and SkirmishResult; MechData/CombatAbility are written solely by
	# apply_to_units, which is not called here), so no defensive duplicate_mech() is needed.
	var res := SkirmishEngine.resolve_skirmish(attacker, defender, from_tile, target_tile, false, true, formation_context, false)
	var favor: String
	if res.defender_destroyed and not res.attacker_destroyed:
		favor = "DECISIVE KILL PROJECTION"
	elif res.attacker_destroyed and not res.defender_destroyed:
		favor = "CRITICAL DANGER (LETHAL COUNTER)"
	elif res.attacker_won_clash:
		favor = "FAVORABLE ASSAULT"
	else:
		favor = "UNFAVORABLE EXCHANGE"
	var forecast := {
		"atk_mod_pct": res.atk_total_mod_pct,
		"def_mod_pct": res.def_total_mod_pct,
		"elev_diff": res.elev_diff,
		"est_dmg_to_def": res.total_dmg_to_defender,
		"est_dmg_to_atk": res.total_dmg_to_attacker,
		"atk_eff_fp": res.atk_effective_firepower,
		"def_eff_fp": res.def_effective_firepower,
		"atk_spd": res.atk_effective_speed,  # round-1 initiative speeds, the ones the queue was built from
		"def_spd": res.def_effective_speed,
		"first_striker": "ATTACKER" if res.first_striker == "atk" else "DEFENDER",
		"rounds_fought": res.rounds_fought,
		"attacker_won": res.attacker_won_clash,
		"win_favor": favor,
		"approach_summary": res.approach_summary,
		"approach_angle": res.approach_angle,
		"tactical_tags": res.tactical_tags.duplicate(),
	}
	_store(key, forecast)
	return forecast
