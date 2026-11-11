class_name StoryDialog
extends RefCounted

## Draws one portrait dialog line in the CRT style, shared by the Story screen (cutscenes) and the
## tactical HUD (mid-mission lines). A line is {"who": StoryCast id or "" for narration, "text",
## optional "as": display name override ("???")}. Layout is in CrtUI virtual pixels.

const BOX_H := 112
const MARGIN := 24
const PORTRAIT_SCALE := 2
const TYPE_CPS := 60.0   # typewriter speed, characters per second

const TICK_EVERY := 3      # typewriter blip once per this many characters

## Plays the typewriter blip when the reveal crossed a TICK_EVERY boundary this frame (and the line
## is not finished). Callers pass the character counts before and after advancing the typewriter.
static func type_tick(before: int, after: int, total: int) -> void:
	if after > before and before < total and after / TICK_EVERY != before / TICK_EVERY:
		SoundManager.play("type_blip", 1.0 + 0.06 * float(after % 3))

static func box_rect(v: Vector2) -> Rect2:
	return Rect2(MARGIN, v.y - BOX_H - 8, v.x - 2 * MARGIN, BOX_H)

static func _text_x(r: Rect2, who: String) -> float:
	return r.position.x + (10 + StoryCast.PORTRAIT_SIZE * PORTRAIT_SCALE + 12 if who != "" else 16)

static var _memo_text: String = ""
static var _memo_px: float = -1.0
static var _memo_lines: PackedStringArray = []

## `text` wrapped at `px` virtual pixels. The last answer is kept: a line on screen is asked for
## every frame (typewriter count and draw) and only changes when the dialog moves on.
static func wrap_text(text: String, px: float) -> PackedStringArray:
	if text != _memo_text or px != _memo_px:
		_memo_text = text
		_memo_px = px
		_memo_lines = CrtUI.wrap_lines(text, px)
	return _memo_lines

## Characters the typewriter has to reveal for these wrapped lines.
static func count(lines: PackedStringArray) -> int:
	var n := 0
	for l in lines:
		n += l.length()
	return n

## The wrapped lines as the typewriter shows them after `shown` characters (-1 = all): one entry
## per line, "" for a line not reached yet.
static func reveal(lines: PackedStringArray, shown: int) -> PackedStringArray:
	var out := PackedStringArray()
	var left: int = shown if shown >= 0 else (1 << 30)
	for l in lines:
		out.append(l.substr(0, maxi(left, 0)))
		left -= l.length()
	return out

## True once `shown` characters cover the whole of `lines` (the "next" cursor may blink).
static func typed(lines: PackedStringArray, shown: int) -> bool:
	return shown < 0 or shown >= count(lines)

## The line's body wrapped for the HUD box at virtual size v.
static func wrapped(line: Dictionary, v: Vector2) -> PackedStringArray:
	var r := box_rect(v)
	var who: String = str(line.get("who", ""))
	return wrap_text(str(line.get("text", "")), r.end.x - 12 - _text_x(r, who))

## Characters the typewriter has to reveal for this line in the HUD box.
static func char_count(line: Dictionary, v: Vector2) -> int:
	return count(wrapped(line, v))

## Draws the box with the first `shown` characters of the line (-1 = all); `blink` lights the
## "next" cursor once the line is fully shown. `hint` is the key help in the bottom-right corner.
static func draw(ci: CanvasItem, v: Vector2, line: Dictionary, shown: int = -1, blink: bool = true, hint: String = "SPACE: NEXT  ESC: SKIP") -> void:
	var r := box_rect(v)
	var who: String = str(line.get("who", ""))
	var hostile: bool = StoryCast.side(who) == StoryCast.SYNDIKAT
	var accent: Color = CrtUI.C_HOSTILE if hostile else CrtUI.C_BORDER
	CrtUI.panel(ci, r, accent)
	var tx := _text_x(r, who)
	var y := r.position.y + 10
	if who != "":
		var ps := float(StoryCast.PORTRAIT_SIZE * PORTRAIT_SCALE)
		var pr := Rect2(r.position.x + 8, r.position.y + 8, ps + 2, ps + 2)
		CrtUI.frame(ci, pr, accent)
		var tex := StoryCast.portrait(who)
		if tex != null:
			ci.draw_texture_rect(tex, Rect2(pr.position + Vector2.ONE, Vector2(ps, ps)), false)
		else:
			CrtUI.text_centered(ci, "NO SIGNAL", pr.get_center().x, pr.get_center().y - 4, CrtUI.C_DIM)
		CrtUI.text(ci, str(line.get("as", StoryCast.display_name(who))), Vector2(tx, y), CrtUI.C_HOSTILE if hostile else CrtUI.C_NAME)
		y += 14
		CrtUI.hrule(ci, tx, y - 4, r.end.x - 12 - tx)
	var lines := wrapped(line, v)
	var col: Color = CrtUI.C_NUM if who != "" else CrtUI.C_LABEL
	for l in reveal(lines, shown):
		if l != "":
			CrtUI.text(ci, l, Vector2(tx, y), col)
		y += CrtUI.LINE + 2
	CrtUI.text_right(ci, hint, r.end.x - 22, r.end.y - 12, CrtUI.C_LABEL_DIM)
	if typed(lines, shown) and blink:
		CrtUI.cursor(ci, Vector2(r.end.x - 16, r.end.y - 12))
