class_name CrtScreen
extends Control

## Shared base of the screens drawn in the CRT menu style (MainMenu, and UIOverlay's root control):
## the clickable-region list rebuilt on every _draw, the integer pixel scale of the last draw, the
## redraw-on-change flag, and the pointer dispatch that maps mouse events to hotspot ids.

var _hot := CrtHotspots.new()
var _scale: int = 2
var _dirty: bool = true

## Hotspot id that is hit-tested (so it swallows the pointer) but shows the ordinary arrow cursor.
var passive_id: String = ""

func mark_dirty() -> void:
	_dirty = true

## Updates the hovered hotspot and the cursor shape from a mouse-motion event. Returns the id under
## the pointer ("" when none); marks the screen dirty when the hover changed.
func track_pointer(event: InputEventMouseMotion) -> String:
	var id := _hot.hit(CrtUI.to_virtual(event.position, _scale))
	if id != _hot.hovered:
		_dirty = true
	_hot.hovered = id
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if id != "" and id != passive_id else Control.CURSOR_ARROW
	return id

## Hotspot id under a mouse-button event's position ("" when none).
func hit_id(event: InputEventMouseButton) -> String:
	return _hot.hit(CrtUI.to_virtual(event.position, _scale))

## Id of the hotspot a left-button press landed on, or "" for any other event.
func clicked_id(event: InputEvent) -> String:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return hit_id(event)
	return ""
