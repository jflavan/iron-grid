class_name PixelFont
extends RefCounted

## 5x7 bitmap font (6x8 cells) generated into assets/battle/font. Uppercase only; lowercase
## maps to uppercase, unknown characters draw as '?'. Advance is 6 native px per character.

const FONT_PNG := "res://assets/battle/font/font5x7.png"
const FONT_JSON := "res://assets/battle/font/font5x7.json"
const ADVANCE := 6
const HEIGHT := 8

static var _tex: Texture2D = null
static var _index: Dictionary = {}
static var _ascii_table: PackedInt32Array = PackedInt32Array()

static func _ensure() -> void:
	if _tex != null:
		return
	_tex = load(FONT_PNG) as Texture2D
	var meta = JSON.parse_string(FileAccess.get_file_as_string(FONT_JSON))
	var chars: String = meta["chars"] if meta != null else ""
	for i in chars.length():
		_index[chars[i]] = i

	var q_idx: int = _index.get("?", 0)
	_ascii_table.resize(256)
	_ascii_table.fill(q_idx)
	_ascii_table[32] = -1

	for i in chars.length():
		var code: int = chars.unicode_at(i)
		if code < 256:
			_ascii_table[code] = i
			if code >= 65 and code <= 90:
				_ascii_table[code + 32] = i

static func _glyph_index(ch: String) -> int:
	_ensure()
	if ch.is_empty():
		return 0
	var code: int = ch.unicode_at(0)
	if code < 256:
		return _ascii_table[code]
	var up := ch.to_upper()
	return _index.get(up, _index.get("?", 0))

static func has_glyph(ch: String) -> bool:
	_ensure()
	return _index.has(ch.to_upper())

static func text_width(text: String) -> int:
	return text.length() * ADVANCE

static func draw_text(ci: CanvasItem, text: String, pos: Vector2, color: Color) -> void:
	_ensure()
	if _tex == null:
		return
	var text_len: int = text.length()
	for i in range(text_len):
		var code: int = text.unicode_at(i)
		if code == 32:
			continue
		var gi: int = _ascii_table[code] if code < 256 else _index.get(text[i].to_upper(), 0)
		ci.draw_texture_rect_region(_tex, Rect2(pos + Vector2(i * ADVANCE, 0), Vector2(ADVANCE, HEIGHT)),
			Rect2(Vector2(gi * ADVANCE, 0), Vector2(ADVANCE, HEIGHT)), color)

static func draw_centered(ci: CanvasItem, text: String, center_x: float, y: float, color: Color) -> void:
	draw_text(ci, text, Vector2(roundf(center_x - text_width(text) / 2.0), y), color)

## Greedy word wrap; words longer than a line are hard-split.
static func wrap(text: String, max_px: int) -> PackedStringArray:
	var max_chars: int = maxi(1, max_px / ADVANCE)
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		while word.length() > max_chars:
			if line != "":
				lines.append(line)
				line = ""
			lines.append(word.substr(0, max_chars))
			word = word.substr(max_chars)
		if line == "":
			line = word
		elif line.length() + 1 + word.length() <= max_chars:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if line != "":
		lines.append(line)
	return lines
