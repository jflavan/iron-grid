class_name TacticalBot
extends RefCounted
## Player-side commander built on AIController's attack and positional scoring, with the map role
## flipped for the Coalition (garrison on DEFENSE maps, assault on OFFENSE maps). The garrison and
## objective weights below were tuned separately from AIController's (which carries HQ-interception
## bonuses instead), so this is a sibling, not a mirror: a shared scorer is a pending refactor.

const ME := MechData.Faction.PLAYER
const FOE := MechData.Faction.AI

## Seeded variety: pick uniformly among actions scoring within `jitter` points of the best. 0 = deterministic.
static var jitter: float = 0.0
static var rng := RandomNumberGenerator.new()

static func choose_best_action(unit: MechUnit, grid_map: IsoGridMap, uc: UnitContainer, map_def: MapDefinition) -> Dictionary:
	var m: MechData = unit.mech_data
	var occ: Dictionary = uc.build_occupied_map(unit)
	var reachable: Dictionary = grid_map.find_reachable_tiles(m, occ)
	var foes: Array[MechUnit] = uc.get_faction_units(FOE)
	var start_tile: GridTileData = grid_map.get_tile(m.grid_pos)
	var targets := _objective_targets(grid_map, map_def)
	var deny := _deny_tiles(grid_map, map_def)
	var garrison := map_def.strategy_mode == MapDefinition.StrategyMode.DEFENSE

	var best := { "type": "WAIT_ENTRENCH", "target_pos": m.grid_pos,
		"score": _score_tile(start_tile, m, foes, map_def, targets) + (18.0 if m.current_fuel <= 4 else 4.0) }
	if garrison:
		if start_tile.is_objective and start_tile.controlled_by == ME:
			best["score"] += 48.0
		elif start_tile.elevation >= 3:
			best["score"] += 18.0
	var cands: Array[Dictionary] = [best]

	for dest_pos in reachable.keys():
		var info: Dictionary = reachable[dest_pos]
		if info["is_attack"] or dest_pos == m.grid_pos:
			continue
		var dest_tile: GridTileData = grid_map.get_tile(dest_pos)
		var score: float = _score_tile(dest_tile, m, foes, map_def, targets)
		if deny.has(dest_pos): score += 150.0
		score -= float(info["fuel_spent"]) * 1.1
		if m.current_fuel - int(info["fuel_spent"]) <= 1: score -= 10.0
		var act := { "type": "MOVE", "target_pos": dest_pos, "score": score }
		cands.append(act)
		if score > best["score"]:
			best = act

	for tgt in foes:
		if not is_instance_valid(tgt) or tgt.mech_data == null or not tgt.mech_data.is_alive():
			continue
		var dest_pos: Vector2i = tgt.mech_data.grid_pos
		var dest_tile: GridTileData = grid_map.get_tile(dest_pos)
		if dest_tile == null:
			continue
		for d in TerrainGrid.DIRS:
			var from_pos: Vector2i = dest_pos + d
			if not grid_map.is_valid_coords(from_pos):
				continue
			if from_pos != m.grid_pos and (not reachable.has(from_pos) or reachable[from_pos]["is_attack"]):
				continue
			var move_fuel: int = 0 if from_pos == m.grid_pos else int(reachable[from_pos]["fuel_spent"])
			var from_tile: GridTileData = grid_map.get_tile(from_pos)
			var atk_fuel: int = m.get_step_fuel_cost(from_tile, dest_tile)
			var total_fuel: int = move_fuel + atk_fuel
			if total_fuel > m.current_fuel:
				continue
			var form_ctx: Dictionary = UnitContainer.formation_context(occ, dest_pos, from_pos, int(ME))
			var fc: Dictionary = SkirmishEngine.compute_forecast(m, tgt.mech_data, from_tile, dest_tile, form_ctx)
			var dd: int = fc["est_dmg_to_def"]; var da: int = fc["est_dmg_to_atk"]
			var atk_won: bool = bool(fc.get("attacker_won", dd >= da))
			var score: float = 45.0 + float(dd - da) * 1.35 + (24.0 if atk_won else -20.0)
			score += float(fc["atk_mod_pct"] - fc["def_mod_pct"]) * 0.45
			score -= float(total_fuel) * 0.25
			var angle := str(fc.get("approach_angle", "FRONT"))
			if angle == "REAR": score += 45.0
			elif angle == "FLANK": score += 20.0
			if dd >= tgt.mech_data.current_armor: score += 130.0 if da < m.current_armor else 35.0
			if dest_tile.is_objective and dest_tile.controlled_by != ME: score += 30.0
			if deny.has(dest_pos): score += 150.0
			if da >= m.current_armor and dd < tgt.mech_data.current_armor: score -= 95.0
			if garrison and not deny.has(dest_pos):
				if start_tile.is_objective and start_tile.controlled_by == ME and from_pos != m.grid_pos:
					score -= 42.0
				if from_tile.elevation < start_tile.elevation:
					score -= float(start_tile.elevation - from_tile.elevation) * 18.0
			var click_pos: Vector2i = dest_pos if from_pos == m.grid_pos else from_pos
			var act := { "type": "ENGAGE", "target_pos": click_pos, "attack_pos": dest_pos, "move_pos": from_pos, "score": score }
			cands.append(act)
			if score > best["score"]:
				best = act
	if jitter > 0.0:
		var near: Array[Dictionary] = cands.filter(func(c): return c["score"] >= best["score"] - jitter)
		return near[rng.randi_range(0, near.size() - 1)]
	return best

## Turns the selected player walker one step toward the nearest Syndikat walker (AIController's
## facing rule) through the player's rotate action (the T key). The balance policy calls it before
## each order, so a walker that WAITs faces the threat, and again after a move, which resets facing.
## Returns true when it rotated; false when it already faces the threat or can't rotate.
static func reface_step(bf: Battlefield) -> bool:
	var sel: MechUnit = bf.selected_unit
	if sel == null or not is_instance_valid(sel) or sel.mech_data.faction != ME:
		return false
	var want := AIController.choose_best_facing(sel.mech_data.grid_pos, bf.unit_container.get_faction_units(FOE))
	var before: Vector2i = sel.mech_data.facing
	if before == want:
		return false
	bf._rotate_selected_unit()
	return sel.mech_data.facing != before

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
	if tile.is_objective:
		if tile.controlled_by != ME:
			s += 52.0
		else:
			s += 44.0 if map_def.strategy_mode == MapDefinition.StrategyMode.DEFENSE else 24.0
	var ed: float = 999.0
	for f in foes: ed = minf(ed, float(absi(tile.coords.x - f.mech_data.grid_pos.x) + absi(tile.coords.y - f.mech_data.grid_pos.y)))
	var od: float = 999.0
	for o in targets: od = minf(od, float(absi(tile.coords.x - o.x) + absi(tile.coords.y - o.y)))
	match map_def.strategy_mode:
		MapDefinition.StrategyMode.DEFENSE:
			s -= od * 7.0 + ed * 2.2   # Coalition garrison
			if tile.elevation < 2: s -= 22.0
		MapDefinition.StrategyMode.OFFENSE: s -= od * 6.5 + ed * 4.5   # Coalition assault
		_: s -= ed * 4.8 + od * 3.8
	return s
