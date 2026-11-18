# servo_plant.gd
#
# PURPOSE
#   Plant #4: a DC motor turning a pointer arm. We control its ANGLE (a servo).
#   Second order, with an integrator inside the plant (angle is the integral of
#   speed). Main lessons (README section 5): a "type 1" system has no
#   steady-state error with P alone (for a fixed target); position loops
#   behave very differently from the flywheel's speed loop; P alone rings, and
#   D is what calms it down. Encoder quantization arrives in Milestone C.
#
# MODEL (all SI units). The same DC motor equations as the flywheel, plus
# the angle:
#       current    i = (V - Ke * w) / R
#       J * dw/dt  = Kt * i - b * w - T_load
#       d(theta)/dt = w
#
#   Symbols: theta = arm angle [rad], w = angular velocity [rad/s],
#   V = motor voltage [V] (the input), J = inertia of motor + arm [kg·m²],
#   Kt = Ke = motor constant [N·m/A], R = resistance [ohm],
#   b = viscous friction [N·m·s/rad], T_load = disturbance torque [N·m].
#
#   Transfer function (Advanced Math): theta/V = K / (s * (tau*s + 1)) with
#   K = Kt/(Kt^2 + b*R) and tau = J*R/(Kt^2 + b*R).
#   Defaults: K ~ 9.8 rad/s per volt, tau ~ 2 s.
#
# STATE
#   [0] angle theta (POSITION), [1] angular velocity w (RATE)
class_name ServoPlant
extends Plant


func get_display_name() -> String:
	return "DC motor position (servo)"


func get_description() -> String:
	return "Your controller sets the motor voltage that turns the blue arm. Goal: point the arm at the orange ghost arm."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("inertia", "Arm + motor inertia (J)", "kg·m²") \
			.with_range(0.001, 0.1, 0.01) \
			.with_log_slider() \
			.with_description("How hard the arm is to start and stop turning."),
		QuantityInfo.new("torque_constant", "Motor constant (Kt = Ke)", "N·m/A") \
			.with_range(0.01, 0.5, 0.1) \
			.with_log_slider() \
			.with_description("Torque per amp. Also sets the back-EMF that limits top speed."),
		QuantityInfo.new("resistance", "Winding resistance (R)", "ohm") \
			.with_range(0.2, 10.0, 2.0) \
			.with_log_slider() \
			.with_description("Electrical resistance of the motor. Higher = less torque."),
		QuantityInfo.new("viscous_friction", "Viscous friction (b)", "N·m·s/rad") \
			.with_range(0.0, 0.01, 0.0001) \
			.with_description("Drag that grows with speed."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("angle", "Arm angle", "rad") \
			.with_display("deg", 180.0 / PI) \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("angular_velocity", "Arm speed", "rad/s") \
			.with_display("deg/s", 180.0 / PI) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("voltage", "Motor voltage", "V") \
		.with_range(-12.0, 12.0, 0.0) \
		.with_description("The voltage you apply to the motor. Positive turns it counter-clockwise.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("angle", "Arm angle", "rad") \
		.with_range(-PI, PI, PI / 2.0) \
		.with_display("deg", 180.0 / PI)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("load_torque", "Load torque", "N·m") \
		.with_range(-0.5, 0.5, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0])


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var angular_velocity := state[1]
	var inertia: float = parameters["inertia"]
	var torque_constant: float = parameters["torque_constant"]
	var resistance: float = parameters["resistance"]
	var viscous_friction: float = parameters["viscous_friction"]

	var current := (applied_input - torque_constant * angular_velocity) / resistance
	var motor_torque := torque_constant * current
	var friction_torque := viscous_friction * angular_velocity
	var angular_acceleration := (motor_torque - friction_torque - disturbance) / inertia
	return PackedFloat64Array([angular_velocity, angular_acceleration])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
# Kp = 2 V/rad alone rings for a long time (damping ratio ~0.08); Kd ~ 0.8 tames it.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(2.0, 100.0, 0.0, 100.0, 0.0, 10.0)


func get_visual_scene_path() -> String:
	return "res://plants/servo/servo_visual.tscn"


# --- analytic helpers ---

# Speed per volt K [rad/s/V] and mechanical time constant tau [s].
func get_velocity_gain() -> float:
	var kt := get_parameter("torque_constant")
	return kt / (kt * kt + get_parameter("viscous_friction") * get_parameter("resistance"))


func get_time_constant() -> float:
	var kt := get_parameter("torque_constant")
	var r := get_parameter("resistance")
	return get_parameter("inertia") * r / (kt * kt + get_parameter("viscous_friction") * r)
