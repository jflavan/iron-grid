class_name BattleTimeline
extends RefCounted

## Translates SkirmishResult and live BattleSession TurnSteps into presentation beats for BattleStage.
## Supports both pre-resolved playback and live interactive turn-by-turn command selection.

const WEAPON_CATEGORIES := ["ATTACK", "WEAPON", "BALLISTIC", "ARTILLERY", "THERMAL"]
const SOFTENERS := ["krupp_plate", "gyro_thruster", "ablative_shield"]
const ROW_ATTACK := 0
const ROW_TECH := 1
const ROW_DEFEND := 2
const ROW_RETREAT := 3

var beats: Array[Dictionary] = []
var start_hull: Dictionary = {}
var end_hull: Dictionary = {}
var start_energy: Dictionary = {}
var end_energy: Dictionary = {}
var coalition_side: String = "atk"
var headline: String = ""
var ending: String = "repelled"

static func is_weapon(category: String) -> bool:
	return category in WEAPON_CATEGORIES

static func command_row_for_step(step: SkirmishEngine.TurnStep) -> int:
	match step.command_type:
		SkirmishEngine.CommandType.ATTACK:
			return ROW_ATTACK
		SkirmishEngine.CommandType.TECH:
			return ROW_TECH
		SkirmishEngine.CommandType.DEFEND:
			return ROW_DEFEND
		SkirmishEngine.CommandType.RETREAT:
			return ROW_RETREAT
	return ROW_ATTACK

static func build(result: SkirmishEngine.SkirmishResult) -> BattleTimeline:
	var tl := BattleTimeline.new()
	tl.coalition_side = "atk" if result.attacker.faction == MechData.Faction.PLAYER else "def"
	tl.start_hull = {"atk": result.atk_armor_before, "def": result.def_armor_before}
	tl.start_energy = {"atk": result.atk_energy_before, "def": result.def_energy_before}
	for step in result.steps:
		tl.append_step(step, result)
	tl.sync_ending_from_result(result)
	return tl

func append_step(step: SkirmishEngine.TurnStep, result: SkirmishEngine.SkirmishResult) -> Dictionary:
	var actor := step.actor_side if step.actor_side != "" else ("atk" if step.actor_faction == result.attacker.faction else "def")
	var target := "def" if actor == "atk" else "atk"
	var is_coalition := (actor == coalition_side)
	var beat := {
		"step": step.step_index,
		"round": step.round_number,
		"actor": actor,
		"actor_faction": step.actor_faction,
		"ability_id": step.ability_id,
		"ability_name": step.ability_name,
		"ability_category": step.ability_category,
		"command_row": command_row_for_step(step) if is_coalition else -1,
		"is_support_only": step.is_support_only,
		"needs_followup": false,
		"damage": step.damage_dealt,
		"is_miss": step.is_miss,
		"is_crit": step.is_crit,
		"escaped": step.escaped,
		"escape_failed": step.escape_failed,
		"target": target,
		"status_text": step.status_text,
		"hull_after": {
			"atk": maxi(1, step.atk_hp_after),
			"def": maxi(1, step.def_hp_after)
		},
		"energy_after": {
			"atk": step.atk_en_after,
			"def": step.def_en_after
		},
		"soften_from": step.soften_from,
	}
	beats.append(beat)
	return beat

func sync_ending_from_result(result: SkirmishEngine.SkirmishResult) -> void:
	end_hull = {"atk": result.atk_armor_after, "def": result.def_armor_after}
	end_energy = {"atk": result.atk_energy_after, "def": result.def_energy_after}
	headline = result.summary_headline
	if result.attacker_destroyed and result.defender_destroyed:
		ending = "destroy_both"
	elif result.defender_destroyed:
		ending = "destroy_def"
	elif result.attacker_destroyed:
		ending = "destroy_atk"
	elif result.defender_pushed_back or result.attacker_won_clash:
		ending = "pushback"
	else:
		ending = "repelled"
