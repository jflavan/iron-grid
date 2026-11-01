class_name UIOverlay
extends CanvasLayer

## Tactical UI Overlay (HUD, Telemetry Readouts, Terrain Inspector, Combat Forecast,
## Skirmish Showdown Modal, Field Manual, and Operation Debrief Screen).

signal action_wait_refuel_requested()
signal action_end_turn_requested()
signal action_center_camera_requested()
signal action_return_menu_requested()
signal action_restart_mission_requested()
signal skirmish_modal_closed(result: SkirmishEngine.SkirmishResult)

var root_ctrl: Control
var skirmish_modal: SkirmishModal

var selected_mech: MechData = null
var hovered_mech: MechData = null
var hovered_tile: GridTileData = null
var hovered_reach_info: Dictionary = {}
var current_forecast: Dictionary = {}

var map_def: MapDefinition = null
var player_unit_count: int = 0
var ai_unit_count: int = 0
var player_obj_count: int = 0
var total_obj_count: int = 0

var show_manual_modal: bool = false
var show_game_over_modal: bool = false
var _banner_timer: float = 0.0
var _banner_text: String = ""
var _anim_time: float = 0.0

var _btn_wait: Button
var _btn_end_turn: Button
var _btn_manual: Button
var _btn_center: Button
var _btn_menu: Button
var _btn_retry: Button
var _btn_debrief_menu: Button

func _ready() -> void:
	layer = 10
	root_ctrl = Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)
	root_ctrl.draw.connect(_on_root_draw)

	_create_hud_buttons()

	skirmish_modal = SkirmishModal.new()
	skirmish_modal.resolution_confirmed.connect(func(res): skirmish_modal_closed.emit(res))
	add_child(skirmish_modal)

func _create_hud_buttons() -> void:
	_btn_wait = _make_button("WAIT / REFUEL (+5F) [R]", Vector2(210, 36), func():
		SoundManager.play("ui_confirm")
		action_wait_refuel_requested.emit()
	)
	_btn_end_turn = _make_button("END PLAYER TURN [E]", Vector2(190, 36), func():
		SoundManager.play("phase_shift")
		action_end_turn_requested.emit()
	)
	_btn_manual = _make_button("FIELD MANUAL [H]", Vector2(150, 34), func():
		SoundManager.play("ui_click")
		show_manual_modal = not show_manual_modal
		root_ctrl.queue_redraw()
	)
	_btn_center = _make_button("RESET CAM [C]", Vector2(130, 34), func():
		SoundManager.play("ui_click")
		action_center_camera_requested.emit()
	)
	_btn_menu = _make_button("MAIN MENU", Vector2(120, 34), func():
		SoundManager.play("ui_cancel")
		action_return_menu_requested.emit()
	)

	_btn_retry = _make_button("REDEPLOY OPERATION", Vector2(210, 44), func():
		SoundManager.play("ui_confirm")
		show_game_over_modal = false
		action_restart_mission_requested.emit()
	)
	_btn_retry.visible = false

	_btn_debrief_menu = _make_button("RETURN TO COMMAND HQ", Vector2(220, 44), func():
		SoundManager.play("ui_click")
		action_return_menu_requested.emit()
	)
	_btn_debrief_menu.visible = false

func _make_button(label: String, min_sz: Vector2, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = min_sz
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	root_ctrl.add_child(b)
	return b

func _process(delta: float) -> void:
	_anim_time += delta
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
	_layout_hud_buttons()
	root_ctrl.queue_redraw()

func _layout_hud_buttons() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Top-right utility buttons
	_btn_manual.position = Vector2(vp.x - 426, 12)
	_btn_center.position = Vector2(vp.x - 268, 12)
	_btn_menu.position = Vector2(vp.x - 130, 12)

	# Bottom command action buttons
	var is_player_turn: bool = (GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE) and not skirmish_modal.visible and not show_game_over_modal
	_btn_wait.visible = is_player_turn and selected_mech != null and selected_mech.faction == MechData.Faction.PLAYER and not selected_mech.has_moved
	_btn_end_turn.visible = is_player_turn

	_btn_wait.position = Vector2(20, vp.y - 148)
	_btn_end_turn.position = Vector2(240, vp.y - 148)

	if show_game_over_modal:
		_btn_retry.visible = true
		_btn_debrief_menu.visible = true
		_btn_retry.position = Vector2(vp.x * 0.5 - 225, vp.y * 0.5 + 85)
		_btn_debrief_menu.position = Vector2(vp.x * 0.5 + 10, vp.y * 0.5 + 85)
	else:
		_btn_retry.visible = false
		_btn_debrief_menu.visible = false

func trigger_phase_banner(text: String) -> void:
	_banner_text = text
	_banner_timer = 1.65
	root_ctrl.queue_redraw()

func show_skirmish_resolution(result: SkirmishEngine.SkirmishResult) -> void:
	skirmish_modal.start_showdown(result)

func trigger_game_over() -> void:
	show_game_over_modal = true
	root_ctrl.queue_redraw()

func _on_root_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# 1. Top Command Telemetry Bar
	var top_bar := Rect2(0, 0, vp.x, 58)
	root_ctrl.draw_rect(top_bar, Color(0.07, 0.09, 0.07, 0.94), true)
	root_ctrl.draw_line(Vector2(0, 58), Vector2(vp.x, 58), Color(0.76, 0.58, 0.22, 0.9), 2.0)

	var map_title: String = map_def.map_name if map_def != null else "OPERATION: IRON GRID"
	var strat_badge: String = map_def.get_strategy_name() if map_def != null else "TACTICAL"
	var max_turns: int = map_def.turn_limit if map_def != null else 10

	root_ctrl.draw_string(font, Vector2(18, 25), "%s  [%s]" % [map_title, strat_badge], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.80, 0.32))
	root_ctrl.draw_string(
		font,
		Vector2(18, 46),
		"TURN %02d / %02d   |   COALITION MECHS: %d   |   SYNDICATE MECHS: %d   |   OBJECTIVES HELD: %d / %d" % [
			GlobalState.turn_number, max_turns, player_unit_count, ai_unit_count, player_obj_count, total_obj_count
		],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(0.80, 0.86, 0.76)
	)

	# Phase Status Pill in Center Top
	var phase_col := Color(0.42, 0.92, 0.50) if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE else Color(0.96, 0.36, 0.28)
	if GlobalState.current_phase == GlobalState.TurnPhase.RESOLUTION_PHASE:
		phase_col = Color(0.98, 0.82, 0.28)
	var phase_box := Rect2(vp.x * 0.5 - 140, 12, 280, 34)
	root_ctrl.draw_rect(phase_box, Color(0.11, 0.13, 0.11), true)
	root_ctrl.draw_rect(phase_box, phase_col, false, 1.8)
	root_ctrl.draw_string(font, phase_box.position + Vector2(10, 23), GlobalState.get_phase_name(), HORIZONTAL_ALIGNMENT_CENTER, 260, 13, phase_col)

	# 2. Left Panel — Active Mech Telemetry & Deck HUD
	var display_mech: MechData = selected_mech if selected_mech != null else hovered_mech
	if display_mech != null:
		_draw_left_unit_panel(font, Rect2(12, 68, 286, 472), display_mech)
	else:
		var empty_box := Rect2(12, 68, 286, 96)
		root_ctrl.draw_rect(empty_box, Color(0.07, 0.09, 0.07, 0.88), true)
		root_ctrl.draw_rect(empty_box, Color(0.35, 0.40, 0.32, 0.8), false, 1.5)
		root_ctrl.draw_string(font, Vector2(26, 98), "NO WALKER SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.78, 0.42))
		root_ctrl.draw_string(font, Vector2(26, 121), "Left-Click any friendly walker to plot", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.76, 0.68))
		root_ctrl.draw_string(font, Vector2(26, 140), "fuel range & engage Syndicate forces.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.76, 0.68))

	# 3. Right Panel — Terrain & Elevation Inspector + Combat Forecast
	if hovered_tile != null:
		_draw_right_terrain_panel(font, Rect2(vp.x - 308, 68, 296, 435))

	# 4. Bottom Comms Log & Controls Bar
	var bot_rect := Rect2(12, vp.y - 102, vp.x - 24, 88)
	root_ctrl.draw_rect(bot_rect, Color(0.06, 0.08, 0.06, 0.90), true)
	root_ctrl.draw_rect(bot_rect, Color(0.38, 0.44, 0.34, 0.85), false, 1.4)
	root_ctrl.draw_string(font, bot_rect.position + Vector2(14, 18), "TACTICAL COMMS LOG // (PAN: WASD / Arrows / Right-Drag | ZOOM: Wheel | WAIT/REFUEL: R | END TURN: E)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.72, 0.32))

	var log_count: int = GlobalState.combat_log.size()
	var start_idx: int = maxi(0, log_count - 3)
	for i in range(start_idx, log_count):
		var line_y: float = bot_rect.position.y + 38 + (i - start_idx) * 18
		root_ctrl.draw_string(font, Vector2(bot_rect.position.x + 16, line_y), GlobalState.combat_log[i], HORIZONTAL_ALIGNMENT_LEFT, int(bot_rect.size.x - 32), 12, Color(0.76, 0.86, 0.74))

	# 5. Phase Transition Banner (positioned below top bar so it never obscures the battlefield)
	if _banner_timer > 0.0:
		var b_alpha: float = clampf(_banner_timer * 1.5, 0.0, 0.95)
		var b_rect := Rect2(vp.x * 0.5 - 260, 68, 520, 44)
		root_ctrl.draw_rect(b_rect, Color(0.08, 0.10, 0.08, b_alpha), true)
		root_ctrl.draw_rect(b_rect, Color(0.95, 0.78, 0.28, b_alpha), false, 2.0)
		root_ctrl.draw_string(font, b_rect.position + Vector2(16, 29), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, 488, 17, Color(0.98, 0.86, 0.35, b_alpha))

	# 6. Optional Field Manual Modal
	if show_manual_modal:
		_draw_manual_modal(font, vp)

	# 7. Victory / Defeat Modal
	if show_game_over_modal:
		_draw_game_over_modal(font, vp)

func _draw_left_unit_panel(font: Font, rect: Rect2, m: MechData) -> void:
	var is_player: bool = (m.faction == MechData.Faction.PLAYER)
	var accent := Color(0.45, 0.88, 0.48) if is_player else Color(0.95, 0.35, 0.28)
	root_ctrl.draw_rect(rect, Color(0.07, 0.09, 0.07, 0.92), true)
	root_ctrl.draw_rect(rect, accent, false, 1.8)

	var x: float = rect.position.x + 14
	var y: float = rect.position.y + 22

	var fac_str := "8TH IRON DIVISION (PLAYER)" if is_player else "KRIEGS-SYNDIKAT (HOSTILE)"
	root_ctrl.draw_string(font, Vector2(x, y), fac_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)
	y += 20
	root_ctrl.draw_string(font, Vector2(x, y), m.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.96, 0.94, 0.86))
	y += 17
	root_ctrl.draw_string(font, Vector2(x, y), "%s // %s" % [m.unit_name, m.chassis_class], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.74, 0.78, 0.70))

	# Schematic Portrait Box
	var port := Rect2(x, y + 8, rect.size.x - 28, 96)
	root_ctrl.draw_rect(port, Color(0.04, 0.05, 0.04), true)
	root_ctrl.draw_rect(port, Color(0.24, 0.28, 0.22), false, 1.0)
	MechUnit.draw_mech_silhouette(
		root_ctrl,
		port.position + Vector2(port.size.x * 0.5, port.size.y * 0.80),
		m.chassis_id,
		m.faction,
		1.45,
		_anim_time
	)
	var status_txt := "ENTRENCHED (+15% DEF)" if m.is_entrenched else ("ORDER COMPLETE" if m.has_moved else "SYSTEMS READY")
	var status_col := Color(0.45, 0.95, 0.60) if not m.has_moved else Color(0.75, 0.75, 0.68)
	root_ctrl.draw_string(font, port.position + Vector2(8, 16), status_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, status_col)

	y += 118
	var bar_w: float = rect.size.x - 28

	# Hull Armor Bar
	root_ctrl.draw_string(font, Vector2(x, y), "ARMOR INTEGRITY: %d / %d  (RATING: %d)" % [m.current_armor, m.max_armor, m.armor_rating], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.90, 0.82))
	y += 6
	root_ctrl.draw_rect(Rect2(x, y, bar_w, 11), Color(0.16, 0.16, 0.16), true)
	root_ctrl.draw_rect(Rect2(x, y, bar_w * m.get_armor_ratio(), 11), Color(0.38, 0.88, 0.45), true)

	y += 24
	# Fuel Gauge
	root_ctrl.draw_string(font, Vector2(x, y), "DIESEL FUEL: %d / %d  (+%d/TURN)" % [m.current_fuel, m.max_fuel, m.passive_refuel], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.90, 0.98))
	y += 6
	root_ctrl.draw_rect(Rect2(x, y, bar_w, 11), Color(0.16, 0.16, 0.16), true)
	root_ctrl.draw_rect(Rect2(x, y, bar_w * m.get_fuel_ratio(), 11), Color(0.30, 0.78, 0.94), true)

	y += 24
	root_ctrl.draw_string(font, Vector2(x, y), "PRIMARY FIREPOWER: %d   |   GRID POS: (%d, %d)" % [m.firepower, m.grid_pos.x, m.grid_pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.96, 0.80, 0.34))

	y += 18
	var gear_note := "STANDARD TREAD/LEG GEAR"
	if m.amphibious_gear:
		gear_note = "AMPHIBIOUS SEALS (-2 River Fuel)"
	elif m.mountain_gear:
		gear_note = "QUAD CLIMBING GEAR (-2 Mountain/Climb Fuel)"
	elif m.fuel_efficiency_mod > 0:
		gear_note = "HEAVY CHASSIS (+1 Fuel off-road)"
	root_ctrl.draw_string(font, Vector2(x, y), "MOBILITY: " + gear_note, HORIZONTAL_ALIGNMENT_LEFT, int(bar_w), 11, Color(0.75, 0.84, 0.72))

	y += 22
	root_ctrl.draw_string(font, Vector2(x, y), "EQUIPMENT DECK (SKIRMISH LOADOUT):", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.84, 0.72))
	y += 8

	for i in range(m.deck.size()):
		var c: EquipmentCard = m.deck[i]
		var cr := Rect2(x, y + i * 38, bar_w, 34)
		root_ctrl.draw_rect(cr, Color(0.11, 0.13, 0.11), true)
		root_ctrl.draw_rect(cr, accent.darkened(0.35), false, 1.0)
		root_ctrl.draw_string(font, cr.position + Vector2(8, 14), "%d. %s [%s]" % [i + 1, c.card_name, c.category], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.92, 0.84))
		var edges := "RANKS [N:%s E:%s S:%s W:%s] | DMG:%d SHD:%d" % [
			EquipmentCard.format_rank(c.top),
			EquipmentCard.format_rank(c.right),
			EquipmentCard.format_rank(c.bottom),
			EquipmentCard.format_rank(c.left),
			c.damage_rating,
			c.shield_rating
		]
		root_ctrl.draw_string(font, cr.position + Vector2(8, 29), edges, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.74, 0.84, 0.72))

func _draw_right_terrain_panel(font: Font, rect: Rect2) -> void:
	var has_forecast: bool = not current_forecast.is_empty()
	var panel_h: float = 435.0 if has_forecast else 235.0
	var actual_rect := Rect2(rect.position, Vector2(rect.size.x, panel_h))

	root_ctrl.draw_rect(actual_rect, Color(0.07, 0.09, 0.07, 0.92), true)
	root_ctrl.draw_rect(actual_rect, Color(0.68, 0.56, 0.26, 0.9), false, 1.6)

	var x: float = actual_rect.position.x + 14
	var y: float = actual_rect.position.y + 22

	root_ctrl.draw_string(font, Vector2(x, y), "TERRAIN & ELEVATION TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.78, 0.32))
	y += 22
	root_ctrl.draw_string(font, Vector2(x, y), "SECTOR (%d, %d): %s" % [hovered_tile.coords.x, hovered_tile.coords.y, hovered_tile.get_terrain_name().to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.94, 0.86))
	y += 20
	root_ctrl.draw_string(font, Vector2(x, y), "ELEVATION HEIGHT: %dm (Level %d)" % [hovered_tile.get_elevation_meters(), hovered_tile.elevation], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.74, 0.88, 0.96))
	y += 20
	root_ctrl.draw_string(font, Vector2(x, y), "BASE FUEL COST: %d Fuel / Tile" % hovered_tile.get_base_fuel_cost(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.86, 0.86, 0.78))
	y += 20

	var atk_m: int = hovered_tile.get_attack_modifier_pct()
	var def_m: int = hovered_tile.get_defense_modifier_pct()
	root_ctrl.draw_string(font, Vector2(x, y), "TERRAIN ATTACK MOD: %+d%%" % atk_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.48, 0.95, 0.56) if atk_m >= 0 else Color(1.0, 0.42, 0.35))
	y += 20
	root_ctrl.draw_string(font, Vector2(x, y), "TERRAIN DEFENSE MOD: %+d%%" % def_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.48, 0.95, 0.56) if def_m >= 0 else Color(1.0, 0.42, 0.35))

	if hovered_tile.is_objective:
		y += 22
		var owner_txt := "8TH IRON DIVISION" if hovered_tile.controlled_by == 0 else ("KRIEGS-SYNDIKAT" if hovered_tile.controlled_by == 1 else "CONTESTED")
		root_ctrl.draw_string(font, Vector2(x, y), "STRATEGIC OBJECTIVE: %s (%s)" % [hovered_tile.objective_label, owner_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.98, 0.84, 0.32))

	if not hovered_reach_info.is_empty():
		y += 22
		root_ctrl.draw_string(
			font,
			Vector2(x, y),
			"PATH FUEL COST: -%d Fuel (Rem: %dF)" % [hovered_reach_info["fuel_spent"], hovered_reach_info["fuel_left"]],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.35, 0.92, 0.78)
		)

	# Combat Forecast Box if hovering an attackable enemy node!
	if has_forecast:
		y += 22
		var f_box := Rect2(x, y, actual_rect.size.x - 28, 175)
		root_ctrl.draw_rect(f_box, Color(0.18, 0.08, 0.07, 0.95), true)
		root_ctrl.draw_rect(f_box, Color(1.0, 0.38, 0.25), false, 2.0)

		var fx: float = x + 10
		var fy: float = y + 20
		root_ctrl.draw_string(font, Vector2(fx, fy), "SKIRMISH ENGAGEMENT FORECAST", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.78, 0.32))
		fy += 20
		root_ctrl.draw_string(font, Vector2(fx, fy), str(current_forecast.get("approach_summary", "")), HORIZONTAL_ALIGNMENT_LEFT, int(f_box.size.x - 16), 11, Color(0.92, 0.88, 0.78))
		fy += 22
		root_ctrl.draw_string(
			font,
			Vector2(fx, fy),
			"YOUR MOD: %+d%% (EFF FP: %d)" % [int(current_forecast["atk_mod_pct"]), int(current_forecast["atk_eff_fp"])],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.48, 0.95, 0.55)
		)
		fy += 20
		root_ctrl.draw_string(
			font,
			Vector2(fx, fy),
			"ENEMY MOD: %+d%% (EFF FP: %d)" % [int(current_forecast["def_mod_pct"]), int(current_forecast["def_eff_fp"])],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(1.0, 0.48, 0.40)
		)
		fy += 22
		root_ctrl.draw_string(
			font,
			Vector2(fx, fy),
			"DECK PROJECTION: %d CARDS  vs  %d CARDS" % [int(current_forecast["atk_cards_held"]), int(current_forecast["def_cards_held"])],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.98, 0.86, 0.38)
		)
		fy += 22
		root_ctrl.draw_string(
			font,
			Vector2(fx, fy),
			"EST. DAMAGE DEALT: ~%d   |   RETURN: ~%d" % [int(current_forecast["est_dmg_to_def"]), int(current_forecast["est_dmg_to_atk"])],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.95, 0.95, 0.90)
		)
		fy += 22
		root_ctrl.draw_string(font, Vector2(fx, fy), ">> LEFT-CLICK ENEMY NODE TO ENGAGE <<", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.42, 0.28))

func _draw_manual_modal(font: Font, vp: Vector2) -> void:
	root_ctrl.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.02, 0.78), true)
	var mw: float = 820.0
	var mh: float = 520.0
	var mr := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	root_ctrl.draw_rect(mr, Color(0.08, 0.10, 0.08, 0.98), true)
	root_ctrl.draw_rect(mr, Color(0.85, 0.68, 0.28), false, 2.5)

	var x: float = mr.position.x + 28
	var y: float = mr.position.y + 36
	root_ctrl.draw_string(font, Vector2(x, y), "FIELD MANUAL // TERRAIN, ELEVATION & SKIRMISH RULES (PRESS [H] TO CLOSE)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.96, 0.80, 0.32))
	y += 32

	var lines := [
		"1. TURN FLOW & FUEL MOBILITY:",
		"   - Each Turn follows: PLAYER COMMAND PHASE -> SKIRMISH RESOLUTION PHASE -> SYNDICATE AI PHASE.",
		"   - Moving consumes Diesel Fuel based on Terrain + Uphill Elevation Climb (+1 Fuel per 100m climbed).",
		"   - [WAIT / REFUEL] entrenches (+15% DEF) & restores +5 Fuel. Starting a turn on a City adds +4 Fuel & +12 Armor.",
		"   - Objective captures must be held through the enemy phase: objective victories are checked at turn end.",
		"",
		"2. TERRAIN CHART (FUEL COST | ATTACK MOD | DEFENSE MOD):",
		"   - TRANSIT ROAD (ROD):   1 Fuel |  +5% ATK |   0% DEF  (Fastest artery for Heavy Walkers)",
		"   - OPEN PLAIN (PLN):     2 Fuel |   0% ATK |  +5% DEF  (Standard maneuvering ground)",
		"   - FORTIFIED CITY (CTY): 2 Fuel | +10% ATK | +25% DEF  (Repairs +12 Armor & +4 Fuel each turn!)",
		"   - TRENCH TIMBER (TRN):  3 Fuel |  +5% ATK | +15% DEF  (Prepared defensive cover)",
		"   - RIVER FORD (RIV):     4 Fuel | -15% ATK | -15% DEF  (Bogged down & exposed! Avoid stopping here!)",
		"   - MOUNTAIN CRAG (MTN):  5 Fuel | +15% ATK | +30% DEF  (Commanding rock bastion)",
		"",
		"3. ELEVATION & HIGH GROUND ADVANTAGE:",
		"   - Attacking from higher elevation down onto an enemy grants +12% Firepower, +10% Armor, and +1 Card Rank per level!",
		"   - Attacking uphill suffers -10% Firepower and -1 Card Rank per elevation level.",
		"",
		"4. AUTOMATED SKIRMISH RESOLVER (TRIPLE TRIAD + STATS):",
		"   - Moving onto an enemy-occupied node triggers a Collision & launches the 3x3 Equipment Deck Clash.",
		"   - Cards compare directional ranks (N, E, S, W) against adjacent cards to flip/capture them!",
		"   - Matching sums on 2+ adjacent edges triggers a TACTICAL PLUS combo capture!"
	]
	for l in lines:
		var col := Color(0.95, 0.82, 0.36) if l.begins_with("1.") or l.begins_with("2.") or l.begins_with("3.") or l.begins_with("4.") else Color(0.82, 0.86, 0.78)
		root_ctrl.draw_string(font, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		y += 20

func _draw_game_over_modal(font: Font, vp: Vector2) -> void:
	root_ctrl.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.02, 0.85), true)
	var mw: float = 640.0
	var mh: float = 300.0
	var mr := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	var won: bool = (GlobalState.last_battle_winner == 0)
	var border_col := Color(0.45, 0.92, 0.50) if won else Color(0.95, 0.32, 0.25)

	root_ctrl.draw_rect(mr, Color(0.08, 0.10, 0.08, 0.98), true)
	root_ctrl.draw_rect(mr, border_col, false, 3.0)

	var title := "OPERATION VICTORY // SECTOR SECURED" if won else "OPERATION FAILED // COALITION ROUTED"
	root_ctrl.draw_string(font, mr.position + Vector2(20, 56), title, HORIZONTAL_ALIGNMENT_CENTER, int(mw - 40), 22, border_col)
	root_ctrl.draw_string(font, mr.position + Vector2(30, 110), GlobalState.last_battle_reason, HORIZONTAL_ALIGNMENT_CENTER, int(mw - 60), 15, Color(0.90, 0.88, 0.80))
	root_ctrl.draw_string(font, mr.position + Vector2(30, 150), "TURNS ELAPSED: %d" % GlobalState.turn_number, HORIZONTAL_ALIGNMENT_CENTER, int(mw - 60), 14, Color(0.75, 0.80, 0.72))
