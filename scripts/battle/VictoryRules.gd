class_name VictoryRules
extends RefCounted

## Win / loss conditions as a pure function of the battle state. Battlefield gathers the counts and
## declares the game over; this decides whether it is over. winner: 0 = player, 1 = AI.

## Returns {} while the battle goes on, otherwise {"winner": int, "reason": String}.
## Objective results are only confirmed at the end of a full turn, so a capture must be held through
## the enemy's response phase (otherwise turn-1 dashes into unguarded cities win outright).
static func evaluate(map_def: MapDefinition, grid_map: IsoGridMap, player_count: int, ai_count: int,
		player_obj: int, total_obj: int, turn_number: int, end_of_full_turn: bool) -> Dictionary:
	# 1. Total annihilation
	if ai_count == 0 and player_count > 0:
		return _result(0, "All Kriegs-Syndikat Armored Walkers have been destroyed!")
	if player_count == 0:
		return _result(1, "All 8th Iron Division Walkers were lost in action.")
	if map_def == null or not end_of_full_turn:
		return {}

	# 2. Strategy-specific objective checks
	var turn_limit_reached: bool = turn_number >= map_def.turn_limit
	match map_def.strategy_mode:
		MapDefinition.StrategyMode.OFFENSE:
			# Player wins by holding any Syndicate HQ Bunker at the end of a turn
			var hq_held := false
			for hq_pos in map_def.hq_positions:
				var hq := grid_map.get_tile(hq_pos)
				if hq != null and hq.is_objective and hq.controlled_by == MechData.Faction.PLAYER:
					hq_held = true
			if hq_held:
				return _result(0, "8th Iron Division captured and held the Syndicate HQ Command Bunker!")
			if turn_limit_reached:
				return _result(1, "Turn limit expired before capturing the Syndicate HQ Bunker.")

		MapDefinition.StrategyMode.DEFENSE:
			# AI wins if it holds all Citadel Objectives at turn end; Player wins by holding out through Turn Limit
			if total_obj > 0 and player_obj == 0:
				return _result(1, "Syndicate forces overran all Citadel Bastion nodes!")
			if turn_limit_reached:
				return _result(0, "Citadel Höhenburg held firm through Turn %d against the Syndicate onslaught!" % map_def.turn_limit)

		MapDefinition.StrategyMode.PITCHED_BATTLE:
			if total_obj > 0 and player_obj == total_obj:
				return _result(0, "8th Iron Division secured total control of all River Bridgeheads!")
			if turn_limit_reached:
				# Majority of bridgeheads wins; an even split goes to whoever has more walkers left
				if player_obj * 2 > total_obj or (player_obj * 2 == total_obj and player_count >= ai_count):
					return _result(0, "Coalition forces secured strategic superiority across the Rhine-Fulda crossing!")
				return _result(1, "Syndicate forces held the majority of bridgeheads at Turn limit.")
	return {}

static func _result(winner: int, reason: String) -> Dictionary:
	return {"winner": winner, "reason": reason}
