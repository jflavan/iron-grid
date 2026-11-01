class_name WeaponAnims
extends RefCounted

## Weapon attack animations. Each runs as a pure function of local time t: it sets the actor and
## target poses/effects on their state dictionaries and queues FX draws on the stage.
## `quick` is the shortened follow-up shot used after an armor/tactical card's effect.
## The stage applies the step's damage when local time crosses impact_time().

const FIRE_FULL := 0.40
const FIRE_QUICK := 0.12

static func fire_time(_card_id: String, quick: bool) -> float:
	return FIRE_QUICK if quick else FIRE_FULL

static func travel_time(_card_id: String) -> float:
	return 0.30

static func impact_time(card_id: String, quick: bool) -> float:
	return fire_time(card_id, quick) + travel_time(card_id)

static func duration(card_id: String, quick: bool) -> float:
	return impact_time(card_id, quick) + (0.85 if quick else 1.3)

static func run(stage: BattleStage, a: Dictionary, d: Dictionary, card_id: String, t: float, quick: bool) -> void:
	_shell(stage, a, d, card_id, t, quick)

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

static func hit_reaction(stage: BattleStage, d: Dictionary, dt: float, size: float = 1.0) -> void:
	if dt < 0.0:
		return
	if dt < 0.24 and int(dt / 0.045) % 2 == 0:
		d["white"] = true
	if dt < 0.53:
		d["offset"] += Vector2(roundf(sin(dt * 45.0) * 3.0 * (1.0 - dt / 0.53) * size), 0)
	if dt < 0.38:
		d["pose"] = "hit"

# ---------------------------------------------------------------- generic tank-gun shell (88mm reference)
static func _shell(stage: BattleStage, a: Dictionary, d: Dictionary, card_id: String, t: float, quick: bool) -> void:
	var fire := fire_time(card_id, quick)
	var imp := impact_time(card_id, quick)
	a["pose"] = "brace"
	if not quick and t >= 0.25 and t < 0.33:
		a["pose"] = "chamber"
	if t >= fire:
		a["pose"] = recoil_pose(t - fire)
	var dir: int = a["dir"]
	var muzzle := stage.point(a, "muzzles/" + card_id)
	var target := stage.point(d, "hull")
	if t >= fire and t < fire + 0.12:
		var f := int((t - fire) / 0.04)
		stage.fx(func(ci): BattleFX.muzzle_flash(ci, muzzle, f, dir))
	if t >= fire + 0.05 and t < fire + 1.1:
		var k := (t - fire - 0.05) / 1.05
		stage.fx(func(ci): BattleFX.smoke_trail(ci, muzzle, k, dir))
	if t >= fire and t < imp:
		var k := (t - fire) / (imp - fire)
		var p := muzzle.lerp(target, k) + Vector2(0, -sin(k * PI) * 6.0)
		stage.fx(func(ci): BattleFX.tracer_shell(ci, p, dir))
	if t >= imp:
		hit_reaction(stage, d, t - imp)
		if t < imp + 0.63:
			var k := (t - imp) / 0.63
			stage.fx(func(ci): BattleFX.explosion(ci, target, k))
