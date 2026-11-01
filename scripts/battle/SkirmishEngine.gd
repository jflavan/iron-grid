class_name SkirmishEngine
extends RefCounted

## Classic Final Fantasy Style Turn-Based Battle Engine
## Resolves encounters between two Armored Fighting Walkers using RPG stats
## (Hull HP, Reactor Energy EN, Firepower ATK, Armor DEF, Speed SPD, Evasion EVA, Crit CRIT),
## Terrain & Elevation modifiers, 4 Battle Commands (ATTACK, TECH, DEFEND, RETREAT),
## and 18 Chassis-specific Weapon, Armor, and Tactical TECH abilities.

enum CommandType {
	ATTACK = 0,
	TECH = 1,
	DEFEND = 2,
	RETREAT = 3
}

const MAX_BATTLE_ROUNDS: int = 10
const ROUND1_ATTACKER_SPD_BONUS: int = 8
const ROUND1_ENTRENCHED_SPD_BONUS: int = 6
const ENTRENCHED_SPD_BONUS: int = 4
const ENTRENCHED_EVA_BONUS: int = 5
const ENTRENCHED_ACC_BONUS: int = 6
const CRIT_DAMAGE_MULT: float = 1.42  # live crit multiplier; the deterministic forecast folds the same bonus in by expectation
const DAMAGE_VARIANCE_MIN: float = 0.94  # live shots roll a +/-6% classic RPG variance
const DAMAGE_VARIANCE_MAX: float = 1.06
const DAMAGE_MIN: int = 4            # every landed shot deals at least this, in every mode
const BASE_DAMAGE_MAX: int = 95      # cap on the pre-roll estimate (forecasts never exceed it)
const LIVE_DAMAGE_MAX: int = 120     # a live crit on a capped shot may run up to this
# Elevation, per level of height difference (also quoted by the Rules of Engagement page)
const ELEV_HIGH_FP_PCT: int = 12         # attacker firing down: +FP
const ELEV_HIGH_ENEMY_FP_PCT: int = 8    # ...and the defender below loses FP and armor
const ELEV_HIGH_ARMOR_PCT: int = 10      # ...and the attacker gains armor
const ELEV_CLIMB_FP_PCT: int = 10        # attacker firing uphill: -FP
const ELEV_CLIMB_ENEMY_FP_PCT: int = 12  # ...and the defender above gains FP and armor
const ELEV_EVA_PER_LEVEL: int = 4        # the higher walker's EVA
const ELEV_CRIT_PER_LEVEL: int = 5       # the higher walker's crit
const ELEV_ACC_PER_LEVEL: int = 4        # hit chance, + for the higher walker, - for the lower
const GUARD_DAMAGE_MULT: float = 0.50    # DEFEND: the next landed hit is halved
const DEFEND_EN_GAIN: int = 2
const ESCAPE_BASE_PCT: int = 58          # RETREAT chance = base + per-SPD x speed lead, clamped
const ESCAPE_PER_SPD_PCT: int = 2
const ESCAPE_MIN_PCT: int = 25
const ESCAPE_MAX_PCT: int = 92

class TurnStep extends RefCounted:
	var step_index: int = 0
	var round_number: int = 1
	var actor_side: String = "atk" # "atk" or "def"
	var actor_faction: int = 0
	var actor_name: String = ""
	var command_type: int = CommandType.ATTACK
	var ability_id: String = ""
	var ability_name: String = ""
	var ability_category: String = "WEAPON" # WEAPON, ARMOR, TACTIC, DEFEND, RETREAT
	var is_support_only: bool = false       # true for ARMOR/TACTIC/DEFEND/RETREAT (no weapon shot)
	var is_miss: bool = false
	var is_crit: bool = false
	var escaped: bool = false
	var escape_failed: bool = false
	var damage_dealt: int = 0      # Damage this step dealt to the opponent of actor_side
	var soften_from: String = ""
	var status_text: String = ""
	var description: String = ""
	var atk_hp_after: int = 0
	var def_hp_after: int = 0
	var atk_en_after: int = 0
	var def_en_after: int = 0

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

	var atk_effective_speed: int = 0
	var def_effective_speed: int = 0
	var first_striker: String = "atk"
	var rounds_fought: int = 0

	# Turn-by-Turn Battle Steps
	var steps: Array[TurnStep] = []

	# Damage & Outcome
	var total_dmg_to_defender: int = 0
	var total_dmg_to_attacker: int = 0
	var atk_armor_before: int = 0
	var def_armor_before: int = 0
	var atk_armor_after: int = 0
	var def_armor_after: int = 0
	var atk_energy_before: int = 0
	var def_energy_before: int = 0
	var atk_energy_after: int = 0
	var def_energy_after: int = 0

	var defender_destroyed: bool = false
	var attacker_destroyed: bool = false
	var attacker_retreated: bool = false
	var defender_retreated: bool = false
	var attacker_won_clash: bool = false
	var defender_pushed_back: bool = false
	var summary_headline: String = ""
	var approach_summary: String = ""

class CombatantState extends RefCounted:
	var side: String = "atk"
	var mech: MechData
	var hp: int = 100
	var max_hp: int = 100
	var en: int = 14
	var max_en: int = 14
	var base_atk: int = 30
	var base_def: int = 30
	var base_spd: int = 20
	var base_eva: int = 8
	var base_crit: int = 10
	var base_acc: int = 94

	# Active in-battle statuses & buffs
	var defending: bool = false
	var atk_buff_pct: int = 0
	var def_buff_pct: int = 0
	var spd_buff_pct: int = 0
	var eva_buff_pct: int = 0
	var acc_buff_pct: int = 0
	var crit_buff_pct: int = 0
	var armor_pierce_bonus: float = 0.0
	var pending_soften: String = ""
	var used_support_ids: Dictionary = {} # ARMOR/TACTIC ability ids already deployed this battle
	var retreat_attempted: bool = false

	## ARMOR/TACTIC TECHs deploy once per battle; weapon TECHs only need the energy.
	func can_use(ab: CombatAbility) -> bool:
		if en < ab.energy_cost:
			return false
		return ab.is_weapon() or not used_support_ids.has(ab.ability_id)

	func get_effective_atk() -> int:
		return maxi(8, int(round(float(base_atk) * (1.0 + float(atk_buff_pct) / 100.0))))

	func get_effective_def() -> int:
		return maxi(6, int(round(float(base_def) * (1.0 + float(def_buff_pct) / 100.0))))

	func get_effective_speed() -> int:
		return maxi(5, int(round(float(base_spd) * (1.0 + float(spd_buff_pct) / 100.0))))

	func get_effective_evasion() -> int:
		return clampi(base_eva + eva_buff_pct, 0, 65)

	func get_effective_accuracy(weapon_acc: int) -> int:
		return weapon_acc + (base_acc - 94) + acc_buff_pct

	func get_effective_crit(weapon_crit_bonus: int) -> int:
		return clampi(base_crit + weapon_crit_bonus + crit_buff_pct, 4, 85)

	func get_status_badges() -> Array[String]:
		var badges: Array[String] = []
		if defending:
			badges.append("GUARD")
		if pending_soften != "":
			badges.append("SHIELD")
		if def_buff_pct != 0:
			badges.append("ARM+" if def_buff_pct > 0 else "ARM-")
		if atk_buff_pct > 0 or crit_buff_pct > 0:
			badges.append("LOCK")
		if eva_buff_pct > 0 or spd_buff_pct > 0:
			badges.append("HASTE")
		if acc_buff_pct < 0 or spd_buff_pct < 0 or def_buff_pct < 0:
			badges.append("JAM")
		return badges

## Live Interactive / Step-by-Step Battle Session used by both BattleScreen and automated simulations.
class BattleSession extends RefCounted:
	var result: SkirmishResult
	var atk_state: CombatantState
	var def_state: CombatantState
	var can_defender_retreat: bool = true
	var deterministic_mode: bool = false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	var round_number: int = 0
	var turn_queue: Array[String] = []
	var is_finished: bool = false
	var _step_counter: int = 0

	func _init(
		attacker: MechData,
		defender: MechData,
		from_tile: GridTileData,
		target_tile: GridTileData,
		p_can_def_retreat: bool = true,
		p_seed: int = -1,
		p_deterministic: bool = false
	) -> void:
		deterministic_mode = p_deterministic
		can_defender_retreat = p_can_def_retreat
		if p_seed >= 0:
			rng.seed = p_seed
		else:
			rng.randomize()

		result = SkirmishEngine._init_result_modifiers(attacker, defender, from_tile, target_tile)
		atk_state = _make_combatant("atk", attacker, result.atk_effective_firepower, result.atk_effective_armor, from_tile, result.elev_diff)
		def_state = _make_combatant("def", defender, result.def_effective_firepower, result.def_effective_armor, target_tile, -result.elev_diff)
		_advance_round_queue_if_needed()
		# The forecast's INITIATIVE line is the real round-1 queue, so the HUD can never disagree with play.
		var round1 := _round_initiative_speeds()
		result.atk_effective_speed = round1[0]
		result.def_effective_speed = round1[1]
		result.first_striker = turn_queue[0]

	func _make_combatant(
		side: String,
		m: MechData,
		eff_atk: int,
		eff_def: int,
		tile: GridTileData,
		my_elev_adv: int
	) -> CombatantState:
		var st := CombatantState.new()
		st.side = side
		st.mech = m
		st.hp = m.current_armor
		st.max_hp = m.max_armor
		st.en = m.current_energy
		st.max_en = m.max_energy
		st.base_atk = eff_atk
		st.base_def = eff_def
		st.base_spd = m.speed
		st.base_eva = clampi(m.evasion + tile.get_evasion_modifier_pct() + maxi(0, my_elev_adv) * ELEV_EVA_PER_LEVEL, 0, 55)
		st.base_crit = clampi(m.crit_chance + maxi(0, my_elev_adv) * ELEV_CRIT_PER_LEVEL, 4, 50)
		st.base_acc = 94 + my_elev_adv * ELEV_ACC_PER_LEVEL
		if side == "def" and m.is_entrenched:
			st.base_spd += ENTRENCHED_SPD_BONUS
			st.base_eva += ENTRENCHED_EVA_BONUS
			st.base_acc += ENTRENCHED_ACC_BONUS
		return st

	func get_combatant(side: String) -> CombatantState:
		return atk_state if side == "atk" else def_state

	func get_opponent(side: String) -> CombatantState:
		return def_state if side == "atk" else atk_state

	func get_next_actor_side() -> String:
		if is_finished:
			return ""
		_advance_round_queue_if_needed()
		if turn_queue.is_empty():
			return ""
		return turn_queue[0]

	func _advance_round_queue_if_needed() -> void:
		if is_finished or not turn_queue.is_empty():
			return
		round_number += 1
		if round_number > MAX_BATTLE_ROUNDS:
			_conclude_battle()
			return
		result.rounds_fought = round_number
		var spd := _round_initiative_speeds()
		if spd[0] > spd[1] or (spd[0] == spd[1] and not result.defender.is_entrenched):
			turn_queue = ["atk", "def"]
		else:
			turn_queue = ["def", "atk"]

	## Initiative speeds [atk, def] for the current round. Round 1 gives the initiating Attacker an
	## +8 SPD assault bonus; an Entrenched Defender answers with +6 SPD on top of its +4 base (= +10).
	func _round_initiative_speeds() -> Array[int]:
		var atk_spd := atk_state.get_effective_speed() + (ROUND1_ATTACKER_SPD_BONUS if round_number == 1 else 0)
		var def_spd := def_state.get_effective_speed() + (ROUND1_ENTRENCHED_SPD_BONUS if round_number == 1 and result.defender.is_entrenched else 0)
		var speeds: Array[int] = [atk_spd, def_spd]
		return speeds

	## Chooses an intelligent AI command for `side` (used for Syndicate AI, Player Auto-Pilot, and Forecast).
	func choose_ai_command(side: String) -> Dictionary:
		var actor := get_combatant(side)
		var target := get_opponent(side)

		# 1. Check if we can finish off the target right now with a Weapon TECH or basic ATTACK.
		# expected_strike_damage() is what _resolve_weapon_strike deals before its dice, and
		# is_sure_kill() allows for the live variance band, so a finisher is only chosen when the
		# engine cannot scale it below the kill (a miss is a separate roll either way).
		var basic_est := expected_strike_damage(actor, target, null)
		if is_sure_kill(basic_est, target.hp):
			return {"command": CommandType.ATTACK, "ability_id": ""}

		var best_weapon: CombatAbility = null
		var best_weapon_dmg: int = basic_est
		for ab in actor.mech.abilities:
			if ab.is_weapon() and actor.can_use(ab):
				var est := expected_strike_damage(actor, target, ab)
				if is_sure_kill(est, target.hp):
					return {"command": CommandType.TECH, "ability_id": ab.ability_id}
				if est > best_weapon_dmg:
					best_weapon_dmg = est
					best_weapon = ab

		# 2. Tactical Morale / Retreat Check:
		# On Round 2+, if a walker is in critical hull (<= 38% HP or within lethal range of next enemy strike),
		# cannot finish the opponent this turn, is not defending a vital Objective tile, and hasn't already tried to retreat:
		var hp_ratio := float(actor.hp) / float(maxi(1, actor.max_hp))
		var holding_vital_objective: bool = (side == "def" and result.target_tile != null and result.target_tile.is_objective)
		var can_escape_tile: bool = (side == "atk" or can_defender_retreat)
		# A guard still raised here has not been spent (guards last until the first enemy shot lands),
		# so it really will halve the next incoming hit and belongs in the estimate. The enemy will
		# fire its strongest affordable weapon TECH (step 4), not just its basic gun.
		var enemy_est := strongest_strike_estimate(target, actor)
		var in_lethal_danger: bool = (hp_ratio <= 0.38 or (actor.hp <= enemy_est + 6 and target.hp > actor.hp + 10))
		if not deterministic_mode and round_number >= 2 and in_lethal_danger and target.hp > best_weapon_dmg and not holding_vital_objective and can_escape_tile and not actor.retreat_attempted:
			var esc_chance := compute_escape_chance(actor, target)
			if esc_chance >= 40:
				return {"command": CommandType.RETREAT, "ability_id": ""}

		# 3. Early in the fight (Round 1-2), consider using an unapplied Support/Armor/Tactical TECH
		if round_number <= 2 and hp_ratio >= 0.45:
			for ab in actor.mech.abilities:
				if not ab.is_weapon() and actor.can_use(ab):
					# Prioritize support tech if we haven't used one yet
					if round_number == 1 or deterministic_mode or rng.randi_range(1, 100) <= 75:
						return {"command": CommandType.TECH, "ability_id": ab.ability_id}

		# 4. Otherwise use strongest affordable Weapon TECH or Basic Attack
		if best_weapon != null and actor.can_use(best_weapon):
			return {"command": CommandType.TECH, "ability_id": best_weapon.ability_id}

		return {"command": CommandType.ATTACK, "ability_id": ""}

	## Strongest shot `shooter` can take at `victim` right now: basic gun or any weapon TECH it can use.
	func strongest_strike_estimate(shooter: CombatantState, victim: CombatantState) -> int:
		var best := expected_strike_damage(shooter, victim, null)
		for ab in shooter.mech.abilities:
			if ab.is_weapon() and shooter.can_use(ab):
				best = maxi(best, expected_strike_damage(shooter, victim, ab))
		return best

	func hit_chance_for(actor: CombatantState, target: CombatantState, weapon_tech: CombatAbility) -> int:
		var base_w_acc: int = weapon_tech.accuracy if weapon_tech != null else 94
		return clampi(actor.get_effective_accuracy(base_w_acc) - target.get_effective_evasion(), 28, 100)

	func crit_chance_for(actor: CombatantState, weapon_tech: CombatAbility) -> int:
		return actor.get_effective_crit(weapon_tech.crit_bonus if weapon_tech != null else 0)

	## Pre-roll damage of a shot in this session's mode: the raw estimate when dice are live, or the
	## expectation over hit and crit chance in deterministic mode. _resolve_weapon_strike deals
	## exactly this (before variance/crit rolls), so AI decisions and forecasts cannot drift from it.
	func expected_strike_damage(actor: CombatantState, target: CombatantState, weapon_tech: CombatAbility) -> int:
		var dmg := estimate_attack_damage(actor, target, weapon_tech)
		if deterministic_mode:
			var hit := float(hit_chance_for(actor, target, weapon_tech)) / 100.0
			var crit := float(crit_chance_for(actor, weapon_tech)) / 100.0
			dmg = maxi(DAMAGE_MIN, int(round(float(dmg) * hit * (1.0 + crit * (CRIT_DAMAGE_MULT - 1.0)))))
		return dmg

	## True when a shot estimated at `est` kills `hp` even at the bottom of the live variance band.
	func is_sure_kill(est: int, hp: int) -> bool:
		var floor_dmg := est if deterministic_mode else int(floor(float(est) * DAMAGE_VARIANCE_MIN))
		return floor_dmg >= hp

	func compute_escape_chance(actor: CombatantState, target: CombatantState) -> int:
		if actor.side == "def" and not can_defender_retreat:
			return 0
		var spd_diff := actor.get_effective_speed() - target.get_effective_speed()
		return clampi(ESCAPE_BASE_PCT + spd_diff * ESCAPE_PER_SPD_PCT, ESCAPE_MIN_PCT, ESCAPE_MAX_PCT)

	func estimate_attack_damage(actor: CombatantState, target: CombatantState, weapon_tech: CombatAbility) -> int:
		var mult: float = weapon_tech.power_multiplier if weapon_tech != null else 1.0
		var flat: int = weapon_tech.flat_power if weapon_tech != null else 6
		var pierce: float = clampf((weapon_tech.armor_pierce if weapon_tech != null else 0.0) + actor.armor_pierce_bonus, 0.0, 0.65)
		var eff_atk: float = float(actor.get_effective_atk()) * mult + float(flat)
		var eff_def: float = float(target.get_effective_def()) * (1.0 - pierce)
		var raw: float = eff_atk * 0.62 - eff_def * 0.34
		if target.defending:
			raw *= GUARD_DAMAGE_MULT
		if target.pending_soften == "ablative_shield":
			raw *= 0.52
		elif target.pending_soften != "":
			raw *= 0.68
		return clampi(int(round(raw)), DAMAGE_MIN, BASE_DAMAGE_MAX)

	## Executes the next turn in the queue with the chosen command and returns the resulting TurnStep.
	func execute_next_turn(command_type: int, ability_id: String = "") -> TurnStep:
		if is_finished:
			return null
		_advance_round_queue_if_needed()
		if turn_queue.is_empty():
			return null

		var side: String = turn_queue[0]
		var actor := get_combatant(side)
		var target := get_opponent(side)

		# A TECH the actor cannot use (unknown id, spent support TECH, not enough EN) is rejected:
		# the turn is not consumed and the caller gets null. The menu and the AI both check
		# can_use() first, so reaching this is a caller bug worth surfacing rather than masking
		# behind a silent STANDARD FIRE.
		var chosen_ability: CombatAbility = null
		if command_type == CommandType.TECH:
			for ab in actor.mech.abilities:
				if ab.ability_id == ability_id:
					chosen_ability = ab
					break
			if chosen_ability == null or not actor.can_use(chosen_ability):
				push_warning("SkirmishEngine: %s cannot use TECH '%s'; command rejected" % [actor.mech.callsign, ability_id])
				return null
		# A guard that is still up cannot be stacked: DEFEND again would only bank +2 EN.
		if command_type == CommandType.DEFEND and actor.defending:
			push_warning("SkirmishEngine: %s is already guarding; DEFEND rejected" % actor.mech.callsign)
			return null
		turn_queue.pop_front()

		var step := TurnStep.new()
		step.step_index = _step_counter
		_step_counter += 1
		step.round_number = round_number
		step.actor_side = side
		step.actor_faction = int(actor.mech.faction)
		step.actor_name = actor.mech.callsign
		step.command_type = command_type

		match command_type:
			CommandType.ATTACK:
				_resolve_weapon_strike(step, actor, target, null)
			CommandType.TECH:
				actor.en = maxi(0, actor.en - chosen_ability.energy_cost)
				if chosen_ability.is_weapon():
					_resolve_weapon_strike(step, actor, target, chosen_ability)
				else:
					_resolve_support_tech(step, actor, target, chosen_ability)
			CommandType.DEFEND:
				actor.defending = true
				actor.en = mini(actor.max_en, actor.en + DEFEND_EN_GAIN)
				step.ability_id = "defend"
				step.ability_name = "DEFEND / BRACE"
				step.ability_category = "DEFEND"
				step.is_support_only = true
				step.status_text = "GUARD +50% // +2 EN"
				step.description = "%s braces armor plating (+50%% Guard, +2 EN)." % actor.mech.callsign
			CommandType.RETREAT:
				actor.retreat_attempted = true
				step.ability_id = "retreat"
				step.ability_name = "EMERGENCY RETREAT"
				step.ability_category = "RETREAT"
				step.is_support_only = true
				var esc_chance := compute_escape_chance(actor, target)
				var roll := 50 if deterministic_mode else rng.randi_range(1, 100)
				if roll <= esc_chance:
					step.escaped = true
					step.status_text = "DISENGAGED!"
					step.description = "%s broke off the engagement and retreated!" % actor.mech.callsign
					if side == "atk":
						result.attacker_retreated = true
					else:
						result.defender_retreated = true
				else:
					step.escape_failed = true
					step.status_text = "RETREAT BLOCKED!"
					step.description = "%s attempted to retreat, but %s cut off escape!" % [actor.mech.callsign, target.mech.callsign]

		step.atk_hp_after = atk_state.hp
		step.def_hp_after = def_state.hp
		step.atk_en_after = atk_state.en
		step.def_en_after = def_state.en
		result.steps.append(step)

		if step.escaped or atk_state.hp <= 0 or def_state.hp <= 0:
			_conclude_battle()
		elif turn_queue.is_empty() and round_number >= MAX_BATTLE_ROUNDS:
			_conclude_battle()

		return step

	func _resolve_weapon_strike(step: TurnStep, actor: CombatantState, target: CombatantState, weapon_tech: CombatAbility) -> void:
		if weapon_tech != null:
			step.ability_id = weapon_tech.ability_id
			step.ability_name = weapon_tech.ability_name
			step.ability_category = "WEAPON"
		else:
			step.ability_id = actor.mech.basic_weapon_id
			step.ability_name = "STANDARD FIRE"
			step.ability_category = "ATTACK"
		step.is_support_only = false

		var hit_chance: int = hit_chance_for(actor, target, weapon_tech)
		var hit_roll: int = 1 if deterministic_mode else rng.randi_range(1, 100)

		if hit_roll > hit_chance:
			step.is_miss = true
			step.damage_dealt = 0
			step.status_text = "MISS!"
			step.description = "%s fired [%s] -> MISSED (%s evaded)!" % [actor.mech.callsign, step.ability_name, target.mech.callsign]
			return

		var crit_chance: int = crit_chance_for(actor, weapon_tech)
		var crit_roll: int = 100 if deterministic_mode else rng.randi_range(1, 100)
		var is_crit: bool = (crit_roll <= crit_chance)
		step.is_crit = is_crit

		var dmg: int = expected_strike_damage(actor, target, weapon_tech)
		if not deterministic_mode:
			if is_crit:
				dmg = int(round(float(dmg) * CRIT_DAMAGE_MULT))
			# Slight +/- 6% classic RPG damage variance
			var variance: float = rng.randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
			dmg = clampi(int(round(float(dmg) * variance)), DAMAGE_MIN, LIVE_DAMAGE_MAX)

		if target.pending_soften != "":
			step.soften_from = target.pending_soften
			target.pending_soften = ""

		if target.hp > 0:
			dmg = mini(target.hp, dmg)
		target.hp = maxi(0, target.hp - dmg)
		step.damage_dealt = dmg
		if actor.side == "atk":
			result.total_dmg_to_defender += dmg
		else:
			result.total_dmg_to_attacker += dmg

		var notes: Array[String] = []
		if is_crit:
			notes.append("CRITICAL HIT!")
		if target.defending:
			notes.append("GUARDED (-50%)")
		if step.soften_from != "":
			notes.append("SHIELD DEFLECT!")
		step.status_text = " // ".join(notes)
		# Like a pending shield, a DEFEND guard is spent by the first enemy shot that lands. It is
		# not cleared at the guarding unit's next turn start (an initiative flip would waste it) nor
		# by a MISS, a support TECH or a failed RETREAT.
		target.defending = false

		step.description = "%s strikes with [%s] for %d DMG%s!" % [
			actor.mech.callsign, step.ability_name, dmg, " (CRITICAL!)" if is_crit else ""
		]

	func _resolve_support_tech(step: TurnStep, actor: CombatantState, target: CombatantState, ab: CombatAbility) -> void:
		step.ability_id = ab.ability_id
		step.ability_name = ab.ability_name
		step.ability_category = ab.category
		step.is_support_only = true
		actor.used_support_ids[ab.ability_id] = true

		match ab.effect_type:
			"PROTECT_RICOCHET":
				actor.def_buff_pct = mini(75, actor.def_buff_pct + 35)
				actor.pending_soften = "krupp_plate"
				step.status_text = "DEF +35% // GLACIS ANGLING"
			"BULKHEAD_WALL":
				actor.def_buff_pct = mini(85, actor.def_buff_pct + 45)
				step.status_text = "BULKHEAD DEPLOYED (+45% DEF)"
			"ANCHOR_BRACE":
				actor.def_buff_pct = mini(75, actor.def_buff_pct + 30)
				actor.acc_buff_pct += 20
				actor.crit_buff_pct += 15
				step.status_text = "BRACED (+30% DEF / +CRIT)"
			"REACTIVE_SHIELD":
				actor.def_buff_pct = mini(75, actor.def_buff_pct + 20)
				actor.pending_soften = "ablative_shield"
				step.status_text = "REACTIVE SHIELD ARMED"
			"THRUSTER_EVADE":
				actor.eva_buff_pct = mini(45, actor.eva_buff_pct + 30)
				actor.spd_buff_pct = mini(60, actor.spd_buff_pct + 35)
				actor.pending_soften = "gyro_thruster"
				step.status_text = "EVA +30% // HASTE +35%"
			"RECON_LOCK":
				actor.acc_buff_pct += 35
				actor.crit_buff_pct += 35
				actor.atk_buff_pct = mini(65, actor.atk_buff_pct + 20)
				step.status_text = "TARGET LOCK (+35% CRIT/ACC)"
			"BALLISTIC_PLOT":
				actor.atk_buff_pct = mini(65, actor.atk_buff_pct + 30)
				actor.crit_buff_pct += 25
				actor.armor_pierce_bonus = minf(0.45, actor.armor_pierce_bonus + 0.20)
				step.status_text = "FIRE PLOT (+30% ATK / +AP)"
			"ECM_JAM":
				target.acc_buff_pct = maxi(-45, target.acc_buff_pct - 30)
				target.spd_buff_pct = maxi(-45, target.spd_buff_pct - 25)
				target.def_buff_pct = maxi(-40, target.def_buff_pct - 20)
				step.status_text = "ENEMY JAMMED (-ACC/-SPD/-DEF)"
			"CMD_UPLINK":
				actor.atk_buff_pct = mini(65, actor.atk_buff_pct + 25)
				actor.def_buff_pct = mini(75, actor.def_buff_pct + 25)
				actor.spd_buff_pct = mini(60, actor.spd_buff_pct + 15)
				actor.acc_buff_pct += 15
				step.status_text = "HQ UPLINK (+25% ATK/DEF)"
			_:
				actor.def_buff_pct += 25
				step.status_text = "SYSTEM BOOST"

		step.description = "%s activates [%s] -> %s!" % [actor.mech.callsign, ab.ability_name, step.status_text]

	func _conclude_battle() -> void:
		if is_finished:
			return
		is_finished = true
		turn_queue.clear()

		result.atk_armor_after = maxi(0, atk_state.hp)
		result.def_armor_after = maxi(0, def_state.hp)
		result.atk_energy_after = clampi(atk_state.en, 0, atk_state.max_en)
		result.def_energy_after = clampi(def_state.en, 0, def_state.max_en)

		result.defender_destroyed = (result.def_armor_after <= 0)
		result.attacker_destroyed = (result.atk_armor_after <= 0)

		if result.defender_destroyed and not result.attacker_destroyed:
			result.attacker_won_clash = true
			result.summary_headline = "%s DESTROYED %s & CAPTURED SECTOR!" % [result.attacker.callsign, result.defender.callsign]
		elif result.attacker_destroyed and not result.defender_destroyed:
			result.attacker_won_clash = false
			result.summary_headline = "%s ANNIHILATED IN COUNTER-BARRAGE!" % [result.attacker.callsign]
		elif result.attacker_destroyed and result.defender_destroyed:
			result.attacker_won_clash = false
			result.summary_headline = "MUTUAL DESTRUCTION — BOTH WALKERS WRECKED!"
		elif result.attacker_retreated:
			result.attacker_won_clash = false
			result.summary_headline = "%s DISENGAGED — %s HOLDS SECTOR!" % [result.attacker.callsign, result.defender.callsign]
		elif result.defender_retreated:
			result.attacker_won_clash = true
			result.defender_pushed_back = true
			result.summary_headline = "%s FORCED TO RETREAT — %s SEIZES SECTOR!" % [result.defender.callsign, result.attacker.callsign]
		else:
			# Max rounds reached with both alive: compare remaining hull ratio / damage dealt
			if result.total_dmg_to_defender > result.total_dmg_to_attacker:
				result.attacker_won_clash = true
				result.defender_pushed_back = true
				result.summary_headline = "TACTICAL BREAKTHROUGH — %s DISLODGED!" % [result.defender.callsign]
			else:
				result.attacker_won_clash = false
				result.summary_headline = "ASSAULT REPELLED — %s FALLS BACK!" % [result.attacker.callsign]

	## Lets the AI pick and play the next turn. Returns the TurnStep, or null once the session is over.
	func run_ai_turn() -> TurnStep:
		var side := get_next_actor_side()
		if side == "":
			return null
		var cmd := choose_ai_command(side)
		var step := execute_next_turn(int(cmd["command"]), String(cmd["ability_id"]))
		if step == null and not is_finished:
			# The AI only asks for commands it can use; should that ever break, fall back to a basic
			# shot rather than hand callers a null that reads as "battle over".
			push_error("SkirmishEngine: AI command %s rejected for %s; firing basic weapon instead" % [cmd, side])
			step = execute_next_turn(CommandType.ATTACK)
		return step

	## Plays the rest of the battle with the AI commanding both sides; `on_step` sees every TurnStep.
	func auto_resolve(on_step: Callable = Callable()) -> void:
		var safety := 0
		while not is_finished and safety < 64:
			var step := run_ai_turn()
			if step == null:
				break
			if on_step.is_valid():
				on_step.call(step)
			safety += 1

	func apply_to_units() -> void:
		if not is_finished:
			push_error("SkirmishEngine: apply_to_units() called before the battle concluded; ignored")
			return
		result.attacker.current_armor = result.atk_armor_after
		result.defender.current_armor = result.def_armor_after
		result.attacker.current_energy = result.atk_energy_after
		result.defender.current_energy = result.def_energy_after
		# Only a dislodged defender (destroyed, routed or pushed back) loses its entrenchment; an
		# attacker that breaks off or is repelled cannot de-fortify a garrison for free.
		if result.attacker_won_clash:
			result.defender.is_entrenched = false

## Computes terrain, elevation, and stat modifiers and initializes a SkirmishResult header.
static func _init_result_modifiers(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData
) -> SkirmishResult:
	var res := SkirmishResult.new()
	res.attacker = attacker
	res.defender = defender
	res.from_tile = from_tile
	res.target_tile = target_tile
	res.atk_armor_before = attacker.current_armor
	res.def_armor_before = defender.current_armor
	res.atk_energy_before = attacker.current_energy
	res.def_energy_before = defender.current_energy

	res.elev_diff = from_tile.elevation - target_tile.elevation

	var target_exposure_bonus: int = maxi(0, -target_tile.get_defense_modifier_pct())
	res.atk_terrain_mod_pct = from_tile.get_attack_modifier_pct() + target_exposure_bonus

	var entrench_bonus: int = BalanceProbe.def_pct[int(defender.faction)] if defender.is_entrenched else 0
	res.def_terrain_mod_pct = target_tile.get_defense_modifier_pct() + entrench_bonus

	if res.elev_diff > 0:
		res.atk_elev_mod_pct = res.elev_diff * ELEV_HIGH_FP_PCT
		res.def_elev_mod_pct = -res.elev_diff * ELEV_HIGH_ENEMY_FP_PCT
	elif res.elev_diff < 0:
		var climb_levels: int = -res.elev_diff
		res.atk_elev_mod_pct = -climb_levels * ELEV_CLIMB_FP_PCT
		res.def_elev_mod_pct = climb_levels * ELEV_CLIMB_ENEMY_FP_PCT
	else:
		res.atk_elev_mod_pct = 0
		res.def_elev_mod_pct = 0

	res.atk_total_mod_pct = res.atk_terrain_mod_pct + res.atk_elev_mod_pct
	res.def_total_mod_pct = res.def_terrain_mod_pct + res.def_elev_mod_pct

	res.atk_effective_firepower = maxi(10, int(round(float(attacker.firepower) * (1.0 + float(res.atk_total_mod_pct) / 100.0))))
	var atk_elev_armor_pct: int = maxi(0, res.elev_diff) * ELEV_HIGH_ARMOR_PCT
	res.atk_effective_armor = maxi(8, int(round(float(attacker.armor_rating) * (1.0 + float(from_tile.get_defense_modifier_pct() + atk_elev_armor_pct) / 100.0))))

	res.def_effective_firepower = maxi(10, int(round(float(defender.firepower) * (1.0 + float(target_tile.get_attack_modifier_pct() + res.def_elev_mod_pct) / 100.0))))
	res.def_effective_armor = maxi(8, int(round(float(defender.armor_rating) * (1.0 + float(res.def_total_mod_pct) / 100.0))))
	# Initiative (atk/def_effective_speed, first_striker) is filled in by BattleSession from its round-1 queue.

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
	return res

## Creates a live interactive BattleSession for BattleScreen.
## `p_seed` >= 0 seeds every hit/crit/variance/retreat roll so a battle can be replayed exactly
## (Battlefield passes GlobalState.next_battle_seed(); -1 keeps the shipping unseeded behaviour).
static func create_session(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData,
	can_defender_retreat: bool = true,
	p_seed: int = -1
) -> BattleSession:
	return BattleSession.new(attacker, defender, from_tile, target_tile, can_defender_retreat, p_seed)

## Deterministic session (no dice: every shot hits, no crits, no variance) for forecasts and tests.
static func create_deterministic_session(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData
) -> BattleSession:
	return BattleSession.new(attacker, defender, from_tile, target_tile, true, -1, true)

## Forecasts are deterministic, so identical inputs are served from this cache. The HUD asks on
## every hover and the AI once per reachable tile x adjacent enemy, each a full simulated battle.
static var _forecast_cache: Dictionary = {}
const FORECAST_CACHE_LIMIT: int = 4096

static func clear_forecast_cache() -> void:
	_forecast_cache.clear()

## Every MechData field the simulation reads (and nothing it does not, so identical walkers share an
## entry); a per-unit stat change can never serve a stale forecast.
static func _mech_key(m: MechData) -> Array:
	var ability_ids: Array = []
	for ab in m.abilities:
		ability_ids.append(ab.ability_id)
	return [
		m.chassis_id, int(m.faction), m.is_entrenched,
		m.current_armor, m.max_armor, m.current_energy, m.max_energy,
		m.firepower, m.armor_rating, m.speed, m.evasion, m.crit_chance, ability_ids,
	]

static func _forecast_key(attacker: MechData, defender: MechData, from_tile: GridTileData, target_tile: GridTileData) -> Array:
	return [
		_mech_key(attacker), _mech_key(defender),
		int(from_tile.terrain_type), from_tile.elevation, int(target_tile.terrain_type), target_tile.elevation, target_tile.is_objective,
		BalanceProbe.def_pct[int(defender.faction)],
	]

## Computes a fast, deterministic tactical forecast before committing to an engagement.
static func compute_forecast(attacker: MechData, defender: MechData, from_tile: GridTileData, target_tile: GridTileData) -> Dictionary:
	var key := _forecast_key(attacker, defender, from_tile, target_tile)
	if _forecast_cache.has(key):
		return (_forecast_cache[key] as Dictionary).duplicate()
	var sim_atk := attacker.duplicate_mech()
	var sim_def := defender.duplicate_mech()
	var res := resolve_skirmish(sim_atk, sim_def, from_tile, target_tile, false, true)
	var favor := "EVEN ENCOUNTER"
	if res.defender_destroyed and not res.attacker_destroyed:
		favor = "DECISIVE KILL PROJECTION"
	elif res.attacker_destroyed and not res.defender_destroyed:
		favor = "CRITICAL DANGER (LETHAL COUNTER)"
	elif res.attacker_won_clash:
		favor = "FAVORABLE ASSAULT"
	else:
		favor = "UNFAVORABLE EXCHANGE"

	if _forecast_cache.size() >= FORECAST_CACHE_LIMIT:
		_forecast_cache.clear()
	var forecast := {
		"atk_mod_pct": res.atk_total_mod_pct,
		"def_mod_pct": res.def_total_mod_pct,
		"elev_diff": res.elev_diff,
		"est_dmg_to_def": res.total_dmg_to_defender,
		"est_dmg_to_atk": res.total_dmg_to_attacker,
		"atk_eff_fp": res.atk_effective_firepower,
		"def_eff_fp": res.def_effective_firepower,
		"atk_spd": res.atk_effective_speed,  # round-1 initiative speeds, the ones the queue was built from
		"def_spd": res.def_effective_speed,
		"first_striker": "ATTACKER" if res.first_striker == "atk" else "DEFENDER",
		"rounds_fought": res.rounds_fought,
		"attacker_won": res.attacker_won_clash,
		"win_favor": favor,
		"approach_summary": res.approach_summary
	}
	_forecast_cache[key] = forecast
	return forecast.duplicate()

## Executes a complete turn-based battle resolution (used by forecasts, AI simulations, and tests).
## If `apply_to_units` is true, mutates `attacker` and `defender` Hull and Energy.
static func resolve_skirmish(
	attacker: MechData,
	defender: MechData,
	from_tile: GridTileData,
	target_tile: GridTileData,
	apply_to_units: bool = true,
	deterministic: bool = true
) -> SkirmishResult:
	var session := BattleSession.new(attacker, defender, from_tile, target_tile, true, -1, deterministic)
	session.auto_resolve()
	if apply_to_units:
		session.apply_to_units()
	return session.result
