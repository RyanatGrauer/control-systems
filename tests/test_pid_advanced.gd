# test_pid_advanced.gd
#
# Stage 11: derivative on measurement, D filter, anti-windup, setpoint
# weighting, trapezoidal integration, ISA conversion, bumpless transfer.
extends TestCase


func _make_pid(kp: float, ki: float, kd: float) -> PidController:
	var pid := PidController.new()
	pid.proportional_gain = kp
	pid.integral_gain = ki
	pid.derivative_gain = kd
	pid.use_output_limits = false
	return pid


func test_derivative_kick_and_fix() -> void:
	var on_error := _make_pid(0.0, 0.0, 1.0)
	on_error.compute(0.0, 0.0, 0.01)
	on_error.compute(1.0, 0.0, 0.01)  # setpoint steps by 1
	check_near(on_error.get_term_contributions()["d"], 100.0, 1e-9, "kick = Kd*1/dt")

	var on_measurement := _make_pid(0.0, 0.0, 1.0)
	on_measurement.derivative_on_measurement = true
	on_measurement.compute(0.0, 0.0, 0.01)
	on_measurement.compute(1.0, 0.0, 0.01)
	check_near(on_measurement.get_term_contributions()["d"], 0.0, 1e-12, "no kick on measurement")
	on_measurement.compute(1.0, 0.1, 0.01)  # measurement rises 0.1
	check_near(on_measurement.get_term_contributions()["d"], -10.0, 1e-9, "D = -Kd*dy/dt")


func test_derivative_filter_smooths() -> void:
	var pid := _make_pid(0.0, 0.0, 1.0)
	pid.derivative_on_measurement = true
	pid.derivative_filter_enabled = true
	pid.derivative_filter_tau = 0.09  # dt/(tau+dt) = 0.1
	pid.compute(0.0, 0.0, 0.01)
	pid.compute(0.0, -0.1, 0.01)  # raw D = +10
	check_near(pid.get_term_contributions()["d"], 1.0, 1e-9, "first filtered value = 10% of raw")


func test_trapezoidal_integral() -> void:
	var pid := _make_pid(0.0, 1.0, 0.0)
	pid.integral_method = PidController.IntegralMethod.TRAPEZOIDAL
	pid.compute(1.0, 0.0, 0.1)  # e = 1, first tick uses e alone -> 0.1
	pid.compute(3.0, 0.0, 0.1)  # e = 3, average 2 -> +0.2
	check_near(pid.get_term_contributions()["i"], 0.3, 1e-12, "trapezoid sum")


func test_setpoint_weighting() -> void:
	var pid := _make_pid(2.0, 0.0, 0.0)
	pid.setpoint_weighting_enabled = true
	pid.proportional_setpoint_weight = 0.5
	pid.compute(4.0, 1.0, 0.01)
	check_near(pid.get_term_contributions()["p"], 2.0 * (0.5 * 4.0 - 1.0), 1e-12, "P = Kp(b r - y)")


func _windup_run(mode: PidController.AntiWindup) -> float:
	# Error of 10 for 100 ticks while clipped at 1, then error flips to -1.
	var pid := _make_pid(0.0, 1.0, 0.0)
	pid.use_output_limits = true
	pid.output_min = -1.0
	pid.output_max = 1.0
	pid.anti_windup = mode
	pid.back_calculation_gain = 50.0
	for i in 100:
		pid.compute(10.0, 0.0, 0.01)
	return pid.get_term_contributions()["i"]


func test_anti_windup_modes() -> void:
	check_near(_windup_run(PidController.AntiWindup.NONE), 10.0, 1e-9, "no anti-windup winds up")
	var clamped := _windup_run(PidController.AntiWindup.CLAMPING)
	check_true(clamped <= 1.0 + 0.1 + 1e-9, "clamping stops near the limit (got %s)" % clamped)
	var back := _windup_run(PidController.AntiWindup.BACK_CALCULATION)
	check_true(back < 2.0, "back-calculation keeps the integral near the limit (got %s)" % back)


func test_isa_conversion() -> void:
	var pid := _make_pid(2.0, 4.0, 0.5)
	check_near(pid.get_integral_time(), 0.5, 1e-12, "Ti = Kp/Ki")
	check_near(pid.get_derivative_time(), 0.25, 1e-12, "Td = Kd/Kp")
	pid.integral_gain = 0.0
	check_true(is_inf(pid.get_integral_time()), "Ti undefined without Ki")


func test_bumpless_transfer() -> void:
	var simulation := Simulation.new(FlywheelPlant.new(), ManualController.new())
	var manual := simulation.controller as ManualController
	manual.manual_command = 6.0
	simulation.step_many(500)
	var command_before := simulation.command
	# Small Ki so one tick of genuine integral action can't hide a bump.
	var pid := _make_pid(0.05, 0.001, 0.0)
	simulation.set_controller(pid)
	simulation.step_many(simulation.get_controller_period_steps())
	check_near(simulation.command, command_before, 0.1, "PID starts from the manual command")

	# Without Ki there is no bumpless preload (documented).
	var p_only := _make_pid(0.05, 0.0, 0.0)
	simulation.set_controller(p_only)
	check_near(p_only.get_term_contributions()["i"], 0.0, 1e-12, "no preload when Ki = 0")

	# PID -> Manual keeps the last command.
	var new_manual := ManualController.new()
	simulation.set_controller(new_manual)
	check_near(new_manual.manual_command, simulation.command, 1e-12, "manual starts at last command")
