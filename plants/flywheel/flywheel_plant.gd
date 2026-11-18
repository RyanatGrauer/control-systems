# flywheel_plant.gd
#
# PURPOSE
#   Plant #1: a flywheel driven by a DC motor. We control its SPEED.
#   First-order system. Main lessons (README section 5): P alone leaves a
#   steady-state error, I removes it, and feedforward (kV) does most of the work.
#   Similar to an FTC/FRC shooter flywheel.
#
# MODEL (all SI units)
#   A DC motor with the electrical time constant neglected (it is ~1000x faster
#   than the mechanical one), driving inertia J with viscous friction b:
#
#       current         i = (V - Ke * w) / R          (back-EMF opposes voltage)
#       motor torque    T = Kt * i
#       J * dw/dt = T - b * w - T_load
#
#   Symbols: w = angular velocity [rad/s], V = motor voltage [V] (the input),
#   Kt = torque constant [N·m/A], Ke = back-EMF constant [V·s/rad]
#   (in SI units Ke equals Kt numerically, so we use one parameter for both),
#   R = winding resistance [ohm], b = viscous friction [N·m·s/rad],
#   T_load = disturbance load torque [N·m].
#
#   This is first order with time constant  tau = J*R / (Kt^2 + b*R)
#   and steady-state speed per volt          K   = Kt / (Kt^2 + b*R).
#   With the defaults: tau ~ 0.98 s, free speed at 12 V ~ 585 rad/s (~5600 RPM).
#
# STATE
#   [0] angular velocity w (rad/s). The wheel's angle is NOT a state here: the
#       visual tracks it for animation only.
class_name FlywheelPlant
extends Plant

const RAD_PER_S_TO_RPM: float = 60.0 / TAU


func get_display_name() -> String:
	return "Flywheel / DC motor speed"


func get_description() -> String:
	return "Your controller sets the motor voltage (yellow) that spins the wheel. Goal: keep the wheel at the target speed (orange)."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("inertia", "Flywheel inertia (J)", "kg·m²") \
			.with_range(0.00005, 0.01, 0.0004) \
			.with_log_slider() \
			.with_description("How hard the wheel is to speed up or slow down. Heavier wheel = slower response."),
		QuantityInfo.new("torque_constant", "Motor constant (Kt = Ke)", "N·m/A") \
			.with_range(0.005, 0.1, 0.02) \
			.with_log_slider() \
			.with_description("Torque per amp of current. It also sets the back-EMF, which limits top speed."),
		QuantityInfo.new("resistance", "Winding resistance (R)", "ohm") \
			.with_range(0.1, 10.0, 1.0) \
			.with_log_slider() \
			.with_description("Electrical resistance of the motor. Higher = less current and less torque."),
		QuantityInfo.new("viscous_friction", "Viscous friction (b)", "N·m·s/rad") \
			.with_range(0.0, 0.0005, 0.00001) \
			.with_description("Drag that grows with speed (bearings, air)."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("angular_velocity", "Wheel speed", "rad/s") \
			.with_range(-700.0, 700.0, 0.0) \
			.with_display("RPM", RAD_PER_S_TO_RPM) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("voltage", "Motor voltage", "V") \
		.with_range(-12.0, 12.0, 0.0) \
		.with_description("The voltage you apply to the motor. Positive spins it forward.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("angular_velocity", "Wheel speed", "rad/s") \
		.with_range(0.0, 600.0, 3000.0 / RAD_PER_S_TO_RPM) \
		.with_display("RPM", RAD_PER_S_TO_RPM)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("load_torque", "Load torque", "N·m") \
		.with_range(-0.2, 0.2, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0])


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var angular_velocity := state[0]
	var inertia: float = parameters["inertia"]
	var torque_constant: float = parameters["torque_constant"]
	var resistance: float = parameters["resistance"]
	var viscous_friction: float = parameters["viscous_friction"]

	var current := (applied_input - torque_constant * angular_velocity) / resistance
	var motor_torque := torque_constant * current
	var friction_torque := viscous_friction * angular_velocity
	var angular_acceleration := (motor_torque - friction_torque - disturbance) / inertia
	return PackedFloat64Array([angular_acceleration])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains and slider maxima for this plant.
# Every plant starts P-only so students add I and D themselves.
# Kp = 0.05 alone leaves ~30% steady-state error (the classic "P is not enough"
# lesson); Ki around 0.1 removes it.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(0.05, 5.0, 0.0, 10.0, 0.0, 0.05)


# The output (speed) is itself a velocity, so kV multiplies the speed setpoint.
func output_is_rate() -> bool:
	return true


# TUNABLE: feedforward slider maxima. Ideal kV = 1/K ~ 0.0205 V/(rad/s),
# ideal kA = J*R/Kt = 0.02 V/(rad/s²) with the default parameters.
func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(2.0, 0.1, 0.1, 12.0)


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var w := state[0]
	var j := get_parameter("inertia")
	var kt := get_parameter("torque_constant")
	var r := get_parameter("resistance")
	var b := get_parameter("viscous_friction")
	var current := (plant_input - kt * w) / r
	var acceleration := compute_derivative(state, plant_input, disturbance, 0.0)[0]
	return "\n".join([
		"i = (V - Kt·ω) / R",
		"   = (%s - %s·%s) / %s = %s A" % [num(plant_input), num(kt), num(w), num(r), num(current)],
		"J·dω/dt = Kt·i - b·ω - T_load",
		"%s·dω/dt = %s·%s - %s·%s - %s" % [num(j), num(kt), num(current), num(b), num(w), num(disturbance)],
		"dω/dt = %s rad/s²   (ω = %s rad/s = %s RPM)" % [num(acceleration), num(w),
			num(w * RAD_PER_S_TO_RPM)],
	])


func get_visual_scene_path() -> String:
	return "res://plants/flywheel/flywheel_visual.tscn"


# --- analytic helpers (used by tests and, later, by the Equations tab) ---

# Mechanical time constant tau [s].
func get_time_constant() -> float:
	var kt: float = parameters["torque_constant"]
	var r: float = parameters["resistance"]
	var b: float = parameters["viscous_friction"]
	var j: float = parameters["inertia"]
	return j * r / (kt * kt + b * r)


# Steady-state speed [rad/s] for a constant voltage and no load.
func get_steady_state_speed(voltage: float) -> float:
	var kt: float = parameters["torque_constant"]
	var r: float = parameters["resistance"]
	var b: float = parameters["viscous_friction"]
	return voltage * kt / (kt * kt + b * r)
