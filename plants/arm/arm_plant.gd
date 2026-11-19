# arm_plant.gd
#
# PURPOSE
#   Plant #6: a motor-driven arm swinging in a vertical plane, with a weight
#   at its tip. We control its ANGLE. Main lessons (README section 5):
#   gravity's pull changes with angle (cos θ), so the feedforward that holds
#   it must too (kG·cos θ); and gains that are "right" at one angle are wrong
#   at another. Like an FTC/FRC arm or a robot shoulder.
#
# MODEL (all SI units)
#   θ = angle from HORIZONTAL (0 = sticking straight out, +90° = straight up,
#   -90° = hanging down). A DC motor (electrical time constant neglected)
#   with motor constant k [N·m/A] (gearing included):
#       motor torque     τ_m = k·(V - k·ω)/R        (back-EMF opposes V)
#       gravity torque   τ_g = m·g·L·cos θ           (largest when horizontal)
#       J·dω/dt = τ_m - τ_g - b·ω - τ_load,   J = m·L² (weight at the tip)
#       dθ/dt = ω
#   Hard stops (Plant.apply_constraints) at -90° (resting, hanging down) and
#   +180°.
#
#   Defaults: 1 kg at 0.4 m. Holding it horizontal takes 3.92 N·m, i.e.
#   ~2.6 V: that's the ideal kG (get_hold_voltage()).
#
# STATE
#   [0] angle θ (POSITION), [1] angular velocity ω (RATE)
class_name ArmPlant
extends Plant

const GRAVITY: float = 9.81
const MIN_ANGLE: float = -PI / 2.0  # resting stop, hanging down
const MAX_ANGLE: float = PI         # TUNABLE: upper stop (pointing the other way)


func get_display_name() -> String:
	return "Rotating arm with gravity"


func get_description() -> String:
	return "Your controller sets the motor voltage that turns the blue arm; gravity pulls the weight down, hardest when the arm is level. Goal: hold the arm at the orange ghost."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("mass", "Tip mass (m)", "kg") \
			.with_range(0.1, 5.0, 1.0) \
			.with_log_slider() \
			.with_description("The weight at the end of the arm. Heavier = more torque to hold it up."),
		QuantityInfo.new("length", "Arm length (L)", "m") \
			.with_range(0.1, 1.0, 0.4) \
			.with_description("Longer = more gravity torque and more inertia."),
		QuantityInfo.new("motor_constant", "Motor constant (k)", "N·m/A") \
			.with_range(0.3, 5.0, 1.5) \
			.with_log_slider() \
			.with_description("Torque per amp at the arm, including gearing. Also sets top speed."),
		QuantityInfo.new("resistance", "Winding resistance (R)", "ohm") \
			.with_range(0.1, 5.0, 1.0) \
			.with_log_slider() \
			.with_description("Electrical resistance of the motor. Higher = less torque."),
		QuantityInfo.new("viscous_friction", "Joint friction (b)", "N·m·s/rad") \
			.with_range(0.0, 1.0, 0.05) \
			.with_description("Drag in the joint that grows with speed."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("angle", "Arm angle", "rad") \
			.with_display("deg", rad_to_deg(1.0)) \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("angular_velocity", "Angular velocity", "rad/s") \
			.with_display("deg/s", rad_to_deg(1.0)) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("voltage", "Motor voltage", "V") \
		.with_range(-12.0, 12.0, 0.0) \
		.with_description("Positive lifts the arm (counter-clockwise).")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("angle", "Arm angle", "rad") \
		.with_range(MIN_ANGLE, MAX_ANGLE, 0.0) \
		.with_display("deg", rad_to_deg(1.0))


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("extra_torque", "Extra load torque (down)", "N·m") \
		.with_range(-5.0, 5.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([MIN_ANGLE, 0.0])  # hanging on its stop


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var angle := state[0]
	var angular_velocity := state[1]
	var k: float = parameters["motor_constant"]
	var motor_torque: float = k * (applied_input - k * angular_velocity) / parameters["resistance"]
	var acceleration: float = (motor_torque - get_gravity_torque(angle)
			- parameters["viscous_friction"] * angular_velocity - disturbance) / get_inertia()
	return PackedFloat64Array([angular_velocity, acceleration])


func apply_constraints(state: PackedFloat64Array) -> PackedFloat64Array:
	if state[0] < MIN_ANGLE:
		state[0] = MIN_ANGLE
		state[1] = maxf(state[1], 0.0)
	elif state[0] > MAX_ANGLE:
		state[0] = MAX_ANGLE
		state[1] = minf(state[1], 0.0)
	return state


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(10.0, 200.0, 0.0, 200.0, 0.0, 20.0)


# TUNABLE: feedforward slider maxima. Ideal kG ~ 2.6 V with cos θ on.
func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(2.0, 5.0, 1.0, 12.0)


func get_inner_definition() -> QuantityInfo:
	return QuantityInfo.new("angular_velocity", "Angular velocity", "rad/s") \
		.with_range(-6.0, 6.0, 0.0) \
		.with_display("deg/s", rad_to_deg(1.0))


func get_inner_output(state: PackedFloat64Array) -> float:
	return state[1]


# TUNABLE: cascade defaults. Outer: (rad/s)/rad; inner: V/(rad/s).
func get_cascade_gain_definitions() -> Array:
	return make_cascade_gain_definitions([5.0, 50.0, 0.0, 50.0, 0.0, 5.0],
			[2.0, 50.0, 0.0, 200.0, 0.0, 5.0])


func get_inner_setpoint_limit() -> float:
	return 3.0  # TUNABLE: fastest swing the outer loop may ask for [rad/s]


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var theta := state[0]
	var omega := state[1]
	var k := get_parameter("motor_constant")
	var r := get_parameter("resistance")
	var motor_torque := k * (plant_input - k * omega) / r
	var acceleration := compute_derivative(state, plant_input, disturbance, 0.0)[1]
	return "\n".join([
		"τ_motor = k·(V - k·ω)/R = %s·(%s - %s·%s)/%s = %s N·m" % [num(k), num(plant_input),
			num(k), num(omega), num(r), num(motor_torque)],
		"τ_gravity = m·g·L·cos θ = %s·9.81·%s·cos(%s°) = %s N·m" % [num(get_parameter("mass")),
			num(get_parameter("length")), num(rad_to_deg(theta)), num(get_gravity_torque(theta))],
		"J·dω/dt = τ_motor - τ_gravity - b·ω - τ_load,   J = m·L² = %s kg·m²" % num(get_inertia()),
		"dω/dt = %s rad/s²   (θ = %s°, ω = %s rad/s)" % [num(acceleration),
			num(rad_to_deg(theta)), num(omega)],
	])


func get_visual_scene_path() -> String:
	return "res://plants/arm/arm_visual.tscn"


# --- analytic helpers ---

func get_inertia() -> float:
	return get_parameter("mass") * pow(get_parameter("length"), 2.0)


func get_gravity_torque(angle: float) -> float:
	return get_parameter("mass") * GRAVITY * get_parameter("length") * cos(angle)


# Voltage that holds the arm still when level (θ = 0): the ideal kG.
func get_hold_voltage() -> float:
	return get_gravity_torque(0.0) * get_parameter("resistance") / get_parameter("motor_constant")
