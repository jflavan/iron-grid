class_name BattleStage
extends Node2D

## Draws and sequences one skirmish at native 360x225 (rendered inside a SubViewport and scaled 4x).
## Playback is a phase machine over BattleTimeline beats:
##   intro -> [menu -> (support) -> attack -> settle] x6 -> ending -> result
## Animations are pure functions of phase-local time evaluated in _draw, so skipping or large
## frame deltas never leave stale state behind.

const W := 360
const H := 225
const GROUND_Y := 141.0
const FEET_X := {"left": 92.0, "right": 268.0}
const MENU_Y := 153

const C_LABEL := Color("#3ad06a")
const C_NAME := Color("#e8b040")
const C_NUM := Color("#e8e8d0")
const C_CURSOR := Color("#ffe080")
const C_GAUGE_BG := Color("#16301c")
const C_FUEL := Color("#e0a030")
const C_HULL := Color("#e04838")

const COMMANDS := ["FIGHT", "WEAPON", "ARMOR", "TACTIC"]
const CHASSIS_NAMES := {
	"vanguard": "STURMJÄGER", "goliath": "SIEGEBREAKER", "falke": "SPÄHFALKE",
	"donner": "SPINNE", "kommandant": "KAISERSTUHL", "moloch": "BRENNER",
}

const INTRO_DUR := 0.6
const SETTLE_DUR := 0.45
const CAPTURE_DUR := 0.9
const ENDING_DUR := 0.6

var result: SkirmishEngine.SkirmishResult
var timeline: BattleTimeline
var mechs: Dictionary = {}          # "atk"/"def" -> state Dictionary
var hull_display: Dictionary = {"atk": 0, "def": 0}
var true_hull: Dictionary = {"atk": 0, "def": 0}
var finished: bool = false
var speed_label: String = ""

var phase: String = "idle"
var phase_t: float = 0.0
var beat_idx: int = -1
var clock: float = 0.0
var numbers: Array[Dictionary] = []
var _impact_done: bool = false
var _fx: Array[Callable] = []
var _backdrop: Texture2D

# ---------------------------------------------------------------- setup / control
func setup(p_result: SkirmishEngine.SkirmishResult, p_timeline: BattleTimeline) -> void:
	result = p_result
	timeline = p_timeline
	finished = false
	phase = "intro"
	phase_t = 0.0
	beat_idx = -1
	clock = 0.0
	numbers.clear()
	_impact_done = false
	hull_display = timeline.start_hull.duplicate()
	true_hull = timeline.start_hull.duplicate()
	_backdrop = load(BattleLayout.backdrop_path(result.target_tile.terrain_type)) as Texture2D
	var atk_left := BattleLayout.attacker_on_left(result.from_tile.coords, result.target_tile.coords)
	var lift := BattleLayout.elevation_offsets(result.elev_diff)
	mechs = {
		"atk": _make_mech("atk", result.attacker, atk_left, lift.x),
		"def": _make_mech("def", result.defender, not atk_left, lift.y),
	}
	queue_redraw()

func _make_mech(side: String, data: MechData, on_left: bool, lift: int) -> Dictionary:
	var m := {
		"side": side, "data": data, "chassis": data.chassis_id, "sheet": data.chassis_id,
		"faction": int(data.faction), "mirrored": not on_left, "dir": 1 if on_left else -1,
		"base": Vector2.ZERO, "pose": "", "offset": Vector2.ZERO, "white": false,
		"visible": true, "idle_shift_ms": 0.0 if side == "atk" else 420.0,
	}
	var feet := MechSpriteBank.anchor(m["sheet"], "feet", "idle0", m["mirrored"])
	var fx: float = FEET_X["left" if on_left else "right"]
	m["base"] = Vector2(roundf(fx - feet.x), roundf(GROUND_Y - feet.y + lift))
	return m

func skip_to_end() -> void:
	if finished:
		return
	hull_display = timeline.end_hull.duplicate()
	true_hull = timeline.end_hull.duplicate()
	numbers.clear()
	beat_idx = timeline.beats.size()
	_enter("result")
	queue_redraw()

func advance(delta: float) -> void:
	if result == null:
		return
	clock += delta
	for n in numbers:
		n["age"] += delta
	numbers = numbers.filter(func(n): return n["age"] < 1.6)
	if phase == "result":
		queue_redraw()
		return
	phase_t += delta
	while true:
		if phase == "attack" and not _impact_done and phase_t >= _attack_impact_time():
			_apply_impact(current_beat())
		var dur := _phase_duration()
		if phase == "result" or phase_t < dur:
			break
		phase_t -= dur
		_next_phase()
	queue_redraw()

func current_beat() -> Dictionary:
	if beat_idx >= 0 and beat_idx < timeline.beats.size():
		return timeline.beats[beat_idx]
	return {}

# ---------------------------------------------------------------- phase machine
func _phase_duration() -> float:
	var b := current_beat()
	match phase:
		"intro":
			return INTRO_DUR
		"menu":
			return 0.3 + 0.12 * maxi(0, int(b["command_row"])) if int(b["command_row"]) >= 0 else 0.25
		"support":
			return _support_duration(b)
		"attack":
			return WeaponAnims.duration(_attack_card(b), b["needs_followup"])
		"settle":
			return CAPTURE_DUR if b["capture_text"] != "" else SETTLE_DUR
		"ending":
			return ENDING_DUR
	return 0.0

func _next_phase() -> void:
	match phase:
		"intro":
			_start_beat(0)
		"menu":
			_enter("support" if current_beat()["needs_followup"] else "attack")
		"support":
			_enter("attack")
		"attack":
			if not _impact_done:
				_apply_impact(current_beat())
			_enter("settle")
		"settle":
			_start_beat(beat_idx + 1)
		"ending":
			_enter("result")

func _start_beat(i: int) -> void:
	beat_idx = i
	if i >= timeline.beats.size():
		_enter("ending")
		return
	_impact_done = false
	_enter("menu")
	if int(current_beat()["command_row"]) >= 0:
		SoundManager.play("ui_click")

func _enter(p: String) -> void:
	phase = p
	if p == "result":
		finished = true
		hull_display = timeline.end_hull.duplicate()

func _attack_card(b: Dictionary) -> String:
	if b["needs_followup"]:
		return String(MechSpriteBank.meta_for(mechs[b["actor"]]["sheet"]).get("basic_weapon", "kwk_88"))
	return b["card_id"]

func _attack_impact_time() -> float:
	var b := current_beat()
	return WeaponAnims.impact_time(_attack_card(b), b["needs_followup"])

func _support_duration(_b: Dictionary) -> float:
	return 0.6

func _apply_impact(b: Dictionary) -> void:
	if b.is_empty() or _impact_done:
		return
	_impact_done = true
	var target: String = b["target"]
	true_hull[target] = int(true_hull[target]) - int(b["damage"])
	hull_display[target] = b["hull_after"][target]
	numbers.append({"value": int(b["damage"]), "pos": point(mechs[target], "hull"), "age": 0.0})
	SoundManager.play("cannon_fire", randf_range(0.9, 1.08))

# ---------------------------------------------------------------- helpers for animations
func fx(c: Callable) -> void:
	_fx.append(c)

func pose_of(m: Dictionary) -> String:
	if m["pose"] != "":
		return m["pose"]
	return MechSpriteBank.idle_pose(m["sheet"], clock * 1000.0 + float(m["idle_shift_ms"]))

func point(m: Dictionary, anchor_name: String) -> Vector2:
	return m["base"] + m["offset"] + MechSpriteBank.anchor(m["sheet"], anchor_name, pose_of(m), m["mirrored"])

func coalition_mech() -> Dictionary:
	return mechs[timeline.coalition_side]

func syndikat_mech() -> Dictionary:
	return mechs["def" if timeline.coalition_side == "atk" else "atk"]

static func short_callsign(s: String) -> String:
	var i := s.find(" (")
	return s.substr(0, i) if i > 0 else s

# ---------------------------------------------------------------- drawing
func _animate() -> void:
	for m in mechs.values():
		m["pose"] = ""
		m["offset"] = Vector2.ZERO
		m["white"] = false
	_fx.clear()
	var b := current_beat()
	if b.is_empty():
		return
	var a: Dictionary = mechs[b["actor"]]
	var d: Dictionary = mechs[b["target"]]
	match phase:
		"menu":
			a["pose"] = ""
		"support":
			a["pose"] = "brace"
		"attack":
			WeaponAnims.run(self, a, d, _attack_card(b), phase_t, b["needs_followup"])

func _draw() -> void:
	if result == null:
		return
	_animate()
	draw_texture(_backdrop, Vector2.ZERO)
	for m in mechs.values():
		var feet := point(m, "feet")
		BattleFX.shadow(self, feet.x, GROUND_Y, int(MechSpriteBank.cell_size(m["sheet"]).x * 0.32))
	for side in ["def", "atk"] if phase != "attack" or current_beat().get("actor", "atk") == "atk" else ["atk", "def"]:
		_draw_mech(mechs[side])
	for c in _fx:
		c.call(self)
	for n in numbers:
		BattleFX.damage_number(self, n["value"], n["pos"], n["age"])
	_draw_menu()
	_draw_banner()

func _draw_mech(m: Dictionary) -> void:
	if not m["visible"]:
		return
	var pose := pose_of(m)
	var tex := MechSpriteBank.get_sheet(m["sheet"], m["faction"])
	if tex == null:
		return
	var src := MechSpriteBank.frame_rect(m["sheet"], pose)
	var pos: Vector2 = m["base"] + m["offset"]
	if m["mirrored"]:
		draw_set_transform(Vector2(pos.x + src.size.x, pos.y), 0.0, Vector2(-1, 1))
	else:
		draw_set_transform(pos, 0.0, Vector2.ONE)
	draw_texture_rect_region(tex, Rect2(Vector2.ZERO, src.size), src)
	if m["white"]:
		var white := MechSpriteBank.get_white_sheet(m["sheet"], m["faction"])
		if white != null:
			draw_texture_rect_region(white, Rect2(Vector2.ZERO, src.size), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var stacks: Array = MechSpriteBank.meta_for(m["sheet"]).get("anchors", {}).get("stacks", [])
	for i in stacks.size():
		BattleFX.exhaust(self, point(m, "stacks/%d" % i), clock, i * 0.37 + (0.2 if m["side"] == "def" else 0.0), m["dir"])

func _draw_menu() -> void:
	var syn := syndikat_mech()
	var coa := coalition_mech()
	BattleFX.panel(self, Rect2(2, MENU_Y, 108, 70))
	BattleFX.panel(self, Rect2(112, MENU_Y, 246, 70))
	var sd: MechData = syn["data"]
	PixelFont.draw_text(self, short_callsign(sd.callsign), Vector2(8, MENU_Y + 8), C_NAME)
	PixelFont.draw_text(self, "KS-RED", Vector2(8, MENU_Y + 20), C_LABEL)
	PixelFont.draw_text(self, CHASSIS_NAMES.get(sd.chassis_id, sd.chassis_id.to_upper()), Vector2(8, MENU_Y + 32), C_LABEL.darkened(0.25))
	var tile := result.target_tile
	PixelFont.draw_text(self, "%s %dm" % [tile.get_terrain_short_code(), tile.get_elevation_meters()], Vector2(8, MENU_Y + 56), C_LABEL)

	var cd: MechData = coa["data"]
	PixelFont.draw_text(self, short_callsign(cd.callsign), Vector2(200, MENU_Y + 8), C_NAME)
	PixelFont.draw_text(self, "FUEL", Vector2(200, MENU_Y + 23), C_LABEL)
	_gauge(Rect2(286, MENU_Y + 25, 64, 4), cd.get_fuel_ratio(), C_FUEL)
	_right_text("%d/%d" % [cd.current_fuel, cd.max_fuel], 350, MENU_Y + 32, C_NUM)
	PixelFont.draw_text(self, "HULL", Vector2(200, MENU_Y + 43), C_LABEL)
	var side: String = timeline.coalition_side
	var hull := int(hull_display[side])
	_gauge(Rect2(286, MENU_Y + 45, 64, 3), clampf(float(hull) / maxf(1.0, float(cd.max_armor)), 0.0, 1.0), C_HULL)
	_right_text("%d/%d" % [hull, cd.max_armor], 350, MENU_Y + 53, C_NUM)
	if speed_label != "":
		_right_text(speed_label, 350, MENU_Y + 8, C_LABEL.darkened(0.3))

	var b := current_beat()
	if phase == "menu" and int(b.get("command_row", -1)) >= 0:
		BattleFX.panel(self, Rect2(116, MENU_Y + 4, 76, 62))
		for i in COMMANDS.size():
			PixelFont.draw_text(self, COMMANDS[i], Vector2(132, MENU_Y + 12 + i * 13), C_NAME)
		var target_row := int(b["command_row"])
		var row := mini(target_row, int(phase_t / 0.12))
		if int(clock / 0.18) % 2 == 0 or row == target_row:
			var cy := MENU_Y + 12 + row * 13
			draw_colored_polygon(PackedVector2Array([Vector2(122, cy), Vector2(128, cy + 3.5), Vector2(122, cy + 7)]), C_CURSOR)

func _gauge(r: Rect2, ratio: float, col: Color) -> void:
	draw_rect(r, C_GAUGE_BG)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(ratio, 0.0, 1.0)), r.size.y)), col)

func _right_text(s: String, right_x: int, y: int, col: Color) -> void:
	PixelFont.draw_text(self, s, Vector2(right_x - PixelFont.text_width(s), y), col)

func _draw_banner() -> void:
	var b := current_beat()
	if phase in ["support", "attack", "settle"] and not b.is_empty():
		var text: String = b["card_name"].to_upper()
		var lines := [text]
		if phase == "settle" and b["capture_text"] != "":
			lines.append(b["capture_text"])
		var w := 16
		for l in lines:
			w = maxi(w, PixelFont.text_width(l) + 16)
		w = maxi(w, 168)
		var r := Rect2(roundf((W - w) / 2.0), 4, w, 6 + lines.size() * 10)
		BattleFX.panel(self, r)
		for i in lines.size():
			PixelFont.draw_centered(self, lines[i], W / 2.0, r.position.y + 4 + i * 10, C_NAME if i == 0 else C_CURSOR)
	elif phase == "result":
		var lines := PixelFont.wrap(timeline.headline.to_upper(), 300)
		var r := Rect2(24, 44, 312, 20 + lines.size() * 10 + 12)
		BattleFX.panel(self, r)
		for i in lines.size():
			PixelFont.draw_centered(self, lines[i], W / 2.0, r.position.y + 10 + i * 10, C_NAME)
		if int(clock / 0.5) % 2 == 0:
			PixelFont.draw_centered(self, "CONFIRM [SPACE]", W / 2.0, r.end.y - 14, C_LABEL)
