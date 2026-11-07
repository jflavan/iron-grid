class_name PixelFont
extends RefCounted

## 5x7 bitmap font (6x8 cells) generated into assets/battle/font. Uppercase only; lowercase
## maps to uppercase, unknown characters draw as '?'. Advance is 6 native px per character.

const FONT_PNG := "res://assets/battle/font/font5x7.png"
const FONT_JSON := "res://assets/battle/font/font5x7.json"
const ADVANCE := 6
const HEIGHT := 8

static var _tex: Texture2D = null
static var _attempted: bool = false
static var _index: Dictionary = {}
static var _ascii_table: PackedInt32Array = PackedInt32Array()

## Loads the glyph atlas and index now instead of on the first text draw.
static func warm() -> void:
	_ensure()

static func _ensure() -> void:
	if _attempted:
		return
	_attempted = true
	_tex = load(FONT_PNG) as Texture2D
	var meta = JSON.parse_string(FileAccess.get_file_as_string(FONT_JSON))
	var chars: String = ""
	if meta is Dictionary and meta.has("chars"):
		chars = String(meta["chars"])
	else:
		push_error("PixelFont: could not read the glyph index from %s; text will draw as '?'" % FONT_JSON)
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

static var _mesh_atlas: ImageTexture = null

## The font atlas laid out for baking text into a textured mesh (CanvasMeshBuilder): rows 0-7 are
## the glyphs, row 8 repeats row 7 (so filtering at the glyphs' bottom edge matches the clamped
## original), row 9 is a transparent gap and rows 10-13 are solid white, which untextured geometry
## samples. One texture keeps solid geometry and labels in a single draw call.
static func mesh_atlas() -> Texture2D:
	_ensure()
	if _mesh_atlas == null and _tex != null:
		var src := _tex.get_image()
		if src.is_compressed():
			src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		var w: int = src.get_width()
		var img := Image.create(w, HEIGHT + 6, false, Image.FORMAT_RGBA8)
		img.blit_rect(src, Rect2i(0, 0, w, HEIGHT), Vector2i.ZERO)
		img.blit_rect(src, Rect2i(0, HEIGHT - 1, w, 1), Vector2i(0, HEIGHT))
		img.fill_rect(Rect2i(0, HEIGHT + 2, w, 4), Color.WHITE)
		_mesh_atlas = ImageTexture.create_from_image(img)
	return _mesh_atlas

## UV inside mesh_atlas()'s white band: the corner of four white texels, so it samples pure white
## under nearest or linear filtering.
static func mesh_white_uv() -> Vector2:
	return Vector2(0.5, float(HEIGHT + 4) / float(HEIGHT + 6))

## Glyph quads of `text` for mesh_atlas(): [dest Rect2 relative to the text origin, UV Rect2],
## laid out exactly like draw_text (one 6x8 cell per character, spaces skipped).
static func mesh_glyphs(text: String) -> Array:
	var atlas := mesh_atlas()
	var out: Array = []
	if atlas == null:
		return out
	var inv := Vector2(1.0 / float(atlas.get_width()), 1.0 / float(atlas.get_height()))
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code == 32:
			continue
		var gi: int = _ascii_table[code] if code < 256 else _index.get(text[i].to_upper(), 0)
		out.append([Rect2(Vector2(i * ADVANCE, 0), Vector2(ADVANCE, HEIGHT)),
			Rect2(Vector2(gi * ADVANCE, 0) * inv, Vector2(ADVANCE, HEIGHT) * inv)])
	return out

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
