class_name CrtUI
extends RefCounted

## The battle screen's menu style, shared by every screen: scanline CRT panels with a 1px green
## border and inner rule, the 5x7 PixelFont, amber names / green labels / cream numbers, the
## yellow cursor and thin gauges.
##
## The battle screen draws at native 360x225 scaled 4x. The main menu and the tactical HUD draw
## in "virtual" pixels at an integer scale (2x at the 1440x900 design size, see DESIGN): call
## begin() at the top of _draw, then lay out in virtual pixels from virtual_size().

const DESIGN := Vector2i(720, 450)

const C_SCREEN := Color("#050805")
const C_FILL := Color("#0c100c")
const C_SCAN := Color("#0f150f")
const C_BORDER := Color("#3ad06a")
const C_RULE := Color("#1d5a2f")

const C_LABEL := Color("#3ad06a")
const C_LABEL_DIM := Color("#2b9c4f")
const C_NAME := Color("#e8b040")
const C_NUM := Color("#e8e8d0")
const C_DIM := Color("#586858")
const C_CURSOR := Color("#ffe080")
const C_HOSTILE := Color("#e05848")
const C_GAUGE_BG := Color("#16301c")
const C_FUEL := Color("#e0a030")
const C_EN := Color("#38b8f0")
const C_HULL := Color("#e04838")

const LINE := 10        # line pitch for body text (8px glyphs + 2px leading)
const ROW := 12         # row pitch for selectable menu rows

## Characters the 5x7 font lacks, mapped to the nearest glyph it has.
const _SUBSTITUTES := {"|": "/", "~": "", "*": "#", "{": "(", "}": ")", "–": "-", "×": "X", "@": "#"}

# ---------------------------------------------------------------- scale
## Largest integer scale at which DESIGN fits the viewport (never below 1).
static func pixel_scale(viewport_size: Vector2) -> int:
	return maxi(1, mini(int(viewport_size.x) / DESIGN.x, int(viewport_size.y) / DESIGN.y))

static func virtual_size(viewport_size: Vector2, scale: int) -> Vector2:
	return (viewport_size / float(scale)).floor()

static func begin(ci: CanvasItem, scale: int) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, scale))

static func to_virtual(screen_pos: Vector2, scale: int) -> Vector2:
	return screen_pos / float(scale)

# ---------------------------------------------------------------- text
static func sanitize(s: String) -> String:
	var up := s.to_upper()
	var out := ""
	for ch in up:
		out += _SUBSTITUTES.get(ch, ch)
	return out

static func text(ci: CanvasItem, s: String, pos: Vector2, col: Color) -> void:
	PixelFont.draw_text(ci, sanitize(s), pos.round(), col)

static func text_right(ci: CanvasItem, s: String, right_x: float, y: float, col: Color) -> void:
	text(ci, s, Vector2(right_x - PixelFont.text_width(s), y), col)

static func text_centered(ci: CanvasItem, s: String, center_x: float, y: float, col: Color) -> void:
	text(ci, s, Vector2(roundf(center_x - PixelFont.text_width(s) / 2.0), y), col)

static func wrap_lines(s: String, max_px: float) -> PackedStringArray:
	return PixelFont.wrap(sanitize(s), int(max_px))

## Cuts s to fit max_px, ending in ".." when shortened.
static func fit(s: String, max_px: float) -> String:
	var max_chars := int(max_px) / PixelFont.ADVANCE
	if s.length() <= max_chars:
		return s
	return s.substr(0, maxi(0, max_chars - 2)) + ".."

## Draws wrapped lines from pos, stopping before max_y. Returns the y below the last line drawn.
static func paragraph(ci: CanvasItem, s: String, pos: Vector2, max_px: float, col: Color, max_y: float = INF) -> float:
	var y := pos.y
	for line in wrap_lines(s, max_px):
		if y + PixelFont.HEIGHT > max_y:
			break
		text(ci, line, Vector2(pos.x, y), col)
		y += LINE
	return y

# ---------------------------------------------------------------- shapes
## The battle screen's CRT panel. alpha fades the whole panel (phase banners).
static func panel(ci: CanvasItem, r: Rect2, border: Color = C_BORDER, alpha: float = 1.0) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, _a(C_FILL, alpha))
	var scan := _a(C_SCAN, alpha)
	var y := 1
	while y < int(r.size.y):
		ci.draw_rect(Rect2(r.position.x, r.position.y + y, r.size.x, 1), scan)
		y += 2
	var b := _a(border, alpha)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), b)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), b)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), b)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), b)
	var rule := C_RULE if border == C_BORDER else Color(border, 0.35)
	ci.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)), _a(rule, alpha))

## Plain inset frame (portrait boxes, items inside a panel).
static func frame(ci: CanvasItem, r: Rect2, border: Color = C_RULE) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, C_FILL)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), border)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), border)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), border)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), border)

static func hrule(ci: CanvasItem, x: float, y: float, w: float) -> void:
	ci.draw_rect(Rect2(roundf(x), roundf(y), roundf(w), 1), C_RULE)

## The battle menu's cursor: a 6x7 triangle pointing right, top-left at pos.
static func cursor(ci: CanvasItem, pos: Vector2, col: Color = C_CURSOR) -> void:
	var p := pos.round()
	ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(6, 3.5), p + Vector2(0, 7)]), col)

static func gauge(ci: CanvasItem, r: Rect2, ratio: float, col: Color) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r, C_GAUGE_BG)
	ci.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(ratio, 0.0, 1.0)), r.size.y)), col)

## Draws a battle sprite's idle frame standing on the bottom edge of cell, centred horizontally.
## scale is the CrtUI pixel scale the caller passed to begin(); the transform is restored after.
static func mech(ci: CanvasItem, chassis: String, faction: int, cell: Rect2, mirrored: bool, t_ms: float, scale: int) -> void:
	var tex := MechSpriteBank.get_sheet(chassis, faction)
	if tex == null:
		return
	var src := MechSpriteBank.frame_rect(chassis, MechSpriteBank.idle_pose(chassis, t_ms))
	var pos := Vector2(roundf(cell.position.x + (cell.size.x - src.size.x) / 2.0), cell.end.y - src.size.y)
	if mirrored:
		ci.draw_set_transform_matrix(Transform2D(Vector2(-scale, 0), Vector2(0, scale), (pos + Vector2(src.size.x, 0)) * scale))
	else:
		ci.draw_set_transform_matrix(Transform2D(Vector2(scale, 0), Vector2(0, scale), pos * scale))
	ci.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, src.size), src)
	begin(ci, scale)

## Largest battle sprite cell across chassis, so portrait boxes can be sized to never clip or overlap.
static func max_mech_cell(chassis_ids: Array) -> Vector2:
	var m := Vector2.ZERO
	for c in chassis_ids:
		m = m.max(MechSpriteBank.cell_size(c))
	return m

static func _a(c: Color, alpha: float) -> Color:
	return Color(c, c.a * alpha)
