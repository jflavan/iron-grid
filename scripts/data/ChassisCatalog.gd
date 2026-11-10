class_name ChassisCatalog
extends RefCounted

## The six walker chassis templates, keyed by chassis id. GlobalState.chassis_catalog is filled
## from build() at startup; create_mech_instance() duplicates these templates.

## Display order used by the menus and the rules pages.
const ORDER: Array[String] = ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]

## `ability_catalog` is AbilityCatalog.build()'s result: each chassis gets duplicates of its abilities.
static func build(ability_catalog: Dictionary) -> Dictionary:
	var chassis_catalog: Dictionary = {}
	# 1. Vanguard (Medium Assault Walker)
	var vanguard := MechData.new(
		"vanguard", "KPZ-09 Sturmjäger", "VANGUARD", "vanguard", "Medium Assault Walker",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		110, 30, 34, 13, 0, 5,
		"Backbone bipedal walker of the 8th Iron Division. Balanced Krupp armor, 88mm cannon, and dependable diesel-turbine fuel economy across all terrain.",
		22, 8, 10, 14, 3, "kwk_88"
	)
	vanguard.abilities = [
		ability_catalog["kwk_88"].duplicate_ability(),
		ability_catalog["krupp_plate"].duplicate_ability(),
		ability_catalog["coax_mg"].duplicate_ability()
	]
	chassis_catalog["vanguard"] = vanguard

	# 2. Goliath (Super-Heavy Dreadnought)
	var goliath := MechData.new(
		"goliath", "VK-100 Siegebreaker", "GOLIATH", "goliath", "Super-Heavy Dreadnought",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		155, 44, 46, 10, 1, 4,
		"Towering fortress mech armed with a 210mm siege mortar. Nearly impervious in frontal duels, but slow and guzzles fuel off-road.",
		12, 3, 8, 14, 3, "flak_38"
	)
	goliath.abilities = [
		ability_catalog["morser_210"].duplicate_ability(),
		ability_catalog["ferro_bulkhead"].duplicate_ability(),
		ability_catalog["flak_38"].duplicate_ability()
	]
	chassis_catalog["goliath"] = goliath

	# 3. Falke (Light Recon Strider)
	var falke := MechData.new(
		"falke", "Sd.Kfz-22 Spähfalke", "FALKE", "falke", "Light Recon Strider",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		85, 21, 28, 17, -1, 6,
		"High-speed scout strider fitted with amphibious seals, gyro-thrusters, and optical targeting. Excels at high-evasion critical strikes and tactical retreats.",
		34, 18, 16, 16, 4, "autocannon_50"
	)
	falke.amphibious_gear = true
	falke.abilities = [
		ability_catalog["autocannon_50"].duplicate_ability(),
		ability_catalog["gyro_thruster"].duplicate_ability(),
		ability_catalog["recon_lock"].duplicate_ability()
	]
	chassis_catalog["falke"] = falke

	# 4. Donner (Quadruped Siege Artillery)
	var donner := MechData.new(
		"donner", "SPG-88 Spinne", "DONNER", "donner", "Quadruped Mountain Walker",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		98, 26, 43, 12, 0, 5,
		"Four-legged spider chassis engineered for climbing steep mountain crags. Braces with anchor struts to unleash devastating plunging rocket salvos.",
		18, 7, 12, 15, 3, "rocket_pod"
	)
	donner.mountain_gear = true
	donner.abilities = [
		ability_catalog["rocket_pod"].duplicate_ability(),
		ability_catalog["plunging_comp"].duplicate_ability(),
		ability_catalog["anchor_strut"].duplicate_ability()
	]
	chassis_catalog["donner"] = donner

	# 5. Kommandant (Tactical Command Mech)
	var kommandant := MechData.new(
		"kommandant", "Befehls-IV Kaiserstuhl", "KOMMANDANT", "kommandant", "Tactical Command Walker",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		120, 34, 36, 14, 0, 5,
		"Command-and-control walker equipped with Enigma ECM jammers, HQ battle-net uplinks, and a 105mm assault howitzer to cripple enemy targeting.",
		24, 10, 12, 18, 4, "assault_105"
	)
	kommandant.abilities = [
		ability_catalog["enigma_ecm"].duplicate_ability(),
		ability_catalog["cmd_override"].duplicate_ability(),
		ability_catalog["assault_105"].duplicate_ability()
	]
	chassis_catalog["kommandant"] = kommandant

	# 6. Moloch (Close-Quarters Siege Brawler)
	var moloch := MechData.new(
		"moloch", "Sturm-V Brenner", "MOLOCH", "moloch", "Heavy Urban Brawler",
		MechData.Faction.PLAYER, Vector2i.ZERO,
		135, 38, 41, 12, 0, 5,
		"Brutal close-combat walker armed with a thermite projector, tungsten pile-bunker, and explosive reactive armor bricks.",
		19, 6, 12, 14, 3, "thermite_lance"
	)
	moloch.abilities = [
		ability_catalog["thermite_lance"].duplicate_ability(),
		ability_catalog["pile_bunker"].duplicate_ability(),
		ability_catalog["ablative_shield"].duplicate_ability()
	]
	chassis_catalog["moloch"] = moloch
	return chassis_catalog

## Story-only chassis (not in ORDER: never in the hangar, the rules pages or a skirmish theater).
const BOSS_ORDER: Array[String] = ["ragnarok"]

static func build_bosses(ability_catalog: Dictionary) -> Dictionary:
	var bosses: Dictionary = {}
	var ragnarok := MechData.new(
		"ragnarok", "Pz.Kpfw-X Ragnarök", "RAGNARÖK", "ragnarok", "Super-Heavy Throne Walker",
		MechData.Faction.AI, Vector2i.ZERO,
		240, 46, 47, 10, 1, 4,
		"Supreme Marshal Grau's personal land-dreadnought: twin siege barrels on a walking fortress. Only one was ever built.",
		11, 2, 10, 18, 4, "flak_38"
	)
	ragnarok.abilities = [
		ability_catalog["morser_210"].duplicate_ability(),
		ability_catalog["ferro_bulkhead"].duplicate_ability(),
		ability_catalog["flak_38"].duplicate_ability()
	]
	bosses["ragnarok"] = ragnarok
	return bosses

## Every chassis id a story map may spawn.
static func story_ids() -> Array:
	return ORDER + BOSS_ORDER
