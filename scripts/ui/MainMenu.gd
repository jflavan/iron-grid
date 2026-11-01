class_name MainMenu
extends Control

## Command HQ: theater select with briefing and recon map, plus the Hangar Codex (6 chassis).
## Drawn in the battle screen's CRT menu style (CrtUI) at an integer pixel scale.
## Controls: Up/Down or 1-3 pick a theater, Left/Right pick a chassis, Enter/Space launch.
## Every menu row is also clickable.

const HANGAR_W := 300       # right column width (virtual px); fits two of the largest sprites side by side
const RECON_CELL := Vector2i(14, 10)

var selected_map_idx: int = 0
var selected_chassis_idx: int = 0
var _chassis_keys: Array[String] = ["vanguard", "goliath", "falke", "donner", "kommandant", "moloch"]
var _anim_time: float = 0.0
var _scale: int = 2
var _hot := CrtHotspots.new()
var _stat_max := {"hull": 1, "en": 1, "armor": 1, "fire": 1, "spd": 1, "fuel": 1}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	selected_map_idx = GlobalState.selected_map_index
	for key in _chassis_keys:
		var m: MechData = GlobalState.chassis_catalog[key]
		_stat_max["hull"] = maxi(_stat_max["hull"], m.max_armor)
		_stat_max["en"] = maxi(_stat_max["en"], m.max_energy)
		_stat_max["armor"] = maxi(_stat_max["armor"], m.armor_rating)
		_stat_max["fire"] = maxi(_stat_max["fire"], m.firepower)
		_stat_max["spd"] = maxi(_stat_max["spd"], m.speed)
		_stat_max["fuel"] = maxi(_stat_max["fuel"], m.max_fuel)

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_on_launch_pressed()
		KEY_1, KEY_2, KEY_3:
			_select_map(event.keycode - KEY_1)
		KEY_UP:
			_select_map(selected_map_idx - 1)
		KEY_DOWN:
			_select_map(selected_map_idx + 1)
		KEY_LEFT:
			_select_chassis(selected_chassis_idx - 1)
		KEY_RIGHT:
			_select_chassis(selected_chassis_idx + 1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hot.hovered = _hot.hit(CrtUI.to_virtual(event.position, _scale))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hot.hovered != "" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _hot.hit(CrtUI.to_virtual(event.position, _scale))
		if id != "":
			_activate(id)
			accept_event()

func _activate(id: String) -> void:
	if id.begins_with("map:"):
		_select_map(int(id.substr(4)))
	elif id.begins_with("chassis:"):
		_select_chassis(int(id.substr(8)))
	elif id == "launch":
		_on_launch_pressed()
	elif id == "exit":
		SoundManager.play("ui_cancel")
		get_tree().quit()

func _select_map(i: int) -> void:
	if i < 0 or i >= GlobalState.maps.size() or i == selected_map_idx:
		return
	SoundManager.play("ui_click")
	selected_map_idx = i
	GlobalState.selected_map_index = i

func _select_chassis(i: int) -> void:
	i = posmod(i, _chassis_keys.size())
	if i == selected_chassis_idx:
		return
	SoundManager.play("ui_click")
	selected_chassis_idx = i

func _on_launch_pressed() -> void:
	SoundManager.play("ui_confirm")
	GlobalState.selected_map_index = selected_map_idx
	get_tree().change_scene_to_file("res://scenes/Battlefield.tscn")

# ---------------------------------------------------------------- drawing
func _row_color(id: String, selected: bool) -> Color:
	if _hot.hovered == id:
		return CrtUI.C_CURSOR
	return CrtUI.C_NAME if selected else CrtUI.C_NUM

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), CrtUI.C_SCREEN)
	_scale = CrtUI.pixel_scale(vp)
	var v := CrtUI.virtual_size(vp, _scale)
	CrtUI.begin(self, _scale)
	_hot.clear()

	# Header
	CrtUI.panel(self, Rect2(6, 6, v.x - 12, 30))
	CrtUI.text(self, "OPERATION: IRON GRID", Vector2(16, 12), CrtUI.C_NAME)
	CrtUI.text(self, "DIESELPUNK ISOMETRIC TACTICAL WARFARE // TURN-BASED RPG COMBAT ENGINE", Vector2(16, 23), CrtUI.C_LABEL_DIM)
	var exit_r := Rect2(v.x - 66, 9, 54, 12)
	CrtUI.text_right(self, "EXIT", v.x - 16, 12, _row_color("exit", false))
	if _hot.hovered == "exit":
		CrtUI.cursor(self, Vector2(v.x - 16 - PixelFont.text_width("EXIT") - 10, 12))
	_hot.add("exit", exit_r)

	_draw_theaters(Rect2(6, 40, v.x - 16 - HANGAR_W, v.y - 46))
	_draw_hangar(Rect2(v.x - 6 - HANGAR_W, 40, HANGAR_W, v.y - 46))

func _draw_theaters(p: Rect2) -> void:
	CrtUI.panel(self, p)
	var x := p.position.x + 8
	var right := p.end.x - 8
	CrtUI.text(self, "SELECT THEATER", Vector2(x, 48), CrtUI.C_LABEL)
	for i in GlobalState.maps.size():
		var m: MapDefinition = GlobalState.maps[i]
		var y := 64 + i * 14
		var id := "map:%d" % i
		CrtUI.text(self, "%d. %s" % [i + 1, m.map_name], Vector2(x + 12, y), _row_color(id, i == selected_map_idx))
		if i == selected_map_idx:
			CrtUI.cursor(self, Vector2(x + 2, y))
		_hot.add(id, Rect2(x, y - 3, 200, 14))

	var map_def: MapDefinition = GlobalState.maps[selected_map_idx]
	var recon := Rect2(right - (map_def.width * RECON_CELL.x + 12), 46, map_def.width * RECON_CELL.x + 12, map_def.height * RECON_CELL.y + 24)
	_draw_recon(recon, map_def)

	var y := maxf(64 + GlobalState.maps.size() * 14, recon.end.y) + 6
	CrtUI.hrule(self, x, y, p.size.x - 16)
	y += 8
	var w := p.size.x - 16
	var launch := Rect2(x, p.end.y - 34, 220, 26)
	var max_y := launch.position.y - 6
	CrtUI.text(self, map_def.map_name, Vector2(x, y), CrtUI.C_NAME)
	y += 12
	CrtUI.text(self, map_def.subtitle, Vector2(x, y), CrtUI.C_LABEL_DIM)
	y += 14
	CrtUI.text(self, map_def.get_strategy_name(), Vector2(x, y), CrtUI.C_LABEL)
	CrtUI.text_right(self, "TURN LIMIT %d" % map_def.turn_limit, right, y, CrtUI.C_NUM)
	y += 16
	y = CrtUI.paragraph(self, map_def.briefing_text, Vector2(x, y), w, CrtUI.C_NUM, max_y) + 6
	y = CrtUI.paragraph(self, "VICTORY: " + map_def.get_victory_condition_text(), Vector2(x, y), w, CrtUI.C_NAME, max_y) + 6
	CrtUI.paragraph(self, map_def.tactical_tip, Vector2(x, y), w, CrtUI.C_LABEL, max_y)

	CrtUI.panel(self, launch)
	var blink := int(_anim_time / 0.5) % 2 == 0 or _hot.hovered == "launch"
	if blink:
		CrtUI.cursor(self, launch.position + Vector2(8, 9))
	CrtUI.text(self, "LAUNCH OPERATION [ENTER]", launch.position + Vector2(20, 9), CrtUI.C_CURSOR if _hot.hovered == "launch" else CrtUI.C_NAME)
	_hot.add("launch", launch)

func _draw_recon(r: Rect2, map_def: MapDefinition) -> void:
	CrtUI.frame(self, r)
	CrtUI.text(self, "RECON %dX%d" % [map_def.width, map_def.height], r.position + Vector2(6, 5), CrtUI.C_LABEL)
	var ox := r.position.x + 6
	var oy := r.position.y + 18
	for y in map_def.height:
		var t_row := map_def.terrain_codes[y].split(" ", false)
		var e_row := map_def.elevation_rows[y].split(" ", false)
		for x in map_def.width:
			var code: String = t_row[x] if x < t_row.size() else "P"
			var elev: int = int(e_row[x]) if x < e_row.size() else 1
			var col := Color(0.30, 0.36, 0.24)
			match code:
				"R": col = Color(0.16, 0.36, 0.44)
				"D": col = Color(0.42, 0.40, 0.36)
				"F": col = Color(0.20, 0.28, 0.17)
				"C": col = Color(0.55, 0.50, 0.38)
				"M": col = Color(0.50, 0.48, 0.44)
			col = col.lightened(float(elev - 1) * 0.08)
			draw_rect(Rect2(ox + x * RECON_CELL.x, oy + y * RECON_CELL.y, RECON_CELL.x - 1, RECON_CELL.y - 1), col)
	for sp in map_def.spawns:
		var pos: Vector2i = sp["pos"]
		var c := Vector2(ox + pos.x * RECON_CELL.x + RECON_CELL.x / 2 - 2, oy + pos.y * RECON_CELL.y + RECON_CELL.y / 2 - 2)
		draw_rect(Rect2(c, Vector2(4, 4)), Color.BLACK)
		draw_rect(Rect2(c + Vector2(1, 1), Vector2(2, 2)), CrtUI.C_LABEL if int(sp["faction"]) == 0 else CrtUI.C_HOSTILE)

func _draw_hangar(p: Rect2) -> void:
	CrtUI.panel(self, p)
	var x := p.position.x + 8
	var w := p.size.x - 16
	var right := p.end.x - 8
	CrtUI.text(self, "HANGAR CODEX", Vector2(x, 48), CrtUI.C_LABEL)
	CrtUI.text_right(self, "%d CHASSIS" % _chassis_keys.size(), right, 48, CrtUI.C_LABEL_DIM)
	var col_w := w / 3.0
	for i in _chassis_keys.size():
		var ch: MechData = GlobalState.chassis_catalog[_chassis_keys[i]]
		var cx := roundf(x + (i % 3) * col_w)
		var cy := 62 + (i / 3) * CrtUI.ROW
		var id := "chassis:%d" % i
		CrtUI.text(self, CrtUI.fit(ch.callsign, col_w - 12), Vector2(cx + 10, cy), _row_color(id, i == selected_chassis_idx))
		if i == selected_chassis_idx:
			CrtUI.cursor(self, Vector2(cx, cy))
		_hot.add(id, Rect2(cx, cy - 2, col_w, CrtUI.ROW))

	var mech: MechData = GlobalState.chassis_catalog[_chassis_keys[selected_chassis_idx]]
	# Portrait: one cell per livery, each as large as the biggest sprite, so mechs never overlap.
	var cell := CrtUI.max_mech_cell(_chassis_keys)
	var port := Rect2(x, 90, w, cell.y + 8)
	CrtUI.frame(self, port)
	var gap := (w - cell.x * 2.0) / 3.0
	var t_ms := _anim_time * 1000.0
	CrtUI.mech(self, mech.chassis_id, MechData.Faction.PLAYER, Rect2(x + gap, port.position.y + 4, cell.x, cell.y), false, t_ms, _scale)
	CrtUI.mech(self, mech.chassis_id, MechData.Faction.AI, Rect2(x + gap * 2 + cell.x, port.position.y + 4, cell.x, cell.y), true, t_ms + 420.0, _scale)

	var y := port.end.y + 6
	CrtUI.text(self, CrtUI.fit("%s // %s" % [mech.unit_name, mech.chassis_class], w), Vector2(x, y), CrtUI.C_NAME)
	y += 12
	var half := w / 2.0
	_stat(Rect2(x, y, half - 6, 8), "HULL", mech.max_armor, _stat_max["hull"], CrtUI.C_HULL)
	_stat(Rect2(x + half + 6, y, half - 6, 8), "EN", mech.max_energy, _stat_max["en"], CrtUI.C_EN, "%d+%d" % [mech.max_energy, mech.passive_energy_regen])
	y += 10
	_stat(Rect2(x, y, half - 6, 8), "ATK", mech.firepower, _stat_max["fire"], CrtUI.C_FUEL)
	_stat(Rect2(x + half + 6, y, half - 6, 8), "DEF", mech.armor_rating, _stat_max["armor"], CrtUI.C_LABEL)
	y += 10
	_stat(Rect2(x, y, half - 6, 8), "SPD", mech.speed, _stat_max["spd"], CrtUI.C_CURSOR, "%d E%d%%" % [mech.speed, mech.evasion])
	_stat(Rect2(x + half + 6, y, half - 6, 8), "FUEL", mech.max_fuel, _stat_max["fuel"], CrtUI.C_FUEL, "%d+%d" % [mech.max_fuel, mech.passive_refuel])
	y += 12

	# TECH Systems pinned to the bottom; lore fills the space above it.
	var card_h := 34
	var deck_top := p.end.y - 8 - mech.abilities.size() * (card_h + 3) - 12
	CrtUI.paragraph(self, mech.lore_blurb, Vector2(x, y), w, CrtUI.C_NUM, deck_top - 4)
	CrtUI.text(self, "TECH SYSTEMS", Vector2(x, deck_top), CrtUI.C_LABEL)
	CrtUI.text_right(self, "COST  POWER/ACC", right, deck_top, CrtUI.C_LABEL_DIM)
	for i in mech.abilities.size():
		var ab: CombatAbility = mech.abilities[i]
		var cr := Rect2(x, deck_top + 12 + i * (card_h + 3), w, card_h)
		CrtUI.frame(self, cr)
		CrtUI.text(self, CrtUI.fit(ab.ability_name, w - 80), cr.position + Vector2(5, 4), CrtUI.C_NAME)
		CrtUI.text_right(self, ab.category, cr.end.x - 5, cr.position.y + 4, CrtUI.C_LABEL_DIM)
		CrtUI.text(self, CrtUI.fit(ab.description, w - 10), cr.position + Vector2(5, 14), CrtUI.C_NUM)
		CrtUI.text(self, "%d EN" % ab.energy_cost, cr.position + Vector2(5, 24), CrtUI.C_EN)
		var spec_txt := "X%.2f  ACC %d%%" % [ab.power_multiplier, ab.accuracy] if ab.category == "WEAPON" else "SUPPORT / BUFF"
		CrtUI.text_right(self, spec_txt, cr.end.x - 5, cr.position.y + 24, CrtUI.C_LABEL)

func _stat(r: Rect2, label: String, value: int, max_value: int, col: Color, value_text: String = "") -> void:
	CrtUI.text(self, label, r.position, CrtUI.C_LABEL)
	var vtxt := value_text if value_text != "" else str(value)
	CrtUI.gauge(self, Rect2(r.position.x + 30, r.position.y + 3, r.size.x - 30 - PixelFont.text_width(vtxt) - 6, 3), float(value) / float(max_value), col)
	CrtUI.text_right(self, vtxt, r.end.x, r.position.y, CrtUI.C_NUM)
