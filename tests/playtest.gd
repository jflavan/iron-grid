extends Node

## Automated Playtest Harness
## Plays complete missions on every map through the same entry points a human uses
## (tile clicks, WAIT/REFUEL, battle confirmation) while checking game-state invariants
## every frame, plus focused rule checks for fuel, pathfinding, FF-style turn-based combat and victory logic.
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
		await get_tree().create_timer(2.0).timeout
	get_tree().quit(mini(failures.size(), 125))

# =============================================================================
# RULE CHECKS
# =============================================================================
func _run_rule_checks() -> void:
	_check_fuel_costs()
	_check_pathfinding_matches_bruteforce()
	_check_skirmish_engine()
	await _check_victory_rules()
	_check_iron_bridge_layout()
	await _check_iron_bridge_holdouts_lose()
	await _check_tactical_bot_refaces()

func _tile(t: GridTileData.TerrainType, elev: int) -> GridTileData:
	return GridTileData.new(Vector2i.ZERO, t, elev)

func _check_fuel_costs() -> void:
	var std := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var heavy := GlobalState.create_mech_instance("goliath", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var falke := GlobalState.create_mech_instance("falke", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var donner := GlobalState.create_mech_instance("donner", MechData.Faction.PLAYER, "T", Vector2i.ZERO)
	var T := GridTileData.TerrainType
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.ROAD, 1)) == 2, "road costs 2")
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.PLAIN, 1)) == 4, "plain costs 4")
	_check(std.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 3)) == 14, "mountain 10 + 4 climb = 14")
	_check(std.get_step_fuel_cost(_tile(T.MOUNTAIN, 3), _tile(T.PLAIN, 1)) == 4, "descending is free of climb cost")
	_check(heavy.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.ROAD, 1)) == 2, "heavy pays no surcharge on road")
	_check(heavy.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.FOREST, 1)) == 8, "heavy pays +2 off-road")
	_check(falke.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.RIVER, 1)) == 4, "amphibious river 8-4")
	_check(falke.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.PLAIN, 1)) == 2, "light chassis -2 off-road")
	_check(donner.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 2)) == 6, "mountain gear: 10-4 +0 climb")
	_check(donner.get_step_fuel_cost(_tile(T.PLAIN, 1), _tile(T.MOUNTAIN, 3)) == 8, "mountain gear: 10-4 +2 climb")

func _check_pathfinding_matches_bruteforce() -> void:
	var grid := IsoGridMap.new()
	add_child(grid)
	for map_idx in GlobalState.maps.size():
		var map_def: MapDefinition = GlobalState.maps[map_idx]
		grid.load_from_definition(map_def)
		for chassis in ["vanguard", "goliath", "falke", "donner"]:
			var m := GlobalState.create_mech_instance(chassis, MechData.Faction.PLAYER, "T", Vector2i(1, 2))
			var reach: Dictionary = grid.find_reachable_tiles(m, {}).duplicate(true)
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
			_check(a.current_energy == a.max_energy and d.current_energy == d.max_energy, "forecast must not mutate energy")
			var res := SkirmishEngine.resolve_skirmish(a, d, flat, flat, true)
			_check(res.total_dmg_to_defender == fc["est_dmg_to_def"], "%s vs %s: forecast dmg matches deterministic result" % [a_id, d_id])
			_check(res.total_dmg_to_attacker == fc["est_dmg_to_atk"], "%s vs %s: forecast return dmg matches deterministic result" % [a_id, d_id])
			# Per-step damage must add up to the reported totals
			var atk_steps: int = 0
			var def_steps: int = 0
			for s in res.steps:
				if s.actor_side == "atk":
					atk_steps += s.damage_dealt
				else:
					def_steps += s.damage_dealt
				if s.is_support_only:
					_check(s.damage_dealt == 0, "%s support step deals 0 direct damage" % s.ability_id)
			_check(atk_steps == res.total_dmg_to_defender, "%s vs %s: step damage to defender sums to total" % [a_id, d_id])
			_check(def_steps == res.total_dmg_to_attacker, "%s vs %s: step damage to attacker sums to total" % [a_id, d_id])

	# Elevation: +12% FP / +10% Armor per level downhill; uphill costs -10% FP per level
	var va := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "A", Vector2i.ZERO)
	var vd := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "D", Vector2i.ZERO)
	var high := SkirmishEngine.resolve_skirmish(va, vd, _tile(T.PLAIN, 3), _tile(T.PLAIN, 1), false)
	_check(high.atk_effective_firepower == int(round(34 * 1.24)), "high ground: +24%% FP over 2 levels (got %d)" % high.atk_effective_firepower)
	_check(high.atk_effective_armor == int(round(30 * 1.25)), "high ground: +20%% armor + 5%% plain (got %d)" % high.atk_effective_armor)
	var low := SkirmishEngine.resolve_skirmish(va, vd, _tile(T.PLAIN, 1), _tile(T.PLAIN, 2), false)
	_check(low.atk_effective_firepower == int(round(34 * 0.90)), "uphill: -10%% FP (got %d)" % low.atk_effective_firepower)
	_check(low.atk_effective_armor == int(round(30 * 1.05)), "uphill: armor unaffected beyond terrain (got %d)" % low.atk_effective_armor)

	# Speed & Round 1 Initiative: Falke (SPD 34) always outspeeds Goliath (SPD 12), even when Goliath attacks on Round 1 (12+8=20 < 34)
	var gol := GlobalState.create_mech_instance("goliath", MechData.Faction.PLAYER, "G", Vector2i.ZERO)
	var flk := GlobalState.create_mech_instance("falke", MechData.Faction.AI, "F", Vector2i.ZERO)
	var sess_gf := SkirmishEngine.create_deterministic_session(gol, flk, flat, flat)
	_check(sess_gf.get_next_actor_side() == "def", "Falke defender (SPD 34) acts before Goliath attacker (SPD 12+8=20)")

	# Equal chassis: Round-1 Assault Initiative bonus lets Attacker act first
	var v1 := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "V1", Vector2i.ZERO)
	var v2 := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "V2", Vector2i.ZERO)
	var sess_vv := SkirmishEngine.create_deterministic_session(v1, v2, flat, flat)
	_check(sess_vv.get_next_actor_side() == "atk", "Attacker acts first on Round 1 when speeds are equal")

	# Interactive commands check: DEFEND halves incoming damage & restores +2 EN; Support TECH spends EN with 0 shot damage; RETREAT ends battle
	var p_mech := GlobalState.create_mech_instance("vanguard", MechData.Faction.PLAYER, "P", Vector2i.ZERO)
	var e_mech := GlobalState.create_mech_instance("vanguard", MechData.Faction.AI, "E", Vector2i.ZERO)
	p_mech.current_energy = 10
	var sess := SkirmishEngine.create_deterministic_session(p_mech, e_mech, flat, flat)
	var st_sup := sess.execute_next_turn(SkirmishEngine.CommandType.TECH, "krupp_plate")
	_check(st_sup.is_support_only and st_sup.damage_dealt == 0, "Sloped Krupp Plate is a pure FF support turn (0 damage)")
	_check(sess.atk_state.en == 6 and sess.atk_state.def_buff_pct == 35, "Sloped Krupp Plate costs 4 EN and grants +35%% DEF")
	var st_def := sess.execute_next_turn(SkirmishEngine.CommandType.DEFEND)
	_check(st_def.ability_category == "DEFEND" and sess.def_state.defending, "DEFEND command puts defender in guard stance")
	var st_ret := sess.execute_next_turn(SkirmishEngine.CommandType.RETREAT)
	_check(st_ret.escaped and sess.is_finished and sess.result.attacker_retreated, "RETREAT command disengages and finishes battle")

func _check_victory_rules() -> void:
	# PITCHED BATTLE: holding the majority of objectives at the turn limit wins
	var bf := await _spawn_battlefield(0)
	var objs: Array = bf.current_map_def.objectives
	for i in objs.size():
		bf.grid_map.get_tile(objs[i]["pos"]).controlled_by = 0 if i < 3 else 1
	GlobalState.turn_number = bf.current_map_def.turn_limit
	_check(bf._check_victory_conditions(true), "pitched: turn-limit check ends the game")
	_check(GlobalState.last_battle_winner == 0, "pitched: a 3-objective majority at turn limit is a player win")
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
		u.mech_data.has_attacked = true
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
	GlobalState.set_battle_seed(hash(policy) + map_idx)  # every battle roll in this mission replays exactly
	var last_skirmish_shown := false

	for frame in MAX_FRAMES_PER_MISSION:
		await get_tree().process_frame
		_check_invariants(bf, map_def)
		stats["max_turn"] = maxi(stats["max_turn"], GlobalState.turn_number)

		if GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER:
			break

		var modal: BattleScreen = bf.ui_overlay.skirmish_modal
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
			elif policy.begins_with("holdout"):
				_holdout_policy_step(bf, policy, stats)
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

# Iron Bridge must not be winnable by digging in and running out the clock. Five objectives rule out
# a 2-2 tie, the neutral Central Island Depot decides the default standoff, and every city sits level
# with the roads so a garrison can be assaulted without an uphill penalty.
const IRON_BRIDGE_CENTER := Vector2i(4, 4)
const IRON_BRIDGE_BANK_CITIES: Array[Vector2i] = [Vector2i(3, 1), Vector2i(6, 1), Vector2i(3, 6), Vector2i(6, 6)]

func _check_iron_bridge_layout() -> void:
	var m: MapDefinition = GlobalState.maps[0]
	_check(m.objectives.size() == 5, "iron bridge: five objectives, so the bridgeheads can't split 2-2 (got %d)" % m.objectives.size())
	var grid := IsoGridMap.new()
	grid.load_from_definition(m)
	var center: GridTileData = grid.get_tile(IRON_BRIDGE_CENTER)
	_check(center != null and center.is_objective and center.terrain_type == GridTileData.TerrainType.CITY,
		"iron bridge: the Central Island Depot at (4,4) is an objective city")
	_check(center != null and center.controlled_by == -1, "iron bridge: the Central Island Depot starts neutral")
	_check(center != null and center.elevation == 1, "iron bridge: the Central Island Depot is level with the bridges (height 1)")
	for c in IRON_BRIDGE_BANK_CITIES:
		var td: GridTileData = grid.get_tile(c)
		_check(td.terrain_type == GridTileData.TerrainType.CITY and td.elevation == 1,
			"iron bridge: bank city %s is level with the road (height %d)" % [c, td.elevation])
	grid.free()

## Both passive lines that used to win Iron Bridge must now lose it: holding the two western cities
## with the Falke and Donner parked on the corner mountains, and the same after grabbing the centre.
func _check_iron_bridge_holdouts_lose() -> void:
	for policy in ["holdout", "holdout_center"]:
		await _play_mission(0, policy)
		_check(GlobalState.last_battle_winner == 1,
			"iron bridge: the passive '%s' line loses (%s)" % [policy, GlobalState.last_battle_reason])

## The balance bot must reface like the Syndicate AI does after its moves, through the player's own
## rotate action, or bot win rates understate a player under the facing rules.
func _check_tactical_bot_refaces() -> void:
	var bf := await _spawn_battlefield(0)
	var iron: MechUnit = null
	for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
		if u.mech_data.callsign.begins_with("IRON-1"):
			iron = u
	iron.mech_data.has_moved = true
	iron.mech_data.has_attacked = true
	iron.mech_data.facing = Vector2i(0, 1)
	bf._select_unit(iron)
	var want := AIController.choose_best_facing(iron.mech_data.grid_pos, bf.unit_container.get_faction_units(MechData.Faction.AI))
	_check(want != Vector2i(0, 1), "precondition: IRON-1 starts facing away from the nearest Syndikat walker")
	var bot: Object = load("res://tests/TacticalBot.gd").new()
	_check(bot.has_method("reface_step"), "TacticalBot has a reface_step for the player rotate action")
	var steps := 0
	while steps < 6 and bot.has_method("reface_step") and bot.call("reface_step", bf):
		steps += 1
	_check(iron.mech_data.facing == want, "TacticalBot refaces an ordered walker toward the nearest Syndikat walker (%s, want %s)" % [iron.mech_data.facing, want])
	_check(steps > 0 and steps <= 3, "refacing takes 1-3 rotate actions (took %d)" % steps)
	_check(not bot.call("reface_step", bf) if bot.has_method("reface_step") else false, "reface_step reports nothing left to do once facing the threat")
	await _free_battlefield(bf)

const HOLDOUT_POSTS :={"TITAN-2": Vector2i(3, 6), "IRON-1": Vector2i(3, 1), "SWIFT-3": Vector2i(1, 7), "CRAG-4": Vector2i(1, 0)}

## Moves each walker to its post once, then only ever WAITs. Never attacks.
func _holdout_policy_step(bf: Battlefield, policy: String, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.is_order_complete():
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.is_order_complete():
				bf._select_unit(u)
				return
		return
	var m := sel.mech_data
	if m.has_moved:
		bf._on_wait_refuel_requested()
		return
	var post: Vector2i = HOLDOUT_POSTS.get(m.callsign.get_slice(" ", 0), m.grid_pos)
	if policy == "holdout_center" and m.callsign.begins_with("SWIFT-3"):
		post = IRON_BRIDGE_CENTER
	var info: Dictionary = bf.grid_map.reachable_info.get(post, {})
	if post != m.grid_pos and not info.is_empty() and not info["is_attack"]:
		stats["moves"] += 1
		bf._on_tile_clicked(post, null)
	else:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()

func _turtle_policy_step(bf: Battlefield, stats: Dictionary) -> void:
	if GlobalState.turn_number % 2 == 0:
		stats["waits"] += 1
		bf._on_end_turn_requested()
		return
	var sel: MechUnit = bf.selected_unit
	if sel != null and sel.mech_data.faction == MechData.Faction.PLAYER and not sel.mech_data.is_order_complete():
		stats["waits"] += 1
		bf._on_wait_refuel_requested()

func _random_policy_step(bf: Battlefield, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.is_order_complete():
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.is_order_complete():
				bf._on_tile_clicked(u.mech_data.grid_pos, null)
				return
		return
	var options: Array = bf.grid_map.reachable_info.keys()
	options.erase(sel.mech_data.grid_pos)
	if options.is_empty() or _rng.randf() < 0.15:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()
		return
	stats["moves"] += 1
	bf._on_tile_clicked(options[_rng.randi_range(0, options.size() - 1)], null)

func _player_policy_step(bf: Battlefield, map_def: MapDefinition, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.is_order_complete():
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.is_order_complete():
				bf._on_tile_clicked(u.mech_data.grid_pos, null)
				return
		return

	var m := sel.mech_data
	var reach: Dictionary = bf.grid_map.reachable_info
	var best_pos := Vector2i(-1, -1)
	var best_score: float = -INF

	var targets: Array[Vector2i] = []
	for obj in map_def.objectives:
		if bf.grid_map.get_tile(obj["pos"]).controlled_by != 0:
			targets.append(obj["pos"])
	var enemies := bf.unit_container.get_faction_units(MechData.Faction.AI)
	for e in enemies:
		targets.append(e.mech_data.grid_pos)

	var here_dist: float = _nearest(m.grid_pos, targets)
	for pos in reach.keys():
		if pos == m.grid_pos:
			continue
		var info: Dictionary = reach[pos]
		var score: float
		if info["is_attack"]:
			var target := bf.unit_container.get_unit_at(pos, sel)
			var fc := SkirmishEngine.compute_forecast(m, target.mech_data, bf.grid_map.get_tile(m.grid_pos), bf.grid_map.get_tile(pos))
			score = 20.0 + float(fc["est_dmg_to_def"] - fc["est_dmg_to_atk"])
			if fc["est_dmg_to_atk"] >= m.current_armor:
				score -= 200.0
		else:
			score = (here_dist - _nearest(pos, targets)) * 6.0 - float(info["fuel_spent"]) * 0.5
			var td := bf.grid_map.get_tile(pos)
			if td.is_objective and td.controlled_by != 0:
				score += 40.0
			# Check if moving to `pos` puts `m` adjacent to an enemy it can immediately attack with remaining fuel
			for e in enemies:
				var epos: Vector2i = e.mech_data.grid_pos
				if absi(epos.x - pos.x) + absi(epos.y - pos.y) == 1:
					var etile := bf.grid_map.get_tile(epos)
					var atk_fuel: int = m.get_step_fuel_cost(td, etile)
					if int(info["fuel_spent"]) + atk_fuel <= m.current_fuel:
						var fc2 := SkirmishEngine.compute_forecast(m, e.mech_data, td, etile)
						var atk_sc: float = 20.0 + float(fc2["est_dmg_to_def"] - fc2["est_dmg_to_atk"])
						if fc2["est_dmg_to_atk"] < m.current_armor and atk_sc > score:
							score = atk_sc
		if score > best_score:
			best_score = score
			best_pos = pos

	if best_pos != Vector2i(-1, -1) and best_score > 0.0:
		stats["moves"] += 1
		bf._on_tile_clicked(best_pos, null)
	else:
		stats["waits"] += 1
		bf._on_wait_refuel_requested()

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
		_check(m.current_energy >= 0 and m.current_energy <= m.max_energy, "%s energy %d within [0,%d]" % [m.callsign, m.current_energy, m.max_energy])
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
