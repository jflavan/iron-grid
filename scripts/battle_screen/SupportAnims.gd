class_name SupportAnims
extends RefCounted

## Armor, Tactical, Defend, and Retreat support animations.
## Each plays during the "support" phase as a pure FF-style support/status turn (no follow-up shot).
## Defensive shields (ricochet, sidestep, reactive bricks) soften and animate on the opponent's next hit.

const DURATIONS := {
	"krupp_plate": 1.0,
	"ferro_bulkhead": 1.15,
	"anchor_strut": 1.0,
	"ablative_shield": 0.9,
	"gyro_thruster": 1.0,
	"recon_lock": 1.3,
	"plunging_comp": 1.4,
	"enigma_ecm": 1.2,
	"cmd_override": 1.5,
	"defend": 0.65,
	"retreat": 0.75,
}
const SLAB_DROP := 0.35
const C_LOCK := Color("#ffe080")
const C_HQ_GREEN := Color("#3ad06a")
const ATTACH_NAMES := ["slab", "rangefinder", "mast"]

static func has_anim(ability_id: String) -> bool:
	return DURATIONS.has(ability_id)

static func duration(ability_id: String) -> float:
	return DURATIONS.get(ability_id, 0.65)

## Persistent visual result of a support TECH, applied once when its support phase completes (or on skip).
static func apply_persistent(_stage: BattleStage, a: Dictionary, ability_id: String) -> void:
	match ability_id:
		"ferro_bulkhead":
			a["slab"] = true
		"anchor_strut":
			var braced := braced_sheet(a)
			if braced != "":
				a["sheet"] = braced
		"ablative_shield":
			a["armed"] = true
		"recon_lock":
			a["rangefinder_on"] = true
		"cmd_override":
			a["mast_on"] = true
		"enigma_ecm":
			var foe_side: String = "def" if a["side"] == "atk" else "atk"
			var foe: Dictionary = _stage.mechs[foe_side]
			foe["jammed"] = true

## Reactive bricks detonate on the hit they soften; the spent sheet replaces the intact one.
static func braced_sheet(a: Dictionary) -> String:
	return String(MechSpriteBank.meta_for(a["chassis"]).get("variants", {}).get("braced", ""))

static func consume_soften(_stage: BattleStage, target: Dictionary, ability_id: String) -> void:
	if ability_id == "ablative_shield" and target.get("armed", false):
		target["armed"] = false
		var spent: String = MechSpriteBank.meta_for(target["chassis"]).get("variants", {}).get("spent", "")
		if spent != "":
			target["sheet"] = spent

static func run(stage: BattleStage, a: Dictionary, d: Dictionary, ability_id: String, t: float) -> void:
	var dur := duration(ability_id)
	var dir: int = a["dir"]
	a["pose"] = "brace"
	match ability_id:
		"krupp_plate":
			a["pose"] = "angle" if t > 0.15 else "brace"
			if t > 0.3 and t < 0.85:
				var k := (t - 0.3) / 0.55
				var g := stage.point(a, "glacis")
				stage.fx(func(ci):
					for i in 9:
						var p := g + Vector2((-10 + k * 26 - i) * dir, -8 + i * 2)
						ci.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(1, 1, 1, 0.9 - i * 0.08)))
				if k > 0.6:
					stage.fx(func(ci): BattleFX.blob(ci, g + Vector2(14 * dir, 6), 2 if int(t / 0.05) % 2 else 1, Color.WHITE))
		"ferro_bulkhead":
			var front := _slab_pos(stage, a)
			if t < SLAB_DROP:
				var k := t / SLAB_DROP
				var p := front + Vector2(0, -170.0 * (1.0 - k * k))
				var tex := _attach_tex("slab", a)
				stage.fx(func(ci): _draw_attach(ci, tex, p, a["mirrored"]))
			else:
				# landed: drawn here until the phase ends and the stage makes it lasting
				var tex := _attach_tex("slab", a)
				stage.fx(func(ci): _draw_attach(ci, tex, front, a["mirrored"]))
				var k := (t - SLAB_DROP) / (dur - SLAB_DROP)
				if k < 0.5:
					a["offset"] += Vector2(0, 1 if int(t / 0.04) % 2 == 0 else 0)
				stage.fx(func(ci): BattleFX.ellipse(ci, Vector2(front.x + 20 * (1 if not a["mirrored"] else -1), BattleStage.GROUND_Y), int(10 + k * 46), int(2 + k * 4), Color(0.55, 0.47, 0.32, 0.75 * (1.0 - k))))
		"anchor_strut":
			if t >= 0.4 and braced_sheet(a) != "":
				a["sheet_vis"] = braced_sheet(a) # visual only; the stage applies the lasting swap
			if t > 0.35 and t < 1.0:
				var k := (t - 0.35) / 0.65
				var feet := stage.point(a, "feet")
				stage.fx(func(ci):
					for s in [-1, 1]:
						BattleFX.ellipse(ci, Vector2(feet.x + s * (30 + k * 18), BattleStage.GROUND_Y), int(4 + k * 10), int(1 + k * 3), Color(0.55, 0.47, 0.32, 0.8 * (1.0 - k))))
			if t > 0.4 and t < 0.5:
				a["offset"] += Vector2(0, 1)
		"ablative_shield":
			if int(t / 0.12) % 2 == 0:
				a["bricks_glow"] = 0.6
		"gyro_thruster":
			var jet := stage.point(a, "attach/thruster")
			stage.fx(func(ci):
				for i in 5:
					var ph := fmod(t * 3.0 + i * 0.2, 1.0)
					BattleFX.blob(ci, jet + Vector2((-4 - ph * 16) * dir, -ph * 6 + (i % 2) * 3), int(2 + ph * 4), Color(0.9, 0.92, 0.93, 0.85 * (1.0 - ph)))
				)
			var slide := sin(clampf(t / dur, 0.0, 1.0) * PI) * 10.0
			a["offset"] += Vector2(roundf(-slide * dir), 0)
			a["ghosts"] = [Vector2(roundf(slide * 0.5 * dir), 0), Vector2(roundf(slide * dir), 0)]
		"recon_lock":
			var ext := clampf(t / 0.3, 0.0, 1.0)
			a["attach"] = {"rangefinder": ext}
			var tgt := stage.point(d, "hull")
			if t > 0.25 and t < 0.45:
				var lens := stage.point(a, "attach/rangefinder")
				stage.fx(func(ci): BattleFX.blob(ci, lens + Vector2(0, -4), 2, Color.WHITE))
			if t > 0.4:
				var k := clampf((t - 0.4) / 0.5, 0.0, 1.0)
				var start := stage.point(a, "hull")
				var p := start.lerp(tgt, k)
				var locked := k >= 1.0
				stage.fx(func(ci):
					var r := 14.0 - (4.0 if locked else 0.0)
					var col := BattleFX.CRT_BORDER if not locked else C_LOCK
					for sx in [-1, 1]:
						for sy in [-1, 1]:
							var c := p + Vector2(sx * r, sy * r)
							ci.draw_rect(Rect2(c.x - (4 if sx > 0 else 0), c.y, 5, 1), col)
							ci.draw_rect(Rect2(c.x, c.y - (4 if sy > 0 else 0), 1, 5), col)
					ci.draw_rect(Rect2(p.x - 1, p.y, 3, 1), col)
					ci.draw_rect(Rect2(p.x, p.y - 1, 1, 3), col)
					if locked and int(t / 0.1) % 2 == 0:
						PixelFont.draw_centered(ci, "LOCK", p.x, p.y + r + 3, col))
		"plunging_comp":
			var hull := stage.point(a, "hull")
			var box := Rect2((hull + Vector2(-22, -58)).round(), Vector2(44, 26))
			box.position.x = clampf(box.position.x, 2, BattleStage.W - 46)
			box.position.y = maxf(box.position.y, 26)
			stage.fx(func(ci):
				BattleFX.panel(ci, box)
				for i in 2:
					var c := box.position + Vector2(11 + i * 22, 13)
					var ang := t * (9.0 + i * 5.0)
					ci.draw_line(c, c + Vector2(cos(ang), sin(ang)) * 7.0, C_LOCK, 1.0)
					ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), BattleFX.CRT_BORDER))
			if t > 0.6:
				draw_plot_arc(stage, a, d, clampf((t - 0.6) / 0.6, 0.0, 1.0))
		"enigma_ecm":
			var src := stage.point(a, "attach/ecm")
			stage.fx(func(ci):
				for i in 3:
					var ph := fmod(t * 1.6 + i / 3.0, 1.0)
					ci.draw_arc(src, 4.0 + ph * 60.0, 0, TAU, 24, Color(0.23, 0.82, 0.42, 1.0 - ph), 1.0))
			if t > 0.35:
				d["glitch"] = 0.5 + 0.5 * sin(t * 30.0)
		"cmd_override":
			var ext := clampf((t - 0.1) / 0.45, 0.0, 1.0)
			a["attach"] = {"mast": ext}
			a["glow"] = Color(0.3, 1.0, 0.4, 0.25 + 0.15 * sin(t * 12.0)) if t > 0.7 else Color(0, 0, 0, 0)
			if t > 0.5:
				var tip := stage.point(a, "attach/mast") + Vector2(0, -40)
				var ph := fmod(t * 1.4, 1.0)
				stage.fx(func(ci): ci.draw_arc(tip, 3.0 + ph * 26.0, PI, TAU, 16, Color(0.23, 0.82, 0.42, 1.0 - ph), 1.0))
			if t > 0.6:
				stage.fx(func(ci):
					var msg := "HQ: FIRE MISSION CONFIRMED"
					var w := PixelFont.text_width(msg) + 12
					var r := Rect2(roundf((BattleStage.W - w) / 2.0), 28, w, 14)
					BattleFX.panel(ci, r)
					PixelFont.draw_text(ci, msg, r.position + Vector2(6, 4), C_HQ_GREEN))
		"defend":
			a["pose"] = "brace"
			a["glow"] = Color(0.4, 0.85, 1.0, 0.35 * sin(clampf(t / dur, 0.0, 1.0) * PI))
			var g := stage.point(a, "glacis")
			stage.fx(func(ci):
				var sy := g.y - 14.0 + (t / dur) * 28.0
				ci.draw_rect(Rect2(g.x - 10, roundf(sy), 20, 2), Color(0.65, 0.95, 1.0, 0.85)))
		"retreat":
			var k := clampf(t / dur, 0.0, 1.0)
			a["pose"] = "brace"
			a["offset"] += Vector2(roundf(-14.0 * k * dir), 0)
			var feet := stage.point(a, "feet")
			stage.fx(func(ci):
				BattleFX.ellipse(ci, Vector2(feet.x, BattleStage.GROUND_Y), int(8 + k * 18), 3, Color(0.55, 0.47, 0.32, 0.7 * (1.0 - k))))

## Dotted ballistic arc from the actor's basic weapon to the target (Elevation Ballistics).
static func draw_plot_arc(stage: BattleStage, a: Dictionary, d: Dictionary, k: float) -> void:
	var weapon: String = (a["data"] as MechData).basic_weapon_id
	var m := stage.point(a, "muzzles/" + weapon)
	var tgt := stage.point(d, "hull")
	var arc: float = WeaponAnims.PROFILES.get(weapon, {}).get("arc", 20.0)
	stage.fx(func(ci):
		var n := int(24 * k)
		for i in n:
			var u := float(i) / 24.0
			var p := m.lerp(tgt, u) + Vector2(0, -sin(u * PI) * arc)
			if i % 2 == 0:
				ci.draw_rect(Rect2(p.round(), Vector2(1, 1)), C_LOCK))

## The soften visual on the impact of the opponent's next hit.
static func soften(stage: BattleStage, a: Dictionary, d: Dictionary, ability_id: String, dt: float) -> void:
	var dir: int = a["dir"]
	match ability_id:
		"krupp_plate":
			if dt < 0.5:
				var g := stage.point(d, "glacis")
				stage.fx(func(ci):
					BattleFX.sparks(ci, g, dt / 0.5, 12, 22.0, 5)
					var p := g + Vector2(-dir * dt * 160.0, -dt * 120.0)
					BattleFX.tracer_dash(ci, p, -dir, 5))
		"gyro_thruster":
			if dt < 0.45:
				var s := sin(dt / 0.45 * PI) * 7.0
				d["offset"] += Vector2(roundf(s * dir), 0)
				d["ghosts"] = [Vector2(roundf(-s * dir * 0.6), 0)]
		"ablative_shield":
			if dt < 0.5:
				var b := stage.point(d, "hull") + Vector2(-dir * 16, 0)
				stage.fx(func(ci):
					BattleFX.explosion(ci, b, dt / 0.5, 0.8)
					for i in 6:
						var p := b + Vector2(-dir * (6 + dt * 60.0) * (1 + i % 3), (i - 3) * 4 + dt * dt * 60.0)
						ci.draw_rect(Rect2(p.round(), Vector2(2, 2)), BattleFX.SMOKE_MID))

static func _slab_pos(stage: BattleStage, a: Dictionary) -> Vector2:
	# Slab stands just in front of the Siegebreaker, feet on the ground line.
	var base: Vector2 = a["base"]
	var att := MechSpriteBank.anchor(a["sheet"], "attach/slab", "idle0", a["mirrored"])
	var w := 40.0
	var x := base.x + att.x - (w if not a["mirrored"] else 0.0)
	return Vector2(roundf(x), BattleStage.GROUND_Y - 54)

static func draw_slab(stage: BattleStage, ci: CanvasItem, a: Dictionary) -> void:
	_draw_attach(ci, _attach_tex("slab", a), _slab_pos(stage, a), a["mirrored"])

## Cached: draw commands only hold the texture RID, so a texture loaded inside _draw and dropped
## right after would be freed before the frame renders (it shows as a white box).
static var _attach_cache: Dictionary = {}   # name -> [coalition tex, syndikat tex] (null until loaded)

static func _attach_tex(name: String, a: Dictionary) -> Texture2D:
	return _attach_tex_for(name, clampi(int(a["faction"]), 0, 1))

static func _attach_tex_for(name: String, faction: int) -> Texture2D:
	var pair: Array = _attach_cache.get(name, [])
	if pair.is_empty():
		pair = [null, null, false, false]   # textures per faction, then "load attempted" flags
		_attach_cache[name] = pair
	if not pair[2 + faction]:
		pair[2 + faction] = true
		pair[faction] = load("res://assets/battle/fx/%s_%s.png" % [name, MechSpriteBank.FACTION_NAMES[faction]]) as Texture2D
	return pair[faction]

## Loads every attachment texture for a faction up front so no load() happens mid-animation.
static func warm(faction: int) -> void:
	for n in ATTACH_NAMES:
		_attach_tex_for(n, clampi(faction, 0, 1))

static func _draw_attach(ci: CanvasItem, tex: Texture2D, pos: Vector2, mirrored: bool) -> void:
	if tex == null:
		return
	if mirrored:
		ci.draw_set_transform(Vector2(pos.x + tex.get_width(), pos.y), 0.0, Vector2(-1, 1))
	else:
		ci.draw_set_transform(pos, 0.0, Vector2.ONE)
	ci.draw_texture(tex, Vector2.ZERO)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Extending attachments (mast, rangefinder) drawn at their anchors, revealed by `ext` 0..1.
static func draw_attachment(stage: BattleStage, ci: CanvasItem, a: Dictionary, name: String, ext: float) -> void:
	var tex := _attach_tex(name, a)
	if tex == null or ext <= 0.0:
		return
	var anchor := stage.point(a, "attach/" + name)
	var size := Vector2(tex.get_width(), tex.get_height())
	if name == "mast":
		var shown := roundf(size.y * ext)
		var src := Rect2(0, 0, size.x, shown)
		ci.draw_texture_rect_region(tex, Rect2(Vector2(anchor.x - size.x / 2.0, anchor.y - shown).round(), Vector2(size.x, shown)), src)
	else:
		var lift := roundf(6.0 * ext)
		ci.draw_texture(tex, Vector2(anchor.x - size.x / 2.0, anchor.y - size.y - lift).round())
