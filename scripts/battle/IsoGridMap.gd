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
# Every tile the dynamic overlay draws this frame, decoded in iso back-to-front order. Rebuilt only
# when the hover, selection or reachable set changes, so a frame walks the active tiles, not the map.
var _overlay_coords: Array[Vector2i] = []
var _overlay_dirty: bool = true
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
	if _since_redraw < 1.0 / AMBIENT_FPS:
		return
	if not reachable_info.is_empty() or not current_path_preview.is_empty() or hovered_coords != Vector2i(-1, -1) or selected_coords != Vector2i(-1, -1):
		_since_redraw = 0.0
		queue_redraw()

func load_from_definition(map_def: MapDefinition) -> void:
	grid_width = map_def.width
	grid_height = map_def.height
	tiles.clear()
	reachable_info = {}
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

	_tile_top.clear()
	for c: Vector2i in tiles.keys():
		_tile_top[c] = grid_to_screen(c, true)

	_ambient_keys = PackedInt32Array()
	for c: Vector2i in tiles.keys():
		var td: GridTileData = tiles[c]
		if td.is_objective or td.terrain_type == GridTileData.TerrainType.RIVER or td.terrain_type == GridTileData.TerrainType.CITY:
			_ambient_keys.append(_iso_key(c))
	_ambient_keys.sort()
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
	var hw: float = TILE_W * 0.5
	var hh: float = TILE_H * 0.5
	var u: float = local_pos.x / hw
	var best_c := Vector2i(-1, -1)
	var best_depth: int = -1

	# Check elevations 0..4 (max supported elevation is 400m = level 4)
	for elev in range(0, 5):
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
	var reachable := {}
	if unit == null or unit.is_order_complete():
		return reachable

	var start: Vector2i = unit.grid_pos
	var max_budget: int = unit.current_fuel

	if not unit.has_moved:
		var search: Array = _shortest_costs(unit, occupied_units, max_budget)
		var best_cost: Dictionary = search[0]
		var came_from: Dictionary = search[1]

		# Build reachable dictionary for unoccupied tiles only
		for pos_key in best_cost.keys():
			var pos: Vector2i = pos_key
			if pos != start and occupied_units.has(pos):
				continue # Cannot end move on any occupied tile (friendly or enemy)

			# Reconstruct path in O(N) using append + reverse
			var path: Array[Vector2i] = []
			var curr: Vector2i = pos
			while curr != start:
				path.append(curr)
				curr = came_from[curr]
			path.append(start)
			path.reverse()

			var spent: int = best_cost[pos]
			reachable[pos] = {
				"fuel_spent": spent,
				"fuel_left": max_budget - spent,
				"path": path,
				"is_attack": false
			}

	if not unit.has_attacked:
		var start_tile: GridTileData = get_tile(start)
		for d in _DIRS:
			var adj: Vector2i = start + d
			if not is_valid_coords(adj):
				continue
			if occupied_units.has(adj):
				var occ: MechData = occupied_units[adj]
				if occ.faction != unit.faction:
					var strike_fuel: int = unit.get_step_fuel_cost(start_tile, get_tile(adj))
					if strike_fuel <= max_budget:
						var atk_path: Array[Vector2i] = [start, adj]
						reachable[adj] = {
							"fuel_spent": strike_fuel,
							"fuel_left": max_budget - strike_fuel,
							"path": atk_path,
							"is_attack": true
						}
	return reachable

## Computes all reachable tiles for `unit` given `occupied_units` (Dictionary: Vector2i -> MechData).
## Movement tiles are unoccupied tiles within fuel budget (when not unit.has_moved).
## Attack tiles are orthogonally adjacent enemy tiles within step fuel budget (when not unit.has_attacked).
func compute_reachable_tiles(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	current_path_preview = []
	reachable_info = find_reachable_tiles(unit, occupied_units)
	queue_redraw()
	return reachable_info

const _NO_FUEL_CAP: int = 1 << 30
const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Dijkstra over fuel cost from unit.grid_pos, shared by movement ranges and strike plans so both
## always agree. Returns [best_cost, came_from] (Vector2i -> int / Vector2i). Rules: never step onto
## an enemy node, and drop any step whose running cost would exceed `budget`.
## `settle`, when given, stops the search once every listed node has been popped (its cost is final).
func _shortest_costs(unit: MechData, occupied_units: Dictionary, budget: int, settle: Array[Vector2i] = []) -> Array:
	var start: Vector2i = unit.grid_pos
	var best_cost: Dictionary = { start: 0 }
	var came_from: Dictionary = { start: start }
	var pending: Dictionary = {}
	for p in settle:
		pending[p] = true

	# Binary min-heap of (cost, discovery order) packed into one int; a node pushed again after a
	# cheaper path was found leaves a stale entry behind that is skipped when popped. Ties pop in
	# discovery order, so paths (and the facing they produce) stay deterministic.
	var heap: Array[int] = []
	var heap_pos: Array[Vector2i] = []
	var seq_of: Dictionary = { start: 0 }   # Vector2i -> discovery order
	var closed: Dictionary = {}
	_heap_push(heap, heap_pos, 0, start)

	while not heap.is_empty():
		var top: int = heap[0]
		var current: Vector2i = heap_pos[0]
		_heap_pop(heap, heap_pos)
		if closed.has(current) or (top >> _SEQ_BITS) != best_cost[current]:
			continue # stale entry
		closed[current] = true
		if not pending.is_empty():
			pending.erase(current)
			if pending.is_empty():
				break

		var cur_cost: int = best_cost[current]
		var cur_tile: GridTileData = get_tile(current)

		for d in _DIRS:
			var next_pos: Vector2i = current + d
			if not is_valid_coords(next_pos) or closed.has(next_pos):
				continue
			# Never step onto an enemy-occupied tile during movement
			if occupied_units.has(next_pos) and occupied_units[next_pos].faction != unit.faction:
				continue
			var next_tile: GridTileData = get_tile(next_pos)
			var step_fuel: int = unit.get_step_fuel_cost(cur_tile, next_tile)
			var new_cost: int = cur_cost + step_fuel
			if new_cost > budget:
				continue

			if not best_cost.has(next_pos) or new_cost < best_cost[next_pos]:
				best_cost[next_pos] = new_cost
				came_from[next_pos] = current
				if not seq_of.has(next_pos):
					seq_of[next_pos] = seq_of.size()
				_heap_push(heap, heap_pos, (new_cost << _SEQ_BITS) | int(seq_of[next_pos]), next_pos)
	return [best_cost, came_from]

const _SEQ_BITS: int = 24

static func _heap_push(heap: Array[int], heap_pos: Array[Vector2i], key: int, pos: Vector2i) -> void:
	var i: int = heap.size()
	heap.append(key)
	heap_pos.append(pos)
	while i > 0:
		var parent: int = (i - 1) >> 1
		if heap[parent] <= key:
			break
		heap[i] = heap[parent]
		heap_pos[i] = heap_pos[parent]
		i = parent
	heap[i] = key
	heap_pos[i] = pos

static func _heap_pop(heap: Array[int], heap_pos: Array[Vector2i]) -> void:
	var last: int = heap.size() - 1
	var key: int = heap[last]
	var pos: Vector2i = heap_pos[last]
	heap.resize(last)
	heap_pos.resize(last)
	if last == 0:
		return
	var i: int = 0
	while true:
		var child: int = 2 * i + 1
		if child >= last:
			break
		if child + 1 < last and heap[child + 1] < heap[child]:
			child += 1
		if heap[child] >= key:
			break
		heap[i] = heap[child]
		heap_pos[i] = heap_pos[child]
		i = child
	heap[i] = key
	heap_pos[i] = pos

## Explains whether `unit` can strike the enemy at `target` this turn, and if not, why and what to
## do (see StrikePlan). Uses the same search and costs as compute_reachable_tiles, without its fuel
## cap, and never touches reachable_info. The advice replays next turn under the real WAIT and
## upkeep rules, assuming the enemy holds its tile.
func compute_strike_plan(unit: MechData, target: Vector2i, occupied_units: Dictionary) -> StrikePlan:
	var plan := StrikePlan.new()
	plan.have = unit.current_fuel
	var start: Vector2i = unit.grid_pos
	# Only the usable launch tiles' costs matter (the filter below drops the rest): stop as soon as
	# they are all final. An occupied neighbour is never entered, so waiting for it would flood
	# the whole map.
	var neighbours: Array[Vector2i] = []
	for d in _DIRS:
		var l: Vector2i = target + d
		if not is_valid_coords(l) or (unit.has_moved and l != start) or (l != start and occupied_units.has(l)):
			continue
		neighbours.append(l)
	var costs: Dictionary = {}
	if not neighbours.is_empty():
		costs = _shortest_costs(unit, occupied_units, _NO_FUEL_CAP, neighbours)[0]
	var target_tile := get_tile(target)

	# Launch tiles: enemy neighbours the search reached that the attacker may stand on and fire from.
	var launches: Array[Dictionary] = []   # {pos, path, step: breakdown}
	for d in _DIRS:
		var l: Vector2i = target + d
		if unit.has_moved and l != start:
			continue
		if not costs.has(l):
			continue
		if l != start and occupied_units.has(l):
			continue
		launches.append({"pos": l, "path": int(costs[l]), "step": unit.get_step_fuel_breakdown(get_tile(l), target_tile)})
	if launches.is_empty():
		plan.severity = StrikePlan.NO_APPROACH
		return plan

	# Cheapest strike; ties go to the start tile, then to the cheaper final step.
	var best: Dictionary = launches[0]
	for c in launches:
		var c_total: int = c["path"] + int(c["step"]["total"])
		var b_total: int = best["path"] + int(best["step"]["total"])
		if c_total < b_total or (c_total == b_total and (
				(c["pos"] == start and best["pos"] != start) or
				(best["pos"] != start and int(c["step"]["total"]) < int(best["step"]["total"])))):
			best = c
	plan.launch = best["pos"]
	plan.path_fuel = best["path"]
	plan.step = best["step"]
	plan.needs = plan.path_fuel + int(plan.step["total"])

	if plan.needs <= plan.have:
		plan.severity = StrikePlan.REACHABLE
		return plan
	var in_reach: Array[Dictionary] = launches.filter(func(c): return int(c["path"]) <= plan.have)
	if in_reach.is_empty():
		plan.severity = StrikePlan.BEYOND_RANGE
		return plan
	plan.severity = StrikePlan.IN_STRIKING_DISTANCE

	# Advice ladder (the first that holds wins).
	var max_f: int = unit.max_fuel
	var cheapest_step: int = launches.map(func(c): return int(c["step"]["total"])).min()
	var fuel_after_wait: int = unit.next_turn_fuel(plan.have, get_tile(start), true)
	if cheapest_step > max_f:
		plan.advice = StrikePlan.ADV_IMPOSSIBLE
		return plan
	for c in in_reach:
		if c["pos"] == start and fuel_after_wait >= int(c["step"]["total"]):
			plan.advice = StrikePlan.ADV_WAIT_HERE
			return plan
	var best_spare: int = -1
	for c in in_reach:
		if c["pos"] == start:
			continue
		var next_fuel: int = unit.next_turn_fuel(plan.have - int(c["path"]), get_tile(c["pos"]), false)
		var spare: int = next_fuel - int(c["step"]["total"])
		if spare >= 0 and spare > best_spare:
			best_spare = spare
			plan.move_to = c["pos"]
	if best_spare >= 0:
		plan.advice = StrikePlan.ADV_MOVE_TO
		return plan
	if fuel_after_wait >= plan.needs:
		plan.advice = StrikePlan.ADV_WAIT
		return plan
	plan.advice = StrikePlan.ADV_MULTI_TURN
	return plan

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
		tile_hovered.emit(hovered_coords, get_tile(hovered_coords))
		queue_redraw()

func handle_click(local_mouse_pos: Vector2) -> void:
	var clicked := screen_to_grid(local_mouse_pos)
	if is_valid_coords(clicked):
		tile_clicked.emit(clicked, get_tile(clicked))

func _on_terrain_draw() -> void:
	if _terrain_mesh != null:
		_terrain_mesh.replay(_terrain_canvas)

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)

	# Dynamic overlay on the active tiles only, in isometric back-to-front order (x + y ascending)
	if _overlay_dirty:
		_rebuild_overlay_coords()
	for coords in _overlay_coords:
		_draw_dynamic_tile(coords, tiles[coords], pulse)

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

## Merges the ambient tiles with the reachable / selected / hovered tiles into one iso-ordered list.
func _rebuild_overlay_coords() -> void:
	_overlay_dirty = false
	var keys := _ambient_keys.duplicate()
	for c: Vector2i in reachable_info.keys():
		if tiles.has(c):
			keys.append(_iso_key(c))
	for c in [selected_coords, hovered_coords]:
		if tiles.has(c):
			keys.append(_iso_key(c))
	keys.sort()
	_overlay_coords.clear()
	var last: int = -1
	for k in keys:
		if k == last:
			continue
		last = k
		var s: int = k / grid_width
		var x: int = k % grid_width
		_overlay_coords.append(Vector2i(x, s - x))

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

	var top_color := _get_terrain_top_color(td.terrain_type, td.elevation)
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

func _draw_dynamic_tile(coords: Vector2i, td: GridTileData, pulse: float) -> void:
	var top_center: Vector2 = _tile_top[coords]

	# River animated ripples & city pulsating bunker slits
	if td.terrain_type == GridTileData.TerrainType.RIVER:
		var wave_offset: float = sin(_anim_time * 2.5 + float(td.coords.x + td.coords.y)) * 4.0
		draw_line(top_center + Vector2(-18 + wave_offset, -4), top_center + Vector2(6 + wave_offset, -4), Color(0.38, 0.65, 0.72, 0.55), 2.0)
		draw_line(top_center + Vector2(-8 - wave_offset, 5), top_center + Vector2(18 - wave_offset, 5), Color(0.38, 0.65, 0.72, 0.55), 2.0)
	elif td.terrain_type == GridTileData.TerrainType.CITY:
		var win_col := Color(0.95, 0.72, 0.22, 0.7 + 0.3 * pulse)
		draw_rect(Rect2(top_center + Vector2(-13, -10), Vector2(4, 2)), win_col, true)
		draw_rect(Rect2(top_center + Vector2(-6, -10), Vector2(4, 2)), win_col, true)
		draw_rect(Rect2(top_center + Vector2(5, -7), Vector2(5, 2)), win_col, true)

	# Reachable Fuel / Attack Target Highlights
	if reachable_info.has(coords) and coords != selected_coords:
		var info: Dictionary = reachable_info[coords]
		var inner_poly: PackedVector2Array = _inset_diamond(4.0, false)
		var inner_loop: PackedVector2Array = _inset_diamond(4.0, true)
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
		draw_polyline(_inset_diamond(3.0, true), Color(1.0, 0.84, 0.32, 0.95), 2.8)
		draw_set_transform(Vector2.ZERO)

	# Hovered Tile Cursor Outline
	if coords == hovered_coords:
		draw_set_transform(top_center)
		draw_polyline(_inset_diamond(2.0, true), Color(1.0, 0.95, 0.75, 0.95), 2.5)
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