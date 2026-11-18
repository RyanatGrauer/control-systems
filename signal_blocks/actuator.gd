# actuator.gd
#
# PURPOSE
#   Turns the controller's raw COMMAND (u) into the physical input actually
#   applied to the plant (u_applied).
#
# HOW IT FITS
#   Simulation calls apply() once per controller tick and then holds the result
#   until the next tick (zero-order hold). In Milestone A it is a pass-through.
#   Milestone C adds saturation, slew-rate limit, and deadband here.
class_name Actuator
extends RefCounted


func apply(command: float, _dt: float) -> float:
	return command


func reset() -> void:
	pass
