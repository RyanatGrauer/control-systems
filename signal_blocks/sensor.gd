# sensor.gd
#
# PURPOSE
#   Turns the plant's TRUE output into the MEASUREMENT (y) the controller sees,
#   with optional real-world problems (README 7.5). Each problem has its own
#   on/off switch, and all are OFF by default (an ideal sensor).
#
# HOW IT FITS
#   - Simulation calls record_true_output() every physics substep (the delay
#     needs a history), and measure() once per controller tick.
#   - Randomness comes ONLY from the `rng` passed in, which the run owns, so the
#     same seed gives the same noise every time (README 4.5).
#
# ORDER OF EFFECTS (the order they happen in a real sensor)
#   1. delay         the reading is `delay_s` old (transport / processing lag)
#   2. noise         + Gaussian random error with standard deviation noise_std
#   3. quantization  rounded to the nearest multiple of `resolution`
#                    (e.g. an encoder can only count whole ticks)
#   4. low-pass      a first-order digital filter with time constant lowpass_tau:
#                       y_f[k] = y_f[k-1] + dt/(tau + dt) * (y[k] - y_f[k-1])
#                    It smooths noise but adds lag.
class_name Sensor
extends RefCounted

# TUNABLE: longest delay supported (seconds).
const MAX_DELAY_S: float = 2.0

var noise_enabled: bool = false
var noise_std: float = 0.0        # SI output units

var quantization_enabled: bool = false
var resolution: float = 1.0       # SI output units per count

var delay_enabled: bool = false
var delay_s: float = 0.05

var lowpass_enabled: bool = false
var lowpass_tau: float = 0.05     # seconds

var _physics_dt: float = 0.001
var _history: DelayLine = DelayLine.new(1)
var _filtered: float = 0.0
var _has_filtered: bool = false


# Called by Simulation.reset() so the delay line matches the physics rate.
func configure(physics_dt: float) -> void:
	_physics_dt = physics_dt
	_history = DelayLine.new(ceili(MAX_DELAY_S / physics_dt))
	reset()


func reset() -> void:
	_history.clear()
	_has_filtered = false
	_filtered = 0.0


# True when every effect is off (the measurement equals the true output).
func is_ideal() -> bool:
	return not (noise_enabled or quantization_enabled or delay_enabled or lowpass_enabled)


# Every physics substep: remember the true output for the delay.
func record_true_output(true_output: float) -> void:
	_history.push(true_output)


func measure(true_output: float, _time: float, rng: RandomNumberGenerator,
		controller_dt: float = 0.01) -> float:
	var value := true_output
	if delay_enabled:
		value = _history.read(roundi(clampf(delay_s, 0.0, MAX_DELAY_S) / _physics_dt))
	if noise_enabled and noise_std > 0.0:
		value += rng.randfn(0.0, noise_std)
	if quantization_enabled and resolution > 0.0:
		value = roundf(value / resolution) * resolution
	if lowpass_enabled:
		if not _has_filtered:
			_filtered = value
			_has_filtered = true
		_filtered += controller_dt / (maxf(lowpass_tau, 0.0) + controller_dt) * (value - _filtered)
		value = _filtered
	else:
		_has_filtered = false
	return value
