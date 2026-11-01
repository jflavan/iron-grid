class_name BattleStage
extends Node2D

## Draws and sequences a Final Fantasy style turn-based battle at native 360x225
## (rendered inside a SubViewport and scaled 4x).
##
## Supports both:
## 1. Live interactive BattleSession:
##    intro -> [command_select (Player) / menu -> support OR attack -> settle] ... -> ending -> result
## 2. Pre-resolved SkirmishResult playback (used by BattlePreview, tests, and skip_to_end):
##    intro -> [menu -> support OR attack -> settle] xN -> ending -> result

const W := 360
const H := 225
const GROUND_Y := 141.0
const FEET_X := {"left": 92.0, "right": 268.0}
const MENU_Y := 153

const C_LABEL := CrtUI.C_LABEL
const C_NAME := CrtUI.C_NAME
const C_NUM := CrtUI.C_NUM
const C_DIM := CrtUI.C_DIM
const C_CURSOR := CrtUI.C_CURSOR
const C_GAUGE_BG := CrtUI.C_GAUGE_BG
const C_FUEL := CrtUI.C_FUEL
const C_EN := CrtUI.C_EN
const C_HULL := CrtUI.C_HULL

const COMMANDS := ["ATTACK", "TECH", "DEFEND", "RETREAT"]
const CHASSIS_NAMES := {
	"vanguard": "STURMJÄGER", "goliath": "SIEGEBREAKER", "falke": "SPÄHFALKE",
	"donner": "SPINNE", "kommandant": "KAISERSTUHL", "moloch": "BRENNER",
}

const INTRO_DUR := 0.6
const SETTLE_DUR := 0.45
const STATUS_DUR := 0.85
const ENDING_DUR := 1.0
const DESTROY_DUR := 2.2

const CMD_BOX_RECT := Rect2(114, MENU_Y + 4, 80, 62)
const TECH_BOX_RECT := Rect2(114, MENU_Y + 4, 242, 62)
const MENU_ROW_H := 13
const CMD_ROW0_TOP := MENU_Y + 9    # first ATTACK/TECH/DEFEND/RETREAT row
const TECH_ROW0_TOP := MENU_Y + 18  # first ability row; the "TECH SYSTEMS" header sits above it
const ROW_TEXT_DY := 3              # glyph top sits this far below the row's hit-test top

var result: SkirmishEngine.SkirmishResult
var session: SkirmishEngine.BattleSession = null
var timeline: BattleTimeline
var mechs: Dictionary = {}          # "atk"/"def" -> state Dictionary
var hull_display: Dictionary = {"atk": 0, "def": 0}
var true_hull: Dictionary = {"atk": 0, "def": 0}
var energy_display: Dictionary = {"atk": 0, "def": 0}
var finished: bool = false
var speed_label: String = ""
var auto_pilot: bool = false

var phase: String = "idle"
var phase_t: float = 0.0
var beat_idx: int = -1
var clock: float = 0.0
var numbers: Array[Dictionary] = []
var _impact_done: bool = false
var _persist_done: Dictionary = {}   # beat index -> true once its ability's lasting effect applied
var _fx: Array[Callable] = []
var _backdrop: Texture2D

# Interactive Command Menu State
var menu_cursor: int = 0
var tech_cursor: int = 0
var in_tech_submenu: bool = false

# ---------------------------------------------------------------- setup / control
func setup(
	p_result: SkirmishEngine.SkirmishResult,
	p_timeline: BattleTimeline,
	p_session: SkirmishEngine.BattleSession = null
) -> void:
	result = p_result
	timeline = p_timeline
	session = p_session
	finished = false
	phase = "intro"
	phase_t = 0.0
	beat_idx = -1
	clock = 0.0
	menu_cursor = 0
	tech_cursor = 0
	in_tech_submenu = false
	numbers.clear()
	_impact_done = false
	_persist_done.clear()
	hull_display = timeline.start_hull.duplicate()
	true_hull = timeline.start_hull.duplicate()
	energy_display = timeline.start_energy.duplicate()
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
		"slab": false, "armed": false, "rangefinder_on": false, "mast_on": false, "jammed": false,
		"dark": false, "sink": 0.0, "end_offset": Vector2.ZERO,
		# per-frame effect state (reset every frame)
		"glitch": 0.0, "ghosts": [], "glow": Color(0, 0, 0, 0), "attach": {}, "bricks_glow": 0.0, "sheet_vis": "",
	}
	var feet := MechSpriteBank.anchor(m["sheet"], "feet", "idle0", m["mirrored"])
	var fx_pos: float = FEET_X["left" if on_left else "right"]
	m["base"] = Vector2(roundf(fx_pos - feet.x), roundf(GROUND_Y - feet.y + lift))
	return m

func skip_to_end() -> void:
	if finished:
		return
	# If running an interactive BattleSession, auto-resolve remaining turns first
	if session != null and not session.is_finished:
		session.auto_resolve(func(step: SkirmishEngine.TurnStep): timeline.append_step(step))
		timeline.sync_ending_from_result(result)

	hull_display = timeline.end_hull.duplicate()
	true_hull = timeline.end_hull.duplicate()
	energy_display = timeline.end_energy.duplicate()
	numbers.clear()
	in_tech_submenu = false

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

## Fast-forwards current turn animations until the next interactive `command_select` prompt
## (or `result` if the battle concludes during this exchange).
func skip_to_next_command_or_end() -> void:
	if finished or phase == "command_select":
		return
	var guard := 0
	while phase not in ["result", "command_select"] and guard < 64:
		if phase == "attack" and not _impact_done:
			_apply_impact(current_beat())
		phase_t = 0.0
		_next_phase()
		guard += 1
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
	if phase == "command_select":
		if auto_pilot:
			_trigger_auto_player_command()
		else:
			queue_redraw()
			return
	phase_t += delta
	while true:
		if phase == "attack" and not _impact_done and phase_t >= _attack_impact_time():
			_apply_impact(current_beat())
		var dur := _phase_duration()
		if phase in ["result", "command_select"] or phase_t < dur:
			break
		phase_t -= dur
		_next_phase()
	queue_redraw()

func current_beat() -> Dictionary:
	if beat_idx >= 0 and beat_idx < timeline.beats.size():
		return timeline.beats[beat_idx]
	return {}

# ---------------------------------------------------------------- interactive menu input
func move_cursor(dir: int) -> void:
	if phase != "command_select":
		return
	SoundManager.play("ui_click")
	if in_tech_submenu:
		var coa_data: MechData = coalition_mech()["data"]
		var ab_count: int = maxi(1, coa_data.abilities.size())
		tech_cursor = (tech_cursor + dir + ab_count) % ab_count
	else:
		menu_cursor = (menu_cursor + dir + COMMANDS.size()) % COMMANDS.size()
	queue_redraw()

func cancel_submenu() -> bool:
	if phase == "command_select" and in_tech_submenu:
		in_tech_submenu = false
		SoundManager.play("ui_cancel")
		queue_redraw()
		return true
	return false

func confirm_selection() -> void:
	if phase != "command_select" or session == null:
		return
	var coa_side := timeline.coalition_side
	var coa_state := session.get_combatant(coa_side)
	if not in_tech_submenu:
		match menu_cursor:
			0: # ATTACK
				SoundManager.play("ui_confirm")
				_commit_session_turn(SkirmishEngine.CommandType.ATTACK, "")
			1: # TECH
				SoundManager.play("ui_click")
				in_tech_submenu = true
				queue_redraw()
			2: # DEFEND
				SoundManager.play("ui_confirm")
				_commit_session_turn(SkirmishEngine.CommandType.DEFEND, "")
			3: # RETREAT
				if coa_side == "def" and not session.can_defender_retreat:
					SoundManager.play("ui_cancel")
					return
				SoundManager.play("ui_confirm")
				_commit_session_turn(SkirmishEngine.CommandType.RETREAT, "")
	else:
		var abilities: Array[CombatAbility] = coa_state.mech.abilities
		if tech_cursor < 0 or tech_cursor >= abilities.size():
			return
		var chosen: CombatAbility = abilities[tech_cursor]
		if not coa_state.can_use(chosen):
			SoundManager.play("ui_cancel")
			return
		SoundManager.play("ui_confirm")
		in_tech_submenu = false
		_commit_session_turn(SkirmishEngine.CommandType.TECH, chosen.ability_id)

## Row index of the menu item under `stage_pos`, or -1 when the point is outside the box, above
## the first row (header / EN meter) or below the last one. floori keeps a point just above row 0
## negative; int() would truncate -0.7 to row 0 and fire the first entry.
func menu_row_at(stage_pos: Vector2) -> int:
	if phase != "command_select":
		return -1
	var box: Rect2 = TECH_BOX_RECT if in_tech_submenu else CMD_BOX_RECT
	if not box.has_point(stage_pos):
		return -1
	var row0_top: int = TECH_ROW0_TOP if in_tech_submenu else CMD_ROW0_TOP
	var row_count: int = (coalition_mech()["data"] as MechData).abilities.size() if in_tech_submenu else COMMANDS.size()
	var row := floori((stage_pos.y - float(row0_top)) / float(MENU_ROW_H))
	return row if row >= 0 and row < row_count else -1

func handle_mouse_motion(stage_pos: Vector2) -> void:
	var row := menu_row_at(stage_pos)
	if row < 0:
		return
	if in_tech_submenu:
		if row != tech_cursor:
			tech_cursor = row
			queue_redraw()
	elif row != menu_cursor:
		menu_cursor = row
		queue_redraw()

func handle_mouse_click(stage_pos: Vector2) -> bool:
	if phase != "command_select":
		return false
	var row := menu_row_at(stage_pos)
	if row >= 0:
		if in_tech_submenu:
			tech_cursor = row
		else:
			menu_cursor = row
		confirm_selection()
		return true
	if in_tech_submenu and not TECH_BOX_RECT.has_point(stage_pos):
		cancel_submenu()
		return true
	return false

## Auto-Pilot: the AI plays the player's turn from command_select.
func _trigger_auto_player_command() -> void:
	if session == null or session.is_finished:
		return
	in_tech_submenu = false
	_show_committed_turn(_record_step(session.run_ai_turn()))

## Appends a live-session step's beat and syncs the ending once the session concludes. Returns
## false when there was no step (the session had already concluded).
## Unit HP/EN are written back once, by BattleScreen._finish(), when the whole fight is over.
func _record_step(step: SkirmishEngine.TurnStep) -> bool:
	if step != null:
		timeline.append_step(step)
	if session.is_finished:
		timeline.sync_ending_from_result(result)
	return step != null

## Player chose a command from the menu.
func _commit_session_turn(cmd_type: int, ability_id: String) -> void:
	if session == null or session.is_finished:
		return
	_show_committed_turn(_record_step(session.execute_next_turn(cmd_type, ability_id)))

## Starts animating the beat a player (or Auto-Pilot) turn just produced.
func _show_committed_turn(had_step: bool) -> void:
	if not had_step:
		_enter("ending")
		return
	beat_idx = timeline.beats.size() - 1
	_impact_done = false
	phase_t = 0.0
	var b := current_beat()
	energy_display[b["actor"]] = b["energy_after"][b["actor"]]
	_enter("support" if b["is_support_only"] else "attack")

# ---------------------------------------------------------------- phase machine
func _phase_duration() -> float:
	var b := current_beat()
	match phase:
		"intro":
			return INTRO_DUR
		"menu":
			return 0.28 + 0.10 * maxi(0, int(b["command_row"])) if int(b["command_row"]) >= 0 else 0.22
		"support":
			return _support_duration(b)
		"attack":
			return WeaponAnims.duration(_attack_ability(b))
		"settle":
			return STATUS_DUR if b["status_text"] != "" else SETTLE_DUR
		"ending":
			return DESTROY_DUR if timeline.ending.begins_with("destroy") else ENDING_DUR
	return 0.0

func _next_phase() -> void:
	match phase:
		"intro":
			_start_beat(0)
		"menu":
			var b := current_beat()
			energy_display[b["actor"]] = b["energy_after"][b["actor"]]
			_enter("support" if b["is_support_only"] else "attack")
		"support":
			_apply_persistent(beat_idx)
			# Pure FF support/status turns finish their turn after the support animation (no follow-up shot)
			_enter("settle")
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
	# Live interactive session that has run out of recorded beats: ask the session for the next turn.
	if session != null and i >= timeline.beats.size():
		var next_side := session.get_next_actor_side()  # "" once the session has concluded
		if next_side == timeline.coalition_side:
			# Player's turn: wait in command_select. With Auto-Pilot on, advance() commits the AI's pick
			# from there, so manual and auto-piloted player turns share one path.
			in_tech_submenu = false
			phase_t = 0.0
			_enter("command_select")
			if not auto_pilot:
				SoundManager.play("ui_click")
			return
		if next_side != "":
			_record_step(session.run_ai_turn())  # Syndikat turn
		elif session.is_finished:
			timeline.sync_ending_from_result(result)

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
		energy_display = timeline.end_energy.duplicate()

func _attack_ability(b: Dictionary) -> String:
	return String(b.get("ability_id", "kwk_88"))

func _attack_impact_time() -> float:
	var b := current_beat()
	return WeaponAnims.impact_time(_attack_ability(b))

func _support_duration(b: Dictionary) -> float:
	return SupportAnims.duration(String(b.get("ability_id", "defend")))

func _apply_persistent(i: int) -> void:
	if i < 0 or i >= timeline.beats.size() or _persist_done.has(i):
		return
	_persist_done[i] = true
	var b: Dictionary = timeline.beats[i]
	if b["is_support_only"]:
		SupportAnims.apply_persistent(self, mechs[b["actor"]], b["ability_id"])

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
	if b.get("is_miss", false):
		numbers.append({"value": 0, "label": "MISS", "crit": false, "pos": point(mechs[target], "hull"), "age": 0.0})
		SoundManager.play("ui_cancel", 1.25)
		return
	true_hull[target] = int(true_hull[target]) - int(b["damage"])
	if b["soften_from"] != "":
		SupportAnims.consume_soften(self, mechs[target], b["soften_from"])
	hull_display[target] = b["hull_after"][target]
	numbers.append({
		"value": int(b["damage"]),
		"label": "",
		"crit": bool(b.get("is_crit", false)),
		"pos": point(mechs[target], "hull"),
		"age": 0.0
	})
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
		m["glitch"] = 0.18 if m.get("jammed", false) and int(clock / 0.25) % 3 == 0 else 0.0
		m["ghosts"] = []
		m["glow"] = Color(0, 0, 0, 0)
		m["attach"] = {}
		if m.get("rangefinder_on", false):
			m["attach"]["rangefinder"] = 1.0
		if m.get("mast_on", false):
			m["attach"]["mast"] = 1.0
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
			SupportAnims.run(self, a, d, b["ability_id"], phase_t)
		"attack":
			var ab_id := _attack_ability(b)
			WeaponAnims.run(self, a, d, ab_id, phase_t)
			var imp := WeaponAnims.impact_time(ab_id)
			if b.get("is_miss", false) and phase_t >= imp and phase_t < imp + 0.35:
				var dt := phase_t - imp
				var dodge := sin(dt / 0.35 * PI) * 8.0
				d["pose"] = "brace"
				d["white"] = false
				d["offset"] = m_end_offset(d) + Vector2(roundf(-dodge * int(d["dir"])), 0)
			elif b["soften_from"] != "" and phase_t >= imp:
				SupportAnims.soften(self, a, d, b["soften_from"], phase_t - imp)

func m_end_offset(m: Dictionary) -> Vector2:
	return m.get("end_offset", Vector2.ZERO)

func _animate_ending() -> void:
	var t := phase_t
	match timeline.ending:
		"pushback":
			var m: Dictionary = mechs["def"]
			var k := clampf(t / 0.6, 0.0, 1.0)
			m["offset"] = Vector2(roundf(-8.0 * k * int(m["dir"])), roundf(k))
			if result != null and result.defender_retreated:
				m["pose"] = "brace"
			else:
				m["pose"] = "hit" if t < 0.5 else "stagger"
		"repelled":
			var m: Dictionary = mechs["atk"]
			var k := clampf(t / 0.6, 0.0, 1.0)
			m["offset"] = Vector2(roundf(-8.0 * k * int(m["dir"])), 0)
			if result != null and result.attacker_retreated:
				m["pose"] = "brace"
			else:
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
		BattleFX.damage_number(self, int(n["value"]), n["pos"], float(n["age"]), String(n.get("label", "")), bool(n.get("crit", false)))
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
	var syn_side: String = "def" if timeline.coalition_side == "atk" else "atk"
	var coa_side: String = timeline.coalition_side

	# Left Panel: Syndicate Enemy Status + Enemy HULL Bar
	BattleFX.panel(self, Rect2(2, MENU_Y, 108, 70))
	# Right Panel: Coalition Player Status + HULL & EN Bars + Command Box
	BattleFX.panel(self, Rect2(112, MENU_Y, 246, 70))

	var sd: MechData = syn["data"]
	PixelFont.draw_text(self, short_callsign(sd.callsign), Vector2(8, MENU_Y + 7), C_NAME)
	PixelFont.draw_text(self, CHASSIS_NAMES.get(sd.chassis_id, sd.chassis_id.to_upper()), Vector2(8, MENU_Y + 18), C_LABEL.darkened(0.25))

	var syn_hull := int(hull_display[syn_side])
	PixelFont.draw_text(self, "HULL", Vector2(8, MENU_Y + 30), C_LABEL)
	_gauge(Rect2(38, MENU_Y + 32, 66, 3), clampf(float(syn_hull) / maxf(1.0, float(sd.max_armor)), 0.0, 1.0), C_HULL)
	_right_text("%d/%d" % [syn_hull, sd.max_armor], 104, MENU_Y + 40, C_NUM)

	var tile := result.target_tile
	PixelFont.draw_text(self, "%s %dm" % [tile.get_terrain_short_code(), tile.get_elevation_meters()], Vector2(8, MENU_Y + 56), C_LABEL)
	if session != null:
		var syn_badges := session.get_combatant(syn_side).get_status_badges()
		if not syn_badges.is_empty():
			_right_text(syn_badges[0], 104, MENU_Y + 56, C_CURSOR)

	# Coalition Panel (Right Half)
	var cd: MechData = coa["data"]
	PixelFont.draw_text(self, short_callsign(cd.callsign), Vector2(200, MENU_Y + 7), C_NAME)

	var mode_tag := speed_label
	if auto_pilot:
		mode_tag = ("AUTO " + mode_tag).strip_edges()
	if mode_tag != "":
		_right_text(mode_tag, 350, MENU_Y + 7, C_LABEL.darkened(0.2))

	var coa_hull := int(hull_display[coa_side])
	PixelFont.draw_text(self, "HULL", Vector2(200, MENU_Y + 21), C_LABEL)
	_gauge(Rect2(284, MENU_Y + 23, 66, 3), clampf(float(coa_hull) / maxf(1.0, float(cd.max_armor)), 0.0, 1.0), C_HULL)
	_right_text("%d/%d" % [coa_hull, cd.max_armor], 350, MENU_Y + 30, C_NUM)

	var coa_en := int(energy_display[coa_side])
	PixelFont.draw_text(self, "EN", Vector2(200, MENU_Y + 41), C_LABEL)
	_gauge(Rect2(284, MENU_Y + 43, 66, 4), clampf(float(coa_en) / maxf(1.0, float(cd.max_energy)), 0.0, 1.0), C_EN)
	_right_text("%d/%d" % [coa_en, cd.max_energy], 350, MENU_Y + 50, C_NUM)

	if session != null:
		var coa_badges := session.get_combatant(coa_side).get_status_badges()
		if not coa_badges.is_empty():
			PixelFont.draw_text(self, " ".join(coa_badges.slice(0, 2)), Vector2(200, MENU_Y + 58), C_CURSOR)
		else:
			PixelFont.draw_text(self, "SPD %d  EVA %d%%" % [cd.speed, cd.evasion], Vector2(200, MENU_Y + 58), C_LABEL.darkened(0.2))

	# Command Menu (Interactive or Automated Beat Preview)
	var b := current_beat()
	if phase == "command_select":
		if not in_tech_submenu:
			BattleFX.panel(self, CMD_BOX_RECT)
			for i in COMMANDS.size():
				var disabled: bool = (i == 3 and coa_side == "def" and session != null and not session.can_defender_retreat)
				var col := C_DIM if disabled else C_NAME
				PixelFont.draw_text(self, COMMANDS[i], Vector2(130, _cmd_row_y(i)), col)
			if int(clock / 0.2) % 2 == 0:
				var cy := _cmd_row_y(menu_cursor)
				draw_colored_polygon(PackedVector2Array([Vector2(120, cy), Vector2(126, cy + 3.5), Vector2(120, cy + 7)]), C_CURSOR)
		else:
			BattleFX.panel(self, TECH_BOX_RECT)
			PixelFont.draw_text(self, "TECH SYSTEMS [ESC]", Vector2(122, MENU_Y + 8), C_LABEL)
			_right_text("EN %d/%d" % [coa_en, cd.max_energy], int(TECH_BOX_RECT.end.x - 6), MENU_Y + 8, C_EN)
			var coa_state := session.get_combatant(coa_side)
			for i in cd.abilities.size():
				var ab: CombatAbility = cd.abilities[i]
				var spent := not ab.is_weapon() and coa_state.used_support_ids.has(ab.ability_id)
				var affordable := coa_state.can_use(ab)
				var col := C_NAME if affordable else C_DIM
				var short_ab := ab.ability_name.to_upper()
				if short_ab.length() > 24:
					short_ab = short_ab.substr(0, 24)
				var ry := _tech_row_y(i)
				PixelFont.draw_text(self, short_ab, Vector2(130, ry), col)
				_right_text("USED" if spent else "%dEN" % ab.energy_cost, int(TECH_BOX_RECT.end.x - 6), ry, C_EN if affordable else C_DIM)
			var cy := _tech_row_y(tech_cursor)
			draw_colored_polygon(PackedVector2Array([Vector2(120, cy), Vector2(126, cy + 3.5), Vector2(120, cy + 7)]), C_CURSOR)
	elif phase == "menu" and int(b.get("command_row", -1)) >= 0:
		BattleFX.panel(self, CMD_BOX_RECT)
		for i in COMMANDS.size():
			PixelFont.draw_text(self, COMMANDS[i], Vector2(130, _cmd_row_y(i)), C_NAME)
		var target_row := int(b["command_row"])
		var row := mini(target_row, int(phase_t / 0.10))
		if int(clock / 0.18) % 2 == 0 or row == target_row:
			var cy := _cmd_row_y(row)
			draw_colored_polygon(PackedVector2Array([Vector2(120, cy), Vector2(126, cy + 3.5), Vector2(120, cy + 7)]), C_CURSOR)

## Drawn y of a command / ability row, derived from the same constants menu_row_at hit-tests with.
func _cmd_row_y(i: int) -> int:
	return CMD_ROW0_TOP + ROW_TEXT_DY + i * MENU_ROW_H

func _tech_row_y(i: int) -> int:
	return TECH_ROW0_TOP + ROW_TEXT_DY + i * MENU_ROW_H

func _gauge(r: Rect2, ratio: float, col: Color) -> void:
	draw_rect(r, C_GAUGE_BG)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(ratio, 0.0, 1.0)), r.size.y)), col)

func _right_text(s: String, right_x: int, y: int, col: Color) -> void:
	PixelFont.draw_text(self, s, Vector2(right_x - PixelFont.text_width(s), y), col)

func _draw_banner() -> void:
	var b := current_beat()
	if phase == "command_select":
		var coa_data: MechData = coalition_mech()["data"]
		var top_lines: Array[String] = []
		if in_tech_submenu and tech_cursor >= 0 and tech_cursor < coa_data.abilities.size():
			var ab: CombatAbility = coa_data.abilities[tech_cursor]
			top_lines.append("%s [%s]" % [ab.ability_name.to_upper(), ab.category])
			top_lines.append(ab.description.to_upper())
		else:
			var prompts := [
				"STANDARD CANNON ATTACK (0 EN)",
				"ACTIVATE CHASSIS TECH ABILITY (USES EN)",
				"BRACE HULL PLATING (-50% DMG TAKEN, +2 EN)",
				"ATTEMPT TACTICAL DISENGAGE (SPEED ROLL)"
			]
			top_lines.append("COMMAND // %s" % short_callsign(coa_data.callsign))
			top_lines.append(prompts[clampi(menu_cursor, 0, prompts.size() - 1)])
		var w := 180
		for l in top_lines:
			w = maxi(w, PixelFont.text_width(l) + 16)
		w = mini(w, 352)
		var r := Rect2(roundf((W - w) / 2.0), 4, w, 6 + top_lines.size() * 10)
		BattleFX.panel(self, r)
		for i in top_lines.size():
			PixelFont.draw_centered(self, top_lines[i], W / 2.0, r.position.y + 4 + i * 10, C_NAME if i == 0 else C_LABEL)
	elif phase in ["support", "attack", "settle"] and not b.is_empty():
		var text: String = String(b["ability_name"]).to_upper()
		var lines := [text]
		if phase == "settle" and String(b.get("status_text", "")) != "":
			lines.append(String(b["status_text"]).to_upper())
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
