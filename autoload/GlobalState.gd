extends Node

## GlobalState Autoload
## Manages global campaign/mission selection, turn phase state, mech & TECH ability catalogs,
## map arena definitions, and combat telemetry logs.

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const BATTLEFIELD_SCENE := "res://scenes/Battlefield.tscn"
const STORY_SCENE := "res://scenes/Story.tscn"

enum TurnPhase {
	PLAYER_PHASE = 0,
	RESOLUTION_PHASE = 1,
	AI_PHASE = 2,
	GAME_OVER = 3
}

signal phase_changed(new_phase: TurnPhase, turn_num: int)
signal log_added(entry: String)

var current_phase: TurnPhase = TurnPhase.PLAYER_PHASE
var turn_number: int = 1
var selected_map_index: int = 0
var last_battle_winner: int = -1 # -1 = None, 0 = Player, 1 = AI
var last_battle_reason: String = ""
var last_battle_title: String = ""   # debrief headline override (a scripted story ending); "" = the stock one

## Story mode: index into StoryCampaign.chapters() of the chapter being played, -1 in a skirmish theater.
var story_chapter: int = -1
## Where the Story scene resumes: "list" (campaign screen), "pre" (run the chapter) or "post" (debrief after a won mission).
var story_stage: String = "list"
## Campaign progress when the running story mission was launched (StoryScreen tells a replay of a
## cleared chapter from a first win by it).
var story_cleared_at_launch: int = 0
var boss_catalog: Dictionary = {}

var ability_catalog: Dictionary = {}
var chassis_catalog: Dictionary = {}
var maps: Array[MapDefinition] = []
var combat_log: Array[String] = []

## Master seed for live battle dice. -1 (the shipping default) leaves every battle unseeded.
## When >= 0, each battle gets its own seed derived from this one and a running counter, so a
## whole mission's hit/crit/variance/retreat rolls replay exactly. Tests set it per mission; the
## BATTLE_SEED environment variable sets it for a hand-played session.
var battle_seed: int = -1
var _battle_seed_counter: int = 0

func _ready() -> void:
	var env_seed := OS.get_environment("BATTLE_SEED")
	if env_seed.is_valid_int():
		set_battle_seed(int(env_seed))
	ability_catalog = AbilityCatalog.build()
	chassis_catalog = ChassisCatalog.build(ability_catalog)
	boss_catalog = ChassisCatalog.build_bosses(ability_catalog)
	maps = MapCatalog.build()

## The story mission being played ({} in a skirmish theater or on a cutscene chapter).
func story_mission() -> Dictionary:
	if story_chapter < 0:
		return {}
	var ch: Dictionary = StoryCampaign.chapter(story_chapter)
	return ch if ch.get("kind", "") == "mission" else {}

## The map Battlefield loads: the story mission's own map, else the selected theater.
func active_map() -> MapDefinition:
	var ms := story_mission()
	if not ms.is_empty():
		return ms["map"]
	return maps[clampi(selected_map_index, 0, maps.size() - 1)]

func leave_story() -> void:
	story_chapter = -1
	story_stage = "list"

func set_battle_seed(p_seed: int) -> void:
	battle_seed = p_seed
	_battle_seed_counter = 0

## Seed for the next live BattleSession (-1 = unseeded).
func next_battle_seed() -> int:
	if battle_seed < 0:
		return -1
	_battle_seed_counter += 1
	return absi(battle_seed * 7919 + _battle_seed_counter) % 2147483647

func reset_battle_state() -> void:
	current_phase = TurnPhase.PLAYER_PHASE
	turn_number = 1
	_battle_seed_counter = 0  # every mission replays from its first battle seed
	last_battle_winner = -1
	last_battle_reason = ""
	last_battle_title = ""
	combat_log.clear()
	add_log("SYSTEM BOOT // OPERATION: IRON GRID TACTICAL LINK ESTABLISHED.")

func set_phase(new_phase: TurnPhase) -> void:
	current_phase = new_phase
	phase_changed.emit(current_phase, turn_number)

func add_log(msg: String) -> void:
	var prefix := "[T%02d] " % turn_number
	var full_msg := prefix + msg
	combat_log.append(full_msg)
	if combat_log.size() > 60:
		combat_log.pop_front()
	log_added.emit(full_msg)

func get_phase_name() -> String:
	match current_phase:
		TurnPhase.PLAYER_PHASE:
			return "PLAYER COMMAND PHASE"
		TurnPhase.RESOLUTION_PHASE:
			return "COMBAT ENCOUNTER PHASE"
		TurnPhase.AI_PHASE:
			return "SYNDICATE AI PHASE"
		TurnPhase.GAME_OVER:
			return "OPERATION CONCLUDED"
	return "UNKNOWN"

func create_mech_instance(chassis_id: String, faction: MechData.Faction, callsign: String, pos: Vector2i, unique_suffix: String = "") -> MechData:
	var template: MechData = boss_catalog.get(chassis_id, chassis_catalog.get(chassis_id, chassis_catalog["vanguard"]))
	var inst := template.duplicate_mech()
	inst.unit_id = "%s_%s_%s" % [chassis_id, "P" if faction == MechData.Faction.PLAYER else "E", unique_suffix]
	inst.faction = faction
	inst.callsign = callsign
	inst.grid_pos = pos
	return inst
