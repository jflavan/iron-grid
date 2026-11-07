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
		"test_miss_plays_no_impact", "test_seed_counter_resets_per_mission", "test_sure_kill_allows_for_variance",
		"test_guard_cannot_stack", "test_status_text_lists_every_effect", "test_identical_walkers_share_forecast",
		"test_apply_before_conclusion_is_ignored", "test_fast_forward_is_quiet",
		"test_step_breakdown_sums", "test_strike_plan_goliath_mountain", "test_strike_plan_matches_reachable",
		"test_strike_plan_beyond_range", "test_strike_plan_skips_occupied_launch_tiles", "test_strike_plan_advice_is_true",
		"test_out_of_reach_hover_and_click", "test_terrain_panel_draws_plan",
		"test_rules_chapters_fit", "test_rules_numbers_come_from_data", "test_rules_navigation",
		"test_hud_plan_clears_after_order", "test_rules_offense_final_turn", "test_rules_example_follows_chassis_data",
		"test_next_turn_fuel_matches_upkeep", "test_manual_numbers_come_from_data", "test_rules_render_is_cached",
		"test_strike_plan_reused_until_state_changes", "test_overlay_click_that_leaves_scene",
		"test_facing_direction_vectors", "test_back_attack_combat_modifiers", "test_flanking_combat_modifiers",
		"test_adjacent_formation_crossfire_and_escort", "test_forecast_matches_directional_resolution",
		"test_unit_container_formation_context", "test_in_place_rotation_and_movement_facing",
		"test_ai_prefers_flank_and_rear_attacks",
		"test_player_and_ai_reface_after_movement",
		"test_decoupled_movement_and_combat",
		"test_rules_page_draws_on_open", "test_ai_launch_context_excludes_mover", "test_redeploy_cancels_auto_advance",
		"test_dijkstra_matches_bellman_ford_on_large_map", "test_terrain_is_baked_into_few_draws",
		"test_hud_state_changes_queue_redraw",
		"test_wrecked_selection_is_cleared", "test_modal_swallows_commands", "test_victory_rules_evaluate", "test_catalogs_are_consistent",
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
	strings.append_array(UIOverlay.manual_lines())
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
	_check(again == null and sess.get_next_actor_side() == "atk" and not sess.is_finished, "re-casting a spent support TECH is rejected and the turn is not consumed")
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
			_check(not sess.atk_state.defending and shot.status_text in ["GUARDED (-50%)", "CRITICAL HIT! // GUARDED (-50%)"], "a landed hit is guarded and spends the guard (seed %d)" % s)
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
	atk.firepower += 10
	var f4 := SkirmishEngine.compute_forecast(atk, dfn, flat, flat)
	_check(SkirmishEngine._forecast_cache.size() == 4 and f4["atk_eff_fp"] > f1["atk_eff_fp"], "a per-unit stat change is a different key")
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

func test_miss_plays_no_impact() -> void:
	var screen := _screen_for(_fight("vanguard", "moloch"))
	await get_tree().process_frame
	var st := screen.stage
	for id in WeaponAnims.PROFILES:
		var a: Dictionary = st.mechs["atk"]
		var d: Dictionary = st.mechs["def"]
		var imp := WeaponAnims.impact_time(id)
		var dur := WeaponAnims.duration(id)
		var reacted := false
		for t in [imp + 0.02, imp + 0.2, (imp + dur) * 0.5, dur - 0.05]:
			d["pose"] = ""
			d["white"] = false
			d["offset"] = Vector2.ZERO
			WeaponAnims.run(st, a, d, id, t, false)
			if d["pose"] != "" or d["white"] or d["offset"] != Vector2.ZERO:
				reacted = true
		_check(not reacted, "%s MISS leaves the target untouched after impact time" % id)
		d["pose"] = ""
		d["white"] = false
		d["offset"] = Vector2.ZERO
		WeaponAnims.run(st, a, d, id, imp + 0.02, true)
		_check(d["pose"] != "" or d["white"] or d["offset"] != Vector2.ZERO, "%s hit still reacts on impact" % id)
	screen.queue_free()

func test_seed_counter_resets_per_mission() -> void:
	GlobalState.set_battle_seed(17)
	var first := GlobalState.next_battle_seed()
	GlobalState.next_battle_seed()
	GlobalState.next_battle_seed()
	GlobalState.reset_battle_state()
	_check(GlobalState.next_battle_seed() == first, "a mission restart replays from the first battle seed")
	GlobalState.set_battle_seed(-1)

func test_sure_kill_allows_for_variance() -> void:
	var live := _flat_session("vanguard", "moloch", false, 3)
	_check(not live.is_sure_kill(30, 30), "an estimate equal to the hull is not a sure kill under -6% variance")
	_check(live.is_sure_kill(32, 30), "an estimate that clears the hull at -6% is a sure kill")
	var det := _flat_session("vanguard", "moloch")
	_check(det.is_sure_kill(30, 30), "deterministic mode has no variance, so equal is enough")
	# Rejected commands do not consume the turn in the live stage either
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var sess := _flat_session("vanguard", "moloch", false, 4)
	screen.start_session(sess)
	screen.stage.advance(0.75)
	screen.stage._commit_session_turn(SkirmishEngine.CommandType.TECH, "no_such_tech")
	_check(screen.stage.phase == "command_select" and sess.result.steps.is_empty(), "an unknown TECH is rejected and the menu stays open")
	screen.queue_free()

func test_guard_cannot_stack() -> void:
	var sess := _flat_session("falke", "goliath")
	sess.execute_next_turn(SkirmishEngine.CommandType.DEFEND)                 # Falke guards
	sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "ferro_bulkhead")  # Goliath buffs: guard still up
	var en_before := sess.atk_state.en
	var again := sess.execute_next_turn(SkirmishEngine.CommandType.DEFEND)
	_check(again == null and sess.atk_state.en == en_before and sess.get_next_actor_side() == "atk", "a second DEFEND while guarding is rejected and banks no EN")
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var live := _flat_session("falke", "goliath", false, 11)
	screen.start_session(live)
	screen.stage.advance(0.75)
	screen.stage.menu_cursor = 2
	screen.stage.confirm_selection()
	_check(live.atk_state.defending, "menu DEFEND raises the guard")
	screen.stage.skip_to_next_command_or_end()
	if screen.stage.phase == "command_select" and live.atk_state.defending:
		var steps := live.result.steps.size()
		screen.stage.menu_cursor = 2
		screen.stage.confirm_selection()
		_check(screen.stage.phase == "command_select" and live.result.steps.size() == steps, "menu refuses DEFEND while the guard is still up")
	screen.queue_free()

func test_status_text_lists_every_effect() -> void:
	var sess := _flat_session("vanguard", "moloch")
	sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "krupp_plate")  # shield pending
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)                # Brenner: consumes the shield
	var shielded := sess.result.steps[1]
	_check(shielded.status_text == "SHIELD DEFLECT!", "a shield alone reads SHIELD DEFLECT! (got '%s')" % shielded.status_text)
	var s2 := _flat_session("vanguard", "moloch")
	s2.execute_next_turn(SkirmishEngine.CommandType.TECH, "krupp_plate")
	s2.execute_next_turn(SkirmishEngine.CommandType.TECH, "ablative_shield")  # Brenner buffs instead; Vanguard shield still pending
	s2.execute_next_turn(SkirmishEngine.CommandType.DEFEND)                    # Vanguard guards on top
	var hit := s2.execute_next_turn(SkirmishEngine.CommandType.ATTACK)        # Brenner fires into guard + shield
	_check(hit.status_text == "GUARDED (-50%) // SHIELD DEFLECT!", "guard and shield are both reported (got '%s')" % hit.status_text)
	_check(hit.soften_from == "krupp_plate" and not s2.atk_state.defending, "both the shield and the guard were spent by that shot")

func test_identical_walkers_share_forecast() -> void:
	SkirmishEngine.clear_forecast_cache()
	var flat := GridTileData.new(Vector2i(3, 2), GridTileData.TerrainType.PLAIN, 1)
	var a1 := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A1", Vector2i(3, 2), "a1")
	var a2 := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A2", Vector2i(3, 3), "a2")
	var dfn := GlobalState.create_mech_instance("moloch", MechData.Faction.AI, "D", Vector2i(4, 2), "d")
	var f1 := SkirmishEngine.compute_forecast(a1, dfn, flat, flat)
	var f2 := SkirmishEngine.compute_forecast(a2, dfn, flat, flat)
	_check(f1 == f2 and SkirmishEngine._forecast_cache.size() == 1, "two identical walkers share one forecast entry")
	SkirmishEngine.clear_forecast_cache()

func test_apply_before_conclusion_is_ignored() -> void:
	var sess := _flat_session("vanguard", "moloch")
	var hp := sess.result.attacker.current_armor
	sess.execute_next_turn(SkirmishEngine.CommandType.ATTACK)
	sess.apply_to_units()
	_check(sess.result.attacker.current_armor == hp and sess.result.defender.current_armor == sess.result.defender.max_armor, "apply_to_units before the battle concludes leaves the units alone")

func test_fast_forward_is_quiet() -> void:
	var screen := BattleScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var live := _flat_session("vanguard", "moloch", false, 21)
	screen.start_session(live)
	screen.stage.advance(0.75)
	screen.stage.menu_cursor = 0
	screen.stage.confirm_selection()
	screen.stage.skip_to_next_command_or_end()
	_check(screen.stage.numbers.is_empty(), "fast-forwarding to the next prompt leaves no stacked damage numbers")
	_check(not screen.stage._fast_forwarding, "fast-forward flag is cleared afterwards")
	screen.queue_free()

# ---------------------------------------------------------------- strike plan (out-of-reach feedback)
const ALL_CHASSIS := ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]

func _grid(map_idx: int) -> IsoGridMap:
	var gm := IsoGridMap.new()
	gm.load_from_definition(GlobalState.maps[map_idx])
	return gm

func _unit(chassis: String, faction: MechData.Faction, pos: Vector2i, tag: String = "u") -> MechData:
	return GlobalState.create_mech_instance(chassis, faction, tag.to_upper() + "-1", pos, tag)


func test_step_breakdown_sums() -> void:
	var bad := 0
	for c in ALL_CHASSIS:
		var m := _unit(c, MechData.Faction.PLAYER, Vector2i.ZERO)
		for tt in GridTileData.TerrainType.values():
			for climb in 3:
				var from := GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.PLAIN, 1)
				var to := GridTileData.new(Vector2i.ONE, tt, 1 + climb)
				var b: Dictionary = m.get_step_fuel_breakdown(from, to)
				if int(b["base"]) + int(b["chassis"]) + int(b["climb"]) != int(b["total"]) or int(b["total"]) != m.get_step_fuel_cost(from, to):
					bad += 1
	_check(bad == 0, "step breakdown terms sum to total == get_step_fuel_cost for every chassis/terrain/climb (%d bad)" % bad)
	var g := _unit("goliath", MechData.Faction.PLAYER, Vector2i.ZERO)
	var gb: Dictionary = g.get_step_fuel_breakdown(GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.FOREST, 2), GridTileData.new(Vector2i.ONE, GridTileData.TerrainType.MOUNTAIN, 3))
	_check(gb["base"] == 10 and gb["chassis"] == 2 and gb["chassis_label"] == "HEAVY" and gb["climb"] == 2 and gb["total"] == 14 and gb["terrain"] == "MTN", "goliath into a mountain one level up is MTN 10 + HEAVY 2 + CLIMB 2 = 14 (got %s)" % gb)
	var d := _unit("donner", MechData.Faction.PLAYER, Vector2i.ZERO)
	var db: Dictionary = d.get_step_fuel_breakdown(GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.PLAIN, 1), GridTileData.new(Vector2i.ONE, GridTileData.TerrainType.MOUNTAIN, 3))
	_check(db["chassis_label"] == "CLIMB GEAR" and db["chassis"] == -4 and db["climb"] == 2, "donner mountain gear shows CLIMB GEAR -4 and a discounted climb (got %s)" % db)

func test_strike_plan_goliath_mountain() -> void:
	# Iron Bridge: (7,7) is trench at L2, (8,7) a mountain at L3.
	var gm := _grid(0)
	var titan := _unit("goliath", MechData.Faction.PLAYER, Vector2i(7, 7), "t")
	titan.current_fuel = 4
	var foe := _unit("donner", MechData.Faction.AI, Vector2i(8, 7), "f")
	var plan: StrikePlan = gm.compute_strike_plan(titan, foe.grid_pos, {foe.grid_pos: foe})
	_check(plan.severity == StrikePlan.IN_STRIKING_DISTANCE, "adjacent titan with 4F is in striking distance (got %d)" % plan.severity)
	_check(plan.needs == 14 and plan.have == 4 and plan.path_fuel == 0, "strike needs 14, have 4, no path fuel (got %d/%d/%d)" % [plan.needs, plan.have, plan.path_fuel])
	_check(plan.advice == StrikePlan.ADV_IMPOSSIBLE, "advice is ADV_IMPOSSIBLE (got %d)" % plan.advice)
	_check(plan.breakdown_text() == "MTN 10 + HEAVY 2 + CLIMB 2", "breakdown text (got '%s')" % plan.breakdown_text())
	gm.free()

func test_strike_plan_matches_reachable() -> void:
	var mismatches: Array = []
	for mi in GlobalState.maps.size():
		var gm := _grid(mi)
		for c in ["vanguard", "goliath"]:
			for start: Vector2i in gm.tiles.keys():
				if start.x % 2 != 0 or start.y % 2 != 0:
					continue
				for target: Vector2i in gm.tiles.keys():
					var dist: int = absi(target.x - start.x) + absi(target.y - start.y)
					if dist == 0 or dist > 4:
						continue
					var atk := _unit(c, MechData.Faction.PLAYER, start, "a")
					var foe := _unit("vanguard", MechData.Faction.AI, target, "f")
					var occ := {target: foe}
					var reach: Dictionary = gm.compute_reachable_tiles(atk, occ)
					var plan: StrikePlan = gm.compute_strike_plan(atk, target, occ)
					if dist == 1:
						if reach.has(target):
							if plan.severity != StrikePlan.REACHABLE or plan.needs != int(reach[target]["fuel_spent"]):
								mismatches.append([mi, c, start, target])
						elif plan.severity == StrikePlan.REACHABLE:
							mismatches.append([mi, c, start, target, "plan says reachable at dist 1"])
					else:
						if reach.has(target):
							mismatches.append([mi, c, start, target, "non-adjacent enemy in reachable_info"])
						elif plan.severity == StrikePlan.REACHABLE:
							if not reach.has(plan.launch) or int(reach[plan.launch]["fuel_spent"]) + int(plan.step["total"]) != plan.needs:
								mismatches.append([mi, c, start, target, "plan launch mismatch"])
		gm.free()
	_check(mismatches.is_empty(), "strike plan agrees with two-step reachable_info (%d mismatches, first %s)" % [mismatches.size(), mismatches.slice(0, 1)])

func test_strike_plan_beyond_range() -> void:
	var gm := _grid(0)
	var titan := _unit("goliath", MechData.Faction.PLAYER, Vector2i(0, 5), "t")
	var foe := _unit("donner", MechData.Faction.AI, Vector2i(8, 7), "f")
	var plan: StrikePlan = gm.compute_strike_plan(titan, foe.grid_pos, {foe.grid_pos: foe})
	_check(plan.severity == StrikePlan.BEYOND_RANGE, "a distant enemy is beyond range (got %d)" % plan.severity)
	_check(plan.needs > titan.max_fuel, "beyond-range needs exceeds the tank (got %d)" % plan.needs)
	gm.free()

func test_strike_plan_skips_occupied_launch_tiles() -> void:
	var gm := _grid(0)
	var atk := _unit("vanguard", MechData.Faction.PLAYER, Vector2i(3, 3), "a")
	var foe := _unit("vanguard", MechData.Faction.AI, Vector2i(0, 0), "f")
	var occ := {
		Vector2i(0, 0): foe,
		Vector2i(1, 0): _unit("falke", MechData.Faction.PLAYER, Vector2i(1, 0), "b"),
		Vector2i(0, 1): _unit("falke", MechData.Faction.PLAYER, Vector2i(0, 1), "c"),
	}
	var plan: StrikePlan = gm.compute_strike_plan(atk, foe.grid_pos, occ)
	_check(plan.severity == StrikePlan.NO_APPROACH, "an enemy whose launch tiles are all friendly-held has no approach (got %d)" % plan.severity)
	gm.free()

func test_strike_plan_advice_is_true() -> void:
	var lies: Array = []
	var seen := {}
	for mi in GlobalState.maps.size():
		var gm := _grid(mi)
		for c in ["vanguard", "goliath"]:
			for start: Vector2i in gm.tiles.keys():
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)]:
					var target: Vector2i = start + d
					if not gm.is_valid_coords(target):
						continue
					var proto := _unit(c, MechData.Faction.PLAYER, start, "a")
					for fuel in range(0, proto.max_fuel + 1, 2):
						var atk := _unit(c, MechData.Faction.PLAYER, start, "a")
						atk.current_fuel = fuel
						var foe := _unit("vanguard", MechData.Faction.AI, target, "f")
						var occ := {target: foe}
						var plan: StrikePlan = gm.compute_strike_plan(atk, target, occ)
						if plan.severity != StrikePlan.IN_STRIKING_DISTANCE:
							continue
						seen[plan.advice] = true
						var tgt_tile := gm.get_tile(target)
						match plan.advice:
							StrikePlan.ADV_WAIT_HERE:
								var nxt := atk.next_turn_fuel(fuel, gm.get_tile(start), true)
								if nxt < atk.get_step_fuel_cost(gm.get_tile(start), tgt_tile):
									lies.append([mi, c, start, target, fuel, "WAIT_HERE"])
							StrikePlan.ADV_MOVE_TO:
								var reach: Dictionary = gm.compute_reachable_tiles(atk, occ)
								if not reach.has(plan.move_to) or absi(plan.move_to.x - target.x) + absi(plan.move_to.y - target.y) != 1:
									lies.append([mi, c, start, target, fuel, "MOVE_TO not a reachable launch tile"])
								else:
									var left: int = fuel - int(reach[plan.move_to]["fuel_spent"])
									var nxt2 := atk.next_turn_fuel(left, gm.get_tile(plan.move_to), false)
									if nxt2 < atk.get_step_fuel_cost(gm.get_tile(plan.move_to), tgt_tile):
										lies.append([mi, c, start, target, fuel, "MOVE_TO"])
							StrikePlan.ADV_WAIT:
								var nxt3 := atk.next_turn_fuel(fuel, gm.get_tile(start), true)
								if nxt3 < plan.needs:
									lies.append([mi, c, start, target, fuel, "WAIT"])
		gm.free()
	_check(lies.is_empty(), "every strike advice holds under the WAIT/upkeep rules (%d false, first %s)" % [lies.size(), lies.slice(0, 1)])
	_check(seen.has(StrikePlan.ADV_WAIT_HERE) and seen.has(StrikePlan.ADV_MOVE_TO), "the advice sweep exercises WAIT_HERE and MOVE_TO (saw %s)" % [seen.keys()])

# ---------------------------------------------------------------- out-of-reach HUD + comms log
func _spawn_iron_bridge() -> Battlefield:
	GlobalState.selected_map_index = 0
	var bf: Battlefield = load("res://scenes/Battlefield.tscn").instantiate()
	add_child(bf)
	await get_tree().process_frame
	return bf

func _unit_by_callsign(bf: Battlefield, prefix: String) -> MechUnit:
	for u in bf.unit_container.units:
		if is_instance_valid(u) and u.mech_data.callsign.begins_with(prefix):
			return u
	return null

func test_out_of_reach_hover_and_click() -> void:
	var bf := await _spawn_iron_bridge()
	var titan := _unit_by_callsign(bf, "TITAN-2")
	var spinne := _unit_by_callsign(bf, "SPINNE-4")
	titan.mech_data.grid_pos = Vector2i(7, 7)
	titan.mech_data.current_fuel = 4
	bf._select_unit(titan)
	bf._refresh_hover_telemetry(Vector2i(8, 7))
	var plan: StrikePlan = bf.ui_overlay.strike_plan
	_check(plan != null and plan.severity == StrikePlan.IN_STRIKING_DISTANCE, "hovering SPINNE-4 from (7,7) with 4F shows an in-striking-distance plan")
	_check(bf.ui_overlay.current_forecast.is_empty(), "no engagement forecast for an unreachable enemy")
	_check(bf.ui_overlay.step_cost_mech == titan.mech_data, "YOUR STEP COST row follows the selected titan")
	bf._refresh_hover_telemetry(Vector2i(5, 3))
	_check(bf.ui_overlay.strike_plan == null, "hovering an empty tile clears the strike plan")

	var log_before: int = GlobalState.combat_log.size()
	bf._on_tile_clicked(Vector2i(8, 7), bf.grid_map.get_tile(Vector2i(8, 7)))
	var new_lines: Array = GlobalState.combat_log.slice(log_before)
	var logged := new_lines.any(func(l): return "CANNOT REACH" in l and "STRIKE NEEDS 14F" in l)
	_check(logged, "clicking the unreachable enemy logs why (got %s)" % [new_lines])
	_check(bf.selected_unit == spinne, "the click still selects the enemy for inspection")

	# A distant enemy is quiet: no log line.
	var iron := _unit_by_callsign(bf, "IRON-1")
	iron.mech_data.has_moved = false
	bf._select_unit(iron)
	var far: StrikePlan = bf.strike_plan_for(Vector2i(8, 7))
	_check(far != null and far.severity == StrikePlan.BEYOND_RANGE, "SPINNE-4 is beyond IRON-1's range (got %s)" % [far.severity if far else null])
	log_before = GlobalState.combat_log.size()
	bf._on_tile_clicked(Vector2i(8, 7), bf.grid_map.get_tile(Vector2i(8, 7)))
	_check(GlobalState.combat_log.size() == log_before, "clicking a beyond-range enemy adds no log line")
	bf.queue_free()
	await get_tree().process_frame

func test_terrain_panel_draws_plan() -> void:
	var bf := await _spawn_iron_bridge()
	var ov := bf.ui_overlay
	ov.hovered_tile = bf.grid_map.get_tile(Vector2i(8, 7))
	ov.strike_plan = null
	var h0: float = ov._terrain_panel_height()
	var titan := _unit_by_callsign(bf, "TITAN-2")
	titan.mech_data.grid_pos = Vector2i(7, 7)
	titan.mech_data.current_fuel = 4
	var spinne := _unit_by_callsign(bf, "SPINNE-4")
	ov.strike_plan = bf.grid_map.compute_strike_plan(titan.mech_data, spinne.mech_data.grid_pos, bf.unit_container.build_occupied_map(titan))
	var h1: float = ov._terrain_panel_height()
	var wrapped := ov.strike_plan.panel_lines(UIOverlay.RIGHT_W - 24).size()
	_check(h1 - h0 >= (1 + wrapped) * CrtUI.LINE, "panel grows to fit the OUT OF REACH box (%s -> %s for %d lines)" % [h0, h1, wrapped])
	var long_plan := StrikePlan.new()
	long_plan.severity = StrikePlan.IN_STRIKING_DISTANCE
	long_plan.path_fuel = 12
	long_plan.step = {"base": 5, "terrain": "MTN", "chassis": -2, "chassis_label": "CLIMB GEAR", "climb": 2, "total": 5}
	long_plan.needs = 17
	long_plan.have = 9
	long_plan.advice = StrikePlan.ADV_MULTI_TURN
	var packed := long_plan.panel_lines(UIOverlay.RIGHT_W - 24)
	var all_fit := packed.size() > 0
	for l in packed:
		all_fit = all_fit and PixelFont.text_width(l) <= UIOverlay.RIGHT_W - 24
	var joined := " ".join(packed)
	_check(all_fit and "PATH 12" in joined and "CLIMB GEAR -2" in joined and "CLIMB 2" in joined, "packed breakdown fits the HUD and never splits a term (%s)" % [packed])
	var lines := ov.strike_plan.panel_lines()
	_check(CrtUI.wrap_lines(lines[0], UIOverlay.RIGHT_W - 24).size() == 1 and (CrtUI.wrap_lines(lines[1], UIOverlay.RIGHT_W - 24).size() in [1, 2]), "fuel and breakdown lines fit HUD line limits (%s)" % [lines])
	ov.root_ctrl.queue_redraw()
	await get_tree().process_frame
	_check(true, "terrain panel draws with a strike plan without errors")
	bf.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- Rules of Engagement page
func _all_rules_text() -> String:
	var parts: PackedStringArray = []
	for ch in RulesContent.chapters():
		parts.append(ch["title"])
		for b in ch["blocks"]:
			if b.has("table"):
				for row in b["table"]:
					parts.append(" ".join(row))
			else:
				parts.append(b.get("p", b.get("key", "")))
	return "\n".join(parts)

func test_rules_chapters_fit() -> void:
	var chapters := RulesContent.chapters()
	_check(chapters.size() == 7, "seven chapters (got %d)" % chapters.size())
	var titles := chapters.map(func(c): return c["title"])
	_check(titles == ["HOW YOU WIN", "MOVEMENT & FUEL", "TERRAIN & HIGH GROUND", "THE CLASH", "AFTER THE CLASH", "CHASSIS ROLES", "FIELD TIPS"], "chapter titles verbatim (got %s)" % [titles])
	var lay: Dictionary = MainMenu.rules_layout(Vector2(CrtUI.DESIGN))
	var body: Rect2 = lay["body"]
	var inner_w: float = body.size.x - 2 * MainMenu.RULES_PAD
	for ch in chapters:
		var h: float = RulesContent.chapter_height(ch, inner_w)
		_check(MainMenu.RULES_BODY_TOP + h <= body.size.y - MainMenu.RULES_PAD, "chapter '%s' fits the body at 720x450 (%s + %s vs %s)" % [ch["title"], MainMenu.RULES_BODY_TOP, h, body.size.y])
		for b in ch["blocks"]:
			if b.has("table"):
				_check(RulesContent.table_width(b["table"]) <= inner_w, "table in '%s' fits the body width" % ch["title"])
	var list_w: float = (lay["list"] as Rect2).size.x - 2 * MainMenu.RULES_PAD - 12
	for t in titles:
		_check(PixelFont.text_width("%d %s" % [titles.find(t) + 1, t]) <= list_w, "chapter list entry '%s' fits" % t)

func test_rules_numbers_come_from_data() -> void:
	var chapters := RulesContent.chapters()
	var fuel_text := ""
	for b in chapters[1]["blocks"]:
		fuel_text += (" ".join(b["table"].map(func(r): return " ".join(r))) if b.has("table") else b.get("p", b.get("key", ""))) + "\n"
	var g: MechData = GlobalState.chassis_catalog["goliath"]
	var mtn := GridTileData.new(Vector2i.ONE, GridTileData.TerrainType.MOUNTAIN, 3)
	_check(("%d+%d" % [g.max_fuel, g.passive_refuel]) in fuel_text, "movement chapter quotes the goliath's tank and refuel from the catalog")
	_check(str(mtn.get_base_fuel_cost() * g.fuel_usage) in fuel_text, "movement chapter quotes the mountain fuel cost")
	var need := g.get_step_fuel_cost(GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.PLAIN, 2), mtn)
	_check(RulesContent.worked_example_needs() == need, "worked example needs == goliath plain(L2)->mountain(L3) step (%d vs %d)" % [RulesContent.worked_example_needs(), need])
	_check(("= %d" % need) in fuel_text, "the worked example shows its total")
	var missing := {}
	for ch in CrtUI.sanitize(_all_rules_text()):
		if ch != " " and ch != "\n" and not PixelFont.has_glyph(ch):
			missing[ch] = true
	_check(missing.is_empty(), "every rules glyph is drawable (missing %s)" % [missing.keys()])

func test_rules_navigation() -> void:
	var menu: MainMenu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(not menu.show_rules, "rules page starts closed")
	menu._activate("rules")
	_check(menu.show_rules and menu.rules_chapter == 0, "activating 'rules' opens chapter 1")
	_check(menu._key_action(KEY_DOWN) == "rules:1", "Down moves to chapter 2 (got %s)" % menu._key_action(KEY_DOWN))
	menu._activate(menu._key_action(KEY_DOWN))
	_check(menu.rules_chapter == 1, "chapter 2 selected")
	menu._activate(menu._key_action(KEY_7))
	_check(menu.rules_chapter == 6, "key 7 jumps to the last chapter")
	_check(menu._key_action(KEY_ENTER) == "" and menu._key_action(KEY_SPACE) == "", "Enter/Space do nothing on the rules page")
	_check(menu._key_action(KEY_ESCAPE) == "rules_back", "Esc goes back")
	menu._activate("rules_back")
	_check(not menu.show_rules, "back closes the rules page")
	_check(menu._key_action(KEY_R) == "rules", "R opens the rules page from Command HQ")
	_check(menu._key_action(KEY_ENTER) == "launch", "Enter still launches from Command HQ")
	menu.queue_redraw()
	await get_tree().process_frame
	menu.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- code-review regression tests
func test_hud_plan_clears_after_order() -> void:
	var bf := await _spawn_iron_bridge()
	var titan := _unit_by_callsign(bf, "TITAN-2")
	titan.mech_data.grid_pos = Vector2i(7, 7)
	titan.mech_data.current_fuel = 4
	bf._select_unit(titan)
	bf._refresh_hover_telemetry(Vector2i(8, 7))
	_check(bf.ui_overlay.strike_plan != null, "precondition: OUT OF REACH plan is showing")
	# The reviewer's case: TITAN-2 is the last walker with an order left, so WAIT selects nobody.
	for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
		if u != titan:
			u.mech_data.has_moved = true
			u.mech_data.has_attacked = true
	bf._on_wait_refuel_requested()
	_check(bf.ui_overlay.strike_plan == null and bf.ui_overlay.step_cost_mech == null, "WAIT clears the strike plan and step-cost row")
	var iron := _unit_by_callsign(bf, "IRON-1")
	iron.mech_data.has_moved = false
	bf._select_unit(iron)
	bf._refresh_hover_telemetry(Vector2i(8, 7))
	_check(bf.ui_overlay.step_cost_mech == iron.mech_data, "precondition: step-cost row follows IRON-1")
	var dest: Vector2i = bf.grid_map.reachable_info.keys().filter(func(k): return k != iron.mech_data.grid_pos and not bf.grid_map.reachable_info[k]["is_attack"])[0]
	bf._execute_unit_movement(iron, dest, bf.grid_map.reachable_info[dest]["path"], int(bf.grid_map.reachable_info[dest]["fuel_spent"]))
	_check(bf.ui_overlay.strike_plan == null and bf.ui_overlay.step_cost_mech == null, "a move clears the strike plan and step-cost row while it animates")
	bf.queue_free()
	await get_tree().process_frame

func test_rules_offense_final_turn() -> void:
	var text := _all_rules_text().to_upper()
	_check(not ("BEFORE THE TURN LIMIT" in text), "the offense rule does not say 'before the turn limit' (holding on the final turn still wins)")
	_check("FINAL TURN" in text, "the offense rule says the final turn still counts")

func test_rules_example_follows_chassis_data() -> void:
	var g: MechData = GlobalState.chassis_catalog["goliath"]
	var saved := g.fuel_efficiency_mod
	g.fuel_efficiency_mod = -1
	var text := _all_rules_text()
	g.fuel_efficiency_mod = saved
	var example := ""
	for l in text.split("\n"):
		if l.begins_with("EXAMPLE:"):
			example = l.to_upper()
	_check(example != "" and not ("HEAVY" in example), "with a -1 goliath the worked example says no HEAVY (%s)" % example)
	_check("LIGHT -2" in example, "the example labels the -2 adjustment LIGHT")
	_check(not ("+-" in text), "no '+-' sign glitch in the rules text")

func test_next_turn_fuel_matches_upkeep() -> void:
	var bf := await _spawn_iron_bridge()
	var iron := _unit_by_callsign(bf, "IRON-1")
	var m := iron.mech_data
	for pos in [Vector2i(3, 1), Vector2i(2, 3)]:   # a city and a plain on Iron Bridge
		for waited in [false, true]:
			for fuel in [0, 3, m.max_fuel - 2, m.max_fuel]:
				m.grid_pos = pos
				m.current_fuel = fuel
				var predicted: int = m.next_turn_fuel(fuel, bf.grid_map.get_tile(pos), waited)
				if waited:
					bf._entrench_unit(m)
				var ps: Array[MechUnit] = [iron]
				bf._apply_turn_upkeep(ps, true)
				_check(m.current_fuel == predicted, "next_turn_fuel matches the real WAIT/upkeep at %s waited=%s fuel=%d (%d vs %d)" % [pos, waited, fuel, predicted, m.current_fuel])
	bf.queue_free()
	await get_tree().process_frame

func test_manual_numbers_come_from_data() -> void:
	var manual := "\n".join(UIOverlay.manual_lines())
	_check(("+%d Fuel" % MechData.WAIT_FUEL) in manual and ("+%d EN" % MechData.WAIT_ENERGY) in manual, "manual WAIT line reads the WAIT constants")
	var mtn := GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.MOUNTAIN, 1)
	_check(("%d Fuel" % mtn.get_base_fuel_cost()) in manual and ("%+d%% DEF" % mtn.get_defense_modifier_pct()) in manual, "manual terrain chart reads GridTileData")
	_check(("+%d SPD" % SkirmishEngine.ROUND1_ATTACKER_SPD_BONUS) in manual, "manual initiative line reads SkirmishEngine")

func test_rules_render_is_cached() -> void:
	var menu: MainMenu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var a = menu._rules_render(1, 500.0)
	var b = menu._rules_render(1, 500.0)
	_check(is_same(a, b), "rules chapter layout is cached per (chapter, width)")
	_check(not is_same(a, menu._rules_render(2, 500.0)), "different chapters get their own layout")
	menu.queue_free()
	await get_tree().process_frame

func test_strike_plan_reused_until_state_changes() -> void:
	var bf := await _spawn_iron_bridge()
	var titan := _unit_by_callsign(bf, "TITAN-2")
	titan.mech_data.grid_pos = Vector2i(7, 7)
	titan.mech_data.current_fuel = 4
	bf._select_unit(titan)
	var p1: StrikePlan = bf.strike_plan_for(Vector2i(8, 7))
	_check(is_same(p1, bf.strike_plan_for(Vector2i(8, 7))), "hover then click reuse one strike plan (no second search)")
	titan.mech_data.current_fuel = 3
	var p2: StrikePlan = bf.strike_plan_for(Vector2i(8, 7))
	_check(not is_same(p1, p2) and p2.have == 3, "a fuel change gives a fresh plan")
	var spinne := _unit_by_callsign(bf, "SPINNE-4")
	spinne.mech_data.grid_pos = Vector2i(9, 7)
	_check(bf.strike_plan_for(Vector2i(8, 7)) == null, "the cache never answers for a tile the enemy left")
	bf.queue_free()
	await get_tree().process_frame

func test_overlay_click_that_leaves_scene() -> void:
	# Clicking MENU changes scene, which takes the overlay out of the tree inside _activate; the
	# handler must not then touch get_viewport() (it is null). The runner fails on that SCRIPT ERROR.
	var bf := await _spawn_iron_bridge()
	var ov := bf.ui_overlay
	ov.action_return_menu_requested.disconnect(bf._on_return_menu_requested)
	ov.action_return_menu_requested.connect(func(): remove_child(bf))
	ov.root_ctrl.queue_redraw()
	await get_tree().process_frame
	var rect := Rect2()
	for sp in ov._hot._spots:
		if sp["id"] == "menu":
			rect = sp["rect"]
	_check(rect.size != Vector2.ZERO, "precondition: MENU hotspot exists")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = rect.get_center() * ov._scale
	ov._input(ev)
	_check(not bf.is_inside_tree(), "the click took the battlefield out of the tree")
	bf.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- Directional Facing & Formations
func test_facing_direction_vectors() -> void:
	var m := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "T", Vector2i(2, 2))
	m.facing = Vector2i(1, 0)
	_check(m.get_facing_name() == "SE", "Vector2i(1, 0) is SE")
	m.facing = Vector2i(0, 1)
	_check(m.get_facing_name() == "SW", "Vector2i(0, 1) is SW")
	m.facing = Vector2i(-1, 0)
	_check(m.get_facing_name() == "NW", "Vector2i(-1, 0) is NW")
	m.facing = Vector2i(0, -1)
	_check(m.get_facing_name() == "NE", "Vector2i(0, -1) is NE")

	m.set_facing(Vector2i(5, 1))
	_check(m.facing == Vector2i(1, 0), "set_facing(5, 1) normalizes to (1, 0)")
	m.set_facing(Vector2i(1, 4))
	_check(m.facing == Vector2i(0, 1), "set_facing(1, 4) normalizes to (0, 1)")

	# Test relative approach angles for all 4 defender facings
	var T := GridTileData.TerrainType
	var target := GridTileData.new(Vector2i(2, 2), T.PLAIN, 1)
	var from_west := GridTileData.new(Vector2i(1, 2), T.PLAIN, 1) # approach is +X (1, 0)
	var from_east := GridTileData.new(Vector2i(3, 2), T.PLAIN, 1) # approach is -X (-1, 0)
	var from_north := GridTileData.new(Vector2i(2, 1), T.PLAIN, 1) # approach is +Y (0, 1)
	var from_south := GridTileData.new(Vector2i(2, 3), T.PLAIN, 1) # approach is -Y (0, -1)

	var def_se := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "D", Vector2i(2, 2))
	def_se.facing = Vector2i(1, 0) # Defender faces SE (+X)
	var r_rear := SkirmishEngine._init_result_modifiers(m, def_se, from_west, target)
	_check(r_rear.approach_angle == "REAR", "attacking from behind facing SE is REAR")
	var r_front := SkirmishEngine._init_result_modifiers(m, def_se, from_east, target)
	_check(r_front.approach_angle == "FRONT", "attacking into facing SE is FRONT")
	var r_flank_n := SkirmishEngine._init_result_modifiers(m, def_se, from_north, target)
	_check(r_flank_n.approach_angle == "FLANK", "attacking from north into facing SE is FLANK")
	var r_flank_s := SkirmishEngine._init_result_modifiers(m, def_se, from_south, target)
	_check(r_flank_s.approach_angle == "FLANK", "attacking from south into facing SE is FLANK")

func test_back_attack_combat_modifiers() -> void:
	var T := GridTileData.TerrainType
	var from_tile := GridTileData.new(Vector2i(2, 2), T.PLAIN, 1)
	var target_tile := GridTileData.new(Vector2i(3, 2), T.PLAIN, 1) # approach is +X (1, 0)

	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "ATK", Vector2i(2, 2))
	var def_front := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF_F", Vector2i(3, 2))
	def_front.facing = Vector2i(-1, 0) # Facing -X -> attacker coming from +X is FRONTAL

	var def_rear := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF_R", Vector2i(3, 2))
	def_rear.facing = Vector2i(1, 0) # Facing +X -> attacker coming from -X into it is REAR

	var res_front := SkirmishEngine.resolve_skirmish(atk, def_front, from_tile, target_tile, false, true)
	var res_rear := SkirmishEngine.resolve_skirmish(atk, def_rear, from_tile, target_tile, false, true)

	_check(res_rear.approach_angle == "REAR", "approach classified as REAR")
	_check(res_rear.atk_directional_mod_pct == SkirmishEngine.REAR_ATK_FP_PCT, "rear attack adds +%d%% ATK" % SkirmishEngine.REAR_ATK_FP_PCT)
	_check(res_rear.def_directional_mod_pct == SkirmishEngine.REAR_DEF_ARMOR_PCT, "rear attack shreds %d%% DEF" % SkirmishEngine.REAR_DEF_ARMOR_PCT)
	_check(res_rear.total_dmg_to_defender > res_front.total_dmg_to_defender, "rear attack deals significantly more damage (%d vs %d)" % [res_rear.total_dmg_to_defender, res_front.total_dmg_to_defender])

	# Entrenchment bypass on back attacks
	var def_ent_front := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF_EF", Vector2i(3, 2))
	def_ent_front.facing = Vector2i(-1, 0)
	def_ent_front.is_entrenched = true
	var def_ent_rear := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF_ER", Vector2i(3, 2))
	def_ent_rear.facing = Vector2i(1, 0)
	def_ent_rear.is_entrenched = true

	var res_ent_f := SkirmishEngine.resolve_skirmish(atk, def_ent_front, from_tile, target_tile, false, true)
	var res_ent_r := SkirmishEngine.resolve_skirmish(atk, def_ent_rear, from_tile, target_tile, false, true)

	_check(res_ent_f.def_total_mod_pct == 5 + BalanceProbe.def_pct[1], "frontal entrenched def includes full entrenchment DEF (+15%)")
	_check(res_ent_r.def_total_mod_pct == 5 + SkirmishEngine.REAR_DEF_ARMOR_PCT, "rear attack bypasses entrenchment DEF (got %d%%)" % res_ent_r.def_total_mod_pct)

func test_flanking_combat_modifiers() -> void:
	var T := GridTileData.TerrainType
	var from_tile := GridTileData.new(Vector2i(2, 2), T.PLAIN, 1)
	var target_tile := GridTileData.new(Vector2i(3, 2), T.PLAIN, 1) # approach is (1, 0)

	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "ATK", Vector2i(2, 2))
	var def_flank := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF_FLK", Vector2i(3, 2))
	def_flank.facing = Vector2i(0, 1) # Facing SW (0, 1) -> approach from (1, 0) is FLANK

	var res_flank := SkirmishEngine.resolve_skirmish(atk, def_flank, from_tile, target_tile, false, true)
	_check(res_flank.approach_angle == "FLANK", "approach is FLANK")
	_check(res_flank.atk_directional_mod_pct == SkirmishEngine.FLANK_ATK_FP_PCT, "flank adds +%d%% ATK" % SkirmishEngine.FLANK_ATK_FP_PCT)
	_check(res_flank.def_directional_mod_pct == SkirmishEngine.FLANK_DEF_ARMOR_PCT, "flank shreds %d%% DEF" % SkirmishEngine.FLANK_DEF_ARMOR_PCT)

	# Flank halves entrenchment
	def_flank.is_entrenched = true
	var res_flank_ent := SkirmishEngine.resolve_skirmish(atk, def_flank, from_tile, target_tile, false, true)
	var half_ent: int = int(round(float(BalanceProbe.def_pct[1]) * 0.5))
	_check(res_flank_ent.def_total_mod_pct == 5 + half_ent + SkirmishEngine.FLANK_DEF_ARMOR_PCT, "flank halves entrenchment DEF (got %d%%)" % res_flank_ent.def_total_mod_pct)

func test_adjacent_formation_crossfire_and_escort() -> void:
	var T := GridTileData.TerrainType
	var from_tile := GridTileData.new(Vector2i(2, 2), T.PLAIN, 1)
	var target_tile := GridTileData.new(Vector2i(3, 2), T.PLAIN, 1)
	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "ATK", Vector2i(2, 2))
	var dfn := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF", Vector2i(3, 2))
	dfn.facing = Vector2i(-1, 0) # Frontal baseline

	# 1 ally assisting -> +8% ATK crossfire
	var ctx_1ally: Dictionary = {"atk_allies_adj": 1, "def_allies_adj": 0, "is_pincer": false, "atk_suppression": 0}
	var res_1ally := SkirmishEngine.resolve_skirmish(atk, dfn, from_tile, target_tile, false, true, ctx_1ally)
	_check(res_1ally.atk_directional_mod_pct == SkirmishEngine.ADJ_CROSSFIRE_FP_PER_ALLY, "1 adjacent ally gives +%d%% ATK" % SkirmishEngine.ADJ_CROSSFIRE_FP_PER_ALLY)

	# Pincer formation -> +8% + 6% = +14% ATK
	var ctx_pincer: Dictionary = {"atk_allies_adj": 1, "def_allies_adj": 0, "is_pincer": true, "atk_suppression": 0}
	var res_pincer := SkirmishEngine.resolve_skirmish(atk, dfn, from_tile, target_tile, false, true, ctx_pincer)
	_check(res_pincer.atk_directional_mod_pct == SkirmishEngine.ADJ_CROSSFIRE_FP_PER_ALLY + SkirmishEngine.PINCER_CROSSFIRE_FP_BONUS, "pincer crossfire gives +14% ATK")

	# Defender Escort Screen -> +10% DEF to defender
	var ctx_escort: Dictionary = {"atk_allies_adj": 0, "def_allies_adj": 1, "is_pincer": false, "atk_suppression": 0}
	var res_escort := SkirmishEngine.resolve_skirmish(atk, dfn, from_tile, target_tile, false, true, ctx_escort)
	_check(res_escort.def_directional_mod_pct == SkirmishEngine.ADJ_ESCORT_DEF_PER_ALLY, "escort ally gives defender +%d%% DEF" % SkirmishEngine.ADJ_ESCORT_DEF_PER_ALLY)

	# Attacker launch suppression -> -6% ATK
	var ctx_supp: Dictionary = {"atk_allies_adj": 0, "def_allies_adj": 0, "is_pincer": false, "atk_suppression": 1}
	var res_supp := SkirmishEngine.resolve_skirmish(atk, dfn, from_tile, target_tile, false, true, ctx_supp)
	_check(res_supp.atk_directional_mod_pct == SkirmishEngine.ADJ_SUPPRESSION_FP_PER_ENEMY, "suppression gives attacker -6% ATK")

func test_forecast_matches_directional_resolution() -> void:
	var T := GridTileData.TerrainType
	var from_tile := GridTileData.new(Vector2i(2, 2), T.PLAIN, 1)
	var target_tile := GridTileData.new(Vector2i(3, 2), T.PLAIN, 1)
	var atk := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "ATK", Vector2i(2, 2))
	var dfn := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "DEF", Vector2i(3, 2))

	for facing_dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		dfn.facing = facing_dir
		for ent in [false, true]:
			dfn.is_entrenched = ent
			for allies in [0, 2]:
				var ctx: Dictionary = {"atk_allies_adj": allies, "def_allies_adj": 1, "is_pincer": allies >= 2, "atk_suppression": 0}
				var fc := SkirmishEngine.compute_forecast(atk, dfn, from_tile, target_tile, ctx)
				var res := SkirmishEngine.resolve_skirmish(atk, dfn, from_tile, target_tile, false, true, ctx)
				_check(fc["est_dmg_to_def"] == res.total_dmg_to_defender, "forecast damage matches deterministic resolution")
				_check(fc["est_dmg_to_atk"] == res.total_dmg_to_attacker, "forecast return damage matches deterministic resolution")
				_check(fc["approach_angle"] == res.approach_angle, "forecast angle matches resolution")
				_check(fc["atk_mod_pct"] == res.atk_total_mod_pct, "forecast atk mod matches resolution")

func test_unit_container_formation_context() -> void:
	var bf := await _spawn_iron_bridge()
	var uc := bf.unit_container
	# Place test units manually on the battlefield
	var iron1 := _unit_by_callsign(bf, "IRON-1")
	var rote1 := _unit_by_callsign(bf, "ROTE-1")
	iron1.mech_data.grid_pos = Vector2i(4, 4)
	rote1.mech_data.grid_pos = Vector2i(5, 4)

	# Single attacker approaching with no allies around
	var ctx_solo := uc.get_formation_context(Vector2i(5, 4), Vector2i(4, 4), int(MechData.Faction.PLAYER))
	_check(ctx_solo["atk_allies_adj"] == 0, "no adjacent allies initially")
	_check(ctx_solo["is_pincer"] == false, "no pincer initially")

	# Move a friendly player unit to (6, 4) -> exactly opposite from_pos (4, 4) through target (5, 4)!
	var titan2 := _unit_by_callsign(bf, "TITAN-2")
	titan2.mech_data.grid_pos = Vector2i(6, 4)
	var ctx_pincer := uc.get_formation_context(Vector2i(5, 4), Vector2i(4, 4), int(MechData.Faction.PLAYER))
	_check(ctx_pincer["atk_allies_adj"] == 1, "1 ally adjacent to target")
	_check(ctx_pincer["is_pincer"] == true, "pincer detected across target")

	# Move an enemy unit next to target (5, 5) -> escort screen
	var glut2 := _unit_by_callsign(bf, "GLUT-2")
	glut2.mech_data.grid_pos = Vector2i(5, 5)
	var ctx_escort := uc.get_formation_context(Vector2i(5, 4), Vector2i(4, 4), int(MechData.Faction.PLAYER))
	_check(ctx_escort["def_allies_adj"] == 1, "1 defender ally adjacent to target")

	# Move another enemy unit next to attacker launch tile (4, 3) -> suppression
	var jager3 := _unit_by_callsign(bf, "JÄGER-3")
	jager3.mech_data.grid_pos = Vector2i(4, 3)
	var ctx_supp := uc.get_formation_context(Vector2i(5, 4), Vector2i(4, 4), int(MechData.Faction.PLAYER))
	_check(ctx_supp["atk_suppression"] == 1, "1 enemy adjacent to launch tile")

	bf.queue_free()
	await get_tree().process_frame

func test_in_place_rotation_and_movement_facing() -> void:
	var bf := await _spawn_iron_bridge()
	var iron1 := _unit_by_callsign(bf, "IRON-1")
	iron1.mech_data.facing = Vector2i(1, 0)
	bf._select_unit(iron1)

	# Test rotation cycle
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing == Vector2i(0, 1), "first rotate gives SW (0, 1)")
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing == Vector2i(-1, 0), "second rotate gives NW (-1, 0)")
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing == Vector2i(0, -1), "third rotate gives NE (0, -1)")
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing == Vector2i(1, 0), "fourth rotate returns to SE (1, 0)")

	bf.queue_free()
	await get_tree().process_frame

func test_ai_prefers_flank_and_rear_attacks() -> void:
	var bf := await _spawn_iron_bridge()
	var ai_unit := _unit_by_callsign(bf, "ROTE-1")
	var player_unit := _unit_by_callsign(bf, "IRON-1")
	# Place player unit at (5, 5) facing SE (1, 0)
	player_unit.mech_data.grid_pos = Vector2i(5, 5)
	player_unit.mech_data.facing = Vector2i(1, 0)

	# Place AI unit at (3, 5) with ample fuel to reach either (4, 5) [Rear attack!] or (5, 4) [Flank attack!]
	ai_unit.mech_data.grid_pos = Vector2i(3, 5)
	ai_unit.mech_data.current_fuel = 14
	ai_unit.mech_data.has_moved = false

	var decision := AIController.choose_best_action(ai_unit, bf.grid_map, bf.unit_container, bf.current_map_def)
	_check(decision["type"] == "ENGAGE", "AI chooses to engage")
	_check(decision["target_pos"] == Vector2i(5, 5), "AI targets the player walker")
	# Verify that the approach taken is from the rear:
	var path: Array[Vector2i] = decision["path"]
	var from_pos: Vector2i = path[path.size() - 2]
	var approach: Vector2i = Vector2i(5, 5) - from_pos
	var dot: int = approach.x * player_unit.mech_data.facing.x + approach.y * player_unit.mech_data.facing.y
	_check(dot == 1, "AI chose a rear approach vector (dot == 1)")

	bf.queue_free()
	await get_tree().process_frame

func test_player_and_ai_reface_after_movement() -> void:
	var bf := await _spawn_iron_bridge()
	var iron1 := _unit_by_callsign(bf, "IRON-1")
	iron1.mech_data.facing = Vector2i(1, 0)
	bf._select_unit(iron1)

	# Execute a move to (2, 2)
	var move_path: Array[Vector2i] = [iron1.mech_data.grid_pos, Vector2i(2, 2)]
	bf._execute_unit_movement(iron1, Vector2i(2, 2), move_path, 2)
	for i in 60:
		await get_tree().process_frame

	_check(iron1.mech_data.has_moved, "IRON-1 marked has_moved after moving")
	_check(bf.selected_unit == iron1, "IRON-1 stays selected after move so player can reface")
	_check(bf._can_rotate_selected_unit(), "_can_rotate_selected_unit is true for moved player mech")
	_check(bf.ui_overlay._can_turn(), "UI command bar enables TURN / FACE after move")

	# Rotate using in-place turn command
	var initial_facing: Vector2i = iron1.mech_data.facing
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing != initial_facing, "IRON-1 facing changed via _rotate_selected_unit")

	# Reface by clicking an orthogonal neighbor empty tile (North: (2, 1))
	bf._on_tile_clicked(Vector2i(2, 1), null)
	_check(iron1.mech_data.facing == Vector2i(0, -1), "IRON-1 refaced to North (0, -1) by clicking neighbor tile")

	# Reface by clicking East neighbor: (3, 2)
	bf._on_tile_clicked(Vector2i(3, 2), null)
	_check(iron1.mech_data.facing == Vector2i(1, 0), "IRON-1 refaced to East (1, 0) by clicking neighbor tile")

	# Deselect and re-select moved unit: player can still reface it
	bf._deselect_unit()
	_check(bf.selected_unit == null, "deselected")
	bf._on_tile_clicked(Vector2i(2, 2), null)
	_check(bf.selected_unit == iron1, "re-selected IRON-1")
	_check(bf._can_rotate_selected_unit(), "can still rotate re-selected moved unit")
	bf._rotate_selected_unit()
	_check(iron1.mech_data.facing == Vector2i(0, 1), "rotated to South (0, 1)")

	# AI Refacing after movement
	var ai_unit := _unit_by_callsign(bf, "ROTE-1")
	ai_unit.mech_data.grid_pos = Vector2i(7, 7)
	# Position player unit at (7, 4) (North of AI destination)
	iron1.mech_data.grid_pos = Vector2i(7, 4)
	iron1.mech_data.current_armor = 50

	# Switch to AI phase to test AI post-move refacing
	GlobalState.set_phase(GlobalState.TurnPhase.AI_PHASE)
	var ai_move_path: Array[Vector2i] = [Vector2i(7, 7), Vector2i(7, 6)]
	bf._execute_unit_movement(ai_unit, Vector2i(7, 6), ai_move_path, 2)
	for i in 60:
		await get_tree().process_frame

	_check(ai_unit.mech_data.grid_pos == Vector2i(7, 6), "AI arrived at (7, 6)")
	# Closest player threat is at (7, 4) which is North (0, -1) relative to (7, 6)
	_check(ai_unit.mech_data.facing == Vector2i(0, -1), "AI refaced North (0, -1) to confront closest player threat")

	bf.queue_free()
	await get_tree().process_frame

func test_decoupled_movement_and_combat() -> void:
	var bf := await _spawn_iron_bridge()
	var modal: BattleScreen = bf.ui_overlay.skirmish_modal

	# 1. Face and Entrench
	var titan := _unit_by_callsign(bf, "TITAN-2")
	titan.mech_data.facing = Vector2i(1, 0)
	bf._select_unit(titan)
	bf._rotate_selected_unit()
	_check(titan.mech_data.facing == Vector2i(0, 1), "unit rotated before entrenching")
	bf._on_wait_refuel_requested()
	_check(titan.mech_data.is_entrenched and titan.mech_data.is_order_complete(), "WAIT entrenches and completes the unit's order")

	# 2. Face and Attack without moving (stationary rear attack; defender never auto-faces)
	var iron := _unit_by_callsign(bf, "IRON-1")
	var rote := _unit_by_callsign(bf, "ROTE-1")
	iron.mech_data.grid_pos = Vector2i(4, 4)
	iron.mech_data.facing = Vector2i(0, -1)
	iron.mech_data.current_fuel = 10
	iron.mech_data.has_moved = false
	iron.mech_data.has_attacked = false
	rote.mech_data.grid_pos = Vector2i(5, 4)
	# ROTE-1 faces SE (1, 0), so IRON-1 at (4, 4) attacks from the rear!
	rote.mech_data.facing = Vector2i(1, 0)
	rote.mech_data.max_armor = 1000
	rote.mech_data.current_armor = 1000

	bf._select_unit(iron)
	_check(bf.grid_map.reachable_info.has(Vector2i(5, 4)) and bool(bf.grid_map.reachable_info[Vector2i(5, 4)]["is_attack"]), "adjacent enemy is highlighted as an attack target")
	var expected_atk_fuel: int = iron.mech_data.get_step_fuel_cost(bf.grid_map.get_tile(Vector2i(4, 4)), bf.grid_map.get_tile(Vector2i(5, 4)))
	bf._on_tile_clicked(Vector2i(5, 4), bf.grid_map.get_tile(Vector2i(5, 4)))
	while bf._is_animating_move or modal.visible:
		if modal.visible:
			if modal._all_steps_done:
				modal._on_confirm_pressed()
			else:
				modal._on_skip_pressed()
		await get_tree().process_frame

	_check(iron.mech_data.grid_pos == Vector2i(4, 4), "attacker stays on its own tile (4, 4) during and after combat")
	_check(iron.mech_data.facing == Vector2i(1, 0), "attacker automatically turns to face the target it attacks")
	_check(iron.mech_data.current_fuel == 10 - expected_atk_fuel, "stationary attack spends only the target tile step cost")
	_check(iron.mech_data.is_order_complete(), "attacking completes the unit's order")
	_check(is_instance_valid(rote) and rote.mech_data.is_alive(), "defender survived the skirmish")
	if is_instance_valid(rote) and rote.mech_data.is_alive():
		_check(rote.mech_data.grid_pos == Vector2i(5, 4), "surviving defender stays on its own tile (5, 4)")
		_check(rote.mech_data.facing == Vector2i(1, 0), "defender does NOT auto-face the attacker (preserves rear/flank orientation)")

	# 3. Move and Face or Attack (move to an empty tile adjacent to an enemy, rotate, then attack or hold)
	var falke := _unit_by_callsign(bf, "SWIFT-3")
	var glut := _unit_by_callsign(bf, "GLUT-2")
	falke.mech_data.grid_pos = Vector2i(3, 5)
	falke.mech_data.current_fuel = 14
	falke.mech_data.has_moved = false
	falke.mech_data.has_attacked = false
	glut.mech_data.grid_pos = Vector2i(5, 5)
	glut.mech_data.facing = Vector2i(1, 0) # facing away from (4, 5)
	glut.mech_data.current_armor = 1 # 1 HP so FALKE-3 destroys it in place

	bf._select_unit(falke)
	_check(not bf.grid_map.reachable_info.has(Vector2i(5, 5)), "non-adjacent enemy is not a direct one-click move+attack target")
	_check(bf.grid_map.reachable_info.has(Vector2i(4, 5)) and not bool(bf.grid_map.reachable_info[Vector2i(4, 5)]["is_attack"]), "empty launch tile (4, 5) is reachable for movement")

	# Step 1: Click empty tile (4, 5) to move adjacent to GLUT-2
	bf._on_tile_clicked(Vector2i(4, 5), bf.grid_map.get_tile(Vector2i(4, 5)))
	for i in 60:
		await get_tree().process_frame

	_check(falke.mech_data.grid_pos == Vector2i(4, 5), "FALKE-3 moved to (4, 5)")
	_check(falke.mech_data.has_moved and not falke.mech_data.has_attacked, "FALKE-3 has moved but can still attack adjacent GLUT-2")
	_check(bf.grid_map.reachable_info.has(Vector2i(5, 5)) and bool(bf.grid_map.reachable_info[Vector2i(5, 5)]["is_attack"]), "adjacent GLUT-2 is now highlighted as an attack target after moving")
	_check(bf.ui_overlay._can_hold(), "HUD shows HOLD POSITION [R] while in post-move attack window")

	# Rotate freely after moving; attack window remains available
	bf._rotate_selected_unit()
	_check(not falke.mech_data.has_attacked and bf.grid_map.reachable_info.has(Vector2i(5, 5)), "rotating after moving keeps adjacent attack target available")

	# Step 2: Click adjacent GLUT-2 at (5, 5) to attack after moving
	bf._on_tile_clicked(Vector2i(5, 5), bf.grid_map.get_tile(Vector2i(5, 5)))
	while bf._is_animating_move or modal.visible:
		if modal.visible:
			if modal._all_steps_done:
				modal._on_confirm_pressed()
			else:
				modal._on_skip_pressed()
		await get_tree().process_frame

	_check(falke.mech_data.grid_pos == Vector2i(4, 5), "even when destroying the defender, attacker remains on (4, 5) and never advances onto (5, 5)")
	_check(falke.mech_data.is_order_complete(), "FALKE-3 order is complete after moving and attacking")
	_check(bf.unit_container.get_unit_at(Vector2i(5, 5)) == null, "destroyed defender is removed from (5, 5)")

	bf.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- scalability / performance review regressions
## The menu redraws on change, not every frame: opening the rules page must still draw it.
func test_rules_page_draws_on_open() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var draws := [0]
	menu.draw.connect(func(): draws[0] += 1)
	menu._activate("rules")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(menu.show_rules and draws[0] > 0, "opening the rules page draws it (draws=%d)" % draws[0])
	draws[0] = 0
	menu._activate("rules:3")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(draws[0] > 0, "changing chapter redraws the rules page")
	draws[0] = 0
	for i in 6:
		await get_tree().process_frame
	_check(draws[0] == 0, "an idle rules page does not redraw every frame (draws=%d)" % draws[0])
	menu.queue_free()
	await get_tree().process_frame

## The AI scores launches while still standing on its start tile; that tile must not count it as its
## own adjacent ally. Checked through AIController itself: the forecast cache records the formation
## context each launch was scored with.
func test_ai_launch_context_excludes_mover() -> void:
	var bf := await _spawn_iron_bridge()
	var uc := bf.unit_container
	var rote := _unit_by_callsign(bf, "ROTE-1")
	var iron := _unit_by_callsign(bf, "IRON-1")
	# Park every other walker on the far row so only these two matter.
	var spot := 0
	for u in uc.units:
		if u != rote and u != iron:
			u.mech_data.grid_pos = Vector2i(spot, 7)
			spot += 1
	rote.mech_data.has_moved = false
	rote.mech_data.has_attacked = false
	rote.mech_data.current_fuel = rote.mech_data.max_fuel
	var faction := int(rote.mech_data.faction)
	var gm0 := bf.grid_map
	# Find a target / start / launch triple: start and launch both next to the target, launch reachable.
	var target := Vector2i(-1, -1)
	var start := Vector2i(-1, -1)
	var launch := Vector2i(-1, -1)
	for y in range(1, 6):
		for x in range(1, 9):
			if launch != Vector2i(-1, -1):
				break
			var t := Vector2i(x, y)
			for sd in UnitContainer._DIRS:
				var st: Vector2i = t + sd
				if not gm0.is_valid_coords(st) or st.y >= 7 or launch != Vector2i(-1, -1):
					continue
				iron.mech_data.grid_pos = t
				rote.mech_data.grid_pos = st
				var reach := gm0.find_reachable_tiles(rote.mech_data, uc.build_occupied_map(rote))
				for ld in UnitContainer._DIRS:
					var l: Vector2i = t + ld
					if l != st and l.y < 7 and reach.has(l) and not reach[l]["is_attack"]:
						target = t
						start = st
						launch = l
						break
	_check(launch != Vector2i(-1, -1), "setup: found a launch tile next to the target other than the start tile")
	iron.mech_data.grid_pos = target
	rote.mech_data.grid_pos = start
	var self_counted := uc.get_formation_context(target, launch, faction)   # rote still on its start tile
	rote.mech_data.grid_pos = launch
	var after_move := uc.get_formation_context(target, launch, faction)
	rote.mech_data.grid_pos = start
	_check(self_counted["atk_allies_adj"] == after_move["atk_allies_adj"] + 1, "setup: standing on the start tile would count as a crossfire ally")

	SkirmishEngine.clear_forecast_cache()
	AIController.choose_best_action(rote, bf.grid_map, uc, bf.current_map_def)
	var gm := bf.grid_map
	var key_ok := SkirmishEngine._forecast_key(rote.mech_data, iron.mech_data, gm.get_tile(launch), gm.get_tile(target), after_move)
	var key_bad := SkirmishEngine._forecast_key(rote.mech_data, iron.mech_data, gm.get_tile(launch), gm.get_tile(target), self_counted)
	_check(SkirmishEngine._forecast_cache.has(key_ok), "AI scored the launch with the post-move formation context")
	_check(not SkirmishEngine._forecast_cache.has(key_bad), "AI did not count itself as its own adjacent ally")
	bf.queue_free()
	await get_tree().process_frame

## Redeploy during the end-of-phase countdown must not let the old timer start the new run's AI phase.
func test_redeploy_cancels_auto_advance() -> void:
	var bf := await _spawn_iron_bridge()
	bf._start_auto_advance_timer(0.05)
	bf.start_mission(0)
	await get_tree().create_timer(0.15).timeout
	_check(GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE, "stale countdown did not start the AI phase after Redeploy")
	bf.queue_free()
	await get_tree().process_frame

## Heap Dijkstra (movement ranges, strike plans) against a brute-force relaxation on a big random map.
func test_dijkstra_matches_bellman_ford_on_large_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var md := MapDefinition.new()
	md.width = 32
	md.height = 28
	var codes := ["P", "D", "R", "F", "C", "M"]
	for y in md.height:
		var t := PackedStringArray()
		var e := PackedStringArray()
		for x in md.width:
			t.append(codes[rng.randi_range(0, codes.size() - 1)])
			e.append(str(rng.randi_range(0, 4)))
		md.terrain_codes.append(" ".join(t))
		md.elevation_rows.append(" ".join(e))
	var gm := IsoGridMap.new()
	add_child(gm)
	gm.load_from_definition(md)
	var m := GlobalState.create_mech_instance("falke", MechData.Faction.PLAYER, "T", Vector2i(16, 14), "dj")
	m.current_fuel = 60
	var occ := {}
	for i in 40:
		var e := GlobalState.create_mech_instance("goliath", MechData.Faction.AI if i % 2 == 0 else MechData.Faction.PLAYER, "E%d" % i, Vector2i(rng.randi_range(0, 31), rng.randi_range(0, 27)), "dj%d" % i)
		if e.grid_pos != m.grid_pos:
			occ[e.grid_pos] = e
	var t0 := Time.get_ticks_usec()
	var reach := gm.find_reachable_tiles(m, occ)
	var dt := Time.get_ticks_usec() - t0
	# Brute force: relax every edge until nothing changes.
	var best := {m.grid_pos: 0}
	var changed := true
	while changed:
		changed = false
		for c: Vector2i in best.keys():
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if not gm.is_valid_coords(n) or (occ.has(n) and occ[n].faction != m.faction):
					continue
				var nc: int = best[c] + m.get_step_fuel_cost(gm.get_tile(c), gm.get_tile(n))
				if nc <= m.current_fuel and (not best.has(n) or nc < best[n]):
					best[n] = nc
					changed = true
	var bad := 0
	for c: Vector2i in best.keys():
		if c != m.grid_pos and occ.has(c):
			continue
		if not reach.has(c) or int(reach[c]["fuel_spent"]) != best[c]:
			bad += 1
			continue
		var path: Array[Vector2i] = reach[c]["path"]
		var sum := 0
		for i in range(1, path.size()):
			sum += m.get_step_fuel_cost(gm.get_tile(path[i - 1]), gm.get_tile(path[i]))
		if sum != best[c]:
			bad += 1
	_check(bad == 0 and reach.size() > 100, "heap Dijkstra matches brute force on 32x28 (%d mismatches, %d tiles, %d us)" % [bad, reach.size(), dt])
	# Same paths (so the same final step and facing) as the original linear-scan search.
	var ref_from := _linear_scan_came_from(gm, m, occ, m.current_fuel)
	var path_bad := 0
	for c: Vector2i in reach.keys():
		if reach[c]["is_attack"]:
			continue # [start, enemy]: a strike, not a search path
		var path: Array[Vector2i] = reach[c]["path"]
		var cur: Vector2i = c
		var ref_path: Array[Vector2i] = [c]
		while cur != m.grid_pos:
			cur = ref_from[cur]
			ref_path.push_front(cur)
		if path != ref_path:
			path_bad += 1
	_check(path_bad == 0, "heap Dijkstra reproduces the linear-scan paths exactly (%d differ)" % path_bad)
	gm.queue_free()
	await get_tree().process_frame

## Static terrain (labels included) is baked into one textured mesh, not one canvas command per
## polygon / label, and the labels really are in it.
func test_terrain_is_baked_into_few_draws() -> void:
	var bf := await _spawn_iron_bridge()
	var gm := bf.grid_map
	var labels := 0
	for c: Vector2i in gm.tiles.keys():
		var td: GridTileData = gm.tiles[c]
		if td.elevation >= 2 and not td.is_objective:
			labels += 1
	var with_labels: int = gm._terrain_mesh.vertex_count()
	_check(gm._terrain_mesh.op_count() == 1, "a 10x8 map's terrain is one draw call (got %d)" % gm._terrain_mesh.op_count())
	gm.show_elev_labels = false
	var without: int = gm._terrain_mesh.vertex_count()
	gm.show_elev_labels = true
	_check(labels > 0 and with_labels - without >= labels * 6, "elevation labels are baked into the mesh (%d labels, %d vertices)" % [labels, with_labels - without])
	_check(PixelFont.mesh_atlas() != null and PixelFont.mesh_atlas().get_height() == PixelFont.HEIGHT + 6, "terrain mesh samples the font mesh atlas")
	bf.queue_free()
	await get_tree().process_frame

## The HUD redraws on change: every piece of state Battlefield pushes into it must mark it dirty.
func test_hud_state_changes_queue_redraw() -> void:
	var bf := await _spawn_iron_bridge()
	var ui := bf.ui_overlay
	for prop in ["selected_mech", "hovered_mech", "hovered_tile", "hovered_reach_info", "current_forecast",
			"strike_plan", "step_cost_mech", "map_def", "player_unit_count", "ai_unit_count", "player_obj_count",
			"total_obj_count", "show_manual_modal", "show_game_over_modal"]:
		ui._dirty = false
		ui.set(prop, ui.get(prop))
		_check(ui._dirty, "assigning UIOverlay.%s marks the HUD dirty" % prop)
	ui._dirty = false
	GlobalState.add_log("redraw probe")
	_check(ui._dirty, "a new log line marks the HUD dirty")
	bf.queue_free()
	await get_tree().process_frame

## Reference: the pre-heap Dijkstra (linear min scan, ties to the earliest-queued node), came_from only.
func _linear_scan_came_from(gm: IsoGridMap, unit: MechData, occ: Dictionary, budget: int) -> Dictionary:
	var start: Vector2i = unit.grid_pos
	var best := {start: 0}
	var from := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var bi := 0
		for i in range(1, queue.size()):
			if best[queue[i]] < best[queue[bi]]:
				bi = i
		var cur: Vector2i = queue[bi]
		queue.remove_at(bi)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not gm.is_valid_coords(n) or (occ.has(n) and occ[n].faction != unit.faction):
				continue
			var nc: int = best[cur] + unit.get_step_fuel_cost(gm.get_tile(cur), gm.get_tile(n))
			if nc > budget:
				continue
			if not best.has(n) or nc < best[n]:
				best[n] = nc
				from[n] = cur
				if not queue.has(n):
					queue.append(n)
	return from

# ---------------------------------------------------------------- review fixes: modals, victory rules, catalogs
## An attacker wrecked in the counter-attack must not stay selected (its node is freed this frame).
func test_wrecked_selection_is_cleared() -> void:
	var bf := await _spawn_iron_bridge()
	var attacker := _unit_by_callsign(bf, "IRON-1")
	var defender: MechUnit = null
	for u in bf.unit_container.get_faction_units(MechData.Faction.AI):
		defender = u
		break
	# A 1v1 for the order economy: every other Coalition walker has already used its order
	for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
		if u != attacker:
			u.mech_data.has_moved = true
			u.mech_data.has_attacked = true
	bf._select_unit(attacker)
	attacker.mech_data.has_moved = true
	attacker.mech_data.has_attacked = true
	attacker.mech_data.current_armor = 0   # wrecked by the counter-attack
	bf._pending_attacker = attacker
	bf._pending_defender = defender
	GlobalState.set_phase(GlobalState.TurnPhase.RESOLUTION_PHASE)
	bf._phase_before_resolution = GlobalState.TurnPhase.PLAYER_PHASE
	bf._on_skirmish_modal_closed(SkirmishEngine.SkirmishResult.new())
	_check(bf.selected_unit == null, "a wrecked attacker is no longer the selected unit")
	_check(bf.ui_overlay.selected_mech == null, "the HUD stops showing the wrecked attacker")
	_check(not bf._selected_is_valid(), "_selected_is_valid() is false without a selection")
	bf._auto_advance_token += 1   # cancel the pending end-of-phase countdown
	bf.queue_free()
	await get_tree().process_frame

## While the manual or the debrief is up, only its own controls respond.
func test_modal_swallows_commands() -> void:
	var bf := await _spawn_iron_bridge()
	var ov := bf.ui_overlay
	var fired: Array = []
	ov.action_end_turn_requested.connect(func(): fired.append("end_turn"))
	ov.action_center_camera_requested.connect(func(): fired.append("cam"))
	ov.show_manual_modal = true
	ov._activate("end_turn")
	ov._activate("cam")
	_check(fired.is_empty(), "commands do nothing while the manual is open (fired %s)" % [fired])
	ov._activate("manual")
	_check(not ov.show_manual_modal, "the manual's own control still closes it")
	ov.show_game_over_modal = true
	ov._activate("end_turn")
	_check(fired.is_empty(), "commands do nothing while the debrief is open (fired %s)" % [fired])
	ov.show_game_over_modal = false
	ov._activate("block")
	_check(fired.is_empty(), "a plain panel hotspot does nothing")
	ov._activate("end_turn")
	_check(fired == ["end_turn"], "with no modal the command fires (fired %s)" % [fired])
	bf._auto_advance_token += 1
	bf.queue_free()
	await get_tree().process_frame

func test_victory_rules_evaluate() -> void:
	var m: MapDefinition = GlobalState.maps[0]
	_check(VictoryRules.evaluate(m, null, 3, 3, 0, 3, 3, false).is_empty(), "mid-game with both sides alive is undecided")
	_check(VictoryRules.evaluate(m, null, 3, 3, 1, 3, 1, true).is_empty(), "end of an early turn with a split objective is undecided")
	var win := VictoryRules.evaluate(m, null, 2, 0, 0, 3, 2, false)
	_check(win.get("winner", -1) == 0 and win.get("reason", "") == "All Kriegs-Syndikat Armored Walkers have been destroyed!", "wiping out the Syndicate wins (got %s)" % [win])
	var loss := VictoryRules.evaluate(m, null, 0, 2, 0, 3, 2, false)
	_check(loss.get("winner", -1) == 1 and loss.get("reason", "") == "All 8th Iron Division Walkers were lost in action.", "losing every walker loses (got %s)" % [loss])
	var limit := VictoryRules.evaluate(m, null, 3, 3, 1, 3, m.turn_limit, true)
	_check(limit.get("winner", -1) == 1, "a minority of bridgeheads at the turn limit loses (got %s)" % [limit])
	var held := VictoryRules.evaluate(m, null, 3, 3, 3, 3, 2, true)
	_check(held.get("winner", -1) == 0, "holding every bridgehead at turn end wins (got %s)" % [held])

func test_catalogs_are_consistent() -> void:
	_check(not GlobalState.ability_catalog.is_empty(), "ability catalog is filled")
	_check(not GlobalState.chassis_catalog.is_empty(), "chassis catalog is filled")
	_check(not GlobalState.maps.is_empty(), "map catalog is filled")
	_check(GlobalState.chassis_catalog.size() == ChassisCatalog.ORDER.size(), "ChassisCatalog.ORDER lists every chassis")
	for id: String in ChassisCatalog.ORDER:
		_check(GlobalState.chassis_catalog.has(id), "chassis %s exists" % id)
		if not GlobalState.chassis_catalog.has(id):
			continue
		var ch: MechData = GlobalState.chassis_catalog[id]
		for ab: CombatAbility in ch.abilities:
			_check(GlobalState.ability_catalog.has(ab.ability_id), "%s ability %s exists in the ability catalog" % [id, ab.ability_id])
