extends SceneTree

## Renders a scene for a few frames and saves a PNG of the window, for checking UI layout.
##   godot --path . -s tools/ui_snapshot/snapshot.gd -- <scene> <out.png> [state]
## state:
##   Battlefield: "select" picks the first Coalition walker and hovers an enemy,
##                "manual" opens the field manual, "gameover" shows the debrief.
##   MainMenu:    "rules" opens Rules of Engagement on Chapter 2 (or "rules:<0-6>").
##   BattlePreview: auto-hides development overlay HUD.
## Needs a display (not --headless): the headless renderer produces empty images.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <scene> <out.png> [state]")
		quit(2)
		return
	_run(args[0], args[1], args[2] if args.size() > 2 else "")

func _run(scene_path: String, out_path: String, state: String) -> void:
	await process_frame
	change_scene_to_file(scene_path)
	for i in 30:
		await process_frame
	var scene := current_scene
	if scene != null:
		if scene.has_method("center_camera_on_map"):
			var ui = scene.get("ui_overlay")
			match state:
				"select":
					var player = null
					var enemy = null
					for u in scene.get("unit_container").get_children():
						if u.mech_data.faction == MechData.Faction.PLAYER and player == null:
							player = u
						elif u.mech_data.faction == MechData.Faction.AI and enemy == null:
							enemy = u
					if player != null:
						ui.selected_mech = player.mech_data
					if enemy != null:
						var td = scene.get("grid_map").get_tile(enemy.mech_data.grid_pos)
						ui.hovered_tile = td
						ui.hovered_reach_info = {"fuel_spent": 4, "fuel_left": 9}
						if player != null:
							ui.current_forecast = SkirmishEngine.compute_forecast(player.mech_data, enemy.mech_data, td, td)
				"manual":
					ui.show_manual_modal = true
				"gameover":
					var gs := root.get_node("GlobalState")
					gs.last_battle_winner = 0
					gs.last_battle_reason = "All five Iron Bridge objectives held through the Syndicate response phase."
					ui.trigger_game_over()
		elif "show_rules" in scene:
			if state == "rules" or state.begins_with("rules:"):
				scene.show_rules = true
				if state.begins_with("rules:"):
					scene.rules_chapter = int(state.split(":")[1])
				else:
					scene.rules_chapter = 1 # Chapter 2: Movement & Fuel
				scene.queue_redraw()
		elif scene.get_script() != null and scene.get_script().resource_path.ends_with("BattlePreview.gd"):
			var hud = scene.get("_hud")
			if hud != null:
				hud.visible = false
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path, " ", img.get_size())
	quit(0)