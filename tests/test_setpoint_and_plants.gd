# test_setpoint_and_plants.gd
#
# Setpoint patterns (stage 8) and sanity checks for plants #3 and #4.
extends TestCase


func _make_generator(pattern: SetpointGenerator.Pattern) -> SetpointGenerator:
	var generator := SetpointGenerator.new()
	generator.pattern = pattern
	generator.start_level = 1.0
	generator.target_level = 5.0
	generator.start_time = 2.0
	generator.period = 4.0
	generator.ramp_rate = 2.0
	generator.amplitude = 0.5
	return generator


func test_constant_and_step() -> void:
	var constant := _make_generator(SetpointGenerator.Pattern.CONSTANT)
	check_equal(constant.value_at(0.0), 5.0, "constant ignores start time")
	var step := _make_generator(SetpointGenerator.Pattern.STEP)
	check_equal(step.value_at(1.999), 1.0, "before step")
	check_equal(step.value_at(2.0), 5.0, "at step")


func test_square_wave() -> void:
	var square := _make_generator(SetpointGenerator.Pattern.SQUARE)
	check_equal(square.value_at(1.0), 1.0, "before start")
	check_equal(square.value_at(2.5), 5.0, "first half period high")
	check_equal(square.value_at(4.5), 1.0, "second half period low")
	check_equal(square.value_at(6.5), 5.0, "next period high")


func test_ramp() -> void:
	var ramp := _make_generator(SetpointGenerator.Pattern.RAMP)
	check_near(ramp.value_at(3.0), 3.0, 1e-12, "1 s at 2/s from 1")
	check_near(ramp.value_at(10.0), 5.0, 1e-12, "holds at target")
	ramp.target_level = -1.0
	check_near(ramp.value_at(2.5), 0.0, 1e-12, "ramps downward too")


func test_sine() -> void:
	var sine := _make_generator(SetpointGenerator.Pattern.SINE)
	check_near(sine.value_at(2.0), 5.0, 1e-12, "starts at centre")
	check_near(sine.value_at(3.0), 5.5, 1e-12, "quarter period: peak")
	check_near(sine.value_at(5.0), 4.5, 1e-12, "three quarters: trough")


func test_mass_spring_damper_free_oscillation() -> void:
	# Released from 0.1 m with no input: matches the damped analytic solution.
	var plant := MassSpringDamperPlant.new()
	var wn := plant.get_natural_frequency()
	var zeta := plant.get_damping_ratio()
	var wd := wn * sqrt(1.0 - zeta * zeta)
	var state := PackedFloat64Array([0.1, 0.0])
	var dt := 0.001
	for i in 3000:
		state = Integrators.rk4_step(plant, state, 0.0, 0.0, i * dt, dt)
	var t := 3.0
	var exact := 0.1 * exp(-zeta * wn * t) * (cos(wd * t) + zeta * wn / wd * sin(wd * t))
	check_near(state[0], exact, 1e-9, "position at t = 3 s")


func test_mass_spring_damper_static_deflection() -> void:
	# A constant force F settles at x = F / k (Hooke's law).
	var plant := MassSpringDamperPlant.new()
	var derivative := plant.compute_derivative(PackedFloat64Array([10.0 / 40.0, 0.0]), 10.0, 0.0, 0.0)
	check_near(derivative[1], 0.0, 1e-12, "no acceleration at x = F/k")


func test_servo_constant_voltage_gives_constant_speed() -> void:
	# The angle keeps growing (integrator in the plant) at K * V rad/s.
	var plant := ServoPlant.new()
	var state := PackedFloat64Array([0.0, plant.get_velocity_gain() * 6.0])
	var derivative := plant.compute_derivative(state, 6.0, 0.0, 0.0)
	check_near(derivative[1], 0.0, 1e-9, "no acceleration at steady speed")
	check_near(derivative[0], plant.get_velocity_gain() * 6.0, 1e-12, "angle rate = speed")


func test_every_catalog_plant_is_consistent() -> void:
	for index in PlantCatalog.get_count():
		var plant := PlantCatalog.create_plant(index)
		var state := plant.get_initial_state()
		check_equal(state.size(), plant.get_state_definitions().size(),
				"%s: state size matches definitions" % plant.get_display_name())
		check_equal(plant.compute_derivative(state, 0.0, 0.0, 0.0).size(), state.size(),
				"%s: derivative size" % plant.get_display_name())
		check_equal(plant.get_pid_gain_definitions().size(), 3,
				"%s: three gain definitions" % plant.get_display_name())
		check_true(ResourceLoader.exists(plant.get_visual_scene_path()),
				"%s: visual scene exists" % plant.get_display_name())
		for info in plant.get_parameter_definitions():
			check_true(info.min_value <= info.default_value and info.default_value <= info.max_value,
					"%s: %s default inside range" % [plant.get_display_name(), info.key])


func test_hotend_heats_only_and_settles_to_rise_per_watt() -> void:
	var plant := HotendPlant.new()
	plant.set_parameter("dead_time", 0.0)
	var derivative := plant.compute_derivative(PackedFloat64Array([25.0]), -40.0, 0.0, 0.0)
	check_near(derivative[0], 0.0, 1e-12, "negative power can't cool below ambient")
	# Steady state at 10 W: T = ambient + R*P = 25 + 60.
	var simulation := Simulation.new(plant, ManualController.new())
	(simulation.controller as ManualController).manual_command = 10.0
	simulation.step_many(int(10.0 * plant.get_time_constant() * 1000.0))
	check_near(simulation.get_true_output(), 85.0, 0.05, "T = ambient + R*P")


func test_hotend_dead_time_delays_response() -> void:
	var plant := HotendPlant.new()
	plant.set_parameter("dead_time", 1.5)
	var simulation := Simulation.new(plant, ManualController.new())
	(simulation.controller as ManualController).manual_command = 40.0
	simulation.step_many(1400)  # 1.4 s: heater has been on, but no heat has arrived
	check_near(simulation.get_true_output(), 25.0, 1e-9, "nothing happens during the dead time")
	simulation.step_many(600)
	check_true(simulation.get_true_output() > 25.1, "heat arrives after the dead time")


func test_elevator_gravity_stops_and_sticking() -> void:
	var plant := ElevatorPlant.new()
	var simulation := Simulation.new(plant, ManualController.new())
	var manual := simulation.controller as ManualController
	simulation.step_many(500)
	check_near(simulation.get_true_output(), 0.0, 1e-12, "with no voltage it rests on the bottom stop")

	manual.manual_command = 12.0
	simulation.step_many(5000)
	check_near(simulation.get_true_output(), ElevatorPlant.RAIL_HEIGHT, 1e-12, "full power hits the top stop")

	# Holding voltage keeps it in place (static friction helps too).
	manual.manual_command = plant.get_hold_voltage()
	simulation.step_many(2000)
	var held_at := simulation.get_true_output()
	simulation.step_many(2000)
	check_near(simulation.get_true_output(), held_at, 1e-6, "hold voltage holds the carriage")

	# Slightly less than hold voltage, but within static friction: it sticks.
	var stiction_volts := plant.get_parameter("static_friction") * plant.get_parameter("resistance") \
			/ plant.get_parameter("motor_constant")
	manual.manual_command = plant.get_hold_voltage() - 0.5 * stiction_volts
	simulation.step_many(2000)
	check_near(simulation.get_true_output(), held_at, 1e-4, "static friction holds it")
	# At 0 V the motor's back-EMF brakes the fall (~0.2 m/s), so allow 10 s.
	manual.manual_command = 0.0
	simulation.step_many(10000)
	check_near(simulation.get_true_output(), 0.0, 1e-12, "falls to the bottom stop when released")
