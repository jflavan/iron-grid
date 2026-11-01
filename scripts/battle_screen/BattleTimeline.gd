class_name BattleTimeline
extends RefCounted

## Pure translation of a SkirmishResult into presentation beats for the battle screen.
## Nothing here changes rules: every damage number comes straight from the BoutSteps.
##
## Beat keys: step, actor ("atk"/"def"), actor_faction, card_id, card_name, card_type,
## command_row (0 FIGHT, 2 ARMOR, 3 TACTIC, -1 = Syndikat action: no command box),
## needs_followup, damage, target, capture_text, hull_after {atk, def} (held at >= 1),
## soften_from (defensive card whose effect blunts this hit, or "").

const WEAPON_TYPES := ["BALLISTIC", "ARTILLERY", "THERMAL"]
const SOFTENERS := ["krupp_plate", "gyro_thruster", "ablative_shield"]
const ROW_FIGHT := 0
const ROW_WEAPON := 1 # reserved for the interactive follow-up phase
const ROW_ARMOR := 2
const ROW_TACTIC := 3

var beats: Array[Dictionary] = []
var start_hull: Dictionary = {}
var end_hull: Dictionary = {}
var coalition_side: String = "atk"
var headline: String = ""
var ending: String = "repelled"

static func is_weapon(card_type: String) -> bool:
	return card_type in WEAPON_TYPES

static func command_row_for(card_type: String) -> int:
	if is_weapon(card_type):
		return ROW_FIGHT
	return ROW_ARMOR if card_type == "ARMOR" else ROW_TACTIC

static func capture_text_for(step: SkirmishEngine.BoutStep) -> String:
	var n := step.flipped_slots.size()
	if n == 0:
		return ""
	if step.combo_type == "TACTICAL PLUS":
		return "TACTICAL PLUS OVERLOAD: %d FLIPPED" % n
	return "OVERMATCH: %d SYSTEM%s CAPTURED" % [n, "" if n == 1 else "S"]

static func build(result: SkirmishEngine.SkirmishResult) -> BattleTimeline:
	var tl := BattleTimeline.new()
	tl.coalition_side = "atk" if result.attacker.faction == MechData.Faction.PLAYER else "def"
	tl.start_hull = {"atk": result.atk_armor_before, "def": result.def_armor_before}
	tl.end_hull = {"atk": result.atk_armor_after, "def": result.def_armor_after}
	tl.headline = result.summary_headline
	if result.attacker_destroyed and result.defender_destroyed:
		tl.ending = "destroy_both"
	elif result.defender_destroyed:
		tl.ending = "destroy_def"
	elif result.attacker_destroyed:
		tl.ending = "destroy_atk"
	elif result.defender_pushed_back or result.attacker_won_clash:
		tl.ending = "pushback"
	else:
		tl.ending = "repelled"

	var running := {"atk": result.atk_armor_before, "def": result.def_armor_before}
	var pending_soften := {"atk": "", "def": ""}
	for step in result.steps:
		var actor := "atk" if step.actor_faction == result.attacker.faction else "def"
		var target := "def" if actor == "atk" else "atk"
		var card: EquipmentCard = step.card_placed
		var damage: int = step.atk_damage_dealt if actor == "atk" else step.def_damage_dealt
		running[target] = running[target] - damage
		var soften: String = pending_soften[target]
		pending_soften[target] = ""
		if card.card_id in SOFTENERS:
			pending_soften[actor] = card.card_id
		var is_coalition := (actor == tl.coalition_side)
		tl.beats.append({
			"step": step.step_index,
			"actor": actor,
			"actor_faction": step.actor_faction,
			"card_id": card.card_id,
			"card_name": card.card_name,
			"card_type": card.category,
			"command_row": command_row_for(card.category) if is_coalition else -1,
			"needs_followup": not is_weapon(card.category),
			"damage": damage,
			"target": target,
			"capture_text": capture_text_for(step),
			"hull_after": {"atk": maxi(1, running["atk"]), "def": maxi(1, running["def"])},
			"soften_from": soften,
		})
	return tl
