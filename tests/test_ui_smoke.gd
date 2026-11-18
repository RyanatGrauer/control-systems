# test_ui_smoke.gd
#
# Builds the real main screen, switches through every plant in both
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
	tree.root.add_child(screen)  # runs _ready(): loads plant 0
	for plant_index in PlantCatalog.get_count():
		screen._load_plant(plant_index, 7, 2.0)
		for mode in [0, 1]:  # Manual, PID
			screen._on_controller_mode_selected(mode)
			_run_frames(screen, 30)
			screen._step_once()
			screen._toggle_pause()  # resume
			screen._reset_run()
			_run_frames(screen, 10)
		check_true(screen._simulation.get_time() > 0.0, "time advanced for plant %d" % plant_index)
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
