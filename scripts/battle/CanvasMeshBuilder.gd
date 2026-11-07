class_name CanvasMeshBuilder
extends RefCounted

## Records solid-colour 2D draw calls into vertex-coloured triangle meshes so static scenery can be
## replayed with one draw_mesh() per segment instead of one draw call per polygon / polyline. The GL
## Compatibility canvas renderer cannot batch polygons, so a terrain drawn command-by-command costs
## hundreds of draw calls every frame. Triangles keep submission order inside a mesh, so painter's
## order (and alpha blending) is the same as issuing the commands one by one.
##
## The draw_* methods mirror CanvasItem's signatures (and Godot's non-antialiased stroke geometry),
## so drawing code can target either a CanvasItem or a builder. The meshes are textured with
## PixelFont.mesh_atlas(): solid geometry samples its white band and labels (add_text) sample their
## glyphs exactly as PixelFont.draw_text would, so labels keep their place in the draw order and
## their filtering, and a whole map stays one draw call however many labels it has.

var _verts := PackedVector2Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _white_uv: Vector2 = PixelFont.mesh_white_uv()
var _ops: Array[ArrayMesh] = []
var _label_cache: Dictionary = {}   # [text, colour] -> [vertices at the origin, colours, UVs]

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

## Bakes a PixelFont label (same placement and texels as PixelFont.draw_text) into the mesh. Each
## distinct text/colour is built once; placing it is one native transform of the cached vertices.
func add_text(text: String, pos: Vector2, color: Color) -> void:
	var key := [text, color]
	var tpl: Array = _label_cache.get(key, [])
	if tpl.is_empty():
		var v := PackedVector2Array()
		var c := PackedColorArray()
		var uv := PackedVector2Array()
		for g in PixelFont.mesh_glyphs(text):
			var r: Rect2 = g[0]
			var t: Rect2 = g[1]
			v.append_array(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
				r.position, r.end, Vector2(r.position.x, r.end.y)]))
			uv.append_array(PackedVector2Array([t.position, Vector2(t.end.x, t.position.y), t.end,
				t.position, t.end, Vector2(t.position.x, t.end.y)]))
			for k in 6:
				c.append(color)
		tpl = [v, c, uv]
		_label_cache[key] = tpl
	if _verts.size() >= MAX_VERTS_PER_MESH:
		_flush()
	_verts.append_array(Transform2D(0.0, pos) * (tpl[0] as PackedVector2Array))
	_cols.append_array(tpl[1])
	_uvs.append_array(tpl[2])

## Vertices recorded so far (the whole bake once finish() has run).
func vertex_count() -> int:
	var n: int = _verts.size()
	for m in _ops:
		n += m.surface_get_array_len(0)
	return n

## Finishes recording; call once before replay(). Splits into several meshes only past
## MAX_VERTS_PER_MESH, so huge maps don't build one enormous vertex buffer.
func finish() -> void:
	_flush()

## Number of draw calls replay() issues (mesh segments).
func op_count() -> int:
	return _ops.size()

func replay(ci: CanvasItem) -> void:
	var atlas := PixelFont.mesh_atlas()
	for mesh in _ops:
		ci.draw_mesh(mesh, atlas)

const MAX_VERTS_PER_MESH := 196608

func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if _verts.size() >= MAX_VERTS_PER_MESH:
		_flush()
	var n: int = _verts.size()
	_verts.resize(n + 3)
	_cols.resize(n + 3)
	_uvs.resize(n + 3)
	_verts[n] = a
	_verts[n + 1] = b
	_verts[n + 2] = c
	for i in 3:
		_cols[n + i] = color
		_uvs[n + i] = _white_uv

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	if _verts.size() >= MAX_VERTS_PER_MESH:
		_flush()
	var n: int = _verts.size()
	_verts.resize(n + 6)
	_cols.resize(n + 6)
	_uvs.resize(n + 6)
	_verts[n] = a
	_verts[n + 1] = b
	_verts[n + 2] = c
	_verts[n + 3] = a
	_verts[n + 4] = c
	_verts[n + 5] = d
	for i in 6:
		_cols[n + i] = color
		_uvs[n + i] = _white_uv

func _flush() -> void:
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ops.append(mesh)
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	_uvs = PackedVector2Array()
