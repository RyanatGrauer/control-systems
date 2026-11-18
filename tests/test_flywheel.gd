# test_flywheel.gd
#
# Plant sanity for plant #1 (README 11): the first-order step response must
# match the analytic answer, equilibrium must hold, and units must agree.
extends TestCase


func _make_simulation(voltage: float) -> Simulation:
	var controller := ManualController.new()
	var simulation := Simulation.new(FlywheelPlant.new(), controller)
	controller.manual_command = voltage  # set AFTER construction (reset() zeroes it)
	return simulation


func test_step_response_matches_first_order_formula() -> void:
	var simulation := _make_simulation(12.0)
	var plant := simulation.plant as FlywheelPlant
	var tau := plant.get_time_constant()
	var final_speed := plant.get_steady_state_speed(12.0)
	for check_time in [tau * 0.5, tau, 3.0 * tau]:
		var target_steps := roundi(check_time / simulation.get_physics_dt())
		simulation.step_many(target_steps - simulation.step_count)
		var t := simulation.get_time()
		var exact := final_speed * (1.0 - exp(-t / tau))
		check_near(simulation.state[0], exact, final_speed * 1e-9,
				"speed at t = %s s" % String.num(t, 3))


func test_reaches_free_speed_and_holds_it() -> void:
	var simulation := _make_simulation(12.0)
	var plant := simulation.plant as FlywheelPlant
	simulation.step_many(15000)  # 15 s, about 15 time constants
	check_near(simulation.state[0], plant.get_steady_state_speed(12.0), 1e-3,
			"steady-state speed")
	# README 5: default motor should have an FTC-like free speed (~5600 RPM).
	var rpm := simulation.state[0] * FlywheelPlant.RAD_PER_S_TO_RPM
	check_true(rpm > 5000.0 and rpm < 6200.0, "free speed in RPM was %s" % rpm)


func test_equilibrium_has_zero_acceleration() -> void:
	var plant := FlywheelPlant.new()
	var speed := plant.get_steady_state_speed(6.0)
	var derivative := plant.compute_derivative(PackedFloat64Array([speed]), 6.0, 0.0, 0.0)
	check_near(derivative[0], 0.0, 1e-9, "acceleration at steady state")


func test_rest_with_no_input_stays_at_rest() -> void:
	var simulation := _make_simulation(0.0)
	simulation.step_many(2000)
	check_equal(simulation.state[0], 0.0, "speed with zero voltage")


func test_load_torque_slows_the_wheel() -> void:
	var plant := FlywheelPlant.new()
	var speed := plant.get_steady_state_speed(12.0)
	var derivative := plant.compute_derivative(PackedFloat64Array([speed]), 12.0, 0.05, 0.0)
	check_true(derivative[0] < 0.0, "a positive load torque decelerates the wheel")


func test_time_constant_units() -> void:
	# tau = J*R / (Kt^2 + b*R): kg·m² · ohm / (N·m/A)² -> seconds.
	# With the defaults this should be about one second.
	var tau := FlywheelPlant.new().get_time_constant()
	check_true(tau > 0.5 and tau < 2.0, "default time constant ~1 s, got %s" % tau)


func test_parameter_change_applies_live() -> void:
	var simulation := _make_simulation(12.0)
	simulation.step_many(500)
	var before := simulation.state[0]
	simulation.plant.set_parameter("inertia", 0.004)  # 10x heavier
	simulation.step_many(1)
	var after_heavy := simulation.state[0] - before
	var light := _make_simulation(12.0)
	light.step_many(501)
	var light_gain := light.state[0] - before
	check_true(after_heavy < light_gain * 0.2, "heavier wheel accelerates much less")
