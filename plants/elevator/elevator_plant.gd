# elevator_plant.gd
#
# PURPOSE
#   Plant #5: a lift carriage on a vertical rail, pulled up by a motor and
#   down by gravity. We control its HEIGHT. Main lessons (README section 5):
#   gravity feedforward (kG), static friction (kS), and hard stops at the ends.
#   Like an FTC/FRC linear slide or elevator.
#
# MODEL (all SI units)
#   A DC motor (electrical time constant neglected) turning a spool. The motor
#   constant k [N/A] already includes the gearing and spool radius, so
#       force from motor   F_m = k * (V - k * v) / R      (back-EMF opposes V)
#       m * dv/dt = F_m - m*g - b*v - F_friction - F_load
#       dx/dt = v
#
#   Symbols: x = height [m], v = upward velocity [m/s], V = motor voltage [V]
#   (the input), m = carriage mass [kg], g = 9.81 m/s², R = resistance [ohm],
#   b = viscous friction [N·s/m], F_load = extra downward load [N] (the
#   disturbance).
#
#   Friction (Karnopp model, a standard way to simulate "sticking"):
#     moving (|v| > V_STICK):  F_friction = F_kinetic * sign(v)
#     stopped:                 friction cancels up to F_static of the other
#                              forces, so the carriage stays put until pushed
#                              hard enough. A small extra term brings the
#                              speed exactly to zero.
#
#   Hard stops (event logic, Plant.apply_constraints): the carriage can't go
#   below 0 m or above the rail height; hitting a stop kills the velocity.
#
#   Defaults: 5 kg, holding it up against gravity takes ~2.45 V (the ideal
#   kG), breaking static friction takes ~0.4 V more (kS), top speed ~1.2 m/s.
#
# STATE
#   [0] height x (POSITION), [1] velocity v (RATE)
class_name ElevatorPlant
extends Plant

const GRAVITY: float = 9.81
const RAIL_HEIGHT: float = 1.5       # TUNABLE: top hard stop [m]
const V_STICK: float = 0.002         # below this speed the carriage can stick [m/s]
const STICK_TIME_CONSTANT: float = 0.005  # how fast "stick" kills residual speed [s]


func get_display_name() -> String:
	return "Elevator / lift"


func get_description() -> String:
	return "Your controller sets the motor voltage that winds the cable up (gravity pulls the blue carriage down). Goal: hold the carriage at the orange ghost height."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("mass", "Carriage mass (m)", "kg") \
			.with_range(0.5, 20.0, 5.0) \
			.with_log_slider() \
			.with_description("Heavier = more voltage needed just to hold it up."),
		QuantityInfo.new("motor_constant", "Motor constant (k)", "N/A") \
			.with_range(2.0, 40.0, 10.0) \
			.with_log_slider() \
			.with_description("Force per amp at the cable, including gearing. Also sets top speed."),
		QuantityInfo.new("resistance", "Winding resistance (R)", "ohm") \
			.with_range(0.1, 5.0, 0.5) \
			.with_log_slider() \
			.with_description("Electrical resistance of the motor. Higher = less force."),
		QuantityInfo.new("static_friction", "Static friction", "N") \
			.with_range(0.0, 50.0, 8.0) \
			.with_description("Force needed to get the carriage moving from rest (it 'sticks')."),
		QuantityInfo.new("kinetic_friction", "Sliding friction", "N") \
			.with_range(0.0, 50.0, 5.0) \
			.with_description("Constant drag while the carriage is moving."),
		QuantityInfo.new("viscous_friction", "Viscous friction (b)", "N·s/m") \
			.with_range(0.0, 20.0, 1.0) \
			.with_description("Drag that grows with speed."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("height", "Height", "m") \
			.with_display("cm", 100.0) \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("velocity", "Velocity", "m/s") \
			.with_display("cm/s", 100.0) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("voltage", "Motor voltage", "V") \
		.with_range(-12.0, 12.0, 0.0) \
		.with_description("Positive winds the cable in (lifts the carriage).")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("height", "Carriage height", "m") \
		.with_range(0.0, RAIL_HEIGHT, 1.0) \
		.with_display("cm", 100.0)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("extra_load", "Extra load (down)", "N") \
		.with_range(-50.0, 50.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0])  # resting on the bottom stop


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var velocity := state[1]
	var mass: float = parameters["mass"]
	var motor_constant: float = parameters["motor_constant"]
	var resistance: float = parameters["resistance"]
	var viscous_friction: float = parameters["viscous_friction"]
	var static_limit: float = parameters["static_friction"]
	var kinetic_friction: float = parameters["kinetic_friction"]

	var motor_force := motor_constant * (applied_input - motor_constant * velocity) / resistance
	var other_forces := motor_force - mass * GRAVITY - disturbance \
			- viscous_friction * velocity

	var friction := 0.0
	if absf(velocity) > V_STICK:
		friction = kinetic_friction * signf(velocity)
	else:
		# Stuck: cancel up to the static limit, and damp out leftover speed.
		friction = clampf(other_forces + mass * velocity / STICK_TIME_CONSTANT,
				-static_limit, static_limit)

	var acceleration := (other_forces - friction) / mass
	return PackedFloat64Array([velocity, acceleration])


# Hard stops at the bottom and top of the rail (inelastic: velocity -> 0).
func apply_constraints(state: PackedFloat64Array) -> PackedFloat64Array:
	if state[0] < 0.0:
		state[0] = 0.0
		state[1] = maxf(state[1], 0.0)
	elif state[0] > RAIL_HEIGHT:
		state[0] = RAIL_HEIGHT
		state[1] = minf(state[1], 0.0)
	return state


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
# Kp = 10 V/m alone sags ~25 cm below the target: that gap is gravity, and
# a kG feedforward (stage 13) or Ki removes it.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(10.0, 200.0, 0.0, 200.0, 0.0, 50.0)


# TUNABLE: feedforward slider maxima. With the defaults the ideal values are
# kG ~ 2.45 V (get_hold_voltage()), kS ~ 0.4 V, kV ~ 10 V/(m/s), kA ~ 0.25 V/(m/s²).
func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(3.0, 30.0, 2.0, 12.0)


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var x := state[0]
	var v := state[1]
	var m := get_parameter("mass")
	var k := get_parameter("motor_constant")
	var r := get_parameter("resistance")
	var motor_force := k * (plant_input - k * v) / r
	var acceleration := compute_derivative(state, plant_input, disturbance, 0.0)[1]
	# Friction is whatever is left over (it depends on sticking/sliding).
	var friction := motor_force - m * GRAVITY - get_parameter("viscous_friction") * v \
			- disturbance - m * acceleration
	var stops := ""
	if x <= 0.0:
		stops = "  (resting on the bottom stop)"
	elif x >= RAIL_HEIGHT:
		stops = "  (against the top stop)"
	return "\n".join([
		"F_motor = k·(V - k·v)/R = %s·(%s - %s·%s)/%s = %s N" % [num(k), num(plant_input), num(k),
			num(v), num(r), num(motor_force)],
		"m·dv/dt = F_motor - m·g - b·v - F_friction - F_load",
		"%s·dv/dt = %s - %s - %s - %s - %s" % [num(m), num(motor_force), num(m * GRAVITY),
			num(get_parameter("viscous_friction") * v), num(friction), num(disturbance)],
		"dv/dt = %s m/s²   (x = %s m, v = %s m/s)%s" % [num(acceleration), num(x), num(v), stops],
	])


func get_visual_scene_path() -> String:
	return "res://plants/elevator/elevator_visual.tscn"


# --- analytic helpers ---

# Voltage that exactly holds the carriage still against gravity (ideal kG).
func get_hold_voltage() -> float:
	return get_parameter("mass") * GRAVITY * get_parameter("resistance") \
			/ get_parameter("motor_constant")
