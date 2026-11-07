class_name MechSilhouette
extends RefCounted

## Procedural walker renderer for the isometric battlefield (MechUnit). Node-free so any canvas can
## draw a walker; the HUD portrait, Showdown and Hangar use the pixel-art sprite sheets instead.

static var _warned: Dictionary = {} # unknown chassis ids already reported

static func draw(
	ci: CanvasItem,
	origin: Vector2,
	chassis_id: String,
	faction: int,
	scale_f: float = 1.0,
	anim_t: float = 0.0,
	dim: float = 1.0,
	flash_white: bool = false
) -> void:
	if not ChassisCatalog.ORDER.has(chassis_id) and not _warned.has(chassis_id):
		_warned[chassis_id] = true
		push_warning("MechSilhouette: unknown chassis '%s', drawing the vanguard silhouette" % chassis_id)
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
	ci.draw_circle(origin + Vector2(0, 4 * scale_f), 16.0 * scale_f, Color(0.03, 0.04, 0.03, 0.55))

	# Diesel Exhaust Smoke Puff
	var puff_y: float = fmod(anim_t * 14.0, 18.0) * scale_f
	var puff_alpha: float = clampf(1.0 - (puff_y / (18.0 * scale_f)), 0.0, 0.45)
	ci.draw_circle(origin + Vector2(-12 * scale_f, (-30 - puff_y) * scale_f), (3.5 + puff_y * 0.15) * scale_f, Color(0.25, 0.26, 0.24, puff_alpha))

	var torso_c := origin + Vector2(0, -18 * scale_f + bob)

	match chassis_id:
		"donner":
			# Quadruped Spider Artillery Walker
			for sx in [-1.0, 1.0]:
				var knee := origin + Vector2(sx * 16 * scale_f, -10 * scale_f + bob * 0.5)
				var foot := origin + Vector2(sx * 20 * scale_f, 3 * scale_f)
				ci.draw_line(torso_c + Vector2(sx * 8 * scale_f, 4 * scale_f), knee, metal_col, 3.5 * scale_f)
				ci.draw_line(knee, foot, dark_metal, 3.0 * scale_f)
				var knee2 := origin + Vector2(sx * 10 * scale_f, -6 * scale_f + bob * 0.5)
				var foot2 := origin + Vector2(sx * 12 * scale_f, 6 * scale_f)
				ci.draw_line(torso_c + Vector2(sx * 5 * scale_f, 6 * scale_f), knee2, hull_dark, 3.5 * scale_f)
				ci.draw_line(knee2, foot2, metal_col, 3.0 * scale_f)
			# Low armored hull
			ci.draw_rect(Rect2(torso_c + Vector2(-14, -8) * scale_f, Vector2(28, 13) * scale_f), hull_base, true)
			ci.draw_rect(Rect2(torso_c + Vector2(-14, -8) * scale_f, Vector2(28, 13) * scale_f), hull_light, false, 1.5 * scale_f)
			# Elevated Multi-Tube Rocket Pod
			var pod_rect := Rect2(torso_c + Vector2(-11, -20) * scale_f, Vector2(22, 11) * scale_f)
			ci.draw_rect(pod_rect, hull_dark, true)
			ci.draw_rect(pod_rect, metal_col, false, 1.5 * scale_f)
			for rx in [-7, -2, 3, 8]:
				ci.draw_circle(torso_c + Vector2(rx, -15) * scale_f, 2.0 * scale_f, visor_col)
			# Visor slit
			ci.draw_rect(Rect2(torso_c + Vector2(-6, -4) * scale_f, Vector2(12, 3) * scale_f), visor_col, true)

		"goliath":
			# Super-Heavy Dreadnought Mech
			for sx in [-1.0, 1.0]:
				var leg_rect := Rect2(origin + Vector2((sx * 8 - 5) * scale_f, -14 * scale_f), Vector2(10, 16) * scale_f)
				ci.draw_rect(leg_rect, hull_dark, true)
				ci.draw_rect(leg_rect, metal_col, false, 1.4 * scale_f)
			# Massive blocky bunker torso
			var body_rect := Rect2(torso_c + Vector2(-17, -16) * scale_f, Vector2(34, 22) * scale_f)
			ci.draw_rect(body_rect, hull_base, true)
			ci.draw_rect(body_rect, hull_light, false, 2.0 * scale_f)
			# Twin Shoulder Siege Howitzers
			ci.draw_line(torso_c + Vector2(-12, -16) * scale_f, torso_c + Vector2(-18, -30) * scale_f, metal_col, 4.5 * scale_f)
			ci.draw_line(torso_c + Vector2(12, -16) * scale_f, torso_c + Vector2(22, -28) * scale_f, metal_col, 5.0 * scale_f)
			# Sloped armor chest & glowing bunker visor
			ci.draw_rect(Rect2(torso_c + Vector2(-10, -9) * scale_f, Vector2(20, 4) * scale_f), visor_col, true)
			ci.draw_rect(Rect2(torso_c + Vector2(-13, -2) * scale_f, Vector2(26, 6) * scale_f), hull_light, true)

		"falke":
			# Agile Reverse-Joint Recon Strider
			for sx in [-1.0, 1.0]:
				var hip := torso_c + Vector2(sx * 6 * scale_f, 4 * scale_f)
				var r_knee := origin + Vector2(sx * 11 * scale_f, -11 * scale_f)
				var foot := origin + Vector2(sx * 7 * scale_f, 3 * scale_f)
				ci.draw_line(hip, r_knee, metal_col, 2.8 * scale_f)
				ci.draw_line(r_knee, foot, hull_light, 2.5 * scale_f)
			# Rounded Scout Cockpit Pod
			var pod_pts := PackedVector2Array([
				torso_c + Vector2(0, -14) * scale_f,
				torso_c + Vector2(12, -5) * scale_f,
				torso_c + Vector2(9, 6) * scale_f,
				torso_c + Vector2(-9, 6) * scale_f,
				torso_c + Vector2(-12, -5) * scale_f
			])
			ci.draw_colored_polygon(pod_pts, hull_base)
			ci.draw_polyline(PackedVector2Array([pod_pts[0], pod_pts[1], pod_pts[2], pod_pts[3], pod_pts[4], pod_pts[0]]), hull_light, 1.5 * scale_f)
			# Rapid 50mm Autocannon Barrel
			ci.draw_line(torso_c + Vector2(10, -4) * scale_f, torso_c + Vector2(24, -10) * scale_f, metal_col, 3.0 * scale_f)
			ci.draw_circle(torso_c + Vector2(0, -4) * scale_f, 4.0 * scale_f, visor_col)

		"kommandant":
			# Command & ECM Walker
			for sx in [-1.0, 1.0]:
				ci.draw_line(torso_c + Vector2(sx * 7, 5) * scale_f, origin + Vector2(sx * 9, 3) * scale_f, hull_dark, 4.5 * scale_f)
			var cmd_rect := Rect2(torso_c + Vector2(-13, -13) * scale_f, Vector2(26, 18) * scale_f)
			ci.draw_rect(cmd_rect, hull_base, true)
			ci.draw_rect(cmd_rect, hull_light, false, 1.6 * scale_f)
			# Rotating Radar Dish & Dual Whip Antennas
			ci.draw_line(torso_c + Vector2(-9, -13) * scale_f, torso_c + Vector2(-11, -28) * scale_f, metal_col, 1.8 * scale_f)
			ci.draw_arc(torso_c + Vector2(6, -18) * scale_f, 6.0 * scale_f, PI * 0.8, PI * 2.1, 12, Color(0.88, 0.78, 0.35), 2.2 * scale_f)
			# 105mm Assault Gun
			ci.draw_line(torso_c + Vector2(12, -4) * scale_f, torso_c + Vector2(25, -8) * scale_f, metal_col, 3.8 * scale_f)
			ci.draw_rect(Rect2(torso_c + Vector2(-7, -7) * scale_f, Vector2(14, 3.5) * scale_f), visor_col, true)

		"moloch":
			# Close-Quarters Urban Brawler (Pile-Bunker + Thermite Lance)
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(origin + Vector2((sx * 8 - 4) * scale_f, -13 * scale_f), Vector2(8, 15) * scale_f), hull_dark, true)
			var br_rect := Rect2(torso_c + Vector2(-15, -14) * scale_f, Vector2(30, 20) * scale_f)
			ci.draw_rect(br_rect, hull_base, true)
			ci.draw_rect(br_rect, hull_light, false, 1.8 * scale_f)
			# Left Arm Shield + Pile-Bunker Spike
			ci.draw_rect(Rect2(torso_c + Vector2(-20, -10) * scale_f, Vector2(6, 15) * scale_f), metal_col, true)
			# Right Arm Thermite Projector with pilot flame
			ci.draw_line(torso_c + Vector2(14, -3) * scale_f, torso_c + Vector2(26, -6) * scale_f, metal_col, 5.0 * scale_f)
			ci.draw_circle(torso_c + Vector2(27, -6) * scale_f, 3.0 * scale_f, Color(1.0, 0.45, 0.1))
			ci.draw_rect(Rect2(torso_c + Vector2(-8, -8) * scale_f, Vector2(16, 4) * scale_f), visor_col, true)

		_:
			# "vanguard" - Classic Medium Assault Walker (Ring of Red / Sturmjäger style)
			for sx in [-1.0, 1.0]:
				var hip := torso_c + Vector2(sx * 7 * scale_f, 5 * scale_f)
				var knee := origin + Vector2(sx * 9 * scale_f, -6 * scale_f)
				var foot := origin + Vector2(sx * 8 * scale_f, 3 * scale_f)
				ci.draw_line(hip, knee, hull_dark, 4.2 * scale_f)
				ci.draw_line(knee, foot, metal_col, 3.8 * scale_f)
			# Sloped Turret Hull
			var hull_poly := PackedVector2Array([
				torso_c + Vector2(-11, -14) * scale_f,
				torso_c + Vector2(11, -14) * scale_f,
				torso_c + Vector2(15, 5) * scale_f,
				torso_c + Vector2(-15, 5) * scale_f
			])
			ci.draw_colored_polygon(hull_poly, hull_base)
			ci.draw_polyline(PackedVector2Array([hull_poly[0], hull_poly[1], hull_poly[2], hull_poly[3], hull_poly[0]]), hull_light, 1.6 * scale_f)
			# 88mm Long Barrel Cannon
			ci.draw_line(torso_c + Vector2(10, -9) * scale_f, torso_c + Vector2(26, -15) * scale_f, metal_col, 3.8 * scale_f)
			# Exhaust stack
			ci.draw_line(torso_c + Vector2(-10, -12) * scale_f, torso_c + Vector2(-12, -22) * scale_f, dark_metal, 3.0 * scale_f)
			# Glowing optical visor
			ci.draw_rect(Rect2(torso_c + Vector2(-7, -7) * scale_f, Vector2(14, 3.5) * scale_f), visor_col, true)
