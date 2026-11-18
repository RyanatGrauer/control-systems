# actuator.gd
#
# PURPOSE
#   Turns the controller's raw COMMAND (u) into the physical input actually
#   applied to the plant (u_applied), with optional real-world limits
#   (README 7.5). Each has an on/off switch; all are OFF by default.
#
# HOW IT FITS
#   Simulation calls apply() once per controller tick and holds the result
#   until the next tick (zero-order hold). The difference between the
#   "Command" and "Applied" plot traces is exactly what happens here.
#
# ORDER OF EFFECTS
#   1. deadband    commands smaller than `deadband` in size do nothing
#                  (static friction or a motor driver that ignores tiny PWM)
#   2. saturation  clamp to [saturation_min, saturation_max] (e.g. +/-12 V battery)
#   3. slew limit  the output can change by at most slew_rate * dt per tick
#                  (e.g. a valve or a ramp-rate-limited motor driver)
class_name Actuator
extends RefCounted

var deadband_enabled: bool = false
var deadband: float = 0.0          # SI input units

var saturation_enabled: bool = false
var saturation_min: float = -1.0   # SI input units
var saturation_max: float = 1.0

var slew_enabled: bool = false
var slew_rate: float = 10.0        # SI input units per second

var is_saturated: bool = false     # true if the last apply() hit a limit (for UI highlights)

var _previous_output: float = 0.0


func apply(command: float, dt: float) -> float:
	var output := command
	if deadband_enabled and absf(output) < deadband:
		output = 0.0

	is_saturated = false
	if saturation_enabled:
		var clamped := clampf(output, saturation_min, saturation_max)
		is_saturated = clamped != output
		output = clamped

	if slew_enabled:
		var max_change := maxf(slew_rate, 0.0) * dt
		output = clampf(output, _previous_output - max_change, _previous_output + max_change)

	_previous_output = output
	return output


func reset() -> void:
	_previous_output = 0.0
	is_saturated = false
