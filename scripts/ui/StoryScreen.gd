class_name StoryScreen
extends CrtScreen

## Story mode's own screen, in three modes:
##   list      the campaign: every chapter by act, what is cleared, what is next
##   scene     a cutscene (prologue / epilogue, mission briefings and debriefs): a title card, then
##             a painted backdrop with the two most recent speakers on stage and the dialog below
##   briefing  the mission's map preview, objective and line-up, with LAUNCH
## It resumes from GlobalState.story_stage: "list", "pre" (run GlobalState.story_chapter from its
## start) or "post" (the mission was just won: play its debrief, then move on).
## Controls: Up/Down + Enter on the list (N twice starts a new campaign, Esc returns to Command HQ);
## Space / Enter / click advances dialog, Esc skips the scene; Enter launches from the briefing.

const MODE_LIST := "list"
const MODE_SCENE := "scene"
const MODE_BRIEFING := "briefing"
const LIST_W := 262
const ROW := 12

var mode: String = MODE_LIST
var sel: int = 0                 # chapter under the cursor on the list
var cleared: int = 0             # StoryProgress.cleared(), cached
var _lines: Array = []           # scene mode: the dialog being played
var _idx: int = 0
var _chars: float = 0.0
var _bg: String = "briefing_room"
var _then: Callable = Callable() # runs when the scene's last line is dismissed
# Staging: who stands in the left / right slot, the line each last spoke on (the staler one makes
# room for a newcomer), how far the newest arrival has slid in, and the scene's fade-in.
var _stage: Array[String] = ["", ""]
var _spoke: Array[int] = [-1, -1]
var _slide: float = 1.0
var _slide_slot: int = -1
var _scene_t: float = 0.0
# Title card shown before the first line: {"over": small line, "title": big line, "under": caption}.
var _card: Dictionary = {}
var _card_t: float = 0.0
var _anim_time: float = 0.0
var _confirm_reset: bool = false
## Progress when the chapter now running was picked from the list: a chapter below it is a replay.
## (A mission's win is saved by Battlefield before its debrief, so the debrief compares against this.)
var _cleared_at_start: int = 0
var _backdrops: Dictionary = {}  # backdrop name -> Texture2D (see _backdrop)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	cleared = StoryProgress.cleared()
	var ch: int = GlobalState.story_chapter
	_cleared_at_start = GlobalState.story_cleared_at_launch if GlobalState.story_stage == "post" else cleared
	if GlobalState.story_stage == "post" and not StoryCampaign.chapter(ch).is_empty():
		_play_debrief(ch)
	elif GlobalState.story_stage == "pre" and not StoryCampaign.chapter(ch).is_empty():
		start_chapter(ch)
	else:
		_show_list()

func _process(delta: float) -> void:
	_anim_time += delta
	if mode == MODE_SCENE:
		dirty = true
		if not _card.is_empty():
			_card_t += delta
			if _card_t >= CARD_TIME:
				_card = {}
		else:
			_scene_t += delta
			_slide = minf(1.0, _slide + delta / SLIDE_TIME)
			if _scene_t >= FADE_TIME * 0.5:   # the first line starts typing once the picture is up
				var before := int(_chars)
				_chars += delta * StoryDialog.TYPE_CPS
				StoryDialog.type_tick(before, int(_chars), _line_total())
	elif int(_anim_time / 0.5) != int((_anim_time - delta) / 0.5):
		dirty = true   # blinking prompts
	if dirty:
		dirty = false
		queue_redraw()

# ---------------------------------------------------------------- flow
func _show_list() -> void:
	mode = MODE_LIST
	GlobalState.story_chapter = -1
	GlobalState.story_stage = "list"
	sel = clampi(cleared, 0, StoryCampaign.chapters().size() - 1)
	_confirm_reset = false
	dirty = true

## Runs chapter `i` from its start: a scene plays through; a mission plays its briefing dialog and
## then shows the briefing page.
func start_chapter(i: int) -> void:
	var ch := StoryCampaign.chapter(i)
	if ch.is_empty():
		_show_list()
		return
	GlobalState.story_chapter = i
	GlobalState.story_stage = "pre"
	var card := {"over": ch["act"], "title": ch["title"], "under": ch["synopsis"]}
	if ch["kind"] == "scene":
		_play(ch["lines"], str(ch.get("bg", "briefing_room")), func(): _complete(i), card)
	else:
		_play(ch["pre"], str(ch.get("bg", "briefing_room")), func():
			mode = MODE_BRIEFING
			dirty = true
		, card)

func _play_debrief(i: int) -> void:
	var ch := StoryCampaign.chapter(i)
	_play(ch.get("post", []), str(ch.get("post_bg", "field_camp")), func(): _complete(i),
		{"over": ch["act"], "title": ch["title"], "under": "AFTER THE BATTLE"})

## Chapter `i` is done: record it and roll straight into the next one (the list after the last).
func _complete(i: int) -> void:
	var replay: bool = i < _cleared_at_start
	StoryProgress.mark_cleared(i)
	cleared = StoryProgress.cleared()
	if not replay and i + 1 < StoryCampaign.chapters().size():
		_cleared_at_start = cleared
		start_chapter(i + 1)
	else:
		# A replayed chapter (or the last one) ends back on the campaign list
		_show_list()
		sel = i

func _play(lines: Array, bg: String, then: Callable, card: Dictionary = {}) -> void:
	if lines.is_empty():
		then.call()
		return
	mode = MODE_SCENE
	_lines = lines
	_idx = 0
	_chars = 0.0
	_bg = bg
	_then = then
	_card = card
	_card_t = 0.0
	_scene_t = 0.0
	_stage = ["", ""]
	_spoke = [-1, -1]
	_slide_slot = -1
	_enter_line()
	dirty = true

## Puts the speaker of the current line on stage. Someone already there just takes the light; a
## newcomer takes their side's slot (Coalition left, Syndikat right) when it is free, else the other
## when that is free, else the slot of whoever has been silent longest.
func _enter_line() -> void:
	var who: String = str(_lines[_idx].get("who", ""))
	if who == "":
		return
	var slot := _stage.find(who)
	if slot < 0:
		var pref: int = 1 if StoryCast.side(who) == StoryCast.SYNDIKAT else 0
		if _stage[pref] == "":
			slot = pref
		elif _stage[1 - pref] == "":
			slot = 1 - pref
		else:
			slot = 0 if _spoke[0] <= _spoke[1] else 1
		_stage[slot] = who
		_slide = 0.0
		_slide_slot = slot
	_spoke[slot] = _idx

## Finishes typing the current line, or moves to the next; `skip_all` ends the scene. A title card
## still on screen is dismissed first.
func advance(skip_all: bool = false) -> void:
	if mode != MODE_SCENE:
		return
	if not _card.is_empty():
		_card = {}   # Esc on a title card only dismisses the card
		dirty = true
		return
	var total := _line_total()
	if not skip_all and int(_chars) < total:
		_chars = float(total)
		dirty = true
		return
	SoundManager.play("ui_click")
	_idx += 1
	_chars = 0.0
	dirty = true
	if skip_all or _idx >= _lines.size():
		var then := _then
		_lines = []
		_then = Callable()
		then.call()
	else:
		_enter_line()

## Width the cutscene box wraps a line's text at (shared by the typewriter count and the draw).
func _line_wrap_px() -> float:
	return _virtual().x - 12 - 28

## Characters the typewriter has to reveal for the line on screen.
func _line_total() -> int:
	var n := 0
	for l in CrtUI.wrap_lines(str(_lines[_idx].get("text", "")), _line_wrap_px()):
		n += l.length()
	return n

func _launch() -> void:
	SoundManager.play("ui_confirm")
	GlobalState.story_cleared_at_launch = _cleared_at_start
	get_tree().change_scene_to_file(GlobalState.BATTLEFIELD_SCENE)

func _virtual() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	return CrtUI.virtual_size(vp, CrtUI.pixel_scale(vp))

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var id := _key_action(event.keycode)
	if id != "":
		get_viewport().set_input_as_handled()   # before _activate: launching leaves the tree
		_activate(id)

func _key_action(keycode: int) -> String:
	match mode:
		MODE_SCENE:
			match keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					return "next"
				KEY_ESCAPE:
					return "skip"
		MODE_BRIEFING:
			match keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					return "launch"
				KEY_ESCAPE, KEY_BACKSPACE:
					return "list"
		MODE_LIST:
			match keycode:
				KEY_UP:
					return "chapter:%d" % (sel - 1)
				KEY_DOWN:
					return "chapter:%d" % (sel + 1)
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					return "play"
				KEY_N:
					return "reset"
				KEY_ESCAPE, KEY_BACKSPACE:
					return "menu"
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		track_pointer(event)
		return
	if mode == MODE_SCENE:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			advance()
			accept_event()
		return
	var id := clicked_id(event)
	if id != "":
		accept_event()
		_activate(id)

func _activate(id: String) -> void:
	dirty = true
	if id != "reset":
		_confirm_reset = false
	if id == "next":
		advance()
	elif id == "skip":
		advance(true)
	elif id == "launch":
		_launch()
	elif id == "list":
		SoundManager.play("ui_cancel")
		_show_list()
	elif id.begins_with("chapter:"):
		var i := clampi(int(id.substr(8)), 0, StoryCampaign.chapters().size() - 1)
		if i != sel:
			SoundManager.play("ui_click")
			sel = i
	elif id == "play":
		if sel <= cleared:
			SoundManager.play("ui_confirm")
			_cleared_at_start = cleared
			start_chapter(sel)
		else:
			SoundManager.play("ui_cancel")
	elif id == "reset":
		if _confirm_reset:
			SoundManager.play("ui_confirm")
			StoryProgress.reset()
			cleared = 0
			_show_list()
		else:
			SoundManager.play("ui_click")
			_confirm_reset = true
	elif id == "menu":
		SoundManager.play("ui_cancel")
		GlobalState.leave_story()
		get_tree().change_scene_to_file(GlobalState.MAIN_MENU_SCENE)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), CrtUI.C_SCREEN)
	px_scale = CrtUI.pixel_scale(vp)
	var v := CrtUI.virtual_size(vp, px_scale)
	CrtUI.begin(self, px_scale)
	hot.clear()
	match mode:
		MODE_LIST:
			_draw_list(v)
		MODE_SCENE:
			_draw_scene(v)
		MODE_BRIEFING:
			_draw_briefing(v)

func _header(v: Vector2, title: String, sub: String) -> void:
	CrtUI.panel(self, Rect2(6, 6, v.x - 12, 30))
	CrtUI.text(self, title, Vector2(16, 12), CrtUI.C_NAME)
	CrtUI.text(self, sub, Vector2(16, 23), CrtUI.C_LABEL_DIM)

func _link(id: String, label: String, right_x: float, y: float) -> void:
	var w := PixelFont.text_width(CrtUI.sanitize(label))
	CrtUI.text_right(self, label, right_x, y, CrtUI.C_CURSOR if hot.hovered == id else CrtUI.C_NUM)
	hot.add(id, Rect2(right_x - w - 6, y - 3, w + 12, 13))

func _status(i: int) -> String:
	if i < cleared:
		return "CLEARED"
	return "NEXT" if i == cleared else "LOCKED"

func _draw_list(v: Vector2) -> void:
	var chapters := StoryCampaign.chapters()
	var done: bool = cleared >= chapters.size()
	_header(v, "STORY MODE // IRON GHOST", "CAMPAIGN COMPLETE" if done else "CHAPTER %d OF %d" % [cleared + 1, chapters.size()])
	_link("menu", "[ESC] COMMAND HQ", v.x - 16, 12)

	var lst := Rect2(6, 40, LIST_W, v.y - 46)
	CrtUI.panel(self, lst)
	var x := lst.position.x + 8
	var y := lst.position.y + 8
	var act := ""
	for i in chapters.size():
		var ch: Dictionary = chapters[i]
		if ch["act"] != act:
			act = ch["act"]
			if i > 0:
				y += 4
			CrtUI.text(self, act, Vector2(x, y), CrtUI.C_LABEL)
			y += ROW
		var id := "chapter:%d" % i
		var locked: bool = i > cleared
		var col: Color = CrtUI.C_DIM if locked else (CrtUI.C_NAME if i == sel else CrtUI.C_NUM)
		if hot.hovered == id and not locked:
			col = CrtUI.C_CURSOR
		CrtUI.text(self, CrtUI.fit(ch["title"], lst.size.x - 80), Vector2(x + 12, y), col)
		CrtUI.text_right(self, _status(i), lst.end.x - 8, y, CrtUI.C_LABEL_DIM if i < cleared else (CrtUI.C_CURSOR if i == cleared else CrtUI.C_DIM))
		if i == sel:
			CrtUI.cursor(self, Vector2(x + 2, y))
		hot.add(id, Rect2(lst.position.x + 2, y - 2, lst.size.x - 4, ROW))
		y += ROW

	var det := Rect2(lst.end.x + 4, 40, v.x - 16 - LIST_W, v.y - 46)
	CrtUI.panel(self, det)
	var ch: Dictionary = chapters[sel]
	var dx := det.position.x + 10
	var dw := det.size.x - 20
	var dy := det.position.y + 10
	CrtUI.text(self, ch["act"], Vector2(dx, dy), CrtUI.C_LABEL)
	CrtUI.text_right(self, _status(sel), det.end.x - 10, dy, CrtUI.C_CURSOR)
	dy += 14
	CrtUI.text(self, ch["title"], Vector2(dx, dy), CrtUI.C_NAME)
	dy += 14
	var locked: bool = sel > cleared
	dy = CrtUI.paragraph(self, "Clear the chapters before this one to unlock it." if locked else ch["synopsis"], Vector2(dx, dy), dw, CrtUI.C_NUM) + 8
	if not locked and ch["kind"] == "mission":
		var map: MapDefinition = ch["map"]
		CrtUI.text(self, map.subtitle, Vector2(dx, dy), CrtUI.C_LABEL_DIM)
		dy += 12
		CrtUI.text(self, "%s // TURN LIMIT %d" % [map.get_strategy_name(), map.turn_limit], Vector2(dx, dy), CrtUI.C_LABEL)
		dy += 16
		var recon := Rect2(dx, dy, map.width * MainMenu.RECON_CELL.x + 12, map.height * MainMenu.RECON_CELL.y + 24)
		MainMenu.draw_recon(self, recon, map)
		_draw_roster(Vector2(recon.end.x + 12, dy), map)
	elif not locked:
		CrtUI.text(self, "CUTSCENE", Vector2(dx, dy), CrtUI.C_LABEL_DIM)

	var play := Rect2(dx, det.end.y - 36, 230, 26)
	CrtUI.panel(self, play, CrtUI.C_RULE if locked else CrtUI.C_BORDER)
	if not locked and (int(_anim_time / 0.5) % 2 == 0 or hot.hovered == "play"):
		CrtUI.cursor(self, play.position + Vector2(8, 9))
	var label: String = "LOCKED" if locked else ("REPLAY CHAPTER [ENTER]" if sel < cleared else ("BEGIN THE STORY [ENTER]" if sel == 0 else "CONTINUE THE STORY [ENTER]"))
	CrtUI.text(self, label, play.position + Vector2(20, 9), CrtUI.C_DIM if locked else (CrtUI.C_CURSOR if hot.hovered == "play" else CrtUI.C_NAME))
	if not locked:
		hot.add("play", play)
	_link("reset", "PRESS N AGAIN TO ERASE PROGRESS" if _confirm_reset else "[N] NEW CAMPAIGN", det.end.x - 10, det.end.y - 20)

## Named pilots of a mission's Coalition line-up, with their portraits.
func _draw_roster(pos: Vector2, map: MapDefinition) -> void:
	CrtUI.text(self, "LINE-UP", pos, CrtUI.C_LABEL)
	var y := pos.y + 12
	for sp in map.spawns:
		if int(sp.get("faction", 0)) != 0:
			continue
		var pilot: String = str(sp.get("pilot", ""))
		var chassis: MechData = GlobalState.boss_catalog.get(sp["chassis"], GlobalState.chassis_catalog.get(sp["chassis"]))
		CrtUI.text(self, StoryCast.roster_name(pilot) if pilot != "" else str(sp["callsign"]).split(" ")[0], Vector2(pos.x, y), CrtUI.C_NAME if pilot != "" else CrtUI.C_NUM)
		y += 10
		CrtUI.text(self, chassis.unit_name if chassis != null else str(sp["chassis"]), Vector2(pos.x + 8, y), CrtUI.C_LABEL_DIM)
		y += 13

const CARD_TIME := 2.6      # seconds a title card stays up unless dismissed
const FADE_TIME := 0.45     # fade from black into a scene
const SLIDE_TIME := 0.18    # a newcomer's slide onto the stage
const STAGE_H := 284        # stage height in virtual px: a 354x142 backdrop at 2x
const BUST_SCALE := 3
## Battle backdrop that stands in for a cutscene backdrop whose art is missing.
const BACKDROP_FALLBACK := {
	"village_fire": "city", "memorial": "plain", "field_camp": "plain", "records_room": "city",
	"snow_pass": "mountain", "causeway": "river", "capital_street": "city", "throne_gate": "mountain",
	"parade_court": "city",
}

func _draw_scene(v: Vector2) -> void:
	var ch := StoryCampaign.chapter(GlobalState.story_chapter)
	if not _card.is_empty():
		_draw_card(v)
		return
	_header(v, "%s // %s" % [ch.get("act", "STORY MODE"), ch.get("title", "")], "")
	CrtUI.text_right(self, "%d / %d" % [mini(_idx + 1, _lines.size()), _lines.size()], v.x - 16, 17, CrtUI.C_LABEL_DIM)
	var stage := Rect2(6, 40, v.x - 12, minf(STAGE_H, v.y - 46 - 100))
	_draw_backdrop(stage, _bg)
	if _idx >= _lines.size():
		return
	var line: Dictionary = _lines[_idx]
	var who: String = str(line.get("who", ""))
	for slot in 2:
		_draw_bust(stage, slot, _stage[slot], _stage[slot] == who and who != "")
	CrtUI.frame_outline(self, stage, CrtUI.C_BORDER)
	_draw_line_box(Rect2(6, stage.end.y + 4, v.x - 12, v.y - stage.end.y - 10), line)
	var fade := 1.0 - clampf(_scene_t / FADE_TIME, 0.0, 1.0)
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, v), Color(CrtUI.C_SCREEN, fade))

## The chapter's title card: act, title in double-size type, caption.
func _draw_card(v: Vector2) -> void:
	var a := clampf(_card_t / 0.35, 0.0, 1.0) * clampf((CARD_TIME - _card_t) / 0.35, 0.0, 1.0)
	var cy := roundf(v.y / 2.0)
	CrtUI.text_centered(self, str(_card.get("over", "")), v.x / 2.0, cy - 40, Color(CrtUI.C_LABEL, a))
	var title := CrtUI.sanitize(str(_card.get("title", "")))
	var tw := PixelFont.text_width(title)
	draw_set_transform(Vector2(roundf(v.x / 2.0 - tw) * px_scale, (cy - 22) * px_scale), 0.0, Vector2(px_scale * 2, px_scale * 2))
	PixelFont.draw_text(self, title, Vector2.ZERO, Color(CrtUI.C_NAME, a))
	CrtUI.begin(self, px_scale)
	draw_rect(Rect2(roundf(v.x / 2.0 - 120), cy + 2, 240, 1), Color(CrtUI.C_RULE, a))
	CrtUI.text_centered(self, str(_card.get("under", "")), v.x / 2.0, cy + 12, Color(CrtUI.C_NUM, a))

## One speaker's portrait standing in a stage slot (0 = left, 1 = right): lit and raised while
## they speak, dimmed while they listen. The right-hand one is mirrored to face the other.
func _draw_bust(stage: Rect2, slot: int, who: String, speaking: bool) -> void:
	if who == "":
		return
	var tex := StoryCast.portrait(who)
	var size := float(StoryCast.PORTRAIT_SIZE * BUST_SCALE)
	var slide := (1.0 - _slide) * 28.0 if slot == _slide_slot else 0.0
	var x := stage.position.x + 16 - slide if slot == 0 else stage.end.x - 16 - size + slide
	var y := stage.end.y - size - (10 if speaking else 4)
	var r := Rect2(roundf(x), roundf(y), size, size)
	var hostile: bool = StoryCast.side(who) == StoryCast.SYNDIKAT
	var accent: Color = CrtUI.C_HOSTILE if hostile else CrtUI.C_BORDER
	draw_rect(r.grow(2), Color(0.02, 0.03, 0.02, 0.85))
	if tex != null:
		var tint := Color.WHITE if speaking else Color(0.38, 0.40, 0.38)
		if slot == 1:
			draw_set_transform_matrix(Transform2D(Vector2(-px_scale, 0), Vector2(0, px_scale), Vector2(r.end.x, r.position.y) * px_scale))
			draw_texture_rect(tex, Rect2(Vector2.ZERO, r.size), false, tint)
			CrtUI.begin(self, px_scale)
		else:
			draw_texture_rect(tex, r, false, tint)
	else:
		draw_rect(r, CrtUI.C_FILL)
		CrtUI.text_centered(self, "NO SIGNAL", r.get_center().x, r.get_center().y - 4, CrtUI.C_DIM)
	CrtUI.frame_outline(self, r.grow(1), accent if speaking else CrtUI.C_RULE)

## The dialog box under the stage: the speaker's name on their side of the box, the typed text.
func _draw_line_box(r: Rect2, line: Dictionary) -> void:
	var who: String = str(line.get("who", ""))
	var hostile: bool = StoryCast.side(who) == StoryCast.SYNDIKAT
	CrtUI.panel(self, r, CrtUI.C_HOSTILE if hostile else CrtUI.C_BORDER)
	var x := r.position.x + 14
	var w := r.size.x - 28
	var y := r.position.y + 10
	if who != "":
		var name := str(line.get("as", StoryCast.display_name(who)))
		var name_col: Color = CrtUI.C_HOSTILE if hostile else CrtUI.C_NAME
		if _stage.find(who) == 1:
			CrtUI.text_right(self, name, r.end.x - 14, y, name_col)
		else:
			CrtUI.text(self, name, Vector2(x, y), name_col)
		CrtUI.hrule(self, x, y + 11, w)
		y += 18
	else:
		y += 6
	var left := int(_chars)
	var total := 0
	for l in CrtUI.wrap_lines(str(line.get("text", "")), _line_wrap_px()):
		total += l.length()
		if left > 0:
			if who == "":
				CrtUI.text_centered(self, l.substr(0, left), r.get_center().x, y, CrtUI.C_LABEL)
			else:
				CrtUI.text(self, l.substr(0, left), Vector2(x, y), CrtUI.C_NUM)
		left -= l.length()
		y += CrtUI.LINE + 2
	CrtUI.text_right(self, "SPACE: NEXT  ESC: SKIP", r.end.x - 24, r.end.y - 12, CrtUI.C_LABEL_DIM)
	if int(_chars) >= total and int(_anim_time / 0.3) % 2 == 0:
		CrtUI.cursor(self, Vector2(r.end.x - 18, r.end.y - 12))

## A cutscene backdrop by id (assets/story/backdrops, else its battle backdrop stand-in), kept
## alive here: a texture loaded inside _draw and dropped again would be freed before the frame is
## rendered. null when there is no picture for the id.
func _backdrop(id: String) -> Texture2D:
	if not _backdrops.has(id):
		var tex: Texture2D = null
		for path: String in ["res://assets/story/backdrops/%s.png" % id,
				"res://assets/battle/backdrops/%s.png" % BACKDROP_FALLBACK.get(id, id)]:
			if ResourceLoader.exists(path):
				tex = load(path) as Texture2D
				break
		_backdrops[id] = tex
	return _backdrops[id]

## The picture behind a cutscene, covering the stage at its own aspect (anchored to its bottom edge).
func _draw_backdrop(stage: Rect2, bg: String) -> void:
	var tex := _backdrop(bg)
	if tex == null:
		CrtUI.panel(self, stage)
		return
	var scale := maxf(stage.size.x / tex.get_width(), stage.size.y / tex.get_height())
	var src_size := stage.size / scale
	draw_texture_rect_region(tex, stage, Rect2((tex.get_width() - src_size.x) / 2.0, tex.get_height() - src_size.y, src_size.x, src_size.y))

func _draw_briefing(v: Vector2) -> void:
	var ch := StoryCampaign.chapter(GlobalState.story_chapter)
	var map: MapDefinition = ch["map"]
	_header(v, "%s // MISSION BRIEFING" % ch["act"], map.subtitle)
	_link("list", "[ESC] CAMPAIGN", v.x - 16, 12)
	var p := Rect2(6, 40, v.x - 12, v.y - 46)
	CrtUI.panel(self, p)
	var x := p.position.x + 10
	var recon := Rect2(p.end.x - 10 - (map.width * MainMenu.RECON_CELL.x + 12), 48, map.width * MainMenu.RECON_CELL.x + 12, map.height * MainMenu.RECON_CELL.y + 24)
	MainMenu.draw_recon(self, recon, map)
	_draw_roster(Vector2(recon.position.x, recon.end.y + 10), map)
	var w := recon.position.x - 14 - x
	var y := 50.0
	CrtUI.text(self, map.map_name, Vector2(x, y), CrtUI.C_NAME)
	y += 14
	CrtUI.text(self, map.get_strategy_name(), Vector2(x, y), CrtUI.C_LABEL)
	CrtUI.text_right(self, "TURN LIMIT %d" % map.turn_limit, x + w, y, CrtUI.C_NUM)
	y += 16
	var launch := Rect2(x, p.end.y - 36, 230, 26)
	var max_y := launch.position.y - 6
	y = CrtUI.paragraph(self, map.briefing_text, Vector2(x, y), w, CrtUI.C_NUM, max_y) + 8
	y = CrtUI.paragraph(self, "VICTORY: " + map.get_victory_condition_text(), Vector2(x, y), w, CrtUI.C_NAME, max_y) + 8
	CrtUI.paragraph(self, map.tactical_tip, Vector2(x, y), w, CrtUI.C_LABEL, max_y)
	CrtUI.panel(self, launch)
	if int(_anim_time / 0.5) % 2 == 0 or hot.hovered == "launch":
		CrtUI.cursor(self, launch.position + Vector2(8, 9))
	CrtUI.text(self, "LAUNCH OPERATION [ENTER]", launch.position + Vector2(20, 9), CrtUI.C_CURSOR if hot.hovered == "launch" else CrtUI.C_NAME)
	hot.add("launch", launch)
