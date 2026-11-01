extends SceneTree
## Structural fight matrix: every chassis vs every chassis, full HP, no selection.
## Run: godot --headless --path . -s tests/matrix.gd
func _init() -> void:
	var gs = load("res://autoload/GlobalState.gd").new()
	gs._ready()
	var ids := ["vanguard","goliath","falke","donner","kommandant","moloch"]
	var terrains := {"PLN/PLN": [GridTileData.TerrainType.PLAIN, GridTileData.TerrainType.PLAIN], "PLN->CTY": [GridTileData.TerrainType.PLAIN, GridTileData.TerrainType.CITY], "PLN->MTN": [GridTileData.TerrainType.PLAIN, GridTileData.TerrainType.MOUNTAIN]}
	for tname in terrains:
		var t = terrains[tname]
		for ent in [false, true]:
			var n := 0; var aw := 0; var dd := 0; var da := 0; var dk := 0; var ak := 0; var ac := 0; var dc := 0
			for a in ids:
				for d in ids:
					var am: MechData = gs.create_mech_instance(a, MechData.Faction.AI, "A", Vector2i.ZERO, "1")
					var dm: MechData = gs.create_mech_instance(d, MechData.Faction.PLAYER, "D", Vector2i.ZERO, "2")
					dm.is_entrenched = ent
					var r := SkirmishEngine.resolve_skirmish(am, dm, GridTileData.new(Vector2i.ZERO, t[0], 0), GridTileData.new(Vector2i.ONE, t[1], 0), false)
					n += 1; aw += int(r.attacker_won_clash); dd += r.total_dmg_to_defender; da += r.total_dmg_to_attacker
					dk += int(r.defender_destroyed); ak += int(r.attacker_destroyed); ac += r.atk_cards_held; dc += r.def_cards_held
			print("%-9s entrenched=%-5s atk_win %2d/%d  dmg def %5.1f  dmg atk %5.1f  cards %.2f-%.2f  def_killed %d atk_killed %d" % [tname, ent, aw, n, float(dd)/n, float(da)/n, float(ac)/n, float(dc)/n, dk, ak])
	gs.free()
	quit()
