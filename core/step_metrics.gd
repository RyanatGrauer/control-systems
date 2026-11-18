# step_metrics.gd
#
# PURPOSE
#   Measures how good a response is (README stage 7): rise time, overshoot,
#   settling time, steady-state error, IAE, and control effort.
#
# HOW IT FITS
#   analyze_recorder() reads the RunRecorder (it never touches the live
#   simulation). The UI calls it a few times per second and shows the numbers
#   under the plots. analyze_arrays() does the real work on plain arrays, so
#   the tests can feed it synthetic signals with known answers.
#
# WHICH PART OF THE RUN IS MEASURED
#   The metrics describe the response to the MOST RECENT setpoint change:
#   the segment from the last time the setpoint changed to the newest sample.
#   (A square wave is therefore measured edge by edge.) If the setpoint never
#   changed in the recording, the whole recording is used.
#     step size   delta = r_final - y(t0)   (target minus where the output started)
#     "progress"  (y - y(t0)) / delta       0 at the start, 1 on target
#   If the setpoint is still moving (ramp, sine), there is no constant segment
#   long enough to call a step; then only IAE and effort are reported, over the
#   whole recording.
#
# DEFINITIONS (standard textbook ones, measured against the SETPOINT)
#   Rise time        time from 10% to 90% progress. Measured against the
#                    setpoint, so a P-only loop that stops short of 90% has
#                    no rise time. That is part of the lesson.
#   Overshoot        how far past the target the output went, as % of delta.
#   Settling time    time after t0 until the output stays within +/-2% of delta
#                    around the target. Not settled if it is outside at the end.
#   Steady-state err mean of (r - y) over the last 0.5 s. Only reported once the
#                    output is steady (it moved less than 4% of delta in
#                    that window) and there is >= 1 s of data; while it is
#                    still swinging, "steady-state" has no meaning yet.
#   IAE              integral of |r - y| dt (smaller is better).
#   Peak |u|         largest applied input magnitude.
#   Effort           integral of u^2 dt (how hard the actuator worked).
#   Values that cannot be measured are NAN; the UI shows them as "-".
class_name StepMetrics
extends RefCounted

# TUNABLE: metric definitions.
const RISE_LOW_FRACTION: float = 0.1
const RISE_HIGH_FRACTION: float = 0.9
const SETTLING_BAND_FRACTION: float = 0.02
const STEADY_STATE_WINDOW_S: float = 0.5
const MIN_STEP_SEGMENT_S: float = 0.2   # shorter "constant" segments are not steps
const MIN_STEADY_STATE_DATA_S: float = 1.0
const STEADY_MOTION_FRACTION: float = 0.04  # max output movement allowed in the window

var has_step: bool = false      # false: only IAE / effort are meaningful
var step_time: float = 0.0      # t0, where the measured segment starts
var step_size: float = 0.0      # delta (SI)
var rise_time: float = NAN
var overshoot_percent: float = NAN
var settling_time: float = NAN
var steady_state_error: float = NAN
var integral_abs_error: float = 0.0
var peak_abs_input: float = 0.0
var effort: float = 0.0


# Reads the recorder's "time", "setpoint", "true_output", "applied_input".
# True output (not the possibly-noisy measurement) is graded, because it is
# what the physical system really did.
static func analyze_recorder(recorder: RunRecorder) -> StepMetrics:
	var count := recorder.get_count()
	var times := PackedFloat64Array()
	var setpoints := PackedFloat64Array()
	var outputs := PackedFloat64Array()
	var inputs := PackedFloat64Array()
	times.resize(count)
	setpoints.resize(count)
	outputs.resize(count)
	inputs.resize(count)
	for i in count:
		times[i] = recorder.get_value("time", i)
		setpoints[i] = recorder.get_value("setpoint", i)
		outputs[i] = recorder.get_value("true_output", i)
		inputs[i] = recorder.get_value("applied_input", i)
	return analyze_arrays(times, setpoints, outputs, inputs)


static func analyze_arrays(times: PackedFloat64Array, setpoints: PackedFloat64Array,
		outputs: PackedFloat64Array, inputs: PackedFloat64Array) -> StepMetrics:
	var result := StepMetrics.new()
	var count := times.size()
	if count < 2:
		return result

	# Find the start of the last constant-setpoint segment.
	var start := count - 1
	while start > 0 and setpoints[start - 1] == setpoints[start]:
		start -= 1
	var segment_duration := times[count - 1] - times[start]
	result.has_step = segment_duration >= MIN_STEP_SEGMENT_S
	if not result.has_step:
		start = 0  # setpoint still moving: measure IAE/effort over everything
	result.step_time = times[start]

	# IAE and effort over the measured segment (rectangle rule).
	for i in range(start, count - 1):
		var dt := times[i + 1] - times[i]
		result.integral_abs_error += absf(setpoints[i] - outputs[i]) * dt
		result.effort += inputs[i] * inputs[i] * dt
	for i in range(start, count):
		result.peak_abs_input = maxf(result.peak_abs_input, absf(inputs[i]))

	if not result.has_step:
		return result

	var target := setpoints[count - 1]
	var initial_output := outputs[start]
	result.step_size = target - initial_output
	if absf(result.step_size) < 1e-12:
		result.has_step = false  # already on target: nothing to measure
		return result

	_measure_rise_and_overshoot(result, times, outputs, start, initial_output)
	_measure_settling(result, times, outputs, start, target)
	_measure_steady_state(result, times, outputs, start, target)
	return result


static func _measure_rise_and_overshoot(result: StepMetrics, times: PackedFloat64Array,
		outputs: PackedFloat64Array, start: int, initial_output: float) -> void:
	var low_time := NAN
	var high_time := NAN
	var max_progress := -INF
	for i in range(start, times.size()):
		var progress := (outputs[i] - initial_output) / result.step_size
		max_progress = maxf(max_progress, progress)
		if is_nan(low_time) and progress >= RISE_LOW_FRACTION:
			low_time = times[i]
		if is_nan(high_time) and progress >= RISE_HIGH_FRACTION:
			high_time = times[i]
	if not is_nan(low_time) and not is_nan(high_time):
		result.rise_time = high_time - low_time
	result.overshoot_percent = maxf(max_progress - 1.0, 0.0) * 100.0


static func _measure_settling(result: StepMetrics, times: PackedFloat64Array,
		outputs: PackedFloat64Array, start: int, target: float) -> void:
	var band := SETTLING_BAND_FRACTION * absf(result.step_size)
	var last_outside := -1
	for i in range(start, times.size()):
		if absf(outputs[i] - target) > band:
			last_outside = i
	if last_outside == times.size() - 1:
		return  # still outside the band at the newest sample: not settled
	if last_outside < 0:
		result.settling_time = 0.0
	else:
		result.settling_time = times[last_outside + 1] - times[start]


static func _measure_steady_state(result: StepMetrics, times: PackedFloat64Array,
		outputs: PackedFloat64Array, start: int, target: float) -> void:
	var end_time := times[times.size() - 1]
	if end_time - times[start] < MIN_STEADY_STATE_DATA_S:
		return
	var total := 0.0
	var samples := 0
	var lowest := INF
	var highest := -INF
	for i in range(start, times.size()):
		if times[i] >= end_time - STEADY_STATE_WINDOW_S:
			total += target - outputs[i]
			samples += 1
			lowest = minf(lowest, outputs[i])
			highest = maxf(highest, outputs[i])
	if samples == 0:
		return
	if highest - lowest > STEADY_MOTION_FRACTION * absf(result.step_size):
		return  # still moving: not steady yet
	result.steady_state_error = total / samples
