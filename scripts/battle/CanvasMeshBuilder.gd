class_name CanvasMeshBuilder
extends RefCounted

## Records solid-colour 2D draw calls into vertex-coloured triangle meshes so static scenery can be
## replayed with one draw_mesh() per segment instead of one draw call per polygon / polyline. The GL
## Compatibility canvas renderer cannot batch polygons, so a terrain drawn command-by-command costs
## hundreds of draw calls every frame. Triangles keep submission order inside a mesh, so painter's
## order (and alpha blending) is the same as issuing the commands one by one.
##
## The draw_* methods mirror CanvasItem's signatures (and Godot's non-antialiased stroke geometry),
## so drawing code can target either a CanvasItem or a builder. Text cannot go into the mesh:
## add_text() closes the current segment and records the label, so replay() draws it at the same
## point in the order.

var _verts := PackedVector2Array()
var _cols := PackedColorArray()
var _ops: Array = []   # ArrayMesh, or [text: String, pos: Vector2, color: Color]

func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	# Fan triangulation: every polygon the terrain draws is convex.
	for i in range(1, points.size() - 1):
		_tri(points[0], points[i], points[i + 1], color)

func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0) -> void:
	var t: Vector2 = (from - to).orthogonal().normalized() * maxf(width, 1.0) * 0.5
	_quad(from + t, to + t, to - t, from - t, color)

func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0) -> void:
	var n: int = points.size()
	if n < 2:
		return
	var hw: float = maxf(width, 1.0) * 0.5
	# Joints use the averaged segment normal, like the canvas renderer's own polyline strip.
	var prev_t := Vector2.ZERO
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	left.resize(n)
	right.resize(n)
	for i in n:
		var t: Vector2
		if i == n - 1:
			t = prev_t
		else:
			t = (points[i + 1] - points[i]).normalized().orthogonal()
			if i == 0:
				prev_t = t
		var tangent: Vector2 = (t + prev_t).normalized() * hw
		left[i] = points[i] + tangent
		right[i] = points[i] - tangent
		prev_t = t
	for i in n - 1:
		_quad(left[i], left[i + 1], right[i + 1], right[i], color)

func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
	var r := rect.abs()
	if filled:
		_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), color)
		return
	# Outline strokes are centred on the edges and the horizontal ones overlap the corners, as in
	# CanvasItem.draw_rect(filled = false).
	var o: float = maxf(width, 1.0) * 0.5
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	draw_line(Vector2(x0 - o, y0), Vector2(x1 + o, y0), color, width)
	draw_line(Vector2(x0 - o, y1), Vector2(x1 + o, y1), color, width)
	draw_line(Vector2(x0, y0 + o), Vector2(x0, y1 - o), color, width)
	draw_line(Vector2(x1, y0 + o), Vector2(x1, y1 - o), color, width)

## Queues a PixelFont label between mesh segments, preserving draw order.
func add_text(text: String, pos: Vector2, color: Color) -> void:
	_flush()
	_ops.append([text, pos, color])

## Finishes recording; call once before replay().
func finish() -> void:
	_flush()

## Number of draw operations replay() issues (mesh segments plus labels).
func op_count() -> int:
	return _ops.size()

func replay(ci: CanvasItem) -> void:
	for op in _ops:
		if op is ArrayMesh:
			ci.draw_mesh(op, null)
		else:
			PixelFont.draw_text(ci, op[0], op[1], op[2])

func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_cols.append(color)
	_cols.append(color)
	_cols.append(color)

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_tri(a, b, c, color)
	_tri(a, c, d, color)

func _flush() -> void:
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ops.append(mesh)
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
