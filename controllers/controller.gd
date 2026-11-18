# controller.gd
#
# PURPOSE
#   Base class (the "contract") for every controller: manual, PID, bang-bang...
#   A controller turns a setpoint and a measurement into a command.
#
# HOW IT FITS
#   Simulation calls compute() once per CONTROLLER tick (not every physics
#   substep). Between ticks the command is held (zero-order hold). A controller
#   never knows which plant it drives; it only sees numbers.
class_name Controller
extends RefCounted

# Set by Simulation before every compute(): how fast the (profiled) setpoint
# is moving, in the units feedforward needs (see Plant.output_is_rate()).
# Zero when there is no motion profile and the output is a position.
var reference_velocity: float = 0.0
var reference_acceleration: float = 0.0


func get_display_name() -> String:
	return "Controller"


# setpoint, measurement: in the plant's output units (SI)
# dt: seconds since the previous controller tick
# Returns the raw command u, before the actuator applies any limits.
func compute(_setpoint: float, _measurement: float, _dt: float) -> float:
	return 0.0


# Clear internal memory (integrators, previous error...) at the start of a run.
func reset() -> void:
	pass


# Called when this controller takes over a running loop from another one
# (e.g. Manual -> PID), right after reset(). Override to avoid a jump in the
# command ("bumpless transfer"). previous_command is the last command sent.
func take_over(_previous_command: float, _setpoint: float, _measurement: float) -> void:
	pass


# Each term's contribution from the most recent tick, for stacked plots.
# Keys used across the project: "p", "i", "d", "ff". Manual control has none.
func get_term_contributions() -> Dictionary:
	return {}
