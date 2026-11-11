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

## Strike plans of the current selection (cleared with it).
var _strike_cache := StrikePlanCache.new()
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
# The strike an AI walker will make once its move animation lands (cleared by _clear_pending_ai)
var _pending_ai_target: MechUnit = null
var _pending_ai_attack_fuel: int = 0

# AI Turn Queue
var _ai_queue: Array[MechUnit] = []
## Cancels a running "all walkers ordered, start the AI phase" countdown when bumped.
var _auto_advance_token: int = 0
var _mission_token: int = 0

## Story mode: the running mission's script (null in a skirmish theater). See StoryDirector.
var _story: StoryDirector = null
var _story_down: Array = []            # story pilots wrecked since the last victory check
var _story_cancel_skirmish: bool = false   # set by a "cancel_skirmish" effect while a battle is pending

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
	ui_overlay.action_story_continue_requested.connect(_on_story_continue_requested)
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
	_cancel_auto_advance()   # a countdown from the previous run must not start this one's AI phase
	GlobalState.reset_battle_state()
	# Drop any transient turn state left over from a previous run of this battlefield (Redeploy)
	selected_unit = null
	_is_animating_move = false
	_ai_queue.clear()
	_pending_attacker = null
	_pending_defender = null
	_clear_pending_ai()
	_phase_before_resolution = GlobalState.TurnPhase.PLAYER_PHASE
	_strike_cache.clear()
	grid_map.suppress_redraw = false
	MechUnit.suppress_redraw = false
	var mission := GlobalState.story_mission()
	if mission.is_empty():
		_story = null
		current_map_def = GlobalState.maps[clampi(map_idx, 0, GlobalState.maps.size() - 1)]
	else:
		_story = StoryDirector.new(mission)
		current_map_def = mission["map"]
	MusicManager.play(MusicCues.for_battle(mission))
	_story_down.clear()
	_story_cancel_skirmish = false
	ui_overlay.close_story_dialog()
	ui_overlay.story_mode = _story != null
	ui_overlay.story_heroes = mission.get("lose_if_lost", [])
	SkirmishEngine.clear_forecast_cache()
	ui_overlay.map_def = current_map_def
	ui_overlay.show_game_over_modal = false

	grid_map.load_from_definition(current_map_def)
	unit_container.spawn_units_for_map(current_map_def, grid_map)
	if _story != null:
		# A pilot the mission cannot lose survives one killing blow (see _second_wind_lines)
		for p: String in _second_wind_pilots():
			var hero := unit_container.unit_of_pilot(p)
			if hero != null:
				hero.mech_data.plot_armor = maxi(hero.mech_data.plot_armor, 1)
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

## C / the CAM hotspot. Always allowed: the AI phase's pans are cosmetic (its turns run on timers).
func _on_center_requested() -> void:
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
	_story_poll({"turn": GlobalState.turn_number}, func(fired: bool):
		if fired:
			_check_victory_conditions()
	)

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

func _clear_pending_ai() -> void:
	_pending_ai_target = null
	_pending_ai_attack_fuel = 0

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
	_strike_cache.clear()
	ui_overlay.strike_plan = null
	ui_overlay.step_cost_mech = null

func _on_tile_hovered(coords: Vector2i) -> void:
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
	return MechUnit.is_live(selected_unit)

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
	if m.has_moved and TerrainGrid.manhattan(coords, m.grid_pos) != 1:
		return null
	return _strike_cache.plan_for(grid_map, unit_container, selected_unit, coords, u_at)

func _on_tile_clicked(coords: Vector2i) -> void:
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
		if diff in TerrainGrid.DIRS:
			_cancel_auto_advance()
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
		_cancel_auto_advance()
		var plan := strike_plan_for(coords)
		if plan != null and plan.severity == StrikePlan.IN_STRIKING_DISTANCE:
			SoundManager.play("ui_cancel")
			GlobalState.add_log(plan.log_line(selected_unit.mech_data.callsign, clicked_unit.mech_data.callsign))
		else:
			SoundManager.play("ui_click")
		_select_unit(clicked_unit)
	else:
		_cancel_auto_advance()
		SoundManager.play("ui_cancel")
		_deselect_unit()

func _execute_unit_attack(attacker: MechUnit, defender: MechUnit, fuel_spent: int) -> void:
	if attacker == null or defender == null:
		return
	_cancel_auto_advance()
	var m_data := attacker.mech_data
	var atk_coords: Vector2i = m_data.grid_pos
	var def_coords: Vector2i = defender.mech_data.grid_pos

	if def_coords != atk_coords:
		m_data.set_facing(def_coords - atk_coords)
	m_data.spend_fuel(fuel_spent)
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
	m_data.spend_fuel(fuel_spent)
	unit_container.move_unit(unit, target_coords)
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
	_story_poll({}, func(_fired: bool): _after_movement(unit))

## The rest of a finished move, once any story beat it set off has played out.
func _after_movement(unit: MechUnit) -> void:
	if _check_victory_conditions():
		return
	if not MechUnit.is_live(unit):
		# A scripted event took the walker off the map mid-order
		_clear_pending_ai()
		if GlobalState.current_phase == GlobalState.TurnPhase.AI_PHASE:
			_process_next_ai_unit()
		return

	if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE:
		var occ := unit_container.build_occupied_map(unit)
		grid_map.compute_reachable_tiles(unit.mech_data, occ)
		_select_unit(unit)
	elif GlobalState.current_phase == GlobalState.TurnPhase.AI_PHASE:
		if unit.mech_data.faction != MechData.Faction.AI:
			_clear_pending_ai()   # it changed sides: its Syndikat order is void
			_process_next_ai_unit()
			return
		if MechUnit.is_live(_pending_ai_target) and _pending_ai_target.mech_data.faction != unit.mech_data.faction:
			var tgt := _pending_ai_target
			var atk_f := _pending_ai_attack_fuel
			_clear_pending_ai()
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

## The first living player walker (in spawn order) that still has an order to give, or null.
func _first_ready_player_unit() -> MechUnit:
	for u in unit_container.get_faction_units(MechData.Faction.PLAYER):
		if MechUnit.is_live(u) and not u.mech_data.is_order_complete():
			return u
	return null

func _has_unmoved_player_units() -> bool:
	return _first_ready_player_unit() != null

## Any player input cancels a running countdown to the AI phase.
func _cancel_auto_advance() -> void:
	_auto_advance_token += 1

func _start_auto_advance_timer(delay: float = 0.45) -> void:
	_cancel_auto_advance()
	var token: int = _auto_advance_token
	_after(delay, func():
		if token == _auto_advance_token and not _is_animating_move:
			_begin_ai_phase()
	, GlobalState.TurnPhase.PLAYER_PHASE)

## True while the mission that captured `tok` is still running and the game is in `phase`: the guard
## every deferred callback (timer, camera tween) applies before acting.
func _mission_alive(tok: int, phase: GlobalState.TurnPhase) -> bool:
	return tok == _mission_token and GlobalState.current_phase == phase

## Runs `fn` after `delay` seconds unless the mission was restarted / ended meanwhile or the game is
## no longer in `phase` (the AI phase by default).
func _after(delay: float, fn: Callable, phase: GlobalState.TurnPhase = GlobalState.TurnPhase.AI_PHASE) -> void:
	var tok := _mission_token
	get_tree().create_timer(delay).timeout.connect(func():
		if _mission_alive(tok, phase):
			fn.call()
	)

## Selects the next walker that still has an order; when none is left, the AI phase starts after a
## brief pause.
func _check_auto_advance_player_phase() -> void:
	var next_unit := _first_ready_player_unit()
	if next_unit != null:
		_select_unit(next_unit)
		return
	_start_auto_advance_timer(0.45)

func _select_next_player_unit() -> void:
	if not can_command():
		return
	var p_units := unit_container.get_faction_units(MechData.Faction.PLAYER)
	if p_units.is_empty():
		return
	_cancel_auto_advance()
	var cur_idx: int = p_units.find(selected_unit)
	for i in range(1, p_units.size() + 1):
		var candidate: MechUnit = p_units[(cur_idx + i) % p_units.size()]
		if MechUnit.is_live(candidate) and not candidate.mech_data.is_order_complete():
			_select_unit(candidate)
			SoundManager.play("ui_click")
			return
	for i in range(1, p_units.size() + 1):
		var candidate: MechUnit = p_units[(cur_idx + i) % p_units.size()]
		if MechUnit.is_live(candidate):
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

	_story_cancel_skirmish = false
	_story_poll({"skirmish": [attacker.mech_data.pilot_id, defender.mech_data.pilot_id]},
		func(_fired: bool): _open_skirmish(attacker, defender, from_coords, target_coords))

func _open_skirmish(attacker: MechUnit, defender: MechUnit, from_coords: Vector2i, target_coords: Vector2i) -> void:
	# A story beat may have called the fight off (a side switch, a scripted interception)
	if (_story_cancel_skirmish or not MechUnit.is_live(attacker) or not MechUnit.is_live(defender)
			or attacker.mech_data.faction == defender.mech_data.faction
			or (_story != null and not _story.forced.is_empty())):   # a scripted ending: no fight
		_story_cancel_skirmish = false
		_resume_after_skirmish(attacker if MechUnit.is_live(attacker) and attacker.mech_data.faction == MechData.Faction.PLAYER else null)
		return
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

	var atk_alive: bool = MechUnit.is_live(_pending_attacker)
	var def_alive: bool = MechUnit.is_live(_pending_defender)

	var down: Array = []
	if not def_alive and _pending_defender != null:
		GlobalState.add_log("%s WRECKED at Sector (%d,%d)!" % [_pending_defender.mech_data.callsign, _pending_target_coords.x, _pending_target_coords.y])
		_note_story_down(_pending_defender, down)
		unit_container.remove_destroyed_unit(_pending_defender)

	if not atk_alive and _pending_attacker != null:
		GlobalState.add_log("%s WRECKED during assault!" % [_pending_attacker.mech_data.callsign])
		_note_story_down(_pending_attacker, down)
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

	_update_all_objective_ownership()
	grid_map.queue_redraw()
	var after := func(): _story_poll({"down": down}, func(_fired: bool): _resume_after_skirmish(surviving_player_attacker))
	var wind := _second_wind_lines([_pending_attacker, _pending_defender])
	if wind.is_empty():
		after.call()
	else:
		var tok := _mission_token
		ui_overlay.show_story_dialog(wind, func():
			if tok == _mission_token:
				after.call()
		)

## Second wind: a pilot whose loss fails the mission is not wrecked by the first battle that would
## have killed them. Their plot armour is spent, the walker limps on at SECOND_WIND_HULL of its hull,
## and the next killing blow counts. Returns the dialog lines to show (empty when nobody was saved).
const SECOND_WIND_HULL := 0.35
const SECOND_WIND_LINES := {
	"leon": "...Hull breach. Emergency seals are holding. I can take one more like that. Only one.",
	"chad": "WHOA! Okay! That one HURT! Field patch is holding. Big Rig does not get a third chance, people!",
}

## Pilots who get a second wind this mission: the must-survive ones, plus any the script names.
func _second_wind_pilots() -> Array:
	return (_story.mission.get("lose_if_lost", []) as Array) + (_story.mission.get("second_wind", []) as Array)

func _second_wind_lines(fighters: Array) -> Array:
	var lines: Array = []
	if _story == null:
		return lines
	var heroes := _second_wind_pilots()
	for u in fighters:
		if not MechUnit.is_live(u):
			continue
		var m: MechData = u.mech_data
		if m.plot_armor <= 0 or m.current_armor > m.plot_armor or not heroes.has(m.pilot_id):
			continue
		m.plot_armor = 0
		m.current_armor = maxi(m.current_armor, ceili(m.max_armor * SECOND_WIND_HULL))
		SkirmishEngine.clear_forecast_cache()   # forecasts against this walker assumed the floor
		u.queue_redraw()
		GlobalState.add_log("%s is crippled but still standing (%d hull). The next killing blow will finish it." % [m.callsign, m.current_armor])
		lines.append({"who": m.pilot_id, "text": SECOND_WIND_LINES.get(m.pilot_id, "Still standing. Barely. Not again.")})
	return lines

## Ends the combat encounter phase: victory check, then back to the phase the fight interrupted.
## Also the path of a fight a story beat called off (nothing was fought, the attacker's order is spent).
func _resume_after_skirmish(surviving_player_attacker: MechUnit) -> void:
	_pending_attacker = null
	_pending_defender = null
	_clear_pending_ai()
	if not (MechUnit.is_live(surviving_player_attacker) and surviving_player_attacker.mech_data.faction == MechData.Faction.PLAYER):
		surviving_player_attacker = null
	if selected_unit != null and not _selected_is_valid():
		_deselect_unit()

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
		if MechUnit.is_live(u) and u.mech_data.has_moved and not u.mech_data.has_attacked:
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
		if MechUnit.is_live(next_ai):
			_execute_single_ai_turn(next_ai)
			return

	# All AI units have completed their orders!
	_finish_ai_phase()

func _execute_single_ai_turn(ai_unit: MechUnit) -> void:
	ui_overlay.selected_mech = ai_unit.mech_data
	# Pan the camera toward the active walker; the decision runs on its own timer, so anything that
	# kills the pan (a C / CAM recentre, a redeploy) cannot drop the AI turn.
	const PAN := 0.28
	camera.focus(ai_unit.position, PAN)
	_after(PAN, func():
		if not MechUnit.is_live(ai_unit):
			_process_next_ai_unit()
			return
		_clear_pending_ai()
		var decision: Dictionary = {"type": AIController.ACTION_WAIT} if _ai_holds_position(ai_unit) else AIController.choose_best_action(
			ai_unit, grid_map, unit_container, current_map_def
		)
		if decision.has("facing"):
			ai_unit.mech_data.facing = decision["facing"]
		var action_type: String = decision.get("type", AIController.ACTION_WAIT)
		if action_type == AIController.ACTION_WAIT:
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
				_after(0.32, _process_next_ai_unit)
				return
			var move_pos: Vector2i = decision["move_pos"]
			var move_path: Array[Vector2i] = decision["move_path"].duplicate()
			var move_fuel: int = int(decision["move_fuel"])
			var attack_fuel: int = int(decision["attack_fuel"])
			if move_pos == ai_unit.mech_data.grid_pos or move_path.size() <= 1:
				_execute_unit_attack(ai_unit, target_unit, attack_fuel)
			else:
				# Strike once the move animation lands (_on_unit_movement_finished)
				_pending_ai_target = target_unit
				_pending_ai_attack_fuel = attack_fuel
				_execute_unit_movement(ai_unit, move_pos, move_path, move_fuel)
		else:
			var target_pos: Vector2i = decision["target_pos"]
			var path: Array[Vector2i] = decision["path"].duplicate()
			var fuel_spent: int = int(decision["fuel_spent"])
			_execute_unit_movement(ai_unit, target_pos, path, fuel_spent)
	)

## A story walker told to stand its ground (MechData.hold_until_turn) waits out its turn until that
## turn comes, unless a Coalition walker is already next to it.
func _ai_holds_position(ai_unit: MechUnit) -> bool:
	var m := ai_unit.mech_data
	if GlobalState.turn_number >= m.hold_until_turn:
		return false
	for u in unit_container.get_faction_units(MechData.Faction.PLAYER):
		if TerrainGrid.manhattan(u.mech_data.grid_pos, m.grid_pos) == 1:
			return false
	return true

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
		if not MechUnit.is_live(u):
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
	var result: Dictionary = {}
	if _story != null:
		# The mission's own rules outrank the map's: a scripted ending, a pilot who must survive,
		# the target whose fall wins it.
		result = _story.verdict(_story_down)
		_story_down.clear()
	if result.is_empty():
		result = VictoryRules.evaluate(current_map_def, grid_map, c["player"], c["ai"],
			c["player_obj"], c["total_obj"], GlobalState.turn_number, end_of_full_turn)
	if result.is_empty():
		return false
	if _story != null and int(result["winner"]) == 0 and not _story.win_allowed():
		return false   # the mission's story beat has not happened yet: the battle goes on until it does
	_declare_game_over(result["winner"], result["reason"], str(result.get("title", "")))
	return true

func _declare_game_over(winner: int, reason: String, title: String = "") -> void:
	_mission_token += 1
	GlobalState.last_battle_winner = winner
	GlobalState.last_battle_reason = reason
	GlobalState.last_battle_title = title
	if _story != null and winner == 0:
		# Saved now, not after the debrief scene: leaving from the debrief must not lose the win
		StoryProgress.mark_cleared(GlobalState.story_chapter)
	MusicManager.play(MusicCues.for_outcome(GlobalState.story_mission(), winner == 0))
	GlobalState.set_phase(GlobalState.TurnPhase.GAME_OVER)
	GlobalState.add_log("OPERATION CONCLUDED: " + reason)
	ui_overlay.trigger_game_over()

func _on_return_menu_requested() -> void:
	GlobalState.leave_story()
	get_tree().change_scene_to_file(GlobalState.MAIN_MENU_SCENE)

func _on_restart_mission_requested() -> void:
	start_mission(GlobalState.selected_map_index)

func _rotate_selected_unit() -> void:
	if not _can_rotate_selected_unit():
		return
	_cancel_auto_advance()
	selected_unit.mech_data.set_facing(selected_unit.mech_data.next_facing())
	SoundManager.play("ui_click")
	GlobalState.add_log("%s re-oriented facing to %s." % [selected_unit.mech_data.callsign, selected_unit.mech_data.get_facing_name()])
	selected_unit.queue_redraw()
	if grid_map.hovered_coords != Vector2i(-1, -1):
		_refresh_hover_telemetry(grid_map.hovered_coords)
	if not _has_unmoved_player_units():
		_start_auto_advance_timer(1.2)

# =============================================================================
# STORY MODE: SCRIPTED BEATS (see StoryDirector for the trigger and effect vocabulary)
# =============================================================================
## A won story mission's debrief: on to the Story scene for the post-mission dialog.
func _on_story_continue_requested() -> void:
	GlobalState.story_stage = "post"
	get_tree().change_scene_to_file(GlobalState.STORY_SCENE)

func _note_story_down(u: MechUnit, down: Array) -> void:
	if u.mech_data.pilot_id != "":
		down.append(u.mech_data.pilot_id)
		_story_down.append(u.mech_data.pilot_id)
		if u.mech_data.faction == MechData.Faction.PLAYER and _story != null:
			_story.lost[u.mech_data.pilot_id] = true
		GlobalState.add_log("%s bailed out of the wreck." % StoryCast.display_name(u.mech_data.pilot_id))

## Asks the story which triggers `ctx` sets off, plays them in order (dialog, then effects), and
## calls `then(fired)` when the last one is done; at once, with false, when nothing fires or no
## story is running. Everything the caller does after a possible story beat belongs in `then`.
func _story_poll(ctx: Dictionary, then: Callable) -> void:
	if _story == null:
		then.call(false)
		return
	var fired := _story.poll(ctx, unit_container, grid_map)
	if fired.is_empty():
		then.call(false)
		return
	_play_story(fired, 0, _mission_token, then)

func _play_story(fired: Array[Dictionary], i: int, tok: int, then: Callable) -> void:
	if tok != _mission_token:
		return   # the mission was restarted or ended under the dialog
	if i >= fired.size():
		_settle_after_story()
		# An effect can itself set off the next beat (a wreck, a thinned-out enemy line)
		var more := _story.poll({"down": _story_down.duplicate()}, unit_container, grid_map)
		if more.is_empty():
			then.call(true)
		else:
			_play_story(more, 0, tok, then)
		return
	var trig: Dictionary = fired[i]
	var apply := func():
		if tok != _mission_token:
			return
		for e: Dictionary in trig.get("effects", []):
			_apply_story_effect(e)
		_play_story(fired, i + 1, tok, then)
	# A pilot who has bailed out of a wreck this mission no longer speaks on the battle net
	var lines: Array = (trig.get("lines", []) as Array).filter(func(l: Dictionary): return not _story.lost.has(str(l.get("who", ""))))
	if lines.is_empty():
		apply.call()
	else:
		ui_overlay.show_story_dialog(lines, apply)

## Brings the board's derived state back in line after effects moved, flipped or removed walkers.
func _settle_after_story() -> void:
	_update_all_objective_ownership()
	_count_state()
	_strike_cache.clear()
	SkirmishEngine.clear_forecast_cache()
	if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE:
		if _selected_is_valid():
			_select_unit(selected_unit)
		else:
			_select_unit(_first_ready_player_unit())

## One scripted effect. Selectors are {"pilot": id} and / or {"group": tag} (UnitContainer.select_units).
##   {"convert": sel}                 those walkers join the Coalition (the side switch)
##   {"rename": {"pilot", "to", "callsign"}}   the walker of `pilot` gets a new pilot id / callsign
##   {"withdraw": sel}                they leave the map intact
##   {"destroy": sel}                 they are wrecked where they stand
##   {"damage": {..sel, "amount"}}    they lose hull (never below 1)
##   {"friendly_fire": {"near": pilot, "amount"}}   the Syndikat walker nearest that pilot loses hull (never below 1)
##   {"spawn": [spawn entries]}       reinforcements, each on the free tile nearest its "pos"
##   {"plot_armor": {..sel, "value"}} sets MechData.plot_armor
##   {"cancel_skirmish": true}        the battle about to start does not happen
##   {"win": reason, "title": text} / {"lose": reason, "title": text}   ends the mission
##   {"music": track id}              the battle music changes (MusicCues.TRACKS)
##   {"log": text}                    a Comms Log line
func _apply_story_effect(e: Dictionary) -> void:
	if e.has("spawn"):
		for sp: Dictionary in e["spawn"]:
			var entry := sp.duplicate()
			entry["pos"] = unit_container.free_tile_near(sp.get("pos", Vector2i.ZERO), grid_map)
			var u := unit_container.spawn_unit(entry, grid_map)
			GlobalState.add_log("%s has entered the field at (%d,%d)!" % [u.mech_data.callsign, entry["pos"].x, entry["pos"].y])
	if e.has("convert"):
		for u in unit_container.select_units(e["convert"]):
			if u.mech_data.faction == MechData.Faction.PLAYER:
				continue
			unit_container.convert_unit(u, MechData.Faction.PLAYER)
			_ai_queue.erase(u)
			if _pending_ai_target == u:
				_clear_pending_ai()
			GlobalState.add_log("%s has turned its guns on the Syndikat!" % u.mech_data.callsign)
	if e.has("rename"):
		var r: Dictionary = e["rename"]
		var u := unit_container.unit_of_pilot(str(r.get("pilot", "")))
		if u != null:
			u.mech_data.pilot_id = str(r.get("to", u.mech_data.pilot_id))
			u.mech_data.callsign = str(r.get("callsign", u.mech_data.callsign))
			u.refresh_plate()
	if e.has("withdraw"):
		for u in unit_container.select_units(e["withdraw"]):
			GlobalState.add_log("%s withdrew from the field." % u.mech_data.callsign)
			_ai_queue.erase(u)
			unit_container.withdraw_unit(u)
	if e.has("destroy"):
		for u in unit_container.select_units(e["destroy"]):
			GlobalState.add_log("%s WRECKED!" % u.mech_data.callsign)
			u.mech_data.plot_armor = 0
			u.mech_data.current_armor = 0
			if u.mech_data.pilot_id != "":
				_story_down.append(u.mech_data.pilot_id)
			_ai_queue.erase(u)
			SoundManager.play("mech_destroy")
			unit_container.remove_destroyed_unit(u)
	if e.has("damage"):
		for u in unit_container.select_units(e["damage"]):
			_story_damage(u, int(e["damage"].get("amount", 0)))
	if e.has("friendly_fire"):
		var ff: Dictionary = e["friendly_fire"]
		var anchor := unit_container.unit_of_pilot(str(ff.get("near", "")))
		var best: MechUnit = null
		for u in unit_container.get_faction_units(MechData.Faction.AI):
			if u.mech_data.pilot_id != "":
				continue   # named Syndikat pilots are never the ones shelled
			if best == null or (anchor != null and TerrainGrid.manhattan(u.mech_data.grid_pos, anchor.mech_data.grid_pos)
					< TerrainGrid.manhattan(best.mech_data.grid_pos, anchor.mech_data.grid_pos)):
				best = u
		if best != null:
			_story_damage(best, int(ff.get("amount", 0)))
	if e.has("plot_armor"):
		for u in unit_container.select_units(e["plot_armor"]):
			u.mech_data.plot_armor = int(e["plot_armor"].get("value", 0))
	if e.has("cancel_skirmish"):
		_story_cancel_skirmish = true
	if e.has("win"):
		_story.forced = {"winner": 0, "reason": str(e["win"]), "title": str(e.get("title", ""))}
	if e.has("lose"):
		_story.forced = {"winner": 1, "reason": str(e["lose"]), "title": str(e.get("title", ""))}
	if e.has("music"):
		MusicManager.play(str(e["music"]))
	if e.has("log"):
		GlobalState.add_log(str(e["log"]))

func _story_damage(u: MechUnit, amount: int) -> void:
	var m := u.mech_data
	var dealt: int = mini(amount, m.current_armor - 1)
	if dealt <= 0:
		return
	m.current_armor -= dealt
	SoundManager.play("cannon_fire")
	GlobalState.add_log("%s took %d hull damage from a shell out of nowhere!" % [m.callsign, dealt])
	u.queue_redraw()
