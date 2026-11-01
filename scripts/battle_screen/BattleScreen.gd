class_name BattleScreen
extends Control

## FF6-style battle screen that replaces SkirmishModal. Plays back an existing SkirmishResult
## (no rule changes) on a 360x225 BattleStage rendered in a SubViewport and scaled 4x with
## nearest-neighbour filtering.
##
## Contract kept from SkirmishModal (used by UIOverlay, Battlefield and the playtests):
##   start_showdown(result), signal resolution_confirmed(result), visible,
##   _all_steps_done, _on_skip_pressed(), _on_confirm_pressed()
## Controls: Space/Enter skip to the end, then confirm; S toggles 1x/2x speed.

signal resolution_confirmed(result: SkirmishEngine.SkirmishResult)

const NATIVE := Vector2i(360, 225)
const SCALE := 4

var current_result: SkirmishEngine.SkirmishResult = null
var stage: BattleStage
var _all_steps_done: bool = false
var _is_active: bool = false
var _fast_mode: bool = false
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
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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
	# Integer 4x (1440x900) centred; shrink to the largest integer scale that fits smaller windows.
	var avail := size if size.x > 0 else Vector2(NATIVE * SCALE)
	var s: int = maxi(1, mini(SCALE, mini(int(avail.x) / NATIVE.x, int(avail.y) / NATIVE.y)))
	var px := Vector2(NATIVE * s)
	_view.position = ((avail - px) / 2.0).floor()
	_view.size = px

func start_showdown(result: SkirmishEngine.SkirmishResult) -> void:
	current_result = result
	_is_active = true
	_all_steps_done = false
	visible = true
	stage.setup(result, BattleTimeline.build(result))
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
	if current_result.defender_destroyed or current_result.attacker_destroyed:
		SoundManager.play("mech_destroy")
	else:
		SoundManager.play("ui_confirm")

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _all_steps_done:
				_on_confirm_pressed()
			else:
				_on_skip_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S:
			_on_speed_pressed()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _all_steps_done:
			_on_confirm_pressed()
		accept_event()

func _on_speed_pressed() -> void:
	_fast_mode = not _fast_mode
	stage.speed_label = "2X" if _fast_mode else ""
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
	var res := current_result
	current_result = null
	resolution_confirmed.emit(res)
