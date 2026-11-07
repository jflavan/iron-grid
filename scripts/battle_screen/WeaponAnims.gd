class_name WeaponAnims
extends RefCounted

## Weapon attack animations. Each runs as a pure function of local time t: it sets the actor and
## target poses/effects on their state dictionaries and queues FX draws on the stage.
## The stage applies the step's damage when local time crosses impact_time() (the first hit).
## `hit` false (a MISS) plays the shot and its tracers but none of the impact: no explosion,
## sparks or hit reaction on the target, which dodges instead (BattleStage._animate).
## Loading always happens inside the machine and is never shown.

const PROFILES := {
	"kwk_88":        {"kind": "shell",   "fire": 0.40, "travel": 0.30, "tail": 1.30, "arc": 6.0, "size": 1.0, "flash": 1.0},
	"assault_105":   {"kind": "shell",   "fire": 0.45, "travel": 0.26, "tail": 1.35, "arc": 3.0, "size": 1.35, "flash": 1.4},
	"coax_mg":       {"kind": "mg",      "fire": 0.25, "travel": 0.16, "tail": 1.45, "rounds": 10, "interval": 0.06},
	"autocannon_50": {"kind": "burst",   "fire": 0.30, "travel": 0.20, "tail": 1.25, "rounds": 3, "interval": 0.14},
	"flak_38":       {"kind": "flak",    "fire": 0.30, "travel": 0.22, "tail": 1.35, "rounds": 4, "interval": 0.12},
	"morser_210":    {"kind": "lob",     "fire": 0.50, "travel": 0.75, "tail": 1.50, "arc": 34.0, "size": 1.6},
	"rocket_pod":    {"kind": "rockets", "fire": 0.35, "travel": 0.60, "tail": 1.55, "rounds": 6, "interval": 0.08, "arc": 30.0},
	"thermite_lance": {"kind": "flame",  "fire": 0.35, "travel": 0.25, "tail": 1.45},
	"pile_bunker":   {"kind": "ram",     "fire": 0.10, "travel": 0.40, "tail": 1.10},
}
const DEFAULT := "kwk_88"
const C_CASING := Color("#d8a040")

static func has_anim(card_id: String) -> bool:
	return PROFILES.has(card_id)

static func _p(card_id: String) -> Dictionary:
	return PROFILES.get(card_id, PROFILES[DEFAULT])

static func fire_time(card_id: String) -> float:
	return float(_p(card_id)["fire"])

static func impact_time(card_id: String) -> float:
	return fire_time(card_id) + float(_p(card_id)["travel"])

static func duration(card_id: String) -> float:
	return impact_time(card_id) + float(_p(card_id)["tail"])

static func run(stage: BattleStage, a: Dictionary, d: Dictionary, card_id: String, t: float, hit: bool = true) -> void:
	var p := _p(card_id)
	var fire := fire_time(card_id)
	var imp := impact_time(card_id)
	var id := card_id if PROFILES.has(card_id) else DEFAULT
	match String(p["kind"]):
		"shell":
			_shell(stage, a, d, id, p, t, fire, imp, hit)
		"mg":
			_rounds(stage, a, d, id, p, t, fire, imp, "mg", hit)
		"burst":
			_rounds(stage, a, d, id, p, t, fire, imp, "burst", hit)
		"flak":
			_rounds(stage, a, d, id, p, t, fire, imp, "flak", hit)
		"lob":
			_lob(stage, a, d, id, p, t, fire, imp, hit)
		"rockets":
			_rockets(stage, a, d, id, p, t, fire, imp, hit)
		"flame":
			_flame(stage, a, d, id, p, t, fire, imp, hit)
		"ram":
			_ram(stage, a, d, id, p, t, fire, imp, hit)

# ---------------------------------------------------------------- shared building blocks
static func recoil_pose(dt: float) -> String:
	if dt < 0.10:
		return "recoil0"
	if dt < 0.22:
		return "recoil1"
	if dt < 0.38:
		return "recoil2"
	if dt < 0.60:
		return "recoil3"
	return "brace"

static func hit_reaction(_stage: BattleStage, d: Dictionary, dt: float, size: float = 1.0) -> void:
	if dt < 0.0:
		return
	if dt < 0.24 and int(dt / 0.045) % 2 == 0:
		d["white"] = true
	var shake_dur := 0.53 * size
	if dt < shake_dur:
		d["offset"] += Vector2(roundf(sin(dt * 45.0) * 3.0 * size * (1.0 - dt / shake_dur)), 0)
	if dt < 0.38 * size:
		d["pose"] = "hit"

static func _muzzle(stage: BattleStage, a: Dictionary, id: String) -> Vector2:
	return stage.point(a, MechSpriteBank.muzzle_name(id))

# ---------------------------------------------------------------- single heavy shell (88mm, 105mm)
static func _shell(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, imp: float, hit: bool) -> void:
	a["pose"] = "brace"
	if t >= fire - 0.15 and t < fire - 0.07:
		a["pose"] = "chamber" # external breech jolt only; loading is internal
	if t >= fire:
		a["pose"] = recoil_pose(t - fire)
	var dir: int = a["dir"]
	var muzzle := _muzzle(stage, a, id)
	var target := stage.point(d, "hull")
	var flash: float = p["flash"]
	if t >= fire and t < fire + 0.12:
		var f := int((t - fire) / 0.04)
		stage.fx(func(ci): BattleFX.muzzle_flash(ci, muzzle, f, dir, flash))
	if t >= fire + 0.05 and t < fire + 1.1:
		var k := (t - fire - 0.05) / 1.05
		stage.fx(func(ci): BattleFX.smoke_trail(ci, muzzle, k, dir))
	if t >= fire and t < fire + 0.8 and id == "kwk_88":
		var k := (t - fire) / 0.8
		var casing := stage.point(a, "hull") + Vector2((-18 - k * 22) * dir, -20 + k * k * 90 - k * 30)
		stage.fx(func(ci): ci.draw_rect(Rect2(casing.round(), Vector2(3, 2) if int(k * 12) % 2 else Vector2(2, 3)), C_CASING))
	if t >= fire and t < imp:
		var k := (t - fire) / (imp - fire)
		var pos := muzzle.lerp(target, k) + Vector2(0, -sin(k * PI) * float(p["arc"]))
		stage.fx(func(ci): BattleFX.tracer_shell(ci, pos, dir))
	if hit and t >= imp:
		var size: float = p["size"]
		hit_reaction(stage, d, t - imp, size)
		if t < imp + 0.63:
			var k := (t - imp) / 0.63
			stage.fx(func(ci): BattleFX.explosion(ci, target, k, size))

# ---------------------------------------------------------------- multi-round fire (MG, autocannon, flak)
static func _rounds(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, imp: float, style: String, hit: bool) -> void:
	var n: int = p["rounds"]
	var interval: float = p["interval"]
	var travel: float = p["travel"]
	var dir: int = a["dir"]
	var target := stage.point(d, "hull")
	a["pose"] = "brace"
	var last_shot := fire + (n - 1) * interval
	if t >= fire and t < last_shot + 0.3:
		var since := fmod(t - fire, interval)
		if style == "burst":
			a["pose"] = "recoil1" if since < 0.06 else "recoil3"
		elif style == "flak":
			a["pose"] = "recoil2" if since < 0.05 else "recoil3"
		else:
			a["pose"] = "recoil3" if int((t - fire) / 0.03) % 2 == 0 else "brace"
	var muzzle := _muzzle(stage, a, id)
	var hit_count := 0
	for i in n:
		var t0 := fire + i * interval
		var spread := Vector2(0, ((i * 7) % 5 - 2) * 3.0)
		var barrel := Vector2(0, ((i % 4) - 1.5) * 4.0) if style == "flak" else Vector2.ZERO
		if t >= t0 and t < t0 + 0.06:
			var f := 1 if style == "mg" else 0
			var scale := 0.6 if style == "mg" else (0.8 if style == "flak" else 0.9)
			var mp := muzzle + barrel
			stage.fx(func(ci): BattleFX.muzzle_flash(ci, mp, f, dir, scale))
		if t >= t0 and t < t0 + travel:
			var k := (t - t0) / travel
			var pos := (muzzle + barrel).lerp(target + spread, k)
			if style == "mg":
				stage.fx(func(ci): BattleFX.tracer_dash(ci, pos, dir, 6))
			else:
				stage.fx(func(ci): BattleFX.tracer_shell(ci, pos, dir, 6))
		var hit_t := t0 + travel
		if hit and t >= hit_t:
			hit_count += 1
			var kk := (t - hit_t) / 0.4
			if kk < 1.0:
				var hp := target + spread
				if style == "mg":
					stage.fx(func(ci): BattleFX.sparks(ci, hp, kk, 5, 10.0, i))
				elif style == "flak":
					stage.fx(func(ci):
						BattleFX.blob(ci, hp, int(3 + kk * 5), BattleFX.SMOKE_MID if kk > 0.3 else Color.WHITE)
						BattleFX.sparks(ci, hp, kk, 6, 14.0, i))
				else:
					stage.fx(func(ci): BattleFX.explosion(ci, hp, kk, 0.6))
	if hit and t >= imp:
		hit_reaction(stage, d, t - imp, 0.7 if style == "mg" else 0.9)
		# keep the target jittering while later rounds land
		if hit_count > 1 and t < last_shot + travel + 0.1:
			d["offset"] += Vector2(1 if int(t / 0.04) % 2 == 0 else -1, 0)

# ---------------------------------------------------------------- 210mm Mörser lob
static func _lob(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, imp: float, hit: bool) -> void:
	a["pose"] = "brace"
	if t >= fire:
		a["pose"] = recoil_pose((t - fire) * 0.7)
	var dir: int = a["dir"]
	var muzzle := _muzzle(stage, a, id)
	var target := stage.point(d, "hull")
	if t >= fire and t < fire + 0.16:
		var f := int((t - fire) / 0.055)
		stage.fx(func(ci): BattleFX.muzzle_flash(ci, muzzle, f, dir, 1.6))
	if t >= fire + 0.05 and t < fire + 1.4:
		var k := (t - fire - 0.05) / 1.35
		stage.fx(func(ci):
			BattleFX.smoke_trail(ci, muzzle, k, dir)
			BattleFX.smoke_trail(ci, muzzle + Vector2(0, 4), k * 0.8, dir))
	if t >= fire and t < imp:
		var k := (t - fire) / (imp - fire)
		var pos := muzzle.lerp(target, k) + Vector2(0, -sin(k * PI) * float(p["arc"]))
		var prev := muzzle.lerp(target, maxf(0.0, k - 0.06)) + Vector2(0, -sin(maxf(0.0, k - 0.06) * PI) * float(p["arc"]))
		stage.fx(func(ci):
			ci.draw_line(prev.round(), pos.round(), BattleFX.FLASH_ORANGE, 1.0)
			BattleFX.blob(ci, pos, 3, BattleFX.OUTLINE)
			BattleFX.blob(ci, pos, 2, BattleFX.SHELL)
			ci.draw_rect(Rect2(pos.round() - Vector2(1, 1), Vector2(1, 1)), Color.WHITE))
	if hit and t >= imp:
		hit_reaction(stage, d, t - imp, 1.6)
		if t < imp + 0.9:
			var k := (t - imp) / 0.9
			var feet := stage.point(d, "feet")
			stage.fx(func(ci):
				BattleFX.ellipse(ci, Vector2(feet.x, BattleStage.GROUND_Y), int(20 + k * 40), int(3 + k * 4), Color(0.45, 0.38, 0.25, 0.7 * (1.0 - k)))
				BattleFX.explosion(ci, target, k, 1.6))

# ---------------------------------------------------------------- Nebelwerfer rocket salvo
static func _rockets(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, _imp: float, hit: bool) -> void:
	var n: int = p["rounds"]
	var interval: float = p["interval"]
	var travel: float = p["travel"]
	var dir: int = a["dir"]
	var muzzle := _muzzle(stage, a, id)
	var target := stage.point(d, "hull")
	a["pose"] = "brace"
	if t >= fire and t < fire + n * interval:
		a["pose"] = "recoil3" if int((t - fire) / interval) % 2 == 0 else "brace"
	for i in n:
		var t0 := fire + i * interval
		var tube := muzzle + Vector2(0, (i % 3) * 5.0 - 5.0)
		var aim := target + Vector2(((i * 5) % 7 - 3) * 4.0, ((i * 3) % 5 - 2) * 4.0)
		if t >= t0 and t < t0 + 0.05:
			stage.fx(func(ci): BattleFX.blob(ci, tube, 3, BattleFX.FLASH_YELLOW))
		if t >= t0 and t < t0 + travel:
			var k := (t - t0) / travel
			var arc: float = p["arc"]
			var pos := tube.lerp(aim, k) + Vector2(0, -sin(k * PI) * arc)
			var prev := tube.lerp(aim, maxf(0.0, k - 0.08)) + Vector2(0, -sin(maxf(0.0, k - 0.08) * PI) * arc)
			stage.fx(func(ci):
				for s in 4:
					var sp := prev.lerp(pos, s / 4.0) - (pos - prev) * 0.6 * s
					BattleFX.blob(ci, sp, 2 + s / 2, Color(0.42, 0.40, 0.37, 0.9 - s * 0.18))
				BattleFX.blob(ci, pos - (pos - prev).normalized() * 4.0, 2, BattleFX.FLASH_ORANGE)
				BattleFX.blob(ci, pos - (pos - prev).normalized() * 4.0, 1, BattleFX.FLASH_YELLOW)
				ci.draw_rect(Rect2(pos.round() - Vector2(2, 2), Vector2(5, 4)), BattleFX.OUTLINE)
				ci.draw_rect(Rect2(pos.round() - Vector2(1, 1), Vector2(3, 2)), BattleFX.SHELL))
		var hit_t := t0 + travel
		if hit and t >= hit_t and t < hit_t + 0.5:
			var k := (t - hit_t) / 0.5
			stage.fx(func(ci): BattleFX.explosion(ci, aim, k, 0.8))
	var first := fire + travel
	if hit and t >= first:
		hit_reaction(stage, d, t - first, 1.1)
		if t < first + n * interval:
			d["offset"] += Vector2(2 if int(t / 0.05) % 2 == 0 else -2, 0)

# ---------------------------------------------------------------- Thermite flame lance
static func _flame(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, imp: float, hit: bool) -> void:
	a["pose"] = "brace"
	var dir: int = a["dir"]
	var nozzle := _muzzle(stage, a, id)
	var target := stage.point(d, "hull")
	var stream_end := fire + 1.0
	if t >= fire - 0.25 and t < fire:
		stage.fx(func(ci): BattleFX.blob(ci, nozzle, 2, BattleFX.FLASH_ORANGE if int(t / 0.05) % 2 else BattleFX.FLASH_YELLOW))
	if t >= fire and t < stream_end:
		a["pose"] = "recoil3"
		var reach := clampf((t - fire) / float(p["travel"]), 0.0, 1.0)
		var fade := clampf((stream_end - t) / 0.2, 0.0, 1.0)
		stage.fx(func(ci):
			var steps := 14
			for s in steps:
				var k := float(s) / steps * reach
				var wob := sin(t * 40.0 + s * 1.7) * (1.0 + k * 3.0)
				var pos := nozzle.lerp(target, k) + Vector2(0, wob)
				var r := int(1 + k * 6 * fade)
				var col := BattleFX.FLASH_YELLOW if k < 0.3 else (BattleFX.FLASH_ORANGE if k < 0.7 else BattleFX.FIRE)
				BattleFX.blob(ci, pos, r, col)
				if s % 3 == 0:
					BattleFX.blob(ci, pos + Vector2(0, -r), maxi(1, r / 2), Color.WHITE)
			# heat shimmer: a few displaced bright pixels above the stream
			for s in 6:
				var hp := nozzle.lerp(target, (s + 0.5) / 6.0 * reach) + Vector2(sin(t * 23.0 + s) * 2.0, -8 - (s % 3) * 2)
				ci.draw_rect(Rect2(hp.round(), Vector2(1, 1)), Color(1, 0.9, 0.6, 0.5)))
	if hit and t >= imp:
		hit_reaction(stage, d, t - imp, 0.8)
		if t < stream_end + 0.9:
			var k := (t - imp) / (stream_end + 0.9 - imp)
			stage.fx(func(ci):
				for e in 7:
					var ph := fmod(k * 3.0 + e * 0.37, 1.0)
					var ep := target + Vector2(((e * 11) % 9 - 4) * 3.0, 6 - ph * 22.0)
					BattleFX.blob(ci, ep, int(3 * (1.0 - ph)) + 1, BattleFX.FIRE if ph > 0.4 else BattleFX.FLASH_ORANGE))

# ---------------------------------------------------------------- Hydraulic pile-bunker ram
static func _ram(stage: BattleStage, a: Dictionary, d: Dictionary, id: String, p: Dictionary, t: float, fire: float, imp: float, hit: bool) -> void:
	var dir: int = a["dir"]
	var tip_rest := stage.point(a, MechSpriteBank.muzzle_name(id))
	var target := stage.point(d, "glacis")
	var gap := maxf(0.0, (target.x - tip_rest.x) * dir + 2.0)
	var out := 0.0
	if t < fire:
		a["pose"] = "brace"
	elif t < imp:
		a["pose"] = "lunge"
		var k := (t - fire) / (imp - fire)
		out = gap * k * k
	elif t < imp + 0.18:
		a["pose"] = "lunge"
		out = gap
	elif t < imp + 0.6:
		a["pose"] = "recoil2"
		out = gap * (1.0 - (t - imp - 0.18) / 0.42)
	else:
		a["pose"] = "brace"
	a["offset"] += Vector2(roundf(out * dir), 0)
	if t >= imp and t < imp + 0.12:
		var tip := stage.point(a, MechSpriteBank.muzzle_name(id))
		stage.fx(func(ci):
			ci.draw_rect(Rect2(tip.x - (0 if dir > 0 else 16), tip.y - 1, 16, 3), Color.WHITE)
			BattleFX.blob(ci, tip, 6, BattleFX.FLASH_YELLOW))
	if hit and t >= imp:
		hit_reaction(stage, d, t - imp, 1.3)
		if t < imp + 0.5:
			var k := (t - imp) / 0.5
			stage.fx(func(ci): BattleFX.sparks(ci, target, k, 14, 26.0, 3))
