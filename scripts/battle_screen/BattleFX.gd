class_name BattleFX
extends RefCounted

## Pixel-art effect primitives drawn on a CanvasItem at native 360x225 resolution
## (muzzle flashes, tracers, explosions, smoke, sparks, CRT panels, damage numbers).

const OUTLINE := Color("#16120e")
const FLASH_ORANGE := Color("#ffb030")
const FLASH_YELLOW := Color("#fff4a0")
const SPARK := Color("#ffd060")
const FIRE := Color("#e05a20")
const SMOKE_DARK := Color("#3a3530")
const SMOKE_MID := Color("#5a5048")
const SMOKE_LIGHT := Color("#8a857c")
const SHELL := Color("#c0c4c8")

const CRT_FILL := CrtUI.C_FILL
const CRT_SCAN := CrtUI.C_SCAN
const CRT_BORDER := CrtUI.C_BORDER
const CRT_RULE := CrtUI.C_RULE

static func blob(ci: CanvasItem, c: Vector2, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		var w := int(round(sqrt(maxf(0.0, r * r - dy * dy))))
		ci.draw_rect(Rect2(roundf(c.x) - w, roundf(c.y) + dy, w * 2, 1), col)

static func ellipse(ci: CanvasItem, c: Vector2, rw: int, rh: int, col: Color) -> void:
	for dy in range(-rh, rh + 1):
		var w := int(round(rw * sqrt(maxf(0.0, 1.0 - float(dy * dy) / float(rh * rh)))))
		ci.draw_rect(Rect2(roundf(c.x) - w, roundf(c.y) + dy, w * 2, 1), col)

static func panel(ci: CanvasItem, r: Rect2) -> void:
	CrtUI.panel(ci, r)

## frame 0..2 (big -> small); dir = +1 fires to the right, -1 to the left; scale enlarges heavy guns.
static func muzzle_flash(ci: CanvasItem, p: Vector2, frame: int, dir: int, scale: float = 1.0) -> void:
	frame = clampi(frame, 0, 2)
	var l := int([14, 10, 5][frame] * scale)
	var hh := int([5, 4, 2][frame] * scale)
	var x0 := p.x if dir > 0 else p.x - l
	ci.draw_rect(Rect2(x0, p.y - hh, l, hh * 2), FLASH_ORANGE)
	ci.draw_rect(Rect2(p.x - 2, p.y - hh - 3, 4, hh * 2 + 6), FLASH_ORANGE)
	var inner := maxi(1, l - 3)
	ci.draw_rect(Rect2(p.x if dir > 0 else p.x - inner, p.y - hh + 2, inner, maxi(1, hh * 2 - 4)), FLASH_YELLOW)
	var core := maxi(2, l - 6)
	ci.draw_rect(Rect2(p.x if dir > 0 else p.x - core, p.y - 1, core, 2), Color.WHITE)
	if frame == 0:
		for o in [Vector2(4, -9), Vector2(9, -7), Vector2(4, 8), Vector2(10, 6), Vector2(16, -3), Vector2(17, 3)]:
			ci.draw_rect(Rect2(p.x + o.x * dir * scale, p.y + o.y * scale, 2, 2), SPARK)

## k: 0..1 lifetime. size scales the fireball.
static func explosion(ci: CanvasItem, c: Vector2, k: float, size: float = 1.0) -> void:
	var r := int(round((3.0 + k * 16.0) * size))
	if k < 0.15:
		blob(ci, c, r + int(4 * size), Color.WHITE)
		return
	blob(ci, c + Vector2(-2, 1), r, SMOKE_DARK)
	blob(ci, c + Vector2(1, -2), int(r * 0.85), SMOKE_MID)
	if k < 0.7:
		blob(ci, c, int(r * 0.7 * (1.0 - k) + 3), FIRE)
		blob(ci, c, int(r * 0.45 * (1.0 - k) + 2), FLASH_ORANGE)
		blob(ci, c, int(r * 0.2 * (1.0 - k) + 1), FLASH_YELLOW)
	for i in 10:
		var a := i * 0.63
		var d := (4.0 + k * 28.0) * size
		ci.draw_rect(Rect2(roundf(c.x + cos(a) * d), roundf(c.y + sin(a) * d * 0.8 + k * k * 14.0), 2, 2), SPARK)

static func tracer_shell(ci: CanvasItem, p: Vector2, dir: int, trail: int = 12) -> void:
	var x := roundf(p.x)
	var y := roundf(p.y)
	ci.draw_rect(Rect2(x - (trail + 2) * dir if dir > 0 else x + 3, y, trail, 1), FLASH_ORANGE)
	ci.draw_rect(Rect2(x - 6 if dir > 0 else x + 1, y, 6, 1), FLASH_YELLOW)
	ci.draw_rect(Rect2(x - 1, y - 2, 7, 5) if dir > 0 else Rect2(x - 5, y - 2, 7, 5), OUTLINE)
	ci.draw_rect(Rect2(x, y - 1, 4, 3) if dir > 0 else Rect2(x - 3, y - 1, 4, 3), SHELL)

static func tracer_dash(ci: CanvasItem, p: Vector2, dir: int, length: int = 6) -> void:
	ci.draw_rect(Rect2(p.x - (length if dir > 0 else 0), p.y, length, 1), FLASH_YELLOW)
	ci.draw_rect(Rect2(p.x - (length + 3 if dir > 0 else -length), p.y, 3, 1), FLASH_ORANGE)

static func sparks(ci: CanvasItem, c: Vector2, k: float, count: int = 8, spread: float = 18.0, seed: int = 0) -> void:
	for i in count:
		var a := float(i) * 2.399 + float(seed)
		var d := 2.0 + k * spread * (0.6 + 0.4 * sin(a * 3.0))
		ci.draw_rect(Rect2(roundf(c.x + cos(a) * d), roundf(c.y + sin(a) * d * 0.7 + k * k * 10.0), 1 if i % 3 else 2, 1), SPARK if i % 2 else Color.WHITE)

static func smoke_trail(ci: CanvasItem, p: Vector2, k: float, dir: int) -> void:
	for i in 3:
		var kk := maxf(0.0, k - i * 0.12)
		blob(ci, p + Vector2((4 + kk * 14 + i * 3) * dir, -kk * 16 - i * 2), int(2 + kk * 5), SMOKE_LIGHT if kk < 0.4 else Color("#6c675f"))

static func exhaust(ci: CanvasItem, p: Vector2, t: float, seed: float, dir: int) -> void:
	for k in 4:
		var life := fmod(t / 0.9 + k / 4.0 + seed, 1.0)
		var px := p.x + roundf(life * -6.0 * dir + sin(life * 6.0 + k) * 2.0)
		var py := p.y - roundf(life * 18.0)
		var col := Color("#6a665e") if life < 0.5 else Color("#857f74")
		col.a = 1.0 - life * 0.8
		blob(ci, Vector2(px, py), 1 + int(round(life * 3.0)), col)

static func shadow(ci: CanvasItem, cx: float, cy: float, rw: int) -> void:
	ellipse(ci, Vector2(cx, cy), rw, 4, Color(0.08, 0.09, 0.04, 0.45))

## FF6-style bouncing damage number; age in seconds.
static func damage_number(ci: CanvasItem, value: int, p: Vector2, age: float) -> void:
	var k := age / 1.2
	var bounce := 0.0
	if k < 0.35:
		bounce = absf(sin(k / 0.35 * PI)) * 14.0
	elif k < 0.5:
		bounce = absf(sin((k - 0.35) / 0.15 * PI)) * 4.0
	var text := str(value)
	var pos := Vector2(roundf(p.x - PixelFont.text_width(text)), roundf(p.y - 30.0 - bounce))
	ci.draw_set_transform(pos, 0.0, Vector2(2, 2))
	for o in [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, -0.5), Vector2(0, 0.5)]:
		PixelFont.draw_text(ci, text, o, OUTLINE)
	PixelFont.draw_text(ci, text, Vector2.ZERO, Color.WHITE)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
