class_name StoryMaps
extends RefCounted

## The twelve story mission maps, keyed by mission id (StoryCampaign pairs each with its dialog and
## triggers). Missions 2-4 are the three skirmish theaters with the named pilots in the line-up;
## the other nine are story-only maps. Spawn entries use the story keys of UnitContainer.spawn_unit.

const P := 0   # Coalition
const E := 1   # Syndikat

## Named pilots fly tuned machines (and the bosses are bosses).
const LEON_STATS := {"max_armor": 160, "armor_rating": 36, "evasion": 12}   # the Division's ace, and the mission fails without him
const ILSE_STATS := {"max_armor": 125, "firepower": 46}
const WOLFRAM_STATS := {"max_armor": 210, "firepower": 42, "armor_rating": 40, "speed": 28, "evasion": 14}
const BRANN_STATS := {"max_armor": 175}
const CHAD_REARGUARD_STATS := {"max_armor": 240, "armor_rating": 50}

static func build() -> Dictionary:
	var base: Array[MapDefinition] = MapCatalog.build()
	return {
		"m01": _aschefeld(),
		"m02": _iron_bridge(base[0]),
		"m03": _bastion(base[1]),
		"m04": _kessel(base[2]),
		"m05": _ravensfurt(),
		"m06": _eisenhammer(),
		"m07": _tauber(),
		"m08": _wolfs_pass(),
		"m09": _kaiserwall(),
		"m10": _crown_boulevard(),
		"m11": _throne_gate(),
		"m12": _iron_ghost(),
	}

# ---------------------------------------------------------------- spawn helpers
static func _u(faction: int, chassis: String, callsign: String, pos: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var sp := {"chassis": chassis, "callsign": callsign, "pos": pos, "faction": faction}
	sp.merge(extra)
	return sp

static func _leon(pos: Vector2i) -> Dictionary:
	return _u(P, "vanguard", "LEON (Sturmjäger)", pos, {"pilot": "leon", "stats": LEON_STATS})

static func _mira(pos: Vector2i) -> Dictionary:
	return _u(P, "falke", "MIRA (Spähfalke)", pos, {"pilot": "mira"})

static func _chad(pos: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var e := {"pilot": "chad"}
	e.merge(extra)
	return _u(P, "moloch", "CHAD (Brenner)", pos, e)

static func _brann(pos: Vector2i) -> Dictionary:
	return _u(P, "goliath", "OLD-IRON (Siegebreaker)", pos, {"pilot": "brann", "stats": BRANN_STATS})

static func _ilse(faction: int, pos: Vector2i, plot_armor: int = 1) -> Dictionary:
	return _u(faction, "donner", "ILSE (Spinne)", pos, {"pilot": "ilse", "stats": ILSE_STATS, "plot_armor": plot_armor})

static func _wolfram(pos: Vector2i, hold_until: int) -> Dictionary:
	return _u(E, "kommandant", "WOLFRAM (Kaiserstuhl)", pos,
		{"pilot": "wolfram", "livery": "blackclaw", "group": "claw", "stats": WOLFRAM_STATS, "plot_armor": 1,
		"hold_until": hold_until})

static func _claw(chassis: String, n: int, pos: Vector2i) -> Dictionary:
	return _u(E, chassis, "KLAUE-%d (Black Claw)" % n, pos, {"group": "claw"})

static func _map(id: String, name: String, subtitle: String, mode: MapDefinition.StrategyMode, turn_limit: int,
		terrain: PackedStringArray, elevation: PackedStringArray) -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = id
	m.map_name = name
	m.subtitle = subtitle
	m.strategy_mode = mode
	m.turn_limit = turn_limit
	m.terrain_codes = terrain
	m.elevation_rows = elevation
	m.height = terrain.size()
	m.width = terrain[0].split(" ", false).size()
	return m

# ---------------------------------------------------------------- ACT 1
static func _aschefeld() -> MapDefinition:
	var m := _map("story_aschefeld", "PROVING GROUND ASCHEFELD", "Sector 01 // Border Depot Line",
		MapDefinition.StrategyMode.PITCHED_BATTLE, 8, PackedStringArray([
			"F P P D P P F M",
			"P C P D P F P P",
			"D D D D D D D D",
			"P P F C P P C P",
			"P F P D P P P F",
			"M P P D F P P P",
		]), PackedStringArray([
			"1 1 1 1 1 1 1 2",
			"1 1 1 1 1 1 1 1",
			"1 1 1 1 1 1 1 1",
			"1 1 1 1 1 1 1 1",
			"1 1 1 1 1 1 1 1",
			"2 1 1 1 1 1 1 1",
		]))
	m.briefing_text = "BORDER SKIRMISH: A Syndikat raiding pair has crossed the wire at Aschefeld. One raider is already sitting on the East Fuel Depot. Three depots are in play: yours in the west, the one they took in the east, and the crossroads depot nobody holds yet."
	m.tactical_tip = "FIELD NOTES: Click a walker, then a highlighted tile to move. Attack from an adjacent tile; strike a walker's side or rear for a bonus. R digs in and refuels. Standing on a depot captures it."
	m.objective_text = "Destroy both raiders, hold all three depots at turn end, OR hold the majority when Turn 8 ends."
	m.win_text = "The Aschefeld depots are secure. The raiders never reached the fuel."
	m.lose_text = "The raiders held the depot line at Aschefeld."
	m.objectives = [
		{"pos": Vector2i(1, 1), "label": "West Fuel Depot", "owner": 0},
		{"pos": Vector2i(3, 3), "label": "Crossroads Depot", "owner": -1},
		{"pos": Vector2i(6, 3), "label": "East Fuel Depot", "owner": 1},
	]
	m.spawns = [
		_leon(Vector2i(0, 2)), _mira(Vector2i(0, 1)), _chad(Vector2i(0, 3)),
		_u(E, "vanguard", "RAUB-1 (Raider)", Vector2i(6, 3)),   # already sitting on the east depot
		_u(E, "falke", "RAUB-2 (Raider)", Vector2i(7, 4)),
	]
	return m

static func _iron_bridge(m: MapDefinition) -> MapDefinition:
	m.map_id = "story_iron_bridge"
	m.spawns = [
		_leon(Vector2i(1, 2)), _chad(Vector2i(1, 5)), _mira(Vector2i(2, 3)),
		_u(P, "donner", "CRAG-4 (Spinne)", Vector2i(1, 0)),
		_u(P, "goliath", "TITAN-2 (Siegebreaker)", Vector2i(0, 5)),
		_u(E, "vanguard", "ROTE-1 (Sturmjäger)", Vector2i(8, 2)),
		_u(E, "moloch", "GLUT-2 (Brenner)", Vector2i(8, 5)),
		_u(E, "falke", "JÄGER-3 (Spähfalke)", Vector2i(7, 4)),
		_u(E, "donner", "SPINNE-4 (Artillery)", Vector2i(8, 7)),
	]
	return m

static func _bastion(m: MapDefinition) -> MapDefinition:
	m.map_id = "story_bastion"
	m.win_text = "Citadel Höhenburg stands. The Black Claw's assault broke on the plateau."
	m.spawns = [
		_brann(Vector2i(6, 1)), _mira(Vector2i(6, 3)), _leon(Vector2i(6, 4)), _chad(Vector2i(6, 6)),
		_u(E, "moloch", "STURM-1 (Brenner)", Vector2i(2, 1)),
		_u(E, "vanguard", "STURM-2 (Sturmjäger)", Vector2i(1, 2)),
		_u(E, "goliath", "KOLOS-3 (Siegebreaker)", Vector2i(1, 6)),
		_u(E, "falke", "SPÄH-4 (Recon)", Vector2i(2, 4)),
		_ilse(E, Vector2i(0, 4)),
	]
	return m

# ---------------------------------------------------------------- ACT 2
static func _kessel(m: MapDefinition) -> MapDefinition:
	m.map_id = "story_kessel"
	m.spawns = [
		_chad(Vector2i(1, 3)),
		_u(P, "kommandant", "COMMAND-2 (Kaiserstuhl)", Vector2i(1, 4)),
		_leon(Vector2i(1, 1)), _mira(Vector2i(1, 6)),
		_u(P, "donner", "THUNDER-5 (Spinne)", Vector2i(0, 0)),
		_u(E, "vanguard", "WACHE-1 (Gate Guard)", Vector2i(5, 3)),
		_u(E, "moloch", "WACHE-2 (Bunker Brawler)", Vector2i(5, 4)),
		_u(E, "donner", "FLAK-3 (Ridge Artillery)", Vector2i(5, 1)),
		_u(E, "goliath", "KOMMANDANTUR-4 (HQ Boss)", Vector2i(8, 3)),
	]
	return m

static func _ravensfurt() -> MapDefinition:
	var m := _map("story_ravensfurt", "PURSUIT AT RAVENSFURT", "Sector 14 // Black Claw Rail Yard",
		MapDefinition.StrategyMode.PITCHED_BATTLE, 10, PackedStringArray([
			"M F P P D P P F M M",
			"F P C P D P P C P F",
			"P P P F D R R P P P",
			"D D D D C D D D D D",
			"P F P P D R R F P P",
			"P P C F D P P C P P",
			"F P P P D P F P P F",
			"M M F P D P P F M M",
		]), PackedStringArray([
			"3 2 1 1 1 1 1 2 3 3",
			"2 1 1 1 1 1 1 1 1 2",
			"1 1 1 2 1 0 0 1 1 1",
			"1 1 1 1 1 1 1 1 1 1",
			"1 2 1 1 1 0 0 2 1 1",
			"1 1 1 2 1 1 1 1 1 1",
			"2 1 1 1 1 1 2 1 1 2",
			"3 3 2 1 1 1 1 2 3 3",
		]))
	m.briefing_text = "PURSUIT: A Black Claw detachment is loading its wounded onto the Ravensfurt rail line. Lt. Hammerfeld has taken the squad forward without waiting for the Division. Five rail depots are in play; the Switchyard in the middle decides who owns the line."
	m.tactical_tip = "TACTICAL ADVISORY: Black Claw pilots are veterans and will look for your flanks. Keep your walkers adjacent to one another: every ally beside the target adds crossfire."
	m.objective_text = "Destroy the Black Claw detachment, hold all five rail depots at turn end, OR hold the majority when Turn 10 ends."
	m.win_text = "The Ravensfurt line is cut. The Black Claw left its rail yard burning."
	m.lose_text = "The Black Claw held the Ravensfurt line and got its trains out."
	m.objectives = [
		{"pos": Vector2i(2, 1), "label": "North Siding", "owner": 0},
		{"pos": Vector2i(2, 5), "label": "South Siding", "owner": 0},
		{"pos": Vector2i(4, 3), "label": "Ravensfurt Switchyard", "owner": -1},
		{"pos": Vector2i(7, 1), "label": "Coaling Tower", "owner": 1},
		{"pos": Vector2i(7, 5), "label": "Engine Shed", "owner": 1},
	]
	m.spawns = [
		_leon(Vector2i(1, 3)), _chad(Vector2i(0, 4)), _mira(Vector2i(1, 2)),
		_u(P, "donner", "CRAG-4 (Spinne)", Vector2i(0, 1)),
		_claw("kommandant", 1, Vector2i(8, 3)), _claw("moloch", 2, Vector2i(8, 4)),
		_claw("vanguard", 3, Vector2i(8, 2)),
	]
	return m

static func _eisenhammer() -> MapDefinition:
	var m := _map("story_eisenhammer", "THE EISENHAMMER FOUNDRY", "Sector 17 // Black Claw Armour Works",
		MapDefinition.StrategyMode.OFFENSE, 10, PackedStringArray([
			"M F P P R P F P M M",
			"P P F P R P P C P M",
			"P P P D D D P F P M",
			"D D D D R D D D C M",
			"D D D D R D D D C M",
			"P P P D D D P F P M",
			"P P F P R P P C P M",
			"M F P P R P F P M M",
		]), PackedStringArray([
			"3 2 1 1 0 1 2 2 3 4",
			"1 1 1 1 0 1 1 2 2 3",
			"1 1 1 1 1 1 1 2 2 3",
			"1 1 1 1 0 1 1 2 3 4",
			"1 1 1 1 0 1 1 2 3 4",
			"1 1 1 1 1 1 1 2 2 3",
			"1 1 1 1 0 1 1 2 2 3",
			"3 2 1 1 0 1 2 2 3 4",
		]))
	m.briefing_text = "FOUNDRY RAID: The Eisenhammer works build the Black Claw's walkers. The main road fords the Hammerbach; the two side bridges are dry. Take either Foundry Works bunker and hold it through the enemy turn."
	m.tactical_tip = "TACTICAL ADVISORY: Don't fight from the ford: the river costs fuel and firepower. Cross on the side bridges, then climb to the works. Someone on their side has a strange idea of fire support."
	m.objective_text = "Capture a Foundry Works bunker and hold it through the enemy turn, OR destroy every defender, within 10 Turns."
	m.win_text = "The Eisenhammer works are in Coalition hands. The Black Claw builds no more walkers here."
	m.lose_text = "The foundry was still pouring steel when the Division called the raid off."
	m.objectives = [
		{"pos": Vector2i(7, 1), "label": "North Smelter", "owner": 1},
		{"pos": Vector2i(7, 6), "label": "South Smelter", "owner": 1},
		{"pos": Vector2i(8, 3), "label": "Foundry Works North", "owner": 1},
		{"pos": Vector2i(8, 4), "label": "Foundry Works South", "owner": 1},
	]
	m.hq_positions = [Vector2i(8, 3), Vector2i(8, 4)]
	m.spawns = [
		_leon(Vector2i(1, 3)), _chad(Vector2i(1, 4)), _mira(Vector2i(1, 6)),
		_u(P, "donner", "CRAG-4 (Spinne)", Vector2i(0, 1)),
		_u(P, "kommandant", "COMMAND-2 (Kaiserstuhl)", Vector2i(0, 4)),
		_claw("vanguard", 1, Vector2i(6, 3)), _claw("moloch", 2, Vector2i(6, 4)),
		_claw("goliath", 3, Vector2i(8, 3)), _claw("falke", 4, Vector2i(5, 5)),
		_ilse(E, Vector2i(7, 1)),
	]
	return m

static func _tauber() -> MapDefinition:
	var m := _map("story_tauber", "THE TAUBER CAUSEWAY", "Sector 19 // Rearguard Action",
		MapDefinition.StrategyMode.DEFENSE, 6, PackedStringArray([
			"P P F R R R R P F M",
			"P F P R R R R P P P",
			"D D D D D D C D D D",
			"P P F R R R R P F P",
			"P F P R R R R F P P",
			"M P P R R R R P P M",
		]), PackedStringArray([
			"1 1 1 0 0 0 0 1 1 2",
			"1 1 1 0 0 0 0 1 1 1",
			"1 1 1 1 1 1 2 1 1 1",
			"1 1 1 0 0 0 0 1 1 1",
			"1 1 1 0 0 0 0 1 1 1",
			"2 1 1 0 0 0 0 1 1 2",
		]))
	m.briefing_text = "REARGUARD: The squad is pulling back across the Tauber with half its walkers on tow cables. One Brenner stays on the causeway fort so the rest can reach the Division's lines. Sgt. Brewster volunteered before anyone asked."
	m.tactical_tip = "TACTICAL ADVISORY: Stay on the fort. It repairs hull every turn, R digs in for more armour and a patch, and anything attacking from the river fights uphill out of the water. Every turn you hold is a turn the squad walks."
	m.objective_text = "Hold the Tauber Bridge Fort until Turn 6 ends. Sgt. Brewster must survive."
	m.win_text = "The Tauber Bridge Fort held through Turn 6. The squad is across."
	m.lose_text = "The Syndikat took the Tauber Bridge Fort and caught the column on the road."
	m.objectives = [{"pos": Vector2i(6, 2), "label": "Tauber Bridge Fort", "owner": 0}]
	m.spawns = [
		_chad(Vector2i(6, 2), {"stats": CHAD_REARGUARD_STATS}),
		_u(E, "vanguard", "HATZ-1 (Sturmjäger)", Vector2i(1, 2)),
		_u(E, "falke", "HATZ-2 (Spähfalke)", Vector2i(0, 1)),
	]
	return m

static func _wolfs_pass() -> MapDefinition:
	var m := _map("story_wolfs_pass", "WOLF'S PASS", "Sector 21 // The Black Claw Standard",
		MapDefinition.StrategyMode.ASSAULT, 8, PackedStringArray([
			"M M M F P P F M M M",
			"M F P P P F P P M M",
			"F P P F D D P F P M",
			"D D D D D C D D D D",
			"P P F P D D F P P F",
			"M P P P F P P P F M",
			"M M F P P P F M M M",
			"M M M M F F M M M M",
		]), PackedStringArray([
			"4 3 3 2 2 2 2 3 4 4",
			"3 2 2 2 2 2 2 2 3 4",
			"2 2 2 2 2 2 2 2 2 3",
			"1 1 2 2 2 2 2 2 1 1",
			"2 2 2 2 2 2 2 2 2 2",
			"3 2 2 2 2 2 2 2 2 3",
			"4 3 2 2 2 2 2 3 4 4",
			"4 4 3 3 2 2 3 3 4 4",
		]))
	m.briefing_text = "UNAUTHORISED SORTIE: Wolfram's black Kaiserstuhl has been sighted holding the pass road with two escorts. Lt. Hammerfeld is grounded. His Sturmjäger left the motor pool at 0340 anyway, and two more walkers followed it out."
	m.tactical_tip = "TACTICAL ADVISORY: Nobody has ever beaten Wolfram in a duel. If you mean to try, bring his hull down with crossfire before the Sturmjäger closes."
	m.objective_text = "Engage Wolfram at the pass. Bring him down, if anyone can."
	m.spawns = [
		_leon(Vector2i(1, 3)), _mira(Vector2i(1, 4)), _chad(Vector2i(0, 3)),
		_wolfram(Vector2i(8, 3), 4),   # he lets his escorts take the measure of the squad first
		_claw("vanguard", 2, Vector2i(8, 2)), _claw("falke", 3, Vector2i(8, 4)),
	]
	return m

# ---------------------------------------------------------------- ACT 3
static func _kaiserwall() -> MapDefinition:
	var m := _map("story_kaiserwall", "THE KAISERWALL", "Sector 30 // Outer Ring of the Capital",
		MapDefinition.StrategyMode.OFFENSE, 10, PackedStringArray([
			"P F P P M M P F P M",
			"P P F P D C P P C M",
			"D D P P D M F P P M",
			"P D D D D C D D C M",
			"P D D D D C D D C M",
			"D D P P D M F P P M",
			"P P F P D C P P C M",
			"P F P P M M P F P M",
		]), PackedStringArray([
			"1 1 1 1 3 3 2 2 2 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 3 2 2 2 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 3 2 2 2 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 3 3 2 2 2 4",
		]))
	m.briefing_text = "BREACH: The Kaiserwall is the capital's outer ring: a rampart with four gatehouses and the Wall Command bunker behind it. General Hammerfeld is leading the breach in person. He was asked not to."
	m.tactical_tip = "TACTICAL ADVISORY: The gatehouses are fortified cities on higher ground. Take a side gate with the Falke or the Spinne and hit the main gate's garrison in the flank instead of walking the Siegebreaker into its guns."
	m.objective_text = "Capture a Wall Command bunker and hold it through the enemy turn, OR destroy the garrison, within 10 Turns."
	m.win_text = "The Kaiserwall is breached. Old Iron's banner is on the Wall Command bunker."
	m.lose_text = "The breach failed. The Kaiserwall still stands between the Division and the capital."
	m.objectives = [
		{"pos": Vector2i(5, 3), "label": "Main Gate North", "owner": 1},
		{"pos": Vector2i(5, 4), "label": "Main Gate South", "owner": 1},
		{"pos": Vector2i(8, 3), "label": "Wall Command North", "owner": 1},
		{"pos": Vector2i(8, 4), "label": "Wall Command South", "owner": 1},
	]
	m.hq_positions = [Vector2i(8, 3), Vector2i(8, 4)]
	m.spawns = [
		_brann(Vector2i(1, 3)), _leon(Vector2i(1, 4)), _chad(Vector2i(0, 4)), _mira(Vector2i(1, 1)),
		_u(P, "donner", "CRAG-4 (Spinne)", Vector2i(1, 6)),
		_u(E, "vanguard", "WALL-1 (Gate Guard)", Vector2i(5, 3)),
		_u(E, "moloch", "WALL-2 (Gate Guard)", Vector2i(5, 4)),
		_u(E, "donner", "WALL-3 (Rampart Battery)", Vector2i(5, 1)),
		_u(E, "goliath", "WALL-4 (Wall Command)", Vector2i(8, 3)),
	]
	return m

static func _crown_boulevard() -> MapDefinition:
	var m := _map("story_crown_boulevard", "CROWN BOULEVARD", "Sector 33 // The Capital, Government Quarter",
		MapDefinition.StrategyMode.PITCHED_BATTLE, 10, PackedStringArray([
			"M P D P C P D P P M",
			"P C D F P F D C P F",
			"D D D D D D D D D D",
			"P F D P C P D F P P",
			"P P D F R F D P C P",
			"D D D D D D D D D D",
			"F C D P F P D C P P",
			"M P D P P P D P F M",
		]), PackedStringArray([
			"3 1 1 1 1 1 1 1 1 3",
			"1 1 1 1 1 1 1 1 1 2",
			"1 1 1 1 1 1 1 1 1 1",
			"1 2 1 1 1 1 1 2 1 1",
			"1 1 1 2 0 2 1 1 1 1",
			"1 1 1 1 1 1 1 1 1 1",
			"2 1 1 1 1 1 1 1 1 1",
			"3 1 1 1 1 1 1 1 2 3",
		]))
	m.briefing_text = "STREET FIGHT: The Division is inside the capital. Five strongpoints command the government quarter, and Crown Plaza in the middle commands the other four. Cmdr. Rotmann's battery is somewhere on the east side. She has been asking for Lt. Hammerfeld by name on the open band."
	m.tactical_tip = "TACTICAL ADVISORY: The boulevards are roads: cheap to cross and good to shoot from. Hold Crown Plaza and the district is yours."
	m.objective_text = "Destroy the garrison, hold all five strongpoints at turn end, OR hold the majority when Turn 10 ends."
	m.win_text = "The government quarter has fallen. The road to the Eisenthron is open."
	m.lose_text = "The garrison held the government quarter and threw the Division back to the wall."
	m.objectives = [
		{"pos": Vector2i(1, 1), "label": "West Gate Barracks", "owner": 0},
		{"pos": Vector2i(1, 6), "label": "Rail Terminus", "owner": 0},
		{"pos": Vector2i(4, 3), "label": "Crown Plaza", "owner": -1},
		{"pos": Vector2i(7, 1), "label": "Ministry of Steel", "owner": 1},
		{"pos": Vector2i(7, 6), "label": "City Arsenal", "owner": 1},
	]
	m.spawns = [
		_leon(Vector2i(0, 2)), _brann(Vector2i(1, 5)), _mira(Vector2i(1, 3)), _chad(Vector2i(1, 2)),
		_u(E, "vanguard", "KRONE-1 (Sturmjäger)", Vector2i(8, 2)),
		_u(E, "moloch", "KRONE-2 (Brenner)", Vector2i(8, 5)),
		_u(E, "falke", "KRONE-3 (Spähfalke)", Vector2i(7, 3)),
		_ilse(E, Vector2i(8, 6)),
	]
	return m

static func _throne_gate() -> MapDefinition:
	var m := _map("story_throne_gate", "GATE OF THE EISENTHRON", "Sector 35 // Marshal Grau's Fortress",
		MapDefinition.StrategyMode.OFFENSE, 10, PackedStringArray([
			"M M F P P F P M M M",
			"M P P F P P D C M M",
			"P P F P P D D F C M",
			"D D D D D D C D C M",
			"D D D D D D C D C M",
			"P P F P P D D F C M",
			"M P P F P P D C M M",
			"M M F P P F P M M M",
		]), PackedStringArray([
			"3 2 1 1 1 2 2 3 4 4",
			"2 1 1 1 1 2 2 3 4 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 2 2 2 3 4",
			"1 1 1 1 1 2 2 2 3 4",
			"2 1 1 1 1 2 2 3 4 4",
			"3 2 1 1 1 2 2 3 4 4",
		]))
	m.briefing_text = "FINAL ASSAULT: The Eisenthron is Grau's fortress. The Black Claw holds the approach under Wolfram's own standard; the Marshal's Garde holds the Throne Gate behind him. There is no other road in."
	m.tactical_tip = "TACTICAL ADVISORY: Wolfram is on the road in front of the barbican. Lt. Hammerfeld has asked that nobody else engage the black Kaiserstuhl. It is not an order anyone intends to enforce."
	m.objective_text = "Capture a Throne Gate bunker and hold it through the enemy turn, OR destroy every defender, within 10 Turns. Lt. Hammerfeld must survive."
	m.win_text = "The Throne Gate has fallen. Only the Marshal is left."
	m.lose_text = "The Throne Gate held. The Division's last assault broke on the Eisenthron."
	m.objectives = [
		{"pos": Vector2i(6, 3), "label": "Outer Barbican North", "owner": 1},
		{"pos": Vector2i(6, 4), "label": "Outer Barbican South", "owner": 1},
		{"pos": Vector2i(8, 3), "label": "Throne Gate North", "owner": 1},
		{"pos": Vector2i(8, 4), "label": "Throne Gate South", "owner": 1},
	]
	m.hq_positions = [Vector2i(8, 3), Vector2i(8, 4)]
	m.spawns = [
		_leon(Vector2i(0, 3)), _brann(Vector2i(1, 4)), _mira(Vector2i(1, 1)), _chad(Vector2i(1, 3)),
		_ilse(P, Vector2i(0, 2), 0),
		_wolfram(Vector2i(5, 3), 3),
		_claw("vanguard", 2, Vector2i(5, 4)), _claw("moloch", 3, Vector2i(6, 3)),
		_u(E, "goliath", "GARDE-1 (Throne Guard)", Vector2i(8, 3)),
		_u(E, "donner", "GARDE-2 (Throne Guard)", Vector2i(7, 1)),
	]
	return m

## The Garde companies that pour out of the gate when the Black Claw turns (mission 11's reveal).
static func throne_gate_reinforcements() -> Array:
	return [
		_u(E, "vanguard", "GARDE-3 (Throne Guard)", Vector2i(8, 4)),
		_u(E, "falke", "GARDE-4 (Throne Guard)", Vector2i(7, 4)),
	]

static func _iron_ghost() -> MapDefinition:
	var m := _map("story_iron_ghost", "IRON GHOST", "Sector 36 // The Eisenthron Parade Court",
		MapDefinition.StrategyMode.ASSAULT, 12, PackedStringArray([
			"M M C P D D P C M M",
			"M F P P D D P P F M",
			"P P F D D D D F P P",
			"D D D D C C D D D D",
			"D D D D C C D D D D",
			"P P F D D D D F P P",
			"M F P P D D P P F M",
			"M M C P D D P C M M",
		]), PackedStringArray([
			"3 3 2 1 1 1 1 2 3 3",
			"3 2 1 1 1 1 1 1 2 3",
			"1 1 1 1 1 1 1 1 1 1",
			"1 1 1 1 2 2 1 1 1 1",
			"1 1 1 1 2 2 1 1 1 1",
			"1 1 1 1 1 1 1 1 1 1",
			"3 2 1 1 1 1 1 1 2 3",
			"3 3 2 1 1 1 1 2 3 3",
		]))
	m.briefing_text = "THE MARSHAL: Supreme Marshal Grau has walked the Ragnarök out onto the parade court with the last of his Garde. It is the only one ever built. Konrad Varga has waited fifteen years to stand in front of it."
	m.tactical_tip = "TACTICAL ADVISORY: The Ragnarök out-guns and out-armours anything on the field. Do not duel it. Break the Garde, surround it, and strike its flanks and rear with crossfire."
	m.objective_text = "Destroy the Ragnarök before Turn 12 ends. Lt. Hammerfeld must survive."
	m.lose_text = "The Ragnarök was still standing when the Division's fuel ran out."
	m.spawns = [
		_leon(Vector2i(1, 3)),
		_u(P, "kommandant", "KONRAD (Kaiserstuhl)", Vector2i(1, 4),
			{"pilot": "konrad", "livery": "blackclaw", "stats": WOLFRAM_STATS, "plot_armor": 1}),
		_brann(Vector2i(0, 3)), _chad(Vector2i(0, 4)), _mira(Vector2i(1, 1)),
		_ilse(P, Vector2i(1, 6), 0),
		_u(E, "ragnarok", "GRAU (Ragnarök)", Vector2i(8, 3), {"pilot": "grau", "hold_until": 3, "plot_armor": 1}),
		_u(E, "goliath", "GARDE-1 (Throne Guard)", Vector2i(8, 4)),
		_u(E, "moloch", "GARDE-2 (Throne Guard)", Vector2i(7, 2)),
		_u(E, "vanguard", "GARDE-3 (Throne Guard)", Vector2i(7, 5)),
		_u(E, "donner", "GARDE-4 (Throne Guard)", Vector2i(9, 2)),
	]
	return m
