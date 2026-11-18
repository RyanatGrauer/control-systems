# test_feedforward_and_profile.gd
#
# Stage 13: trapezoidal motion profile and kS/kV/kA/kG feedforward.
extends TestCase


func _make_profile() -> TrapezoidalProfile:
	var profile := TrapezoidalProfile.new()
	profile.max_velocity = 2.0
	profile.max_acceleration = 1.0
	profile.reset(0.0)
	return profile


func test_trapezoid_from_rest() -> void:
	var profile := _make_profile()
	profile.plan_to(10.0, 0.0)
	# Accelerate 2 s (covers 2 m), cruise 3 s (6 m), brake 2 s (2 m): total 7 s.
	var at_1 := profile.sample(1.0)
	check_near(at_1[1], 1.0, 1e-12, "accelerating at 1 m/s²")
	var at_4 := profile.sample(4.0)
	check_near(at_4[1], 2.0, 1e-12, "cruising at max velocity")
	check_near(at_4[0], 2.0 + 2.0 * 2.0, 1e-12, "position while cruising")
	var at_6 := profile.sample(6.0)
	check_near(at_6[2], -1.0, 1e-12, "braking")
	var at_end := profile.sample(7.0)
	check_near(at_end[0], 10.0, 1e-9, "arrives exactly")
	check_near(at_end[1], 0.0, 1e-9, "arrives at rest")


func test_triangle_for_short_move() -> void:
	var profile := _make_profile()
	profile.plan_to(1.0, 0.0)
	# Peak speed sqrt(a*d) = 1 m/s < max, reached at t = 1 s; arrives at t = 2 s.
	check_near(profile.sample(1.0)[1], 1.0, 1e-12, "triangle peak")
	check_near(profile.sample(2.0)[0], 1.0, 1e-9, "arrives")


func test_replan_mid_move_is_continuous() -> void:
	var profile := _make_profile()
	profile.plan_to(10.0, 0.0)
	var before := profile.sample(3.0)
	profile.plan_to(-5.0, 3.0)  # reverse direction while cruising
	var after := profile.sample(3.0)
	check_near(after[0], before[0], 1e-12, "position continuous")
	check_near(after[1], before[1], 1e-12, "velocity continuous")
	var end_time := 3.0 + 60.0
	check_near(profile.sample(end_time)[0], -5.0, 1e-9, "reaches the new target")
	# Speed never exceeds the limit along the way.
	var time := 3.0
	while time < 20.0:
		check_true(absf(profile.sample(time)[1]) <= 2.0 + 1e-9, "speed limit at t=%s" % time)
		time += 0.25


func test_feedforward_terms() -> void:
	var pid := PidController.new()
	pid.proportional_gain = 0.0
	pid.use_output_limits = false
	pid.feedforward_enabled = true
	pid.static_gain = 0.5
	pid.velocity_gain = 2.0
	pid.acceleration_gain = 3.0
	pid.gravity_gain = 1.0
	pid.reference_velocity = -1.0
	pid.reference_acceleration = 0.5
	var output := pid.compute(0.0, 0.0, 0.01)
	check_near(output, -0.5 - 2.0 + 1.5 + 1.0, 1e-12, "kS sign(v) + kV v + kA a + kG")
	check_near(pid.get_term_contributions()["ff"], output, 1e-12, "FF reported as its own term")
	pid.gravity_uses_cosine = true
	pid.static_gain = 0.0
	pid.velocity_gain = 0.0
	pid.acceleration_gain = 0.0
	check_near(pid.compute(0.0, PI / 3.0, 0.01), 0.5, 1e-12, "kG cos(60°) = kG/2")


func test_flywheel_kv_alone_reaches_target() -> void:
	var plant := FlywheelPlant.new()
	var pid := PidController.new()
	pid.proportional_gain = 0.0
	pid.output_min = -12.0
	pid.output_max = 12.0
	pid.feedforward_enabled = true
	pid.velocity_gain = 1.0 / (plant.get_parameter("torque_constant")
			/ (pow(plant.get_parameter("torque_constant"), 2.0)
			+ plant.get_parameter("viscous_friction") * plant.get_parameter("resistance")))
	var simulation := Simulation.new(plant, pid)
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.CONSTANT
	simulation.setpoint_generator.target_level = 300.0
	simulation.reset()
	simulation.step_many(20000)  # 20 time constants
	check_near(simulation.get_true_output(), 300.0, 0.01, "ideal kV alone gives zero error")


func test_elevator_kg_removes_sag() -> void:
	var plant := ElevatorPlant.new()
	var pid := PidController.new()
	pid.proportional_gain = 10.0
	pid.output_min = -12.0
	pid.output_max = 12.0
	pid.feedforward_enabled = true
	pid.gravity_gain = plant.get_hold_voltage()
	var simulation := Simulation.new(plant, pid)
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.CONSTANT
	simulation.setpoint_generator.target_level = 1.0
	simulation.reset()
	simulation.step_many(10000)
	# Static friction leaves at most F_static*R/(k*Kp) of error.
	var stiction_band := plant.get_parameter("static_friction") * plant.get_parameter("resistance") \
			/ plant.get_parameter("motor_constant") / pid.proportional_gain
	check_near(simulation.get_true_output(), 1.0, stiction_band + 1e-6, "kG cancels gravity")


func test_simulation_profile_feeds_reference() -> void:
	var simulation := Simulation.new(ServoPlant.new(), PidController.new())
	simulation.use_motion_profile = true
	simulation.motion_profile.max_velocity = 1.0
	simulation.motion_profile.max_acceleration = 2.0
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.STEP
	simulation.setpoint_generator.start_level = 0.0
	simulation.setpoint_generator.target_level = 1.0
	simulation.setpoint_generator.start_time = 0.1
	simulation.reset()
	simulation.step_many(1000)  # t = 1 s: past the 0.5 s ramp-up, cruising
	check_near(simulation.controller.reference_velocity, 1.0, 1e-9, "position plant: v_ref = profile speed")
	check_true(simulation.setpoint < 1.0, "setpoint is still moving, not jumped")
