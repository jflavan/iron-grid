class_name MusicCues
extends RefCounted

## Which piece of music plays where. Every id is a file `assets/music/<id>.ogg`; MusicManager plays
## them. This is the one table to edit to re-score a scene.

const DIR := "res://assets/music/"

const TRACKS: PackedStringArray = [
	"overture",          # main menu
	"war_room",          # campaign list, mission briefings
	"scene_calm",        # camp and motor-pool scenes
	"scene_tense",       # records room, office, the capital's streets
	"scene_sorrow",      # Varnhalt burning, the causeway, the pass
	"battle_act1", "battle_act2", "battle_act3",
	"boss",              # the Ragnarök
	"victory", "defeat",
	"theme_coalition",   # skirmish theaters
	"theme_syndikat",    # Wolf's Pass: the Black Claw's own ground
	"ilse",              # Crown Boulevard, until she turns
	"turncoat",          # the Throne Gate, after the standard turns
	"epilogue",
]

const MENU := "overture"
const CAMPAIGN := "war_room"
const SKIRMISH := "theme_coalition"
const VICTORY := "victory"
const DEFEAT := "defeat"

## Cutscene backdrop id -> the music under it.
const BACKDROP: Dictionary = {
	"village_fire": "scene_sorrow",
	"briefing_room": "war_room",
	"field_camp": "scene_calm",
	"motor_pool": "scene_calm",
	"records_room": "scene_tense",
	"office": "scene_tense",
	"causeway": "scene_sorrow",
	"snow_pass": "scene_sorrow",
	"capital_street": "scene_tense",
	"throne_gate": "scene_tense",
	"parade_court": "victory",
	"memorial": "epilogue",
}

const ACT_BATTLE: Dictionary = {
	"ACT 1": "battle_act1",
	"ACT 2": "battle_act2",
	"ACT 3": "battle_act3",
}

static func path(id: String) -> String:
	return DIR + id + ".ogg"

static func for_backdrop(bg: String) -> String:
	return BACKDROP.get(bg, CAMPAIGN)

## The battle music of a story mission (its "music" key, else its act's theme); the skirmish
## theme for an empty `mission`.
static func for_battle(mission: Dictionary) -> String:
	if mission.is_empty():
		return SKIRMISH
	if mission.has("music"):
		return str(mission["music"])
	var act: String = str(mission.get("act", ""))
	for prefix: String in ACT_BATTLE:
		if act.begins_with(prefix):
			return ACT_BATTLE[prefix]
	return SKIRMISH

## What plays over the debrief. A mission's "end_music" overrides it: Wolf's Pass "wins" by
## losing, and should not sound like a victory.
static func for_outcome(mission: Dictionary, player_won: bool) -> String:
	if mission.has("end_music"):
		return str(mission["end_music"])
	return VICTORY if player_won else DEFEAT
