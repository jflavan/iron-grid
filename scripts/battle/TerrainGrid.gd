class_name TerrainGrid
extends RefCounted

## The pure (render-free) battlefield grid: tiles, bounds, movement ranges (fuel Dijkstra) and strike
## plans. IsoGridMap owns one and adds the isometric drawing on top, so the rules can be run and
## tested without a scene tree.

## Neighbour order every search and scorer uses (it decides tie-breaks): +x, -x, +y, -y.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Grid (Manhattan) distance: the number of orthogonal steps between two tiles.
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

const _NO_FUEL_CAP: int = 1 << 30
const _SEQ_BITS: int = 24
## Step-cost table dimensions, derived from the data so a new terrain row or a higher MAX_ELEVATION
## cannot index past the table or into the next terrain's block.
static var TERRAIN_COUNT: int = GridTileData.TerrainType.size()
const ELEV_COUNT: int = GridTileData.MAX_ELEVATION + 1
const ELEV_SQ: int = ELEV_COUNT * ELEV_COUNT

## Read-only outside load_from_definition (a resize without a reload would desync the flat arrays).
var width: int:
	get: return _width
var height: int:
	get: return _height
var _width: int = 0   # 0x0 until load_from_definition
var _height: int = 0
var tiles: Dictionary = {} # Vector2i -> GridTileData
var _flat: Array[GridTileData] = [] # same tiles, indexed y * _width + x
var _terrain_flat := PackedByteArray() # terrain type per flat index (search hot path)
var _elev_flat := PackedByteArray()    # elevation per flat index
var _probe_tiles: Array[GridTileData] = [] # [terrain * ELEV_COUNT + elevation], for the step-cost table

func is_valid_coords(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < _width and coords.y >= 0 and coords.y < _height

func get_tile(coords: Vector2i) -> GridTileData:
	if coords.x < 0 or coords.x >= _width or coords.y < 0 or coords.y >= _height:
		return null
	assert(_flat.size() == _width * _height, "TerrainGrid.get_tile before load_from_definition")
	return _flat[coords.y * _width + coords.x]

func get_tile_elevation(coords: Vector2i) -> int:
	var td: GridTileData = get_tile(coords)
	return td.elevation if td != null else 0

## Parses the map's terrain / elevation rows and objectives into tiles.
func load_from_definition(map_def: MapDefinition) -> void:
	for msg in map_def.validate():
		push_error(msg)
	_width = map_def.width
	_height = map_def.height
	tiles.clear()
	assert(_width * _height < (1 << _SEQ_BITS), "map too large for the search's discovery-order key")
	_flat = []
	_flat.resize(_width * _height)
	_terrain_flat.resize(_width * _height)
	_elev_flat.resize(_width * _height)
	for y in range(_height):
		for x in range(_width):
			var c := Vector2i(x, y)
			var td := GridTileData.new(c, map_def.terrain_at(x, y), map_def.elevation_at(x, y), false, "")
			tiles[c] = td
			_flat[y * _width + x] = td
			_terrain_flat[y * _width + x] = td.terrain_type
			_elev_flat[y * _width + x] = td.elevation

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
		var res: Array = _search(unit, occupied_units, max_budget)
		var cost: PackedInt32Array = res[0]
		var came: PackedInt32Array = res[1]
		var order: Array[int] = res[2]
		var start_idx: int = start.y * _width + start.x

		# Each path is its parent's path plus one tile, so a parent's path is built once and copied
		# natively into its children's instead of every tile walking back to the start. `order` is
		# discovery order (a parent can be improved after its child was discovered), hence the walk up
		# to the nearest tile whose path is already known.
		var paths: Array = []
		paths.resize(_width * _height)
		paths[start_idx] = [start] as Array[Vector2i]
		for idx in order:
			var pos := Vector2i(idx % _width, idx / _width)
			if paths[idx] == null:
				var chain: Array[int] = []
				var cur: int = idx
				while paths[cur] == null:
					chain.append(cur)
					cur = came[cur]
				var base: Array[Vector2i] = paths[cur]
				for k in range(chain.size() - 1, -1, -1):
					var c: int = chain[k]
					var p: Array[Vector2i] = base.duplicate()
					p.append(Vector2i(c % _width, c / _width))
					paths[c] = p
					base = p
			var path: Array[Vector2i] = paths[idx]
			if idx != start_idx and occupied_units.has(pos):
				continue # Cannot end move on any occupied tile (friendly or enemy)

			var spent: int = cost[idx]
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

## Fuel Dijkstra over flat tile indices (y * _width + x), shared by movement ranges and strike plans
## so both always agree. Rules: never step onto an enemy node, and drop any step whose running cost
## would exceed `budget`. `settle`, when given, stops the search once every listed node has been
## popped (its cost is final).
## Returns [cost: PackedInt32Array (-1 = unreached), came_from: PackedInt32Array, order: Array[int]]
## where `order` lists the reached tile indices in discovery order (start first).
## Step costs come from a 6 x 5 x 5 table ([to_terrain][from_elev][to_elev]) filled once per search
## from the real MechData.get_step_fuel_cost, so the rule itself lives in one place.
func _search(unit: MechData, occupied_units: Dictionary, budget: int, settle: Array[Vector2i] = []) -> Array:
	var w: int = _width
	var h: int = _height
	var n: int = w * h
	var start_idx: int = unit.grid_pos.y * w + unit.grid_pos.x

	var cost := PackedInt32Array()
	cost.resize(n)
	cost.fill(-1)
	var came := PackedInt32Array()
	came.resize(n)
	var seq := PackedInt32Array() # discovery order of each node, kept across re-pushes
	seq.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var blocked := PackedByteArray() # enemy-occupied nodes: never entered
	blocked.resize(n)
	for p: Vector2i in occupied_units.keys():
		if is_valid_coords(p) and occupied_units[p].faction != unit.faction:
			blocked[p.y * w + p.x] = 1

	var pending := PackedByteArray()
	var pending_left: int = 0
	if not settle.is_empty():
		pending.resize(n)
		for p in settle:
			if not is_valid_coords(p):
				pending_left += 1 # can never be popped: the search runs to the end, as it always did
			elif pending[p.y * w + p.x] == 0:
				pending[p.y * w + p.x] = 1
				pending_left += 1

	var steps: PackedInt32Array = _step_cost_table(unit)
	var terr: PackedByteArray = _terrain_flat
	var elev: PackedByteArray = _elev_flat

	# Binary min-heap of (cost, discovery order) packed into one int plus a parallel tile index; a
	# node pushed again after a cheaper path was found leaves a stale entry behind that is skipped
	# when popped. Ties pop in discovery order, so paths (and the facing they produce) stay
	# deterministic.
	var heap: Array[int] = []
	var heap_idx: Array[int] = []
	var order: Array[int] = [start_idx]
	cost[start_idx] = 0
	came[start_idx] = start_idx
	seq[start_idx] = 0
	_heap_push(heap, heap_idx, 0, start_idx)

	while not heap.is_empty():
		var top: int = heap[0]
		var cur: int = heap_idx[0]
		_heap_pop(heap, heap_idx)
		if closed[cur] != 0 or (top >> _SEQ_BITS) != cost[cur]:
			continue # stale entry
		closed[cur] = 1
		if pending_left > 0 and pending[cur] == 1:
			pending_left -= 1
			if pending_left == 0:
				break

		var cur_cost: int = cost[cur]
		var cx: int = cur % w
		var cy: int = cur / w
		var from_e: int = elev[cur] * ELEV_COUNT
		# Neighbours in DIRS order: +x, -x, +y, -y.
		for k in 4:
			var ni: int
			match k:
				0:
					if cx + 1 >= w:
						continue
					ni = cur + 1
				1:
					if cx == 0:
						continue
					ni = cur - 1
				2:
					if cy + 1 >= h:
						continue
					ni = cur + w
				_:
					if cy == 0:
						continue
					ni = cur - w
			if closed[ni] != 0 or blocked[ni] != 0:
				continue
			var new_cost: int = cur_cost + steps[terr[ni] * ELEV_SQ + from_e + elev[ni]]
			if new_cost > budget:
				continue
			var old: int = cost[ni]
			if old == -1 or new_cost < old:
				cost[ni] = new_cost
				came[ni] = cur
				if old == -1:
					seq[ni] = order.size()
					order.append(ni)
				_heap_push(heap, heap_idx, (new_cost << _SEQ_BITS) | seq[ni], ni)
	return [cost, came, order]

## [to_terrain][from_elev][to_elev] -> fuel, filled from the unit's own step rule. The rule reads
## only the four stats in the key, so one table per stat tuple serves every walker of that build
## (filling it costs 150 rule calls, as much as a whole capped reach search).
## The key must list every MechData field MechData._step_terms reads (test_step_table_key_covers_fuel_rule_inputs).
static var _step_tables: Dictionary = {}   # [fuel_usage, fuel_efficiency_mod, amphibious, mountain] -> table
static func step_table_key(unit: MechData) -> Array:
	return [unit.fuel_usage, unit.fuel_efficiency_mod, unit.amphibious_gear, unit.mountain_gear]

func _step_cost_table(unit: MechData) -> PackedInt32Array:
	var key := step_table_key(unit)
	var cached: Variant = _step_tables.get(key)
	if cached != null:
		return cached
	if _probe_tiles.is_empty():
		for t in TERRAIN_COUNT:
			for e in ELEV_COUNT:
				_probe_tiles.append(GridTileData.new(Vector2i.ZERO, t as GridTileData.TerrainType, e))
	var table := PackedInt32Array()
	table.resize(TERRAIN_COUNT * ELEV_COUNT * ELEV_COUNT)
	for t in TERRAIN_COUNT:
		for fe in ELEV_COUNT:
			for te in ELEV_COUNT:
				table[t * ELEV_SQ + fe * ELEV_COUNT + te] = unit.get_step_fuel_cost(_probe_tiles[fe], _probe_tiles[t * ELEV_COUNT + te])
	_step_tables[key] = table
	return table

## Dictionary view of a _search result: Vector2i -> cost, in discovery order.
func _costs_dict(res: Array) -> Dictionary:
	var cost: PackedInt32Array = res[0]
	var order: Array[int] = res[2]
	var w: int = _width
	var d: Dictionary = {}
	for i in order:
		d[Vector2i(i % w, i / w)] = cost[i]
	return d

static func _heap_push(heap: Array[int], heap_pos: Array[int], key: int, pos: int) -> void:
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

static func _heap_pop(heap: Array[int], heap_pos: Array[int]) -> void:
	var last: int = heap.size() - 1
	var key: int = heap[last]
	var pos: int = heap_pos[last]
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
## Vector2i -> int (a Dictionary because Battlefield caches it as one; the search itself runs on flat
## arrays and this is a single pass over the reached tiles). It depends only on the unit, its position and the occupancy, never on a strike
## target, so one field serves every compute_strike_plan call of a selection.
func strike_cost_field(unit: MechData, occupied_units: Dictionary) -> Dictionary:
	return _costs_dict(_search(unit, occupied_units, _NO_FUEL_CAP))

## A tile `unit` (standing on `start`) may fire from: on the map, free of other walkers, and, once
## the walker has moved, only its own tile.
func _can_launch_from(l: Vector2i, start: Vector2i, unit: MechData, occupied_units: Dictionary) -> bool:
	if not is_valid_coords(l):
		return false
	if l == start:
		return true
	return not unit.has_moved and not occupied_units.has(l)

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
			if _can_launch_from(l, start, unit, occupied_units):
				neighbours.append(l)
		if not neighbours.is_empty():
			costs = _costs_dict(_search(unit, occupied_units, _NO_FUEL_CAP, neighbours))
	var target_tile := get_tile(target)

	# Launch tiles: enemy neighbours the search reached that the attacker may stand on and fire from.
	var launches: Array[Dictionary] = []   # {pos, path, step: breakdown}
	for d in DIRS:
		var l: Vector2i = target + d
		if not costs.has(l) or not _can_launch_from(l, start, unit, occupied_units):
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
