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

## Script variable names, from the property list, so a new field is copied automatically.
static var _state_props: PackedStringArray = PackedStringArray()

func duplicate_ability() -> CombatAbility:
	if _state_props.is_empty():
		for prop in get_property_list():
			if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["name"] != "_state_props":
				_state_props.append(String(prop["name"]))
	var copy := CombatAbility.new()
	for n in _state_props:
		var v: Variant = get(n)
		if v is Array or v is Dictionary:
			v = v.duplicate(true)
		copy.set(n, v)
	return copy
