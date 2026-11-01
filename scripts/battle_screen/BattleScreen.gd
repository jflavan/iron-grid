class_name BattleScreen
extends Control

## Classic Final Fantasy style battle screen rendered at native 360x225 inside a SubViewport
## and scaled 4x with nearest-neighbour filtering.
##
## Supports both:
## - start_session(session: SkirmishEngine.BattleSession): live interactive turn-based combat
##   where the player picks commands from ATTACK / TECH / DEFEND / RETREAT.
## - start_showdown(result: SkirmishEngine.SkirmishResult): playback of a resolved SkirmishResult.
##
## Controls:
## - Up/Down (or W) + Space/Enter, or Mouse Hover + Left-Click: navigate & select battle commands
## - Esc / Backspace / Right-Click: back out of TECH sub-menu
## - S: toggle 1x/2x animation speed
## - A: toggle Auto-Pilot (AI picks player commands automatically)
## - Space/Enter/Click (when not in command menu): skip to result, then confirm

signal resolution_confirmed(result: SkirmishEngine.SkirmishResult)

const NATIVE := Vector2i(360, 225)
const SCALE := 4

var current_result: SkirmishEngine.SkirmishResult = null
var current_session: SkirmishEngine.BattleSession = null
var stage: BattleStage
var _all_steps_done: bool = false
var _is_active: bool = false
var _fast_mode: bool = false
var _auto_pilot: bool = false
var _viewport: SubViewport
var _view: TextureRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_viewport = SubViewport.new()
	_viewport.size = NATIVE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	stage = BattleStage.new()
	_viewport.add_child(stage)
	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _view == null:
		return
	var avail := size if size.x > 0 else Vector2(NATIVE * SCALE)
	var s: int = maxi(1, mini(SCALE, mini(int(avail.x) / NATIVE.x, int(avail.y) / NATIVE.y)))
	var px := Vector2(NATIVE * s)
	_view.position = ((avail - px) / 2.0).floor()
	_view.size = px

func _screen_to_stage(screen_pos: Vector2) -> Vector2:
	if _view == null or _view.size.x <= 0 or _view.size.y <= 0:
		return screen_pos / float(SCALE)
	var rel := screen_pos - _view.position
	return Vector2(rel.x * float(NATIVE.x) / _view.size.x, rel.y * float(NATIVE.y) / _view.size.y)

## Starts a live interactive turn-based BattleSession.
func start_session(session: SkirmishEngine.BattleSession) -> void:
	current_session = session
	current_result = session.result
	_is_active = true
	_all_steps_done = false
	visible = true
	var tl := BattleTimeline.build(session.result)
	stage.auto_pilot = _auto_pilot
	stage.setup(session.result, tl, session)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.speed_label = "2X" if _fast_mode else ""
	SoundManager.play("radar_lock")

## Plays back a pre-resolved SkirmishResult (used by BattlePreview and unit tests).
func start_showdown(result: SkirmishEngine.SkirmishResult) -> void:
	current_session = null
	current_result = result
	_is_active = true
	_all_steps_done = false
	visible = true
	stage.auto_pilot = _auto_pilot
	stage.setup(result, BattleTimeline.build(result), null)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.speed_label = "2X" if _fast_mode else ""
	SoundManager.play("radar_lock")

func _process(delta: float) -> void:
	if not visible or not _is_active or current_result == null:
		return
	stage.advance(delta * (2.0 if _fast_mode else 1.0))
	if stage.finished and not _all_steps_done:
		_finish()

func _finish() -> void:
	_all_steps_done = true
	if current_session != null:
		current_session.apply_to_units()
	if current_result.defender_destroyed or current_result.attacker_destroyed:
		SoundManager.play("mech_destroy")
	else:
		SoundManager.play("ui_confirm")

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S:
			_on_speed_pressed()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_A:
			_on_auto_pressed()
			get_viewport().set_input_as_handled()
			return

		if stage.phase == "command_select":
			if event.keycode == KEY_UP or event.keycode == KEY_W:
				stage.move_cursor(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				stage.move_cursor(1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE:
				stage.cancel_submenu()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				stage.confirm_selection()
				get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _all_steps_done:
				_on_confirm_pressed()
			else:
				_on_skip_pressed()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible or not _is_active:
		return
	if event is InputEventMouseMotion:
		if stage.phase == "command_select":
			stage.handle_mouse_motion(_screen_to_stage(event.position))
	elif event is InputEventMouseButton and event.pressed:
		if stage.phase == "command_select":
			if event.button_index == MOUSE_BUTTON_RIGHT:
				stage.cancel_submenu()
				accept_event()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if stage.handle_mouse_click(_screen_to_stage(event.position)):
					accept_event()
					return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _all_steps_done:
				_on_confirm_pressed()
			else:
				_on_skip_pressed()
			accept_event()

func _on_speed_pressed() -> void:
	_fast_mode = not _fast_mode
	stage.speed_label = "2X" if _fast_mode else ""
	SoundManager.play("ui_click")

func _on_auto_pressed() -> void:
	_auto_pilot = not _auto_pilot
	stage.auto_pilot = _auto_pilot
	SoundManager.play("ui_click")

func _on_skip_pressed() -> void:
	if not _is_active or _all_steps_done:
		return
	SoundManager.play("ui_click")
	stage.skip_to_end()
	_finish()

func _on_confirm_pressed() -> void:
	if not _is_active:
		return
	if not _all_steps_done:
		_on_skip_pressed()
		return
	SoundManager.play("ui_confirm")
	_is_active = false
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var res := current_result
	current_result = null
	current_session = null
	resolution_confirmed.emit(res)
