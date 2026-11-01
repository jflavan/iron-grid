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
