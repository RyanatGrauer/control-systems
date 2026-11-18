# manual_controller.gd
#
# PURPOSE
#   "You are the controller." The command is whatever the student sets with the
#   slider or the keyboard. This is the first thing students do in most lessons:
#   feel how hard it is to hold a target by hand before seeing PID do it.
#
# HOW IT FITS
#   The UI writes `manual_command`; the Simulation reads it through compute()
#   on each controller tick, like any other controller. The UI never sets the
#   plant input directly.
class_name ManualController
extends Controller

var manual_command: float = 0.0  # in the plant's input units (SI), e.g. volts


func get_display_name() -> String:
	return "Manual (you are the controller)"


func compute(_setpoint: float, _measurement: float, _dt: float) -> float:
	return manual_command


func reset() -> void:
	manual_command = 0.0


# Bumpless transfer: keep sending whatever the previous controller sent.
func take_over(previous_command: float, _setpoint: float, _measurement: float) -> void:
	manual_command = previous_command


func get_equation_text(_setpoint: float, _measurement: float) -> String:
	return "u = your slider = %s\n(No equation: you are the controller.)" % \
			NumberFormat.significant(manual_command, 3)
