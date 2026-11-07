class_name BattleLayout
extends RefCounted

## Grid geometry -> battle screen placement. Engagements always come from an adjacent tile, so the
## gap between the walkers is fixed; only the side (from the isometric screen-x of the approach)
## and the elevation lift vary.

const PX_PER_LEVEL := 4
const MAX_LIFT := 12

const BACKDROP_BY_TERRAIN := {
	GridTileData.TerrainType.PLAIN: "plain",
	GridTileData.TerrainType.ROAD: "road",
	GridTileData.TerrainType.RIVER: "river",
	GridTileData.TerrainType.FOREST: "forest",
	GridTileData.TerrainType.CITY: "city",
	GridTileData.TerrainType.MOUNTAIN: "mountain",
}

## IsoGridMap.grid_to_screen puts screen x at (x - y) * TILE_W / 2, so compare (x - y).
static func attacker_on_left(from: Vector2i, target: Vector2i) -> bool:
	return (from.x - from.y) <= (target.x - target.y)

## Returns (attacker_dy, defender_dy) in native px; the higher walker is lifted (negative y).
static func elevation_offsets(elev_diff: int) -> Vector2i:
	var lift: int = mini(absi(elev_diff) * PX_PER_LEVEL, MAX_LIFT)
	if elev_diff > 0:
		return Vector2i(-lift, 0)
	if elev_diff < 0:
		return Vector2i(0, -lift)
	return Vector2i.ZERO

static var _backdrop_cache: Dictionary = {}

static func backdrop_path(terrain: int) -> String:
	return "res://assets/battle/backdrops/%s.png" % BACKDROP_BY_TERRAIN.get(terrain, "plain")

## `path_override` (tests) replaces the terrain's backdrop file; the cache logic is the same.
static func get_backdrop(terrain: int, path_override: String = "") -> Texture2D:
	var tex: Texture2D = _backdrop_cache.get(terrain)
	if tex == null:
		var path := path_override if path_override != "" else backdrop_path(terrain)
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		if tex != null:   # a missing backdrop is not cached, so adding the file fixes it without a restart
			_backdrop_cache[terrain] = tex
	return tex
