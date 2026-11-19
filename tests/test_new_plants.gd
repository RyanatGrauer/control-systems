# test_new_plants.gd
#
# PURPOSE
#   Stage 23: physics checks for the arm, cruise-control and drone plants
#   (hand-computed equilibria), and the cascaded PID (it tracks, respects
#   its inner limit, and the arm's kG·cos uses the ANGLE).
extends TestCase


func _make_sim(plant: Plant, controller: Controller) -> Simulation:
	var simulation := Simulation.new(plant, controller)
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.CONSTANT
	return simulation


func _run(simulation: Simulation, seconds: float) -> void:
	simulation.step_many(roundi(seconds / simulation.get_physics_dt()))


func test_arm_hold_voltage_holds_it_level() -> void:
	var arm := ArmPlant.new()
	check_near(arm.get_hold_voltage(), 1.0 * 9.81 * 0.4 * 1.0 / 1.5, 1e-9, "hold voltage")
	var derivative := arm.compute_derivative(PackedFloat64Array([0.0, 0.0]),
			arm.get_hold_voltage(), 0.0, 0.0)
	check_near(derivative[1], 0.0, 1e-9, "no acceleration when level at the hold voltage")
	derivative = arm.compute_derivative(PackedFloat64Array([PI / 2.0, 0.0]), 0.0, 0.0, 0.0)
	check_near(derivative[1], 0.0, 1e-9, "straight up needs no torque")
	var manual := ManualController.new()
	var simulation := _make_sim(arm, manual)
	_run(simulation, 1.0)
	check_near(simulation.state[0], ArmPlant.MIN_ANGLE, 1e-9, "rests on its lower stop")


func test_cruise_forces() -> void:
	var car := CruisePlant.new()
	car.set_parameter("hill_grade", 0.0)
	# Flat road at 25 m/s: drag + rolling.
	var expected := 0.5 * 1.2 * 0.7 * 625.0 + 0.01 * 1500.0 * 9.81 * tanh(50.0)
	check_near(car.get_resisting_force(0.0, 25.0), expected, 1e-6, "flat-road resistance")
	car.set_parameter("hill_grade", 0.05)
	# A quarter hill in, the grade is at its steepest.
	check_near(car.get_grade(125.0), 0.05, 1e-9, "steepest point")
	check_near(car.get_road_height(250.0), 0.05 * 500.0 / TAU * 2.0, 1e-6, "hilltop height")
	var stopped := car.apply_constraints(PackedFloat64Array([10.0, -1.0]))
	check_equal(stopped[1], 0.0, "no rolling backwards")


func test_drone_hover_and_no_negative_thrust() -> void:
	var drone := DronePlant.new()
	var derivative := drone.compute_derivative(PackedFloat64Array([2.0, 0.0]),
			drone.get_hover_thrust(), 0.0, 0.0)
	check_near(derivative[1], 0.0, 1e-9, "hover thrust balances gravity")
	derivative = drone.compute_derivative(PackedFloat64Array([2.0, 0.0]), -20.0, 0.0, 0.0)
	check_near(derivative[1], -9.81, 1e-9, "negative thrust does nothing: free fall")
	var simulation := _make_sim(drone, ManualController.new())
	_run(simulation, 1.0)
	check_equal(simulation.state[0], 0.0, "sits on the pad with no thrust")


func test_drone_cascade_hovers_at_target() -> void:
	var drone := DronePlant.new()
	var cascade := ScenarioSetup.make_cascade(drone)
	cascade.outer.proportional_gain = 1.5
	cascade.inner.proportional_gain = 8.0
	cascade.inner.integral_gain = 4.0
	cascade.inner.feedforward_enabled = true
	cascade.inner.gravity_gain = drone.get_hover_thrust()
	var simulation := _make_sim(drone, cascade)
	simulation.setpoint_generator.target_level = 3.0
	simulation.reset()
	var fastest_climb_request := 0.0
	for i in 15000:  # 15 s
		simulation.step_physics()
		fastest_climb_request = maxf(fastest_climb_request, absf(cascade.inner_setpoint))
	check_near(simulation.state[0], 3.0, 0.02, "hovers at 3 m")
	check_true(fastest_climb_request <= drone.get_inner_setpoint_limit() + 1e-9,
			"outer loop never asks for more than ±2 m/s")
	check_near(fastest_climb_request, 2.0, 1e-6, "a 3 m step does hit the speed limit")
	check_near(simulation.recorder.get_latest("inner_setpoint"), cascade.inner_setpoint, 1e-9,
			"inner setpoint is recorded")


func test_arm_cascade_gravity_uses_the_angle() -> void:
	var arm := ArmPlant.new()
	var cascade := ScenarioSetup.make_cascade(arm)
	cascade.outer.proportional_gain = 5.0
	cascade.inner.proportional_gain = 3.0
	cascade.inner.feedforward_enabled = true
	cascade.inner.gravity_gain = arm.get_hold_voltage()
	cascade.inner.gravity_uses_cosine = true
	var simulation := _make_sim(arm, cascade)
	simulation.setpoint_generator.target_level = 0.0
	simulation.reset()
	_run(simulation, 6.0)
	# With exact kG·cos θ the P-only cascade has no reason to sag.
	check_near(simulation.state[0], 0.0, 0.01, "holds level with kG·cos(angle)")
	check_near(cascade.inner.compute_feedforward(123.0), arm.get_hold_voltage() * cos(simulation.state[0]),
			1e-6, "inner FF uses the arm angle, not the speed")


func test_cascade_tuning_round_trip() -> void:
	var cascade := ScenarioSetup.make_cascade(DronePlant.new())
	cascade.outer.proportional_gain = 2.5
	cascade.inner.integral_gain = 7.0
	var copy := ScenarioSetup.make_cascade(DronePlant.new())
	copy.apply_tuning(cascade.get_tuning())
	check_equal(copy.get_tuning(), cascade.get_tuning(), "tuning round trip")
	check_true(ScenarioSetup.make_cascade(FlywheelPlant.new()) == null, "no cascade for the flywheel")
