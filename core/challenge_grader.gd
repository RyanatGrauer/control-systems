# challenge_grader.gd
#
# PURPOSE
#   Grades a finished challenge run (README 7.6) from its recording. Pure
#   function of the recorder and the Challenge, so the live run in the UI and
#   a headless run in the tests are graded by exactly the same code.
#
# WHAT IS MEASURED (on the TRUE output, like the metrics bar)
#   Only samples up to duration_s count.
#   Step specs (rise, overshoot, settling, steady-state error, IAE) use
#   StepMetrics on the part of the run BEFORE the load switches on, so the
#   load doesn't spoil the step response (and vice versa).
#   Peak input and effort cover the whole test.
#   Load specs use the part from load_time_s on:
#     worst error  = max |setpoint - output|
#     recovery     = time from the load until the output is back within the
#                    2% band for good (band = 2% of the step size, or 2% of
#                    the output range if there was no step). NAN if it is
#                    still outside at the end.
class_name ChallengeGrader
extends RefCounted


static func grade(challenge: Challenge, recorder: RunRecorder, plant: Plant) -> ChallengeResult:
	var times := PackedFloat64Array()
	var setpoints := PackedFloat64Array()
	var outputs := PackedFloat64Array()
	var inputs := PackedFloat64Array()
	for i in recorder.get_count():
		var t := recorder.get_value("time", i)
		if t > challenge.duration_s + 1e-9:
			break
		times.append(t)
		setpoints.append(recorder.get_value("setpoint", i))
		outputs.append(recorder.get_value("true_output", i))
		inputs.append(recorder.get_value("applied_input", i))

	# Step part: everything before the load.
	var step_end := times.size()
	if challenge.load_enabled:
		step_end = times.bsearch(challenge.load_time_s)
	var step := StepMetrics.analyze_arrays(times.slice(0, step_end), setpoints.slice(0, step_end),
			outputs.slice(0, step_end), inputs.slice(0, step_end))

	var peak_input := 0.0
	var effort := 0.0
	for i in inputs.size():
		peak_input = maxf(peak_input, absf(inputs[i]))
		if i + 1 < times.size():
			effort += inputs[i] * inputs[i] * (times[i + 1] - times[i])

	var load_peak := NAN
	var load_recovery := NAN
	if challenge.load_enabled and step_end < times.size():
		var output_info := plant.get_output_definition()
		var band_size := absf(challenge.target_level - challenge.start_level)
		if band_size < 1e-12:
			band_size = output_info.max_value - output_info.min_value
		var band := band_size * StepMetrics.SETTLING_BAND_FRACTION
		load_peak = 0.0
		var last_outside := -1
		for i in range(step_end, times.size()):
			var error := absf(setpoints[i] - outputs[i])
			load_peak = maxf(load_peak, error)
			if error > band:
				last_outside = i
		if last_outside < 0:
			load_recovery = 0.0
		elif last_outside < times.size() - 1:
			load_recovery = times[last_outside + 1] - challenge.load_time_s

	var measured := {
		"rise_time_s": step.rise_time,
		"overshoot_percent": step.overshoot_percent if step.has_step else NAN,
		"settling_time_s": step.settling_time,
		"steady_state_error": absf(step.steady_state_error),
		"iae": step.integral_abs_error,
		"peak_input": peak_input,
		"effort": effort,
		"load_peak_error": load_peak,
		"load_recovery_s": load_recovery,
	}
	var result := ChallengeResult.new()
	result.iae = step.integral_abs_error
	for key: String in Challenge.SPEC_INFO:  # fixed order, whatever the file's order
		if not challenge.specs.has(key):
			continue
		var value: float = measured[key]
		var limit: float = challenge.specs[key]
		result.rows.append({"key": key, "title": Challenge.SPEC_INFO[key][0],
			"unit_kind": Challenge.SPEC_INFO[key][1], "limit": limit, "value": value,
			"passed": not is_nan(value) and value <= limit})
	return result
