extends SceneTree
## Count how often entrenching makes a fight WORSE for the defender, across all chassis pairs,
## approach/target terrains and elevations.
## Run: godot --headless --path . -s tests/backfire.gd
func _init() -> void:
	var gs = load("res://autoload/GlobalState.gd").new()
	gs._ready()
	var ids := ["vanguard","goliath","falke","donner","kommandant","moloch"]
	var terr: Array = GridTileData.TerrainType.values()
	var tn: Array = GridTileData.TerrainType.keys()
	var n := 0; var worse := 0; var better := 0; var same := 0; var flipped_lost := 0; var flipped_won := 0
	var sum_cut := 0.0; var ex := []
	for a in ids:
		for d in ids:
			for ft in terr:
				for tt in terr:
					for fe in range(0, 4):
						for te in range(0, 4):
							if absi(fe - te) > 1: continue
							var am: MechData = gs.create_mech_instance(a, MechData.Faction.AI, "A", Vector2i.ZERO, "1")
							var dm: MechData = gs.create_mech_instance(d, MechData.Faction.PLAYER, "D", Vector2i.ZERO, "2")
							var f := GridTileData.new(Vector2i.ZERO, ft, fe); var t := GridTileData.new(Vector2i.ONE, tt, te)
							var r0 := SkirmishEngine.resolve_skirmish(am, dm, f, t, false)
							dm.is_entrenched = true
							var r1 := SkirmishEngine.resolve_skirmish(am, dm, f, t, false)
							n += 1
							var net0: int = r0.total_dmg_to_defender - r0.total_dmg_to_attacker
							var net1: int = r1.total_dmg_to_defender - r1.total_dmg_to_attacker
							sum_cut += r0.total_dmg_to_defender - r1.total_dmg_to_defender
							if net1 > net0:
								worse += 1
								if ex.size() < 3: ex.append("%s->%s %s(%d)->%s(%d): net %d -> %d, cards %d-%d -> %d-%d" % [a, d, tn[ft], fe, tn[tt], te, net0, net1, r0.atk_cards_held, r0.def_cards_held, r1.atk_cards_held, r1.def_cards_held])
							elif net1 < net0: better += 1
							else: same += 1
							if r1.attacker_won_clash and not r0.attacker_won_clash: flipped_lost += 1
							if r0.attacker_won_clash and not r1.attacker_won_clash: flipped_won += 1
	print("fights %d | entrench helps defender %d (%.0f%%) | no change %d (%.0f%%) | HURTS defender %d (%.0f%%)" % [n, better, 100.0*better/n, same, 100.0*same/n, worse, 100.0*worse/n])
	print("avg damage taken cut %.1f | clash turned into a defender win %d | clash turned into a defender LOSS %d" % [sum_cut/n, flipped_won, flipped_lost])
	for e in ex: print("  e.g. " + e)
	gs.free(); quit()
