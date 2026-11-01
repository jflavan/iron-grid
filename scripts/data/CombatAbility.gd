class_name CombatAbility
extends RefCounted

## Represents a Special Weapon, Armor, or Tactical TECH Ability for an Armored Fighting Walker.
## Used in the classic Final Fantasy turn-based battle system.

var ability_id: String = ""
var ability_name: String = ""
var category: String = "WEAPON" # WEAPON, ARMOR, TACTIC
var energy_cost: int = 4
var power_multiplier: float = 1.35 # Multiplier on walker's effective Firepower (for WEAPON abilities)
var flat_power: int = 10           # Flat base damage added before mitigation (for WEAPON abilities)
var accuracy: int = 95             # Base hit chance % (1..100+)
var crit_bonus: int = 10           # Bonus critical hit chance %
var armor_pierce: float = 0.0      # Fraction of target defense ignored (0.0..0.5)
var effect_type: String = ""       # "", "PROTECT_RICOCHET", "BULKHEAD_WALL", "ANCHOR_BRACE", "REACTIVE_SHIELD", "THRUSTER_EVADE", "RECON_LOCK", "BALLISTIC_PLOT", "ECM_JAM", "CMD_UPLINK"
var description: String = ""

func _init(
	p_id: String = "",
	p_name: String = "",
	p_cat: String = "WEAPON",
	p_cost: int = 4,
	p_mult: float = 1.35,
	p_flat: int = 10,
	p_acc: int = 95,
	p_crit: int = 10,
	p_pierce: float = 0.0,
	p_effect: String = "",
	p_desc: String = ""
) -> void:
	ability_id = p_id
	ability_name = p_name
	category = p_cat
	energy_cost = p_cost
	power_multiplier = p_mult
	flat_power = p_flat
	accuracy = p_acc
	crit_bonus = p_crit
	armor_pierce = p_pierce
	effect_type = p_effect
	description = p_desc

func is_weapon() -> bool:
	return category == "WEAPON"

func duplicate_ability() -> CombatAbility:
	return CombatAbility.new(
		ability_id,
		ability_name,
		category,
		energy_cost,
		power_multiplier,
		flat_power,
		accuracy,
		crit_bonus,
		armor_pierce,
		effect_type,
		description
	)

func get_stats_summary() -> String:
	if is_weapon():
		var ap_txt := " | AP:%d%%" % int(round(armor_pierce * 100.0)) if armor_pierce > 0.0 else ""
		return "EN:%d | PWR:%d%%+%d | HIT:%d%% CRIT:+%d%%%s" % [
			energy_cost,
			int(round(power_multiplier * 100.0)),
			flat_power,
			accuracy,
			crit_bonus,
			ap_txt
		]
	else:
		return "EN:%d | %s SUPPORT TECH (NO SHOT)" % [energy_cost, category]

