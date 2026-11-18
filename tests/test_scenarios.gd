# test_scenarios.gd
#
# Stage 15: every scenario file loads, names only settings that exist, and
# its overrides actually reach the simulation. A typo in a scenario file
# fails here instead of silently doing nothing.
extends TestCase


func test_every_scenario_loads_and_applies_cleanly() -> void:
	var scenarios := ScenarioCatalog.load_all()
	check_true(scenarios.size() >= 5, "the built-in scenarios are found (got %d)" % scenarios.size())
	var covered := {}
	for scenario in scenarios:
		scenario.problems.clear()
		var plant := scenario.create_plant()
		var pid := PidController.new()
		var simulation := Simulation.new(plant, pid)
		SetpointPanel.apply_defaults(simulation)
		NonidealityPanel.apply_defaults(simulation)
		DisturbancePanel.apply_defaults(simulation)
		scenario.apply_settings(simulation, pid)
		check_true(scenario.problems.is_empty(), "'%s': %s" % [scenario.title, ", ".join(scenario.problems)])
		check_true(scenario.title != "" and scenario.notes != "", "'%s' has a title and notes" % scenario.title)
		simulation.step_many(1000)
		check_true(is_finite(simulation.get_true_output()), "'%s' runs" % scenario.title)
		covered[plant.get_script()] = true
	for index in PlantCatalog.get_count():
		var plant := PlantCatalog.create_plant(index)
		check_true(covered.has(plant.get_script()), "a scenario uses %s" % plant.get_display_name())


func test_overrides_reach_the_simulation() -> void:
	var scenario := Scenario.new()
	scenario.title = "test"
	scenario.plant_script = FlywheelPlant
	scenario.plant_parameters = {"inertia": 0.001}
	scenario.pid_settings = {"integral_gain": 3, "anti_windup": PidController.AntiWindup.CLAMPING}
	scenario.sensor_settings = {"noise_enabled": true, "noise_std": 2.5}
	scenario.setpoint_settings = {"pattern": SetpointGenerator.Pattern.RAMP, "target_level": 100.0}
	scenario.controller_rate_hz = 50.0
	var plant := scenario.create_plant()
	var pid := PidController.new()
	var simulation := Simulation.new(plant, pid)
	scenario.apply_settings(simulation, pid)
	check_true(scenario.problems.is_empty(), "no problems")
	check_equal(plant.get_parameter("inertia"), 0.001, "plant parameter")
	check_equal(pid.integral_gain, 3.0, "int written into a float gain")
	check_equal(pid.anti_windup, PidController.AntiWindup.CLAMPING, "enum setting")
	check_true(simulation.sensor.noise_enabled, "sensor toggle")
	check_equal(simulation.setpoint_generator.pattern, SetpointGenerator.Pattern.RAMP, "setpoint pattern")
	check_near(simulation.get_actual_controller_rate_hz(), 50.0, 1e-9, "controller rate")


func test_unknown_names_are_reported() -> void:
	var scenario := Scenario.new()
	scenario.title = "typo test"
	scenario.print_warnings = false
	scenario.plant_script = FlywheelPlant
	scenario.plant_parameters = {"inertai": 1.0}
	scenario.sensor_settings = {"nosie_enabled": true}
	var plant := scenario.create_plant()
	var pid := PidController.new()
	scenario.apply_settings(Simulation.new(plant, pid), pid)
	check_equal(scenario.problems.size(), 2, "both typos reported")


func _peak_temperature(anti_windup: PidController.AntiWindup) -> float:
	var scenario := load("res://scenarios/06_hotend_windup.tres") as Scenario
	var plant := scenario.create_plant()
	var pid := PidController.new()
	pid.output_min = plant.get_input_definition().min_value
	pid.output_max = plant.get_input_definition().max_value
	var simulation := Simulation.new(plant, pid)
	SetpointPanel.apply_defaults(simulation)
	scenario.apply_settings(simulation, pid)
	pid.anti_windup = anti_windup
	simulation.reset()
	var peak := -INF
	for i in 150:  # 150 s
		simulation.step_many(1000)
		peak = maxf(peak, simulation.get_true_output())
	return peak


func test_windup_scenario_shows_its_lesson() -> void:
	var without := _peak_temperature(PidController.AntiWindup.NONE)
	var clamped := _peak_temperature(PidController.AntiWindup.CLAMPING)
	print("    windup scenario peaks: none %.1f °C, clamping %.1f °C" % [without, clamped])
	check_true(without > 215.0, "clear overshoot without anti-windup (peak %.1f)" % without)
	check_true(clamped < without - 10.0, "clamping reduces it (peak %.1f)" % clamped)
