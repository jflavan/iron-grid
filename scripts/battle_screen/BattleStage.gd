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

const C_LABEL := CrtUI.C_LABEL
const C_NAME := CrtUI.C_NAME
const C_NUM := CrtUI.C_NUM
const C_CURSOR := CrtUI.C_CURSOR
const C_GAUGE_BG := CrtUI.C_GAUGE_BG
const C_FUEL := CrtUI.C_FUEL
const C_HULL := CrtUI.C_HULL

const COMMANDS := ["FIGHT", "WEAPON", "ARMOR", "TACTIC"]
const CHASSIS_NAMES := {
	"vanguard": "STURMJÄGER", "goliath": "SIEGEBREAKER", "falke": "SPÄHFALKE",
	"donner": "SPINNE", "kommandant": "KAISERSTUHL", "moloch": "BRENNER",
}

const INTRO_DUR := 0.6
const SETTLE_DUR := 0.45
const CAPTURE_DUR := 0.9
const ENDING_DUR := 1.0
const DESTROY_DUR := 2.2

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
var _persist_done: Dictionary = {}   # beat index -> true once its card's lasting effect applied
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
	_persist_done.clear()
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
		# lasting state for the rest of the fight
		"slab": false, "armed": false, "dark": false, "sink": 0.0, "end_offset": Vector2.ZERO,
		# per-frame effect state (reset every frame)
		"glitch": 0.0, "ghosts": [], "glow": Color(0, 0, 0, 0), "attach": {}, "bricks_glow": 0.0, "sheet_vis": "",
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
	# Replay the lasting effects (and soften consumption) of everything not yet shown.
	var first_unhit := maxi(0, beat_idx)
	if phase in ["attack", "settle"] and _impact_done:
		first_unhit = beat_idx + 1
	for i in range(maxi(0, beat_idx), timeline.beats.size()):
		_apply_persistent(i)
		if i >= first_unhit:
			var b: Dictionary = timeline.beats[i]
			if b["soften_from"] != "":
				SupportAnims.consume_soften(self, mechs[b["target"]], b["soften_from"])
	beat_idx = timeline.beats.size()
	_apply_ending_final()
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
			return DESTROY_DUR if timeline.ending.begins_with("destroy") else ENDING_DUR
	return 0.0

func _next_phase() -> void:
	match phase:
		"intro":
			_start_beat(0)
		"menu":
			_enter("support" if current_beat()["needs_followup"] else "attack")
		"support":
			_apply_persistent(beat_idx)
			_enter("attack")
		"attack":
			if not _impact_done:
				_apply_impact(current_beat())
			_enter("settle")
		"settle":
			_start_beat(beat_idx + 1)
		"ending":
			_apply_ending_final()
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

func _support_duration(b: Dictionary) -> float:
	return SupportAnims.duration(b["card_id"])

func _apply_persistent(i: int) -> void:
	if i < 0 or i >= timeline.beats.size() or _persist_done.has(i):
		return
	_persist_done[i] = true
	var b: Dictionary = timeline.beats[i]
	if b["needs_followup"]:
		SupportAnims.apply_persistent(self, mechs[b["actor"]], b["card_id"])

func _ending_losers() -> Array:
	match timeline.ending:
		"destroy_def":
			return ["def"]
		"destroy_atk":
			return ["atk"]
		"destroy_both":
			return ["atk", "def"]
	return []

func _apply_ending_final() -> void:
	for side in _ending_losers():
		var m: Dictionary = mechs[side]
		m["dark"] = true
		m["sink"] = MechSpriteBank.cell_size(m["sheet"]).y * 0.45
	if timeline.ending == "pushback":
		mechs["def"]["end_offset"] = Vector2(-8 * int(mechs["def"]["dir"]), 1)
	elif timeline.ending == "repelled":
		mechs["atk"]["end_offset"] = Vector2(-8 * int(mechs["atk"]["dir"]), 0)

func _apply_impact(b: Dictionary) -> void:
	if b.is_empty() or _impact_done:
		return
	_impact_done = true
	var target: String = b["target"]
	true_hull[target] = int(true_hull[target]) - int(b["damage"])
	if b["soften_from"] != "":
		SupportAnims.consume_soften(self, mechs[target], b["soften_from"])
	hull_display[target] = b["hull_after"][target]
	numbers.append({"value": int(b["damage"]), "pos": point(mechs[target], "hull"), "age": 0.0})
	SoundManager.play("cannon_fire", randf_range(0.9, 1.08))

# ---------------------------------------------------------------- helpers for animations
func fx(c: Callable) -> void:
	_fx.append(c)

## Sheet drawn this frame: a support animation may preview a variant before it becomes lasting.
func sheet_of(m: Dictionary) -> String:
	return m["sheet_vis"] if m.get("sheet_vis", "") != "" else m["sheet"]

func pose_of(m: Dictionary) -> String:
	if m["pose"] != "":
		return m["pose"]
	return MechSpriteBank.idle_pose(sheet_of(m), clock * 1000.0 + float(m["idle_shift_ms"]))

func point(m: Dictionary, anchor_name: String) -> Vector2:
	return m["base"] + m["offset"] + MechSpriteBank.anchor(sheet_of(m), anchor_name, pose_of(m), m["mirrored"])

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
		m["offset"] = m["end_offset"]
		m["white"] = false
		m["glitch"] = 0.0
		m["ghosts"] = []
		m["glow"] = Color(0, 0, 0, 0)
		m["attach"] = {}
		m["sheet_vis"] = ""
		m["bricks_glow"] = 0.4 if m["armed"] and int(clock / 0.3) % 2 == 0 else 0.0
	_fx.clear()
	# Hold-at-1: a walker whose real hull is gone keeps acting but staggers, sparks and smokes.
	if phase not in ["ending", "result"]:
		for side in mechs:
			if int(true_hull[side]) <= 0:
				var m: Dictionary = mechs[side]
				m["pose"] = "stagger"
				var h := point(m, "hull")
				var k := fmod(clock * 1.7 + (0.5 if side == "def" else 0.0), 1.0)
				fx(func(ci):
					BattleFX.sparks(ci, h + Vector2(4, -6), k, 4, 10.0, 7)
					BattleFX.blob(ci, h + Vector2(-6, -12 - k * 14), int(2 + k * 4), Color(0.25, 0.24, 0.22, 0.8 * (1.0 - k))))
	if phase == "ending":
		_animate_ending()
		return
	var b := current_beat()
	if b.is_empty():
		return
	var a: Dictionary = mechs[b["actor"]]
	var d: Dictionary = mechs[b["target"]]
	match phase:
		"support":
			SupportAnims.run(self, a, d, b["card_id"], phase_t)
		"attack":
			var card := _attack_card(b)
			var quick: bool = b["needs_followup"]
			if b["card_id"] == "recon_lock":
				a["attach"] = {"rangefinder": 1.0}
			elif b["card_id"] == "cmd_override":
				a["attach"] = {"mast": 1.0}
				a["glow"] = Color(0.3, 1.0, 0.4, 0.3)
			elif b["card_id"] == "plunging_comp":
				SupportAnims.draw_plot_arc(self, a, d, 1.0)
			WeaponAnims.run(self, a, d, card, phase_t, quick)
			var imp := WeaponAnims.impact_time(card, quick)
			if b["soften_from"] != "" and phase_t >= imp:
				SupportAnims.soften(self, a, d, b["soften_from"], phase_t - imp)

func _animate_ending() -> void:
	var t := phase_t
	match timeline.ending:
		"pushback":
			var m: Dictionary = mechs["def"]
			var k := clampf(t / 0.6, 0.0, 1.0)
			m["offset"] = Vector2(roundf(-8.0 * k * int(m["dir"])), roundf(k))
			m["pose"] = "hit" if t < 0.5 else "stagger"
		"repelled":
			var m: Dictionary = mechs["atk"]
			var k := clampf(t / 0.6, 0.0, 1.0)
			m["offset"] = Vector2(roundf(-8.0 * k * int(m["dir"])), 0)
			m["pose"] = "hit" if t < 0.5 else "brace"
		_:
			for side in _ending_losers():
				var m: Dictionary = mechs[side]
				m["pose"] = "stagger"
				var h := point(m, "hull")
				var size := MechSpriteBank.cell_size(m["sheet"])
				for i in 6:
					var t0 := i * 0.22
					if t >= t0 and t < t0 + 0.6:
						var k := (t - t0) / 0.6
						var p := h + Vector2(((i * 13) % 7 - 3) * size.x * 0.08, ((i * 5) % 5 - 2) * size.y * 0.08)
						var sz := 1.0 + (i % 2) * 0.4
						fx(func(ci): BattleFX.explosion(ci, p, k, sz))
				if t < 1.3:
					m["white"] = int(t / 0.08) % 2 == 0
					m["offset"] += Vector2(roundf(sin(t * 50.0) * 2.0), 0)
				if t > 1.2:
					var k := clampf((t - 1.2) / 0.9, 0.0, 1.0)
					m["sink"] = size.y * 0.45 * k
					m["dark"] = k > 0.15

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
	for m in mechs.values():
		if m["slab"]:
			SupportAnims.draw_slab(self, self, m)
		for att in m["attach"]:
			SupportAnims.draw_attachment(self, self, m, att, float(m["attach"][att]))
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
	var tex := MechSpriteBank.get_sheet(sheet_of(m), m["faction"])
	if tex == null:
		return
	var src := MechSpriteBank.frame_rect(sheet_of(m), pose)
	var pos: Vector2 = m["base"] + m["offset"]
	var needs_white: bool = m["white"] or m["ghosts"].size() > 0 or m["glow"].a > 0.0
	var white := MechSpriteBank.get_white_sheet(sheet_of(m)) if needs_white else null
	# sinking wreck: only the part above the ground line is drawn
	var sink := roundf(float(m["sink"]))
	var visible_h := src.size.y - sink
	if visible_h <= 0:
		return
	var src_vis := Rect2(src.position, Vector2(src.size.x, visible_h))
	var dst_pos := Vector2(0, sink)
	var mod := Color(0.32, 0.30, 0.28) if m["dark"] else Color.WHITE
	for g in m["ghosts"]:
		_begin_mech_xform(m, pos + g, src.size)
		if white != null:
			draw_texture_rect_region(white, Rect2(dst_pos, src_vis.size), src_vis, Color(0.7, 0.8, 0.9, 0.35))
	_begin_mech_xform(m, pos, src.size)
	var glitch: float = m["glitch"]
	if glitch > 0.0:
		var y := 0.0
		var band := 4.0
		while y < visible_h:
			var hh := minf(band, visible_h - y)
			var shift := roundf(sin(clock * 37.0 + y * 0.9) * 4.0 * glitch) if int(y / band) % 2 == 0 else 0.0
			draw_texture_rect_region(tex, Rect2(Vector2(shift, sink + y), Vector2(src.size.x, hh)), Rect2(src.position + Vector2(0, y), Vector2(src.size.x, hh)), mod)
			y += band
	else:
		draw_texture_rect_region(tex, Rect2(dst_pos, src_vis.size), src_vis, mod)
	if white != null:
		if m["white"]:
			draw_texture_rect_region(white, Rect2(dst_pos, src_vis.size), src_vis)
		elif m["glow"].a > 0.0:
			draw_texture_rect_region(white, Rect2(dst_pos, src_vis.size), src_vis, m["glow"])
	if m["bricks_glow"] > 0.0 and not m["dark"]:
		var br = MechSpriteBank.meta_for(m["chassis"]).get("anchors", {}).get("bricks", null)
		if br != null:
			var off := MechSpriteBank.pose_offset(sheet_of(m), pose)
			draw_rect(Rect2(Vector2(br[0], br[1]) + off, Vector2(31, 19)), Color(1.0, 0.7, 0.2, m["bricks_glow"] * 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not m["dark"]:
		var stacks: Array = MechSpriteBank.meta_for(sheet_of(m)).get("anchors", {}).get("stacks", [])
		for i in stacks.size():
			BattleFX.exhaust(self, point(m, "stacks/%d" % i), clock, i * 0.37 + (0.2 if m["side"] == "def" else 0.0), m["dir"])
	elif sink > 0.0:
		BattleFX.exhaust(self, point(m, "hull") + Vector2(0, sink), clock * 0.7, 0.1, m["dir"])

func _begin_mech_xform(m: Dictionary, pos: Vector2, size: Vector2) -> void:
	if m["mirrored"]:
		draw_set_transform(Vector2(pos.x + size.x, pos.y), 0.0, Vector2(-1, 1))
	else:
		draw_set_transform(pos, 0.0, Vector2.ONE)

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
