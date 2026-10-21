extends Node

## Automated Playtest Harness
## Plays complete missions on every map through the same entry points a human uses
## (tile clicks, WAIT/REFUEL, skirmish confirmation) while checking game-state invariants
## every frame, plus focused rule checks for fuel, pathfinding, skirmishes and victory logic.
##
## Run headless:  godot --headless --path . res://tests/Playtest.tscn
## Exit code is the number of failures (0 = all checks passed).
## Env: PLAYTEST_POLICIES=greedy,turtle,random:1 (subset of commanders), PLAYTEST_VERBOSE=1 (print combat log).

const BATTLEFIELD_SCENE := preload("res://scenes/Battlefield.tscn")
const MAX_FRAMES_PER_MISSION: int = 60000

var failures: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _failure_seen: Dictionary = {}
var _check_count: int = 0

func _ready() -> void:
	if OS.get_environment("PLAYTEST_VERBOSE") != "":
		GlobalState.log_added.connect(func(entry: String): print("    LOG " + entry))
	Engine.time_scale = 12.0
	await get_tree().process_frame
	await _run_rule_checks()
	var policies: PackedStringArray = ["greedy", "turtle", "random:1", "random:2", "random:3", "random:4"]
	if OS.get_environment("PLAYTEST_POLICIES") != "":
		policies = OS.get_environment("PLAYTEST_POLICIES").split(",")
	for policy in policies:
		for map_idx in GlobalState.maps.size():
			await _play_mission(map_idx, policy)
	_report_and_quit()

func _check(cond: bool, msg: String) -> void:
	_check_count += 1
	if not cond and not _failure_seen.has(msg):
		_failure_seen[msg] = true
		failures.append(msg)
		push_error("[PLAYTEST FAIL] " + msg)

func _report_and_quit() -> void:
	print("[PLAYTEST] %d checks, %d failures" % [_check_count, failures.size()])
	for f in failures.slice(0, 40):
		print("  FAIL: " + f)
	Engine.time_scale = 1.0
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(2.0).timeout # let attached debuggers (e.g. the Godot MCP) read the summary
	get_tree().quit(mini(failures.size(), 125))

# =============================================================================
# RULE CHECKS
# =============================================================================
func _run_rule_checks() -> void:
	_check_fuel_costs()
	_check_pathfinding_matches_bruteforce()
	_check_skirmish_engine()
	await _check_victory_rules()

func _tile(t: GridTileData.TerrainType, elev: int) -> GridTileData:
	return GridTileData.new(Vector2i.ZERO, t, elev)

func _check_fuel_costs() -> void:
	var std := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var heavy := GlobalState.create_mech_instance("goliath", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var falke := GlobalState.create_mech_instance("falke", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var donner := GlobalState.create_mech_instance("donner", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var T := GridTileData.TerrainType
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.ROAD, 1)) == 1, "road costs 1")
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.PLAIN, 1)) == 2, "plain costs 2")
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 3)) == 7, "mountain 5 + 2 climb = 7")
	_check(std.get_step_fuel_cost(_tile(T.MOUNTAIN, 3), _tile(T.PLAIN, 1)) == 2, "descending is free of climb cost")
	_check(heavy.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.ROAD, 1)) == 1, "heavy pays no surcharge on road")
	_check(heavy.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.FOREST, 1)) == 4, "heavy pays +1 off-road")
	_check(falke.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.RIVER, 1)) == 2, "amphibious river 4-2")
	_check(falke.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.PLAIN, 1)) == 1, "light chassis -1 off-road")
	_check(donner.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 2)) == 3, "mountain gear: 5-2 +0 climb")
	_check(donner.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 3)) == 4, "mountain gear: 5-2 +1 climb")

func _check_pathfinding_matches_bruteforce() -> void:
	var grid := IsoGridMap.new()
	add_child(grid)
	for map_idx in GlobalState.maps.size():
		var map_def: MapDefinition = GlobalState.maps[map_idx]
		grid.load_from_definition(map_def)
		for chassis in ["vanguard", "goliath", "falke", "donner"]:
			var m := GlobalState.create_mech_instance(chassis, MechData.Faction.PLAYER, "T", Vector2i(1, 2))
			var reach: Dictionary = grid.compute_reachable_tiles(m, {}).duplicate(true)
			# Bellman-Ford style relaxation gives the true minimum cost to every tile
			var best: Dictionary = { m.grid_pos: 0 }
			var changed := true
			while changed:
				changed = false
				for pos in best.keys():
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nxt: Vector2i = pos + d
						if not grid.is_valid_coords(nxt):
							continue
						var c: int = best[pos] + m.get_step_fuel_cost(grid.get_tile(pos), grid.get_tile(nxt))
						if c <= m.current_fuel and (not best.has(nxt) or c < best[nxt]):
							best[nxt] = c
							changed = true
			_check(reach.size() == best.size(), "map %d %s: reachable count %d vs optimal %d" % [map_idx, chassis, reach.size(), best.size()])
			for pos in best.keys():
				if reach.has(pos):
					_check(reach[pos]["fuel_spent"] == best[pos], "map %d %s: cost to %s is optimal" % [map_idx, chassis, pos])
					var path: Array = reach[pos]["path"]
					var walked: int = 0
					for i in range(1, path.size()):
						walked += m.get_step_fuel_cost(grid.get_tile(path[i - 1]), grid.get_tile(path[i]))
					_check(walked == reach[pos]["fuel_spent"], "map %d %s: path to %s sums to its cost" % [map_idx, chassis, pos])
	grid.queue_free()

func _check_skirmish_engine() -> void:
	var T := GridTileData.TerrainType
	var flat := _tile(T.PLAIN, 1)
	for a_id in GlobalState.chassis_catalog.keys():
		for d_id in GlobalState.chassis_catalog.keys():
			var a := GlobalState.create_mech_instance(a_id, MechData.Faction.PLAYER, "A", Vector2i.ZERO)
			var d := GlobalState.create_mech_instance(d_id, MechData.Faction.AI, "D", Vector2i.ZERO)
			var fc := SkirmishEngine.compute_forecast(a, d, flat, flat)
			_check(a.current_armor == a.max_armor and d.current_armor == d.max_armor, "forecast must not mutate units")
			var res := SkirmishEngine.resolve_skirmish(a, d, flat, flat, true)
			_check(res.total_dmg_to_defender == fc["est_dmg_to_def"], "%s vs %s: forecast dmg matches result" % [a_id, d_id])
			_check(res.total_dmg_to_attacker == fc["est_dmg_to_atk"], "%s vs %s: forecast return dmg matches result" % [a_id, d_id])
			_check(res.atk_cards_held + res.def_cards_held == 6, "six cards on board")
			# Animated per-step damage must add up to the reported totals (no bar jumping back up at the end)
			var atk_steps: int = 0
			var def_steps: int = 0
			for s in res.steps:
				atk_steps += s.atk_damage_dealt
				def_steps += s.def_damage_dealt
			_check(atk_steps == res.total_dmg_to_defender, "%s vs %s: step damage to defender sums to total" % [a_id, d_id])
			_check(def_steps == res.total_dmg_to_attacker, "%s vs %s: step damage to attacker sums to total" % [a_id, d_id])
			# Every placement after the opening card must contest at least one opposing card
			var occupied: Array[int] = []
			for i in res.steps.size():
				var s: SkirmishEngine.BoutStep = res.steps[i]
				if i > 0:
					var touches_enemy := false
					for nb in _neighbors(s.slot_index):
						if occupied.has(nb) and _slot_side(res.steps, nb) != s.actor_faction:
							touches_enemy = true
					_check(touches_enemy, "placement %d (slot %d) contests an opposing card" % [i, s.slot_index])
				occupied.append(s.slot_index)

	# Elevation: +12% FP / +10% Armor / +1 card rank per level downhill; uphill costs FP and ranks only
	var va := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A", Vector2i.ZERO)
	var vd := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "D", Vector2i.ZERO)
	var high := SkirmishEngine.resolve_skirmish(va, vd, _tile(T.PLAIN, 3), _tile(T.PLAIN, 1), false)
	_check(high.atk_effective_firepower == int(round(34 * 1.24)), "high ground: +24%% FP over 2 levels (got %d)" % high.atk_effective_firepower)
	_check(high.atk_effective_armor == int(round(30 * 1.25)), "high ground: +20%% armor + 5%% plain (got %d)" % high.atk_effective_armor)
	_check(high.atk_card_edge_mod >= 2, "high ground: at least +2 card ranks (plus any stat overmatch)")
	var low := SkirmishEngine.resolve_skirmish(va, vd, _tile(T.PLAIN, 1), _tile(T.PLAIN, 2), false)
	_check(low.atk_effective_firepower == int(round(34 * 0.90)), "uphill: -10%% FP (got %d)" % low.atk_effective_firepower)
	_check(low.atk_effective_armor == int(round(30 * 1.05)), "uphill: armor unaffected beyond terrain (got %d)" % low.atk_effective_armor)
	_check(low.atk_card_edge_mod == -1, "uphill: -1 card rank")

	# Attacker should be able to capture defender cards when it badly outranks them
	var strong := GlobalState.create_mech_instance("moloch", MechData.Faction.PLAYER, "A", Vector2i.ZERO)
	var weak := GlobalState.create_mech_instance("falke", MechData.Faction.AI, "D", Vector2i.ZERO)
	for c in strong.deck:
		c.top = 10; c.right = 10; c.bottom = 10; c.left = 10
	for c in weak.deck:
		c.top = 1; c.right = 1; c.bottom = 1; c.left = 1
	var r2 := SkirmishEngine.resolve_skirmish(strong, weak, flat, flat, false)
	_check(_flips_by(r2, strong.faction) >= 2, "dominant attacker overmatches defender cards (flipped %d)" % _flips_by(r2, strong.faction))
	var r3 := SkirmishEngine.resolve_skirmish(weak, strong, flat, flat, false)
	_check(_flips_by(r3, strong.faction) >= 2, "dominant defender overmatches attacker cards (flipped %d)" % _flips_by(r3, strong.faction))

func _flips_by(res: SkirmishEngine.SkirmishResult, faction: int) -> int:
	var n: int = 0
	for s in res.steps:
		if s.actor_faction == faction:
			n += s.flipped_slots.size()
	return n

func _neighbors(idx: int) -> Array[int]:
	var out: Array[int] = []
	@warning_ignore("integer_division")
	var r: int = idx / 3
	var c: int = idx % 3
	if r > 0: out.append(idx - 3)
	if r < 2: out.append(idx + 3)
	if c > 0: out.append(idx - 1)
	if c < 2: out.append(idx + 1)
	return out

func _slot_side(steps: Array[SkirmishEngine.BoutStep], slot: int) -> int:
	for s in steps:
		if s.slot_index == slot:
			return s.actor_faction
	return -1

func _check_victory_rules() -> void:
	# PITCHED BATTLE: holding the majority of objectives at the turn limit wins
	var bf := await _spawn_battlefield(0)
	var objs: Array = bf.current_map_def.objectives
	for i in objs.size():
		bf.grid_map.get_tile(objs[i]["pos"]).controlled_by = 0 if i < 3 else 1
	GlobalState.turn_number = bf.current_map_def.turn_limit
	_check(bf._check_victory_conditions(true), "pitched: turn-limit check ends the game")
	_check(GlobalState.last_battle_winner == 0, "pitched: 3/4 objectives at turn limit is a player win")
	await _free_battlefield(bf)

	# DEFENSE: losing every citadel node at turn end is a defeat
	bf = await _spawn_battlefield(1)
	for obj in bf.current_map_def.objectives:
		bf.grid_map.get_tile(obj["pos"]).controlled_by = 1
	_check(not bf._check_victory_conditions(false), "defense: overrun mid-turn does not end the game yet")
	_check(bf._check_victory_conditions(true), "defense: losing all citadel nodes at turn end ends the game")
	_check(GlobalState.last_battle_winner == 1, "defense: losing all citadel nodes is a defeat")
	await _free_battlefield(bf)

	# OFFENSE: an HQ capture only wins once it has been held through the Syndicate phase
	bf = await _spawn_battlefield(2)
	bf.grid_map.get_tile(bf.current_map_def.hq_positions[1]).controlled_by = 0
	_check(not bf._check_victory_conditions(false), "offense: HQ capture mid-turn does not end the game yet")
	_check(bf._check_victory_conditions(true), "offense: HQ held at turn end ends the game")
	_check(GlobalState.last_battle_winner == 0, "offense: HQ held at turn end is a victory")
	await _free_battlefield(bf)

	# PITCHED BATTLE: total control likewise has to survive the enemy phase
	bf = await _spawn_battlefield(0)
	for obj in bf.current_map_def.objectives:
		bf.grid_map.get_tile(obj["pos"]).controlled_by = 0
	_check(not bf._check_victory_conditions(false), "pitched: total control mid-turn does not end the game yet")
	_check(bf._check_victory_conditions(true) and GlobalState.last_battle_winner == 0, "pitched: total control at turn end is a victory")
	await _free_battlefield(bf)

	# Annihilation in either direction
	bf = await _spawn_battlefield(0)
	for u in bf.unit_container.get_faction_units(MechData.Faction.AI):
		bf.unit_container.remove_destroyed_unit(u)
	_check(bf._check_victory_conditions(false) and GlobalState.last_battle_winner == 0, "annihilating the Syndicate is a victory")
	await _free_battlefield(bf)

	# Game over must freeze the turn flow (no pending timers may start a new phase)
	bf = await _spawn_battlefield(0)
	for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
		u.mech_data.has_moved = true
	bf._check_auto_advance_player_phase()
	bf._declare_game_over(0, "test")
	for i in 120:
		await get_tree().process_frame
	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER, "pending auto-advance timer must not leave GAME_OVER")
	# Redeploying must fully reset turn state
	bf._on_restart_mission_requested()
	for i in 120:
		await get_tree().process_frame
	_check(GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE, "redeploy returns to the player phase")
	_check(GlobalState.turn_number == 1, "redeploy resets the turn counter")
	await _free_battlefield(bf)

func _spawn_battlefield(map_idx: int) -> Battlefield:
	GlobalState.selected_map_index = map_idx
	var bf: Battlefield = BATTLEFIELD_SCENE.instantiate()
	add_child(bf)
	await get_tree().process_frame
	return bf

func _free_battlefield(bf: Battlefield) -> void:
	bf.queue_free()
	await get_tree().process_frame

# =============================================================================
# FULL MISSION PLAYTHROUGHS
# =============================================================================
func _play_mission(map_idx: int, policy: String) -> void:
	var bf := await _spawn_battlefield(map_idx)
	var map_def: MapDefinition = bf.current_map_def
	var stats := { "moves": 0, "waits": 0, "skirmishes": 0, "max_turn": 1 }
	_rng.seed = hash(policy) + map_idx
	var last_skirmish_shown := false

	for frame in MAX_FRAMES_PER_MISSION:
		await get_tree().process_frame
		_check_invariants(bf, map_def)
		stats["max_turn"] = maxi(stats["max_turn"], GlobalState.turn_number)

		if GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER:
			break

		var modal: SkirmishModal = bf.ui_overlay.skirmish_modal
		if modal.visible:
			if not last_skirmish_shown:
				stats["skirmishes"] += 1
				last_skirmish_shown = true
			if modal._all_steps_done:
				modal._on_confirm_pressed()
			else:
				modal._on_skip_pressed()
			continue
		last_skirmish_shown = false

		if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not bf._is_animating_move:
			if policy == "turtle":
				_turtle_policy_step(bf, stats)
			elif policy.begins_with("random"):
				_random_policy_step(bf, stats)
			else:
				_player_policy_step(bf, map_def, stats)

	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER, "map %d: mission reaches a conclusion" % map_idx)
	_check(GlobalState.turn_number <= map_def.turn_limit, "map %d: game ends by the turn limit (turn %d)" % [map_idx, GlobalState.turn_number])
	var turn_at_end: int = GlobalState.turn_number
	for i in 90:
		await get_tree().process_frame
	_check(GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER and GlobalState.turn_number == turn_at_end, "map %d: nothing advances after game over" % map_idx)

	print("[PLAYTEST] %s map %d %s -> winner=%s turns=%d moves=%d waits=%d skirmishes=%d reason=\"%s\"" % [
		policy, map_idx, map_def.map_name, "PLAYER" if GlobalState.last_battle_winner == 0 else "AI",
		GlobalState.turn_number, stats["moves"], stats["waits"], stats["skirmishes"], GlobalState.last_battle_reason
	])
	await _free_battlefield(bf)

## Turtle commander: entrench every walker in place on odd turns, and just hit END TURN on even
## turns, exercising the refuel/repair upkeep and the turn-limit victory rules.
func _turtle_policy_step(bf: Battlefield, stats: Dictionary) -> void:
	if GlobalState.turn_number % 2 == 0:
		stats["waits"] += 1
		bf._on_end_turn_requested()
		return
	var sel: MechUnit = bf.selected_unit
	if sel != null and sel.mech_data.faction == MechData.Faction.PLAYER and not sel.mech_data.has_moved:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()

## Random commander (seeded): clicks a random reachable tile (move or attack) or entrenches,
## fuzzing movement, collisions, pushbacks and retreats across many board states.
func _random_policy_step(bf: Battlefield, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.has_moved:
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.has_moved:
				_click_tile(bf, u.mech_data.grid_pos)
				return
		return
	var options: Array = bf.grid_map.reachable_info.keys()
	options.erase(sel.mech_data.grid_pos)
	if options.is_empty() or _rng.randf() < 0.15:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()
		return
	stats["moves"] += 1
	_click_tile(bf, options[_rng.randi_range(0, options.size() - 1)])

## Greedy commander: take favourable fights, otherwise advance on the nearest
## objective not yet held (or the nearest enemy), entrenching if nothing useful is in reach.
func _player_policy_step(bf: Battlefield, map_def: MapDefinition, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.has_moved:
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.has_moved:
				_click_tile(bf, u.mech_data.grid_pos)
				return
		return # everyone has moved; auto-advance timer will start the AI phase

	var m := sel.mech_data
	var reach: Dictionary = bf.grid_map.reachable_info
	var best_pos := Vector2i(-1, -1)
	var best_score: float = -INF

	var targets: Array[Vector2i] = []
	for obj in map_def.objectives:
		if bf.grid_map.get_tile(obj["pos"]).controlled_by != 0:
			targets.append(obj["pos"])
	for e in bf.unit_container.get_faction_units(MechData.Faction.AI):
		targets.append(e.mech_data.grid_pos)

	var here_dist: float = _nearest(m.grid_pos, targets)
	for pos in reach.keys():
		if pos == m.grid_pos:
			continue
		var info: Dictionary = reach[pos]
		var score: float
		if info["is_attack"]:
			var target := bf.unit_container.get_unit_at(pos, sel)
			var path: Array = info["path"]
			var fc := SkirmishEngine.compute_forecast(m, target.mech_data, bf.grid_map.get_tile(path[path.size() - 2]), bf.grid_map.get_tile(pos))
			score = 20.0 + float(fc["est_dmg_to_def"] - fc["est_dmg_to_atk"])
			if fc["est_dmg_to_atk"] >= m.current_armor:
				score -= 200.0
		else:
			score = (here_dist - _nearest(pos, targets)) * 6.0 - float(info["fuel_spent"]) * 0.5
			var td := bf.grid_map.get_tile(pos)
			if td.is_objective and td.controlled_by != 0:
				score += 40.0
		if score > best_score:
			best_score = score
			best_pos = pos

	if best_pos != Vector2i(-1, -1) and best_score > 0.0:
		stats["moves"] += 1
		_click_tile(bf, best_pos)
	else:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()

## Clicks a tile the way a real cursor does: the pointer hovers the tile (path preview) before the click lands.
func _click_tile(bf: Battlefield, coords: Vector2i) -> void:
	bf.grid_map.update_hover(bf.grid_map.grid_to_screen(coords, true))
	bf._on_tile_clicked(coords, bf.grid_map.get_tile(coords))

func _nearest(from: Vector2i, targets: Array[Vector2i]) -> float:
	var best: float = 999.0
	for t in targets:
		best = minf(best, float(absi(from.x - t.x) + absi(from.y - t.y)))
	return best

func _check_invariants(bf: Battlefield, map_def: MapDefinition) -> void:
	var phase := GlobalState.current_phase
	var settled: bool = (phase == GlobalState.TurnPhase.PLAYER_PHASE or phase == GlobalState.TurnPhase.AI_PHASE) \
		and not bf._is_animating_move and not bf.ui_overlay.skirmish_modal.visible
	var seen: Dictionary = {}
	for u in bf.unit_container.units:
		if not is_instance_valid(u) or not u.mech_data.is_alive():
			continue
		var m := u.mech_data
		_check(m.current_fuel >= 0 and m.current_fuel <= m.max_fuel, "%s fuel %d within [0,%d]" % [m.callsign, m.current_fuel, m.max_fuel])
		_check(m.current_armor >= 0 and m.current_armor <= m.max_armor, "%s armor %d within [0,%d]" % [m.callsign, m.current_armor, m.max_armor])
		_check(bf.grid_map.is_valid_coords(m.grid_pos), "%s on a valid tile %s" % [m.callsign, m.grid_pos])
		if settled:
			_check(not seen.has(m.grid_pos), "%s shares tile %s with %s" % [m.callsign, m.grid_pos, seen.get(m.grid_pos, "")])
			seen[m.grid_pos] = m.callsign
			if not u._is_walking:
				var expected: Vector2 = bf.grid_map.grid_to_screen(m.grid_pos, true)
				_check(u.position.distance_to(expected) < 1.0, "%s drawn at its grid tile %s" % [m.callsign, m.grid_pos])
	for pos in bf.grid_map.reachable_info.keys():
		var info: Dictionary = bf.grid_map.reachable_info[pos]
		_check(info.has("is_attack") and info.has("path") and info.has("fuel_spent"), "reachable entry %s is intact" % pos)
	_check(GlobalState.turn_number <= map_def.turn_limit, "turn %d exceeds limit %d" % [GlobalState.turn_number, map_def.turn_limit])
