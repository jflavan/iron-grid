class_name MechUnit
extends Node2D

## Visual Isometric Mech Unit Node
## Renders a multi-part dieselpunk Armored Fighting Walker with idle engine vibration,
## diesel exhaust puffs, faction livery, armor/fuel overhead telemetry bars, and path movement tweening.

var mech_data: MechData
var is_selected: bool = false
var _anim_time: float = 0.0
var _is_walking: bool = false
var _hit_flash: float = 0.0
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
	_plate_name = CrtUI.sanitize(mech_data.callsign.split(" ")[0])
	_plate_w = maxf(48.0, float(PixelFont.text_width(_plate_name) + 14))
	queue_redraw()

static var suppress_redraw: bool = false

func _process(delta: float) -> void:
	if suppress_redraw:
		return
	_anim_time += delta * (3.5 if _is_walking else 1.0)
	_since_redraw += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	elif _since_redraw < 1.0 / AMBIENT_FPS or not _on_screen():
		return
	_since_redraw = 0.0
	queue_redraw()

func _on_screen() -> bool:
	var p: Vector2 = get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(CULL_MARGIN).has_point(p)

func trigger_hit_flash() -> void:
	_hit_flash = 1.0
	queue_redraw()

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
	draw_mech_silhouette(self, Vector2(0, 6), mech_data.chassis_id, mech_data.faction, 0.78, _anim_time, dim_factor, _hit_flash > 0.0)
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

## Static procedural renderer used on the battlefield, HUD portrait, Skirmish Showdown, and Mech Hangar.
static func draw_mech_silhouette(
	canvas: CanvasItem,
	origin: Vector2,
	chassis_id: String,
	faction: int,
	scale_f: float = 1.0,
	anim_t: float = 0.0,
	dim: float = 1.0,
	flash_white: bool = false
) -> void:
	var bob: float = sin(anim_t * 3.2) * 1.4 * scale_f
	var hull_base: Color
	var hull_light: Color
	var hull_dark: Color
	var visor_col: Color

	if flash_white:
		hull_base = Color(0.98, 0.95, 0.88)
		hull_light = Color.WHITE
		hull_dark = Color(0.85, 0.82, 0.75)
		visor_col = Color(1.0, 0.3, 0.1)
	elif faction == MechData.Faction.PLAYER:
		hull_base = Color(0.36 * dim, 0.43 * dim, 0.29 * dim)
		hull_light = Color(0.50 * dim, 0.58 * dim, 0.40 * dim)
		hull_dark = Color(0.22 * dim, 0.27 * dim, 0.18 * dim)
		visor_col = Color(1.0, 0.74, 0.18)
	else:
		hull_base = Color(0.46 * dim, 0.22 * dim, 0.20 * dim)
		hull_light = Color(0.64 * dim, 0.30 * dim, 0.27 * dim)
		hull_dark = Color(0.28 * dim, 0.13 * dim, 0.12 * dim)
		visor_col = Color(1.0, 0.25, 0.20)

	var metal_col := Color(0.42 * dim, 0.43 * dim, 0.40 * dim)
	var dark_metal := Color(0.20 * dim, 0.21 * dim, 0.19 * dim)

	# Ground Shadow
	canvas.draw_circle(origin + Vector2(0, 4 * scale_f), 16.0 * scale_f, Color(0.03, 0.04, 0.03, 0.55))

	# Diesel Exhaust Smoke Puff
	var puff_y: float = fmod(anim_t * 14.0, 18.0) * scale_f
	var puff_alpha: float = clampf(1.0 - (puff_y / (18.0 * scale_f)), 0.0, 0.45)
	canvas.draw_circle(origin + Vector2(-12 * scale_f, (-30 - puff_y) * scale_f), (3.5 + puff_y * 0.15) * scale_f, Color(0.25, 0.26, 0.24, puff_alpha))

	var torso_c := origin + Vector2(0, -18 * scale_f + bob)

	match chassis_id:
		"donner":
			# Quadruped Spider Artillery Walker
			for sx in [-1.0, 1.0]:
				var knee := origin + Vector2(sx * 16 * scale_f, -10 * scale_f + bob * 0.5)
				var foot := origin + Vector2(sx * 20 * scale_f, 3 * scale_f)
				canvas.draw_line(torso_c + Vector2(sx * 8 * scale_f, 4 * scale_f), knee, metal_col, 3.5 * scale_f)
				canvas.draw_line(knee, foot, dark_metal, 3.0 * scale_f)
				var knee2 := origin + Vector2(sx * 10 * scale_f, -6 * scale_f + bob * 0.5)
				var foot2 := origin + Vector2(sx * 12 * scale_f, 6 * scale_f)
				canvas.draw_line(torso_c + Vector2(sx * 5 * scale_f, 6 * scale_f), knee2, hull_dark, 3.5 * scale_f)
				canvas.draw_line(knee2, foot2, metal_col, 3.0 * scale_f)
			# Low armored hull
			canvas.draw_rect(Rect2(torso_c + Vector2(-14, -8) * scale_f, Vector2(28, 13) * scale_f), hull_base, true)
			canvas.draw_rect(Rect2(torso_c + Vector2(-14, -8) * scale_f, Vector2(28, 13) * scale_f), hull_light, false, 1.5 * scale_f)
			# Elevated Multi-Tube Rocket Pod
			var pod_rect := Rect2(torso_c + Vector2(-11, -20) * scale_f, Vector2(22, 11) * scale_f)
			canvas.draw_rect(pod_rect, hull_dark, true)
			canvas.draw_rect(pod_rect, metal_col, false, 1.5 * scale_f)
			for rx in [-7, -2, 3, 8]:
				canvas.draw_circle(torso_c + Vector2(rx, -15) * scale_f, 2.0 * scale_f, visor_col)
			# Visor slit
			canvas.draw_rect(Rect2(torso_c + Vector2(-6, -4) * scale_f, Vector2(12, 3) * scale_f), visor_col, true)

		"goliath":
			# Super-Heavy Dreadnought Mech
			for sx in [-1.0, 1.0]:
				var leg_rect := Rect2(origin + Vector2((sx * 8 - 5) * scale_f, -14 * scale_f), Vector2(10, 16) * scale_f)
				canvas.draw_rect(leg_rect, hull_dark, true)
				canvas.draw_rect(leg_rect, metal_col, false, 1.4 * scale_f)
			# Massive blocky bunker torso
			var body_rect := Rect2(torso_c + Vector2(-17, -16) * scale_f, Vector2(34, 22) * scale_f)
			canvas.draw_rect(body_rect, hull_base, true)
			canvas.draw_rect(body_rect, hull_light, false, 2.0 * scale_f)
			# Twin Shoulder Siege Howitzers
			canvas.draw_line(torso_c + Vector2(-12, -16) * scale_f, torso_c + Vector2(-18, -30) * scale_f, metal_col, 4.5 * scale_f)
			canvas.draw_line(torso_c + Vector2(12, -16) * scale_f, torso_c + Vector2(22, -28) * scale_f, metal_col, 5.0 * scale_f)
			# Sloped armor chest & glowing bunker visor
			canvas.draw_rect(Rect2(torso_c + Vector2(-10, -9) * scale_f, Vector2(20, 4) * scale_f), visor_col, true)
			canvas.draw_rect(Rect2(torso_c + Vector2(-13, -2) * scale_f, Vector2(26, 6) * scale_f), hull_light, true)

		"falke":
			# Agile Reverse-Joint Recon Strider
			for sx in [-1.0, 1.0]:
				var hip := torso_c + Vector2(sx * 6 * scale_f, 4 * scale_f)
				var r_knee := origin + Vector2(sx * 11 * scale_f, -11 * scale_f)
				var foot := origin + Vector2(sx * 7 * scale_f, 3 * scale_f)
				canvas.draw_line(hip, r_knee, metal_col, 2.8 * scale_f)
				canvas.draw_line(r_knee, foot, hull_light, 2.5 * scale_f)
			# Rounded Scout Cockpit Pod
			var pod_pts := PackedVector2Array([
				torso_c + Vector2(0, -14) * scale_f,
				torso_c + Vector2(12, -5) * scale_f,
				torso_c + Vector2(9, 6) * scale_f,
				torso_c + Vector2(-9, 6) * scale_f,
				torso_c + Vector2(-12, -5) * scale_f
			])
			canvas.draw_colored_polygon(pod_pts, hull_base)
			canvas.draw_polyline(PackedVector2Array([pod_pts[0], pod_pts[1], pod_pts[2], pod_pts[3], pod_pts[4], pod_pts[0]]), hull_light, 1.5 * scale_f)
			# Rapid 50mm Autocannon Barrel
			canvas.draw_line(torso_c + Vector2(10, -4) * scale_f, torso_c + Vector2(24, -10) * scale_f, metal_col, 3.0 * scale_f)
			canvas.draw_circle(torso_c + Vector2(0, -4) * scale_f, 4.0 * scale_f, visor_col)

		"kommandant":
			# Command & ECM Walker
			for sx in [-1.0, 1.0]:
				canvas.draw_line(torso_c + Vector2(sx * 7, 5) * scale_f, origin + Vector2(sx * 9, 3) * scale_f, hull_dark, 4.5 * scale_f)
			var cmd_rect := Rect2(torso_c + Vector2(-13, -13) * scale_f, Vector2(26, 18) * scale_f)
			canvas.draw_rect(cmd_rect, hull_base, true)
			canvas.draw_rect(cmd_rect, hull_light, false, 1.6 * scale_f)
			# Rotating Radar Dish & Dual Whip Antennas
			canvas.draw_line(torso_c + Vector2(-9, -13) * scale_f, torso_c + Vector2(-11, -28) * scale_f, metal_col, 1.8 * scale_f)
			canvas.draw_arc(torso_c + Vector2(6, -18) * scale_f, 6.0 * scale_f, PI * 0.8, PI * 2.1, 12, Color(0.88, 0.78, 0.35), 2.2 * scale_f)
			# 105mm Assault Gun
			canvas.draw_line(torso_c + Vector2(12, -4) * scale_f, torso_c + Vector2(25, -8) * scale_f, metal_col, 3.8 * scale_f)
			canvas.draw_rect(Rect2(torso_c + Vector2(-7, -7) * scale_f, Vector2(14, 3.5) * scale_f), visor_col, true)

		"moloch":
			# Close-Quarters Urban Brawler (Pile-Bunker + Thermite Lance)
			for sx in [-1.0, 1.0]:
				canvas.draw_rect(Rect2(origin + Vector2((sx * 8 - 4) * scale_f, -13 * scale_f), Vector2(8, 15) * scale_f), hull_dark, true)
			var br_rect := Rect2(torso_c + Vector2(-15, -14) * scale_f, Vector2(30, 20) * scale_f)
			canvas.draw_rect(br_rect, hull_base, true)
			canvas.draw_rect(br_rect, hull_light, false, 1.8 * scale_f)
			# Left Arm Shield + Pile-Bunker Spike
			canvas.draw_rect(Rect2(torso_c + Vector2(-20, -10) * scale_f, Vector2(6, 15) * scale_f), metal_col, true)
			# Right Arm Thermite Projector with pilot flame
			canvas.draw_line(torso_c + Vector2(14, -3) * scale_f, torso_c + Vector2(26, -6) * scale_f, metal_col, 5.0 * scale_f)
			canvas.draw_circle(torso_c + Vector2(27, -6) * scale_f, 3.0 * scale_f, Color(1.0, 0.45, 0.1))
			canvas.draw_rect(Rect2(torso_c + Vector2(-8, -8) * scale_f, Vector2(16, 4) * scale_f), visor_col, true)

		_:
			# "vanguard" - Classic Medium Assault Walker (Ring of Red / Sturmjäger style)
			for sx in [-1.0, 1.0]:
				var hip := torso_c + Vector2(sx * 7 * scale_f, 5 * scale_f)
				var knee := origin + Vector2(sx * 9 * scale_f, -6 * scale_f)
				var foot := origin + Vector2(sx * 8 * scale_f, 3 * scale_f)
				canvas.draw_line(hip, knee, hull_dark, 4.2 * scale_f)
				canvas.draw_line(knee, foot, metal_col, 3.8 * scale_f)
			# Sloped Turret Hull
			var hull_poly := PackedVector2Array([
				torso_c + Vector2(-11, -14) * scale_f,
				torso_c + Vector2(11, -14) * scale_f,
				torso_c + Vector2(15, 5) * scale_f,
				torso_c + Vector2(-15, 5) * scale_f
			])
			canvas.draw_colored_polygon(hull_poly, hull_base)
			canvas.draw_polyline(PackedVector2Array([hull_poly[0], hull_poly[1], hull_poly[2], hull_poly[3], hull_poly[0]]), hull_light, 1.6 * scale_f)
			# 88mm Long Barrel Cannon
			canvas.draw_line(torso_c + Vector2(10, -9) * scale_f, torso_c + Vector2(26, -15) * scale_f, metal_col, 3.8 * scale_f)
			# Exhaust stack
			canvas.draw_line(torso_c + Vector2(-10, -12) * scale_f, torso_c + Vector2(-12, -22) * scale_f, dark_metal, 3.0 * scale_f)
			# Glowing optical visor
			canvas.draw_rect(Rect2(torso_c + Vector2(-7, -7) * scale_f, Vector2(14, 3.5) * scale_f), visor_col, true)
