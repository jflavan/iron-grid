class_name TacticalBot
extends RefCounted
## Player-side mirror of AIController: same attack/positional scoring and weights, with the
## map role flipped for the Coalition (garrison on DEFENSE maps, assault on OFFENSE maps).

const ME := MechData.Faction.PLAYER
const FOE := MechData.Faction.AI

## Seeded variety: pick uniformly among actions scoring within `jitter` points of the best. 0 = deterministic.
static var jitter: float = 0.0
static var rng := RandomNumberGenerator.new()

static func choose_best_action(unit: MechUnit, grid_map: IsoGridMap, uc: UnitContainer, map_def: MapDefinition) -> Dictionary:
	var m: MechData = unit.mech_data
	var reachable: Dictionary = grid_map.compute_reachable_tiles(m, uc.build_occupied_map(unit))
	var foes: Array[MechUnit] = uc.get_faction_units(FOE)
	var start_tile: GridTileData = grid_map.get_tile(m.grid_pos)
	var targets := _objective_targets(grid_map, map_def)
	var deny := _deny_tiles(grid_map, map_def)
	var garrison := map_def.strategy_mode == MapDefinition.StrategyMode.DEFENSE

	var best := { "type": "WAIT_ENTRENCH", "target_pos": m.grid_pos,
		"score": _score_tile(start_tile, m, foes, map_def, targets) + (18.0 if m.current_fuel <= 4 else 4.0) }
	if garrison and start_tile.is_objective and start_tile.controlled_by == ME:
		best["score"] += 38.0
	var cands: Array[Dictionary] = [best]

	for dest_pos in reachable.keys():
		var info: Dictionary = reachable[dest_pos]
		var path: Array[Vector2i] = info["path"]
		var dest_tile: GridTileData = grid_map.get_tile(dest_pos)
		var score: float
		if info["is_attack"]:
			var tgt: MechUnit = uc.get_unit_at(dest_pos, unit)
			if tgt == null: continue
			var from_tile: GridTileData = grid_map.get_tile(path[path.size() - 2] if path.size() >= 2 else m.grid_pos)
			var fc: Dictionary = SkirmishEngine.compute_forecast(m, tgt.mech_data, from_tile, dest_tile)
			var dd: int = fc["est_dmg_to_def"]; var da: int = fc["est_dmg_to_atk"]
			score = 45.0 + float(dd - da) * 1.35 + float(int(fc["atk_cards_held"]) - int(fc["def_cards_held"])) * 16.0
			score += float(fc["atk_mod_pct"] - fc["def_mod_pct"]) * 0.45
			if dd >= tgt.mech_data.current_armor: score += 130.0
			if dest_tile.is_objective and dest_tile.controlled_by != ME: score += 30.0
			if deny.has(dest_pos): score += 150.0
			if da >= m.current_armor and dd < tgt.mech_data.current_armor: score -= 95.0
		else:
			if dest_pos == m.grid_pos: continue
			score = _score_tile(dest_tile, m, foes, map_def, targets)
			if deny.has(dest_pos): score += 150.0
			score -= float(info["fuel_spent"]) * 1.1
			if m.current_fuel - int(info["fuel_spent"]) <= 1: score -= 10.0
		var act := { "type": "ENGAGE" if info["is_attack"] else "MOVE", "target_pos": dest_pos, "score": score }
		cands.append(act)
		if score > best["score"]:
			best = act
	grid_map.clear_highlights()
	if jitter > 0.0:
		var near: Array[Dictionary] = cands.filter(func(c): return c["score"] >= best["score"] - jitter)
		return near[rng.randi_range(0, near.size() - 1)]
	return best

## Syndicate-held objectives that would hand the Syndicate the win at turn end (Citadel fully lost).
static func _deny_tiles(grid_map: IsoGridMap, map_def: MapDefinition) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if map_def.strategy_mode != MapDefinition.StrategyMode.DEFENSE: return tiles
	for obj in map_def.objectives:
		var td: GridTileData = grid_map.get_tile(obj["pos"])
		if td.controlled_by == ME: return []
		tiles.append(td.coords)
	return tiles

static func _objective_targets(grid_map: IsoGridMap, map_def: MapDefinition) -> Array[Vector2i]:
	var all_objs: Array[Vector2i] = []; var unheld: Array[Vector2i] = []
	var pool: Array = map_def.objectives.map(func(o): return o["pos"])
	if map_def.strategy_mode == MapDefinition.StrategyMode.OFFENSE and not map_def.hq_positions.is_empty():
		pool = map_def.hq_positions # assault only wins by holding an HQ bunker
	for p in pool:
		all_objs.append(p)
		if grid_map.get_tile(p).controlled_by != ME: unheld.append(p)
	if map_def.strategy_mode == MapDefinition.StrategyMode.DEFENSE or unheld.is_empty(): return all_objs
	return unheld

static func _score_tile(tile: GridTileData, m: MechData, foes: Array[MechUnit], map_def: MapDefinition, targets: Array[Vector2i]) -> float:
	if tile == null: return -999.0
	var s: float = float(tile.get_defense_modifier_pct()) * 0.65 + float(tile.elevation) * 7.5
	if tile.terrain_type == GridTileData.TerrainType.RIVER: s -= 26.0
	elif tile.terrain_type == GridTileData.TerrainType.CITY: s += 18.0
	elif tile.terrain_type == GridTileData.TerrainType.MOUNTAIN and m.mountain_gear: s += 16.0
	if tile.is_objective: s += 52.0 if tile.controlled_by != ME else 24.0
	var ed: float = 999.0
	for f in foes: ed = minf(ed, float(absi(tile.coords.x - f.mech_data.grid_pos.x) + absi(tile.coords.y - f.mech_data.grid_pos.y)))
	var od: float = 999.0
	for o in targets: od = minf(od, float(absi(tile.coords.x - o.x) + absi(tile.coords.y - o.y)))
	match map_def.strategy_mode:
		MapDefinition.StrategyMode.DEFENSE: s -= od * 7.0 + ed * 2.2   # Coalition garrison
		MapDefinition.StrategyMode.OFFENSE: s -= od * 6.5 + ed * 4.5   # Coalition assault
		_: s -= ed * 4.8 + od * 3.8
	return s
