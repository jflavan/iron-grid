class_name MapCatalog
extends RefCounted

## The playable mission definitions (terrain, objectives, spawns, briefings). GlobalState.maps is
## filled from build() at startup.

static func build() -> Array[MapDefinition]:
	var maps: Array[MapDefinition] = []

	# =========================================================================
	# MAP 1: OPERATION IRON BRIDGE — PITCHED BATTLE (10x8)
	# Terrain codes: P=Plain, D=Road, R=River, F=Forest/Trench, C=City, M=Mountain
	# =========================================================================
	var map1 := MapDefinition.new()
	map1.map_id = "iron_bridge"
	map1.map_name = "OPERATION: IRON BRIDGE"
	map1.subtitle = "Sector 04 // Rhine-Fulda Contested Crossing"
	map1.strategy_mode = MapDefinition.StrategyMode.PITCHED_BATTLE
	map1.turn_limit = 10
	map1.width = 10
	map1.height = 8
	map1.briefing_text = (
		"PITCHED BATTLE: Both forces converge on the industrial river valley of Sector 04. " +
		"Two reinforced stone bridges carry the main transit roads across the river, and between them a fortified depot sits on the river island. " +
		"Five objectives are in play: each side starts with its two bank bridgeheads, so the Central Island Depot decides the battle. Take it and hold it."
	)
	map1.tactical_tip = (
		"TACTICAL ADVISORY: Every city here sits level with the roads, so a garrison can be stormed without an uphill penalty, and digging in alone won't hold the line. " +
		"Rivers cost %d Fuel and impose -15%% ATK / -15%% DEF / -10%% EVA: cross on the bridges, or wade with a Falke. Concentrate your attacks on one target at a time." % RulesContent.terrain_fuel(GridTileData.new(Vector2i.ZERO, GridTileData.TerrainType.RIVER, 1), RulesContent.default_fuel_usage())
	)
	# Every city sits level with the roads (height 1) and a neutral Central Island Depot stands
	# between the bridges: five objectives can't split 2-2, so digging in can't run out the clock.
	map1.terrain_codes = PackedStringArray([
		"M M F P R R P F M M",
		"F P P C R R C P P F",
		"D D D D D D D D D D",
		"P F P P R R P P F P",
		"P F P P C R P P F P",
		"D D D D D D D D D D",
		"F P P C R R C P P F",
		"M M F P R R P F M M"
	])
	map1.elevation_rows = PackedStringArray([
		"3 3 2 1 0 0 1 2 3 3",
		"2 1 1 1 0 0 1 1 1 2",
		"1 1 1 1 1 1 1 1 1 1",
		"1 2 1 1 0 0 1 1 2 1",
		"1 2 1 1 1 0 1 1 2 1",
		"1 1 1 1 1 1 1 1 1 1",
		"2 1 1 1 0 0 1 1 1 2",
		"3 3 2 1 0 0 1 2 3 3"
	])
	map1.objectives = [
		{ "pos": Vector2i(3, 1), "label": "North West Bridgehead", "owner": 0 },
		{ "pos": Vector2i(6, 1), "label": "North East Bridgehead", "owner": 1 },
		{ "pos": Vector2i(3, 6), "label": "South West Bridgehead", "owner": 0 },
		{ "pos": Vector2i(6, 6), "label": "South East Bridgehead", "owner": 1 },
		{ "pos": Vector2i(4, 4), "label": "Central Island Depot", "owner": -1 }
	]
	map1.spawns = [
		# Player Coalition Forces (West Side)
		{ "chassis": "vanguard", "callsign": "IRON-1 (Sturmjäger)", "pos": Vector2i(1, 2), "faction": 0 },
		{ "chassis": "goliath",  "callsign": "TITAN-2 (Siegebreaker)", "pos": Vector2i(0, 5), "faction": 0 },
		{ "chassis": "falke",    "callsign": "SWIFT-3 (Spähfalke)", "pos": Vector2i(2, 3), "faction": 0 },
		{ "chassis": "donner",   "callsign": "CRAG-4 (Spinne)", "pos": Vector2i(1, 0), "faction": 0 },
		# AI Syndicate Forces (East Side)
		{ "chassis": "vanguard", "callsign": "ROTE-1 (Sturmjäger)", "pos": Vector2i(8, 2), "faction": 1 },
		{ "chassis": "moloch",   "callsign": "GLUT-2 (Brenner)", "pos": Vector2i(8, 5), "faction": 1 },
		{ "chassis": "falke",    "callsign": "JÄGER-3 (Spähfalke)", "pos": Vector2i(7, 4), "faction": 1 },
		{ "chassis": "donner",   "callsign": "SPINNE-4 (Artillery)", "pos": Vector2i(8, 7), "faction": 1 }
	]
	maps.append(map1)

	# =========================================================================
	# MAP 2: BASTION REDOUBT — FORTIFIED DEFENSE (10x8)
	# =========================================================================
	var map2 := MapDefinition.new()
	map2.map_id = "bastion_redoubt"
	map2.map_name = "BASTION REDOUBT"
	map2.subtitle = "Sector 09 // Citadel Höhenburg Defense"
	map2.strategy_mode = MapDefinition.StrategyMode.DEFENSE
	map2.turn_limit = 8
	map2.width = 10
	map2.height = 8
	map2.briefing_text = (
		"FORTIFIED DEFENSE: A numerically superior Kriegs-Syndikat armored column is storming up the Western valley toward Citadel Höhenburg. " +
		"Your defenders command the Eastern mountain plateau (Elevation 3-4). Hold the Citadel Cities until Turn 8 or annihilate the assault wave!"
	)
	map2.tactical_tip = (
		"TACTICAL ADVISORY: Each level of Elevation advantage grants +12% Firepower, +10% Armor deflection, +4% Hit/EVA & +5% Crit! " +
		"Let enemy walkers burn fuel climbing the mountain switchbacks or wading the moat river, then counter-strike from Elevation 3-4!"
	)
	map2.terrain_codes = PackedStringArray([
		"P P F R P M M M M M",
		"D D D D D D C M C M",
		"P F P R P F M M M M",
		"P P P R F P M C M M",
		"P P P R F P M C M M",
		"P F P R P F M M M M",
		"D D D D D D C M C M",
		"P P F R P M M M M M"
	])
	map2.elevation_rows = PackedStringArray([
		"1 1 1 0 2 3 3 4 4 4",
		"1 1 1 1 2 2 3 3 4 4",
		"1 2 1 0 2 2 3 3 4 4",
		"1 1 1 0 2 2 3 4 4 4",
		"1 1 1 0 2 2 3 4 4 4",
		"1 2 1 0 2 2 3 3 4 4",
		"1 1 1 1 2 2 3 3 4 4",
		"1 1 1 0 2 3 3 4 4 4"
	])
	map2.objectives = [
		{ "pos": Vector2i(6, 1), "label": "North Bastion Gate", "owner": 0 },
		{ "pos": Vector2i(6, 6), "label": "South Bastion Gate", "owner": 0 },
		{ "pos": Vector2i(7, 3), "label": "Citadel Upper Core", "owner": 0 },
		{ "pos": Vector2i(7, 4), "label": "Citadel Lower Core", "owner": 0 }
	]
	map2.spawns = [
		# Player Defenders on High Ground (East Citadel)
		{ "chassis": "goliath",    "callsign": "BASTION-1 (Dreadnought)", "pos": Vector2i(6, 1), "faction": 0 },
		{ "chassis": "donner",     "callsign": "EYRIE-2 (Spinne)", "pos": Vector2i(6, 3), "faction": 0 },
		{ "chassis": "kommandant", "callsign": "AEGIS-3 (Command)", "pos": Vector2i(6, 4), "faction": 0 },
		{ "chassis": "vanguard",   "callsign": "WATCH-4 (Sturmjäger)", "pos": Vector2i(6, 6), "faction": 0 },
		# AI Assault Wave (West Valley - 5 Units!)
		{ "chassis": "moloch",     "callsign": "STURM-1 (Brenner)", "pos": Vector2i(2, 1), "faction": 1 },
		{ "chassis": "vanguard",   "callsign": "STURM-2 (Sturmjäger)", "pos": Vector2i(1, 2), "faction": 1 },
		{ "chassis": "goliath",    "callsign": "KOLOS-3 (Siegebreaker)", "pos": Vector2i(1, 6), "faction": 1 },
		{ "chassis": "falke",      "callsign": "SPÄH-4 (Recon)", "pos": Vector2i(2, 4), "faction": 1 },
		{ "chassis": "donner",     "callsign": "FEUER-5 (Spinne)", "pos": Vector2i(0, 4), "faction": 1 }
	]
	maps.append(map2)

	# =========================================================================
	# MAP 3: BREAKTHROUGH AT KESSEL-9 — BLITZKRIEG OFFENSE (10x8)
	# =========================================================================
	var map3 := MapDefinition.new()
	map3.map_id = "kessel_breakthrough"
	map3.map_name = "BREAKTHROUGH AT KESSEL-9"
	map3.subtitle = "Sector 12 // Armored Spearhead Assault"
	map3.strategy_mode = MapDefinition.StrategyMode.OFFENSE
	map3.turn_limit = 10
	map3.width = 10
	map3.height = 8
	map3.briefing_text = (
		"BLITZKRIEG OFFENSE: Syndicate command has fortified the Kessel-9 rail nexus. " +
		"Lead an armored spearhead of five mobile walkers down the central highway or around the river/mountain flanks to capture the Syndicate HQ Bunker at (8,3) or (8,4) before Turn 10!"
	)
	map3.tactical_tip = (
		"TACTICAL ADVISORY: Don't attack entrenched City/Mountain defenders from low rivers! " +
		"Use Falke Striders and Donner Mountain Walkers to seize the flanking ridges (Elevation 3), then strike the HQ Bunker with Moloch & Kommandant units!"
	)
	map3.terrain_codes = PackedStringArray([
		"P D D F M M F P M M",
		"P D P P F C F P C M",
		"P P P R R F P P F M",
		"D D D D D C D D C M",
		"D D D D D C D D C M",
		"P P P R R F P P F M",
		"P D P P F C F P C M",
		"P D D F M M F P M M"
	])
	map3.elevation_rows = PackedStringArray([
		"1 1 2 2 3 3 2 2 3 4",
		"1 1 1 2 2 2 2 2 3 3",
		"1 1 1 0 0 2 2 2 3 3",
		"1 1 1 1 1 2 2 2 3 4",
		"1 1 1 1 1 2 2 2 3 4",
		"1 1 1 0 0 2 2 2 3 3",
		"1 1 1 2 2 2 2 2 3 3",
		"1 1 2 2 3 3 2 2 3 4"
	])
	map3.objectives = [
		{ "pos": Vector2i(5, 3), "label": "Outer Gate North", "owner": 1 },
		{ "pos": Vector2i(5, 4), "label": "Outer Gate South", "owner": 1 },
		{ "pos": Vector2i(8, 3), "label": "Syndicate HQ North", "owner": 1 },
		{ "pos": Vector2i(8, 4), "label": "Syndicate HQ South", "owner": 1 }
	]
	map3.hq_positions = [Vector2i(8, 3), Vector2i(8, 4)]
	map3.spawns = [
		# Player Strike Force (5 Units on West Spearhead)
		{ "chassis": "moloch",     "callsign": "SPEAR-1 (Brenner)", "pos": Vector2i(1, 3), "faction": 0 },
		{ "chassis": "kommandant", "callsign": "COMMAND-2 (Kaiserstuhl)", "pos": Vector2i(1, 4), "faction": 0 },
		{ "chassis": "vanguard",   "callsign": "LANCE-3 (Sturmjäger)", "pos": Vector2i(1, 1), "faction": 0 },
		{ "chassis": "falke",      "callsign": "GHOST-4 (Spähfalke)", "pos": Vector2i(1, 6), "faction": 0 },
		{ "chassis": "donner",     "callsign": "THUNDER-5 (Spinne)", "pos": Vector2i(0, 0), "faction": 0 },
		# AI Entrenched Defense Line (4 Units guarding Gates & HQ)
		{ "chassis": "vanguard",   "callsign": "WACHE-1 (Gate Guard)", "pos": Vector2i(5, 3), "faction": 1 },
		{ "chassis": "moloch",     "callsign": "WACHE-2 (Bunker Brawler)", "pos": Vector2i(5, 4), "faction": 1 },
		{ "chassis": "donner",     "callsign": "FLAK-3 (Ridge Artillery)", "pos": Vector2i(5, 1), "faction": 1 },
		{ "chassis": "goliath",    "callsign": "KOMMANDANTUR-4 (HQ Boss)", "pos": Vector2i(8, 3), "faction": 1 }
	]
	maps.append(map3)
	return maps
