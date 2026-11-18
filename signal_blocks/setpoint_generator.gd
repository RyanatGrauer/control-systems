# setpoint_generator.gd
#
# PURPOSE
#   Produces the setpoint (reference, r) as a function of simulated time.
#
# HOW IT FITS
#   Simulation asks for value_at(time) on every controller tick.
#   Milestone A only needs a STEP: hold `initial_value` until `step_time`, then
#   jump to `final_value`. With step_time = 0 this is a constant target, which
#   the manual-control panel uses. Stage 8 adds square, ramp, and sine here.
class_name SetpointGenerator
extends RefCounted

var initial_value: float = 0.0  # SI, before the step
var final_value: float = 0.0    # SI, after the step
var step_time: float = 0.0      # seconds


func value_at(time: float) -> float:
	if time < step_time:
		return initial_value
	return final_value
