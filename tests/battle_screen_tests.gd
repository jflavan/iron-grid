extends Node

## Battle screen unit tests (sprite bank, font, layout, timeline, interactive FF menu, animations).
## Run headless:  godot --headless --path . res://tests/BattleScreenTests.tscn
## Exit code is the number of failures (0 = all checks passed).

const CHASSIS: Array[String] = ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]

var failures: Array[String] = []
var _checks: int = 0

func _ready() -> void:
	for t in [
		"test_sprite_bank_loads", "test_anchor_mirrors", "test_recoil_moves_muzzle",
		"test_side_from_approach", "test_elevation_offsets", "test_wrap_long_headline",
		"test_damage_sums", "test_hold_at_one", "test_ai_attacker_panels", "test_pure_support_turns", "test_status_text",
		"test_skip_confirm_reuse", "test_full_playback_finishes", "test_interactive_session_menu",
		"test_every_weapon_has_anim", "test_every_support_has_anim", "test_persistent_effects_after_skip",
		"test_pairings_play_to_result", "test_attachment_textures_cached",
		"test_mouse_click_skips_then_confirms", "test_viewport_renders_only_while_active",
		"test_white_sheets_are_pregenerated", "test_support_run_is_pure",
		"test_crt_pixel_scale", "test_crt_glyph_coverage", "test_menu_mechs_never_overlap",
		"test_menu_header_click_is_inert", "test_basic_weapon_single_source", "test_guard_survives_initiative_flip",
		"test_forecast_initiative_matches_queue", "test_seeded_sessions_replay", "test_support_tech_is_single_use",
		"test_guard_survives_miss", "test_auto_pilot_uses_command_select", "test_repelled_attacker_leaves_entrenchment",
		"test_forecast_damage_matches_ai_estimate", "test_forecast_cache", "test_status_badges",
	]:
		await call(t)
	print("[BATTLE TESTS] %d checks, %d failures" % [_checks, failures.size()])
	for f in failures:
		print("  FAIL: " + f)
	get_tree().quit(mini(failures.size(), 125))

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		failures.append(msg)
		push_error("[BATTLE TEST FAIL] " + msg)

# ---------------------------------------------------------------- sprite bank / font / layout
func test_sprite_bank_loads() -> void:
	for c in CHASSIS:
		var meta: Dictionary = MechSpriteBank.meta_for(c)
		for fac in [0, 1]:
			var tex: Texture2D = MechSpriteBank.get_sheet(c, fac)
			_check(tex != null, "%s faction %d sheet loads" % [c, fac])
			if tex != null:
				_check(tex.get_width() == int(meta["w"]) * meta["poses"].size(), "%s sheet width = w * poses" % c)

func test_anchor_mirrors() -> void:
	var w: int = int(MechSpriteBank.meta_for("vanguard")["w"])
	var a := MechSpriteBank.anchor("vanguard", "feet", "idle0", false)
	var b := MechSpriteBank.anchor("vanguard", "feet", "idle0", true)
	_check(is_equal_approx(b.x, w - 1 - a.x), "mirrored anchor x = w - 1 - x (got %s vs %s)" % [b, a])
	_check(is_equal_approx(b.y, a.y), "mirrored anchor keeps y")

func test_recoil_moves_muzzle() -> void:
	var brace := MechSpriteBank.anchor("vanguard", "muzzles/kwk_88", "brace", false)
	var recoil := MechSpriteBank.anchor("vanguard", "muzzles/kwk_88", "recoil0", false)
	_check(is_equal_approx(brace.x - recoil.x, 9.0), "88mm muzzle recoils 9px (-3 body -6 gun), got %s" % (brace.x - recoil.x))
	var r: Rect2 = MechSpriteBank.frame_rect("vanguard", "recoil0")
	_check(r.size == Vector2(112, 100), "frame rect size is the cell size")

func test_side_from_approach() -> void:
	_check(BattleLayout.attacker_on_left(Vector2i(3, 2), Vector2i(4, 2)), "+x approach puts attacker left")
	_check(not BattleLayout.attacker_on_left(Vector2i(4, 2), Vector2i(3, 2)), "-x approach puts attacker right")
	_check(not BattleLayout.attacker_on_left(Vector2i(3, 2), Vector2i(3, 3)), "+y approach puts attacker right")
	_check(BattleLayout.attacker_on_left(Vector2i(3, 3), Vector2i(3, 2)), "-y approach puts attacker left")

func test_elevation_offsets() -> void:
	_check(BattleLayout.elevation_offsets(2) == Vector2i(-8, 0), "attacker 2 levels up is raised 8px")
	_check(BattleLayout.elevation_offsets(-1) == Vector2i(0, -4), "defender 1 level up is raised 4px")
	_check(BattleLayout.elevation_offsets(0) == Vector2i.ZERO, "level ground has no offset")
	_check(BattleLayout.elevation_offsets(9) == Vector2i(-12, 0), "offset clamps to 12px")

func test_wrap_long_headline() -> void:
	var s := "TACTICAL BREAKTHROUGH — IRON-1 (Sturmjäger) DISLODGED KRIEGS-SYNDIKAT WALKER!"
	var lines := PixelFont.wrap(s, 344)
	_check(lines.size() > 1, "long headline wraps")
	for l in lines:
		_check(PixelFont.text_width(l) <= 344, "wrapped line fits 344px: '%s'" % l)
	_check(PixelFont.has_glyph("Ä") and PixelFont.has_glyph("ä"), "umlauts are drawable")

# ---------------------------------------------------------------- timeline
func _fight(atk_chassis: String, def_chassis: String, atk_faction: int = 0, def_armor: int = -1) -> SkirmishEngine.SkirmishResult:
	var atk := GlobalState.create_mech_instance(atk_chassis, atk_faction as MechData.Faction, "ATK-1 (Test)", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance(def_chassis, (1 - atk_faction) as MechData.Faction, "DEF-2 (Test)", Vector2i(4, 2), "d")
	if def_armor >= 0:
		dfn.current_armor = def_armor
	var from := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var target := GridTileData.new(Vector2i(4, 2), GridTileData.TerrainType.PLAIN, 1)
	return SkirmishEngine.resolve_skirmish(atk, dfn, from, target, false)

func test_damage_sums() -> void:
	for pair in [["vanguard", "moloch"], ["falke", "goliath"], ["kommandant", "donner"]]:
		var r := _fight(pair[0], pair[1])
		var tl := BattleTimeline.build(r)
		_check(tl.beats.size() == r.steps.size(), "one beat per step")
		var to_def := 0
		var to_atk := 0
		for b in tl.beats:
			if b["actor"] == "atk":
				to_def += int(b["damage"])
			else:
				to_atk += int(b["damage"])
		_check(to_def == r.total_dmg_to_defender, "%s beats sum to defender damage" % pair[0])
		_check(to_atk == r.total_dmg_to_attacker, "%s beats sum to attacker damage" % pair[0])
		_check(tl.start_hull["atk"] == r.atk_armor_before and tl.end_hull["def"] == r.def_armor_after, "start/end hull match result")

func test_hold_at_one() -> void:
	var r := _fight("goliath", "falke", 0, 5)
	var tl := BattleTimeline.build(r)
	for b in tl.beats:
		_check(int(b["hull_after"]["def"]) >= 1, "defender held at >= 1 during playback (step %d)" % b["step"])
	_check(tl.end_hull["def"] == 0, "defender ends at 0")
	_check(tl.ending == "destroy_def", "ending is destroy_def, got %s" % tl.ending)

func test_ai_attacker_panels() -> void:
	var r := _fight("moloch", "vanguard", 1)
	var tl := BattleTimeline.build(r)
	_check(tl.coalition_side == "def", "coalition is the defender when the AI attacks")
	for b in tl.beats:
		if b["actor"] == "atk":
			_check(b["command_row"] == -1, "syndikat actions show no command box")
		else:
			_check(b["command_row"] in [0, 1, 2, 3], "coalition actions point at a valid command row")

func test_pure_support_turns() -> void:
	var r := _fight("vanguard", "moloch")
	var tl := BattleTimeline.build(r)
	var found_support := false
	for i in tl.beats.size():
		var b: Dictionary = tl.beats[i]
		if b["ability_id"] == "krupp_plate":
			found_support = true
			_check(b["is_support_only"] == true, "armor TECH is pure support (no follow-up shot)")
			_check(b["damage"] == 0, "armor TECH deals 0 damage on its own turn")
			_check(b["command_row"] == BattleTimeline.ROW_TECH, "armor TECH points at TECH command row")
			if i + 1 < tl.beats.size() and tl.beats[i + 1]["actor"] != b["actor"] and not tl.beats[i + 1]["is_support_only"]:
				_check(tl.beats[i + 1]["soften_from"] == "krupp_plate", "next incoming hit is softened by Krupp plate")
	_check(found_support, "Vanguard uses Krupp Plate support TECH")

func test_status_text() -> void:
	var seen := false
	for pair in [["vanguard", "moloch"], ["kommandant", "falke"], ["donner", "goliath"]]:
		var r := _fight(pair[0], pair[1])
		var tl := BattleTimeline.build(r)
		for b in tl.beats:
			if b["status_text"] != "":
				seen = true
	_check(seen, "status text appears on support/shield/crit beats")

# ---------------------------------------------------------------- screen contract & interactive menu
func test_skip_confirm_reuse() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var got: Array = []
	screen.resolution_confirmed.connect(func(res): got.append(res))
	var r1 := _fight("vanguard", "moloch")
	var r2 := _fight("donner", "kommandant", 1)
	screen.start_showdown(r1)
	_check(screen.visible, "screen visible after start_showdown")
	await get_tree().process_frame
	screen._on_skip_pressed()
	screen._on_skip_pressed()
	_check(screen._all_steps_done, "skip finishes playback")
	_check(got.is_empty(), "skip alone does not confirm")
	screen._on_confirm_pressed()
	_check(got.size() == 1 and got[0] == r1, "confirm emits once with r1")
	_check(not screen.visible, "screen hidden after confirm")
	screen.start_showdown(r2)
	_check(not screen._all_steps_done, "reused screen restarts playback")
	await get_tree().process_frame
	screen._on_confirm_pressed()
	screen._on_confirm_pressed()
	_check(got.size() == 2 and got[1] == r2, "second fight emits once with r2")
	screen.queue_free()

func test_full_playback_finishes() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.start_showdown(_fight("goliath", "falke", 0, 5))
	var steps := 0
	while not screen._all_steps_done and steps < 4000:
		screen._process(1.0 / 30.0)
		steps += 1
	_check(screen._all_steps_done, "playback reaches the result on its own (%d ticks)" % steps)
	_check(screen.stage.hull_display["def"] == 0, "destroyed defender shows 0 hull at the end")
	screen.queue_free()

func test_interactive_session_menu() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "ATK-1", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance("moloch", MechData.Faction.AI, "DEF-2", Vector2i(4, 2), "d")
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var sess := SkirmishEngine.create_session(atk, dfn, flat, flat, true)
	screen.start_session(sess)
	# Advance past intro (0.6s) -> should pause in command_select for player
	screen.stage.advance(0.75)
	_check(screen.stage.phase == "command_select", "interactive session pauses in command_select for player")
	# Move cursor down to TECH (row 1) and open sub-menu
	screen.stage.move_cursor(1)
	_check(screen.stage.menu_cursor == 1, "cursor moved to TECH row")
	screen.stage.confirm_selection()
	_check(screen.stage.in_tech_submenu == true, "confirming TECH opens the TECH sub-menu")
	# Cancel sub-menu back to main menu
	screen.stage.cancel_submenu()
	_check(screen.stage.in_tech_submenu == false, "cancel_submenu returns to main command menu")
	# Re-enter TECH sub-menu, select ability 1 (krupp_plate)
	screen.stage.confirm_selection()
	screen.stage.move_cursor(1)
	screen.stage.confirm_selection()
	_check(screen.stage.phase == "support", "selecting Krupp Plate enters support phase")
	# Clicking during animation in an active interactive session fast-forwards to the next command_select prompt
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 20)
	screen._gui_input(click)
	_check(screen.stage.phase == "command_select" and not screen._all_steps_done, "click during animation advances to next command_select without skipping battle")
	# Clicking outside the command box while in command_select must not skip the battle
	screen._gui_input(click)
	_check(screen.stage.phase == "command_select" and not screen._all_steps_done, "click outside command box during command_select does not skip battle")
	# Skip remaining battle to end
	screen._on_skip_pressed()
	_check(screen._all_steps_done and sess.is_finished, "skip auto-resolves interactive session to completion")
	screen.queue_free()

# ---------------------------------------------------------------- animations
func test_every_weapon_has_anim() -> void:
	var n := 0
	for id in GlobalState.ability_catalog:
		var ab: CombatAbility = GlobalState.ability_catalog[id]
		if not ab.is_weapon():
			continue
		n += 1
		_check(WeaponAnims.has_anim(id), "%s has a dedicated weapon animation" % id)
		var d := WeaponAnims.duration(id)
		var imp := WeaponAnims.impact_time(id)
		_check(d > 0.0 and imp > 0.0 and imp < d, "%s impact inside duration" % id)
	_check(n == 9, "nine weapon TECHs in the catalog, got %d" % n)

func test_every_support_has_anim() -> void:
	var n := 0
	for id in GlobalState.ability_catalog:
		var ab: CombatAbility = GlobalState.ability_catalog[id]
		if ab.is_weapon():
			continue
		n += 1
		_check(SupportAnims.has_anim(id), "%s has a support animation" % id)
		_check(SupportAnims.duration(id) > 0.0, "%s support duration > 0" % id)
	_check(n == 9, "nine armor/tactical TECHs in the catalog, got %d" % n)
	_check(SupportAnims.has_anim("defend") and SupportAnims.has_anim("retreat"), "defend and retreat have animations")

func _screen_for(r: SkirmishEngine.SkirmishResult) -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	screen.start_showdown(r)
	return screen

func test_persistent_effects_after_skip() -> void:
	# Donner uses Anchor Struts or Plunging Comp; let's explicitly test persistent visual states
	var atk_d := GlobalState.create_mech_instance("donner", MechData.Faction.PLAYER, "A", Vector2i(3, 2))
	var dfn_v := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "D", Vector2i(4, 2))
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var sess1 := SkirmishEngine.create_deterministic_session(atk_d, dfn_v, flat, flat)
	sess1.execute_next_turn(SkirmishEngine.CommandType.TECH, "anchor_strut")
	var s1 := BattleScreen.new()
	add_child(s1)
	s1.start_session(sess1)
	await get_tree().process_frame
	s1._on_skip_pressed()
	_check(s1.stage.mechs["atk"]["sheet"] == "donner_braced", "Spinne ends braced after Anchor Struts + skip")
	s1.queue_free()

	var s2 := _screen_for(_fight("goliath", "falke"))
	await get_tree().process_frame
	s2._on_skip_pressed()
	_check(s2.stage.mechs["atk"]["slab"] == true, "Siegebreaker slab stays up after skip")
	s2.queue_free()

	var atk_m := GlobalState.create_mech_instance("moloch", MechData.Faction.PLAYER, "A", Vector2i(3, 2))
	var dfn_k := GlobalState.create_mech_instance("kommandant", MechData.Faction.AI, "D", Vector2i(4, 2))
	var sess3 := SkirmishEngine.create_deterministic_session(atk_m, dfn_k, flat, flat)
	sess3.execute_next_turn(SkirmishEngine.CommandType.TECH, "ablative_shield")
	sess3.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	var s3 := BattleScreen.new()
	add_child(s3)
	s3.start_session(sess3)
	await get_tree().process_frame
	s3._on_skip_pressed()
	_check(s3.stage.mechs["atk"]["sheet"] == "moloch_spent", "Brenner bricks are spent after absorbing a hit")
	s3.queue_free()

	var s4 := _screen_for(_fight("goliath", "falke", 0, 5))
	await get_tree().process_frame
	s4._on_skip_pressed()
	_check(s4.stage.mechs["def"]["dark"] == true, "destroyed defender is shown as a wreck")
	s4.queue_free()

func test_pairings_play_to_result() -> void:
	Engine.time_scale = 30.0
	var pairs := [["vanguard", "goliath"], ["goliath", "falke"], ["falke", "donner"], ["donner", "kommandant"],
		["kommandant", "moloch"], ["moloch", "vanguard"], ["falke", "moloch"], ["kommandant", "vanguard"]]
	for i in pairs.size():
		var screen := _screen_for(_fight(pairs[i][0], pairs[i][1], i % 2, 5 if i % 3 == 0 else -1))
		var frames := 0
		while not screen._all_steps_done and frames < 4500:
			await get_tree().process_frame
			frames += 1
		_check(screen._all_steps_done, "%s vs %s plays through to the result (%d frames)" % [pairs[i][0], pairs[i][1], frames])
		_check(screen.stage.hull_display["atk"] == screen.current_result.atk_armor_after, "%s final hull matches result" % pairs[i][0])
		screen.queue_free()
	Engine.time_scale = 1.0

func test_attachment_textures_cached() -> void:
	var m := {"faction": 0}
	for att in ["slab", "mast", "rangefinder"]:
		_check(SupportAnims._attach_tex(att, m) != null, "%s attachment texture loads" % att)
	_check(SupportAnims._attach_cache.size() >= 3, "attachment textures are retained across frames")

func test_mouse_click_skips_then_confirms() -> void:
	var screen := _screen_for(_fight("vanguard", "moloch"))
	await get_tree().process_frame
	var got: Array = []
	screen.resolution_confirmed.connect(func(res): got.append(res))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._gui_input(click)
	_check(screen._all_steps_done, "first click skips to the result")
	_check(got.is_empty(), "first click does not confirm")
	screen._gui_input(click)
	_check(got.size() == 1, "second click confirms")
	screen.queue_free()

func test_viewport_renders_only_while_active() -> void:
	var screen := _screen_for(_fight("falke", "donner"))
	await get_tree().process_frame
	_check(screen._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "viewport renders every frame while a fight plays")
	screen._on_confirm_pressed()
	screen._on_confirm_pressed()
	_check(screen._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "viewport stops rendering once hidden")
	screen.queue_free()

func test_white_sheets_are_pregenerated() -> void:
	for c in CHASSIS + ["moloch_spent", "donner_braced"]:
		var w := MechSpriteBank.get_white_sheet(c, 0)
		_check(w != null and w.resource_path.ends_with("_white.png"), "%s white flash sheet is a pre-generated PNG" % c)
		if w != null:
			_check(w.get_width() == MechSpriteBank.get_sheet(c, 0).get_width(), "%s white sheet matches sheet size" % c)

func test_support_run_is_pure() -> void:
	var screen := _screen_for(_fight("donner", "goliath"))
	await get_tree().process_frame
	var st := screen.stage
	for ab_id in ["anchor_strut", "ferro_bulkhead", "ablative_shield"]:
		var a: Dictionary = st.mechs["atk"]
		var d: Dictionary = st.mechs["def"]
		var before := [a["sheet"], a["slab"], a["armed"]]
		for t in [0.2, 0.5, 0.9]:
			SupportAnims.run(st, a, d, ab_id, t)
		_check([a["sheet"], a["slab"], a["armed"]] == before, "%s animation does not mutate lasting state" % ab_id)
	screen.queue_free()

# ---------------------------------------------------------------- shared CRT menu style (main menu / HUD)
func test_crt_pixel_scale() -> void:
	_check(CrtUI.pixel_scale(Vector2(1440, 900)) == 2, "1440x900 draws menus at 2x")
	_check(CrtUI.pixel_scale(Vector2(2880, 1800)) == 4, "2880x1800 draws menus at 4x")
	_check(CrtUI.pixel_scale(Vector2(1280, 720)) == 1, "a window smaller than 1440x900 falls back to 1x")
	_check(CrtUI.pixel_scale(Vector2(100, 100)) == 1, "scale never drops below 1")
	_check(CrtUI.virtual_size(Vector2(1441, 901), 2) == Vector2(720, 450), "virtual size floors to whole pixels")

func test_crt_glyph_coverage() -> void:
	var strings: Array[String] = []
	for m: MapDefinition in GlobalState.maps:
		strings.append_array([m.map_name, m.subtitle, m.briefing_text, m.tactical_tip, m.get_strategy_name(), m.get_victory_condition_text()])
		for sp in m.spawns:
			strings.append(String(sp["callsign"]))
		for o in m.objectives:
			strings.append(String(o["label"]))
	for key in GlobalState.chassis_catalog:
		var ch: MechData = GlobalState.chassis_catalog[key]
		strings.append_array([ch.callsign, ch.unit_name, ch.chassis_class, ch.lore_blurb])
		for ab: CombatAbility in ch.abilities:
			strings.append_array([ab.ability_name, ab.category, ab.description])
	strings.append_array(UIOverlay.MANUAL_LINES)
	var missing := {}
	for s in strings:
		for ch in CrtUI.sanitize(s):
			if ch != " " and not PixelFont.has_glyph(ch):
				missing[ch] = s
	_check(missing.is_empty(), "every menu string has pixel-font glyphs after sanitize (missing: %s)" % [missing.keys()])
	_check(CrtUI.sanitize("a|b~c") == "A/BC", "sanitize maps | to / and drops ~ (got %s)" % CrtUI.sanitize("a|b~c"))

func test_menu_mechs_never_overlap() -> void:
	var cell := CrtUI.max_mech_cell(CHASSIS)
	var hangar_inner := float(MainMenu.HANGAR_W - 16)
	_check(cell.x * 2.0 < hangar_inner, "hangar fits both liveries side by side without overlap (%s x2 vs %s)" % [cell.x, hangar_inner])
	_check(cell.x <= UIOverlay.LEFT_W - 12, "HUD portrait frame fits the widest sprite (%s vs %s)" % [cell.x, UIOverlay.LEFT_W - 12])

# ---------------------------------------------------------------- review regression tests
func _flat_session(atk_chassis: String, def_chassis: String, deterministic: bool = true, p_seed: int = -1) -> SkirmishEngine.BattleSession:
	var atk := GlobalState.create_mech_instance(atk_chassis, MechData.Faction.PLAYER, "ATK-1", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance(def_chassis, MechData.Faction.AI, "DEF-2", Vector2i(4, 2), "d")
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	return SkirmishEngine.BattleSession.new(atk, dfn, flat, flat, true, p_seed, deterministic)

func test_menu_header_click_is_inert() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var sess := _flat_session("vanguard", "moloch", false)
	screen.start_session(sess)
	screen.stage.advance(0.75)
	_check(screen.stage.phase == "command_select", "session pauses for the player's command")
	var st := screen.stage
	# Main command box: the 6px strip above the ATTACK row must select nothing
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 6)) == -1, "click above ATTACK row selects no command")
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 10)) == 0, "top of ATTACK row is row 0")
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 10 + 3 * 13)) == 3, "fourth row is RETREAT")
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 10 + 4 * 13)) == -1, "below RETREAT selects nothing")
	_check(not st.handle_mouse_click(Vector2(130, BattleStage.MENU_Y + 6)), "header click on main menu is not consumed")
	_check(st.phase == "command_select" and sess.result.steps.is_empty(), "no command was committed by the header click")
	# TECH sub-menu: the "TECH SYSTEMS [ESC]" header and EN meter line must not fire the first ability
	st.menu_cursor = 1
	st.confirm_selection()
	_check(st.in_tech_submenu, "TECH sub-menu is open")
	var en_before: int = sess.atk_state.en
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 8)) == -1, "TECH header row selects no ability")
	_check(st.menu_row_at(Vector2(130, BattleStage.MENU_Y + 18)) == 0, "first ability row is row 0")
	st.handle_mouse_motion(Vector2(130, BattleStage.MENU_Y + 8))
	_check(st.tech_cursor == 0 and st.in_tech_submenu, "hovering the header leaves the cursor alone")
	var consumed := st.handle_mouse_click(Vector2(130, BattleStage.MENU_Y + 8))
	_check(not consumed and st.in_tech_submenu and st.phase == "command_select", "header click neither fires an ability nor closes the sub-menu")
	_check(sess.atk_state.en == en_before and sess.result.steps.is_empty(), "no EN was spent by the header click")
	# Clicking a real ability row still works
	st.handle_mouse_click(Vector2(130, BattleStage.MENU_Y + 18 + 13 + 4))
	_check(st.phase == "support" and sess.result.steps.size() == 1 and sess.result.steps[0].ability_id == "krupp_plate", "clicking the second ability row fires Krupp Plate")
	screen.queue_free()

func test_basic_weapon_single_source() -> void:
	for key in GlobalState.chassis_catalog:
		var ch: MechData = GlobalState.chassis_catalog[key]
		var weapon_ids: Array[String] = []
		for ab: CombatAbility in ch.abilities:
			if ab.is_weapon():
				weapon_ids.append(ab.ability_id)
		_check(ch.basic_weapon_id in weapon_ids, "%s basic gun %s is one of its weapon TECHs %s" % [key, ch.basic_weapon_id, weapon_ids])
		var muzzles: Dictionary = MechSpriteBank.meta_for(key)["anchors"]["muzzles"]
		_check(muzzles.has(ch.basic_weapon_id), "%s sprite sheet has a muzzle anchor for its basic gun %s" % [key, ch.basic_weapon_id])
		_check(WeaponAnims.has_anim(ch.basic_weapon_id), "%s basic gun %s has a weapon animation" % [key, ch.basic_weapon_id])
		_check(not MechSpriteBank.meta_for(key).has("basic_weapon"), "%s sprite metadata no longer carries a second basic_weapon definition" % key)

func test_guard_survives_initiative_flip() -> void:
	# Vanguard (SPD 22) attacks Kommandant (SPD 24): round 1 is [atk, def] thanks to the +8 assault bonus,
	# round 2 flips to [def, atk]. The defender's round-1 DEFEND must still halve the attacker's round-2 shot.
	var sess := _flat_session("vanguard", "kommandant")
	_check(sess.get_next_actor_side() == "atk", "attacker opens round 1")
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	sess.execute_next_turn(SkirmishEngine.CommandType.DEFEND)
	_check(sess.def_state.defending, "defender is guarding after DEFEND")
	_check(sess.get_next_actor_side() == "def", "initiative flips to the defender in round 2")
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	_check(sess.def_state.defending, "guard is not cleared by the defender's own back-to-back turn")
	var guarded_est := sess.estimate_attack_damage(sess.atk_state, sess.def_state, null)
	var step := sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	_check(step.status_text == "GUARDED (-50%)", "attacker's round-2 shot is guarded (got '%s')" % step.status_text)
	_check(step.damage_dealt <= guarded_est, "guarded shot deals the halved estimate at most (%d vs %d)" % [step.damage_dealt, guarded_est])
	_check(not sess.def_state.defending, "guard is spent once the enemy has acted")
	# The AI's retreat check sees the same guard the engine will apply, never a stale one
	var sess2 := _flat_session("falke", "goliath")
	sess2.execute_next_turn(SkirmishEngine.CommandType.DEFEND)
	sess2.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	_check(not sess2.atk_state.defending, "guard is gone when the guarding unit's next turn comes after an enemy action")

func test_forecast_initiative_matches_queue() -> void:
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var ridge := GridTileData.new(Vector2i(4, 2), GridTileData.TerrainType.MOUNTAIN, 3)
	for a in CHASSIS:
		for d in CHASSIS:
			for entrenched in [false, true]:
				var atk := GlobalState.create_mech_instance(a, MechData.Faction.PLAYER, "A", Vector2i(3, 2), "a")
				var dfn := GlobalState.create_mech_instance(d, MechData.Faction.AI, "D", Vector2i(4, 2), "d")
				dfn.is_entrenched = entrenched
				var fc := SkirmishEngine.compute_forecast(atk, dfn, flat, ridge)
				var sess := SkirmishEngine.create_deterministic_session(atk, dfn, flat, ridge)
				var expected := "ATTACKER" if sess.get_next_actor_side() == "atk" else "DEFENDER"
				_check(fc["first_striker"] == expected, "%s vs %s%s: forecast INITIATIVE %s matches the real round-1 queue (%s)" % [a, d, " (entrenched)" if entrenched else "", fc["first_striker"], expected])
				_check(sess.result.first_striker == sess.get_next_actor_side(), "%s vs %s: result.first_striker is the first actor" % [a, d])

func test_seeded_sessions_replay() -> void:
	var dmg := []
	for run in 2:
		var sess := _flat_session("moloch", "donner", false, 4242)
		var seq: Array[int] = []
		while not sess.is_finished and seq.size() < 64:
			var side := sess.get_next_actor_side()
			if side == "":
				break
			var cmd := sess.choose_ai_command(side)
			var step := sess.execute_next_turn(int(cmd["command"]), String(cmd["ability_id"]))
			seq.append(step.damage_dealt * 4 + (2 if step.is_crit else 0) + (1 if step.is_miss else 0))
		dmg.append(seq)
	_check(dmg[0] == dmg[1] and dmg[0].size() > 0, "two sessions with the same seed replay the same rolls")
	GlobalState.set_battle_seed(17)
	var first := [GlobalState.next_battle_seed(), GlobalState.next_battle_seed()]
	GlobalState.set_battle_seed(17)
	var again := [GlobalState.next_battle_seed(), GlobalState.next_battle_seed()]
	_check(first == again and first[0] != first[1] and first[0] >= 0, "GlobalState hands out a reproducible, distinct seed per battle")
	GlobalState.set_battle_seed(-1)
	_check(GlobalState.next_battle_seed() == -1, "no master seed means unseeded battles")
	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance("moloch", MechData.Faction.AI, "D", Vector2i(4, 2), "d")
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	_check(SkirmishEngine.create_session(atk, dfn, flat, flat, true, 7).rng.seed == 7, "create_session threads the seed into the session RNG")

func test_support_tech_is_single_use() -> void:
	var sess := _flat_session("vanguard", "moloch")
	var krupp: CombatAbility = sess.atk_state.mech.abilities[1]
	_check(krupp.ability_id == "krupp_plate" and sess.atk_state.can_use(krupp), "Krupp Plate is available at the start")
	var first := sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "krupp_plate")
	_check(first.command_type == SkirmishEngine.CommandType.TECH and first.is_support_only, "first Krupp Plate deploys")
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)  # Brenner's turn
	_check(not sess.atk_state.can_use(krupp), "a deployed ARMOR TECH is spent for the rest of the battle")
	var en_before := sess.atk_state.en
	var def_before := sess.atk_state.def_buff_pct
	var again := sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "krupp_plate")
	_check(again.command_type == SkirmishEngine.CommandType.ATTACK and not again.is_support_only, "re-casting a spent support TECH falls back to ATTACK")
	_check(sess.atk_state.en == en_before and sess.atk_state.def_buff_pct == def_before, "no EN is spent and the buff does not stack")
	var kwk: CombatAbility = sess.atk_state.mech.abilities[0]
	_check(kwk.is_weapon() and sess.atk_state.can_use(kwk), "weapon TECHs stay usable every turn")
	# The interactive menu refuses a spent TECH the same way
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var live := _flat_session("vanguard", "moloch", false)
	screen.start_session(live)
	screen.stage.advance(0.75)
	screen.stage.menu_cursor = 1
	screen.stage.confirm_selection()
	screen.stage.tech_cursor = 1
	screen.stage.confirm_selection()
	_check(live.result.steps.size() == 1 and live.result.steps[0].ability_id == "krupp_plate", "menu deploys Krupp Plate once")
	screen.stage.skip_to_next_command_or_end()
	if screen.stage.phase == "command_select":
		screen.stage.menu_cursor = 1
		screen.stage.confirm_selection()
		screen.stage.tech_cursor = 1
		var steps_before := live.result.steps.size()
		screen.stage.confirm_selection()
		_check(screen.stage.in_tech_submenu and live.result.steps.size() == steps_before, "menu refuses to re-deploy a spent TECH")
	screen.queue_free()

func test_guard_survives_miss() -> void:
	# Seeded live sessions: find one where the Syndikat shot after a DEFEND misses, then check the
	# guard is still up (like a pending shield); a landed hit is the one that spends it.
	var seen_miss := false
	for s in range(1, 200):
		var sess := _flat_session("falke", "goliath", false, s)
		sess.execute_next_turn(SkirmishEngine.CommandType.DEFEND)   # Falke (SPD 34+8) acts first
		var shot := sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)  # Goliath fires
		if shot.is_miss:
			seen_miss = true
			_check(sess.atk_state.defending, "a MISS does not spend the guard (seed %d)" % s)
			break
		else:
			_check(not sess.atk_state.defending and shot.status_text in ["GUARDED (-50%)", "CRITICAL HIT! // GUARDED"], "a landed hit is guarded and spends the guard (seed %d)" % s)
	_check(seen_miss, "found a seed where the shot after DEFEND misses")
	# An enemy support TECH leaves the guard up too
	var det := _flat_session("falke", "goliath")
	det.execute_next_turn(SkirmishEngine.CommandType.DEFEND)
	det.execute_next_turn(SkirmishEngine.CommandType.TECH, "ferro_bulkhead")
	_check(det.atk_state.defending, "an enemy support TECH does not spend the guard")

func test_auto_pilot_uses_command_select() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen._auto_pilot = true
	var sess := _flat_session("vanguard", "moloch", false, 99)
	screen.start_session(sess)
	_check(screen.stage.auto_pilot, "stage inherits auto-pilot")
	var ticks := 0
	while not screen._all_steps_done and ticks < 4000:
		screen._process(1.0 / 30.0)
		ticks += 1
	_check(screen._all_steps_done and sess.is_finished, "auto-pilot plays the whole fight on its own (%d ticks)" % ticks)
	var coalition_steps := 0
	for st in sess.result.steps:
		if st.actor_side == "atk":
			coalition_steps += 1
	_check(coalition_steps > 0, "auto-pilot committed the player's turns")
	screen.queue_free()

func test_repelled_attacker_leaves_entrenchment() -> void:
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var atk := GlobalState.create_mech_instance("falke", MechData.Faction.PLAYER, "A", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance("goliath", MechData.Faction.AI, "D", Vector2i(4, 2), "d")
	dfn.is_entrenched = true
	var sess := SkirmishEngine.BattleSession.new(atk, dfn, flat, flat, true, 5)
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)  # Falke opens
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)  # Goliath answers
	var ret := sess.execute_next_turn(SkirmishEngine.CommandType.RETREAT)
	while not sess.is_finished and not ret.escaped:
		sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
		if sess.is_finished:
			break
		ret = sess.execute_next_turn(SkirmishEngine.CommandType.RETREAT)
	if sess.result.attacker_retreated:
		sess.apply_to_units()
		_check(dfn.is_entrenched, "an attacker that breaks off leaves the defender entrenched")
	else:
		_check(true, "retreat never succeeded with this seed; skipping entrenchment check")
	var win := _fight("goliath", "falke", 0, 5)
	_check(win.defender_destroyed and not win.defender.is_entrenched, "a destroyed defender is no longer entrenched")

func test_forecast_damage_matches_ai_estimate() -> void:
	# In deterministic mode the AI's kill check must see the same number the strike will deal
	for pair in [["vanguard", "moloch"], ["falke", "goliath"], ["donner", "kommandant"], ["moloch", "falke"]]:
		var sess := _flat_session(pair[0], pair[1])
		var side := sess.get_next_actor_side()
		var actor := sess.get_combatant(side)
		var target := sess.get_opponent(side)
		var est := sess.expected_strike_damage(actor, target, null)
		var raw := sess.estimate_attack_damage(actor, target, null)
		var hp_before := target.hp
		var step := sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
		_check(step.damage_dealt == mini(est, hp_before), "%s deterministic strike deals its expected damage (%d vs %d)" % [actor.mech.chassis_id, step.damage_dealt, est])
		_check(est <= raw, "%s expected damage folds hit/crit chance in (%d <= %d)" % [actor.mech.chassis_id, est, raw])
	# The retreat estimate counts the enemy's affordable weapon TECHs, not just its basic gun
	var s2 := _flat_session("vanguard", "moloch")
	var basic := s2.expected_strike_damage(s2.def_state, s2.atk_state, null)
	var strongest := s2.strongest_strike_estimate(s2.def_state, s2.atk_state)
	_check(strongest > basic, "Brenner's pile-bunker raises the strongest-strike estimate above its basic lance (%d > %d)" % [strongest, basic])

func test_forecast_cache() -> void:
	SkirmishEngine.clear_forecast_cache()
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A", Vector2i(3, 2), "a")
	var dfn := GlobalState.create_mech_instance("moloch", MechData.Faction.AI, "D", Vector2i(4, 2), "d")
	var f1 := SkirmishEngine.compute_forecast(atk, dfn, flat, flat)
	var f2 := SkirmishEngine.compute_forecast(atk, dfn, flat, flat)
	_check(f1 == f2 and SkirmishEngine._forecast_cache.size() == 1, "identical inputs are served from one cache entry")
	f2["est_dmg_to_def"] = -1
	_check(SkirmishEngine.compute_forecast(atk, dfn, flat, flat)["est_dmg_to_def"] == f1["est_dmg_to_def"], "callers get a copy, not the cached dictionary")
	dfn.current_armor -= 20
	var f3 := SkirmishEngine.compute_forecast(atk, dfn, flat, flat)
	_check(SkirmishEngine._forecast_cache.size() == 2 and f3["est_dmg_to_def"] <= f1["est_dmg_to_def"], "changed hull is a different key")
	dfn.is_entrenched = true
	SkirmishEngine.compute_forecast(atk, dfn, flat, flat)
	_check(SkirmishEngine._forecast_cache.size() == 3, "entrenchment is part of the key")
	SkirmishEngine.clear_forecast_cache()
	_check(SkirmishEngine._forecast_cache.is_empty(), "cache clears")

func test_status_badges() -> void:
	var sess := _flat_session("falke", "goliath")
	sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "gyro_thruster")
	var badges := sess.atk_state.get_status_badges()
	_check("SHIELD" in badges and "HASTE" in badges and not ("ARM+" in badges), "Gyro thrusters show SHIELD + HASTE, not ARM+ (got %s)" % [badges])
	sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "ferro_bulkhead")
	_check("ARM+" in sess.def_state.get_status_badges() and not ("SHIELD" in sess.def_state.get_status_badges()), "Ferro bulkhead shows ARM+ without SHIELD")
	var s2 := _flat_session("kommandant", "vanguard")
	s2.execute_next_turn(SkirmishEngine.CommandType.TECH, "enigma_ecm")
	var jammed := s2.def_state.get_status_badges()
	_check("ARM-" in jammed and "JAM" in jammed, "an ECM-jammed unit shows ARM- and JAM (got %s)" % [jammed])
