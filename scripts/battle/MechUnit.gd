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

func setup(data: MechData, screen_pos: Vector2) -> void:
	mech_data = data
	position = screen_pos
	_anim_time = randf() * 10.0
	queue_redraw()

func _process(delta: float) -> void:
	_anim_time += delta * (3.5 if _is_walking else 1.0)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	queue_redraw()

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

	var dim_factor: float = 0.65 if (mech_data.has_moved and mech_data.faction == MechData.Faction.PLAYER) else 1.0

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
	var f_screen := Vector2(float(mech_data.facing.x - mech_data.facing.y) * 2.0, float(mech_data.facing.x + mech_data.facing.y)).normalized()
	var chev_dist: float = 23.0
	var tip: Vector2 = Vector2(0, 6) + f_screen * chev_dist
	var perp: Vector2 = Vector2(-f_screen.y, f_screen.x)
	var left_pt: Vector2 = tip - f_screen * 7.5 + perp * 5.0
	var right_pt: Vector2 = tip - f_screen * 7.5 - perp * 5.0
	var notch_pt: Vector2 = tip - f_screen * 4.5
	var chev_pts := PackedVector2Array([tip, left_pt, notch_pt, right_pt])
	var chev_col: Color = Color(1.0, 0.82, 0.22, 0.95) if mech_data.faction == MechData.Faction.PLAYER else Color(0.95, 0.32, 0.25, 0.95)
	if mech_data.has_moved and mech_data.faction == MechData.Faction.PLAYER:
		chev_col = chev_col.darkened(0.35)
	draw_colored_polygon(chev_pts, chev_col)
	draw_polyline(PackedVector2Array([left_pt, tip, right_pt]), Color(0.1, 0.1, 0.1, 0.8), 1.2)

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

	# Base Plinth Telemetry Plate (Callsign + Armor Bar + Fuel Bar) tucked at the walker's feet inside its own tile
	var bar_w: float = 46.0
	var bar_x: float = -bar_w * 0.5
	var bar_y: float = 17.0

	# Backing plate
	draw_rect(Rect2(bar_x - 2, bar_y - 10, bar_w + 4, 19), Color(0.05, 0.06, 0.05, 0.90), true)
	var faction_border := Color(0.45, 0.88, 0.45, 0.95) if mech_data.faction == MechData.Faction.PLAYER else Color(0.95, 0.32, 0.26, 0.95)
	draw_rect(Rect2(bar_x - 2, bar_y - 10, bar_w + 4, 19), faction_border, false, 1.2)

	# Short callsign + Facing + Ready dot
	var font: Font = ThemeDB.fallback_font
	var short_name: String = mech_data.callsign.split(" ")[0]
	var label_text: String = "%s %s" % [short_name, mech_data.get_facing_name()]
	draw_string(font, Vector2(bar_x, bar_y - 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, int(bar_w - 6), 8, Color(0.95, 0.93, 0.85))

	# Ready status pip
	var pip_col := Color(0.35, 0.95, 0.45) if not mech_data.has_moved else Color(0.45, 0.45, 0.42)
	if mech_data.faction == MechData.Faction.AI:
		pip_col = Color(0.95, 0.35, 0.3)
	draw_circle(Vector2(bar_x + bar_w - 3, bar_y - 5), 2.2, pip_col)

	# Armor Bar (3px tall)
	var armor_ratio: float = mech_data.get_armor_ratio()
	var armor_col := Color(0.35, 0.88, 0.42) if armor_ratio > 0.5 else (Color(0.95, 0.72, 0.22) if armor_ratio > 0.25 else Color(0.95, 0.25, 0.2))
	draw_rect(Rect2(bar_x, bar_y + 1, bar_w, 3), Color(0.18, 0.18, 0.18), true)
	draw_rect(Rect2(bar_x, bar_y + 1, bar_w * armor_ratio, 3), armor_col, true)

	# Fuel Bar (2.5px tall)
	var fuel_ratio: float = mech_data.get_fuel_ratio()
	draw_rect(Rect2(bar_x, bar_y + 5, bar_w, 2.5), Color(0.15, 0.15, 0.15), true)
	draw_rect(Rect2(bar_x, bar_y + 5, bar_w * fuel_ratio, 2.5), Color(0.32, 0.78, 0.92), true)

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

