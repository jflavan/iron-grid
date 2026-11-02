class_name RulesContent
extends RefCounted

## Text of the Rules of Engagement page (Command HQ). Every number is read from the game's own data
## (GridTileData, the chassis catalog, MechData / SkirmishEngine / Battlefield constants and the
## BalanceProbe defaults), so the page cannot drift from the rules when balance changes.
##
## chapters() -> [{title, blocks}], where a block is one of:
##   {"p": String}                              paragraph
##   {"key": String}                            key rule, drawn in the cursor colour
##   {"table": Array[PackedStringArray]}        rows, the first one is the header

const TABLE_GAP := 12        # px between table columns
const BLOCK_GAP := 4         # px after each block

## One-line role per chassis, written for this page (the rest of each row comes from the catalog).
const ROLES := {
	"vanguard": "ALL-ROUNDER: HOLDS LINES, TAKES CITIES",
	"goliath": "SIEGE TANK: ROADS, THEN SHORT HEAVY STRIKES",
	"falke": "SCOUT: FLANKS, RIVERS, HUNTS STRAGGLERS",
	"donner": "RIDGE GUN: CLIMBS CRAGS, FIRES DOWNHILL",
	"kommandant": "COMMAND: UPLINK BUFFS AND ECM JAMMING",
	"moloch": "BRAWLER: BREAKS CITY AND BUNKER DEFENDERS",
}
const CHASSIS_ORDER := ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]
const TERRAIN_ORDER := [
	GridTileData.TerrainType.ROAD, GridTileData.TerrainType.PLAIN, GridTileData.TerrainType.CITY,
	GridTileData.TerrainType.FOREST, GridTileData.TerrainType.RIVER, GridTileData.TerrainType.MOUNTAIN,
]

static func chapters() -> Array[Dictionary]:
	return [_how_you_win(), _movement(), _terrain(), _clash(), _after_clash(), _chassis_roles(), _tips()]

# ---------------------------------------------------------------- measuring (shared with MainMenu)
## Wrapped lines of a text block at `width` px.
static func block_lines(block: Dictionary, width: float) -> PackedStringArray:
	if block.has("table"):
		return PackedStringArray()
	return CrtUI.wrap_lines(str(block.get("p", block.get("key", ""))), width)

static func block_height(block: Dictionary, width: float) -> float:
	var n: int = (block["table"] as Array).size() if block.has("table") else block_lines(block, width).size()
	return n * CrtUI.LINE + BLOCK_GAP

## Height of a chapter's blocks (the title is drawn above them by the page).
static func chapter_height(chapter: Dictionary, width: float) -> float:
	var h := 0.0
	for b in chapter["blocks"]:
		h += block_height(b, width)
	return h

## Left x offset of each table column.
static func table_col_x(rows: Array) -> PackedFloat32Array:
	var widths: Array[float] = []
	for row in rows:
		for i in row.size():
			var w := float(PixelFont.text_width(CrtUI.sanitize(row[i])))
			if i >= widths.size():
				widths.append(w)
			else:
				widths[i] = maxf(widths[i], w)
	var xs := PackedFloat32Array()
	var x := 0.0
	for w in widths:
		xs.append(x)
		x += w + TABLE_GAP
	return xs

static func table_width(rows: Array) -> float:
	var xs := table_col_x(rows)
	var last := 0.0
	for row in rows:
		last = maxf(last, xs[row.size() - 1] + PixelFont.text_width(CrtUI.sanitize(row[row.size() - 1])))
	return last

# ---------------------------------------------------------------- helpers
static func _tile(t: GridTileData.TerrainType, elev: int = 1) -> GridTileData:
	return GridTileData.new(Vector2i.ZERO, t, elev)

static func _pct(v: int) -> String:
	return "%+d%%" % v

static func _chassis(id: String) -> MechData:
	return GlobalState.chassis_catalog[id]

## The Goliath stepping from a plain at L2 onto a mountain at L3, the case the page walks through.
static func _worked_example() -> Dictionary:
	return _chassis("goliath").get_step_fuel_breakdown(_tile(GridTileData.TerrainType.PLAIN, 2), _tile(GridTileData.TerrainType.MOUNTAIN, 3))

static func worked_example_needs() -> int:
	return int(_worked_example()["total"])

# ---------------------------------------------------------------- chapters
static func _how_you_win() -> Dictionary:
	var rows: Array = [PackedStringArray(["THEATER", "MISSION", "TURNS"])]
	for m: MapDefinition in GlobalState.maps:
		rows.append(PackedStringArray([m.map_name, m.get_strategy_name(), str(m.turn_limit)]))
	return {"title": "HOW YOU WIN", "blocks": [
		{"p": "Each turn runs PLAYER COMMAND PHASE -> any clashes -> SYNDICATE PHASE. Every walker gets one order per turn: move, attack (move onto an enemy) or WAIT/REFUEL."},
		{"key": "Wiping out the enemy wins any mission. Losing every walker loses it."},
		{"p": "PITCHED BATTLE: hold every objective at the end of a turn, or the majority when the turn limit runs out (an even split goes to the side with more walkers left; you win an exact tie)."},
		{"p": "FORTIFIED DEFENSE: keep at least one citadel node until the turn limit. If you hold none of them at the end of a turn, you lose."},
		{"p": "BLITZKRIEG OFFENSE: take a Syndicate HQ bunker and still hold it at the end of a turn. The final turn still counts. You lose only if no bunker is held when the turn limit runs out."},
		{"key": "Captures only count at the end of a full turn: they have to survive the enemy phase."},
		{"table": rows},
	]}

static func _movement() -> Dictionary:
	var fuel_rows: Array = [PackedStringArray(["TERRAIN", "FUEL"])]
	for t in TERRAIN_ORDER:
		var td := _tile(t)
		fuel_rows.append(PackedStringArray([td.get_terrain_name(), str(td.get_base_fuel_cost())]))
	var ch_rows: Array = [PackedStringArray(["CHASSIS", "TANK+REFUEL", "OFF-ROAD", "GEAR"])]
	for id in CHASSIS_ORDER:
		var m := _chassis(id)
		var gear := "AMPHIB: RIVER -2" if m.amphibious_gear else ("CLIMB GEAR: MTN -2, CLIMB -1" if m.mountain_gear else "-")
		var off := "%+d" % m.fuel_efficiency_mod if m.fuel_efficiency_mod != 0 else "0"
		ch_rows.append(PackedStringArray([m.callsign, "%d+%d" % [m.max_fuel, m.passive_refuel], off, gear]))
	var ex := _worked_example()
	var g := _chassis("goliath")
	return {"title": "MOVEMENT & FUEL", "blocks": [
		{"p": "Every step burns diesel: the terrain's fuel cost, plus the chassis adjustment off-road, plus 1 per elevation level climbed. Roads never take the surcharge."},
		{"key": "Attacking = stepping onto the enemy's tile, so a strike pays THAT tile's fuel. Hover an enemy to see what a strike needs."},
		{"table": fuel_rows},
		{"table": ch_rows},
		{"p": "Refuel: each chassis regains its refuel at the start of your turn. WAIT/REFUEL adds +%d now. A city adds +%d more each turn." % [MechData.WAIT_FUEL, MechData.CITY_FUEL]},
		{"key": "EXAMPLE: %s on a plain, enemy on a mountain one level up: %s = %d of its %d fuel. Move next to it, then strike on a fuller tank." % [
			g.callsign, " + ".join(StrikePlan.step_terms(ex)), int(ex["total"]), g.max_fuel]},
	]}

static func _terrain() -> Dictionary:
	var rows: Array = [PackedStringArray(["TERRAIN", "ATK", "DEF", "EVA"])]
	for t in TERRAIN_ORDER:
		var td := _tile(t)
		rows.append(PackedStringArray([td.get_terrain_name(), _pct(td.get_attack_modifier_pct()), _pct(td.get_defense_modifier_pct()), _pct(td.get_evasion_modifier_pct())]))
	var S := SkirmishEngine
	return {"title": "TERRAIN & HIGH GROUND", "blocks": [
		{"p": "Both walkers fight with the modifiers of the tile they stand on: the attacker its approach tile, the defender its own."},
		{"table": rows},
		{"key": "HIGH GROUND, per level you stand above the enemy: %s firepower and %s armor for you, %s firepower and armor for the enemy, %s hit, %s EVA, %s crit." % [
			_pct(S.ELEV_HIGH_FP_PCT), _pct(S.ELEV_HIGH_ARMOR_PCT), _pct(-S.ELEV_HIGH_ENEMY_FP_PCT), _pct(S.ELEV_ACC_PER_LEVEL), _pct(S.ELEV_EVA_PER_LEVEL), _pct(S.ELEV_CRIT_PER_LEVEL)]},
		{"p": "ATTACKING UPHILL, per level: %s firepower and %s hit for you, while the defender above gains %s firepower and armor plus its own high-ground hit, EVA and crit." % [
			_pct(-S.ELEV_CLIMB_FP_PCT), _pct(-S.ELEV_ACC_PER_LEVEL), _pct(S.ELEV_CLIMB_ENEMY_FP_PCT)]},
		{"p": "CITIES repair +%d hull and add +%d fuel and +%d EN at the start of each of your turns. WAIT/REFUEL in a city patches +%d hull more." % [
			BalanceProbe.upkeep[0], MechData.CITY_FUEL, MechData.CITY_ENERGY, BalanceProbe.patch[0]]},
		{"p": "RIVERS are a trap: expensive to wade, and a walker standing in one fights at a penalty."},
	]}

static func _clash() -> Dictionary:
	var S := SkirmishEngine
	return {"title": "THE CLASH", "blocks": [
		{"p": "Moving onto an enemy starts a turn-based battle. Turn order each round is by SPD. The attacker gets +%d SPD in round 1." % S.ROUND1_ATTACKER_SPD_BONUS},
		{"key": "FACING: REAR attack grants +%d%% ATK, %+d%% DEF shred, +%d%% Hit/Crit, +%d SPD and BYPASSES entrenchment! FLANK attack grants +%d%% ATK, %+d%% DEF shred and halves entrenchment." % [
			S.REAR_ATK_FP_PCT, S.REAR_DEF_ARMOR_PCT, S.REAR_ATK_ACC_PCT, S.REAR_ATK_SPD_BONUS, S.FLANK_ATK_FP_PCT, S.FLANK_DEF_ARMOR_PCT]},
		{"p": "FORMATIONS: Each adjacent ally adds +%d%% ATK crossfire (opposite = +%d%% pincer). Each defender ally adds +%d%% DEF escort. Press T to turn in place." % [
			S.ADJ_CROSSFIRE_FP_PER_ALLY, S.PINCER_CROSSFIRE_FP_BONUS, S.ADJ_ESCORT_DEF_PER_ALLY]},
		{"p": "ENTRENCHED (the defender used WAIT/REFUEL): %s DEF, +%d SPD in round 1 and +%d after, %s EVA and %s hit." % [
			_pct(BalanceProbe.def_pct[0]), S.ROUND1_ENTRENCHED_SPD_BONUS + S.ENTRENCHED_SPD_BONUS, S.ENTRENCHED_SPD_BONUS, _pct(S.ENTRENCHED_EVA_BONUS), _pct(S.ENTRENCHED_ACC_BONUS)]},
		{"key": "ATTACK: basic gun (0 EN). TECH: special systems (uses EN). DEFEND: next hit %d%% (+%d EN)." % [
			int(round(S.GUARD_DAMAGE_MULT * 100.0)), S.DEFEND_EN_GAIN]},
		{"key": "RETREAT: break off (%d%% %+d%%/SPD lead, between %d%%-%d%%). Defender must have an open tile behind." % [
			S.ESCAPE_BASE_PCT, S.ESCAPE_PER_SPD_PCT, S.ESCAPE_MIN_PCT, S.ESCAPE_MAX_PCT]},
		{"p": "A battle lasts until a walker is wrecked, one retreats, or %d rounds pass." % S.MAX_BATTLE_ROUNDS},
	]}

static func _after_clash() -> Dictionary:
	return {"title": "AFTER THE CLASH", "blocks": [
		{"key": "ATTACKER WINS (enemy wrecked, retreated, or out-damaged at the round limit): the defender is pushed to an open tile and the attacker takes its sector."},
		{"p": "If the beaten defender has no open tile to fall back to, it takes %d crush damage instead. If that wrecks it, the attacker takes the tile. Otherwise the attacker steps back to its approach tile." % Battlefield.CRUSH_DAMAGE},
		{"key": "ATTACKER REPELLED (it retreated, or took at least as much damage as it dealt by the round limit): it falls back to the tile it attacked from. A wrecked attacker is lost."},
		{"p": "A defender keeps its entrenchment unless the attacker won the clash."},
		{"p": "Every walker that attacked has used its order for the turn, win or lose."},
	]}

static func _chassis_roles() -> Dictionary:
	var rows: Array = [PackedStringArray(["CHASSIS", "FUEL", "SPD", "ROLE"])]
	for id in CHASSIS_ORDER:
		var m := _chassis(id)
		rows.append(PackedStringArray([m.callsign, "%d+%d" % [m.max_fuel, m.passive_refuel], str(m.speed), ROLES[id]]))
	return {"title": "CHASSIS ROLES", "blocks": [
		{"p": "FUEL is tank + refuel per turn. Full stats and TECH loadouts are in the HANGAR CODEX on the Command HQ screen."},
		{"table": rows},
	]}

static func _tips() -> Dictionary:
	var g := _chassis("goliath")
	return {"title": "FIELD TIPS", "blocks": [
		{"key": "Hover an enemy before you commit: a red tile can be struck, and OUT OF REACH tells you what a strike would cost."},
		{"p": ("Heavies live on roads. A %s pays %+d off-road, so it reaches a ridge only with a nearly full tank." % [g.callsign, g.fuel_efficiency_mod])
			if g.fuel_efficiency_mod > 0 else "Roads cost 1 fuel and never take a chassis surcharge: use them to bring slow walkers forward."},
		{"p": "To hit a walker on a crag, end your move next to it, then strike next turn after your refuel."},
		{"p": "Fight downhill. Every level of height you give up costs firepower and accuracy."},
		{"p": "Don't stop in a river. Wade through on a road bridge, or with a Falke."},
		{"p": "Hold cities: they repair, refuel and recharge you every turn, and they are hard to crack."},
		{"p": "WAIT/REFUEL when the enemy is coming to you: the entrenched defender often shoots first."},
		{"p": "Send Falke and Donner to the flanking ridges early. They spend the least fuel getting there."},
	]}
