class_name IsoGridMap
extends Node2D

## Isometric 2.5D Battlefield Grid Map
## Renders extruded terrain blocks, elevation cliffs, procedural terrain features (rivers, bridges,
## cities, trenches, mountains), fuel movement ranges, and path previews.

signal tile_hovered(coords: Vector2i, tile: GridTileData)
signal tile_clicked(coords: Vector2i, tile: GridTileData)

const TILE_W: float = 118.0
const TILE_H: float = 59.0
const ELEV_STEP: float = 12.0
const BASE_THICKNESS: float = 20.0

var grid_width: int = 10
var grid_height: int = 8
var tiles: Dictionary = {} # Vector2i -> GridTileData

var hovered_coords: Vector2i = Vector2i(-1, -1)
var selected_coords: Vector2i = Vector2i(-1, -1)

# Dijkstra output: Vector2i -> { "fuel_spent": int, "fuel_left": int, "path": Array[Vector2i], "is_attack": bool }
var reachable_info: Dictionary = {}
var current_path_preview: Array[Vector2i] = []

var _anim_time: float = 0.0
var show_elev_labels: bool = true

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()

func load_from_definition(map_def: MapDefinition) -> void:
	grid_width = map_def.width
	grid_height = map_def.height
	tiles.clear()
	reachable_info.clear()
	current_path_preview = []
	hovered_coords = Vector2i(-1, -1)
	selected_coords = Vector2i(-1, -1)

	for y in range(grid_height):
		var t_row: PackedStringArray = map_def.terrain_codes[y].split(" ", false)
		var e_row: PackedStringArray = map_def.elevation_rows[y].split(" ", false)
		for x in range(grid_width):
			var code: String = t_row[x] if x < t_row.size() else "P"
			var elev: int = int(e_row[x]) if x < e_row.size() else 1
			var t_type := _parse_terrain_code(code)
			var c := Vector2i(x, y)
			tiles[c] = GridTileData.new(c, t_type, elev, false, "")

	for obj in map_def.objectives:
		var pos: Vector2i = obj["pos"]
		if tiles.has(pos):
			var td: GridTileData = tiles[pos]
			td.is_objective = true
			td.objective_label = str(obj.get("label", "Objective"))
			td.controlled_by = int(obj.get("owner", -1))

	queue_redraw()

func _parse_terrain_code(code: String) -> GridTileData.TerrainType:
	match code.to_upper():
		"D", "R_D":
			return GridTileData.TerrainType.ROAD
		"R":
			return GridTileData.TerrainType.RIVER
		"F":
			return GridTileData.TerrainType.FOREST
		"C":
			return GridTileData.TerrainType.CITY
		"M":
			return GridTileData.TerrainType.MOUNTAIN
		_:
			return GridTileData.TerrainType.PLAIN

func is_valid_coords(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < grid_width and coords.y >= 0 and coords.y < grid_height

func get_tile(coords: Vector2i) -> GridTileData:
	return tiles.get(coords, null)

func get_tile_elevation(coords: Vector2i) -> int:
	var td: GridTileData = tiles.get(coords, null)
	return td.elevation if td != null else 0

## Converts grid coordinates (x, y) into local 2D screen position (center of the tile's top diamond).
func grid_to_screen(coords: Vector2i, include_elevation: bool = true) -> Vector2:
	var sx: float = float(coords.x - coords.y) * (TILE_W * 0.5)
	var sy: float = float(coords.x + coords.y) * (TILE_H * 0.5)
	if include_elevation:
		sy -= float(get_tile_elevation(coords)) * ELEV_STEP
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
	# Iterate from front-most depth to back-most so elevated foreground tiles take priority
	var max_sum: int = (grid_width - 1) + (grid_height - 1)
	for s in range(max_sum, -1, -1):
		for x in range(grid_width):
			var y: int = s - x
			if y < 0 or y >= grid_height:
				continue
			var c := Vector2i(x, y)
			var center := grid_to_screen(c, true)
			var poly := get_diamond_points(center, 0.0)
			if Geometry2D.is_point_in_polygon(local_pos, poly):
				return c
	return Vector2i(-1, -1)

## Computes all reachable tiles for `unit` given `occupied_units` (Dictionary: Vector2i -> MechData).
## Allows moving onto an enemy node to trigger a Collision / Skirmish!
func compute_reachable_tiles(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	reachable_info.clear()
	current_path_preview = []
	if unit == null or unit.has_moved:
		queue_redraw()
		return reachable_info

	var start: Vector2i = unit.grid_pos
	var max_budget: int = unit.current_fuel

	var best_cost: Dictionary = { start: 0 }
	var came_from: Dictionary = { start: start }
	var queue: Array[Vector2i] = [start]

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	while not queue.is_empty():
		# Pop lowest fuel cost node (Dijkstra)
		var best_idx: int = 0
		var best_val: int = best_cost[queue[0]]
		for i in range(1, queue.size()):
			var c_val: int = best_cost[queue[i]]
			if c_val < best_val:
				best_val = c_val
				best_idx = i
		var current: Vector2i = queue[best_idx]
		queue.remove_at(best_idx)

		var cur_cost: int = best_cost[current]
		var cur_tile: GridTileData = get_tile(current)

		# Do not expand THROUGH an enemy unit (entering an enemy node triggers immediate collision)
		if current != start and occupied_units.has(current):
			var occ_unit: MechData = occupied_units[current]
			if occ_unit.faction != unit.faction:
				continue

		for d in dirs:
			var next_pos: Vector2i = current + d
			if not is_valid_coords(next_pos):
				continue
			# Cannot launch an engagement onto an enemy node from a tile occupied by another friendly unit
			if occupied_units.has(next_pos) and occupied_units[next_pos].faction != unit.faction:
				if current != start and occupied_units.has(current):
					continue
			var next_tile: GridTileData = get_tile(next_pos)
			var step_fuel: int = unit.get_step_fuel_cost(cur_tile, next_tile)
			var new_cost: int = cur_cost + step_fuel
			if new_cost > max_budget:
				continue

			if not best_cost.has(next_pos) or new_cost < best_cost[next_pos]:
				best_cost[next_pos] = new_cost
				came_from[next_pos] = current
				if not queue.has(next_pos):
					queue.append(next_pos)

	# Build reachable_info dictionary (excluding tiles occupied by OTHER friendly units)
	for pos_key in best_cost.keys():
		var pos: Vector2i = pos_key
		var is_enemy_target := false
		if occupied_units.has(pos) and pos != start:
			var occ: MechData = occupied_units[pos]
			if occ.faction == unit.faction:
				continue # Cannot end move on another friendly mech
			else:
				is_enemy_target = true

		# Reconstruct path
		var path: Array[Vector2i] = []
		var curr: Vector2i = pos
		while curr != start:
			path.push_front(curr)
			curr = came_from[curr]
		path.push_front(start)

		var spent: int = best_cost[pos]
		reachable_info[pos] = {
			"fuel_spent": spent,
			"fuel_left": max_budget - spent,
			"path": path,
			"is_attack": is_enemy_target
		}

	queue_redraw()
	return reachable_info

func clear_highlights() -> void:
	reachable_info.clear()
	current_path_preview = []
	selected_coords = Vector2i(-1, -1)
	queue_redraw()

func update_hover(local_mouse_pos: Vector2) -> void:
	var new_hover := screen_to_grid(local_mouse_pos)
	if new_hover != hovered_coords:
		hovered_coords = new_hover
		if reachable_info.has(hovered_coords):
			# Copy: the stored path is the same array a click hands to the movement animation
			current_path_preview = reachable_info[hovered_coords]["path"].duplicate()
		else:
			current_path_preview = []
		tile_hovered.emit(hovered_coords, get_tile(hovered_coords))
		queue_redraw()

func handle_click(local_mouse_pos: Vector2) -> void:
	var clicked := screen_to_grid(local_mouse_pos)
	if is_valid_coords(clicked):
		tile_clicked.emit(clicked, get_tile(clicked))

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)

	# Render tiles in isometric back-to-front order (x + y ascending)
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
			_draw_single_tile(coords, td, font, pulse)

	# Draw movement path preview arrow & fuel waypoints on top
	if current_path_preview.size() > 1:
		var pts := PackedVector2Array()
		for p in current_path_preview:
			pts.append(grid_to_screen(p, true))
		var is_atk: bool = reachable_info.get(current_path_preview[-1], {}).get("is_attack", false)
		var line_col := Color(1.0, 0.32, 0.2, 0.95) if is_atk else Color(0.95, 0.78, 0.28, 0.95)
		draw_polyline(pts, Color(0.05, 0.05, 0.05, 0.85), 6.0)
		draw_polyline(pts, line_col, 3.2)
		for i in range(1, pts.size()):
			draw_circle(pts[i], 4.5, line_col)
		# Fuel cost tag at destination
		var dest_pos: Vector2 = pts[-1] + Vector2(-28, -28)
		var spent: int = reachable_info.get(current_path_preview[-1], {}).get("fuel_spent", 0)
		var tag_str: String = "ENGAGE (-%dF)" % spent if is_atk else "-%d FUEL" % spent
		draw_rect(Rect2(dest_pos - Vector2(4, 14), Vector2(84, 18)), Color(0.08, 0.09, 0.08, 0.92), true)
		draw_rect(Rect2(dest_pos - Vector2(4, 14), Vector2(84, 18)), line_col, false, 1.5)
		draw_string(font, dest_pos, tag_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, line_col)

func _draw_single_tile(coords: Vector2i, td: GridTileData, font: Font, pulse: float) -> void:
	var top_center := grid_to_screen(coords, true)
	var base_center := grid_to_screen(coords, false)
	var extrude_h: float = (top_center.y - base_center.y) # Negative or 0
	var total_drop: float = BASE_THICKNESS - extrude_h

	var diamond := get_diamond_points(top_center, 0.0)
	var p_top := diamond[0]
	var p_right := diamond[1]
	var p_bottom := diamond[2]
	var p_left := diamond[3]

	var top_color := _get_terrain_top_color(td.terrain_type, td.elevation)
	var left_wall_color := top_color.darkened(0.34)
	var right_wall_color := top_color.darkened(0.48)

	# 1. Left & Right 3D Extruded Cliff Faces
	var left_face := PackedVector2Array([
		p_left,
		p_bottom,
		p_bottom + Vector2(0, total_drop),
		p_left + Vector2(0, total_drop)
	])
	var right_face := PackedVector2Array([
		p_bottom,
		p_right,
		p_right + Vector2(0, total_drop),
		p_bottom + Vector2(0, total_drop)
	])
	draw_colored_polygon(left_face, left_wall_color)
	draw_colored_polygon(right_face, right_wall_color)

	# Stratified elevation contour lines on cliff sides
	for e_lvl in range(1, td.elevation + 1):
		var dy: float = float(e_lvl) * ELEV_STEP
		draw_line(p_left + Vector2(0, dy), p_bottom + Vector2(0, dy), Color(0.12, 0.14, 0.11, 0.55), 1.2)
		draw_line(p_bottom + Vector2(0, dy), p_right + Vector2(0, dy), Color(0.08, 0.10, 0.08, 0.65), 1.2)

	draw_polyline(PackedVector2Array([p_left, p_left + Vector2(0, total_drop), p_bottom + Vector2(0, total_drop), p_right + Vector2(0, total_drop), p_right]), Color(0.1, 0.11, 0.09, 0.8), 1.2)

	# 2. Top Diamond Surface
	draw_colored_polygon(diamond, top_color)

	# 3. Procedural Terrain Surface Details
	_draw_terrain_details(top_center, td, pulse)

	# 4. Grid Bevel Outline
	var border_col := Color(0.16, 0.19, 0.15, 0.65)
	draw_polyline(PackedVector2Array([p_top, p_right, p_bottom, p_left, p_top]), border_col, 1.3)

	# 5. Reachable Fuel / Attack Target Highlights
	if reachable_info.has(coords) and coords != selected_coords:
		var info: Dictionary = reachable_info[coords]
		var inner_poly := get_diamond_points(top_center, 4.0)
		var inner_loop := PackedVector2Array([inner_poly[0], inner_poly[1], inner_poly[2], inner_poly[3], inner_poly[0]])
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

	# 6. Selected Unit Tile Highlight
	if coords == selected_coords:
		var sel_poly := get_diamond_points(top_center, 3.0)
		var sel_loop := PackedVector2Array([sel_poly[0], sel_poly[1], sel_poly[2], sel_poly[3], sel_poly[0]])
		draw_polyline(sel_loop, Color(1.0, 0.84, 0.32, 0.95), 2.8)

	# 7. Hovered Tile Cursor Outline
	if coords == hovered_coords:
		var hov_poly := get_diamond_points(top_center, 2.0)
		var hov_loop := PackedVector2Array([hov_poly[0], hov_poly[1], hov_poly[2], hov_poly[3], hov_poly[0]])
		draw_polyline(hov_loop, Color(1.0, 0.95, 0.75, 0.95), 2.5)

	# 8. Subtle Elevation & Objective Badges
	if td.is_objective:
		var flag_col := Color(0.35, 0.85, 0.45) if td.controlled_by == 0 else (Color(0.95, 0.3, 0.25) if td.controlled_by == 1 else Color(0.85, 0.8, 0.5))
		draw_circle(top_center + Vector2(0, -18), 5.5, Color(0.1, 0.1, 0.1, 0.9))
		draw_circle(top_center + Vector2(0, -18), 4.0, flag_col)
	elif show_elev_labels and td.elevation >= 2:
		draw_string(font, top_center + Vector2(-8, 22), "%dm" % (td.elevation * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 0.86, 0.78, 0.55))

func _get_terrain_top_color(t_type: GridTileData.TerrainType, elev: int) -> Color:
	var elev_tint: float = float(elev - 1) * 0.045
	match t_type:
		GridTileData.TerrainType.PLAIN:
			return Color(0.31 + elev_tint, 0.37 + elev_tint, 0.24 + elev_tint)
		GridTileData.TerrainType.ROAD:
			return Color(0.36 + elev_tint, 0.35 + elev_tint, 0.32 + elev_tint)
		GridTileData.TerrainType.RIVER:
			return Color(0.16, 0.33, 0.38)
		GridTileData.TerrainType.FOREST:
			return Color(0.22 + elev_tint, 0.30 + elev_tint, 0.19 + elev_tint)
		GridTileData.TerrainType.CITY:
			return Color(0.42 + elev_tint, 0.40 + elev_tint, 0.36 + elev_tint)
		GridTileData.TerrainType.MOUNTAIN:
			return Color(0.45 + elev_tint, 0.43 + elev_tint, 0.39 + elev_tint)
	return Color(0.3, 0.35, 0.25)

func _draw_terrain_details(center: Vector2, td: GridTileData, pulse: float) -> void:
	match td.terrain_type:
		GridTileData.TerrainType.RIVER:
			# Animated water ripples
			var wave_offset: float = sin(_anim_time * 2.5 + float(td.coords.x + td.coords.y)) * 4.0
			draw_line(center + Vector2(-18 + wave_offset, -4), center + Vector2(6 + wave_offset, -4), Color(0.38, 0.65, 0.72, 0.55), 2.0)
			draw_line(center + Vector2(-8 - wave_offset, 5), center + Vector2(18 - wave_offset, 5), Color(0.38, 0.65, 0.72, 0.55), 2.0)
		GridTileData.TerrainType.ROAD:
			# Industrial transit roadbed & yellow convoy center-stripes
			var road_strip := PackedVector2Array([
				center + Vector2(-28, -14),
				center + Vector2(-18, -19),
				center + Vector2(28, 4),
				center + Vector2(18, 9)
			])
			draw_colored_polygon(road_strip, Color(0.25, 0.25, 0.23))
			draw_line(center + Vector2(-16, -10), center + Vector2(-4, -4), Color(0.85, 0.68, 0.24, 0.8), 2.0)
			draw_line(center + Vector2(4, 0), center + Vector2(16, 6), Color(0.85, 0.68, 0.24, 0.8), 2.0)
		GridTileData.TerrainType.FOREST:
			# Trench revetment & stylized dark pines
			draw_line(center + Vector2(-14, 4), center + Vector2(10, -6), Color(0.28, 0.22, 0.15), 3.0)
			var tree_offsets := [Vector2(-12, -4), Vector2(10, -2), Vector2(-2, 6)]
			for to in tree_offsets:
				var tp: Vector2 = center + to
				var foliage := PackedVector2Array([tp + Vector2(0, -13), tp + Vector2(7, 1), tp + Vector2(-7, 1)])
				draw_colored_polygon(foliage, Color(0.14, 0.24, 0.13))
				draw_polyline(PackedVector2Array([foliage[0], foliage[1], foliage[2], foliage[0]]), Color(0.28, 0.40, 0.24), 1.0)
		GridTileData.TerrainType.CITY:
			# Isometric ferro-concrete bunkers & industrial structures
			var b1 := Rect2(center + Vector2(-16, -14), Vector2(14, 12))
			var b2 := Rect2(center + Vector2(2, -10), Vector2(13, 10))
			draw_rect(b1, Color(0.28, 0.27, 0.25), true)
			draw_rect(b1, Color(0.58, 0.55, 0.48), false, 1.4)
			draw_rect(b2, Color(0.24, 0.23, 0.22), true)
			draw_rect(b2, Color(0.52, 0.50, 0.44), false, 1.4)
			# Glowing bunker slits
			var win_col := Color(0.95, 0.72, 0.22, 0.7 + 0.3 * pulse)
			draw_rect(Rect2(center + Vector2(-13, -10), Vector2(4, 2)), win_col, true)
			draw_rect(Rect2(center + Vector2(-6, -10), Vector2(4, 2)), win_col, true)
			draw_rect(Rect2(center + Vector2(5, -7), Vector2(5, 2)), win_col, true)
		GridTileData.TerrainType.MOUNTAIN:
			# 3D Craggy peak facets rising from the tile
			var peak := center + Vector2(0, -20)
			var left_slope := PackedVector2Array([peak, center + Vector2(-22, 4), center + Vector2(2, 8)])
			var right_slope := PackedVector2Array([peak, center + Vector2(2, 8), center + Vector2(22, 2)])
			draw_colored_polygon(left_slope, Color(0.52, 0.50, 0.46))
			draw_colored_polygon(right_slope, Color(0.35, 0.34, 0.31))
			# Snow/Ash ridge cap
			var snow := PackedVector2Array([peak, center + Vector2(-8, -10), center + Vector2(1, -8), center + Vector2(8, -11)])
			draw_colored_polygon(snow, Color(0.78, 0.80, 0.76, 0.85))
		GridTileData.TerrainType.PLAIN:
			# Subtle earthen tufts
			draw_line(center + Vector2(-8, -2), center + Vector2(-3, -2), Color(0.24, 0.30, 0.18, 0.6), 1.5)
			draw_line(center + Vector2(6, 4), center + Vector2(12, 4), Color(0.24, 0.30, 0.18, 0.6), 1.5)
