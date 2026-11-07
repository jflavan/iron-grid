class_name TerrainDefs
extends RefCounted

## Single data table for every terrain type: display names, map-file letter codes, fuel and combat
## modifiers and the top-surface colours the battlefield renderer uses. GridTileData's getters and
## the map loader read from here, so adding a terrain is one table row.

const T := GridTileData.TerrainType

## Per terrain: name, short (HUD) code, letters (map-file codes, upper case), fuel (base fuel to
## enter), def / atk / eva (modifier %), and `color`: the top-surface base RGB, `tinted` whether it
## brightens with elevation (by 0.045 per level above 1).
const TABLE: Dictionary = {
	T.PLAIN: {"name": "Open Plain", "short": "PLN", "letters": ["P"], "fuel": 2,
		"def": 5, "atk": 0, "eva": 0, "color": [0.31, 0.37, 0.24], "tinted": true},
	T.ROAD: {"name": "Transit Road", "short": "ROD", "letters": ["D", "R_D"], "fuel": 1,
		"def": 0, "atk": 5, "eva": 0, "color": [0.36, 0.35, 0.32], "tinted": true},
	T.RIVER: {"name": "River Ford", "short": "RIV", "letters": ["R"], "fuel": 4,
		"def": -15, "atk": -15, "eva": -10, "color": [0.16, 0.33, 0.38], "tinted": false},
	T.FOREST: {"name": "Trench Timber", "short": "TRN", "letters": ["F"], "fuel": 3,
		"def": 15, "atk": 5, "eva": 8, "color": [0.22, 0.30, 0.19], "tinted": true},
	T.CITY: {"name": "Fortified City", "short": "CTY", "letters": ["C"], "fuel": 2,
		"def": 25, "atk": 10, "eva": 10, "color": [0.42, 0.40, 0.36], "tinted": true},
	T.MOUNTAIN: {"name": "Mountain Crag", "short": "MTN", "letters": ["M"], "fuel": 5,
		"def": 30, "atk": 15, "eva": 10, "color": [0.45, 0.43, 0.39], "tinted": true},
}

const FALLBACK_COLOR := Color(0.3, 0.35, 0.25)

static var _code_to_type: Dictionary = {}
static var _top_cache: Dictionary = {} # (type * 16 + elevation) -> Color

## Letter code from a map file ("D", "R_D", "F"...) to a terrain type; unknown codes are PLAIN.
static func parse_code(code: String) -> GridTileData.TerrainType:
	if _code_to_type.is_empty():
		for t: int in TABLE.keys():
			for l: String in TABLE[t]["letters"]:
				_code_to_type[l] = t
	return _code_to_type.get(code.to_upper(), GridTileData.TerrainType.PLAIN)

static func is_known_code(code: String) -> bool:
	parse_code("P") # make sure the lookup is built
	return _code_to_type.has(code.to_upper())

## Top-surface colour of a tile (cached per terrain and elevation).
static func top_color(t: int, elev: int) -> Color:
	var key: int = t * 16 + elev
	if _top_cache.has(key):
		return _top_cache[key]
	var r: Dictionary = TABLE.get(t, {})
	var col: Color = FALLBACK_COLOR
	if not r.is_empty():
		var b: Array = r["color"]
		var tint: float = float(elev - 1) * 0.045 if r["tinted"] else 0.0
		col = Color(b[0] + tint, b[1] + tint, b[2] + tint)
	_top_cache[key] = col
	return col
