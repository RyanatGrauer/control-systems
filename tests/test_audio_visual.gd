# test_audio_visual.gd
#
# PURPOSE
#   A/V patch: every plant's sound level stays in range, hard stops clunk
#   only on arrival (and only when fast), sound settings save and load, mute
#   silences everything, and every file in assets/ is credited.
extends TestCase

const MainScreenScene: PackedScene = preload("res://ui/main_screen.tscn")


func test_every_plant_sound_is_in_range() -> void:
	for index in PlantCatalog.get_count():
		var plant := PlantCatalog.create_plant(index)
		var visual := (load(plant.get_visual_scene_path()) as PackedScene).instantiate() as PlantVisual3D
		var input := plant.get_input_definition()
		var state := plant.get_initial_state()
		for u: float in [input.min_value, 0.0, input.max_value]:
			var level := visual.get_sound_level(plant, state, u)
			check_true(level.x > 0.2 and level.x < 4.0, "%s pitch %s" % [plant.get_display_name(), level.x])
			check_true(level.y >= 0.0 and level.y <= 1.0, "%s loudness %s" % [plant.get_display_name(), level.y])
		visual.free()


func test_hard_stop_clunks_only_on_arrival() -> void:
	var visual := PlantVisual3D.new()
	var events: Array[float] = []
	visual.sound_event.connect(func(_kind: StringName, strength: float) -> void: events.append(strength))
	visual.track_hard_stop(true, 0.0, 1.0)   # starts resting on the stop: silent
	visual.track_hard_stop(true, 0.0, 1.0)
	check_equal(events.size(), 0, "no clunk while resting at the start")
	visual.track_hard_stop(false, 0.5, 1.0)  # moving freely at half speed...
	visual.track_hard_stop(true, 0.0, 1.0)   # ...then hits
	check_equal(events.size(), 1, "one clunk on arrival")
	check_near(events[0], 0.5, 1e-9, "loudness from the speed just before the hit")
	visual.track_hard_stop(false, 0.01, 1.0)  # creeps off and back slowly
	visual.track_hard_stop(true, 0.0, 1.0)
	check_equal(events.size(), 1, "a slow touch is silent")
	visual.free()


func test_sound_settings_round_trip_and_mute() -> void:
	var saved := DisplaySettings.to_save()
	DisplaySettings.sound_volume = 0.3
	DisplaySettings.plant_sounds = false
	var data := DisplaySettings.to_save()
	DisplaySettings.load_save(DisplaySettings.default_save())
	check_near(DisplaySettings.sound_volume, 0.6, 1e-9, "default volume")
	DisplaySettings.load_save(data)
	check_near(DisplaySettings.sound_volume, 0.3, 1e-9, "volume restored")
	check_near(DisplaySettings.get_gain(true), 0.0, 1e-9, "plant sounds off")
	check_near(DisplaySettings.get_gain(false), 0.3, 1e-9, "interface sounds still on")
	DisplaySettings.sound_on = false
	check_near(DisplaySettings.get_gain(false), 0.0, 1e-9, "mute silences everything")
	DisplaySettings.load_save(saved)


func test_old_save_without_sound_keys_gets_defaults() -> void:
	var old := DisplaySettings.default_save()
	for key: String in ["sound_on", "sound_volume", "plant_sounds", "interface_sounds", "detailed_materials"]:
		old.erase(key)
	old["sound_volume"] = "loud"  # wrong type: replaced by the default
	var clean := SaveStore.validate({"settings": old})
	var settings: Dictionary = clean["settings"]
	check_equal(settings["sound_on"], true, "missing key filled from defaults")
	check_near(settings["sound_volume"], 0.6, 1e-9, "bad value replaced by the default")


func test_mute_key_and_toolbar() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	var was_on := DisplaySettings.sound_on
	screen._toggle_sound()
	check_equal(DisplaySettings.sound_on, not was_on, "M toggles sound")
	check_equal(screen._toolbar._sound_button.text, "Sound" if not was_on else "Muted", "toolbar shows it")
	screen._toggle_sound()
	check_true(InputMap.has_action("sound_mute_toggle"), "mute is an InputMap action")
	screen.queue_free()


func test_plant_loop_follows_the_run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	var saved := DisplaySettings.to_save()
	DisplaySettings.sound_on = true
	DisplaySettings.plant_sounds = true
	screen._load_scenario(screen._find_scenario("Cruise control on hills"), 1, 1.0)
	screen._set_paused(false)
	for i in 30:
		screen._process(1.0 / 60.0)
	var view: PlantView = screen._plant_view
	check_true(view._loop_player.stream == SoundBank.ENGINE_LOOP, "the cruise plays the engine loop")
	check_true(view._loop_player.playing, "engine sound while the car drives")
	check_true(view._loop_pitch > 0.5, "pitch follows the speed")
	screen._set_paused(true)
	for i in 60:
		screen._process(1.0 / 60.0)
	check_true(not view._loop_player.playing, "silent while paused")
	DisplaySettings.load_save(saved)
	screen.queue_free()


func test_every_asset_is_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	check_true(credits.length() > 0, "CREDITS.md exists")
	for path in _list_files("res://assets"):
		var relative := path.trim_prefix("res://")
		var credited := credits.contains(relative)
		if not credited:  # texture sets are listed with a * wildcard
			var stem := relative.get_basename()
			credited = credits.contains(stem.substr(0, stem.rfind("_")) + "_*")
		check_true(credited, "%s is in CREDITS.md" % relative)


func _list_files(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_list_files(folder.path_join(sub)))
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".import"):
			found.append(folder.path_join(file))
	return found
