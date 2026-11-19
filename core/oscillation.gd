# oscillation.gd
#
# PURPOSE
#   Measures an oscillation in the recent past of a run: how many full
#   cycles, their period, and whether they are growing, steady or dying out.
#   Used by the lesson check "oscillating" and by the Ziegler–Nichols helper
#   (stage 22) to measure Tu.
#
# METHOD
#   Look at the true output over the last `window_s` seconds. Take the middle
#   of its range as the centre line. Count UPWARD crossings of the centre,
#   with hysteresis (the signal must first drop below centre - band) so
#   sensor-sized wiggles don't count. A cycle is the time between two upward
#   crossings. The period is the average cycle; the amplitude of each cycle
#   is half its peak-to-peak swing.
class_name Oscillation
extends RefCounted

# TUNABLE: a swing smaller than this fraction of the output range is "not
# oscillating" (noise, or a loop that has settled).
const MIN_SWING_FRACTION: float = 0.01

var cycles: int = 0
var period: float = NAN          # s
var first_amplitude: float = 0.0  # half peak-to-peak of the first full cycle
var last_amplitude: float = 0.0   # ... of the last full cycle
var crossing_times: PackedFloat64Array = []  # upward crossings (cycle starts), s
var low: float = 0.0   # range of the output in the window (SI)
var high: float = 0.0
var input_low: float = 0.0   # range of the applied input in the window (SI),
var input_high: float = 0.0  # if the recorder has "applied_input"


# last_amplitude / first_amplitude: about 1 = sustained, < 1 = dying out.
func get_growth() -> float:
	if cycles < 2 or first_amplitude <= 0.0:
		return NAN
	return last_amplitude / first_amplitude


static func analyze(recorder: RunRecorder, window_s: float, output_range: float) -> Oscillation:
	var result := Oscillation.new()
	var count := recorder.get_count()
	if count < 3:
		return result
	var end_time := recorder.get_value("time", count - 1)
	var first := count - 1
	while first > 0 and recorder.get_value("time", first - 1) >= end_time - window_s:
		first -= 1
	var lowest := INF
	var highest := -INF
	for i in range(first, count):
		var y := recorder.get_value("true_output", i)
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	result.low = lowest
	result.high = highest
	if recorder.has_channel("applied_input"):
		result.input_low = INF
		result.input_high = -INF
		for i in range(first, count):
			var u := recorder.get_value("applied_input", i)
			result.input_low = minf(result.input_low, u)
			result.input_high = maxf(result.input_high, u)
	var min_swing := MIN_SWING_FRACTION * absf(output_range)
	if highest - lowest < min_swing:
		return result
	var centre := 0.5 * (lowest + highest)
	var band := 0.25 * min_swing

	var crossings: PackedFloat64Array = []
	var amplitudes: PackedFloat64Array = []
	var armed := false  # true once the signal has been below centre - band
	var cycle_low := INF
	var cycle_high := -INF
	for i in range(first, count):
		var y := recorder.get_value("true_output", i)
		cycle_low = minf(cycle_low, y)
		cycle_high = maxf(cycle_high, y)
		if y < centre - band:
			armed = true
		elif armed and y > centre + band:
			armed = false
			if not crossings.is_empty():
				amplitudes.append(0.5 * (cycle_high - cycle_low))
			crossings.append(recorder.get_value("time", i))
			cycle_low = INF
			cycle_high = -INF
	result.crossing_times = crossings  # packed arrays copy on write: assign at the end
	result.cycles = amplitudes.size()
	if result.cycles >= 1:
		result.period = (crossings[crossings.size() - 1] - crossings[0]) / result.cycles
		result.first_amplitude = amplitudes[0]
		result.last_amplitude = amplitudes[amplitudes.size() - 1]
	return result
