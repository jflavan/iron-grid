class_name BattleCamera
extends Camera2D

## The battlefield camera: keyboard pan (WASD / arrows), wheel zoom, right/middle-button drag,
## centring on a map and a smooth pan to a point. Battlefield owns every other kind of input and
## feeds mouse events here through handle_mouse(); `input_enabled` is false while a modal is up.

const PAN_SPEED := 420.0
const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.8
const ZOOM_STEP := 0.1
const DEFAULT_ZOOM := 0.86
const FOCUS_OFFSET := Vector2(0, 10)

var input_enabled: bool = true:
	set(v):
		input_enabled = v
		if not v:
			_dragging = false

var _dragging: bool = false
var _drag_last_mouse: Vector2 = Vector2.ZERO
var _tw: Tween = null   # the running focus pan; a new pan or a recentre replaces it

func _process(delta: float) -> void:
	if not input_enabled:
		return
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
		position += pan_dir.normalized() * (PAN_SPEED * delta / zoom.x)

func is_dragging() -> bool:
	return _dragging

func stop_drag() -> void:
	_dragging = false

## Wheel zoom and right/middle drag. A button release always ends a drag, even with input disabled.
func handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if not b.pressed and (b.button_index == MOUSE_BUTTON_RIGHT or b.button_index == MOUSE_BUTTON_MIDDLE):
			_dragging = false
			return
		if not input_enabled:
			return
		if b.button_index == MOUSE_BUTTON_RIGHT or b.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = b.pressed
			_drag_last_mouse = b.position
		elif b.button_index == MOUSE_BUTTON_WHEEL_UP and b.pressed:
			_set_zoom(zoom.x + ZOOM_STEP)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN and b.pressed:
			_set_zoom(zoom.x - ZOOM_STEP)
	elif event is InputEventMouseMotion and _dragging and input_enabled:
		var m := event as InputEventMouseMotion
		var diff: Vector2 = m.position - _drag_last_mouse
		_drag_last_mouse = m.position
		position -= diff / zoom.x

func _set_zoom(z: float) -> void:
	var nz: float = clampf(z, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(nz, nz)

func center_on_map(map_def: MapDefinition) -> void:
	if map_def == null:
		return
	_kill_focus()
	var cx: float = float(map_def.width - map_def.height) * (IsoGridMap.TILE_W * 0.25)
	var cy: float = float(map_def.width + map_def.height - 2) * (IsoGridMap.TILE_H * 0.25)
	position = Vector2(cx, cy + 8.0)
	zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)

## Smoothly pans to `pos` (plus a small downward offset) over `duration` seconds. Returns the tween
## so the caller can chain a callback.
func focus(pos: Vector2, duration: float = 0.28) -> Tween:
	_kill_focus()
	_tw = create_tween()
	_tw.tween_property(self, "position", pos + FOCUS_OFFSET, duration).set_trans(Tween.TRANS_SINE)
	return _tw

func _kill_focus() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
