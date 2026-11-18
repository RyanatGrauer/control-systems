# test_ui_smoke.gd
#
# Builds the real main screen, switches through every scenario in both
# controller modes, every setpoint pattern, and runs frames. It checks nothing
# visual; its job is to fail (through the runner's error counter) if any UI
# code hits a script error. Rendering is a dummy in headless mode.
extends TestCase

const MainScreenScene: PackedScene = preload("res://ui/main_screen.tscn")


func _run_frames(screen: Node, count: int) -> void:
	for i in count:
		screen._process(1.0 / 60.0)


func test_every_plant_and_mode_runs() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)  # runs _ready(): loads scenario 0
	for plant_index in screen._scenarios.size():
		screen._load_scenario(plant_index, 7, 2.0)
		for mode in [0, 1]:  # Manual, PID
			screen._on_controller_mode_selected(mode)
			_run_frames(screen, 30)
			screen._step_once()
			screen._toggle_pause()  # resume
			screen._reset_run()
			_run_frames(screen, 10)
		check_true(screen._simulation.get_time() > 0.0, "time advanced for scenario %d" % plant_index)
	screen.queue_free()


func test_setpoint_patterns_and_gain_keys() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	screen._on_controller_mode_selected(1)
	var panel: SetpointPanel = screen._setpoint_panel
	for index in SetpointPanel.SETTINGS_FOR_PATTERN.size():
		panel._on_pattern_selected(index)
		_run_frames(screen, 20)
		screen._metrics_bar.refresh()
	var pid: PidController = screen._pid_controller
	var before := pid.proportional_gain
	screen._pid_panel.select_gain(0)
	screen._pid_panel.nudge_selected_gain(1.0)
	check_near(pid.proportional_gain, before * 1.1, before * 1e-9, "Kp nudged x1.1")
	screen._pid_panel.select_gain(1)  # Ki starts at 0
	screen._pid_panel.nudge_selected_gain(1.0)
	var ki_info: QuantityInfo = screen._simulation.plant.get_pid_gain_definitions()[1]
	check_near(pid.integral_gain, ki_info.max_value * 0.01, 1e-12, "Ki nudged up from zero to 1% of max")
	screen._pid_panel.nudge_selected_gain(-1.0)
	check_equal(pid.integral_gain, 0.0, "Ki nudged back down to exactly zero")
	screen.queue_free()


func test_setpoint_bar_flip_and_sync() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	var generator: SetpointGenerator = screen._simulation.setpoint_generator
	var old_target := generator.target_level
	var old_start := generator.start_level
	screen._setpoint_bar.flip()
	check_equal(generator.target_level, old_start, "flip moves target to the old start level")
	check_equal(generator.start_level, old_target, "flip moves start level to the old target")
	screen._setpoint_bar.flip()
	check_equal(generator.target_level, old_target, "flipping twice restores the target")
	_run_frames(screen, 5)
	screen.queue_free()


func test_nonideality_panel_builds_for_every_plant() -> void:
	for index in PlantCatalog.get_count():
		var simulation := Simulation.new(PlantCatalog.create_plant(index), PidController.new())
		NonidealityPanel.apply_defaults(simulation)
		var panel := NonidealityPanel.new()
		panel.setup(simulation)
		check_true(not simulation.sensor.noise_enabled, "noise off by default")
		check_true(simulation.sensor.noise_std > 0.0, "noise default scaled to plant")
		check_true(simulation.actuator.saturation_max > simulation.actuator.saturation_min,
				"saturation defaults to the input range")
		panel.free()


func test_disturbance_panel_and_poke() -> void:
	for index in PlantCatalog.get_count():
		var simulation := Simulation.new(PlantCatalog.create_plant(index), PidController.new())
		DisturbancePanel.apply_defaults(simulation)
		var panel := DisturbancePanel.new()
		panel.setup(simulation)
		check_true(not simulation.disturbance_generator.step_enabled, "step load off by default")
		simulation.step_many(100)
		simulation.poke(1.0)
		simulation.step_many(10)
		check_true(simulation.disturbance != 0.0, "a poke produces a disturbance (plant %d)" % index)
		simulation.step_many(200)
		check_near(simulation.disturbance, 0.0, 1e-12, "the poke ends")
		panel.free()


func test_drift_restored_on_reset() -> void:
	var plant := HotendPlant.new()
	var simulation := Simulation.new(plant, ManualController.new())
	var generator := simulation.disturbance_generator
	generator.drift_enabled = true
	generator.drift_key = "ambient_temperature"
	generator.drift_factor = 2.0
	generator.drift_time = 0.01
	simulation.step_many(50)
	check_near(plant.get_parameter("ambient_temperature"), 50.0, 1e-12, "drifted")
	simulation.reset()
	check_near(plant.get_parameter("ambient_temperature"), 25.0, 1e-12, "restored")
	check_near(simulation.get_true_output(), 25.0, 1e-12, "initial state uses the restored value")


func test_snapshots_and_ghosts() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	screen._on_controller_mode_selected(1)
	var pid: PidController = screen._pid_controller
	pid.proportional_gain = 0.05
	screen._on_snapshot_save("A")
	pid.proportional_gain = 0.2
	pid.integral_gain = 1.0
	screen._on_snapshot_save("B")
	screen._reset_run()  # (the first run mixed Manual and PID: plain label)
	check_equal(screen._ghosts.size(), 0, "a sub-second run is not kept")
	_run_frames(screen, 120)  # 2 s of a pure run B
	screen._on_snapshot_load("A")
	check_near(pid.proportional_gain, 0.05, 1e-12, "slot A restored Kp")
	check_near(pid.integral_gain, 0.0, 1e-12, "slot A restored Ki")
	check_near(screen._simulation.get_time(), 0.0, 1e-12, "loading re-runs from t = 0")
	check_equal(screen._ghosts.size(), 1, "the B run became a ghost")
	check_equal(screen._ghosts[0].label, "B", "ghost labelled with its slot")
	_run_frames(screen, 120)
	pid.proportional_gain = 0.3  # changed after loading: no longer "A"
	screen._reset_run()
	check_equal(screen._ghosts[1].label, "run 2", "tweaked run gets a plain label")
	pid.apply_tuning(screen._get_slots()["A"])
	screen._on_controller_mode_selected(0)
	_run_frames(screen, 120)
	screen._on_controller_mode_selected(1)
	_run_frames(screen, 10)
	screen._reset_run()
	check_equal(screen._ghosts[2].label, "run 3", "a run that switched modes gets a plain label")
	for i in 4:
		_run_frames(screen, 90)
		screen._reset_run()
	check_equal(screen._ghosts.size(), 3, "only the newest ghosts are kept")
	screen._on_clear_ghosts()
	check_equal(screen._ghosts.size(), 0, "clear ghosts")
	screen.queue_free()


func test_pid_tuning_round_trip() -> void:
	var source := PidController.new()
	source.proportional_gain = 1.5
	source.anti_windup = PidController.AntiWindup.BACK_CALCULATION
	source.feedforward_enabled = true
	source.gravity_gain = 2.0
	var tuning := source.get_tuning()
	check_true(not tuning.has("_integral_term"), "memory is not part of a tuning")
	var target := PidController.new()
	target.apply_tuning(tuning)
	check_equal(target.get_tuning(), tuning, "every setting copied")


func test_block_diagram_and_equations() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	for index in screen._scenarios.size():
		screen._load_scenario(index, 1, 1.0)
		for mode in [0, 1]:
			screen._on_controller_mode_selected(mode)
			_run_frames(screen, 20)
			var text: String = screen._simulation.plant.get_equation_text(screen._simulation.state,
					screen._simulation.plant_input, screen._simulation.disturbance)
			check_true(text.length() > 20, "plant equation text for scenario %d" % index)
			check_true(screen._simulation.controller.get_equation_text(1.0, 0.5) != "",
					"controller equation text")
		for block_id in ["setpoint", "controller", "actuator", "plant", "sensor", "disturbance"]:
			screen._on_block_clicked(block_id)
			check_true((screen._sections[block_id] as CollapsibleSection).body.visible,
					"clicking %s opens its section" % block_id)
	screen.queue_free()


func test_pid_equation_matches_terms() -> void:
	var pid := PidController.new()
	pid.proportional_gain = 2.0
	pid.integral_gain = 0.0
	pid.use_output_limits = true
	pid.output_min = -1.0
	pid.output_max = 1.0
	pid.compute(3.0, 1.0, 0.01)
	var text := pid.get_equation_text(3.0, 1.0)
	check_true("e = r - y = 3.0 - 1.0 = 2.0" in text, "error line: " + text)
	check_true("P = Kp·e = 2.0·2.0 = 4.0" in text, "P line")
	check_true("CLIPPED" in text, "clipping is called out")


func test_presenter_and_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	_run_frames(screen, 5)
	screen._set_presenter(true)
	check_true(tree.root.content_scale_factor > 1.0, "presenter scales the UI up")
	check_true(not screen._advanced_sections[0].visible, "presenter hides advanced sections")
	check_true(DisplaySettings.line_scale() > 1.0, "presenter thickens lines")
	screen._load_scenario(1, 1, 1.0)  # rebuilding keeps presenter mode
	check_true(not screen._advanced_sections[0].visible, "still presenter after a scenario load")
	screen._set_presenter(false)
	check_near(tree.root.content_scale_factor, 1.0, 1e-6, "presenter off restores scale")

	for preset in [DisplaySettings.Preset.LOW, DisplaySettings.Preset.HIGH,
			DisplaySettings.Preset.MEDIUM]:
		DisplaySettings.apply_preset(preset)
		screen._on_display_settings_changed()
		_run_frames(screen, 3)
	DisplaySettings.apply_preset(DisplaySettings.Preset.LOW)
	check_true(not DisplaySettings.shadows and not DisplaySettings.animated_ghost,
			"Low preset turns effects off")
	DisplaySettings.apply_preset(DisplaySettings.Preset.MEDIUM)
	screen.queue_free()


func test_saturation_badge() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	screen._load_scenario(0, 1, 1.0)
	screen._simulation.actuator.saturation_enabled = true
	screen._simulation.actuator.saturation_max = 0.1
	screen._manual_controller.manual_command = 5.0
	_run_frames(screen, 30)
	check_true(screen._plant_view._saturation_badge.visible, "badge shows while saturated")
	screen.queue_free()


# Presenter mode scales the UI up, so the layout's minimum size must still fit
# the default 1280x720 window divided by the scale (or the right edge is cut off).
func test_presenter_layout_fits() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	_run_frames(screen, 3)
	screen._set_presenter(true)
	_run_frames(screen, 3)
	var available := Vector2(1280.0, 720.0) / DisplaySettings.PRESENTER_UI_SCALE
	var needed: Vector2 = screen._background.get_parent().get_child(1).get_combined_minimum_size()
	check_true(needed.x <= available.x, "presenter layout width %d fits %d" % [needed.x, available.x])
	check_true(needed.y <= available.y, "presenter layout height %d fits %d" % [needed.y, available.y])
	screen._set_presenter(false)
	screen.queue_free()


func test_snapshots_are_saved_and_restored() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	screen._load_scenario(3, 1, 1.0)
	screen._pid_controller.proportional_gain = 4.25
	screen._on_snapshot_save("C")
	for i in 120:  # 2 s of frames: past the autosave delay
		screen._process(1.0 / 60.0)
	screen.queue_free()

	var again := MainScreenScene.instantiate()
	tree.root.add_child(again)  # _ready loads the save and the last scenario
	check_equal(again._scenario_index, 3, "reopens the last scenario")
	check_true(again._get_slots().has("C"), "snapshot came back")
	check_near(again._get_slots()["C"]["proportional_gain"], 4.25, 1e-12, "with its gain")
	again._save_store.reset_all()
	again.queue_free()
