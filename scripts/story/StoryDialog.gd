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

## The line's body wrapped for the box at virtual size v.
static func wrapped(line: Dictionary, v: Vector2) -> PackedStringArray:
	var r := box_rect(v)
	var who: String = str(line.get("who", ""))
	return CrtUI.wrap_lines(str(line.get("text", "")), r.end.x - 12 - _text_x(r, who))

## Characters the typewriter has to reveal for this line.
static func char_count(line: Dictionary, v: Vector2) -> int:
	var n := 0
	for l in wrapped(line, v):
		n += l.length()
	return n

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
	var left: int = shown if shown >= 0 else (1 << 30)
	var lines := wrapped(line, v)
	var col: Color = CrtUI.C_NUM if who != "" else CrtUI.C_LABEL
	for l in lines:
		if left <= 0:
			break
		CrtUI.text(ci, l.substr(0, left), Vector2(tx, y), col)
		left -= l.length()
		y += CrtUI.LINE + 2
	CrtUI.text_right(ci, hint, r.end.x - 22, r.end.y - 12, CrtUI.C_LABEL_DIM)
	if left > 0 and blink:
		CrtUI.cursor(ci, Vector2(r.end.x - 16, r.end.y - 12))
