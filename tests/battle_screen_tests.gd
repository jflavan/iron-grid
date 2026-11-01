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
	_check(is_equal_approx(b.x, w - a.x), "mirrored anchor x = w - x (got %s vs %s)" % [b, a])
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
