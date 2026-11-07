class_name UnitContainer
extends Node2D

## Manages all active MechUnit instances on the battlefield, Y-sorted for isometric depth.
## Performs node collision checks to detect when two opposing units occupy the same grid node.

var units: Array[MechUnit] = []

## Bumped whenever the set of occupied tiles may have changed (spawn, removal, move_unit()), so a
## caller can cache build_occupied_map() / anything derived from it and compare epochs.
var occupancy_epoch: int = 0

## The one way a walker changes tile: writes its grid position and bumps the occupancy epoch.
func move_unit(u: MechUnit, to: Vector2i) -> void:
	u.mech_data.grid_pos = to
	occupancy_epoch += 1

func _ready() -> void:
	y_sort_enabled = true

func clear_units() -> void:
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	occupancy_epoch += 1

func spawn_units_for_map(map_def: MapDefinition, grid_map: IsoGridMap) -> void:
	clear_units()
	var idx: int = 0
	for sp in map_def.spawns:
		idx += 1
		var chassis_id: String = str(sp.get("chassis", "vanguard"))
		var callsign: String = str(sp.get("callsign", "UNIT-%d" % idx))
		var pos: Vector2i = sp.get("pos", Vector2i.ZERO)
		var fac_int: int = int(sp.get("faction", 0))
		var fac: MechData.Faction = MechData.Faction.PLAYER if fac_int == 0 else MechData.Faction.AI

		var m_data := GlobalState.create_mech_instance(chassis_id, fac, callsign, pos, str(idx))
		m_data.facing = Vector2i(1, 0) if fac == MechData.Faction.PLAYER else Vector2i(-1, 0)
		var m_node := MechUnit.new()
		add_child(m_node)
		m_node.setup(m_data, grid_map.grid_to_screen(pos, true))
		units.append(m_node)
	occupancy_epoch += 1

func get_unit_at(coords: Vector2i, exclude_unit: MechUnit = null) -> MechUnit:
	for u in units:
		if u != exclude_unit and MechUnit.is_live(u) and u.mech_data.grid_pos == coords:
			return u
	return null

func build_occupied_map(exclude_unit: MechUnit = null) -> Dictionary:
	var occ: Dictionary = {}
	for u in units:
		if u != exclude_unit and MechUnit.is_live(u):
			occ[u.mech_data.grid_pos] = u.mech_data
	return occ

func get_faction_units(faction: MechData.Faction) -> Array[MechUnit]:
	var list: Array[MechUnit] = []
	for u in units:
		if MechUnit.is_live(u) and u.mech_data.faction == faction:
			list.append(u)
	return list

func remove_destroyed_unit(u: MechUnit) -> void:
	if u == null:
		return
	units.erase(u)
	occupancy_epoch += 1
	if is_instance_valid(u):
		_spawn_explosion_effect(u.position)
		u.queue_free()

func _spawn_explosion_effect(screen_pos: Vector2) -> void:
	var fx := Node2D.new()
	fx.position = screen_pos
	add_child(fx)
	var tween := create_tween()
	fx.set_meta("t", 0.0)
	fx.draw.connect(func():
		var t: float = float(fx.get_meta("t", 0.0))
		var r1: float = lerpf(8.0, 52.0, t)
		var alpha: float = clampf(1.0 - t, 0.0, 1.0)
		fx.draw_circle(Vector2(0, -14), r1, Color(1.0, 0.45, 0.12, alpha * 0.65))
		fx.draw_circle(Vector2(0, -14), r1 * 0.55, Color(1.0, 0.92, 0.55, alpha * 0.85))
		fx.draw_arc(Vector2(0, -14), r1 * 1.1, 0, TAU, 24, Color(0.95, 0.25, 0.1, alpha), 3.0)
	)
	tween.tween_method(func(val: float):
		if is_instance_valid(fx):
			fx.set_meta("t", val)
			fx.queue_redraw()
	, 0.0, 1.0, 0.48)
	tween.tween_callback(func():
		if is_instance_valid(fx):
			fx.queue_free()
	)

## Calculates adjacent tactical formation (crossfire, pincer, escort screen, suppression)
## for an engagement where attacker launches from `from_pos` into `target_pos`. A caller that already
## holds an occupancy map (the AI) uses the static formation_context directly.
func get_formation_context(target_pos: Vector2i, from_pos: Vector2i, attacker_faction: int) -> Dictionary:
	return formation_context(build_occupied_map(), target_pos, from_pos, attacker_faction)

static func formation_context(occ: Dictionary, target_pos: Vector2i, from_pos: Vector2i, attacker_faction: int) -> Dictionary:
	var atk_allies: int = 0
	var def_allies: int = 0
	var is_pincer: bool = false
	var pincer_opposite_pos: Vector2i = target_pos + (target_pos - from_pos)

	for d in TerrainGrid.DIRS:
		var adj_pos: Vector2i = target_pos + d
		if adj_pos == from_pos:
			continue # Attacker launches from from_pos, not a separate supporting ally
		var m: MechData = occ.get(adj_pos, null)
		if m != null:
			if int(m.faction) == attacker_faction:
				atk_allies += 1
				if adj_pos == pincer_opposite_pos:
					is_pincer = true
			else:
				def_allies += 1

	# Check suppression: defender allies adjacent to attacker's launch tile (from_pos)
	var suppression: int = 0
	if from_pos != target_pos:
		for d in TerrainGrid.DIRS:
			var adj_launch: Vector2i = from_pos + d
			if adj_launch == target_pos:
				continue # Target is the defender
			var m_launch: MechData = occ.get(adj_launch, null)
			if m_launch != null and int(m_launch.faction) != attacker_faction:
				suppression += 1

	return {
		"atk_allies_adj": atk_allies,
		"def_allies_adj": def_allies,
		"is_pincer": is_pincer,
		"atk_suppression": suppression,
	}

