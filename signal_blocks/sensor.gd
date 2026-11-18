# sensor.gd
#
# PURPOSE
#   Turns the plant's TRUE output into the MEASUREMENT (y) the controller sees.
#
# HOW IT FITS
#   Simulation calls measure() once per controller tick. In Milestone A the
#   sensor is ideal (y = true output). Milestone C adds noise, quantization,
#   delay and a low-pass filter here, each with its own on/off switch. Any
#   randomness must come from the `rng` passed in (owned by the run), so a run
#   with the same seed is identical every time (README 4.5).
class_name Sensor
extends RefCounted


func measure(true_output: float, _time: float, _rng: RandomNumberGenerator) -> float:
	return true_output


func reset() -> void:
	pass
