class_name AbilityCatalog
extends RefCounted

## The TECH ability definitions (9 weapons, 9 armor / tactic / support), keyed by ability id.
## GlobalState.ability_catalog is filled from build() at startup.

static func build() -> Dictionary:
	var ability_catalog: Dictionary = {}
	# 9 Weapon TECH Abilities (Category: WEAPON)
	ability_catalog["kwk_88"] = CombatAbility.new(
		"kwk_88", "88mm KwK AP-Shell", "WEAPON",
		4, 1.35, 12, 96, 15, 0.20, "",
		"High-velocity armor-piercing cannon shell (20% Armor Pierce)."
	)
	ability_catalog["coax_mg"] = CombatAbility.new(
		"coax_mg", "Twin MG-42 Salvo", "WEAPON",
		3, 1.18, 10, 100, 12, 0.0, "",
		"Rapid-fire tracer barrage: 100% base accuracy and +12% crit, before the target's evasion."
	)
	ability_catalog["morser_210"] = CombatAbility.new(
		"morser_210", "210mm Siege Howitzer", "WEAPON",
		6, 1.50, 18, 90, 15, 0.25, "",
		"Devastating heavy bunker-busting shell (25% Armor Pierce)."
	)
	ability_catalog["flak_38"] = CombatAbility.new(
		"flak_38", "Quad Flak-38 Battery", "WEAPON",
		4, 1.22, 12, 98, 14, 0.10, "",
		"Multi-barrel high-velocity autocannon burst."
	)
	ability_catalog["autocannon_50"] = CombatAbility.new(
		"autocannon_50", "50mm Rapid Autocannon", "WEAPON",
		3, 1.30, 11, 98, 20, 0.15, "",
		"High-cyclic flanker cannon aimed at critical weakpoints."
	)
	ability_catalog["rocket_pod"] = CombatAbility.new(
		"rocket_pod", "Nebelwerfer Rocket Pod", "WEAPON",
		5, 1.45, 16, 92, 14, 0.15, "",
		"Saturation high-angle rocket artillery barrage."
	)
	ability_catalog["assault_105"] = CombatAbility.new(
		"assault_105", "105mm StuH Howitzer", "WEAPON",
		4, 1.38, 14, 96, 15, 0.15, "",
		"Direct-fire assault gun engineered for urban combat."
	)
	ability_catalog["thermite_lance"] = CombatAbility.new(
		"thermite_lance", "Thermite Flame Lance", "WEAPON",
		4, 1.40, 14, 96, 12, 0.25, "",
		"Superheated plasma-diesel stream that melts hull plating."
	)
	ability_catalog["pile_bunker"] = CombatAbility.new(
		"pile_bunker", "Hydraulic Pile-Bunker", "WEAPON",
		5, 1.55, 18, 90, 22, 0.35, "",
		"Explosive-driven tungsten spike ram (35% Armor Pierce)."
	)

	# 9 Support / Armor / Tactical TECH Abilities (Pure FF Support/Status turns — no weapon shot)
	ability_catalog["krupp_plate"] = CombatAbility.new(
		"krupp_plate", "Sloped Krupp Plate", "ARMOR",
		4, 0.0, 0, 100, 0, 0.0, "PROTECT_RICOCHET",
		"Angles hull glacis: +35% DEF & ricochet-blunts the next enemy attack."
	)
	ability_catalog["ferro_bulkhead"] = CombatAbility.new(
		"ferro_bulkhead", "Ferro-Bunker Bulkhead", "ARMOR",
		5, 0.0, 0, 100, 0, 0.0, "BULKHEAD_WALL",
		"Drops a massive frontal shield slab: +45% DEF for the entire battle."
	)
	ability_catalog["anchor_strut"] = CombatAbility.new(
		"anchor_strut", "Quad Anchor Struts", "ARMOR",
		4, 0.0, 0, 100, 0, 0.0, "ANCHOR_BRACE",
		"Locks hydraulic outriggers: +30% DEF, +20% Accuracy & +15% Crit."
	)
	ability_catalog["ablative_shield"] = CombatAbility.new(
		"ablative_shield", "Reactive Shield Wall", "ARMOR",
		4, 0.0, 0, 100, 0, 0.0, "REACTIVE_SHIELD",
		"Arms explosive armor bricks: +20% DEF & halves the next hit taken."
	)
	ability_catalog["gyro_thruster"] = CombatAbility.new(
		"gyro_thruster", "Gyro-Flank Thrusters", "TACTIC",
		4, 0.0, 0, 100, 0, 0.0, "THRUSTER_EVADE",
		"Steam-boosted lateral jets: +30% Evasion, +35% Speed & dodges/blunts next hit."
	)
	ability_catalog["recon_lock"] = CombatAbility.new(
		"recon_lock", "Optical Rangefinder", "TACTIC",
		4, 0.0, 0, 100, 0, 0.0, "RECON_LOCK",
		"Stereoscopic target lock: +35% Accuracy, +35% Crit Chance & +20% ATK."
	)
	ability_catalog["plunging_comp"] = CombatAbility.new(
		"plunging_comp", "Elevation Ballistics", "TACTIC",
		4, 0.0, 0, 100, 0, 0.0, "BALLISTIC_PLOT",
		"Analog fire-control solution: +30% ATK, +25% Crit & +20% Armor Pierce."
	)
	ability_catalog["enigma_ecm"] = CombatAbility.new(
		"enigma_ecm", "Enigma ECM Scrambler", "TACTIC",
		4, 0.0, 0, 100, 0, 0.0, "ECM_JAM",
		"Broad-spectrum jammer: inflicts -30% Accuracy, -25% Speed & -20% DEF on foe."
	)
	ability_catalog["cmd_override"] = CombatAbility.new(
		"cmd_override", "Command Uplink", "TACTIC",
		5, 0.0, 0, 100, 0, 0.0, "CMD_UPLINK",
		"HQ battle-net pulse: boosts +25% ATK, +25% DEF, +15% Speed & +15% Accuracy."
	)
	return ability_catalog
