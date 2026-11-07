class_name IsoGridMap
extends Node2D

## Isometric 2.5D Battlefield Grid Map
## Renders extruded terrain blocks, elevation cliffs, procedural terrain features (rivers, bridges,
## cities, trenches, mountains), fuel movement ranges, and path previews.

signal tile_hovered(coords: Vector2i)
signal tile_clicked(coords: Vector2i)

const TILE_W: float = 118.0
const TILE_H: float = 59.0
const ELEV_STEP: float = 12.0
const BASE_THICKNESS: float = 20.0

## The pure grid (tiles, bounds, pathfinding, strike plans); everything below is rendering on top.
var grid := TerrainGrid.new()
var grid_width: int:
	get: return grid.width
var grid_height: int:
	get: return grid.height
var tiles: Dictionary: # Vector2i -> GridTileData
	get: return grid.tiles

var hovered_coords: Vector2i = Vector2i(-1, -1):
	set(v):
		if v != hovered_coords:
			hovered_coords = v
			_overlay_dirty = true
var selected_coords: Vector2i = Vector2i(-1, -1):
	set(v):
		if v != selected_coords:
			selected_coords = v
			_overlay_dirty = true

# Dijkstra output: Vector2i -> { "fuel_spent": int, "fuel_left": int, "path": Array[Vector2i], "is_attack": bool }
# Replace it wholesale (never mutate it in place) so the overlay notices the change. Entries and
# their paths are shared read-only (current_path_preview, the HUD): duplicate a path before editing.
var reachable_info: Dictionary = {}:
	set(v):
		reachable_info = v
		_base_dirty = true
		_overlay_dirty = true
		_path_dirty = true
var current_path_preview: Array[Vector2i] = []:
	set(v):
		current_path_preview = v
		_path_dirty = true

var _anim_time: float = 0.0
var show_elev_labels: bool = true:
	set(v):
		if v != show_elev_labels:
			show_elev_labels = v
			_rebuild_terrain_mesh()
var _terrain_canvas: Node2D = null
var suppress_redraw: bool = false
var _tile_top: Dictionary = {} # Vector2i -> top-diamond centre (grid_to_screen with elevation)

# Static terrain, baked once per map into a few vertex-coloured meshes (see CanvasMeshBuilder).
var _terrain_mesh: CanvasMeshBuilder = null
# Tiles with per-frame ambient animation or badges (rivers, cities, objectives), as iso sort keys.
var _ambient_keys := PackedInt32Array()
# The sorted, de-duplicated iso keys of the ambient + reachable tiles and their decoded coords. Rebuilt
# only when the reachable set or the map changes (_base_dirty); a hover or selection change only
# re-derives the few extra keys below, so moving the mouse never re-sorts the whole list.
var _base_keys := PackedInt32Array()
var _base_coords: Array[Vector2i] = []
var _base_dirty: bool = true
# The (at most two) selected / hovered tiles that are not already in the base list, ascending.
var _extra_keys: Array[int] = []
var _overlay_dirty: bool = true
# Canvas transform and viewport size the overlay was last culled against.
var _view_xform := Transform2D()
var _view_size := Vector2.ZERO
# Overlay level of detail: below this canvas scale a river / city tile is one flat static tint
# instead of animated ripples / window lights (invisible at that size, and each costs 2-5 commands).
const LOD_SCALE: float = 0.5
var _lod: bool = false
# True when the last recording contained something animated (pulsing range highlight, river ripple,
# city lights); only then does the 30 Hz re-record have any visible effect.
var _anim_visible: bool = true
var _sel_loop := PackedVector2Array()
var _hov_loop := PackedVector2Array()
# Path preview polyline + fuel tag, rebuilt only when the preview or reachable set changes.
var _path_dirty: bool = true
var _path_pts := PackedVector2Array()
var _path_is_atk: bool = false
var _path_tag: String = ""

# Inset diamond outlines around the origin for the overlay (drawn with a translate transform).
static var _inset_cache: Dictionary = {}

func _ready() -> void:
	_terrain_canvas = Node2D.new()
	_terrain_canvas.name = "TerrainCanvas"
	_terrain_canvas.show_behind_parent = true
	add_child(_terrain_canvas)
	move_child(_terrain_canvas, 0)
	_terrain_canvas.draw.connect(_on_terrain_draw)

## The overlay's ambient motion (highlight pulse, river ripples, city lights) is slow, so it is
## re-recorded at this rate; hover / selection / range changes queue_redraw() at once.
const AMBIENT_FPS := 30.0
var _since_redraw: float = 0.0

func _process(delta: float) -> void:
	if suppress_redraw:
		return
	_anim_time += delta
	_since_redraw += delta
	# The overlay only records tiles inside the view, so a pan, zoom or resize re-records it.
	var xf: Transform2D = get_global_transform_with_canvas()
	var vs: Vector2 = get_viewport_rect().size
	if xf != _view_xform or vs != _view_size:
		_view_xform = xf
		_view_size = vs
		queue_redraw()
	# State changes record at once; the 30 Hz tick is only for ambient motion that is in view.
	if _base_dirty or _overlay_dirty or _path_dirty:
		queue_redraw()
	if _since_redraw < 1.0 / AMBIENT_FPS:
		return
	if _anim_visible:
		_since_redraw = 0.0
		queue_redraw()

func load_from_definition(map_def: MapDefinition) -> void:
	grid.load_from_definition(map_def)
	reachable_info = {}
	current_path_preview = []
	hovered_coords = Vector2i(-1, -1)
	selected_coords = Vector2i(-1, -1)

	_tile_top.clear()
	for c: Vector2i in tiles.keys():
		_tile_top[c] = grid_to_screen(c, true)

	_ambient_keys = PackedInt32Array()
	for c: Vector2i in tiles.keys():
		var td: GridTileData = tiles[c]
		if td.is_objective or td.terrain_type == GridTileData.TerrainType.RIVER or td.terrain_type == GridTileData.TerrainType.CITY:
			_ambient_keys.append(_iso_key(c))
	_ambient_keys.sort()
	_base_dirty = true
	_overlay_dirty = true

	_rebuild_terrain_mesh()
	queue_redraw()

## Bakes the static terrain into meshes. Static scenery only changes when a map loads.
func _rebuild_terrain_mesh() -> void:
	_terrain_mesh = CanvasMeshBuilder.new()
	var max_sum: int = (grid_width - 1) + (grid_height - 1)
	for s in range(0, max_sum + 1):
		for x in range(grid_width):
			var y: int = s - x
			if y < 0 or y >= grid_height:
				continue
			var coords := Vector2i(x, y)
			var td: GridTileData = tiles.get(coords, null)
			if td == null:
				continue
			_draw_static_tile(_terrain_mesh, coords, td)
	_terrain_mesh.finish()
	if _terrain_canvas != null:
		_terrain_canvas.queue_redraw()

## Sort key matching the iso back-to-front draw order (x + y ascending, then x ascending).
func _iso_key(c: Vector2i) -> int:
	return (c.x + c.y) * grid_width + c.x

func is_valid_coords(coords: Vector2i) -> bool:
	return grid.is_valid_coords(coords)

func get_tile(coords: Vector2i) -> GridTileData:
	return grid.get_tile(coords)

## Converts grid coordinates (x, y) into local 2D screen position (center of the tile's top diamond).
func grid_to_screen(coords: Vector2i, include_elevation: bool = true) -> Vector2:
	var sx: float = float(coords.x - coords.y) * (TILE_W * 0.5)
	var sy: float = float(coords.x + coords.y) * (TILE_H * 0.5)
	if include_elevation:
		sy -= float(grid.get_tile_elevation(coords)) * ELEV_STEP
	return Vector2(sx, sy)

## Returns the 4 vertices of the top isometric diamond at `center`.
func get_diamond_points(center: Vector2, inset: float = 0.0) -> PackedVector2Array:
	var hw: float = TILE_W * 0.5 - inset * 2.0
	var hh: float = TILE_H * 0.5 - inset
	return PackedVector2Array([
		center + Vector2(0, -hh), # Top
		center + Vector2(hw, 0),  # Right
		center + Vector2(0, hh),  # Bottom
		center + Vector2(-hw, 0)  # Left
	])

## Converts local 2D screen position to grid coordinates, accurately accounting for 3D tile elevation.
func screen_to_grid(local_pos: Vector2) -> Vector2i:
	var hw: float = TILE_W * 0.5
	var hh: float = TILE_H * 0.5
	var u: float = local_pos.x / hw
	var best_c := Vector2i(-1, -1)
	var best_depth: int = -1

	# Check elevations 0..MAX_ELEVATION (400m = level 4)
	for elev in range(0, GridTileData.MAX_ELEVATION + 1):
		var v: float = (local_pos.y + float(elev) * ELEV_STEP) / hh
		var cx_f: float = (u + v) * 0.5
		var cy_f: float = (v - u) * 0.5
		var x: int = int(floor(cx_f + 0.5))
		var y: int = int(floor(cy_f + 0.5))
		if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
			continue
		var c := Vector2i(x, y)
		var td: GridTileData = tiles.get(c, null)
		if td == null or td.elevation != elev:
			continue
		var dx: float = absf(local_pos.x - float(x - y) * hw) / hw
		var dy: float = absf(local_pos.y - (float(x + y) * hh - float(elev) * ELEV_STEP)) / hh
		if dx + dy <= 1.0001:
			var depth: int = x + y
			if depth > best_depth:
				best_depth = depth
				best_c = c

	return best_c

## Pure data query: computes all reachable tiles for `unit` given `occupied_units` without modifying UI state.
func find_reachable_tiles(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	return grid.find_reachable_tiles(unit, occupied_units)

## Computes all reachable tiles for `unit` given `occupied_units` (Dictionary: Vector2i -> MechData)
## and shows them on the overlay (find_reachable_tiles is the pure query).
func compute_reachable_tiles(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	current_path_preview = []
	reachable_info = find_reachable_tiles(unit, occupied_units)
	queue_redraw()
	return reachable_info

## See TerrainGrid.compute_strike_plan. Never touches reachable_info.
func compute_strike_plan(unit: MechData, target: Vector2i, occupied_units: Dictionary, cost_field: Dictionary = {}) -> StrikePlan:
	return grid.compute_strike_plan(unit, target, occupied_units, cost_field)

## See TerrainGrid.strike_cost_field: compute once per selection, pass to compute_strike_plan.
func strike_cost_field(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	return grid.strike_cost_field(unit, occupied_units)

func clear_highlights() -> void:
	reachable_info = {}
	current_path_preview = []
	selected_coords = Vector2i(-1, -1)
	queue_redraw()

func update_hover(local_mouse_pos: Vector2) -> void:
	var new_hover := screen_to_grid(local_mouse_pos)
	if new_hover != hovered_coords:
		hovered_coords = new_hover
		if reachable_info.has(hovered_coords):
			current_path_preview = reachable_info[hovered_coords]["path"]
		else:
			current_path_preview = []
		tile_hovered.emit(hovered_coords)
		queue_redraw()

func handle_click(local_mouse_pos: Vector2) -> void:
	var clicked := screen_to_grid(local_mouse_pos)
	if is_valid_coords(clicked):
		tile_clicked.emit(clicked)

func _on_terrain_draw() -> void:
	if _terrain_mesh != null:
		_terrain_mesh.replay(_terrain_canvas)

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)

	# Dynamic overlay on the active tiles only, in isometric back-to-front order (x + y ascending),
	# skipping tiles outside the view.
	if _base_dirty:
		_rebuild_base()
	if _overlay_dirty:
		_rebuild_extras()
	_view_xform = get_global_transform_with_canvas()
	_view_size = get_viewport_rect().size
	_lod = _view_xform.get_scale().x < LOD_SCALE
	_anim_visible = false
	var view: Rect2 = (_view_xform.affine_inverse() * get_viewport_rect()).grow(maxf(TILE_W, TILE_H * 2.0))
	var inset_poly: PackedVector2Array = _inset_diamond(4.0, false)
	var inset_loop: PackedVector2Array = _inset_diamond(4.0, true)
	_sel_loop = _inset_diamond(3.0, true)
	_hov_loop = _inset_diamond(2.0, true)
	var ei: int = 0
	var band: Vector2i = _visible_base_range(view)
	for i in range(band.x, band.y):
		var k: int = _base_keys[i]
		while ei < _extra_keys.size() and _extra_keys[ei] < k:
			_draw_overlay_at(_decode_key(_extra_keys[ei]), view, pulse, inset_poly, inset_loop)
			ei += 1
		_draw_overlay_at(_base_coords[i], view, pulse, inset_poly, inset_loop)
	while ei < _extra_keys.size():
		_draw_overlay_at(_decode_key(_extra_keys[ei]), view, pulse, inset_poly, inset_loop)
		ei += 1

	# Draw movement path preview arrow & fuel waypoints on top
	if _path_dirty:
		_rebuild_path_preview()
	if _path_pts.size() > 1:
		var line_col := Color(1.0, 0.32, 0.2, 0.95) if _path_is_atk else Color(0.95, 0.78, 0.28, 0.95)
		draw_polyline(_path_pts, Color(0.05, 0.05, 0.05, 0.85), 6.0)
		draw_polyline(_path_pts, line_col, 3.2)
		for i in range(1, _path_pts.size()):
			draw_circle(_path_pts[i], 4.5, line_col)
		# Fuel cost tag at destination
		var tag_w: float = float(PixelFont.text_width(_path_tag)) + 12.0
		var tag_h: float = 14.0
		var dest_pos: Vector2 = _path_pts[-1] + Vector2(-roundf(tag_w * 0.5), -32.0)
		var tag_rect := Rect2(dest_pos, Vector2(tag_w, tag_h))
		draw_rect(tag_rect, CrtUI.C_FILL, true)
		draw_rect(tag_rect, line_col, false, 1.2)
		PixelFont.draw_text(self, _path_tag, (dest_pos + Vector2(6, 3)).round(), line_col)

## Index range [lo, hi) of _base_keys whose tiles can lie inside `view` (local coordinates). Keys sort
## by x + y, and a tile's top-centre y is (x + y) * TILE_H / 2 minus its elevation lift, so a
## vertical window of the view is a contiguous key range found by two binary searches. Conservative:
## the per-tile has_point test in _draw_overlay_at stays the exact filter.
func _visible_base_range(view: Rect2) -> Vector2i:
	var hh: float = TILE_H * 0.5
	var s_lo: int = maxi(0, int(floor(view.position.y / hh)))
	var s_hi: int = int(ceil((view.end.y + float(GridTileData.MAX_ELEVATION) * ELEV_STEP) / hh))
	if s_hi < s_lo:
		return Vector2i.ZERO
	var lo: int = _base_keys.bsearch(s_lo * grid_width)
	var hi: int = _base_keys.bsearch((s_hi + 1) * grid_width)
	return Vector2i(lo, maxi(lo, hi))

func _decode_key(k: int) -> Vector2i:
	var x: int = k % grid_width
	return Vector2i(x, k / grid_width - x)

## Sorted ambient + reachable tiles (the part of the overlay that does not change on hover).
func _rebuild_base() -> void:
	_base_dirty = false
	var keys := _ambient_keys.duplicate()
	for c: Vector2i in reachable_info.keys():
		if tiles.has(c):
			keys.append(_iso_key(c))
	keys.sort()
	_base_keys = PackedInt32Array()
	_base_coords.clear()
	var last: int = -1
	for k in keys:
		if k == last:
			continue
		last = k
		_base_keys.append(k)
		_base_coords.append(_decode_key(k))

## The selected / hovered tiles missing from the base list: at most two keys, merged while drawing.
func _rebuild_extras() -> void:
	_overlay_dirty = false
	_extra_keys.clear()
	for c in [selected_coords, hovered_coords]:
		if not tiles.has(c):
			continue
		var k: int = _iso_key(c)
		var at: int = _base_keys.bsearch(k)
		if (at < _base_keys.size() and _base_keys[at] == k) or _extra_keys.has(k):
			continue
		_extra_keys.append(k)
	_extra_keys.sort()

func _rebuild_path_preview() -> void:
	_path_dirty = false
	_path_pts = PackedVector2Array()
	_path_tag = ""
	if current_path_preview.size() <= 1:
		return
	for p in current_path_preview:
		_path_pts.append(grid_to_screen(p, true))
	var dest: Dictionary = reachable_info.get(current_path_preview[-1], {})
	_path_is_atk = dest.get("is_attack", false)
	var spent: int = dest.get("fuel_spent", 0)
	_path_tag = CrtUI.sanitize("ENGAGE (-%dF)" % spent if _path_is_atk else "-%d FUEL" % spent)

func _draw_static_tile(ci: CanvasMeshBuilder, coords: Vector2i, td: GridTileData) -> void:
	# Geometry is only needed while baking, so it is built here rather than kept per tile.
	var top_center: Vector2 = _tile_top[coords]
	var base_center := grid_to_screen(coords, false)
	var total_drop: float = BASE_THICKNESS - (top_center.y - base_center.y)
	var diamond := get_diamond_points(top_center, 0.0)
	var p_top := diamond[0]
	var p_right := diamond[1]
	var p_bottom := diamond[2]
	var p_left := diamond[3]
	var drop := Vector2(0, total_drop)
	var left_face := PackedVector2Array([p_left, p_bottom, p_bottom + drop, p_left + drop])
	var right_face := PackedVector2Array([p_bottom, p_right, p_right + drop, p_bottom + drop])
	var outline := PackedVector2Array([p_left, p_left + drop, p_bottom + drop, p_right + drop, p_right])
	var grid_outline := PackedVector2Array([p_top, p_right, p_bottom, p_left, p_top])

	var top_color := TerrainDefs.top_color(td.terrain_type, td.elevation)
	var left_wall_color := top_color.darkened(0.34)
	var right_wall_color := top_color.darkened(0.48)

	# 1. Left & Right 3D Extruded Cliff Faces
	ci.draw_colored_polygon(left_face, left_wall_color)
	ci.draw_colored_polygon(right_face, right_wall_color)

	# Stratified elevation contour lines on cliff sides
	for e_lvl in range(1, td.elevation + 1):
		var dy: float = float(e_lvl) * ELEV_STEP
		ci.draw_line(p_left + Vector2(0, dy), p_bottom + Vector2(0, dy), Color(0.12, 0.14, 0.11, 0.55), 1.2)
		ci.draw_line(p_bottom + Vector2(0, dy), p_right + Vector2(0, dy), Color(0.08, 0.10, 0.08, 0.65), 1.2)

	ci.draw_polyline(outline, Color(0.1, 0.11, 0.09, 0.8), 1.2)

	# 2. Top Diamond Surface
	ci.draw_colored_polygon(diamond, top_color)

	# 3. Procedural Static Terrain Surface Details
	_draw_static_terrain_details(ci, top_center, td)

	# 4. Grid Bevel Outline
	var border_col := Color(0.16, 0.19, 0.15, 0.65)
	ci.draw_polyline(grid_outline, border_col, 1.3)

	# 5. Static Elevation Labels
	if show_elev_labels and td.elevation >= 2 and not td.is_objective:
		var elev_str := "%dm" % (td.elevation * 100)
		var ew: int = PixelFont.text_width(elev_str)
		ci.add_text(elev_str, (top_center + Vector2(-roundf(float(ew) * 0.5), 18)).round(), Color(0.85, 0.86, 0.78, 0.65))

func _draw_overlay_at(coords: Vector2i, view: Rect2, pulse: float, inner_poly: PackedVector2Array, inner_loop: PackedVector2Array) -> void:
	var top_center: Vector2 = _tile_top[coords]
	if not view.has_point(top_center):
		return
	_draw_dynamic_tile(coords, tiles[coords], top_center, pulse, inner_poly, inner_loop)

func _draw_dynamic_tile(coords: Vector2i, td: GridTileData, top_center: Vector2, pulse: float, inner_poly: PackedVector2Array, inner_loop: PackedVector2Array) -> void:
	# River animated ripples & city pulsating bunker slits
	if _lod:
		# Zoomed out: one static tint command per river / city tile.
		if td.terrain_type == GridTileData.TerrainType.RIVER:
			draw_rect(Rect2(top_center + Vector2(-18, -5), Vector2(36, 10)), Color(0.38, 0.65, 0.72, 0.35), true)
		elif td.terrain_type == GridTileData.TerrainType.CITY:
			draw_rect(Rect2(top_center + Vector2(-13, -10), Vector2(23, 5)), Color(0.95, 0.72, 0.22, 0.6), true)
	elif td.terrain_type == GridTileData.TerrainType.RIVER:
		_anim_visible = true
		var wave_offset: float = sin(_anim_time * 2.5 + float(td.coords.x + td.coords.y)) * 4.0
		draw_line(top_center + Vector2(-18 + wave_offset, -4), top_center + Vector2(6 + wave_offset, -4), Color(0.38, 0.65, 0.72, 0.55), 2.0)
		draw_line(top_center + Vector2(-8 - wave_offset, 5), top_center + Vector2(18 - wave_offset, 5), Color(0.38, 0.65, 0.72, 0.55), 2.0)
	elif td.terrain_type == GridTileData.TerrainType.CITY:
		_anim_visible = true
		var win_col := Color(0.95, 0.72, 0.22, 0.7 + 0.3 * pulse)
		draw_rect(Rect2(top_center + Vector2(-13, -10), Vector2(4, 2)), win_col, true)
		draw_rect(Rect2(top_center + Vector2(-6, -10), Vector2(4, 2)), win_col, true)
		draw_rect(Rect2(top_center + Vector2(5, -7), Vector2(5, 2)), win_col, true)

	# Reachable Fuel / Attack Target Highlights
	var info: Variant = reachable_info.get(coords) if coords != selected_coords else null
	if info != null:
		_anim_visible = true
		draw_set_transform(top_center)
		if info["is_attack"]:
			var atk_fill := Color(0.95, 0.22, 0.15, 0.28 + 0.18 * pulse)
			var atk_edge := Color(1.0, 0.38, 0.22, 0.95)
			draw_colored_polygon(inner_poly, atk_fill)
			draw_polyline(inner_loop, atk_edge, 2.6)
		else:
			var mov_fill := Color(0.25, 0.78, 0.58, 0.18 + 0.08 * pulse)
			var mov_edge := Color(0.42, 0.95, 0.72, 0.78)
			draw_colored_polygon(inner_poly, mov_fill)
			draw_polyline(inner_loop, mov_edge, 1.8)
		draw_set_transform(Vector2.ZERO)

	# Selected Unit Tile Highlight
	if coords == selected_coords:
		draw_set_transform(top_center)
		draw_polyline(_sel_loop, Color(1.0, 0.84, 0.32, 0.95), 2.8)
		draw_set_transform(Vector2.ZERO)

	# Hovered Tile Cursor Outline
	if coords == hovered_coords:
		draw_set_transform(top_center)
		draw_polyline(_hov_loop, Color(1.0, 0.95, 0.75, 0.95), 2.5)
		draw_set_transform(Vector2.ZERO)

	# Objective Badges
	if td.is_objective:
		var flag_col := Color(0.35, 0.85, 0.45) if td.controlled_by == 0 else (Color(0.95, 0.3, 0.25) if td.controlled_by == 1 else Color(0.85, 0.8, 0.5))
		draw_circle(top_center + Vector2(0, -18), 5.5, Color(0.1, 0.1, 0.1, 0.9))
		draw_circle(top_center + Vector2(0, -18), 4.0, flag_col)

## Inset top diamond centred on the origin; `closed` repeats the first vertex for an outline.
func _inset_diamond(inset: float, closed: bool) -> PackedVector2Array:
	var key: float = inset + (100.0 if closed else 0.0)
	if not _inset_cache.has(key):
		var pts := get_diamond_points(Vector2.ZERO, inset)
		if closed:
			pts.append(pts[0])
		_inset_cache[key] = pts
	return _inset_cache[key]

func _draw_static_terrain_details(ci: CanvasMeshBuilder, center: Vector2, td: GridTileData) -> void:
	match td.terrain_type:
		GridTileData.TerrainType.RIVER:
			pass # ripples drawn in dynamic pass
		GridTileData.TerrainType.ROAD:
			# Industrial transit roadbed & yellow convoy center-stripes
			var road_strip := PackedVector2Array([
				center + Vector2(-28, -14),
				center + Vector2(-18, -19),
				center + Vector2(28, 4),
				center + Vector2(18, 9)
			])
			ci.draw_colored_polygon(road_strip, Color(0.25, 0.25, 0.23))
			ci.draw_line(center + Vector2(-16, -10), center + Vector2(-4, -4), Color(0.85, 0.68, 0.24, 0.8), 2.0)
			ci.draw_line(center + Vector2(4, 0), center + Vector2(16, 6), Color(0.85, 0.68, 0.24, 0.8), 2.0)
		GridTileData.TerrainType.FOREST:
			# Trench revetment & stylized dark pines
			ci.draw_line(center + Vector2(-14, 4), center + Vector2(10, -6), Color(0.28, 0.22, 0.15), 3.0)
			var tree_offsets := [Vector2(-12, -4), Vector2(10, -2), Vector2(-2, 6)]
			for to in tree_offsets:
				var tp: Vector2 = center + to
				var foliage := PackedVector2Array([tp + Vector2(0, -13), tp + Vector2(7, 1), tp + Vector2(-7, 1)])
				ci.draw_colored_polygon(foliage, Color(0.14, 0.24, 0.13))
				ci.draw_polyline(PackedVector2Array([foliage[0], foliage[1], foliage[2], foliage[0]]), Color(0.28, 0.40, 0.24), 1.0)
		GridTileData.TerrainType.CITY:
			# Isometric ferro-concrete bunkers & industrial structures
			var b1 := Rect2(center + Vector2(-16, -14), Vector2(14, 12))
			var b2 := Rect2(center + Vector2(2, -10), Vector2(13, 10))
			ci.draw_rect(b1, Color(0.28, 0.27, 0.25), true)
			ci.draw_rect(b1, Color(0.58, 0.55, 0.48), false, 1.4)
			ci.draw_rect(b2, Color(0.24, 0.23, 0.22), true)
			ci.draw_rect(b2, Color(0.52, 0.50, 0.44), false, 1.4)
		GridTileData.TerrainType.MOUNTAIN:
			# 3D Craggy peak facets rising from the tile
			var peak := center + Vector2(0, -20)
			var left_slope := PackedVector2Array([peak, center + Vector2(-22, 4), center + Vector2(2, 8)])
			var right_slope := PackedVector2Array([peak, center + Vector2(2, 8), center + Vector2(22, 2)])
			ci.draw_colored_polygon(left_slope, Color(0.52, 0.50, 0.46))
			ci.draw_colored_polygon(right_slope, Color(0.35, 0.34, 0.31))
			# Snow/Ash ridge cap
			var snow := PackedVector2Array([peak, center + Vector2(-8, -10), center + Vector2(1, -8), center + Vector2(8, -11)])
			ci.draw_colored_polygon(snow, Color(0.78, 0.80, 0.76, 0.85))
		GridTileData.TerrainType.PLAIN:
			# Subtle earthen tufts
			ci.draw_line(center + Vector2(-8, -2), center + Vector2(-3, -2), Color(0.24, 0.30, 0.18, 0.6), 1.5)
			ci.draw_line(center + Vector2(6, 4), center + Vector2(12, 4), Color(0.24, 0.30, 0.18, 0.6), 1.5)