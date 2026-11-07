class_name Rules
extends RefCounted

## Shipped turn-economy rule values (what a walker gains by entrenching, being patched up in a
## City, or sitting out a turn). The engine, the HUD and the Rules page all read them through the
## accessors below, which let tests/balance.gd swap in experimental values per faction via
## BalanceProbe without the production code depending on a test harness for its defaults.

## DEF bonus (%) an entrenched defender gets in a skirmish.
const ENTRENCH_DEF_PCT: int = 15
## Armor repaired per turn while entrenched (the field "patch").
const PATCH_ARMOR: int = 8
## Armor repaired by start-of-turn upkeep on a City tile.
const UPKEEP_ARMOR: int = 12

static func entrench_def_pct(faction: int) -> int:
	return BalanceProbe.def_pct[faction]

static func patch_armor(faction: int) -> int:
	return BalanceProbe.patch[faction]

static func upkeep_armor(faction: int) -> int:
	return BalanceProbe.upkeep[faction]
