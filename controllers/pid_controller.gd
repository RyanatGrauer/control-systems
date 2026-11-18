# pid_controller.gd
#
# PURPOSE
#   The centerpiece controller (README 6.1): a discrete PID in PARALLEL form
#   (Kp, Ki, Kd) with optional output limits. Advanced features (derivative on
#   measurement, derivative filter, anti-windup, setpoint weighting, ISA form,
#   feedforward) are added in Milestone C as on/off switches.
#
# HOW IT FITS
#   Simulation calls compute() once per CONTROLLER tick with dt = controller
#   period. The command is then held until the next tick (zero-order hold).
#   Gains are plain variables, so the UI can change them live while running.
#
# THE EXACT DISCRETE UPDATE (k = tick number, dt = controller period)
#   e[k]   = r[k] - y[k]                         error
#   P[k]   = Kp * e[k]                           proportional term
#   I[k]   = I[k-1] + Ki * e[k] * dt             integral term (forward Euler)
#   D[k]   = Kd * (e[k] - e[k-1]) / dt           derivative term (on error)
#            (D[0] = 0: there is no previous error on the first tick)
#   sum[k] = P[k] + I[k] + D[k]
#   u[k]   = clamp(sum[k], output_min, output_max)   if output limits are on
#
#   Note that I[k] stores the already-multiplied-by-Ki sum. That means changing
#   Ki during a run changes how fast the integral grows FROM NOW ON, without
#   making the output jump. (Storing the raw sum of errors and multiplying by Ki
#   later would make the output jump whenever Ki changes.)
#
#   Derivative on ERROR means a setpoint step causes a huge one-tick spike
#   ("derivative kick"). That is deliberate for now: stage 11 adds the
#   "derivative on measurement" fix as a toggle so students can see both.
#   This version has NO anti-windup, so when the output limits are hit the
#   integral keeps growing ("windup"). Stage 11 adds the fixes.
class_name PidController
extends Controller

# Gains (parallel form). Units depend on the plant, e.g. for the flywheel
# Kp is in volts per (rad/s).
var proportional_gain: float = 1.0  # Kp
var integral_gain: float = 0.0      # Ki
var derivative_gain: float = 0.0    # Kd

var use_output_limits: bool = true
var output_min: float = -1.0
var output_max: float = 1.0

# Memory between ticks.
var _integral_term: float = 0.0     # I[k-1], already includes Ki
var _previous_error: float = 0.0    # e[k-1]
var _has_previous_error: bool = false

# Contributions from the latest tick (for plots and the live term bars).
var _last_terms: Dictionary = {"p": 0.0, "i": 0.0, "d": 0.0, "ff": 0.0, "sum": 0.0}


func get_display_name() -> String:
	return "PID"


func compute(setpoint: float, measurement: float, dt: float) -> float:
	var error := setpoint - measurement

	var p_term := proportional_gain * error

	_integral_term += integral_gain * error * dt
	var i_term := _integral_term

	var d_term := 0.0
	if _has_previous_error and dt > 0.0:
		d_term = derivative_gain * (error - _previous_error) / dt
	_previous_error = error
	_has_previous_error = true

	var total := p_term + i_term + d_term
	var output := total
	if use_output_limits:
		output = clampf(total, output_min, output_max)

	_last_terms = {"p": p_term, "i": i_term, "d": d_term, "ff": 0.0, "sum": total}
	return output


func reset() -> void:
	_integral_term = 0.0
	_previous_error = 0.0
	_has_previous_error = false
	_last_terms = {"p": 0.0, "i": 0.0, "d": 0.0, "ff": 0.0, "sum": 0.0}


# "Reset integral" button: forget accumulated error without a full reset.
func reset_integral() -> void:
	_integral_term = 0.0


func get_term_contributions() -> Dictionary:
	return _last_terms
