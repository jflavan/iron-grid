extends SceneTree

## Renders a scene for a few frames and saves a PNG of the window, for checking UI layout.
##   godot --path . -s tools/ui_snapshot/snapshot.gd -- <scene> <out.png> [state]
## state:
##   Battlefield: "select" picks the first Coalition walker and hovers an enemy,
##                "manual" opens the field manual, "gameover" shows the debrief.
##   MainMenu:    "rules" opens Rules of Engagement on Chapter 2 (or "rules:<0-6>").
##   BattlePreview: auto-hides development overlay HUD.
##   Story mode ("story[:<chapter id>[:<what>]]", e.g. "story:m03:briefing"):
##     Story.tscn:  "story" is the campaign list (shown with five chapters cleared); with a chapter id
##                  its opening dialog, <what> = a number skips that many lines, "card" shows the
##                  chapter title card, "briefing" the mission briefing page.
##     Battlefield: the story mission with its turn-1 dialog up; <what> = "battle" opens a skirmish
##                  between Leon (or the first named pilot) and the nearest Syndikat walker.
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
	var story: PackedStringArray = state.split(":") if state.begins_with("story") else PackedStringArray()
	if not story.is_empty():
		# Loaded by path: this script compiles before the autoloads exist, so it must not name a
		# class whose script (or whose dependencies) refers to GlobalState.
		var gs := root.get_node("GlobalState")
		var progress = load("res://scripts/story/StoryProgress.gd")
		progress.path = "user://story_snapshot_save.json"
		progress.reset()
		progress.mark_cleared(4)
		gs.story_chapter = load("res://scripts/story/StoryCampaign.gd").index_of(story[1]) if story.size() > 1 else -1
		gs.story_stage = "pre" if gs.story_chapter >= 0 else "list"
	change_scene_to_file(scene_path)
	for i in 30:
		await process_frame
	var scene := current_scene
	if scene != null and not story.is_empty():
		var what: String = story[2] if story.size() > 2 else ""
		if scene.has_method("start_chapter"):
			if what == "briefing":
				scene.advance(true)
			elif what != "card":
				scene.advance()   # dismiss the title card
				for i in int(what):
					scene.advance()
					scene.advance()
				await create_timer(0.7).timeout   # let the scene fade in
				scene.advance()   # finish typing the line on screen
		elif scene.has_method("center_camera_on_map") and what == "battle":
			var ui = scene.get("ui_overlay")
			while ui.story_dialog_open():
				ui.advance_story_dialog(true)
			var uc = scene.get("unit_container")
			var hero = uc.unit_of_pilot("leon")
			if hero == null:
				for u in uc.units:
					if u.mech_data.pilot_id != "" and u.mech_data.faction == MechData.Faction.PLAYER:
						hero = u
						break
			var foe = null
			for u in uc.get_faction_units(MechData.Faction.AI):
				if foe == null or u.mech_data.pilot_id != "":
					foe = u
			if hero != null and foe != null:
				uc.move_unit(hero, foe.mech_data.grid_pos + Vector2i(-1, 0))
				scene._execute_unit_attack(hero, foe, 0)
				for i in 10:
					await process_frame
				while ui.story_dialog_open():
					ui.advance_story_dialog(true)
				for i in 60:
					await process_frame
		elif scene.has_method("center_camera_on_map"):
			scene.get("ui_overlay").advance_story_dialog()   # finish typing the line on screen
	elif scene != null:
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