# test_pid.gd
#
# PID math against hand-calculated values (README 11).
extends TestCase


func _make_pid(kp: float, ki: float, kd: float) -> PidController:
	var pid := PidController.new()
	pid.proportional_gain = kp
	pid.integral_gain = ki
	pid.derivative_gain = kd
	pid.use_output_limits = false
	return pid


func test_hand_calculated_sequence() -> void:
	# Kp = 2, Ki = 1, Kd = 0.5, dt = 0.1, setpoint 1, measurements 0, 0.5, 1.25
	# -> errors 1, 0.5, -0.25.
	# tick 1: P = 2,    I = 0.1,   D = 0 (no previous error)        u = 2.1
	# tick 2: P = 1,    I = 0.15,  D = 0.5 * (0.5 - 1) / 0.1 = -2.5   u = -1.35
	# tick 3: P = -0.5, I = 0.125, D = 0.5 * (-0.25 - 0.5) / 0.1 = -3.75  u = -4.125
	var pid := _make_pid(2.0, 1.0, 0.5)
	check_near(pid.compute(1.0, 0.0, 0.1), 2.1, 1e-12, "tick 1")
	check_near(pid.compute(1.0, 0.5, 0.1), -1.35, 1e-12, "tick 2")
	var terms := pid.get_term_contributions()
	check_near(terms["d"], -2.5, 1e-12, "tick 2 D term")
	check_near(pid.compute(1.0, 1.25, 0.1), -4.125, 1e-12, "tick 3")
	terms = pid.get_term_contributions()
	check_near(terms["p"], -0.5, 1e-12, "tick 3 P term")
	check_near(terms["i"], 0.125, 1e-12, "tick 3 I term")
	check_near(terms["sum"], -4.125, 1e-12, "tick 3 sum")


func test_output_limits_clamp_but_terms_do_not() -> void:
	var pid := _make_pid(10.0, 0.0, 0.0)
	pid.use_output_limits = true
	pid.output_min = -12.0
	pid.output_max = 12.0
	check_near(pid.compute(5.0, 0.0, 0.01), 12.0, 1e-12, "clamped high")
	check_near(pid.get_term_contributions()["sum"], 50.0, 1e-12, "sum before clamping")
	check_near(pid.compute(-5.0, 0.0, 0.01), -12.0, 1e-12, "clamped low")


func test_changing_ki_does_not_bump_output() -> void:
	# The integral stores Ki * sum(e * dt), so a new Ki only affects future growth.
	var pid := _make_pid(0.0, 1.0, 0.0)
	for i in 10:
		pid.compute(1.0, 0.0, 0.1)  # integral = 1.0
	pid.integral_gain = 5.0
	check_near(pid.compute(1.0, 1.0, 0.1), 1.0, 1e-12, "zero error after Ki change: output stays 1.0")


func test_reset_clears_memory() -> void:
	var pid := _make_pid(1.0, 1.0, 1.0)
	pid.compute(1.0, 0.0, 0.1)
	pid.compute(1.0, 0.2, 0.1)
	pid.reset()
	check_near(pid.compute(1.0, 0.0, 0.1), 1.1, 1e-12, "after reset: P=1, I=0.1, D=0")


func test_reset_integral_only() -> void:
	var pid := _make_pid(0.0, 1.0, 0.0)
	pid.compute(1.0, 0.0, 1.0)
	pid.reset_integral()
	check_near(pid.compute(0.0, 0.0, 1.0), 0.0, 1e-12, "integral cleared")


func test_flywheel_p_only_leaves_steady_state_error_and_i_removes_it() -> void:
	# README 5 lesson 1, checked against the closed-loop formula:
	# steady state = K*Kp / (1 + K*Kp) of the target, K = plant speed per volt.
	var plant := FlywheelPlant.new()
	var pid := _make_pid(0.05, 0.0, 0.0)
	var simulation := Simulation.new(plant, pid)
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.CONSTANT
	simulation.setpoint_generator.target_level = 300.0
	simulation.reset()
	simulation.step_many(20000)
	var plant_gain := plant.get_steady_state_speed(1.0)
	var expected := 300.0 * plant_gain * 0.05 / (1.0 + plant_gain * 0.05)
	check_near(simulation.state[0], expected, 0.01, "P-only steady state")

	pid.integral_gain = 0.1
	simulation.reset()
	simulation.step_many(30000)
	check_near(simulation.state[0], 300.0, 0.01, "PI reaches the target")


func test_servo_p_only_has_no_steady_state_error() -> void:
	# Type-1 plant (integrator inside): P alone reaches a fixed target.
	var pid := _make_pid(2.0, 0.0, 0.8)
	var simulation := Simulation.new(ServoPlant.new(), pid)
	simulation.setpoint_generator.pattern = SetpointGenerator.Pattern.CONSTANT
	simulation.setpoint_generator.target_level = 1.0
	simulation.reset()
	simulation.step_many(20000)
	check_near(simulation.state[0], 1.0, 1e-4, "servo angle reaches target with P + D")
