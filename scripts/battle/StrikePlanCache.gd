class_name StrikePlanCache
extends RefCounted

## Strike plans (TerrainGrid.compute_strike_plan) for the current selection, so sweeping the cursor
## back and forth across enemies runs each search once. Plans are keyed by everything they depend
## on; the uncapped movement-cost field they read is built once per (walker, tile, occupancy epoch).
## Battlefield owns one and clears it with the selection.

const PLAN_CACHE_MAX := 64

var _plans: Dictionary = {}
var _field: Dictionary = {}     # TerrainGrid.strike_cost_field of the selected walker
var _field_key: Array = []      # [walker, tile, occupancy epoch] the field was built for

func clear() -> void:
	_plans.clear()
	_field = {}
	_field_key = []

## The [walker, tile, occupancy epoch] the cost field was last built for (empty before the first plan).
func field_key() -> Array:
	return _field_key

## The plan for `u` striking `target_unit` on `target`, from the cache or a fresh search.
func plan_for(grid: IsoGridMap, units: UnitContainer, u: MechUnit, target: Vector2i, target_unit: MechUnit) -> StrikePlan:
	var m: MechData = u.mech_data
	var epoch: int = units.occupancy_epoch
	var key := [m, m.grid_pos, m.current_fuel, m.has_moved, target, target_unit, target_unit.mech_data.grid_pos, epoch]
	var cached: StrikePlan = _plans.get(key, null)
	if cached != null:
		return cached
	if _plans.size() >= PLAN_CACHE_MAX:
		_plans.clear()
	var occ := units.build_occupied_map(u)
	var plan: StrikePlan
	if m.has_moved:
		# Only the start tile can launch now, so the targeted search settles after one pop: no field.
		plan = grid.compute_strike_plan(m, target, occ)
	else:
		var fkey := [m, m.grid_pos, epoch]
		if fkey != _field_key:
			_field = grid.strike_cost_field(m, occ)
			_field_key = fkey
		plan = grid.compute_strike_plan(m, target, occ, _field)
	_plans[key] = plan
	return plan
