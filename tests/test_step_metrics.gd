# test_step_metrics.gd
#
# Metrics on synthetic signals with known answers (README 11).
extends TestCase

const DT: float = 0.001


# Builds arrays for a response that starts at t = 0 with setpoint `target`.
func _analyze(duration: float, target: float, response: Callable, input_value: float = 0.0) -> StepMetrics:
	var times := PackedFloat64Array()
	var setpoints := PackedFloat64Array()
	var outputs := PackedFloat64Array()
	var inputs := PackedFloat64Array()
	var count := roundi(duration / DT) + 1
	for i in count:
		var t := i * DT
		times.append(t)
		setpoints.append(target)
		outputs.append(response.call(t))
		inputs.append(input_value)
	return StepMetrics.analyze_arrays(times, setpoints, outputs, inputs)


func test_first_order_response() -> void:
	# y = 1 - exp(-t/tau): rise (10-90%) = tau*ln(9), settling (2%) = tau*ln(50),
	# no overshoot, IAE = tau.
	var tau := 0.5
	var metrics := _analyze(6.0, 1.0, func(t: float) -> float: return 1.0 - exp(-t / tau))
	check_true(metrics.has_step, "has step")
	check_near(metrics.rise_time, tau * log(9.0), 2.0 * DT, "rise time")
	check_near(metrics.settling_time, tau * log(50.0), 2.0 * DT, "settling time")
	check_near(metrics.overshoot_percent, 0.0, 1e-9, "overshoot")
	check_near(metrics.integral_abs_error, tau, 0.002, "IAE")
	check_near(metrics.steady_state_error, 0.0, 1e-4, "steady-state error")


func test_underdamped_overshoot() -> void:
	# Second-order step response, zeta = 0.3: overshoot = exp(-pi*zeta/sqrt(1-zeta^2)).
	var zeta := 0.3
	var wn := 5.0
	var wd := wn * sqrt(1.0 - zeta * zeta)
	var response := func(t: float) -> float:
		return 1.0 - exp(-zeta * wn * t) * (cos(wd * t) + zeta / sqrt(1.0 - zeta * zeta) * sin(wd * t))
	var metrics := _analyze(10.0, 1.0, response)
	var expected_overshoot := exp(-PI * zeta / sqrt(1.0 - zeta * zeta)) * 100.0
	check_near(metrics.overshoot_percent, expected_overshoot, 0.05, "overshoot %")
	check_true(metrics.settling_time > 2.0 and metrics.settling_time < 3.2,
			"settling ~ 4/(zeta*wn) = 2.7 s, got %s" % metrics.settling_time)


func test_steady_state_error_and_no_rise() -> void:
	# Stops at 70% of the target: SS error 0.3, never reaches 90% -> no rise time,
	# never within 2% -> not settled.
	var metrics := _analyze(5.0, 1.0, func(t: float) -> float: return 0.7 * (1.0 - exp(-t / 0.2)))
	check_near(metrics.steady_state_error, 0.3, 1e-4, "steady-state error")
	check_true(is_nan(metrics.rise_time), "no rise time")
	check_true(is_nan(metrics.settling_time), "not settled")


func test_effort_and_peak() -> void:
	var metrics := _analyze(2.0, 1.0, func(_t: float) -> float: return 1.0, -3.0)
	check_near(metrics.peak_abs_input, 3.0, 1e-12, "peak |u|")
	check_near(metrics.effort, 18.0, 0.01, "integral of u^2 over 2 s")


func test_measures_from_last_setpoint_change() -> void:
	# Setpoint 0 until t = 1, then 2. Output jumps to 1 at t = 1.5, then 2 at t = 2.
	var times := PackedFloat64Array()
	var setpoints := PackedFloat64Array()
	var outputs := PackedFloat64Array()
	var inputs := PackedFloat64Array()
	for i in 4001:
		var t := i * DT
		times.append(t)
		setpoints.append(0.0 if t < 1.0 else 2.0)
		outputs.append(0.0 if t < 1.5 else (1.0 if t < 2.0 else 2.0))
		inputs.append(0.0)
	var metrics := StepMetrics.analyze_arrays(times, setpoints, outputs, inputs)
	check_near(metrics.step_time, 1.0, DT, "step time")
	check_near(metrics.step_size, 2.0, 1e-12, "step size")
	check_near(metrics.rise_time, 0.5, 2.0 * DT, "rise from 10% (t=1.5) to 90% (t=2)")
	check_near(metrics.settling_time, 1.0, 2.0 * DT, "settles at t = 2, 1 s after the step")


func test_moving_setpoint_has_no_step() -> void:
	var metrics := _analyze(0.0, 1.0, func(_t: float) -> float: return 0.0)
	check_true(not metrics.has_step, "single sample: no step")
	var times := PackedFloat64Array()
	var ramp := PackedFloat64Array()
	var zeros := PackedFloat64Array()
	for i in 1000:
		times.append(i * DT)
		ramp.append(i * DT)
		zeros.append(0.0)
	metrics = StepMetrics.analyze_arrays(times, ramp, zeros, zeros)
	check_true(not metrics.has_step, "ramp: no step")
	check_near(metrics.integral_abs_error, 0.5, 0.002, "IAE of a ramp error over 1 s")


func test_no_steady_state_error_while_still_oscillating() -> void:
	# Lightly damped: after 3 s it still swings far more than 4% of the step.
	var response := func(t: float) -> float: return 1.0 - exp(-0.2 * t) * cos(6.0 * t)
	var metrics := _analyze(3.0, 1.0, response)
	check_true(is_nan(metrics.steady_state_error), "SS error hidden while oscillating, got %s" % metrics.steady_state_error)
