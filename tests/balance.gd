extends "res://tests/playtest.gd"
## Entrenchment / City-healing balance experiment.
## Run:  BALANCE_VARIANT=full BALANCE_POLICIES=tactical:1,tactical:2 BALANCE_MAPS=0,1,2 \
##         godot --headless --path . res://tests/Balance.tscn > out_full.log
## Then: python3 tests/analyze_balance.py out_*.log
## Env:
##   BALANCE_VARIANT = full | none_both | none_ai | none_player | no_patch | no_combat |
##                     double_both | double_player | no_upkeep | no_city_heal | no_city_heal_ai
##   BALANCE_POLICIES = comma list (tactical, tactical:N, greedy, holder, turtle, random:N)
##   BALANCE_MAPS = comma list of map indices
## Prints one "[BALANCE] {json}" line per mission.

func _ready() -> void:
	Engine.time_scale = 12.0
	BalanceProbe.enabled = true
	var variant := OS.get_environment("BALANCE_VARIANT")
	if variant == "": variant = "full"
	match variant:
		"none_both":
			BalanceProbe.def_pct = [0, 0]; BalanceProbe.patch = [0, 0]
		"none_ai":
			BalanceProbe.def_pct = [15, 0]; BalanceProbe.patch = [8, 0]
		"none_player":
			BalanceProbe.def_pct = [0, 15]; BalanceProbe.patch = [0, 8]
		"no_patch":
			BalanceProbe.patch = [0, 0]
		"double_both":
			BalanceProbe.def_pct = [30, 30]; BalanceProbe.patch = [16, 16]
		"double_player":
			BalanceProbe.def_pct = [30, 15]; BalanceProbe.patch = [16, 8]
		"no_upkeep":
			BalanceProbe.upkeep = [0, 0]
		"no_city_heal":
			BalanceProbe.upkeep = [0, 0]; BalanceProbe.patch = [0, 0]
		"no_city_heal_ai":
			BalanceProbe.upkeep = [12, 0]; BalanceProbe.patch = [8, 0]
		"no_combat":
			BalanceProbe.def_pct = [0, 0]
	await get_tree().process_frame
	var policies := OS.get_environment("BALANCE_POLICIES").split(",")
	var maps := OS.get_environment("BALANCE_MAPS").split(",")
	for policy in policies:
		for mi in maps:
			await _run_one(int(mi), policy, variant)
	print("[BALANCE-DONE] invariant failures=%d" % failures.size())
	for f in failures.slice(0, 10):
		print("  FAIL: " + f)
	get_tree().quit(0)

func _run_one(map_idx: int, policy: String, variant: String) -> void:
	BalanceProbe.reset()
	var bf := await _spawn_battlefield(map_idx)
	var map_def: MapDefinition = bf.current_map_def
	var stats := { "moves": 0, "waits": 0, "skirmishes": 0, "max_turn": 1 }
	_rng.seed = hash(policy) + map_idx
	GlobalState.set_battle_seed(hash(policy) + map_idx)  # every battle roll in this mission replays exactly
	TacticalBot.jitter = 30.0
	if policy.begins_with("tactical:"):
		TacticalBot.jitter = 30.0
		TacticalBot.rng.seed = int(policy.split(":")[1]) * 7919 + map_idx
	for frame in MAX_FRAMES_PER_MISSION:
		await get_tree().process_frame
		_check_invariants(bf, map_def)
		if GlobalState.current_phase == GlobalState.TurnPhase.GAME_OVER:
			break
		var modal: BattleScreen = bf.ui_overlay.skirmish_modal
		if modal.visible:
			if modal._all_steps_done: modal._on_confirm_pressed()
			else: modal._on_skip_pressed()
			continue
		if GlobalState.current_phase == GlobalState.TurnPhase.PLAYER_PHASE and not bf._is_animating_move:
			if policy == "turtle": _turtle_policy_step(bf, stats)
			elif policy == "holder": _holder_policy_step(bf, map_def, stats)
			elif policy.begins_with("tactical"): _tactical_policy_step(bf, map_def, stats)
			elif policy.begins_with("random"): _random_policy_step(bf, stats)
			else: _player_policy_step(bf, map_def, stats)
	var side := func(f):
		var n := 0; var hp := 0; var mx := 0
		for u in bf.unit_container.get_faction_units(f):
			n += 1; hp += u.mech_data.current_armor; mx += u.mech_data.max_armor
		return [n, hp, mx]
	var p: Array = side.call(MechData.Faction.PLAYER)
	var a: Array = side.call(MechData.Faction.AI)
	var p_objs := 0
	for obj in map_def.objectives:
		if bf.grid_map.get_tile(obj["pos"]).controlled_by == 0: p_objs += 1
	var out := {
		"variant": variant, "map": map_idx, "policy": policy,
		"winner": "PLAYER" if GlobalState.last_battle_winner == 0 else "AI",
		"reason": GlobalState.last_battle_reason, "turns": GlobalState.turn_number,
		"p_alive": p[0], "p_hp": p[1], "a_alive": a[0], "a_hp": a[1], "p_objs": p_objs, "tot_objs": map_def.objectives.size(),
		"entrench": BalanceProbe.entrench_actions, "patch_heal": BalanceProbe.patch_healed, "upkeep_heal": BalanceProbe.upkeep_healed,
		"skirmishes": BalanceProbe.skirmishes,
	}
	print("[BALANCE] " + JSON.stringify(out))
	await _free_battlefield(bf)

## Holder commander: greedy, but a walker standing on a player-held objective digs in
## (entrenches) unless it has a clearly favourable attack available.
func _holder_policy_step(bf: Battlefield, map_def: MapDefinition, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel != null and sel.mech_data.faction == MechData.Faction.PLAYER and not sel.mech_data.has_moved:
		var td := bf.grid_map.get_tile(sel.mech_data.grid_pos)
		if td.is_objective and td.controlled_by == 0:
			var good_attack := false
			for pos in bf.grid_map.reachable_info.keys():
				var info: Dictionary = bf.grid_map.reachable_info[pos]
				if not info["is_attack"]: continue
				var target := bf.unit_container.get_unit_at(pos, sel)
				var path: Array = info["path"]
				var fc := SkirmishEngine.compute_forecast(sel.mech_data, target.mech_data, bf.grid_map.get_tile(path[path.size() - 2]), bf.grid_map.get_tile(pos))
				if fc["est_dmg_to_def"] >= target.mech_data.current_armor and fc["est_dmg_to_atk"] < sel.mech_data.current_armor:
					good_attack = true
			if not good_attack:
				stats["waits"] += 1
				bf._on_wait_refuel_requested()
				return
	_player_policy_step(bf, map_def, stats)

## Competent commander: mirrors the Syndicate AI's scoring (TacticalBot) through the human click flow.
func _tactical_policy_step(bf: Battlefield, map_def: MapDefinition, stats: Dictionary) -> void:
	var sel: MechUnit = bf.selected_unit
	if sel == null or sel.mech_data.faction != MechData.Faction.PLAYER or sel.mech_data.has_moved:
		for u in bf.unit_container.get_faction_units(MechData.Faction.PLAYER):
			if not u.mech_data.has_moved:
				bf._on_tile_clicked(u.mech_data.grid_pos, null)
				return
		return
	var d := TacticalBot.choose_best_action(sel, bf.grid_map, bf.unit_container, map_def)
	bf._select_unit(sel) # decision scoring cleared the highlights; restore the click targets
	if d["type"] == "WAIT_ENTRENCH" or not bf.grid_map.reachable_info.has(d["target_pos"]):
		stats["waits"] += 1
		bf._on_wait_refuel_requested()
	else:
		stats["moves"] += 1
		bf._on_tile_clicked(d["target_pos"], null)
