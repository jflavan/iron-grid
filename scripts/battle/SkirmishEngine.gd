class_name SkirmishEngine
extends RefCounted

## Automated Skirmish Resolver Engine
## Combines Stats-vs-Stats (Firepower, Armor Rating, Terrain & Elevation modifiers)
## with a 3-Bout Triple Triad style Equipment Deck showdown on a 3x3 Tactical Grid.

class BoardSlot extends RefCounted:
	var grid_idx: int = 0 # 0..8 in 3x3 grid (row = idx / 3, col = idx % 3)
	var card: EquipmentCard = null
	var owner_faction: int = -1 # 0 = Player, 1 = AI
	var original_faction: int = -1
	var bonus_applied: int = 0

class BoutStep extends RefCounted:
	var step_index: int = 0
	var actor_faction: int = 0
	var actor_name: String = ""
	var card_placed: EquipmentCard = null
	var slot_index: int = 0
	var flipped_slots: Array[int] = []
	var combo_type: String = "" # "", "OVERMATCH", "TACTICAL PLUS"
	var atk_damage_dealt: int = 0
	var def_damage_dealt: int = 0
	var description: String = ""

class SkirmishResult extends RefCounted:
	var attacker: MechData
	var defender: MechData
	var from_tile: GridTileData
	var target_tile: GridTileData
	
	# Computed modifiers
	var elev_diff: int = 0
	var atk_terrain_mod_pct: int = 0
	var atk_elev_mod_pct: int = 0
	var atk_total_mod_pct: int = 0
	var def_terrain_mod_pct: int = 0
	var def_elev_mod_pct: int = 0
	var def_total_mod_pct: int = 0
	
	var atk_effective_firepower: int = 0
	var atk_effective_armor: int = 0
	var def_effective_firepower: int = 0
	var def_effective_armor: int = 0
	
	var atk_card_edge_mod: int = 0
	var def_card_edge_mod: int = 0
	
	# 3x3 Board & Bouts
	var steps: Array[BoutStep] = []
	var final_board: Array[BoardSlot] = []
	var atk_cards_held: int = 0
	var def_cards_held: int = 0
	
	# Damage & Outcome
	var total_dmg_to_defender: int = 0
	var total_dmg_to_attacker: int = 0
	var atk_armor_before: int = 0
	var def_armor_before: int = 0
	var atk_armor_after: int = 0
	var def_armor_after: int = 0
	
	var defender_destroyed: bool = false
	var attacker_destroyed: bool = false
	var attacker_won_clash: bool = false
	var defender_pushed_back: bool = false
	var summary_headline: String = ""
	var approach_summary: String = ""

## Computes a fast tactical forecast before committing to an engagement.
static func compute_forecast(attacker: MechData, defender: MechData, from_tile: GridTileData, target_tile: GridTileData) -> Dictionary:
	var sim_atk := attacker.duplicate_mech()
	var sim_def := defender.duplicate_mech()
	var res := resolve_skirmish(sim_atk, sim_def, from_tile, target_tile, false)
	return {
		"atk_mod_pct": res.atk_total_mod_pct,
		"def_mod_pct": res.def_total_mod_pct,
		"elev_diff": res.elev_diff,
		"est_dmg_to_def": res.total_dmg_to_defender,
		"est_dmg_to_atk": res.total_dmg_to_attacker,
		"atk_eff_fp": res.atk_effective_firepower,
		"def_eff_fp": res.def_effective_firepower,
		"atk_cards_held": res.atk_cards_held,
		"def_cards_held": res.def_cards_held,
		"approach_summary": res.approach_summary
	}

## Executes the full automated skirmish resolution.
## If `apply_to_units` is true, mutates `attacker.current_armor` and `defender.current_armor`.
static func resolve_skirmish(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData,
	apply_to_units: bool = true
) -> SkirmishResult:
	var res := SkirmishResult.new()
	res.attacker = attacker
	res.defender = defender
	res.from_tile = from_tile
	res.target_tile = target_tile
	res.atk_armor_before = attacker.current_armor
	res.def_armor_before = defender.current_armor

	# 1. Calculate Terrain & Elevation Modifiers
	res.elev_diff = from_tile.elevation - target_tile.elevation
	
	# Attacker gets attack modifier from approach tile + bonus if target is exposed in a river
	var target_exposure_bonus: int = maxi(0, -target_tile.get_defense_modifier_pct())
	res.atk_terrain_mod_pct = from_tile.get_attack_modifier_pct() + target_exposure_bonus
	
	# Defender gets defense + attack modifier from contested target tile + entrenchment bonus
	var entrench_bonus: int = BalanceProbe.def_pct[int(defender.faction)] if defender.is_entrenched else 0
	res.def_terrain_mod_pct = target_tile.get_defense_modifier_pct() + entrench_bonus

	# Elevation advantage: High ground gives +12% per level; attacking uphill gives -10% per level
	if res.elev_diff > 0:
		res.atk_elev_mod_pct = res.elev_diff * 12
		res.def_elev_mod_pct = -res.elev_diff * 8
	elif res.elev_diff < 0:
		var climb_levels: int = -res.elev_diff
		res.atk_elev_mod_pct = -climb_levels * 10
		res.def_elev_mod_pct = climb_levels * 12
	else:
		res.atk_elev_mod_pct = 0
		res.def_elev_mod_pct = 0

	res.atk_total_mod_pct = res.atk_terrain_mod_pct + res.atk_elev_mod_pct
	res.def_total_mod_pct = res.def_terrain_mod_pct + res.def_elev_mod_pct

	# Effective Firepower & Armor Ratings
	res.atk_effective_firepower = maxi(10, int(round(float(attacker.firepower) * (1.0 + float(res.atk_total_mod_pct) / 100.0))))
	# High ground also deflects return fire (+10% Armor per level); attacking uphill only costs firepower
	var atk_elev_armor_pct: int = maxi(0, res.elev_diff) * 10
	res.atk_effective_armor = maxi(8, int(round(float(attacker.armor_rating) * (1.0 + float(from_tile.get_defense_modifier_pct() + atk_elev_armor_pct) / 100.0))))

	res.def_effective_firepower = maxi(10, int(round(float(defender.firepower) * (1.0 + float(target_tile.get_attack_modifier_pct() + res.def_elev_mod_pct) / 100.0))))
	res.def_effective_armor = maxi(8, int(round(float(defender.armor_rating) * (1.0 + float(res.def_total_mod_pct) / 100.0))))

	# Card Edge Modifiers from Terrain, Elevation & Stat Overmatch
	res.atk_card_edge_mod = from_tile.get_card_edge_bonus() + clampi(res.elev_diff, -2, 2)
	if res.atk_effective_firepower >= res.def_effective_armor + 10:
		res.atk_card_edge_mod += 1

	res.def_card_edge_mod = target_tile.get_card_edge_bonus() + clampi(-res.elev_diff, -2, 2)
	if defender.is_entrenched:
		res.def_card_edge_mod += BalanceProbe.card[int(defender.faction)]
	if res.def_effective_firepower >= res.atk_effective_armor + 10:
		res.def_card_edge_mod += 1

	var elev_label := "LEVEL GROUND"
	if res.elev_diff > 0:
		elev_label = "HIGH GROUND +%dm (%+d%%)" % [res.elev_diff * 100, res.atk_elev_mod_pct]
	elif res.elev_diff < 0:
		elev_label = "UPHILL ASSAULT %dm (%+d%%)" % [res.elev_diff * 100, res.atk_elev_mod_pct]
	res.approach_summary = "%s [%dm] -> %s [%dm] | %s" % [
		from_tile.get_terrain_name(), from_tile.get_elevation_meters(),
		target_tile.get_terrain_name(), target_tile.get_elevation_meters(),
		elev_label
	]

	# 2. Initialize 3x3 Triple Triad Tactical Matrix
	var board: Array[BoardSlot] = []
	for i in range(9):
		var s := BoardSlot.new()
		s.grid_idx = i
		board.append(s)

	# Tactical placement sequence across the 3x3 board so every card after the opener contests an
	# opposing card (the attacker's final card closes on two defender edges, the defender's on two):
	# Center (4), Top-Center (1), Top-Right (2), Middle-Left (3), Top-Left (0), Middle-Right (5)
	var placement_order: Array[int] = [4, 1, 2, 3, 0, 5]

	for bout_idx in range(3):
		# Attacker places card `bout_idx`
		var atk_slot_idx: int = placement_order[bout_idx * 2]
		var atk_card: EquipmentCard = _prepare_modified_card(attacker.deck[bout_idx % attacker.deck.size()], res.atk_card_edge_mod)
		var atk_step := _place_card_on_board(board, atk_slot_idx, atk_card, attacker.faction, attacker.callsign, bout_idx * 2)
		res.steps.append(atk_step)

		# Defender places card `bout_idx`
		var def_slot_idx: int = placement_order[bout_idx * 2 + 1]
		var def_card: EquipmentCard = _prepare_modified_card(defender.deck[bout_idx % defender.deck.size()], res.def_card_edge_mod)
		var def_step := _place_card_on_board(board, def_slot_idx, def_card, defender.faction, defender.callsign, bout_idx * 2 + 1)
		res.steps.append(def_step)

	res.final_board = board

	# 3. Count Captured Cards & Compute Hull Damage
	var atk_card_dmg: int = 0
	var atk_card_shd: int = 0
	var def_card_dmg: int = 0
	var def_card_shd: int = 0

	for slot in board:
		if slot.card == null:
			continue
		if slot.owner_faction == attacker.faction:
			res.atk_cards_held += 1
			atk_card_dmg += slot.card.damage_rating
			atk_card_shd += slot.card.shield_rating
		elif slot.owner_faction == defender.faction:
			res.def_cards_held += 1
			def_card_dmg += slot.card.damage_rating
			def_card_shd += slot.card.shield_rating

	# Combine Core Stat Strike + Controlled Equipment Cards vs Armor & Shields
	var raw_atk_strike: float = float(res.atk_effective_firepower) * 0.85 + float(atk_card_dmg) * 0.95
	var def_mitigation: float = float(res.def_effective_armor) * 0.55 + float(def_card_shd) * 0.50
	res.total_dmg_to_defender = clampi(int(round(raw_atk_strike - def_mitigation)), 12, 140)

	# Defender counter-fire (slightly reduced if attacker overwhelmed the card grid)
	var counter_scale: float = 0.72 if res.atk_cards_held > res.def_cards_held else 0.92
	var raw_def_strike: float = (float(res.def_effective_firepower) * 0.80 + float(def_card_dmg) * 0.90) * counter_scale
	var atk_mitigation: float = float(res.atk_effective_armor) * 0.55 + float(atk_card_shd) * 0.50
	res.total_dmg_to_attacker = clampi(int(round(raw_def_strike - atk_mitigation)), 8, 120)

	res.def_armor_after = maxi(0, res.def_armor_before - res.total_dmg_to_defender)
	# If defender is destroyed by overwhelming assault, attacker takes 25% less final return fire
	if res.def_armor_after == 0 and res.atk_cards_held >= res.def_cards_held:
		res.total_dmg_to_attacker = int(round(float(res.total_dmg_to_attacker) * 0.75))
	res.atk_armor_after = maxi(0, res.atk_armor_before - res.total_dmg_to_attacker)

	# Distribute the final damage numbers across the 6 steps for visual telemetry animation
	_distribute_step_damage(res)

	res.defender_destroyed = (res.def_armor_after <= 0)
	res.attacker_destroyed = (res.atk_armor_after <= 0)

	if res.defender_destroyed and not res.attacker_destroyed:
		res.attacker_won_clash = true
		res.summary_headline = "%s DESTROYED %s & CAPTURED SECTOR!" % [attacker.callsign, defender.callsign]
	elif res.attacker_destroyed and not res.defender_destroyed:
		res.attacker_won_clash = false
		res.summary_headline = "%s ANNIHILATED IN COUNTER-BARRAGE!" % [attacker.callsign]
	elif res.attacker_destroyed and res.defender_destroyed:
		res.attacker_won_clash = false
		res.summary_headline = "MUTUAL DESTRUCTION — BOTH WALKERS WRECKED!"
	else:
		# Both survived: compare cards held, then damage dealt
		if res.atk_cards_held > res.def_cards_held or (res.atk_cards_held == res.def_cards_held and res.total_dmg_to_defender >= res.total_dmg_to_attacker):
			res.attacker_won_clash = true
			res.defender_pushed_back = true
			res.summary_headline = "TACTICAL VICTORY (%d-%d) — %s DISLODGED!" % [res.atk_cards_held, res.def_cards_held, defender.callsign]
		else:
			res.attacker_won_clash = false
			res.summary_headline = "ASSAULT REPELLED (%d-%d) — %s FALLS BACK!" % [res.atk_cards_held, res.def_cards_held, attacker.callsign]

	if apply_to_units:
		attacker.current_armor = res.atk_armor_after
		defender.current_armor = res.def_armor_after
		defender.is_entrenched = false

	return res

static func _prepare_modified_card(base_card: EquipmentCard, edge_mod: int) -> EquipmentCard:
	var c := base_card.duplicate_card()
	c.top = clampi(c.top + edge_mod, 1, 10)
	c.right = clampi(c.right + edge_mod, 1, 10)
	c.bottom = clampi(c.bottom + edge_mod, 1, 10)
	c.left = clampi(c.left + edge_mod, 1, 10)
	return c

static func _place_card_on_board(
	board: Array[BoardSlot],
	slot_idx: int,
	card: EquipmentCard,
	faction: int,
	actor_name: String,
	step_idx: int
) -> BoutStep:
	var slot := board[slot_idx]
	slot.card = card
	slot.owner_faction = faction
	slot.original_faction = faction

	var step := BoutStep.new()
	step.step_index = step_idx
	step.actor_faction = faction
	step.actor_name = actor_name
	step.card_placed = card
	step.slot_index = slot_idx

	@warning_ignore("integer_division")
	var row: int = slot_idx / 3
	var col: int = slot_idx % 3

	# Orthogonal neighbors: [neighbor_idx, my_edge_val, their_edge_val, direction_name]
	var neighbors: Array[Dictionary] = []
	if row > 0:
		var n_idx: int = (row - 1) * 3 + col
		if board[n_idx].card != null:
			neighbors.append({ "idx": n_idx, "my_val": card.top, "op_val": board[n_idx].card.bottom, "dir": "NORTH" })
	if col < 2:
		var n_idx: int = row * 3 + (col + 1)
		if board[n_idx].card != null:
			neighbors.append({ "idx": n_idx, "my_val": card.right, "op_val": board[n_idx].card.left, "dir": "EAST" })
	if row < 2:
		var n_idx: int = (row + 1) * 3 + col
		if board[n_idx].card != null:
			neighbors.append({ "idx": n_idx, "my_val": card.bottom, "op_val": board[n_idx].card.top, "dir": "SOUTH" })
	if col > 0:
		var n_idx: int = row * 3 + (col - 1)
		if board[n_idx].card != null:
			neighbors.append({ "idx": n_idx, "my_val": card.left, "op_val": board[n_idx].card.right, "dir": "WEST" })

	# Check Triple Triad "PLUS" rule (two or more adjacent edges have equal sums)
	var sum_counts: Dictionary = {}
	for nb in neighbors:
		var edge_sum: int = int(nb["my_val"]) + int(nb["op_val"])
		sum_counts[edge_sum] = sum_counts.get(edge_sum, 0) + 1

	var plus_triggered := false
	for nb in neighbors:
		var n_idx: int = int(nb["idx"])
		var target_slot := board[n_idx]
		var edge_sum: int = int(nb["my_val"]) + int(nb["op_val"])
		if sum_counts[edge_sum] >= 2 and target_slot.owner_faction != faction:
			target_slot.owner_faction = faction
			step.flipped_slots.append(n_idx)
			plus_triggered = true

	# Standard directional rank comparison
	for nb in neighbors:
		var n_idx: int = int(nb["idx"])
		var target_slot := board[n_idx]
		if target_slot.owner_faction != faction and int(nb["my_val"]) > int(nb["op_val"]):
			target_slot.owner_faction = faction
			if not step.flipped_slots.has(n_idx):
				step.flipped_slots.append(n_idx)

	if plus_triggered:
		step.combo_type = "TACTICAL PLUS"
		step.description = "%s deploys [%s] -> TACTICAL PLUS OVERLOAD! Flipped %d system(s)!" % [
			actor_name, card.card_name, step.flipped_slots.size()
		]
	elif step.flipped_slots.size() > 0:
		step.combo_type = "OVERMATCH"
		step.description = "%s deploys [%s] -> OVERMATCH! Captured %d enemy card(s)!" % [
			actor_name, card.card_name, step.flipped_slots.size()
		]
	else:
		step.description = "%s deploys [%s] into Matrix Slot #%d." % [
			actor_name, card.card_name, slot_idx + 1
		]

	return step

static func _distribute_step_damage(res: SkirmishResult) -> void:
	# Distribute total damage across the 3 bouts so armor gauges drop dynamically during the showdown
	var def_rem: int = res.total_dmg_to_defender
	var atk_rem: int = res.total_dmg_to_attacker
	for i in range(res.steps.size()):
		var step := res.steps[i]
		if i % 2 == 0: # Attacker step deals damage to defender
			var portion: int = int(round(float(res.total_dmg_to_defender) / 3.0)) if i < 4 else def_rem
			portion = clampi(portion, 0, def_rem)
			step.atk_damage_dealt = portion
			def_rem -= portion
		else: # Defender step deals counter damage to attacker
			var portion: int = int(round(float(res.total_dmg_to_attacker) / 3.0)) if i < 5 else atk_rem
			portion = clampi(portion, 0, atk_rem)
			step.def_damage_dealt = portion
			atk_rem -= portion
