class_name UIOverlay
extends CanvasLayer

## Tactical UI Overlay (HUD, Telemetry Readouts, Terrain Inspector, Combat Forecast,
## Skirmish Showdown Modal, Field Manual, and Operation Debrief Screen).
## Drawn in the battle screen's CRT menu style (CrtUI) at an integer pixel scale. Commands are
## menu rows: click them, or use their keys (handled by Battlefield); the debrief also takes
## Up/Down + Enter.

signal action_wait_refuel_requested()
signal action_rotate_requested()
signal action_next_mech_requested()
signal action_end_turn_requested()
signal action_center_camera_requested()
signal action_return_menu_requested()
signal action_restart_mission_requested()
signal skirmish_modal_closed(result: SkirmishEngine.SkirmishResult)

const LEFT_W := 152       # fits the widest battle sprite (136px) inside its portrait frame
const RIGHT_W := 164
const LOG_H := 64
const TOP_H := 30
const BLOCKER := "block"   # hotspot id of a plain panel: swallows the click, does nothing

## The H Field Manual. Numbers are read from the game data (GridTileData, MechData, SkirmishEngine,
## BalanceProbe defaults) so it agrees with the Rules of Engagement page after a balance change.
static func manual_lines() -> Array[String]:
	var S := SkirmishEngine
	var lines: Array[String] = [
		"1. TURN FLOW & FUEL MOBILITY:",
		"   - Each Turn follows: PLAYER COMMAND PHASE -> COMBAT ENCOUNTER PHASE -> SYNDICATE AI PHASE.",
		"   - Moving consumes Diesel Fuel based on Terrain + Uphill Elevation Climb (+2 Fuel per 100m climbed).",
		"   - On its turn, a walker can face & entrench, move and then face or attack, or face and attack in place. Attacking an adjacent enemy costs its tile's step fuel (terrain + chassis surcharge + climb) and never moves onto its tile.",
		"   - [WAIT / REFUEL] entrenches (%+d%% DEF, %+d%% EVA, %+d%% Hit, +%d SPD) & restores +%d Fuel / +%d EN (+%d Hull in a City). Cities repair +%d Hull, +%d Fuel, +%d EN each turn." % [
			BalanceProbe.def_pct[0], S.ENTRENCHED_EVA_BONUS, S.ENTRENCHED_ACC_BONUS, S.ENTRENCHED_SPD_BONUS,
			MechData.WAIT_FUEL, MechData.WAIT_ENERGY, BalanceProbe.patch[0], BalanceProbe.upkeep[0], MechData.CITY_FUEL, MechData.CITY_ENERGY],
		"   - Objective captures must be held through the enemy phase: objective victories are checked at turn end.",
		"",
		"2. TERRAIN CHART (FUEL COST / ATTACK / DEFENSE / EVASION MOD):",
	]
	var fuel_mult: int = GlobalState.chassis_catalog["vanguard"].fuel_usage if GlobalState.chassis_catalog.has("vanguard") else 2
	for t in RulesContent.TERRAIN_ORDER:
		var td := GridTileData.new(Vector2i.ZERO, t, 1)
		lines.append("   - %s (%s): %d Fuel / %+d%% ATK / %+d%% DEF / %+d%% EVA" % [
			td.get_terrain_name().to_upper(), td.get_terrain_short_code(), td.get_base_fuel_cost() * fuel_mult, td.get_attack_modifier_pct(), td.get_defense_modifier_pct(), td.get_evasion_modifier_pct()])
	lines.append_array([
		"",
		"3. ELEVATION & HIGH GROUND ADVANTAGE:",
		"   - Attacking from higher elevation down onto an enemy grants +%d%% Firepower, +%d%% Armor, +%d%% Hit, +%d%% EVA and +%d%% Crit per level!" % [
			S.ELEV_HIGH_FP_PCT, S.ELEV_HIGH_ARMOR_PCT, S.ELEV_ACC_PER_LEVEL, S.ELEV_EVA_PER_LEVEL, S.ELEV_CRIT_PER_LEVEL],
		"   - Attacking uphill suffers -%d%% Firepower and -%d%% Hit Accuracy per elevation level (the defender above gains +%d%% Firepower & Armor)." % [
			S.ELEV_CLIMB_FP_PCT, S.ELEV_ACC_PER_LEVEL, S.ELEV_CLIMB_ENEMY_FP_PCT],
		"",
		"4. TURN-BASED RPG COMBAT (ATTACK / TECH / DEFEND / RETREAT):",
		"   - Attacking an adjacent enemy triggers a classic Final Fantasy turn-based battle; both walkers remain on their own tiles.",
		"   - Turn order each round is determined by Speed (SPD). Round 1 gives the Attacker +%d SPD; an Entrenched Defender answers with +%d." % [
			S.ROUND1_ATTACKER_SPD_BONUS, S.ROUND1_ENTRENCHED_SPD_BONUS + S.ENTRENCHED_SPD_BONUS],
		"   - Choose ATTACK (0 EN), TECH (uses Reactor Energy EN for heavy weapons & support buffs), DEFEND (-%d%% DMG on the enemy's next hit, +%d EN), or RETREAT." % [
			100 - int(round(S.GUARD_DAMAGE_MULT * 100.0)), S.DEFEND_EN_GAIN],
		"   - ARMOR/TACTIC TECHs deploy once per battle. A DEFEND guard, like a shield, holds through misses and support turns and is spent by the first shot that lands; it cannot be stacked.",
		"   - Full rules: RULES OF ENGAGEMENT on the Command HQ screen (press R there).",
	])
	return lines


var root_ctrl: CrtScreen
var skirmish_modal: BattleScreen

# HUD state set by Battlefield. Every assignment queues a redraw: the HUD is drawn on change (plus
# the animated portrait and banner), not every frame.
var selected_mech: MechData = null:
	set(v): selected_mech = v; _dirty = true
var hovered_mech: MechData = null:
	set(v): hovered_mech = v; _dirty = true
var hovered_tile: GridTileData = null:
	set(v): hovered_tile = v; _dirty = true
var hovered_reach_info: Dictionary = {}:
	set(v): hovered_reach_info = v; _dirty = true
var current_forecast: Dictionary = {}:
	set(v): current_forecast = v; _dirty = true
var strike_plan: StrikePlan = null:       # why the hovered enemy can't be struck (Battlefield.strike_plan_for)
	set(v): strike_plan = v; _dirty = true
var step_cost_mech: MechData = null:      # ready selected walker whose real step cost the sector panel shows
	set(v): step_cost_mech = v; _dirty = true

var map_def: MapDefinition = null:
	set(v): map_def = v; _dirty = true
var player_unit_count: int = 0:
	set(v): player_unit_count = v; _dirty = true
var ai_unit_count: int = 0:
	set(v): ai_unit_count = v; _dirty = true
var player_obj_count: int = 0:
	set(v): player_obj_count = v; _dirty = true
var total_obj_count: int = 0:
	set(v): total_obj_count = v; _dirty = true

## Set by Battlefield while a walker is mid-move: orders are refused, so the commands render disabled.
var commands_locked: bool = false:
	set(v): commands_locked = v; _dirty = true
var show_manual_modal: bool = false:
	set(v): show_manual_modal = v; _dirty = true; _manual_cache = []   # re-read balance values on open
var show_game_over_modal: bool = false:
	set(v): show_game_over_modal = v; _dirty = true
var _banner_timer: float = 0.0
var _banner_text: String = ""
var _anim_time: float = 0.0
# The CRT screen state lives on root_ctrl (a CrtScreen); these forward to it so the HUD code reads as before.
var _scale: int:
	get: return root_ctrl._scale if root_ctrl != null else 2
	set(v): root_ctrl._scale = v
var _hot: CrtHotspots:
	get: return root_ctrl._hot
var _dirty: bool:
	get: return root_ctrl == null or root_ctrl._dirty
	set(v):
		if root_ctrl != null:
			root_ctrl._dirty = v
var _debrief_row: int = 0
# Redraw scheduling: _dirty is set by HUD state changes, input and GlobalState signals; the idle
# portrait redraws when its frame steps; the heartbeat picks up in-place MechData changes (fuel,
# armor) that no setter sees.
const REDRAW_HEARTBEAT := 0.25
var _since_redraw: float = 0.0
var _portraits: PackedStringArray = []   # chassis of the idle portraits in the last frame
var _portrait_frame: int = -1
var _manual_cache: Array = []            # [inner width, laid-out lines] for the H manual

func _ready() -> void:
	layer = 10
	root_ctrl = CrtScreen.new()
	root_ctrl.passive_id = BLOCKER
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(root_ctrl)
	root_ctrl.draw.connect(_on_root_draw)

	skirmish_modal = BattleScreen.new()
	skirmish_modal.resolution_confirmed.connect(func(res): skirmish_modal_closed.emit(res))
	skirmish_modal.visibility_changed.connect(_mark_dirty)
	add_child(skirmish_modal)
	GlobalState.phase_changed.connect(func(_p, _t): _mark_dirty())
	GlobalState.log_added.connect(func(_e): _mark_dirty())

func _mark_dirty() -> void:
	if root_ctrl != null:
		root_ctrl.mark_dirty()

func _process(delta: float) -> void:
	if skirmish_modal != null and skirmish_modal.visible:
		# The banner keeps counting down under the modal (it would otherwise reappear frozen afterwards)
		if _banner_timer > 0.0:
			_banner_timer = maxf(0.0, _banner_timer - delta)
			if _banner_timer == 0.0:
				_dirty = true
		return
	_anim_time += delta
	_since_redraw += delta
	var banner_live: bool = _banner_timer > 0.0   # true for the frame it expires too, to erase it
	if banner_live:
		_banner_timer = maxf(0.0, _banner_timer - delta)
	var frame: int = 0
	for chassis in _portraits:
		frame += MechSpriteBank.idle_frame(chassis, _anim_time * 1000.0)
	if _dirty or banner_live or frame != _portrait_frame or _since_redraw >= REDRAW_HEARTBEAT:
		_dirty = false
		_since_redraw = 0.0
		_portrait_frame = frame
		root_ctrl.queue_redraw()

func trigger_phase_banner(text: String) -> void:
	_banner_text = text
	_banner_timer = 1.65
	root_ctrl.queue_redraw()

func show_skirmish_session(session: SkirmishEngine.BattleSession) -> void:
	skirmish_modal.start_session(session)

func trigger_game_over() -> void:
	show_game_over_modal = true
	_debrief_row = 0
	root_ctrl.queue_redraw()

func _is_player_command_time() -> bool:
	return GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not skirmish_modal.visible and not show_game_over_modal and not commands_locked

func _can_turn() -> bool:
	return _is_player_command_time() and selected_mech != null and selected_mech.faction == MechData.Faction.PLAYER

func _can_wait() -> bool:
	return _is_player_command_time() and selected_mech != null and selected_mech.faction == MechData.Faction.PLAYER and not selected_mech.has_moved

func _can_hold() -> bool:
	return _is_player_command_time() and selected_mech != null and selected_mech.faction == MechData.Faction.PLAYER and selected_mech.has_moved and not selected_mech.has_attacked

func _can_next_mech() -> bool:
	return _is_player_command_time() and selected_mech != null and selected_mech.faction == MechData.Faction.PLAYER and selected_mech.has_moved

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if skirmish_modal.visible:
		return
	if event is InputEventKey or event is InputEventMouseButton:
		_dirty = true
	if event is InputEventMouseMotion:
		var id := root_ctrl.track_pointer(event)
		if id.begins_with("debrief:"):
			_debrief_row = int(id.substr(8))
	elif event is InputEventMouseButton:
		var id := root_ctrl.hit_id(event)
		_hot.hovered = id   # keep pointer_over_hud() right for clicks that arrive without a motion event
		if id != "" and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mark it handled first: MENU / debrief rows change scene and take this overlay out of the tree.
			get_viewport().set_input_as_handled()
			_activate(id)
		elif id == BLOCKER and event.pressed:
			get_viewport().set_input_as_handled()   # wheel / right-click over a panel does not zoom or drag the map
	elif show_game_over_modal and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()   # before _activate: "return to menu" leaves the tree
		match event.keycode:
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
				_debrief_row = 1 - _debrief_row
				SoundManager.play("ui_click")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate("debrief:%d" % _debrief_row)

## True while the pointer is over any HUD panel or command: the map must not see it.
func pointer_over_hud() -> bool:
	return _hot.hovered != ""

func _activate(id: String) -> void:
	if id == BLOCKER:
		return
	# A modal owns the screen: only its own controls respond
	if show_manual_modal and id != "manual":
		return
	if show_game_over_modal and not id.begins_with("debrief:"):
		return
	match id:
		"manual":
			SoundManager.play("ui_click")
			show_manual_modal = not show_manual_modal
		"cam":
			SoundManager.play("ui_click")
			action_center_camera_requested.emit()
		"menu":
			SoundManager.play("ui_cancel")
			action_return_menu_requested.emit()
		"turn":
			action_rotate_requested.emit()
		"next_mech":
			action_next_mech_requested.emit()
		"wait":
			SoundManager.play("ui_confirm")
			action_wait_refuel_requested.emit()
		"end_turn":
			SoundManager.play("phase_shift")
			action_end_turn_requested.emit()
		"debrief:0":
			SoundManager.play("ui_confirm")
			show_game_over_modal = false
			action_restart_mission_requested.emit()
		"debrief:1":
			SoundManager.play("ui_click")
			action_return_menu_requested.emit()
	root_ctrl.queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _t(s: String, pos: Vector2, col: Color) -> void:
	CrtUI.text(root_ctrl, s, pos, col)

func _tr(s: String, right_x: float, y: float, col: Color) -> void:
	CrtUI.text_right(root_ctrl, s, right_x, y, col)

## A clickable menu row: cursor on hover (or when forced), hover colour, hotspot.
func _row(id: String, label: String, pos: Vector2, width: float, key_hint: String = "", force_cursor: bool = false) -> void:
	var hot := _hot.hovered == id
	if hot or force_cursor:
		CrtUI.cursor(root_ctrl, pos)
	_t(label, pos + Vector2(10, 0), CrtUI.C_CURSOR if hot else CrtUI.C_NAME)
	if key_hint != "":
		_tr(key_hint, pos.x + width, pos.y, CrtUI.C_LABEL_DIM)
	_hot.add(id, Rect2(pos.x - 2, pos.y - 3, width + 4, CrtUI.ROW + 2))

## A HUD panel that also swallows clicks and hover, so they never reach the map underneath.
func _panel(r: Rect2, border: Color = CrtUI.C_BORDER, alpha: float = 1.0) -> void:
	CrtUI.panel(root_ctrl, r, border, alpha)
	_hot.add(BLOCKER, r)

func _phase_color() -> Color:
	match GlobalState.current_phase:
		GlobalState.TurnPhase.PLAYER_PHASE:
			return CrtUI.C_LABEL
		GlobalState.TurnPhase.RESOLUTION_PHASE:
			return CrtUI.C_NAME
	return CrtUI.C_HOSTILE

# ---------------------------------------------------------------- drawing
func _on_root_draw() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_scale = CrtUI.pixel_scale(vp)
	var v := CrtUI.virtual_size(vp, _scale)
	CrtUI.begin(root_ctrl, _scale)
	_hot.clear()
	_portraits.clear()

	_draw_top_bar(v)

	var display_mech: MechData = selected_mech if selected_mech != null else hovered_mech
	if display_mech != null:
		_draw_unit_panel(Rect2(6, TOP_H + 4, LEFT_W, 0), display_mech)
	else:
		var r := Rect2(6, TOP_H + 4, LEFT_W, 58)
		_panel(r)
		_t("NO WALKER SELECTED", r.position + Vector2(6, 6), CrtUI.C_NAME)
		CrtUI.paragraph(root_ctrl, "Click a friendly walker to plot fuel range and engage.", r.position + Vector2(6, 20), r.size.x - 12, CrtUI.C_NUM)

	if hovered_tile != null:
		_draw_terrain_panel(Rect2(v.x - 6 - RIGHT_W, TOP_H + 4, RIGHT_W, 0))

	var log_r := Rect2(6, v.y - 6 - LOG_H, v.x - 12, LOG_H)
	_draw_commands(Rect2(v.x - 6 - RIGHT_W, log_r.position.y - 4, RIGHT_W, 0))
	_draw_log(log_r)

	if _banner_timer > 0.0:
		var a := clampf(_banner_timer * 1.5, 0.0, 1.0)
		var w := maxf(260.0, PixelFont.text_width(_banner_text) + 24.0)
		var br := Rect2(roundf((v.x - w) / 2.0), TOP_H + 4, w, 20)
		CrtUI.panel(root_ctrl, br, CrtUI.C_NAME, a)
		CrtUI.text_centered(root_ctrl, _banner_text, v.x / 2.0, br.position.y + 6, Color(CrtUI.C_NAME, a))

	# A modal owns the screen: drop the HUD's hotspots, swallow everything, keep only its own controls
	if show_manual_modal:
		var manual_rect: Rect2 = _hot.rect_of("manual")
		_hot.clear()
		_hot.add(BLOCKER, Rect2(Vector2.ZERO, v))
		_hot.add("manual", manual_rect)   # the MANUAL [H] button still closes it
		_draw_manual_modal(v)
	if show_game_over_modal:
		_hot.clear()
		_hot.add(BLOCKER, Rect2(Vector2.ZERO, v))
		_draw_game_over_modal(v)

func _draw_top_bar(v: Vector2) -> void:
	_panel(Rect2(0, 0, v.x, TOP_H))
	var map_title: String = map_def.map_name if map_def != null else "OPERATION: IRON GRID"
	var strat_badge: String = map_def.get_strategy_name() if map_def != null else "TACTICAL"
	var max_turns: int = map_def.turn_limit if map_def != null else 10
	var title := "%s  [%s]" % [map_title, strat_badge]
	var stats := "TURN %02d/%02d  COALITION %d  SYNDIKAT %d  OBJ %d/%d" % [
		GlobalState.turn_number, max_turns, player_unit_count, ai_unit_count, player_obj_count, total_obj_count
	]
	_t(title, Vector2(8, 6), CrtUI.C_NAME)
	_t(stats, Vector2(8, 17), CrtUI.C_NUM)

	# Phase box: centred, but never over the title/stats text.
	var phase := GlobalState.get_phase_name()
	var pw := maxf(150.0, PixelFont.text_width(phase) + 20.0)
	var left_end := 8.0 + PixelFont.text_width(title if title.length() > stats.length() else stats) + 12.0
	var pill := Rect2(roundf(maxf(v.x / 2.0 - pw / 2.0, left_end)), 5, pw, 20)
	var pc := _phase_color()
	_panel(pill, pc)
	CrtUI.text_centered(root_ctrl, phase, pill.position.x + pw / 2.0, pill.position.y + 7, pc)

	# Utility commands, right-aligned
	var items := [["menu", "MENU"], ["cam", "CAM [C]"], ["manual", "MANUAL [H]"]]
	var x := v.x - 8
	for it in items:
		var w := PixelFont.text_width(it[1]) + 10
		x -= w
		_row(it[0], it[1], Vector2(x, 11), w)
		x -= 14

func _draw_unit_panel(rect: Rect2, m: MechData) -> void:
	var is_player: bool = m.faction == MechData.Faction.PLAYER
	var accent := CrtUI.C_LABEL if is_player else CrtUI.C_HOSTILE
	var cell := MechSpriteBank.cell_size(m.chassis_id)
	var tech_h := 12 + m.abilities.size() * 20
	var gear := _gear_note(m)
	var gear_lines := CrtUI.wrap_lines("MOBILITY: " + gear, rect.size.x - 12).size()
	rect.size.y = 6 + 40 + cell.y + 8 + 4 + 12 + 57 + gear_lines * CrtUI.LINE + 4 + tech_h + 2
	_panel(rect, accent)

	var x := rect.position.x + 6
	var w := rect.size.x - 12
	var y := rect.position.y + 6
	_t("8TH IRON DIVISION" if is_player else "KRIEGS-SYNDIKAT", Vector2(x, y), accent)
	y += 10
	_t(CrtUI.fit(m.callsign, w), Vector2(x, y), CrtUI.C_NAME)
	y += 10
	_t(CrtUI.fit(m.unit_name, w), Vector2(x, y), CrtUI.C_LABEL_DIM)
	y += 10
	_t(CrtUI.fit(m.chassis_class, w), Vector2(x, y), CrtUI.C_LABEL_DIM)
	y += 10

	# Portrait: the battle sprite at 1:1, in its own frame, facing the way it fights.
	var port := Rect2(x, y, w, cell.y + 8)
	CrtUI.frame(root_ctrl, port)
	CrtUI.mech(root_ctrl, m.chassis_id, int(m.faction), Rect2(x, y + 4, w, cell.y), not is_player, _anim_time * 1000.0, _scale)
	_portraits.append(m.chassis_id)
	y += port.size.y + 4
	var status_txt := "ENTRENCHED +15% DEF" if m.is_entrenched else ("READY TO STRIKE" if (m.has_moved and not m.has_attacked) else ("ORDER COMPLETE" if m.is_order_complete() else "SYSTEMS READY"))
	_t(status_txt, Vector2(x, y), CrtUI.C_LABEL if not m.is_order_complete() else CrtUI.C_LABEL_DIM)
	_tr(m.get_facing_arrow(), x + w, y, CrtUI.C_CURSOR)
	y += 12

	_t("HULL", Vector2(x, y), CrtUI.C_LABEL)
	_tr("%d/%d DEF%d" % [m.current_armor, m.max_armor, m.armor_rating], x + w, y, CrtUI.C_NUM)
	CrtUI.gauge(root_ctrl, Rect2(x, y + 10, w, 3), m.get_armor_ratio(), CrtUI.C_HULL)
	y += 15
	_t("EN", Vector2(x, y), CrtUI.C_LABEL)
	_tr("%d/%d +%d" % [m.current_energy, m.max_energy, m.passive_energy_regen], x + w, y, CrtUI.C_NUM)
	CrtUI.gauge(root_ctrl, Rect2(x, y + 10, w, 3), m.get_energy_ratio(), CrtUI.C_EN)
	y += 15
	_t("FUEL", Vector2(x, y), CrtUI.C_LABEL)
	_tr("%d/%d +%d" % [m.current_fuel, m.max_fuel, m.passive_refuel], x + w, y, CrtUI.C_NUM)
	CrtUI.gauge(root_ctrl, Rect2(x, y + 10, w, 3), m.get_fuel_ratio(), CrtUI.C_FUEL)
	y += 15
	_t("ATK %d  SPD %d" % [m.firepower, m.speed], Vector2(x, y), CrtUI.C_LABEL)
	_tr("EVA %d%%" % m.evasion, x + w, y, CrtUI.C_NUM)
	y += 12
	y = CrtUI.paragraph(root_ctrl, "MOBILITY: " + gear, Vector2(x, y), w, CrtUI.C_LABEL_DIM) + 4

	_t("TECH SYSTEMS", Vector2(x, y), CrtUI.C_LABEL)
	_tr("COST/CAT", x + w, y, CrtUI.C_LABEL_DIM)
	y += 12
	for ab: CombatAbility in m.abilities:
		_t(CrtUI.fit(ab.ability_name, w), Vector2(x, y), CrtUI.C_NAME)
		_t("%d EN" % ab.energy_cost, Vector2(x, y + 9), CrtUI.C_EN)
		var cat_spec := "X%.2f" % ab.power_multiplier if ab.category == "WEAPON" else ab.category
		_tr(cat_spec, x + w, y + 9, CrtUI.C_NUM)
		y += 20

func _gear_note(m: MechData) -> String:
	if m.amphibious_gear:
		return "AMPHIBIOUS SEALS (-2 RIVER FUEL)"
	if m.mountain_gear:
		return "QUAD CLIMBING GEAR (-2 MOUNTAIN/CLIMB FUEL)"
	if m.fuel_efficiency_mod > 0:
		return "HEAVY CHASSIS (+1 FUEL OFF-ROAD)"
	return "STANDARD TREAD/LEG GEAR"

## Sector panel rows: [label, value, colour].
func _terrain_rows() -> Array:
	var rows: Array = []
	var atk_m: int = hovered_tile.get_attack_modifier_pct()
	var def_m: int = hovered_tile.get_defense_modifier_pct()
	rows.append(["ELEVATION", "%dM L%d" % [hovered_tile.get_elevation_meters(), hovered_tile.elevation], CrtUI.C_NUM])
	if step_cost_mech != null:
		# Entering from the same level: the chassis surcharge/gear applies, climb depends on the approach.
		var own: int = step_cost_mech.get_step_fuel_cost(hovered_tile, hovered_tile)
		rows.append(["YOUR STEP COST", "%dF +CLIMB" % own, CrtUI.C_NUM])
	else:
		rows.append(["FUEL COST", "%d/TILE" % hovered_tile.get_base_fuel_cost(), CrtUI.C_NUM])
	rows.append(["ATTACK MOD", "%+d%%" % atk_m, CrtUI.C_LABEL if atk_m >= 0 else CrtUI.C_HOSTILE])
	rows.append(["DEFENSE MOD", "%+d%%" % def_m, CrtUI.C_LABEL if def_m >= 0 else CrtUI.C_HOSTILE])
	if not hovered_reach_info.is_empty():
		rows.append(["PATH FUEL", "-%d (%d LEFT)" % [hovered_reach_info["fuel_spent"], hovered_reach_info["fuel_left"]], CrtUI.C_CURSOR])
	return rows

func _objective_text() -> String:
	if not hovered_tile.is_objective:
		return ""
	var owner_txt := "8TH IRON DIV" if hovered_tile.controlled_by == 0 else ("SYNDIKAT" if hovered_tile.controlled_by == 1 else "CONTESTED")
	return "OBJECTIVE: %s (%s)" % [hovered_tile.objective_label, owner_txt]

## Everything the sector panel draws, wrapped for inner width `w`, plus its total height. Computed
## once per draw and shared by the drawing code and _terrain_panel_height so they cannot disagree.
func _terrain_layout(w: float) -> Dictionary:
	var rows := _terrain_rows()
	var obj_text := _objective_text()
	var obj_lines := CrtUI.wrap_lines(obj_text, w) if obj_text != "" else PackedStringArray()
	var has_forecast := not current_forecast.is_empty()
	var summary_lines := CrtUI.wrap_lines(str(current_forecast.get("approach_summary", "")), w - 12) if has_forecast else PackedStringArray()
	var forecast_h: float = 6 + 12 + summary_lines.size() * CrtUI.LINE + 4 + 4 * 11 + 4 + 12 if has_forecast else 0
	var plan_lines := PackedStringArray()
	var plan_h := 0.0
	if strike_plan != null and strike_plan.severity != StrikePlan.REACHABLE:
		plan_lines = strike_plan.panel_lines(w - 12)
		plan_h = (6 + 12 + plan_lines.size() * CrtUI.LINE + 4) if strike_plan.severity == StrikePlan.IN_STRIKING_DISTANCE else (plan_lines.size() * CrtUI.LINE + 2)
	var height: float = 6 + 22 + rows.size() * 11 + (obj_lines.size() * CrtUI.LINE + 4 if not obj_lines.is_empty() else 0) \
		+ (forecast_h + 6 if has_forecast else 0) + (plan_h + 6 if plan_h > 0 else 0) + 2
	return {
		"rows": rows, "obj_lines": obj_lines, "summary_lines": summary_lines, "forecast_h": forecast_h,
		"plan_lines": plan_lines, "plan_h": plan_h, "height": height,
	}

## Height of the sector panel for the current hover state at inner width `w`.
func _terrain_panel_height(w: float = RIGHT_W - 12) -> float:
	return _terrain_layout(w)["height"]

func _draw_terrain_panel(rect: Rect2) -> void:
	var x := rect.position.x + 6
	var w := rect.size.x - 12
	var right := x + w
	var lay := _terrain_layout(w)
	var rows: Array = lay["rows"]
	var obj_lines: PackedStringArray = lay["obj_lines"]
	var has_forecast := not current_forecast.is_empty()
	var summary_lines: PackedStringArray = lay["summary_lines"]
	var forecast_h: float = lay["forecast_h"]
	rect.size.y = lay["height"]
	_panel(rect)

	var y := rect.position.y + 6
	_t("SECTOR %d,%d" % [hovered_tile.coords.x, hovered_tile.coords.y], Vector2(x, y), CrtUI.C_LABEL)
	y += 10
	_t(CrtUI.fit(hovered_tile.get_terrain_name(), w), Vector2(x, y), CrtUI.C_NAME)
	y += 12
	for r in rows:
		_t(r[0], Vector2(x, y), CrtUI.C_LABEL)
		_tr(r[1], right, y, r[2])
		y += 11
	if not obj_lines.is_empty():
		y += 2
		for l in obj_lines:
			_t(l, Vector2(x, y), CrtUI.C_NAME)
			y += CrtUI.LINE
		y += 2

	if has_forecast:
		y += 4
		var f := Rect2(x - 2, y, w + 4, forecast_h)
		_panel(f, CrtUI.C_HOSTILE)
		var fx := x + 4
		var fr := right - 4
		var fy := y + 6
		_t("ENGAGEMENT FORECAST", Vector2(fx, fy), CrtUI.C_NAME)
		fy += 12
		for l in summary_lines:
			_t(l, Vector2(fx, fy), CrtUI.C_NUM)
			fy += CrtUI.LINE
		fy += 4
		_t("YOUR MOD", Vector2(fx, fy), CrtUI.C_LABEL)
		_tr("%+d%% FP%d" % [int(current_forecast["atk_mod_pct"]), int(current_forecast["atk_eff_fp"])], fr, fy, CrtUI.C_NUM)
		fy += 11
		_t("ENEMY MOD", Vector2(fx, fy), CrtUI.C_HOSTILE)
		_tr("%+d%% FP%d" % [int(current_forecast["def_mod_pct"]), int(current_forecast["def_eff_fp"])], fr, fy, CrtUI.C_NUM)
		fy += 11
		_t("INITIATIVE", Vector2(fx, fy), CrtUI.C_LABEL)
		_tr(CrtUI.fit(str(current_forecast.get("first_striker", "ATK")), 78), fr, fy, CrtUI.C_CURSOR)
		fy += 11
		_t("EST DMG/RETURN", Vector2(fx, fy), CrtUI.C_LABEL)
		_tr("%d/%d" % [int(current_forecast["est_dmg_to_def"]), int(current_forecast["est_dmg_to_atk"])], fr, fy, CrtUI.C_NUM)
		fy += 15
		_t("CLICK ENEMY TO ENGAGE", Vector2(fx, fy), CrtUI.C_HOSTILE)

	var plan_h: float = lay["plan_h"]
	if plan_h > 0:
		y += 4
		if strike_plan.severity == StrikePlan.IN_STRIKING_DISTANCE:
			_panel(Rect2(x - 2, y, w + 4, plan_h), CrtUI.C_CURSOR)
			var py := y + 6
			_t("OUT OF REACH", Vector2(x + 4, py), CrtUI.C_CURSOR)
			py += 12
			for l in lay["plan_lines"]:
				_t(l, Vector2(x + 4, py), CrtUI.C_NUM)
				py += CrtUI.LINE
		else:
			for l in lay["plan_lines"]:
				_t(l, Vector2(x + 4, y), CrtUI.C_LABEL_DIM)
				y += CrtUI.LINE

## Bottom-right command menu; bottom edge sits at rect.position.y.
func _draw_commands(rect: Rect2) -> void:
	var rows: Array = []
	if _can_turn():
		rows.append(["turn", "TURN / FACE", "T"])
	if _can_wait():
		rows.append(["wait", "WAIT / REFUEL +5F", "R"])
	elif _can_hold():
		rows.append(["wait", "HOLD POSITION", "R"])
	if _can_next_mech():
		rows.append(["next_mech", "NEXT MECH", "SPACE"])
	if _is_player_command_time():
		rows.append(["end_turn", "END TURN", "E"])
	if rows.is_empty():
		return
	var h := 8 + rows.size() * CrtUI.ROW
	var r := Rect2(rect.position.x, rect.position.y - h, rect.size.x, h)
	_panel(r)
	for i in rows.size():
		_row(rows[i][0], rows[i][1], r.position + Vector2(6, 5 + i * CrtUI.ROW), r.size.x - 12, rows[i][2])

func _draw_log(r: Rect2) -> void:
	_panel(r)
	var x := r.position.x + 6
	var w := r.size.x - 12
	_t("COMMS LOG", Vector2(x, r.position.y + 6), CrtUI.C_LABEL)
	_tr("PAN WASD/ARROWS/RMB  ZOOM WHEEL  WAIT R  END TURN E", x + w, r.position.y + 6, CrtUI.C_LABEL_DIM)
	var log_count: int = GlobalState.combat_log.size()
	var start_idx: int = maxi(0, log_count - 4)
	for i in range(start_idx, log_count):
		_t(CrtUI.fit(GlobalState.combat_log[i], w), Vector2(x, r.position.y + 18 + (i - start_idx) * CrtUI.LINE), CrtUI.C_NUM)

func _draw_manual_modal(v: Vector2) -> void:
	root_ctrl.draw_rect(Rect2(Vector2.ZERO, v), Color(0.0, 0.0, 0.0, 0.72))
	var w := minf(v.x - 24, 680.0)
	var inner := w - 20
	if _manual_cache.is_empty() or _manual_cache[0] != inner:
		_manual_cache = [inner, _layout_manual(inner)]
	var lines: Array = _manual_cache[1]
	var h := 30 + lines.size() * CrtUI.LINE + 8
	var r := Rect2(roundf((v.x - w) / 2.0), roundf((v.y - h) / 2.0), w, h)
	_panel(r)
	_t("FIELD MANUAL", r.position + Vector2(10, 8), CrtUI.C_LABEL)
	_tr("[H] CLOSE", r.end.x - 10, r.position.y + 8, CrtUI.C_LABEL_DIM)
	var y := r.position.y + 26
	for l in lines:
		if l[0] != "":
			_t(l[0], Vector2(r.position.x + 10 + l[1], y), l[2])
		y += CrtUI.LINE

## Wraps the manual into [text, x offset, colour] rows for an `inner`-wide panel.
func _layout_manual(inner: float) -> Array:
	var lines: Array = []
	for l: String in manual_lines():
		if l == "":
			lines.append(["", 0, CrtUI.C_NUM])
		elif l.begins_with("   - "):
			var wrapped := CrtUI.wrap_lines(l.substr(5), inner - 12)
			for k in wrapped.size():
				lines.append([("- " if k == 0 else "  ") + wrapped[k], 0, CrtUI.C_NUM])
		else:
			lines.append([l, 0, CrtUI.C_NAME])
	return lines

func _draw_game_over_modal(v: Vector2) -> void:
	root_ctrl.draw_rect(Rect2(Vector2.ZERO, v), Color(0.0, 0.0, 0.0, 0.8))
	var won: bool = GlobalState.last_battle_winner == 0
	var col := CrtUI.C_LABEL if won else CrtUI.C_HOSTILE
	var w := 340.0
	var reason := CrtUI.wrap_lines(GlobalState.last_battle_reason, w - 24)
	var h := 16 + 12 + 8 + reason.size() * CrtUI.LINE + 8 + 12 + 10 + 2 * CrtUI.ROW + 10
	var r := Rect2(roundf((v.x - w) / 2.0), roundf((v.y - h) / 2.0), w, h)
	_panel(r, col)
	var cx := r.position.x + w / 2.0
	var y := r.position.y + 12
	CrtUI.text_centered(root_ctrl, "OPERATION VICTORY // SECTOR SECURED" if won else "OPERATION FAILED // COALITION ROUTED", cx, y, col)
	y += 20
	for l in reason:
		CrtUI.text_centered(root_ctrl, l, cx, y, CrtUI.C_NUM)
		y += CrtUI.LINE
	y += 8
	CrtUI.text_centered(root_ctrl, "TURNS ELAPSED: %d" % GlobalState.turn_number, cx, y, CrtUI.C_LABEL_DIM)
	y += 20
	var labels := ["REDEPLOY OPERATION", "RETURN TO COMMAND HQ"]
	var row_w := PixelFont.text_width(labels[1]) + 12
	for i in labels.size():
		_row("debrief:%d" % i, labels[i], Vector2(roundf(cx - row_w / 2.0), y + i * CrtUI.ROW), row_w, "", _debrief_row == i)
