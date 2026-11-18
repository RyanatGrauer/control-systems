# pid_controller.gd
#
# PURPOSE
#   The centerpiece controller (README 6.1): a discrete PID in PARALLEL form
#   (Kp, Ki, Kd) with switchable features. Every feature is OFF by default
#   (the plain textbook PID), so students can turn each one on and see what
#   problem it fixes.
#
# HOW IT FITS
#   Simulation calls compute() once per CONTROLLER tick with dt = controller
#   period. The command is then held until the next tick (zero-order hold).
#   Gains and switches are plain variables, so the UI can change them live.
#
# THE EXACT DISCRETE UPDATE (k = tick number, dt = controller period,
# r = setpoint, y = measurement)
#   e[k]   = r[k] - y[k]                                 error
#   P[k]   = Kp * (b*r[k] - y[k])                        b = 1 unless setpoint weighting
#   I[k]   = I[k-1] + Ki * e[k] * dt                     forward Euler (default)
#        or  I[k-1] + Ki * (e[k] + e[k-1])/2 * dt        trapezoidal
#   s[k]   = c*r[k] - y[k]                               the signal D acts on:
#            c = 1   derivative on ERROR (default; setpoint steps cause "derivative kick")
#            c = 0   derivative on MEASUREMENT (the fix)
#            c = weight   with setpoint weighting on
#   Draw[k] = Kd * (s[k] - s[k-1]) / dt                  (0 on the first tick)
#   D[k]   = Draw[k]                                     no filter (default)
#        or  D[k-1] + dt/(Tf + dt) * (Draw[k] - D[k-1])  first-order low-pass filter
#   FF[k]  = kS*sign(v) + kV*v + kA*a + kG (or kG*cos(y))   feedforward, if on;
#            v, a = reference velocity/acceleration from Simulation
#   sum[k] = P[k] + I[k] + D[k] + FF[k]                  before limits
#   u[k]   = clamp(sum[k], output_min, output_max)       if output limits are on
#
#   I[k] stores the already-multiplied-by-Ki sum, so changing Ki mid-run
#   changes how fast the integral grows FROM NOW ON without making u jump.
#
# ANTI-WINDUP (only matters while the output limits clip the command)
#   NONE              the integral keeps growing while clipped ("windup"): big
#                     overshoot once the output finally un-clips.
#   CLAMPING          conditional integration: skip the integral update on any
#                     tick where the output is clipped AND the error would push
#                     it further into the limit.
#   BACK_CALCULATION  bleed the integral toward the limit:
#                     I[k] += Kb * (u[k] - sum[k]) * dt, with tracking gain Kb [1/s].
#
# BUMPLESS TRANSFER
#   take_over() is called when switching from Manual to PID. It preloads the
#   integral so the first PID command equals the last manual command, so the
#   actuator doesn't jump. This needs an integral term, so it only happens
#   when Ki > 0 (with Ki = 0 a preloaded I term would never go away).
#
# ISA / STANDARD FORM (display only; same controller written another way)
#   u = Kp * (e + (1/Ti) * integral(e) + Td * de/dt),  Ti = Kp/Ki,  Td = Kd/Kp
class_name PidController
extends Controller

# Gains (parallel form). Units depend on the plant, e.g. for the flywheel
# Kp is in volts per (rad/s).
var proportional_gain: float = 1.0  # Kp
var integral_gain: float = 0.0      # Ki
var derivative_gain: float = 0.0    # Kd

enum AntiWindup { NONE, CLAMPING, BACK_CALCULATION }
enum IntegralMethod { FORWARD_EULER, TRAPEZOIDAL }

var use_output_limits: bool = true
var output_min: float = -1.0
var output_max: float = 1.0

# Switchable features (all off by default = textbook PID).
var derivative_on_measurement: bool = false
var derivative_filter_enabled: bool = false
var derivative_filter_tau: float = 0.02         # Tf [s]
var anti_windup: AntiWindup = AntiWindup.NONE
var back_calculation_gain: float = 10.0         # Kb [1/s]
var integral_method: IntegralMethod = IntegralMethod.FORWARD_EULER
var setpoint_weighting_enabled: bool = false
var proportional_setpoint_weight: float = 1.0   # b
var derivative_setpoint_weight: float = 1.0     # c

# Feedforward (stage 13): acts on the setpoint's motion, not on the error.
var feedforward_enabled: bool = false
var static_gain: float = 0.0          # kS
var velocity_gain: float = 0.0        # kV
var acceleration_gain: float = 0.0    # kA
var gravity_gain: float = 0.0         # kG
var gravity_uses_cosine: bool = false # kG * cos(measured angle), for arms

# Memory between ticks.
var _integral_term: float = 0.0     # I[k-1], already includes Ki
var _previous_error: float = 0.0    # e[k-1]
var _previous_d_signal: float = 0.0 # s[k-1]
var _filtered_d_term: float = 0.0   # D[k-1] (filtered)
var _has_previous_error: bool = false

# Contributions from the latest tick (for plots and the live term bars).
var _last_terms: Dictionary = {"p": 0.0, "i": 0.0, "d": 0.0, "ff": 0.0, "sum": 0.0}
var _is_clipped: bool = false       # did the last tick hit an output limit?


func get_display_name() -> String:
	return "PID"


func compute(setpoint: float, measurement: float, dt: float) -> float:
	var error := setpoint - measurement

	# P on the (optionally weighted) error.
	var b := proportional_setpoint_weight if setpoint_weighting_enabled else 1.0
	var p_term := proportional_gain * (b * setpoint - measurement)

	# D on the chosen signal, optionally low-pass filtered.
	var c := 1.0
	if derivative_on_measurement:
		c = 0.0
	elif setpoint_weighting_enabled:
		c = derivative_setpoint_weight
	var d_signal := c * setpoint - measurement
	var raw_d_term := 0.0
	if _has_previous_error and dt > 0.0:
		raw_d_term = derivative_gain * (d_signal - _previous_d_signal) / dt
	var d_term := raw_d_term
	if derivative_filter_enabled:
		_filtered_d_term += dt / (maxf(derivative_filter_tau, 0.0) + dt) \
				* (raw_d_term - _filtered_d_term)
		d_term = _filtered_d_term
	else:
		_filtered_d_term = raw_d_term

	var ff_term := compute_feedforward(measurement)

	# Candidate integral update.
	var averaged_error := error
	if integral_method == IntegralMethod.TRAPEZOIDAL and _has_previous_error:
		averaged_error = 0.5 * (error + _previous_error)
	var integral_increment := integral_gain * averaged_error * dt

	# Conditional integration: skip the update if it would wind further into a limit.
	if anti_windup == AntiWindup.CLAMPING and use_output_limits:
		var trial_sum := p_term + _integral_term + integral_increment + d_term + ff_term
		var pushes_up := trial_sum > output_max and integral_increment > 0.0
		var pushes_down := trial_sum < output_min and integral_increment < 0.0
		if pushes_up or pushes_down:
			integral_increment = 0.0
	_integral_term += integral_increment

	var total := p_term + _integral_term + d_term + ff_term
	var output := total
	if use_output_limits:
		output = clampf(total, output_min, output_max)
	_is_clipped = output != total

	# Back-calculation: pull the integral back by how far the sum overshot the limit.
	if anti_windup == AntiWindup.BACK_CALCULATION and use_output_limits:
		_integral_term += back_calculation_gain * (output - total) * dt

	_previous_error = error
	_previous_d_signal = d_signal
	_has_previous_error = true

	_last_terms = {"p": p_term, "i": _integral_term, "d": d_term, "ff": ff_term, "sum": total}
	return output


func compute_feedforward(measurement: float) -> float:
	if not feedforward_enabled:
		return 0.0
	var gravity := gravity_gain * (cos(measurement) if gravity_uses_cosine else 1.0)
	return static_gain * signf(reference_velocity) + velocity_gain * reference_velocity \
			+ acceleration_gain * reference_acceleration + gravity


# Bumpless transfer from manual (see header). Call right after reset().
func take_over(previous_command: float, setpoint: float, measurement: float) -> void:
	_previous_error = setpoint - measurement
	var c := 0.0 if derivative_on_measurement else 1.0
	if setpoint_weighting_enabled and not derivative_on_measurement:
		c = derivative_setpoint_weight
	_previous_d_signal = c * setpoint - measurement
	_has_previous_error = true
	_filtered_d_term = 0.0
	if integral_gain > 0.0:
		var b := proportional_setpoint_weight if setpoint_weighting_enabled else 1.0
		_integral_term = previous_command - proportional_gain * (b * setpoint - measurement) \
				- compute_feedforward(measurement)


func is_output_clipped() -> bool:
	return _is_clipped


# ISA/standard-form equivalents. INF when undefined (Ki = 0 or Kp = 0).
func get_integral_time() -> float:
	return proportional_gain / integral_gain if integral_gain > 0.0 else INF


func get_derivative_time() -> float:
	return derivative_gain / proportional_gain if proportional_gain > 0.0 else INF


func reset() -> void:
	_integral_term = 0.0
	_previous_error = 0.0
	_previous_d_signal = 0.0
	_filtered_d_term = 0.0
	_has_previous_error = false
	_is_clipped = false
	_last_terms = {"p": 0.0, "i": 0.0, "d": 0.0, "ff": 0.0, "sum": 0.0}


# "Reset integral" button: forget accumulated error without a full reset.
func reset_integral() -> void:
	_integral_term = 0.0


func get_term_contributions() -> Dictionary:
	return _last_terms
