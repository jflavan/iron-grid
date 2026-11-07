class_name AIController
extends RefCounted

## Tactical AI Decision Engine for Kriegs-Syndikat Forces
## Evaluates reachable tiles, approach vectors, terrain/elevation modifiers, and combat forecasts
## to choose between attacking player walkers, capturing objectives, holding high ground, or refueling.

## Decision "type" values (consumers compare against these strings).
const ACTION_WAIT := "WAIT_ENTRENCH"
const ACTION_MOVE := "MOVE"
const ACTION_ENGAGE := "ENGAGE"

static func choose_best_action(
	ai_unit: MechUnit,
	grid_map: IsoGridMap,
	unit_container: UnitContainer,
	map_def: MapDefinition
) -> Dictionary:
	var m_data: MechData = ai_unit.mech_data
	var occ_map: Dictionary = unit_container.build_occupied_map(ai_unit)
	var reachable: Dictionary = grid_map.find_reachable_tiles(m_data, occ_map)

	var player_units: Array[MechUnit] = unit_container.get_faction_units(MechData.Faction.PLAYER)
	# Foe positions, gathered once: the positional score reads them for every candidate tile.
	var foe_positions: Array[Vector2i] = []
	for pu in player_units:
		foe_positions.append(pu.mech_data.grid_pos)
	var start_pos: Vector2i = m_data.grid_pos
	var start_tile: GridTileData = grid_map.get_tile(start_pos)
	var obj_targets := _objective_targets(grid_map, map_def)
	var deny_tiles := _imminent_defeat_tiles(grid_map, map_def)
	var garrison: bool = (map_def.strategy_mode == MapDefinition.StrategyMode.OFFENSE)

	var wait_path: Array[Vector2i] = [start_pos]
	# In-place baseline score (holding / entrenching & refueling)
	var best_action: Dictionary = {
		"type": ACTION_WAIT,
		"target_pos": start_pos,
		"path": wait_path,
		"fuel_spent": 0,
		"score": _score_positional_tile(start_tile, m_data, foe_positions, map_def, obj_targets) + (18.0 if m_data.current_fuel <= 4 else 4.0)
	}

	# On OFFENSE maps (where AI is the entrenched garrison), units standing on Objective Cities
	# strongly prefer holding their bunker unless they can favorably smash an intruder.
	if garrison and start_tile.is_objective and start_tile.controlled_by == MechData.Faction.AI:
		best_action["score"] += 38.0

	for pos_key in reachable.keys():
		var dest_pos: Vector2i = pos_key
		var info: Dictionary = reachable[dest_pos]
		if info["is_attack"] or dest_pos == start_pos:
			continue
		var path: Array[Vector2i] = info["path"]
		var fuel_spent: int = info["fuel_spent"]
		var dest_tile: GridTileData = grid_map.get_tile(dest_pos)

		var pos_score: float = _score_positional_tile(dest_tile, m_data, foe_positions, map_def, obj_targets)
		if deny_tiles.has(dest_pos):
			pos_score += 150.0 # Retaking this node breaks the Coalition's pending objective victory
		# Small penalty for burning all fuel without engaging
		pos_score -= float(fuel_spent) * 1.1
		if m_data.current_fuel - fuel_spent <= 1:
			pos_score -= 10.0

		if pos_score > best_action["score"]:
			best_action = {
				"type": ACTION_MOVE,
				"target_pos": dest_pos,
				"path": path,
				"fuel_spent": fuel_spent,
				"score": pos_score
			}

	# Evaluate decoupled attacks against each living player unit from all reachable adjacent launch tiles (including start_pos)
	var attack_targets: Array[MechUnit] = [] if m_data.has_attacked else player_units
	for target_unit in attack_targets:
		if not is_instance_valid(target_unit) or target_unit.mech_data == null or not target_unit.mech_data.is_alive():
			continue
		var dest_pos: Vector2i = target_unit.mech_data.grid_pos
		var dest_tile: GridTileData = grid_map.get_tile(dest_pos)
		if dest_tile == null:
			continue

		for d in TerrainGrid.DIRS:
			var from_pos: Vector2i = dest_pos + d
			if not grid_map.is_valid_coords(from_pos):
				continue
			if from_pos != start_pos and (not reachable.has(from_pos) or reachable[from_pos]["is_attack"]):
				continue
			var move_fuel: int = 0 if from_pos == start_pos else int(reachable[from_pos]["fuel_spent"])
			var move_path: Array[Vector2i] = []
			if from_pos == start_pos:
				move_path.append(start_pos)
			else:
				move_path.assign(reachable[from_pos]["path"])
			var from_tile: GridTileData = grid_map.get_tile(from_pos)
			var attack_fuel: int = m_data.get_step_fuel_cost(from_tile, dest_tile)
			var total_fuel: int = move_fuel + attack_fuel
			if total_fuel > m_data.current_fuel:
				continue

			# occ_map excludes ai_unit: it is still on start_pos during the forecast, and must not
			# count as its own adjacent ally when it launches from another tile.
			var form_ctx := UnitContainer.formation_context(occ_map, dest_pos, from_pos, int(m_data.faction))
			var forecast: Dictionary = SkirmishEngine.forecast_shared(   # read-only below
				m_data, target_unit.mech_data, from_tile, dest_tile, form_ctx
			)
			var est_dmg_def: int = forecast["est_dmg_to_def"]
			var est_dmg_atk: int = forecast["est_dmg_to_atk"]
			var atk_won: bool = bool(forecast.get("attacker_won", est_dmg_def >= est_dmg_atk))

			var atk_score: float = 45.0
			atk_score += float(est_dmg_def - est_dmg_atk) * 1.35
			atk_score += 24.0 if atk_won else -20.0
			atk_score += float(forecast["atk_mod_pct"] - forecast["def_mod_pct"]) * 0.45
			atk_score -= float(total_fuel) * 0.25

			# Bonus for flanking and rear attack angles
			var approach_ang := str(forecast.get("approach_angle", "FRONT"))
			if approach_ang == "REAR":
				atk_score += 45.0
			elif approach_ang == "FLANK":
				atk_score += 20.0

			# Huge bonus for finishing off an enemy walker cleanly (scaled if mutual destruction)
			if est_dmg_def >= target_unit.mech_data.current_armor:
				atk_score += 130.0 if est_dmg_atk < m_data.current_armor else 35.0
			# Attacking a walker that is holding an objective
			if dest_tile.is_objective and dest_tile.controlled_by != MechData.Faction.AI:
				atk_score += 30.0
			if deny_tiles.has(dest_pos):
				atk_score += 150.0
			# On OFFENSE maps, prioritize intercepting player walkers threatening the HQ bunkers
			if garrison:
				for hq_pos in map_def.hq_positions:
					var hq_dist: int = absi(dest_pos.x - hq_pos.x) + absi(dest_pos.y - hq_pos.y)
					if hq_dist <= 3:
						atk_score += 45.0
						break
			# Caution if the counter-attack would destroy the AI walker without a kill trade
			if est_dmg_atk >= m_data.current_armor and est_dmg_def < target_unit.mech_data.current_armor:
				atk_score -= 95.0

			if atk_score > best_action["score"]:
				var full_path: Array[Vector2i] = move_path.duplicate()
				full_path.append(dest_pos)
				best_action = {
					"type": ACTION_ENGAGE,
					"move_pos": from_pos,
					"move_path": move_path,
					"move_fuel": move_fuel,
					"target_pos": dest_pos,
					"attack_fuel": attack_fuel,
					"path": full_path,
					"fuel_spent": total_fuel,
					"facing": dest_pos - from_pos,
					"score": atk_score
				}

	if not best_action.has("facing"):
		best_action["facing"] = choose_best_facing(best_action.get("target_pos", start_pos), player_units)

	return best_action

## Chooses cardinal facing direction towards the closest threatening player unit
static func choose_best_facing(pos: Vector2i, enemy_units: Array[MechUnit]) -> Vector2i:
	var closest_dist: int = 99999
	var closest_pos: Vector2i = pos + Vector2i(-1, 0)
	for u in enemy_units:
		if is_instance_valid(u) and u.mech_data != null and u.mech_data.is_alive():
			var d: int = absi(u.mech_data.grid_pos.x - pos.x) + absi(u.mech_data.grid_pos.y - pos.y)
			if d < closest_dist:
				closest_dist = d
				closest_pos = u.mech_data.grid_pos
	var diff: Vector2i = closest_pos - pos
	if diff == Vector2i.ZERO:
		return Vector2i(-1, 0)
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(1 if diff.x > 0 else -1, 0)
	return Vector2i(0, 1 if diff.y > 0 else -1)

## Player-held objective tiles that would hand the Coalition an objective victory at turn end
## (every bridgehead on Pitched maps, any Syndicate HQ on Offense maps). Empty if no such threat.
static func _imminent_defeat_tiles(grid_map: IsoGridMap, map_def: MapDefinition) -> Dictionary:
	var tiles: Dictionary = {} # Vector2i -> true, for O(1) has()
	match map_def.strategy_mode:
		MapDefinition.StrategyMode.PITCHED_BATTLE:
			for obj in map_def.objectives:
				var td: GridTileData = grid_map.get_tile(obj["pos"])
				if td == null or td.controlled_by != MechData.Faction.PLAYER:
					return {}
				tiles[td.coords] = true
		MapDefinition.StrategyMode.OFFENSE:
			for hq_pos in map_def.hq_positions:
				var td: GridTileData = grid_map.get_tile(hq_pos)
				if td != null and td.controlled_by == MechData.Faction.PLAYER:
					tiles[hq_pos] = true
	return tiles

## Objective tiles the AI should steer toward. Assaulting AIs (Defense / Pitched maps) home in on the
## objectives they don't hold yet, so one capture doesn't anchor the whole wave; the Offense garrison
## keeps measuring from every bunker it guards.
static func _objective_targets(grid_map: IsoGridMap, map_def: MapDefinition) -> Array[Vector2i]:
	var all_objs: Array[Vector2i] = []
	var unheld: Array[Vector2i] = []
	for obj in map_def.objectives:
		var opos: Vector2i = obj["pos"]
		all_objs.append(opos)
		var td: GridTileData = grid_map.get_tile(opos)
		if td != null and td.controlled_by != MechData.Faction.AI:
			unheld.append(opos)
	if map_def.strategy_mode == MapDefinition.StrategyMode.OFFENSE or unheld.is_empty():
		return all_objs
	return unheld

static func _score_positional_tile(
	tile: GridTileData,
	m_data: MechData,
	foe_positions: Array[Vector2i],
	map_def: MapDefinition,
	obj_targets: Array[Vector2i]
) -> float:
	if tile == null:
		return -999.0
	var score: float = 0.0

	# 1. Terrain Defense & Elevation value
	score += float(tile.get_defense_modifier_pct()) * 0.65
	score += float(tile.elevation) * 7.5
	if tile.terrain_type == GridTileData.TerrainType.RIVER:
		score -= 26.0 # Avoid stopping in exposed rivers!
	elif tile.terrain_type == GridTileData.TerrainType.CITY:
		score += 18.0
	elif tile.terrain_type == GridTileData.TerrainType.MOUNTAIN and m_data.mountain_gear:
		score += 16.0

	# 2. Objective Control value
	if tile.is_objective:
		if tile.controlled_by != MechData.Faction.AI:
			score += 52.0 # High priority to capture player/neutral objective cities!
		else:
			score += 24.0 # Good to garrison friendly objectives

	# 3. Distance to Player Units & Objectives based on Strategy Mode
	var min_enemy_dist: float = 999.0
	for fp in foe_positions:
		var d: float = float(absi(tile.coords.x - fp.x) + absi(tile.coords.y - fp.y))
		if d < min_enemy_dist:
			min_enemy_dist = d

	var min_obj_dist: float = 999.0
	for opos in obj_targets:
		var od: float = float(absi(tile.coords.x - opos.x) + absi(tile.coords.y - opos.y))
		if od < min_obj_dist:
			min_obj_dist = od

	match map_def.strategy_mode:
		MapDefinition.StrategyMode.DEFENSE:
			# On Defense map, AI is the assaulting wave -> push aggressively toward objectives & defenders!
			score -= min_obj_dist * 6.5
			score -= min_enemy_dist * 4.5
		MapDefinition.StrategyMode.OFFENSE:
			# On Offense map, AI is the defending garrison -> hold defensive line & stay near objectives
			score -= min_obj_dist * 7.0
			score -= min_enemy_dist * 2.2
			if map_def.hq_positions.has(tile.coords):
				score += 28.0
		_:
			# Pitched Battle -> balance closing on enemies & seizing central objectives
			score -= min_enemy_dist * 4.8
			score -= min_obj_dist * 3.8

	return score
