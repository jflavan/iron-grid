extends Node

## Battle screen unit tests (sprite bank, font, layout, timeline, screen contract, animations).
## Run headless:  godot --headless --path . res://tests/BattleScreenTests.tscn
## Exit code is the number of failures (0 = all checks passed).

const CHASSIS: Array[String] = ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]

var failures: Array[String] = []
var _checks: int = 0

func _ready() -> void:
	for t in [
		"test_sprite_bank_loads", "test_anchor_mirrors", "test_recoil_moves_muzzle",
		"test_side_from_approach", "test_elevation_offsets", "test_wrap_long_headline",
		"test_damage_sums", "test_hold_at_one", "test_ai_attacker_panels", "test_followup_flags", "test_capture_text",
		"test_skip_confirm_reuse", "test_full_playback_finishes",
		"test_every_weapon_has_anim", "test_every_support_has_anim", "test_persistent_effects_after_skip",
		"test_pairings_play_to_result", "test_attachment_textures_cached",
		"test_mouse_click_skips_then_confirms", "test_viewport_renders_only_while_active",
		"test_white_sheets_are_pregenerated", "test_support_run_is_pure",
		"test_crt_pixel_scale", "test_crt_glyph_coverage", "test_menu_mechs_never_overlap",
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
	# a pixel in column x lands in column w - 1 - x under the mirrored draw transform
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
	var s := "TACTICAL VICTORY (4-2) — IRON-1 (Sturmjäger) DISLODGED KRIEGS-SYNDIKAT WALKER!"
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
		elif b["card_type"] in ["BALLISTIC", "ARTILLERY", "THERMAL"]:
			_check(b["command_row"] == 0, "coalition weapon actions point at FIGHT")

func test_followup_flags() -> void:
	var r := _fight("vanguard", "moloch")
	var tl := BattleTimeline.build(r)
	_check(tl.beats[2]["card_id"] == "krupp_plate", "step 2 is Krupp plate")
	_check(tl.beats[2]["needs_followup"] == true, "armor card needs a follow-up shot")
	_check(tl.beats[0]["needs_followup"] == false, "weapon card needs no follow-up")
	_check(tl.beats[2]["command_row"] == 2, "armor card points at ARMOR")
	_check(tl.beats[3]["soften_from"] == "krupp_plate", "next incoming hit is softened by Krupp")
	_check(tl.beats[5]["soften_from"] == "", "soften is consumed once")

func test_capture_text() -> void:
	var seen := false
	for pair in [["vanguard", "moloch"], ["kommandant", "falke"], ["donner", "goliath"], ["moloch", "kommandant"]]:
		var r := _fight(pair[0], pair[1])
		var tl := BattleTimeline.build(r)
		for i in r.steps.size():
			if r.steps[i].flipped_slots.size() > 0:
				seen = true
				_check(tl.beats[i]["capture_text"] != "", "captures produce text (step %d)" % i)
			else:
				_check(tl.beats[i]["capture_text"] == "", "no capture, no text (step %d)" % i)
	_check(seen, "at least one sampled fight has a capture")

# ---------------------------------------------------------------- screen contract
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

# ---------------------------------------------------------------- animations
func test_every_weapon_has_anim() -> void:
	var n := 0
	for id in GlobalState.card_catalog:
		var card: EquipmentCard = GlobalState.card_catalog[id]
		if not BattleTimeline.is_weapon(card.category):
			continue
		n += 1
		_check(WeaponAnims.has_anim(id), "%s has a dedicated weapon animation" % id)
		for quick in [false, true]:
			var d := WeaponAnims.duration(id, quick)
			var imp := WeaponAnims.impact_time(id, quick)
			_check(d > 0.0 and imp > 0.0 and imp < d, "%s (quick=%s) impact inside duration" % [id, quick])
		_check(WeaponAnims.duration(id, true) < WeaponAnims.duration(id, false), "%s follow-up is shorter" % id)
	_check(n == 9, "nine weapon cards in the catalog, got %d" % n)

func test_every_support_has_anim() -> void:
	var n := 0
	for id in GlobalState.card_catalog:
		var card: EquipmentCard = GlobalState.card_catalog[id]
		if BattleTimeline.is_weapon(card.category):
			continue
		n += 1
		_check(SupportAnims.has_anim(id), "%s has a support animation" % id)
		_check(SupportAnims.duration(id) > 0.0, "%s support duration > 0" % id)
	_check(n == 9, "nine armor/tactical cards in the catalog, got %d" % n)

func _screen_for(r: SkirmishEngine.SkirmishResult) -> BattleScreen:
	var screen := BattleScreen.new()
	add_child(screen)
	screen.start_showdown(r)
	return screen

func test_persistent_effects_after_skip() -> void:
	# Spinne plays Anchor Struts on step 4 -> braced sheet; Siegebreaker drops its slab on step 2;
	# Brenner arms its bricks on step 4 and the defender's step-5 hit detonates them.
	var s1 := _screen_for(_fight("donner", "vanguard"))
	await get_tree().process_frame
	s1._on_skip_pressed()
	_check(s1.stage.mechs["atk"]["sheet"] == "donner_braced", "Spinne ends braced after skip")
	s1.queue_free()
	var s2 := _screen_for(_fight("goliath", "falke"))
	await get_tree().process_frame
	s2._on_skip_pressed()
	_check(s2.stage.mechs["atk"]["slab"] == true, "Siegebreaker slab stays up after skip")
	s2.queue_free()
	var s3 := _screen_for(_fight("moloch", "kommandant"))
	await get_tree().process_frame
	s3._on_skip_pressed()
	_check(s3.stage.mechs["atk"]["sheet"] == "moloch_spent", "Brenner bricks are spent after the next hit")
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
		while not screen._all_steps_done and frames < 3000:
			await get_tree().process_frame
			frames += 1
		_check(screen._all_steps_done, "%s vs %s plays through to the result (%d frames)" % [pairs[i][0], pairs[i][1], frames])
		_check(screen.stage.hull_display["atk"] == screen.current_result.atk_armor_after, "%s final hull matches result" % pairs[i][0])
		screen.queue_free()
	Engine.time_scale = 1.0

func test_attachment_textures_cached() -> void:
	# Draw commands keep only the RID; an uncached texture loaded in _draw is freed before rendering.
	var m := {"faction": 0}
	for att in ["slab", "mast", "rangefinder"]:
		_check(SupportAnims._attach_tex(att, m) != null, "%s attachment texture loads" % att)
	# held by the static cache, not just by the caller
	_check(SupportAnims._attach_cache.size() >= 3, "attachment textures are retained across frames")

# ---------------------------------------------------------------- review fixes
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
		_check(w != null and w.resource_path.ends_with("_white.png"), "%s white flash sheet is a pre-generated PNG (no per-pixel build at impact)" % c)
		if w != null:
			_check(w.get_width() == MechSpriteBank.get_sheet(c, 0).get_width(), "%s white sheet matches sheet size" % c)

func test_support_run_is_pure() -> void:
	var screen := _screen_for(_fight("donner", "goliath"))
	await get_tree().process_frame
	var st := screen.stage
	for card in ["anchor_strut", "ferro_bulkhead", "ablative_shield"]:
		var a: Dictionary = st.mechs["atk"]
		var d: Dictionary = st.mechs["def"]
		var before := [a["sheet"], a["slab"], a["armed"]]
		for t in [0.2, 0.5, 0.9]:
			SupportAnims.run(st, a, d, card, t)
		_check([a["sheet"], a["slab"], a["armed"]] == before, "%s animation does not mutate lasting state" % card)
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
		for c: EquipmentCard in ch.deck:
			strings.append_array([c.card_name, c.category, c.description])
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
