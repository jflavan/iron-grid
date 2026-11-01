class_name Battlefield
extends Node2D

## Root Battlefield Controller
## Orchestrates the Node Architecture: GlobalState, GridMap (IsoGridMap), UnitContainer,
## Camera2D, and UIOverlay. Manages Turn Flow: Player Phase -> Combat Encounter Phase -> AI Phase.

@onready var grid_map: IsoGridMap = $GridMap
@onready var unit_container: UnitContainer = $UnitContainer
@onready var camera: Camera2D = $Camera2D
@onready var ui_overlay: UIOverlay = $UIOverlay

var current_map_def: MapDefinition

## Hull lost by a defender that loses the clash with no open tile to retreat to.
const CRUSH_DAMAGE: int = 15

var _strike_plan_key: Array = []
var _strike_plan_cached: StrikePlan = null
var selected_unit: MechUnit = null
var _is_animating_move: bool = false
var _phase_before_resolution: GlobalState.TurnPhase = GlobalState.TurnPhase.PLAYER_PHASE

# Pending collision context for Combat Resolution
var _pending_attacker: MechUnit = null
var _pending_defender: MechUnit = null
var _pending_start_coords: Vector2i = Vector2i.ZERO
var _pending_from_coords: Vector2i = Vector2i.ZERO
var _pending_target_coords: Vector2i = Vector2i.ZERO

# AI Turn Queue
var _ai_queue: Array[MechUnit] = []
var _is_dragging_cam: bool = false
var _drag_last_mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	grid_map.tile_hovered.connect(_on_tile_hovered)
	grid_map.tile_clicked.connect(_on_tile_clicked)

	ui_overlay.action_wait_refuel_requested.connect(_on_wait_refuel_requested)
	ui_overlay.action_end_turn_requested.connect(_on_end_turn_requested)
	ui_overlay.action_center_camera_requested.connect(center_camera_on_map)
	ui_overlay.action_return_menu_requested.connect(_on_return_menu_requested)
	ui_overlay.action_restart_mission_requested.connect(_on_restart_mission_requested)
	ui_overlay.skirmish_modal_closed.connect(_on_skirmish_modal_closed)

	start_mission(GlobalState.selected_map_index)

func start_mission(map_idx: int) -> void:
	GlobalState.reset_battle_state()
	# Drop any transient turn state left over from a previous run of this battlefield (Redeploy)
	selected_unit = null
	_is_animating_move = false
	_ai_queue.clear()
	_pending_attacker = null
	_pending_defender = null
	var idx: int = clampi(map_idx, 0, GlobalState.maps.size() - 1)
	current_map_def = GlobalState.maps[idx]
	SkirmishEngine.clear_forecast_cache()
	ui_overlay.map_def = current_map_def
	ui_overlay.show_game_over_modal = false

	grid_map.load_from_definition(current_map_def)
	unit_container.spawn_units_for_map(current_map_def, grid_map)

	_update_all_objective_ownership()
	center_camera_on_map()

	GlobalState.add_log("MISSION START: %s (%s)" % [current_map_def.map_name, current_map_def.get_strategy_name()])
	GlobalState.add_log("OBJECTIVE: " + current_map_def.get_victory_condition_text())
	_begin_player_phase(true)

func center_camera_on_map() -> void:
	if current_map_def == null:
		return
	var cx: float = float(current_map_def.width - current_map_def.height) * (IsoGridMap.TILE_W * 0.25)
	var cy: float = float(current_map_def.width + current_map_def.height - 2) * (IsoGridMap.TILE_H * 0.25)
	camera.position = Vector2(cx, cy + 8.0)
	camera.zoom = Vector2(0.86, 0.86)

func _process(delta: float) -> void:
	# Smooth keyboard camera panning
	if not ui_overlay.skirmish_modal.visible and not ui_overlay.show_game_over_modal:
		var pan_dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan_dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan_dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan_dir.y += 1.0
		if pan_dir != Vector2.ZERO:
			camera.position += pan_dir.normalized() * (420.0 * delta / camera.zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if ui_overlay.skirmish_modal.visible or ui_overlay.show_game_over_modal:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			ui_overlay.show_manual_modal = not ui_overlay.show_manual_modal
			SoundManager.play("ui_click")
			return
		if ui_overlay.show_manual_modal:
			if event.keycode == KEY_ESCAPE:
				ui_overlay.show_manual_modal = false
			return
		if event.keycode == KEY_C:
			center_camera_on_map()
			SoundManager.play("ui_click")
		elif event.keycode == KEY_E and GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not _is_animating_move:
			_on_end_turn_requested()
		elif event.keycode == KEY_R and GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not _is_animating_move:
			_on_wait_refuel_requested()
		elif event.keycode == KEY_ESCAPE:
			_deselect_unit()

	if ui_overlay.show_manual_modal:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging_cam = event.pressed
			_drag_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var nz: float = clampf(camera.zoom.x + 0.1, 0.65, 1.8)
			camera.zoom = Vector2(nz, nz)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var nz: float = clampf(camera.zoom.x - 0.1, 0.65, 1.8)
			camera.zoom = Vector2(nz, nz)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var local_pos := grid_map.get_local_mouse_position()
			grid_map.handle_click(local_pos)

	elif event is InputEventMouseMotion:
		if _is_dragging_cam:
			var diff: Vector2 = event.position - _drag_last_mouse
			_drag_last_mouse = event.position
			camera.position -= diff / camera.zoom.x
		var local_pos := grid_map.get_local_mouse_position()
		grid_map.update_hover(local_pos)

# =============================================================================
# TURN FLOW: PLAYER PHASE
# =============================================================================
func _begin_player_phase(is_first_turn: bool = false) -> void:
	GlobalState.set_phase(GlobalState.TurnPhase.PLAYER_PHASE)
	_deselect_unit()

	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	_apply_turn_upkeep(p_units, not is_first_turn)

	_sync_hud_counts()
	ui_overlay.trigger_phase_banner("TURN %02d // PLAYER COMMAND PHASE" % GlobalState.turn_number)
	SoundManager.play("phase_shift")

	# Auto-select first available player unit for convenience
	if p_units.size() > 0:
		_select_unit(p_units[0])

## Start-of-phase upkeep shared by both factions: clears last turn's orders, snaps sprites to their
## grid tiles, then (optionally) applies passive diesel refuel, reactor energy regen, plus City Depot
## resupply (+4 Fuel, +3 EN) and repairs (+12 Armor).
func _apply_turn_upkeep(units: Array[MechUnit], include_refuel: bool) -> void:
	for u in units:
		var m := u.mech_data
		m.has_moved = false
		m.is_entrenched = false
		u.position = grid_map.grid_to_screen(m.grid_pos, true)
		if not include_refuel:
			continue
		var tile := grid_map.get_tile(m.grid_pos)
		var refuel_amt: int = m.upkeep_refuel(tile)
		var energy_amt: int = m.passive_energy_regen
		if tile != null and tile.terrain_type == GridTileData.TerrainType.CITY:
			energy_amt += MechData.CITY_ENERGY
			var healed: int = mini(BalanceProbe.upkeep[int(m.faction)], m.max_armor - m.current_armor)
			m.current_armor += healed
			BalanceProbe.upkeep_healed[int(m.faction)] += healed
			if healed > 0:
				GlobalState.add_log("%s repaired +%d Armor at City Depot." % [m.callsign, healed])
		m.current_fuel = mini(m.max_fuel, m.current_fuel + refuel_amt)
		m.current_energy = mini(m.max_energy, m.current_energy + energy_amt)

## WAIT / REFUEL order shared by both factions: ends the unit's turn entrenched (+15% DEF),
## restores up to 5 Fuel and +4 Energy, and patches +8 Armor when holding a City. Returns fuel gained.
func _entrench_unit(m: MechData) -> int:
	m.has_moved = true
	m.is_entrenched = true
	var gained_fuel: int = m.wait_fuel_gain(m.current_fuel)
	m.current_fuel += gained_fuel
	m.current_energy = mini(m.max_energy, m.current_energy + MechData.WAIT_ENERGY)
	var td := grid_map.get_tile(m.grid_pos)
	BalanceProbe.entrench_actions[int(m.faction)] += 1
	if td != null and td.terrain_type == GridTileData.TerrainType.CITY:
		var before: int = m.current_armor
		m.current_armor = mini(m.max_armor, m.current_armor + BalanceProbe.patch[int(m.faction)])
		BalanceProbe.patch_healed[int(m.faction)] += m.current_armor - before
	return gained_fuel

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
		if selected_unit.mech_data.faction == MechData.Faction.PLAYER and not selected_unit.mech_data.has_moved:
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
	ui_overlay.hovered_reach_info = {}
	ui_overlay.current_forecast = {}
	_clear_strike_readout()
	grid_map.clear_highlights()

## Drops the OUT OF REACH box and the YOUR STEP COST row: the selected walker has used its order
## (or there is no selection), so neither applies any more.
func _clear_strike_readout() -> void:
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
		ui_overlay.hovered_reach_info = r_info.duplicate(true)
		if r_info.get("is_attack", false) and selected_unit != null and u_at != null:
			var path: Array[Vector2i] = r_info["path"]
			var from_pos: Vector2i = path[path.size() - 2] if path.size() >= 2 else selected_unit.mech_data.grid_pos
			var from_tile := grid_map.get_tile(from_pos)
			ui_overlay.current_forecast = SkirmishEngine.compute_forecast(
				selected_unit.mech_data, u_at.mech_data, from_tile, td
			)
		else:
			ui_overlay.current_forecast = {}
	else:
		ui_overlay.hovered_reach_info = {}
		ui_overlay.current_forecast = {}

func _has_ready_player_selection() -> bool:
	return (GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and selected_unit != null
		and is_instance_valid(selected_unit) and selected_unit.mech_data.faction == MechData.Faction.PLAYER
		and not selected_unit.mech_data.has_moved)

## Why the selected walker cannot strike the enemy on `coords`, or null when there is nothing to
## explain: not the player phase, no ready player walker selected, no enemy there, or the enemy is
## already a highlighted attack target.
func strike_plan_for(coords: Vector2i) -> StrikePlan:
	if not _has_ready_player_selection() or grid_map.reachable_info.has(coords):
		return null
	var u_at := unit_container.get_unit_at(coords)
	if u_at == null or u_at.mech_data.faction == selected_unit.mech_data.faction:
		return null
	# Hover and the click that follows ask the same question: answer it once per board state.
	var m := selected_unit.mech_data
	var occ := unit_container.build_occupied_map(selected_unit)
	var key := [m, m.grid_pos, m.current_fuel, coords, occ.keys()]
	if _strike_plan_key == key:
		return _strike_plan_cached
	_strike_plan_key = key
	_strike_plan_cached = grid_map.compute_strike_plan(m, coords, occ)
	return _strike_plan_cached

func _on_tile_clicked(coords: Vector2i, _tile: GridTileData) -> void:
	if GlobalState.current_phase != GlobalState.TurnPhase.PLAYER_PHASE or _is_animating_move:
		return

	var clicked_unit := unit_container.get_unit_at(coords)

	# 1. If a ready player unit is selected and player clicked a reachable destination (move or attack!)
	if selected_unit != null and selected_unit.mech_data.faction == MechData.Faction.PLAYER and not selected_unit.mech_data.has_moved:
		if grid_map.reachable_info.has(coords) and coords != selected_unit.mech_data.grid_pos:
			var info: Dictionary = grid_map.reachable_info[coords]
			var move_path: Array[Vector2i] = info["path"].duplicate()
			var move_fuel: int = int(info["fuel_spent"])
			_execute_unit_movement(selected_unit, coords, move_path, move_fuel)
			return

	# 2. Otherwise, clicking any unit selects it to inspect its telemetry & fuel range.
	# An enemy the selected walker could almost strike says why it can't (OUT OF REACH).
	if clicked_unit != null:
		var plan := strike_plan_for(coords)
		if plan != null and plan.severity == StrikePlan.IN_STRIKING_DISTANCE:
			SoundManager.play("ui_cancel")
			GlobalState.add_log(plan.log_line(selected_unit.mech_data.callsign, clicked_unit.mech_data.callsign))
		else:
			SoundManager.play("ui_click")
		_select_unit(clicked_unit)
	else:
		SoundManager.play("ui_cancel")
		_deselect_unit()

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

	m_data.prev_grid_pos = from_coords
	m_data.current_fuel = maxi(0, m_data.current_fuel - fuel_spent)
	m_data.grid_pos = target_coords
	m_data.has_moved = true
	m_data.is_entrenched = false

	grid_map.clear_highlights()
	ui_overlay.hovered_reach_info = {}
	ui_overlay.current_forecast = {}
	_clear_strike_readout()

	unit.animate_move_along_screen_points(screen_pts, func():
		if is_instance_valid(unit):
			unit.position = grid_map.grid_to_screen(target_coords, true)
			unit.queue_redraw()
		_is_animating_move = false
		_on_unit_movement_finished(unit, start_coords, from_coords, target_coords, fuel_spent)
	)

func _on_unit_movement_finished(unit: MechUnit, start_coords: Vector2i, from_coords: Vector2i, target_coords: Vector2i, fuel_spent: int) -> void:
	# Perform Collision Check on destination node!
	var opposing_unit := unit_container.check_opposing_collision(unit)
	if opposing_unit != null:
		GlobalState.add_log(
			"%s moved (-%dF) onto %s at (%d,%d) -> COMBAT ENGAGED!" % [
				unit.mech_data.callsign, fuel_spent, opposing_unit.mech_data.callsign, target_coords.x, target_coords.y
			]
		)
		_trigger_skirmish_resolution(unit, opposing_unit, start_coords, from_coords, target_coords)
		return

	# Non-collision move completed
	var dest_tile := grid_map.get_tile(target_coords)
	GlobalState.add_log(
		"%s advanced to %s (%d,%d) [-%d Fuel, %dF left]." % [
			unit.mech_data.callsign, dest_tile.get_terrain_name(), target_coords.x, target_coords.y,
			fuel_spent, unit.mech_data.current_fuel
		]
	)
	_update_all_objective_ownership()
	_sync_hud_counts()

	if _check_victory_conditions():
		return

	if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE:
		_select_unit(unit)
		_check_auto_advance_player_phase()
	elif GlobalState.current_phase == GlobalState.TurnPhase.AI_PHASE:
		_process_next_ai_unit()

func _on_wait_refuel_requested() -> void:
	if GlobalState.current_phase != GlobalState.TurnPhase.PLAYER_PHASE or _is_animating_move:
		return
	if selected_unit == null or selected_unit.mech_data.faction != MechData.Faction.PLAYER or selected_unit.mech_data.has_moved:
		return

	var m := selected_unit.mech_data
	var gained_fuel: int = _entrench_unit(m)

	GlobalState.add_log("%s entrenched at (%d,%d) [%+d%% DEF, +%d Fuel, +%d EN]." % [
		m.callsign, m.grid_pos.x, m.grid_pos.y, BalanceProbe.def_pct[int(m.faction)], gained_fuel, MechData.WAIT_ENERGY])
	grid_map.clear_highlights()
	_clear_strike_readout()
	selected_unit.queue_redraw()
	_check_auto_advance_player_phase()

func _check_auto_advance_player_phase() -> void:
	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	for u in p_units:
		if not u.mech_data.has_moved:
			# Select next unmoved unit automatically
			_select_unit(u)
			return
	# All player units have moved -> automatically transition to AI Phase after brief pause
	var timer := get_tree().create_timer(0.45)
	timer.timeout.connect(func():
		if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not _is_animating_move:
			_begin_ai_phase()
	)

func _on_end_turn_requested() -> void:
	if GlobalState.current_phase != GlobalState.TurnPhase.PLAYER_PHASE or _is_animating_move:
		return
	_begin_ai_phase()

# =============================================================================
# TURN FLOW: COMBAT RESOLUTION PHASE (INTERACTIVE FF-STYLE ENCOUNTER)
# =============================================================================
func _trigger_skirmish_resolution(attacker: MechUnit, defender: MechUnit, start_coords: Vector2i, from_coords: Vector2i, target_coords: Vector2i) -> void:
	_phase_before_resolution = GlobalState.current_phase
	GlobalState.set_phase(GlobalState.TurnPhase.RESOLUTION_PHASE)

	_pending_attacker = attacker
	_pending_defender = defender
	_pending_start_coords = start_coords
	_pending_from_coords = from_coords
	_pending_target_coords = target_coords

	var from_tile := grid_map.get_tile(from_coords)
	var target_tile := grid_map.get_tile(target_coords)

	BalanceProbe.record_skirmish(attacker.mech_data, defender.mech_data, from_tile, target_tile)
	var can_def_retreat := (unit_container.find_retreat_tile(target_coords, from_coords, grid_map) != Vector2i(-1, -1))
	var session := SkirmishEngine.create_session(
		attacker.mech_data, defender.mech_data, from_tile, target_tile, can_def_retreat, GlobalState.next_battle_seed()
	)
	ui_overlay.show_skirmish_session(session)

func _on_skirmish_modal_closed(result: SkirmishEngine.SkirmishResult) -> void:
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

	# If both units survived (e.g. via RETREAT or round limit), resolve node occupancy so two opposing units never stay stacked
	if atk_alive and def_alive:
		if result.attacker_won_clash:
			var retreat_coords := unit_container.find_retreat_tile(_pending_target_coords, _pending_from_coords, grid_map)
			if retreat_coords != Vector2i(-1, -1):
				# Capture locally: _pending_defender is cleared before the tween finishes
				var retreating: MechUnit = _pending_defender
				retreating.mech_data.grid_pos = retreat_coords
				retreating.animate_move_along_screen_points(
					[retreating.position, grid_map.grid_to_screen(retreat_coords, true)],
					func():
						if is_instance_valid(retreating):
							retreating.position = grid_map.grid_to_screen(retreat_coords, true)
				)
				_pending_attacker.mech_data.grid_pos = _pending_target_coords
				_pending_attacker.position = grid_map.grid_to_screen(_pending_target_coords, true)
				GlobalState.add_log("%s retreated to (%d,%d)!" % [_pending_defender.mech_data.callsign, retreat_coords.x, retreat_coords.y])
			else:
				# Defender has no retreat tile -> overrun crush damage, attacker steps back to approach tile
				_pending_defender.mech_data.current_armor = maxi(0, _pending_defender.mech_data.current_armor - CRUSH_DAMAGE)
				if not _pending_defender.mech_data.is_alive():
					GlobalState.add_log("%s crushed with no line of retreat!" % _pending_defender.mech_data.callsign)
					unit_container.remove_destroyed_unit(_pending_defender)
					_pending_attacker.mech_data.grid_pos = _pending_target_coords
					_pending_attacker.position = grid_map.grid_to_screen(_pending_target_coords, true)
				else:
					var fallback := _get_safe_fallback_coords(_pending_attacker, _pending_from_coords, _pending_start_coords)
					_pending_attacker.mech_data.grid_pos = fallback
					_pending_attacker.position = grid_map.grid_to_screen(fallback, true)
		else:
			# Attacker retreated or assault was repelled -> Attacker falls back to its approach node
			var fallback := _get_safe_fallback_coords(_pending_attacker, _pending_from_coords, _pending_start_coords)
			# Capture locally: _pending_attacker is cleared before the tween finishes
			var repelled: MechUnit = _pending_attacker
			repelled.mech_data.grid_pos = fallback
			repelled.animate_move_along_screen_points(
				[repelled.position, grid_map.grid_to_screen(fallback, true)],
				func():
					if is_instance_valid(repelled):
						repelled.position = grid_map.grid_to_screen(fallback, true)
			)

	_pending_attacker = null
	_pending_defender = null

	_update_all_objective_ownership()
	_sync_hud_counts()
	grid_map.queue_redraw()

	if _check_victory_conditions():
		return

	# Resume previous phase
	GlobalState.set_phase(_phase_before_resolution)
	if _phase_before_resolution == GlobalState.TurnPhase.PLAYER_PHASE:
		_check_auto_advance_player_phase()
	elif _phase_before_resolution == GlobalState.TurnPhase.AI_PHASE:
		var t := get_tree().create_timer(0.35)
		t.timeout.connect(_process_next_ai_unit)

func _get_safe_fallback_coords(attacker: MechUnit, from_coords: Vector2i, start_coords: Vector2i) -> Vector2i:
	if unit_container.get_unit_at(from_coords, attacker) == null:
		return from_coords
	if unit_container.get_unit_at(start_coords, attacker) == null:
		return start_coords
	var adj := unit_container.find_retreat_tile(from_coords, _pending_target_coords, grid_map)
	if adj != Vector2i(-1, -1):
		return adj
	return start_coords

# =============================================================================
# TURN FLOW: SYNDICATE AI PHASE
# =============================================================================
func _begin_ai_phase() -> void:
	_deselect_unit()
	GlobalState.set_phase(GlobalState.TurnPhase.AI_PHASE)
	ui_overlay.trigger_phase_banner("TURN %02d // SYNDICATE AI PHASE" % GlobalState.turn_number)
	GlobalState.add_log("--- SYNDICATE AI COMMAND PHASE INITIATED ---")

	_ai_queue = unit_container.get_faction_units(MechData.Faction.AI)
	# Mirror the player: no refuel/repair upkeep before a faction's first phase
	_apply_turn_upkeep(_ai_queue, GlobalState.turn_number > 1)

	var t := get_tree().create_timer(0.65)
	t.timeout.connect(_process_next_ai_unit)

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
	# Smoothly pan camera toward active AI walker
	var cam_tw := create_tween()
	cam_tw.tween_property(camera, "position", ai_unit.position + Vector2(0, 10), 0.28).set_trans(Tween.TRANS_SINE)
	cam_tw.tween_callback(func():
		if not is_instance_valid(ai_unit) or not ai_unit.mech_data.is_alive():
			_process_next_ai_unit()
			return
		var decision: Dictionary = AIController.choose_best_action(
			ai_unit, grid_map, unit_container, current_map_def
		)
		var action_type: String = decision.get("type", "WAIT_ENTRENCH")
		if action_type == "WAIT_ENTRENCH":
			_entrench_unit(ai_unit.mech_data)
			GlobalState.add_log("%s entrenched & refueled at (%d,%d)." % [
				ai_unit.mech_data.callsign, ai_unit.mech_data.grid_pos.x, ai_unit.mech_data.grid_pos.y
			])
			ai_unit.queue_redraw()
			var wait_t := get_tree().create_timer(0.32)
			wait_t.timeout.connect(_process_next_ai_unit)
		else:
			var target_pos: Vector2i = decision["target_pos"]
			var path: Array[Vector2i] = decision["path"].duplicate()
			var fuel_spent: int = int(decision["fuel_spent"])
			_execute_unit_movement(ai_unit, target_pos, path, fuel_spent)
	)

func _finish_ai_phase() -> void:
	_update_all_objective_ownership()
	_sync_hud_counts()
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

func _sync_hud_counts() -> void:
	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	var e_units := unit_container.get_faction_units(MechData.Faction.AI)
	ui_overlay.player_unit_count = p_units.size()
	ui_overlay.ai_unit_count = e_units.size()

	var p_objs: int = 0
	var tot_objs: int = current_map_def.objectives.size() if current_map_def != null else 0
	if current_map_def != null:
		for obj in current_map_def.objectives:
			var td := grid_map.get_tile(obj["pos"])
			if td != null and td.controlled_by == MechData.Faction.PLAYER:
				p_objs += 1
	ui_overlay.player_obj_count = p_objs
	ui_overlay.total_obj_count = tot_objs

func _check_victory_conditions(end_of_full_turn: bool = false) -> bool:
	_sync_hud_counts()
	var p_count: int = ui_overlay.player_unit_count
	var e_count: int = ui_overlay.ai_unit_count
	var p_objs: int = ui_overlay.player_obj_count
	var tot_objs: int = ui_overlay.total_obj_count

	# 1. Total Annihilation Checks
	if e_count == 0 and p_count > 0:
		_declare_game_over(0, "All Kriegs-Syndikat Armored Walkers have been destroyed!")
		return true
	if p_count == 0:
		_declare_game_over(1, "All 8th Iron Division Walkers were lost in action.")
		return true

	# 2. Strategy-Specific Objective Checks
	# Objective victories are only confirmed at the end of a full turn, so a capture must be held
	# through the enemy's response phase (otherwise turn-1 dashes into unguarded cities win outright).
	if current_map_def != null:
		match current_map_def.strategy_mode:
			MapDefinition.StrategyMode.OFFENSE:
				# Player wins by holding any Syndicate HQ Bunker at the end of a turn
				var hq_held := false
				for hq_pos in current_map_def.hq_positions:
					var hq := grid_map.get_tile(hq_pos)
					if hq != null and hq.is_objective and hq.controlled_by == MechData.Faction.PLAYER:
						hq_held = true
				if end_of_full_turn and hq_held:
					_declare_game_over(0, "8th Iron Division captured and held the Syndicate HQ Command Bunker!")
					return true
				if end_of_full_turn and GlobalState.turn_number >= current_map_def.turn_limit:
					_declare_game_over(1, "Turn limit expired before capturing the Syndicate HQ Bunker.")
					return true

			MapDefinition.StrategyMode.DEFENSE:
				# AI wins if it holds all Citadel Objectives at turn end; Player wins by holding out through Turn Limit
				if end_of_full_turn and tot_objs > 0 and p_objs == 0:
					_declare_game_over(1, "Syndicate forces overran all Citadel Bastion nodes!")
					return true
				if end_of_full_turn and GlobalState.turn_number >= current_map_def.turn_limit:
					_declare_game_over(0, "Citadel Höhenburg held firm through Turn %d against the Syndicate onslaught!" % current_map_def.turn_limit)
					return true

			MapDefinition.StrategyMode.PITCHED_BATTLE:
				if end_of_full_turn and tot_objs > 0 and p_objs == tot_objs:
					_declare_game_over(0, "8th Iron Division secured total control of all River Bridgeheads!")
					return true
				if end_of_full_turn and GlobalState.turn_number >= current_map_def.turn_limit:
					# Majority of bridgeheads wins; an even split goes to whoever has more walkers left
					if p_objs * 2 > tot_objs or (p_objs * 2 == tot_objs and p_count >= e_count):
						_declare_game_over(0, "Coalition forces secured strategic superiority across the Rhine-Fulda crossing!")
					else:
						_declare_game_over(1, "Syndicate forces held the majority of bridgeheads at Turn limit.")
					return true

	return false

func _declare_game_over(winner: int, reason: String) -> void:
	GlobalState.last_battle_winner = winner
	GlobalState.last_battle_reason = reason
	GlobalState.set_phase(GlobalState.TurnPhase.GAME_OVER)
	GlobalState.add_log("OPERATION CONCLUDED: " + reason)
	ui_overlay.trigger_game_over()

func _on_return_menu_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_restart_mission_requested() -> void:
	start_mission(GlobalState.selected_map_index)
