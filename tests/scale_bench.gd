extends Node

## Headless scalability benchmark: synthetic maps from 10x10 to 48x48 with a walker on roughly
## every 12th tile, timing the CPU-side systems that grow with map and army size: map load (incl.
## the terrain mesh bake), movement ranges, strike plans and full AI decisions. Times are medians.
## Run: godot --headless --path . res://tests/ScaleBench.tscn

const SIZES: Array[int] = [10, 20, 32, 48]
const REPEATS := 5

func _ready() -> void:
	print("\n[SCALE BENCH] size  units  map_load_ms  reach_ms  strike_plan_ms  ai_decision_ms  terrain_ops")
	for n in SIZES:
		await _bench_size(n)
	print("[SCALE BENCH] done")
	get_tree().quit(0)

func _bench_size(n: int) -> void:
	var md := _synthetic_map(n)
	var gm := IsoGridMap.new()
	add_child(gm)
	var load_t: Array[float] = []
	for r in REPEATS:
		var t0 := Time.get_ticks_usec()
		gm.load_from_definition(md)
		load_t.append((Time.get_ticks_usec() - t0) / 1000.0)

	var uc := UnitContainer.new()
	add_child(uc)
	uc.spawn_units_for_map(md, gm)
	var players := uc.get_faction_units(MechData.Faction.PLAYER)
	var ais := uc.get_faction_units(MechData.Faction.AI)

	var reach_t: Array[float] = []
	var plan_t: Array[float] = []
	var ai_t: Array[float] = []
	for r in REPEATS:
		var u: MechUnit = players[r % players.size()]
		u.mech_data.current_fuel = u.mech_data.max_fuel
		var occ := uc.build_occupied_map(u)
		var t0 := Time.get_ticks_usec()
		gm.find_reachable_tiles(u.mech_data, occ)
		reach_t.append((Time.get_ticks_usec() - t0) / 1000.0)
		# Worst case for the uncapped strike search: the farthest enemy.
		var far: MechUnit = ais[0]
		for e in ais:
			if _dist(e, u) > _dist(far, u):
				far = e
		t0 = Time.get_ticks_usec()
		gm.compute_strike_plan(u.mech_data, far.mech_data.grid_pos, occ)
		plan_t.append((Time.get_ticks_usec() - t0) / 1000.0)
		var a: MechUnit = ais[r % ais.size()]
		a.mech_data.has_moved = false
		a.mech_data.has_attacked = false
		a.mech_data.current_fuel = a.mech_data.max_fuel
		SkirmishEngine.clear_forecast_cache()
		t0 = Time.get_ticks_usec()
		AIController.choose_best_action(a, gm, uc, md)
		ai_t.append((Time.get_ticks_usec() - t0) / 1000.0)

	print("[SCALE BENCH] %4d  %5d  %11.2f  %8.2f  %14.2f  %14.2f  %11d" % [
		n, uc.units.size(), _median(load_t), _median(reach_t), _median(plan_t), _median(ai_t), _terrain_ops(gm)])
	uc.clear_units()
	uc.queue_free()
	gm.queue_free()
	await get_tree().process_frame

func _terrain_ops(gm: IsoGridMap) -> int:
	# Mesh segments + labels replayed per frame (absent on builds without the terrain bake).
	var mesh = gm.get("_terrain_mesh")
	return mesh.op_count() if mesh != null else -1

func _synthetic_map(n: int) -> MapDefinition:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + n
	var md := MapDefinition.new()
	md.map_name = "SCALE %d" % n
	md.width = n
	md.height = n
	md.strategy_mode = MapDefinition.StrategyMode.PITCHED_BATTLE
	var codes := ["P", "P", "P", "D", "F", "F", "R", "C", "M"]
	for y in n:
		var t := PackedStringArray()
		var e := PackedStringArray()
		for x in n:
			t.append(codes[rng.randi_range(0, codes.size() - 1)])
			e.append(str(rng.randi_range(0, 3)))
		md.terrain_codes.append(" ".join(t))
		md.elevation_rows.append(" ".join(e))
	for i in maxi(1, n / 8):
		md.objectives.append({"pos": Vector2i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1)), "label": "OBJ", "owner": -1})
	var chassis := ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]
	var taken := {}
	var count: int = maxi(4, n * n / 12)
	while taken.size() < count:
		var p := Vector2i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))
		if taken.has(p):
			continue
		taken[p] = true
		md.spawns.append({"chassis": chassis[taken.size() % chassis.size()], "callsign": "U-%d" % taken.size(), "pos": p, "faction": taken.size() % 2})
	return md

func _dist(a: MechUnit, b: MechUnit) -> int:
	return absi(a.mech_data.grid_pos.x - b.mech_data.grid_pos.x) + absi(a.mech_data.grid_pos.y - b.mech_data.grid_pos.y)

func _median(v: Array[float]) -> float:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2]
