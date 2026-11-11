extends "res://tests/playtest.gd"

## Story mode checks: the campaign script is well-formed, progress saves and loads, the scripted
## effects (side switch, withdrawal, plot armour, scripted endings) do what the script relies on,
## and every story mission plays to a conclusion under the playtest's commanders with its dialog
## and triggers running.
##
## Run headless:  godot --headless --path . res://tests/StoryTests.tscn
## Env: STORY_POLICIES=greedy,turtle (commanders; default greedy), STORY_MISSIONS=m08,m11 (subset).

func _ready() -> void:
	if OS.get_environment("PLAYTEST_VERBOSE") != "":
		GlobalState.log_added.connect(func(entry: String): print("    LOG " + entry))
	Engine.time_scale = 12.0
	StoryProgress.path = "user://story_test_save.json"
	await get_tree().process_frame
	_check_campaign_data()
	_check_progress()
	_check_director()
	_check_music_cues()
	await _check_side_switch()
	await _check_scripted_ending()
	await _check_withdrawal_win_text()
	await _check_cancelled_skirmish()
	var policies: PackedStringArray = ["greedy", "tactical:1"]
	if OS.get_environment("STORY_POLICIES") != "":
		policies = OS.get_environment("STORY_POLICIES").split(",")
	var only: PackedStringArray = OS.get_environment("STORY_MISSIONS").split(",", false)
	var chapters := StoryCampaign.chapters()
	for policy in policies:
		for i in chapters.size():
			if chapters[i]["kind"] != "mission" or (not only.is_empty() and not only.has(chapters[i]["id"])):
				continue
			GlobalState.story_chapter = i
			_tactical = policy.begins_with("tactical")
			if _tactical:
				TacticalBot.jitter = 30.0
				TacticalBot.rng.seed = int(policy.get_slice(":", 1)) * 7919 + i
			await _play_mission(i, policy)
			_check_mission_outcome(chapters[i])
	GlobalState.leave_story()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(StoryProgress.path))
	_report_and_quit()

## "tactical:<seed>" commanders play through TacticalBot (the competent commander of tests/balance.gd)
## instead of the greedy one, and keep a must-survive pilot out of the line once its hull is low,
## as a player who reads "must survive" would.
var _tactical: bool = false
const HERO_CAUTION_HULL := 0.5

func _player_policy_step(bf: Battlefield, map_def: MapDefinition, stats: Dictionary) -> void:
	if not _tactical:
		super(bf, map_def, stats)
		return
	var sel: MechUnit = bf.selected_unit
	if sel != null and sel.mech_data.faction == MechData.Faction.PLAYER and sel.mech_data.is_order_complete():
		if TacticalBot.reface_step(bf):
			return
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.is_order_complete():
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.is_order_complete():
				bf._on_tile_clicked(u.mech_data.grid_pos)
				return
		return
	var heroes: Array = bf._story.mission.get("lose_if_lost", []) if bf._story != null else []
	var cautious: bool = heroes.has(sel.mech_data.pilot_id) and sel.mech_data.get_armor_ratio() < HERO_CAUTION_HULL
	var d := {"type": "WAIT_ENTRENCH"} if cautious else TacticalBot.choose_best_action(sel, bf.grid_map, bf.unit_container, map_def)
	bf._select_unit(sel)   # decision scoring cleared the highlights; restore the click targets
	# A garrison never walks off the objective it is holding: it strikes what comes next to it, or digs in
	var here := bf.grid_map.get_tile(sel.mech_data.grid_pos)
	if (map_def.strategy_mode == MapDefinition.StrategyMode.DEFENSE and here.is_objective and d["type"] != "WAIT_ENTRENCH"
			and TerrainGrid.manhattan(d["target_pos"], sel.mech_data.grid_pos) != 1):
		d = {"type": "WAIT_ENTRENCH"}
	if d["type"] == "WAIT_ENTRENCH" or not bf.grid_map.reachable_info.has(d["target_pos"]):
		stats["waits"] += 1
		bf._on_wait_refuel_requested()
	else:
		stats["moves"] += 1
		bf._on_tile_clicked(d["target_pos"])

func _check_campaign_data() -> void:
	var chapters := StoryCampaign.chapters()
	var errs := StoryCampaign.validate()
	_check(errs.is_empty(), "campaign script is well-formed: %s" % ", ".join(errs))
	var missions := 0
	for ch in chapters:
		if ch["kind"] == "mission":
			missions += 1
			_check(not (ch["pre"] as Array).is_empty() and not (ch["post"] as Array).is_empty(), "%s has briefing and debrief dialog" % ch["id"])
	_check(missions == 12, "twelve missions (got %d)" % missions)
	_check(chapters[0]["id"] == "prologue" and chapters[-1]["id"] == "epilogue", "the campaign opens on the prologue and closes on the epilogue")
	for id: String in StoryCast.CAST.keys():
		_check(StoryCast.portrait(id) != null, "portrait for '%s' exists" % id)
	_check(MechSpriteBank.get_livery_sheet("kommandant", 1, "blackclaw") != MechSpriteBank.get_sheet("kommandant", 1), "the Black Claw livery has its own sheet")
	_check(MechSpriteBank.get_livery_sheet("vanguard", 1, "blackclaw") == MechSpriteBank.get_sheet("vanguard", 1), "a chassis without the livery falls back to its faction sheet")
	_check(not ChassisCatalog.ORDER.has("ragnarok") and GlobalState.boss_catalog.has("ragnarok"), "the Ragnarök is a story-only chassis")
	_check(GlobalState.maps.size() == 3, "the skirmish theaters are untouched by the story maps")

func _check_progress() -> void:
	StoryProgress.reset()
	_check(StoryProgress.cleared() == 0, "a reset campaign has nothing cleared")
	StoryProgress.mark_cleared(2)
	_check(StoryProgress.cleared() == 3, "clearing chapter 2 unlocks chapter 3")
	StoryProgress.mark_cleared(0)
	_check(StoryProgress.cleared() == 3, "replaying an early chapter never lowers progress")
	var f := FileAccess.open(StoryProgress.path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	_check(StoryProgress.cleared() == 0, "a corrupt save reads as a fresh campaign")
	StoryProgress.reset()

func _check_director() -> void:
	var d := StoryDirector.new({"lose_if_lost": ["leon"], "win_if_down": "grau", "win_text": "done"})
	_check(d.verdict([]).is_empty(), "director: no verdict while everyone stands")
	_check(d.verdict(["mira"]).is_empty(), "director: losing another pilot is not a verdict")
	_check(d.verdict(["leon"]).get("winner", -1) == 1, "director: losing a required pilot fails the mission")
	_check(d.verdict(["grau"]).get("reason", "") == "done", "director: the target's fall wins with the mission's text")
	d.forced = {"winner": 0, "reason": "scripted", "title": "T"}
	_check(d.verdict(["leon"]).get("reason", "") == "scripted", "director: a scripted ending outranks the other rules")
	var a := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A", Vector2i.ZERO)
	var b := GlobalState.create_mech_instance("falke", MechData.Faction.AI, "B", Vector2i(1, 0))
	b.plot_armor = 1
	b.current_armor = 3
	var flat := GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.PLAIN, 1)
	var session := SkirmishEngine.create_session(a, b, flat, flat, false, 7, {})
	session.auto_resolve()
	session.apply_to_units()
	_check(b.current_armor >= 1 and b.is_alive(), "plot armour keeps a story pilot's walker standing (hull %d)" % b.current_armor)
	_check(not session.result.defender_destroyed and not session.result.summary_headline.contains("DESTROYED"),
		"plot armour: the battle result does not report a walker that is still standing as destroyed (%s)" % session.result.summary_headline)

func _story_battlefield(id: String) -> Battlefield:
	GlobalState.story_chapter = StoryCampaign.index_of(id)
	var bf := await _spawn_battlefield(0)
	while bf.ui_overlay.story_dialog_open():
		bf.ui_overlay.advance_story_dialog(true)
	return bf

## The music table: every cue names a real track, every track is used, and the files are all
## there (or none are: a checkout without the music is silent, not broken).
func _check_music_cues() -> void:
	var used: Dictionary = {MusicCues.MENU: true, MusicCues.CAMPAIGN: true, MusicCues.SKIRMISH: true, MusicCues.VICTORY: true, MusicCues.DEFEAT: true}
	for id: String in MusicCues.BACKDROP.values() + MusicCues.ACT_BATTLE.values():
		used[id] = true
	for ch in StoryCampaign.chapters():
		used[MusicCues.for_backdrop(str(ch.get("bg", "")))] = true
		if ch["kind"] == "mission":
			used[MusicCues.for_battle(ch)] = true
			used[MusicCues.for_outcome(ch, true)] = true
		for t: Dictionary in ch.get("triggers", []):
			for e: Dictionary in t.get("effects", []):
				if e.has("music"):
					used[e["music"]] = true
	for id: String in used:
		_check(MusicCues.TRACKS.has(id), "music: cue '%s' is a known track" % id)
	var present: int = 0
	for id: String in MusicCues.TRACKS:
		_check(used.has(id), "music: track '%s' is used somewhere" % id)
		if FileAccess.file_exists(MusicCues.path(id)):
			present += 1
	_check(present == 0 or present == MusicCues.TRACKS.size(), "music: all %d track files are present, or none (found %d)" % [MusicCues.TRACKS.size(), present])
	_check(MusicCues.for_battle({}) == MusicCues.SKIRMISH, "music: a skirmish theater plays the skirmish theme")
	_check(MusicCues.for_battle(StoryCampaign.chapter(StoryCampaign.index_of("m01"))) == "battle_act1", "music: a mission without its own cue plays its act's theme")
	_check(MusicCues.for_battle(StoryCampaign.chapter(StoryCampaign.index_of("m12"))) == "boss", "music: the last mission plays the boss theme")
	_check(MusicCues.for_outcome(StoryCampaign.chapter(StoryCampaign.index_of("m08")), true) == MusicCues.DEFEAT, "music: Wolf's Pass ends on the defeat theme though the mission counts as cleared")
	MusicManager.play("overture")
	MusicManager.play("")
	_check(MusicManager.current == "", "music: stopping leaves nothing current")

## Mission 11's reveal: the Black Claw joins the Coalition, Wolfram becomes Konrad, the Garde arrives.
func _check_side_switch() -> void:
	var bf := await _story_battlefield("m11")
	var uc := bf.unit_container
	var wolfram := uc.unit_of_pilot("wolfram")
	_check(wolfram != null and wolfram.mech_data.faction == MechData.Faction.AI and wolfram.mech_data.livery == "blackclaw", "m11: Wolfram starts on the Syndikat side in black")
	_check(MusicManager.current == "battle_act3", "m11: the battle opens on the act's theme (got '%s')" % MusicManager.current)
	# The gate cannot be won before the reveal: the debrief and the last mission depend on it
	for hq in bf.current_map_def.hq_positions:
		bf.grid_map.get_tile(hq).controlled_by = 0
	_check(not bf._check_victory_conditions(true), "m11: holding the Throne Gate before the reveal does not end the mission")
	for hq in bf.current_map_def.hq_positions:
		bf.grid_map.get_tile(hq).controlled_by = 1
	var players_before := uc.get_faction_units(MechData.Faction.PLAYER).size()
	var foes_before := uc.get_faction_units(MechData.Faction.AI).size()
	var claws := uc.select_units({"group": "claw"}).size()
	var leon := uc.unit_of_pilot("leon")
	leon.mech_data.grid_pos = wolfram.mech_data.grid_pos + Vector2i(-1, 0)
	bf._execute_unit_attack(leon, wolfram, 0)
	while bf.ui_overlay.story_dialog_open():
		bf.ui_overlay.advance_story_dialog(true)
	_check(not bf.ui_overlay.skirmish_modal.visible, "m11: the duel is called off by the reveal")
	_check(MusicManager.current == "turncoat", "m11: the music turns with the standard (got '%s')" % MusicManager.current)
	_check(GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE, "m11: play resumes in the player's phase after the reveal")
	_check(uc.unit_of_pilot("wolfram") == null and uc.unit_of_pilot("konrad") == wolfram, "m11: Wolfram's walker is now Konrad's")
	_check(wolfram.mech_data.faction == MechData.Faction.PLAYER and wolfram.mech_data.callsign.begins_with("KONRAD"), "m11: Konrad fights for the Coalition")
	_check(uc.get_faction_units(MechData.Faction.PLAYER).size() == players_before + claws, "m11: the whole Black Claw group changed sides")
	_check(uc.get_faction_units(MechData.Faction.AI).size() == foes_before - claws + 2, "m11: two Garde walkers reinforce the gate")
	var seen: Dictionary = {}
	for u in uc.units:
		_check(not seen.has(u.mech_data.grid_pos), "m11: reinforcement %s has its own tile" % u.mech_data.callsign)
		seen[u.mech_data.grid_pos] = true
	_check(bf._story.has_fired("reveal"), "m11: the reveal is recorded, so its fallbacks stay quiet")
	_check(wolfram.mech_data.plot_armor == 1, "m11: Konrad is kept standing for the debrief")
	StoryProgress.reset()
	for hq in bf.current_map_def.hq_positions:
		bf.grid_map.get_tile(hq).controlled_by = 0
	_check(bf._check_victory_conditions(true) and GlobalState.last_battle_winner == 0, "m11: after the reveal, holding the Throne Gate wins")
	_check(StoryProgress.cleared() == StoryCampaign.index_of("m11") + 1, "m11: the win is saved the moment the mission ends")
	await _free_battlefield(bf)

## Mission 3: when Ilse withdraws as the last Syndikat walker, the win is worded by the map, not as
## "all walkers destroyed".
func _check_withdrawal_win_text() -> void:
	var bf := await _story_battlefield("m03")
	var uc := bf.unit_container
	for u in uc.get_faction_units(MechData.Faction.AI):
		if u.mech_data.pilot_id != "ilse":
			uc.remove_destroyed_unit(u)
	uc.unit_of_pilot("ilse").mech_data.current_armor = 1
	bf._story_poll({}, func(_f: bool): bf._check_victory_conditions())
	while bf.ui_overlay.story_dialog_open():
		bf.ui_overlay.advance_story_dialog(true)
	_check(uc.unit_of_pilot("ilse") == null, "m03: Ilse withdraws when her Spinne is crippled")
	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER and GlobalState.last_battle_winner == 0, "m03: her withdrawal as the last enemy wins the mission")
	_check(GlobalState.last_battle_reason == bf.current_map_def.win_text and not GlobalState.last_battle_reason.contains("destroyed"),
		"m03: the win is not reported as every walker destroyed (%s)" % GlobalState.last_battle_reason)
	await _free_battlefield(bf)

## Mission 8 ends by script when Leon goes down, and it counts as the story moving on.
func _check_scripted_ending() -> void:
	var bf := await _story_battlefield("m08")
	var leon := bf.unit_container.unit_of_pilot("leon")
	var wolfram := bf.unit_container.unit_of_pilot("wolfram")
	_check(leon.mech_data.plot_armor == 1, "m08: Leon has a second wind though the mission can go on without him")
	_check(bf._ai_holds_position(wolfram), "m08: Wolfram stands his ground on turn 1")
	GlobalState.turn_number = wolfram.mech_data.hold_until_turn
	_check(not bf._ai_holds_position(wolfram), "m08: Wolfram comes down the pass once his hold turn arrives")
	GlobalState.turn_number = 1
	leon.mech_data.current_armor = 0
	var down: Array = []
	bf._note_story_down(leon, down)
	bf.unit_container.remove_destroyed_unit(leon)
	bf._story_poll({"down": down}, func(_f: bool): bf._check_victory_conditions())
	while bf.ui_overlay.story_dialog_open():
		bf.ui_overlay.advance_story_dialog(true)
	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER, "m08: Leon going down ends the mission")
	_check(GlobalState.last_battle_winner == 0 and GlobalState.last_battle_title != "", "m08: the scripted ending lets the story continue under its own headline")
	_check(bf.ui_overlay._story_won(), "m08: the debrief offers CONTINUE")
	await _free_battlefield(bf)

## Mission 12: Grau's first shot at Leon is intercepted; Konrad falls and Grau is wounded.
func _check_cancelled_skirmish() -> void:
	var bf := await _story_battlefield("m12")
	var uc := bf.unit_container
	var grau := uc.unit_of_pilot("grau")
	var leon := uc.unit_of_pilot("leon")
	_check(grau.mech_data.plot_armor == 1, "m12: the Ragnarök cannot be brought down before Konrad's sacrifice")
	var hull := grau.mech_data.current_armor
	leon.mech_data.grid_pos = grau.mech_data.grid_pos + Vector2i(-1, 0)
	bf._execute_unit_attack(leon, grau, 0)
	while bf.ui_overlay.story_dialog_open():
		bf.ui_overlay.advance_story_dialog(true)
	_check(uc.unit_of_pilot("konrad") == null, "m12: Konrad takes the shot meant for Leon")
	_check(grau.mech_data.current_armor == hull - 75, "m12: Konrad's last shot breaches the Ragnarök")
	_check(GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and MechUnit.is_live(leon), "m12: the mission goes on with Leon alive")
	_check(grau.mech_data.plot_armor == 0, "m12: after the sacrifice the Ragnarök can fall")
	grau.mech_data.current_armor = 0
	var down: Array = []
	bf._note_story_down(grau, down)
	uc.remove_destroyed_unit(grau)
	bf._story_poll({"down": down}, func(_f: bool): bf._check_victory_conditions())
	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER and GlobalState.last_battle_winner == 0, "m12: the Ragnarök's fall wins the war with Garde walkers still standing")
	await _free_battlefield(bf)

## What the script promises about a mission that just ran under a commander.
func _check_mission_outcome(ch: Dictionary) -> void:
	match ch["id"]:
		"m08":
			_check(GlobalState.last_battle_winner == 0, "m08: every way the duel ends, the story continues")
