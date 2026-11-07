class_name Battlefield
extends Node2D

## Root Battlefield Controller
## Orchestrates the Node Architecture: GlobalState, GridMap (IsoGridMap), UnitContainer,
## Camera2D, and UIOverlay. Manages Turn Flow: Player Phase -> Combat Encounter Phase -> AI Phase.

@onready var grid_map: IsoGridMap = $GridMap
@onready var unit_container: UnitContainer = $UnitContainer
@onready var camera: BattleCamera = $Camera2D
@onready var ui_overlay: UIOverlay = $UIOverlay

var current_map_def: MapDefinition

# Strike plans for the current selection, keyed by everything they depend on, so sweeping the
# cursor back and forth across enemies runs each search once. Cleared with the selection.
var _strike_plans: Dictionary = {}
const STRIKE_PLAN_CACHE_MAX := 64
## Uncapped movement-cost field of the selected walker (TerrainGrid.strike_cost_field), valid for one
## (walker, tile, occupancy epoch); every strike plan against any enemy then costs a few lookups.
var _strike_field: Dictionary = {}
var _strike_field_key: Array = []
var selected_unit: MechUnit = null
var _is_animating_move: bool = false:
	set(v):
		_is_animating_move = v
		if ui_overlay != null:
			ui_overlay.commands_locked = v   # END TURN / WAIT render disabled while a walker moves
var _phase_before_resolution: GlobalState.TurnPhase = GlobalState.TurnPhase.PLAYER_PHASE

# Pending collision context for Combat Resolution
var _pending_attacker: MechUnit = null
var _pending_defender: MechUnit = null
var _pending_target_coords: Vector2i = Vector2i.ZERO
var _pending_ai_target: MechUnit = null
var _pending_ai_attack_fuel: int = 0

# AI Turn Queue
var _ai_queue: Array[MechUnit] = []
var _auto_advance_token: int = 0
var _mission_token: int = 0

func _ready() -> void:
	grid_map.tile_hovered.connect(_on_tile_hovered)
	grid_map.tile_clicked.connect(_on_tile_clicked)

	ui_overlay.action_wait_refuel_requested.connect(_on_wait_refuel_requested)
	ui_overlay.action_rotate_requested.connect(_rotate_selected_unit)
	ui_overlay.action_next_mech_requested.connect(_select_next_player_unit)
	ui_overlay.action_end_turn_requested.connect(_on_end_turn_requested)
	ui_overlay.action_center_camera_requested.connect(_on_center_requested)
	ui_overlay.action_return_menu_requested.connect(_on_return_menu_requested)
	ui_overlay.action_restart_mission_requested.connect(_on_restart_mission_requested)
	ui_overlay.skirmish_modal_closed.connect(_on_skirmish_modal_closed)
	ui_overlay.modal_changed.connect(_on_modal_changed)
	_on_modal_changed()

	start_mission(GlobalState.selected_map_index)

func _exit_tree() -> void:
	# A skirmish still open when the scene is left must not leave rendering suppressed for the next one
	if grid_map != null:
		grid_map.suppress_redraw = false
	MechUnit.suppress_redraw = false

func start_mission(map_idx: int) -> void:
	_mission_token += 1
	_auto_advance_token += 1   # a countdown from the previous run must not start this one's AI phase
	GlobalState.reset_battle_state()
	# Drop any transient turn state left over from a previous run of this battlefield (Redeploy)
	selected_unit = null
	_is_animating_move = false
	_ai_queue.clear()
	_pending_attacker = null
	_pending_defender = null
	_pending_ai_target = null
	_pending_ai_attack_fuel = 0
	_phase_before_resolution = GlobalState.TurnPhase.PLAYER_PHASE
	_strike_plans.clear()
	_strike_field = {}
	_strike_field_key = []
	grid_map.suppress_redraw = false
	MechUnit.suppress_redraw = false
	var idx: int = clampi(map_idx, 0, GlobalState.maps.size() - 1)
	current_map_def = GlobalState.maps[idx]
	SkirmishEngine.clear_forecast_cache()
	ui_overlay.map_def = current_map_def
	ui_overlay.show_game_over_modal = false

	grid_map.load_from_definition(current_map_def)
	unit_container.spawn_units_for_map(current_map_def, grid_map)
	var chassis_ids: Array = []
	for sp in current_map_def.spawns:
		var cid := str(sp.get("chassis", "vanguard"))
		if not chassis_ids.has(cid):
			chassis_ids.append(cid)
	BattleStage.warm_assets(chassis_ids, BattleLayout.BACKDROP_BY_TERRAIN.keys())

	_update_all_objective_ownership()
	center_camera_on_map()

	GlobalState.add_log("MISSION START: %s (%s)" % [current_map_def.map_name, current_map_def.get_strategy_name()])
	GlobalState.add_log("OBJECTIVE: " + current_map_def.get_victory_condition_text())
	_begin_player_phase(true)

func center_camera_on_map() -> void:
	camera.center_on_map(current_map_def)

## C / the CAM hotspot. The AI phase owns the camera (it pans to each walker and waits on that pan).
func _on_center_requested() -> void:
	if GlobalState.current_phase != GlobalState.TurnPhase.AI_PHASE:
		center_camera_on_map()

## The camera takes pan / zoom / drag input only while no modal is up; set when a modal opens or closes.
func _on_modal_changed() -> void:
	camera.input_enabled = not ui_overlay.modal_open()

## True when the player may issue an order: their phase, no walker mid-move, no modal up.
func can_command() -> bool:
	return GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not _is_animating_move and not ui_overlay.modal_open()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		camera.handle_mouse(event)   # a release always ends a drag

	if ui_overlay.modal_blocks_map():
		camera.stop_drag()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			if ui_overlay.toggle_manual():
				camera.stop_drag()
			return
		if ui_overlay.show_manual_modal:
			if event.keycode == KEY_ESCAPE:
				ui_overlay.close_manual()
				camera.stop_drag()
			return
		if event.keycode == KEY_C:
			_on_center_requested()
			SoundManager.play("ui_click")
		elif event.keycode == KEY_E:
			_on_end_turn_requested()
		elif event.keycode == KEY_R:
			_on_wait_refuel_requested()
		elif event.keycode == KEY_T:
			_rotate_selected_unit()
		elif event.keycode == KEY_TAB or event.keycode == KEY_SPACE:
			_select_next_player_unit()
		elif event.keycode == KEY_ESCAPE:
			_deselect_unit()

	if ui_overlay.modal_open():
		camera.stop_drag()
		return

	if event is InputEventMouseButton:
		if ui_overlay.pointer_over_hud() and event.pressed:
			return   # a click on a HUD panel is not a click on the map
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grid_map.handle_click(grid_map.get_local_mouse_position())
		else:
			camera.handle_mouse(event)

	elif event is InputEventMouseMotion:
		camera.handle_mouse(event)
		if not ui_overlay.pointer_over_hud():
			grid_map.update_hover(grid_map.get_local_mouse_position())

# =============================================================================
# TURN FLOW: PLAYER PHASE
# =============================================================================
func _begin_player_phase(is_first_turn: bool = false) -> void:
	GlobalState.set_phase(GlobalState.TurnPhase.PLAYER_PHASE)
	_deselect_unit()

	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	_apply_turn_upkeep(p_units, not is_first_turn)

	_count_state()
	ui_overlay.trigger_phase_banner("TURN %02d // PLAYER COMMAND PHASE" % GlobalState.turn_number)
	SoundManager.play("phase_shift")

	# Auto-select first available player unit for convenience
	if p_units.size() > 0:
		_select_unit(p_units[0])

## Start-of-phase upkeep shared by both factions: snaps sprites to their grid tiles and applies
## Rules.apply_upkeep (order reset, then optional refuel / energy regen / City Depot resupply).
func _apply_turn_upkeep(units: Array[MechUnit], include_refuel: bool) -> void:
	for u in units:
		var m := u.mech_data
		u.position = grid_map.grid_to_screen(m.grid_pos, true)
		var healed: int = Rules.apply_upkeep(m, grid_map.get_tile(m.grid_pos), include_refuel)
		if healed > 0:
			GlobalState.add_log("%s repaired +%d Armor at City Depot." % [m.callsign, healed])

## WAIT / REFUEL order shared by both factions (see Rules.entrench). Returns fuel gained.
func _entrench_unit(m: MechData) -> int:
	return Rules.entrench(m, grid_map.get_tile(m.grid_pos))

func _select_unit(u: MechUnit) -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.is_selected = false
		selected_unit.queue_redraw()

	selected_unit = u
	if selected_unit != null:
		selected_unit.is_selected = true
		selected_unit.queue_redraw()
		ui_overlay.selected_mech = selected_unit.mech_data
		grid_map.selected_coords = selected_unit.mech_data.grid_pos
		if selected_unit.mech_data.faction == MechData.Faction.PLAYER and not selected_unit.mech_data.is_order_complete():
			var occ := unit_container.build_occupied_map(selected_unit)
			grid_map.compute_reachable_tiles(selected_unit.mech_data, occ)
		else:
			grid_map.clear_highlights()
			grid_map.selected_coords = selected_unit.mech_data.grid_pos
	else:
		ui_overlay.selected_mech = null
		grid_map.clear_highlights()

	_refresh_hover_telemetry(grid_map.hovered_coords)

func _deselect_unit() -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		selected_unit.is_selected = false
		selected_unit.queue_redraw()
	selected_unit = null
	ui_overlay.selected_mech = null
	_clear_hover_readouts()
	grid_map.clear_highlights()

## Clears the hovered-tile reach info, the combat forecast and the strike readout.
func _clear_hover_readouts() -> void:
	ui_overlay.hovered_reach_info = {}
	ui_overlay.current_forecast = {}
	_clear_strike_readout()

## Drops the OUT OF REACH box and the YOUR STEP COST row: the selected walker has used its order
## (or there is no selection), so neither applies any more.
func _clear_strike_readout() -> void:
	_strike_plans.clear()
	_strike_field = {}
	_strike_field_key = []
	ui_overlay.strike_plan = null
	ui_overlay.step_cost_mech = null

func _on_tile_hovered(coords: Vector2i, _tile: GridTileData) -> void:
	_refresh_hover_telemetry(coords)

func _refresh_hover_telemetry(coords: Vector2i) -> void:
	var td := grid_map.get_tile(coords)
	ui_overlay.hovered_tile = td
	var u_at := unit_container.get_unit_at(coords)
	ui_overlay.hovered_mech = u_at.mech_data if u_at != null else null
	ui_overlay.strike_plan = strike_plan_for(coords)
	ui_overlay.step_cost_mech = selected_unit.mech_data if _has_ready_player_selection() else null

	if grid_map.reachable_info.has(coords):
		var r_info: Dictionary = grid_map.reachable_info[coords]
		ui_overlay.hovered_reach_info = r_info   # read-only for the HUD; reachable_info is replaced, not mutated
		if r_info.get("is_attack", false) and selected_unit != null and u_at != null:
			var path: Array[Vector2i] = r_info["path"]
			var from_pos: Vector2i = path[path.size() - 2] if path.size() >= 2 else selected_unit.mech_data.grid_pos
			var from_tile := grid_map.get_tile(from_pos)
			var form_ctx := unit_container.get_formation_context(coords, from_pos, int(selected_unit.mech_data.faction))
			ui_overlay.current_forecast = SkirmishEngine.compute_forecast(
				selected_unit.mech_data, u_at.mech_data, from_tile, td, form_ctx
			)
		else:
			ui_overlay.current_forecast = {}
	else:
		ui_overlay.hovered_reach_info = {}
		ui_overlay.current_forecast = {}

## True while `selected_unit` still refers to a live walker (not freed, not wrecked).
func _selected_is_valid() -> bool:
	return selected_unit != null and is_instance_valid(selected_unit) and selected_unit.mech_data != null and selected_unit.mech_data.is_alive()

func _can_rotate_selected_unit() -> bool:
	return (can_command() and selected_unit != null
		and is_instance_valid(selected_unit) and selected_unit.mech_data.faction == MechData.Faction.PLAYER)

func _has_ready_player_selection() -> bool:
	return (GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and selected_unit != null
		and is_instance_valid(selected_unit) and selected_unit.mech_data.faction == MechData.Faction.PLAYER
		and not selected_unit.mech_data.is_order_complete())

## Why the selected walker cannot strike the enemy on `coords`, or null when there is nothing to
## explain: not the player phase, no ready player walker selected, no enemy there, or the enemy is
## already a highlighted attack target.
func strike_plan_for(coords: Vector2i) -> StrikePlan:
	if not _has_ready_player_selection() or grid_map.reachable_info.has(coords):
		return null
	var u_at := unit_container.get_unit_at(coords)
	if u_at == null or u_at.mech_data.faction == selected_unit.mech_data.faction:
		return null
	var m := selected_unit.mech_data
	if m.has_moved and absi(coords.x - m.grid_pos.x) + absi(coords.y - m.grid_pos.y) != 1:
		return null
	var key := [m, m.grid_pos, m.current_fuel, m.has_moved, coords, u_at, u_at.mech_data.grid_pos, unit_container.occupancy_epoch]
	var cached: StrikePlan = _strike_plans.get(key, null)
	if cached != null:
		return cached
	if _strike_plans.size() >= STRIKE_PLAN_CACHE_MAX:
		_strike_plans.clear()
	var occ := unit_container.build_occupied_map(selected_unit)
	var plan: StrikePlan
	if m.has_moved:
		# Only the start tile can launch now, so the targeted search settles after one pop: no field.
		plan = grid_map.compute_strike_plan(m, coords, occ)
	else:
		var field_key := [m, m.grid_pos, unit_container.occupancy_epoch]
		if field_key != _strike_field_key:
			_strike_field = grid_map.strike_cost_field(m, occ)
			_strike_field_key = field_key
		plan = grid_map.compute_strike_plan(m, coords, occ, _strike_field)
	_strike_plans[key] = plan
	return plan

func _on_tile_clicked(coords: Vector2i, _tile: GridTileData) -> void:
	if not can_command():
		return

	var clicked_unit := unit_container.get_unit_at(coords)

	# 1. If a ready player unit is selected and player clicked a reachable destination (move to empty tile, or attack adjacent enemy!)
	if _selected_is_valid() and selected_unit.mech_data.faction == MechData.Faction.PLAYER and not selected_unit.mech_data.is_order_complete():
		if grid_map.reachable_info.has(coords) and coords != selected_unit.mech_data.grid_pos:
			var info: Dictionary = grid_map.reachable_info[coords]
			var move_fuel: int = int(info["fuel_spent"])
			if info.get("is_attack", false) and clicked_unit != null:
				_execute_unit_attack(selected_unit, clicked_unit, move_fuel)
				return
			elif not selected_unit.mech_data.has_moved:
				var move_path: Array[Vector2i] = info["path"].duplicate()
				_execute_unit_movement(selected_unit, coords, move_path, move_fuel)
				return

	# 2. If a moved player unit is selected and player clicks an orthogonal neighbor empty tile -> reface toward it!
	if _selected_is_valid() and selected_unit.mech_data.faction == MechData.Faction.PLAYER and selected_unit.mech_data.has_moved and clicked_unit == null:
		var diff := coords - selected_unit.mech_data.grid_pos
		if diff in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_auto_advance_token += 1
			selected_unit.mech_data.set_facing(diff)
			selected_unit.mech_data.has_attacked = true
			SoundManager.play("ui_click")
			GlobalState.add_log("%s refaced to %s." % [selected_unit.mech_data.callsign, selected_unit.mech_data.get_facing_name()])
			selected_unit.queue_redraw()
			_refresh_hover_telemetry(coords)
			if not _has_unmoved_player_units():
				_start_auto_advance_timer(1.2)
			return

	# 3. Otherwise, clicking any unit selects it to inspect its telemetry & fuel range.
	# An enemy the selected walker could almost strike says why it can't (OUT OF REACH).
	if clicked_unit != null:
		_auto_advance_token += 1
		var plan := strike_plan_for(coords)
		if plan != null and plan.severity == StrikePlan.IN_STRIKING_DISTANCE:
			SoundManager.play("ui_cancel")
			GlobalState.add_log(plan.log_line(selected_unit.mech_data.callsign, clicked_unit.mech_data.callsign))
		else:
			SoundManager.play("ui_click")
		_select_unit(clicked_unit)
	else:
		_auto_advance_token += 1
		SoundManager.play("ui_cancel")
		_deselect_unit()

func _execute_unit_attack(attacker: MechUnit, defender: MechUnit, fuel_spent: int) -> void:
	if attacker == null or defender == null:
		return
	_auto_advance_token += 1
	var m_data := attacker.mech_data
	var atk_coords: Vector2i = m_data.grid_pos
	var def_coords: Vector2i = defender.mech_data.grid_pos

	if def_coords != atk_coords:
		m_data.set_facing(def_coords - atk_coords)
	m_data.current_fuel = maxi(0, m_data.current_fuel - fuel_spent)
	m_data.has_moved = true
	m_data.has_attacked = true
	m_data.is_entrenched = false
	attacker.queue_redraw()

	grid_map.clear_highlights()
	_clear_hover_readouts()

	GlobalState.add_log(
		"%s engaged %s at (%d,%d) from (%d,%d) [-%dF] -> COMBAT ENGAGED!" % [
			m_data.callsign, defender.mech_data.callsign, def_coords.x, def_coords.y,
			atk_coords.x, atk_coords.y, fuel_spent
		]
	)
	_trigger_skirmish_resolution(attacker, defender, atk_coords, def_coords)

func _execute_unit_movement(unit: MechUnit, target_coords: Vector2i, path: Array[Vector2i], fuel_spent: int) -> void:
	_is_animating_move = true
	var m_data := unit.mech_data
	var start_coords: Vector2i = m_data.grid_pos
	var move_path: Array[Vector2i] = path.duplicate()
	var from_coords: Vector2i = move_path[move_path.size() - 2] if move_path.size() >= 2 else start_coords

	var screen_pts: Array[Vector2] = []
	for p in move_path:
		screen_pts.append(grid_map.grid_to_screen(p, true))
	if screen_pts.size() < 2:
		screen_pts = [unit.position, grid_map.grid_to_screen(target_coords, true)]

	if target_coords != from_coords:
		m_data.facing = target_coords - from_coords
	m_data.current_fuel = maxi(0, m_data.current_fuel - fuel_spent)
	m_data.grid_pos = target_coords
	unit_container.note_unit_moved()
	m_data.has_moved = true
	m_data.is_entrenched = false

	grid_map.clear_highlights()
	_clear_hover_readouts()

	unit.animate_move_along_screen_points(screen_pts, func():
		if is_instance_valid(unit):
			unit.position = grid_map.grid_to_screen(target_coords, true)
			unit.queue_redraw()
		_is_animating_move = false
		_on_unit_movement_finished(unit, target_coords, fuel_spent)
	)

func _on_unit_movement_finished(unit: MechUnit, target_coords: Vector2i, fuel_spent: int) -> void:
	var dest_tile := grid_map.get_tile(target_coords)
	GlobalState.add_log(
		"%s advanced to %s (%d,%d) [-%d Fuel, %dF left]." % [
			unit.mech_data.callsign, dest_tile.get_terrain_name(), target_coords.x, target_coords.y,
			fuel_spent, unit.mech_data.current_fuel
		]
	)
	_update_all_objective_ownership()
	if _check_victory_conditions():
		return

	if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE:
		var occ := unit_container.build_occupied_map(unit)
		grid_map.compute_reachable_tiles(unit.mech_data, occ)
		_select_unit(unit)
	elif GlobalState.current_phase == GlobalState.TurnPhase.AI_PHASE:
		if _pending_ai_target != null and is_instance_valid(_pending_ai_target) and _pending_ai_target.mech_data.is_alive():
			var tgt := _pending_ai_target
			var atk_f := _pending_ai_attack_fuel
			_pending_ai_target = null
			_pending_ai_attack_fuel = 0
			_execute_unit_attack(unit, tgt, atk_f)
			return
		unit.mech_data.has_attacked = true
		var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
		var desired_facing := AIController.choose_best_facing(unit.mech_data.grid_pos, p_units)
		unit.mech_data.set_facing(desired_facing)
		unit.queue_redraw()
		GlobalState.add_log("%s refaced %s to meet Coalition threats." % [unit.mech_data.callsign, unit.mech_data.get_facing_name()])
		_process_next_ai_unit()

func _on_wait_refuel_requested() -> void:
	if not can_command():
		return
	if selected_unit == null or selected_unit.mech_data.faction != MechData.Faction.PLAYER or selected_unit.mech_data.is_order_complete():
		return

	var m := selected_unit.mech_data
	if m.has_moved:
		# Post-move HOLD POSITION: finishes the unit's turn without attacking or entrenching
		m.has_attacked = true
		GlobalState.add_log("%s holds position at (%d,%d)." % [m.callsign, m.grid_pos.x, m.grid_pos.y])
		grid_map.clear_highlights()
		grid_map.selected_coords = m.grid_pos
		_clear_hover_readouts()
		selected_unit.queue_redraw()
		_check_auto_advance_player_phase()
		return

	var gained_fuel: int = _entrench_unit(m)

	GlobalState.add_log("%s entrenched at (%d,%d) [%+d%% DEF, +%d Fuel, +%d EN]." % [
		m.callsign, m.grid_pos.x, m.grid_pos.y, Rules.entrench_def_pct(int(m.faction)), gained_fuel, MechData.WAIT_ENERGY])
	grid_map.clear_highlights()
	_clear_strike_readout()
	selected_unit.queue_redraw()
	_check_auto_advance_player_phase()

func _has_unmoved_player_units() -> bool:
	for u in unit_container.get_faction_units(MechData.Faction.PLAYER):
		if is_instance_valid(u) and u.mech_data != null and u.mech_data.is_alive() and not u.mech_data.is_order_complete():
			return true
	return false

func _start_auto_advance_timer(delay: float = 0.45) -> void:
	_auto_advance_token += 1
	var token: int = _auto_advance_token
	_after(delay, func():
		if token == _auto_advance_token and not _is_animating_move:
			_begin_ai_phase()
	, GlobalState.TurnPhase.PLAYER_PHASE)

## Runs `fn` after `delay` seconds unless the mission was restarted / ended meanwhile or the game is
## no longer in `phase` (the AI phase by default).
func _after(delay: float, fn: Callable, phase: GlobalState.TurnPhase = GlobalState.TurnPhase.AI_PHASE) -> void:
	var tok := _mission_token
	get_tree().create_timer(delay).timeout.connect(func():
		if tok == _mission_token and GlobalState.current_phase == phase:
			fn.call()
	)

func _check_auto_advance_player_phase(auto_select_unmoved: bool = true) -> void:
	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	if auto_select_unmoved:
		for u in p_units:
			if is_instance_valid(u) and u.mech_data != null and u.mech_data.is_alive() and not u.mech_data.is_order_complete():
				# Select next unmoved unit automatically
				_select_unit(u)
				return
	else:
		if _has_unmoved_player_units():
			return
	# All player units have moved -> automatically transition to AI Phase after brief pause
	_start_auto_advance_timer(0.45)

func _select_next_player_unit() -> void:
	if not can_command():
		return
	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	if p_units.is_empty():
		return
	_auto_advance_token += 1
	var cur_idx: int = p_units.find(selected_unit)
	for i in range(1, p_units.size() + 1):
		var candidate: MechUnit = p_units[(cur_idx + i) % p_units.size()]
		if is_instance_valid(candidate) and candidate.mech_data != null and candidate.mech_data.is_alive() and not candidate.mech_data.is_order_complete():
			_select_unit(candidate)
			SoundManager.play("ui_click")
			return
	for i in range(1, p_units.size() + 1):
		var candidate: MechUnit = p_units[(cur_idx + i) % p_units.size()]
		if is_instance_valid(candidate) and candidate.mech_data != null and candidate.mech_data.is_alive():
			_select_unit(candidate)
			SoundManager.play("ui_click")
			if not _has_unmoved_player_units():
				_start_auto_advance_timer(0.45)
			return

func _on_end_turn_requested() -> void:
	if not can_command():
		return
	_begin_ai_phase()

# =============================================================================
# TURN FLOW: COMBAT RESOLUTION PHASE (INTERACTIVE FF-STYLE ENCOUNTER)
# =============================================================================
func _trigger_skirmish_resolution(attacker: MechUnit, defender: MechUnit, from_coords: Vector2i, target_coords: Vector2i) -> void:
	_phase_before_resolution = GlobalState.current_phase
	GlobalState.set_phase(GlobalState.TurnPhase.RESOLUTION_PHASE)

	_pending_attacker = attacker
	_pending_defender = defender
	_pending_target_coords = target_coords

	var from_tile := grid_map.get_tile(from_coords)
	var target_tile := grid_map.get_tile(target_coords)

	var form_ctx := unit_container.get_formation_context(target_coords, from_coords, int(attacker.mech_data.faction))
	BalanceProbe.record_skirmish(attacker.mech_data, defender.mech_data, from_tile, target_tile, form_ctx)
	var session := SkirmishEngine.create_session(
		attacker.mech_data, defender.mech_data, from_tile, target_tile, true, GlobalState.next_battle_seed(), form_ctx
	)
	grid_map.suppress_redraw = true
	MechUnit.suppress_redraw = true
	ui_overlay.show_skirmish_session(session)

func _on_skirmish_modal_closed(result: SkirmishEngine.SkirmishResult) -> void:
	grid_map.suppress_redraw = false
	MechUnit.suppress_redraw = false
	grid_map.queue_redraw()
	BalanceProbe.record_outcome(result)
	GlobalState.add_log("COMBAT RESULT: " + result.summary_headline)

	var atk_alive: bool = (_pending_attacker != null and is_instance_valid(_pending_attacker) and _pending_attacker.mech_data.is_alive())
	var def_alive: bool = (_pending_defender != null and is_instance_valid(_pending_defender) and _pending_defender.mech_data.is_alive())

	if not def_alive and _pending_defender != null:
		GlobalState.add_log("%s WRECKED at Sector (%d,%d)!" % [_pending_defender.mech_data.callsign, _pending_target_coords.x, _pending_target_coords.y])
		unit_container.remove_destroyed_unit(_pending_defender)

	if not atk_alive and _pending_attacker != null:
		GlobalState.add_log("%s WRECKED during assault!" % [_pending_attacker.mech_data.callsign])
		unit_container.remove_destroyed_unit(_pending_attacker)

	if selected_unit != null and not _selected_is_valid():
		_deselect_unit()

	# Both units remain on their respective tiles; defenders never auto-reface out of turn.
	if atk_alive and _pending_attacker != null:
		_pending_attacker.position = grid_map.grid_to_screen(_pending_attacker.mech_data.grid_pos, true)
		if _pending_attacker.mech_data.faction == MechData.Faction.AI:
			var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
			_pending_attacker.mech_data.set_facing(AIController.choose_best_facing(_pending_attacker.mech_data.grid_pos, p_units))
		_pending_attacker.queue_redraw()
	if def_alive and _pending_defender != null:
		_pending_defender.position = grid_map.grid_to_screen(_pending_defender.mech_data.grid_pos, true)
		_pending_defender.queue_redraw()

	var surviving_player_attacker: MechUnit = null
	if atk_alive and _pending_attacker != null and _pending_attacker.mech_data.faction == MechData.Faction.PLAYER:
		surviving_player_attacker = _pending_attacker

	_pending_attacker = null
	_pending_defender = null
	_pending_ai_target = null
	_pending_ai_attack_fuel = 0

	_update_all_objective_ownership()
	grid_map.queue_redraw()

	if _check_victory_conditions():
		return

	# Resume previous phase
	GlobalState.set_phase(_phase_before_resolution)
	if _phase_before_resolution == GlobalState.TurnPhase.PLAYER_PHASE:
		if surviving_player_attacker != null:
			_select_unit(surviving_player_attacker)
		else:
			_check_auto_advance_player_phase()
			return
		if not _has_unmoved_player_units():
			_start_auto_advance_timer(0.45)
	elif _phase_before_resolution == GlobalState.TurnPhase.AI_PHASE:
		_after(0.35, _process_next_ai_unit)

# =============================================================================
# TURN FLOW: SYNDICATE AI PHASE
# =============================================================================
func _begin_ai_phase() -> void:
	_deselect_unit()
	GlobalState.set_phase(GlobalState.TurnPhase.AI_PHASE)
	ui_overlay.trigger_phase_banner("TURN %02d // SYNDICATE AI PHASE" % GlobalState.turn_number)
	GlobalState.add_log("--- SYNDICATE AI COMMAND PHASE INITIATED ---")

	# Finalize any player units that moved but did not attack
	for u in unit_container.get_faction_units(MechData.Faction.PLAYER):
		if is_instance_valid(u) and u.mech_data != null and u.mech_data.is_alive():
			if u.mech_data.has_moved and not u.mech_data.has_attacked:
				u.mech_data.has_attacked = true

	_ai_queue = unit_container.get_faction_units(MechData.Faction.AI)
	# Mirror the player: no refuel/repair upkeep before a faction's first phase
	_apply_turn_upkeep(_ai_queue, GlobalState.turn_number > 1)

	_after(0.65, _process_next_ai_unit)

func _process_next_ai_unit() -> void:
	if GlobalState.current_phase != GlobalState.TurnPhase.AI_PHASE:
		return

	while not _ai_queue.is_empty():
		var next_ai: MechUnit = _ai_queue.pop_front()
		if is_instance_valid(next_ai) and next_ai.mech_data != null and next_ai.mech_data.is_alive():
			_execute_single_ai_turn(next_ai)
			return

	# All AI units have completed their orders!
	_finish_ai_phase()

func _execute_single_ai_turn(ai_unit: MechUnit) -> void:
	ui_overlay.selected_mech = ai_unit.mech_data
	var tok := _mission_token
	# Smoothly pan camera toward active AI walker
	var cam_tw := camera.focus(ai_unit.position, 0.28)
	cam_tw.tween_callback(func():
		if tok != _mission_token or GlobalState.current_phase != GlobalState.TurnPhase.AI_PHASE:
			return
		if not is_instance_valid(ai_unit) or not ai_unit.mech_data.is_alive():
			_process_next_ai_unit()
			return
		var decision: Dictionary = AIController.choose_best_action(
			ai_unit, grid_map, unit_container, current_map_def
		)
		if decision.has("facing"):
			ai_unit.mech_data.facing = decision["facing"]
		var action_type: String = decision.get("type", AIController.ACTION_WAIT)
		if action_type == AIController.ACTION_WAIT:
			_pending_ai_target = null
			_pending_ai_attack_fuel = 0
			_entrench_unit(ai_unit.mech_data)
			GlobalState.add_log("%s entrenched & refueled at (%d,%d)." % [
				ai_unit.mech_data.callsign, ai_unit.mech_data.grid_pos.x, ai_unit.mech_data.grid_pos.y
			])
			ai_unit.queue_redraw()
			_after(0.32, _process_next_ai_unit)
		elif action_type == AIController.ACTION_ENGAGE:
			var target_pos: Vector2i = decision["target_pos"]
			var target_unit := unit_container.get_unit_at(target_pos, ai_unit)
			if target_unit == null:
				# The decision's target is gone: skip this walker rather than stall the phase
				_pending_ai_target = null
				_pending_ai_attack_fuel = 0
				_after(0.32, _process_next_ai_unit)
				return
			var move_pos: Vector2i = decision.get("move_pos", ai_unit.mech_data.grid_pos)
			var move_path: Array[Vector2i] = decision.get("move_path", [ai_unit.mech_data.grid_pos]).duplicate()
			var move_fuel: int = int(decision.get("move_fuel", 0))
			var attack_fuel: int = int(decision.get("attack_fuel", decision.get("fuel_spent", 0)))
			if move_pos == ai_unit.mech_data.grid_pos or move_path.size() <= 1:
				_pending_ai_target = null
				_pending_ai_attack_fuel = 0
				_execute_unit_attack(ai_unit, target_unit, attack_fuel)
			else:
				_pending_ai_target = target_unit
				_pending_ai_attack_fuel = attack_fuel
				_execute_unit_movement(ai_unit, move_pos, move_path, move_fuel)
		else:
			_pending_ai_target = null
			_pending_ai_attack_fuel = 0
			var target_pos: Vector2i = decision["target_pos"]
			var path: Array[Vector2i] = decision["path"].duplicate()
			var fuel_spent: int = int(decision["fuel_spent"])
			_execute_unit_movement(ai_unit, target_pos, path, fuel_spent)
	)

func _finish_ai_phase() -> void:
	_update_all_objective_ownership()
	if _check_victory_conditions(true):
		return

	GlobalState.turn_number += 1
	_begin_player_phase(false)

# =============================================================================
# OBJECTIVES & VICTORY / DEFEAT CONDITIONS
# =============================================================================
func _update_all_objective_ownership() -> void:
	for u in unit_container.units:
		if not is_instance_valid(u) or u.mech_data == null or not u.mech_data.is_alive():
			continue
		var td := grid_map.get_tile(u.mech_data.grid_pos)
		if td != null and td.is_objective:
			if td.controlled_by != u.mech_data.faction:
				td.controlled_by = u.mech_data.faction
				GlobalState.add_log("%s captured %s!" % [u.mech_data.callsign, td.objective_label])
	grid_map.queue_redraw()

## Counts living walkers and held objectives once, pushes them to the HUD and returns them as
## {player, ai, player_obj, total_obj}.
func _count_state() -> Dictionary:
	var p_count: int = unit_container.get_faction_units(MechData.Faction.PLAYER).size()
	var e_count: int = unit_container.get_faction_units(MechData.Faction.AI).size()
	var p_objs: int = 0
	var tot_objs: int = current_map_def.objectives.size() if current_map_def != null else 0
	if current_map_def != null:
		for obj in current_map_def.objectives:
			var td := grid_map.get_tile(obj["pos"])
			if td != null and td.controlled_by == MechData.Faction.PLAYER:
				p_objs += 1
	ui_overlay.player_unit_count = p_count
	ui_overlay.ai_unit_count = e_count
	ui_overlay.player_obj_count = p_objs
	ui_overlay.total_obj_count = tot_objs
	return {"player": p_count, "ai": e_count, "player_obj": p_objs, "total_obj": tot_objs}

func _check_victory_conditions(end_of_full_turn: bool = false) -> bool:
	var c := _count_state()
	var result := VictoryRules.evaluate(current_map_def, grid_map, c["player"], c["ai"],
		c["player_obj"], c["total_obj"], GlobalState.turn_number, end_of_full_turn)
	if result.is_empty():
		return false
	_declare_game_over(result["winner"], result["reason"])
	return true

func _declare_game_over(winner: int, reason: String) -> void:
	_mission_token += 1
	GlobalState.last_battle_winner = winner
	GlobalState.last_battle_reason = reason
	GlobalState.set_phase(GlobalState.TurnPhase.GAME_OVER)
	GlobalState.add_log("OPERATION CONCLUDED: " + reason)
	ui_overlay.trigger_game_over()

func _on_return_menu_requested() -> void:
	get_tree().change_scene_to_file(GlobalState.MAIN_MENU_SCENE)

func _on_restart_mission_requested() -> void:
	start_mission(GlobalState.selected_map_index)

func _rotate_selected_unit() -> void:
	if not _can_rotate_selected_unit():
		return
	_auto_advance_token += 1
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var cur_idx: int = dirs.find(selected_unit.mech_data.facing)
	var next_idx: int = (cur_idx + 1) % dirs.size()
	selected_unit.mech_data.set_facing(dirs[next_idx])
	SoundManager.play("ui_click")
	GlobalState.add_log("%s re-oriented facing to %s." % [selected_unit.mech_data.callsign, selected_unit.mech_data.get_facing_name()])
	selected_unit.queue_redraw()
	if grid_map.hovered_coords != Vector2i(-1, -1):
		_refresh_hover_telemetry(grid_map.hovered_coords)
	if not _has_unmoved_player_units():
		_start_auto_advance_timer(1.2)
