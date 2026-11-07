class_name CrtHotspots
extends RefCounted

## Clickable regions of a CrtUI screen, in virtual pixels. Screens rebuild the list every _draw
## (add() next to the thing they draw) and query it from input handlers.

var hovered: String = ""
var _spots: Array[Dictionary] = []

func clear() -> void:
	_spots.clear()

func add(id: String, r: Rect2) -> void:
	_spots.append({"id": id, "rect": r})

## Id under the virtual-pixel point, or "" when none. Later spots win (drawn on top).
func hit(p: Vector2) -> String:
	for i in range(_spots.size() - 1, -1, -1):
		if (_spots[i]["rect"] as Rect2).has_point(p):
			return _spots[i]["id"]
	return ""

func has(id: String) -> bool:
	for s in _spots:
		if s["id"] == id:
			return true
	return false

## Rect of the last spot registered under `id`, or an empty Rect2 when there is none.
func rect_of(id: String) -> Rect2:
	for i in range(_spots.size() - 1, -1, -1):
		if _spots[i]["id"] == id:
			return _spots[i]["rect"]
	return Rect2()
