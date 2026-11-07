class_name TerrainGrid
extends RefCounted

## The pure (render-free) battlefield grid: tiles, bounds, movement ranges (fuel Dijkstra) and strike
## plans. IsoGridMap owns one and adds the isometric drawing on top, so the rules can be run and
## tested without a scene tree.

## Neighbour order every search and scorer uses (it decides tie-breaks): +x, -x, +y, -y.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const _NO_FUEL_CAP: int = 1 << 30
const _SEQ_BITS: int = 24

var width: int = 10
var height: int = 8
var tiles: Dictionary = {} # Vector2i -> GridTileData
var _flat: Array[GridTileData] = [] # same tiles, indexed y * width + x

func is_valid_coords(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < width and coords.y >= 0 and coords.y < height

func get_tile(coords: Vector2i) -> GridTileData:
	if coords.x < 0 or coords.x >= width or coords.y < 0 or coords.y >= height:
		return null
	return _flat[coords.y * width + coords.x] if not _flat.is_empty() else tiles.get(coords, null)

func get_tile_elevation(coords: Vector2i) -> int:
	var td: GridTileData = get_tile(coords)
	return td.elevation if td != null else 0

## Parses the map's terrain / elevation rows and objectives into tiles.
func load_from_definition(map_def: MapDefinition) -> void:
	width = map_def.width
	height = map_def.height
	tiles.clear()
	_flat = []
	_flat.resize(width * height)
	for y in range(height):
		for x in range(width):
			var c := Vector2i(x, y)
			var td := GridTileData.new(c, map_def.terrain_at(x, y), map_def.elevation_at(x, y), false, "")
			tiles[c] = td
			_flat[y * width + x] = td

	for obj in map_def.objectives:
		var pos: Vector2i = obj["pos"]
		if tiles.has(pos):
			var td: GridTileData = tiles[pos]
			td.is_objective = true
			td.objective_label = str(obj.get("label", "Objective"))
			td.controlled_by = int(obj.get("owner", -1))

## Pure data query: computes all reachable tiles for `unit` given `occupied_units` without modifying UI state.
func find_reachable_tiles(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	var reachable := {}
	if unit == null or unit.is_order_complete():
		return reachable

	var start: Vector2i = unit.grid_pos
	var max_budget: int = unit.current_fuel

	if not unit.has_moved:
		var search: Array = shortest_costs(unit, occupied_units, max_budget)
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
		for d in DIRS:
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

## Dijkstra over fuel cost from unit.grid_pos, shared by movement ranges and strike plans so both
## always agree. Returns [best_cost, came_from] (Vector2i -> int / Vector2i). Rules: never step onto
## an enemy node, and drop any step whose running cost would exceed `budget`.
## `settle`, when given, stops the search once every listed node has been popped (its cost is final).
func shortest_costs(unit: MechData, occupied_units: Dictionary, budget: int, settle: Array[Vector2i] = []) -> Array:
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

		for d in DIRS:
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

## Cheapest fuel (uncapped, no early exit) from unit.grid_pos to every tile it can path to, as
## Vector2i -> int. It depends only on the unit, its position and the occupancy, never on a strike
## target, so one field serves every compute_strike_plan call of a selection.
func strike_cost_field(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	return shortest_costs(unit, occupied_units, _NO_FUEL_CAP)[0]

## Explains whether `unit` can strike the enemy at `target` this turn, and if not, why and what to
## do (see StrikePlan). Uses the same search and costs as find_reachable_tiles, without its fuel
## cap. The advice replays next turn under the real WAIT and upkeep rules, assuming the enemy holds
## its tile. `cost_field` (from strike_cost_field) skips the search when the caller already has it.
func compute_strike_plan(unit: MechData, target: Vector2i, occupied_units: Dictionary, cost_field: Dictionary = {}) -> StrikePlan:
	var plan := StrikePlan.new()
	plan.have = unit.current_fuel
	var start: Vector2i = unit.grid_pos
	var costs: Dictionary = cost_field
	if costs.is_empty():
		# Only the usable launch tiles' costs matter (the filter below drops the rest): stop as soon
		# as they are all final. An occupied neighbour is never entered, so waiting for it would
		# flood the whole map.
		var neighbours: Array[Vector2i] = []
		for d in DIRS:
			var l: Vector2i = target + d
			if not is_valid_coords(l) or (unit.has_moved and l != start) or (l != start and occupied_units.has(l)):
				continue
			neighbours.append(l)
		if not neighbours.is_empty():
			costs = shortest_costs(unit, occupied_units, _NO_FUEL_CAP, neighbours)[0]
	var target_tile := get_tile(target)

	# Launch tiles: enemy neighbours the search reached that the attacker may stand on and fire from.
	var launches: Array[Dictionary] = []   # {pos, path, step: breakdown}
	for d in DIRS:
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
