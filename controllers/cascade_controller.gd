# cascade_controller.gd
#
# PURPOSE
#   Cascaded PID (README 6.2): two PIDs in series. The OUTER loop controls
#   the plant's output (e.g. drone height); its output is not a motor
#   command but the SETPOINT of the INNER loop, which controls a faster
#   quantity (e.g. vertical speed) and drives the actuator.
#
#       setpoint ──► outer PID ──► inner setpoint ──► inner PID ──► input
#                      ▲ output (height)                ▲ inner (speed)
#
#   Why: the inner loop fixes fast problems (gravity, thrust lag, a bump)
#   before the outer loop even notices, and the outer loop's output limit
#   becomes a clean speed limit. Rule of thumb: tune the inner loop first,
#   and make it several times faster than the outer loop.
#
# HOW IT FITS
#   Simulation sets `inner_measurement` (Plant.get_inner_output) just before
#   each compute(). Term contributions (plots, term bars) are the INNER
#   loop's, since those add up to the motor command; `inner_setpoint` is
#   recorded so both loops can be plotted.
#   Both PIDs are ordinary PidControllers: every PID feature works in each.
#   Feedforward (e.g. the drone's hover thrust kG) belongs on the INNER loop.
class_name CascadeController
extends Controller

var outer: PidController = PidController.new()
var inner: PidController = PidController.new()
var inner_measurement: float = 0.0  # set by Simulation every tick
var inner_setpoint: float = 0.0     # the outer loop's latest output


func get_display_name() -> String:
	return "Cascaded PID"


func compute(setpoint: float, measurement: float, dt: float) -> float:
	outer.reference_velocity = reference_velocity
	outer.reference_acceleration = reference_acceleration
	inner_setpoint = outer.compute(setpoint, measurement, dt)
	inner.reference_velocity = inner_setpoint  # kV on the inner loop: input per unit of inner target
	inner.reference_acceleration = 0.0
	inner.reference_gravity_angle = measurement  # kG·cos θ uses the ANGLE, not the speed
	return inner.compute(inner_setpoint, inner_measurement, dt)


func reset() -> void:
	outer.reset()
	inner.reset()
	inner_setpoint = 0.0


# Bumpless transfer from manual: the outer loop starts from the current
# inner measurement (no sudden speed demand), the inner from the last command.
func take_over(previous_command: float, setpoint: float, measurement: float) -> void:
	outer.take_over(inner_measurement, setpoint, measurement)
	inner.take_over(previous_command, inner_measurement, inner_measurement)


func get_term_contributions() -> Dictionary:
	return inner.get_term_contributions()


func is_output_clipped() -> bool:
	return inner.is_output_clipped()


# Both tunings, for snapshots and "was this run one tuning?" checks.
func get_tuning() -> Dictionary:
	return {"outer": outer.get_tuning(), "inner": inner.get_tuning()}


func apply_tuning(tuning: Dictionary) -> void:
	outer.apply_tuning(tuning.get("outer", {}))
	inner.apply_tuning(tuning.get("inner", {}))


func get_equation_text(setpoint: float, measurement: float) -> String:
	var n := func(value: float) -> String: return NumberFormat.significant(value, 3)
	return "\n".join([
		"Outer:  v_target = Kp·e + Ki·Σ(e·Δt) + Kd·Δe/Δt,  e = %s - %s = %s" % [n.call(setpoint),
			n.call(measurement), n.call(setpoint - measurement)],
		"        v_target = %s  (limited to ±%s)" % [n.call(inner_setpoint), n.call(outer.output_max)],
		"Inner:  u = Kp·e_v + Ki·Σ(e_v·Δt) + Kd·Δe_v/Δt,  e_v = %s - %s = %s" % [
			n.call(inner_setpoint), n.call(inner_measurement), n.call(inner_setpoint - inner_measurement)],
		"        u = P %s + I %s + D %s + FF %s" % [n.call(inner.get_term_contributions()["p"]),
			n.call(inner.get_term_contributions()["i"]), n.call(inner.get_term_contributions()["d"]),
			n.call(inner.get_term_contributions()["ff"])],
	])
