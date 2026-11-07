class_name MechUnit
extends Node2D

## Visual Isometric Mech Unit Node
## Renders a multi-part dieselpunk Armored Fighting Walker with idle engine vibration,
## diesel exhaust puffs, faction livery, armor/fuel overhead telemetry bars, and path movement tweening.

var mech_data: MechData
var is_selected: bool = false
var _anim_time: float = 0.0
var _is_walking: bool = false
var _since_redraw: float = 0.0
# Name plate text and width, fixed per walker (the callsign never changes after setup).
var _plate_name: String = ""
var _plate_w: float = 48.0

## Ambient animation (hull bob, exhaust puff, selection pulse) moves well under a pixel per frame, so
## walkers re-record their drawing at this rate instead of every frame; walkers outside the view
## don't re-record at all. State changes call queue_redraw() directly and show at once.
const AMBIENT_FPS := 30.0
const CULL_MARGIN := 96.0

func setup(data: MechData, screen_pos: Vector2) -> void:
	mech_data = data
	position = screen_pos
	_anim_time = randf() * 10.0
	# Spread the walkers' 30 Hz redraws over 8 phases so a big army doesn't all re-record in one frame.
	_since_redraw = float(get_index() % 8) / 8.0 / AMBIENT_FPS
	_plate_name = CrtUI.sanitize(mech_data.callsign.split(" ")[0])
	_plate_w = maxf(48.0, float(PixelFont.text_width(_plate_name) + 14))
	queue_redraw()

static var suppress_redraw: bool = false

func _process(delta: float) -> void:
	if suppress_redraw:
		return
	_anim_time += delta * (3.5 if _is_walking else 1.0)
	_since_redraw += delta
	if _since_redraw < 1.0 / AMBIENT_FPS:
		return
	# Keep the remainder so the per-walker stagger survives; an off-screen walker waits a whole tick
	# before testing visibility again instead of every frame.
	_since_redraw = fmod(_since_redraw, 1.0 / AMBIENT_FPS)
	if not _on_screen():
		return
	queue_redraw()

func _on_screen() -> bool:
	var p: Vector2 = get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(CULL_MARGIN).has_point(p)

## True while `u` is a walker node that still exists and whose walker is not wrecked. Takes any value
## (including a freed instance or null), which is why it is static rather than a method.
static func is_live(u) -> bool:
	if not is_instance_valid(u):
		return false
	var unit: MechUnit = u   # typed from here on: the member reads below are the hot part
	return unit.mech_data != null and unit.mech_data.is_alive()

func animate_move_along_screen_points(points: Array[Vector2], on_complete: Callable) -> void:
	if points.size() <= 1:
		if points.size() == 1:
			position = points[0]
		on_complete.call()
		return

	_is_walking = true
	var tween := create_tween()
	for i in range(1, points.size()):
		var target_pt: Vector2 = points[i]
		tween.tween_callback(func(): SoundManager.play("mech_step", randf_range(0.92, 1.08)))
		tween.tween_property(self, "position", target_pt, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		_is_walking = false
		on_complete.call()
	)

func _draw() -> void:
	if mech_data == null:
		return

	var order_done: bool = mech_data.is_order_complete()
	var dim_factor: float = 0.65 if (order_done and mech_data.faction == MechData.Faction.PLAYER) else 1.0

	# Isometric selection diamond ring on the tile surface
	if is_selected:
		var pulse: float = 0.5 + 0.5 * sin(_anim_time * 5.0)
		var rw: float = 34.0 + pulse * 3.0
		var rh: float = 17.0 + pulse * 1.5
		var ring_pts := PackedVector2Array([
			Vector2(0, -rh),
			Vector2(rw, 0),
			Vector2(0, rh),
			Vector2(-rw, 0),
			Vector2(0, -rh)
		])
		draw_polyline(ring_pts, Color(1.0, 0.86, 0.25, 0.95), 2.5)

	# Tactical Directional Facing Chevron on the tile surface
	# Double Chevron (Tactical Echelon): Outer lead chevron + Inner trailing chevron
	var f_screen := Vector2(float(mech_data.facing.x - mech_data.facing.y) * 2.0, float(mech_data.facing.x + mech_data.facing.y)).normalized()
	var perp := Vector2(-f_screen.y, f_screen.x)
	var chev_dist: float = 34.0
	var tip1: Vector2 = Vector2(0, 6) + f_screen * chev_dist

	# Lead chevron (scaled ~14x16px)
	var l_pt1: Vector2 = tip1 - f_screen * 13.0 + perp * 8.0
	var r_pt1: Vector2 = tip1 - f_screen * 13.0 - perp * 8.0
	var n_pt1: Vector2 = tip1 - f_screen * 7.5
	var chev1_pts := PackedVector2Array([tip1, l_pt1, n_pt1, r_pt1])

	# Trailing echelon chevron (scaled ~9x11px)
	var tip2: Vector2 = tip1 - f_screen * 7.0
	var l_pt2: Vector2 = tip2 - f_screen * 8.5 + perp * 5.5
	var r_pt2: Vector2 = tip2 - f_screen * 8.5 - perp * 5.5
	var n_pt2: Vector2 = tip2 - f_screen * 4.5
	var chev2_pts := PackedVector2Array([tip2, l_pt2, n_pt2, r_pt2])

	var chev1_col: Color = CrtUI.C_CURSOR if mech_data.faction == MechData.Faction.PLAYER else CrtUI.C_HOSTILE
	var chev2_col: Color = CrtUI.C_NAME if mech_data.faction == MechData.Faction.PLAYER else Color(0.85, 0.25, 0.2, 0.9)
	if is_selected and mech_data.faction == MechData.Faction.PLAYER:
		var sel_pulse: float = 0.8 + 0.2 * sin(_anim_time * 5.0)
		chev1_col = Color(chev1_col.r, chev1_col.g, chev1_col.b, sel_pulse)
	if order_done and mech_data.faction == MechData.Faction.PLAYER:
		chev1_col = chev1_col.darkened(0.35)
		chev2_col = chev2_col.darkened(0.35)

	# Draw trailing then lead chevron
	draw_colored_polygon(chev2_pts, chev2_col)
	draw_polyline(PackedVector2Array([l_pt2, tip2, r_pt2]), Color(0.05, 0.08, 0.05, 0.9), 1.2)
	draw_colored_polygon(chev1_pts, chev1_col)
	draw_polyline(PackedVector2Array([l_pt1, tip1, r_pt1]), Color(0.05, 0.08, 0.05, 0.9), 1.4)

	# Draw dieselpunk walker silhouette anchored inside the tile diamond
	# Feet planted at y = +6, torso centered at y = -8, top at y = -20 (strictly inside [-29.5, +29.5])
	var flip_h: bool = ((mech_data.facing.x - mech_data.facing.y) < 0)
	if flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	MechSilhouette.draw(self, Vector2(0, 6), mech_data.chassis_id, mech_data.faction, 0.78, _anim_time, dim_factor)
	if flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.0))

	# Entrenched shield chevron next to hull
	if mech_data.is_entrenched:
		var sh_pos := Vector2(18, -10)
		draw_circle(sh_pos, 6.0, Color(0.1, 0.14, 0.1, 0.9))
		draw_arc(sh_pos, 6.0, 0, TAU, 16, Color(0.45, 0.95, 0.65), 1.6)

	# Overhead Floating Tactical Tag (Callsign + Status Pip + Hull/Fuel Gauges)
	var clean_name: String = _plate_name
	var plate_w: float = _plate_w
	var plate_h: float = 17.0
	var plate_x: float = -roundf(plate_w * 0.5)
	var plate_y: float = -38.0
	var plate_rect := Rect2(plate_x, plate_y, plate_w, plate_h)

	# CRT Backing Frame
	var faction_border := CrtUI.C_BORDER if mech_data.faction == MechData.Faction.PLAYER else CrtUI.C_HOSTILE
	draw_rect(plate_rect, CrtUI.C_FILL, true)
	draw_rect(plate_rect, faction_border, false, 1.0)
	draw_line(Vector2(plate_x + 1, plate_y + 9), Vector2(plate_x + plate_w - 1, plate_y + 9), CrtUI.C_RULE, 1.0)

	# Row 1: Short Callsign in PixelFont + Ready status pip
	var name_col := CrtUI.C_NAME if mech_data.faction == MechData.Faction.PLAYER else CrtUI.C_HOSTILE
	if order_done and mech_data.faction == MechData.Faction.PLAYER:
		name_col = name_col.darkened(0.3)
	PixelFont.draw_text(self, clean_name, Vector2(plate_x + 3, plate_y + 1), name_col)

	var pip_col := Color(0.35, 0.95, 0.45) if not order_done else Color(0.45, 0.45, 0.42)
	if mech_data.faction == MechData.Faction.AI:
		pip_col = CrtUI.C_HOSTILE
	draw_circle(Vector2(plate_x + plate_w - 5, plate_y + 5), 2.0, pip_col)

	# Row 2: Micro-Gauges (Armor / Hull + Fuel)
	var gw: float = plate_w - 6.0
	var gx: float = plate_x + 3.0

	# Armor Bar (2px tall)
	var armor_ratio: float = mech_data.get_armor_ratio()
	var armor_col := CrtUI.C_LABEL if armor_ratio > 0.5 else (CrtUI.C_NAME if armor_ratio > 0.25 else CrtUI.C_HULL)
	draw_rect(Rect2(gx, plate_y + 11, gw, 2), CrtUI.C_GAUGE_BG, true)
	draw_rect(Rect2(gx, plate_y + 11, roundf(gw * armor_ratio), 2), armor_col, true)

	# Fuel Bar (2px tall)
	var fuel_ratio: float = mech_data.get_fuel_ratio()
	draw_rect(Rect2(gx, plate_y + 14, gw, 2), CrtUI.C_GAUGE_BG, true)
	draw_rect(Rect2(gx, plate_y + 14, roundf(gw * fuel_ratio), 2), CrtUI.C_FUEL, true)

