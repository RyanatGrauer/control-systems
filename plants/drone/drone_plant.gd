# drone_plant.gd
#
# PURPOSE
#   Plant #8: a quadcopter that can only move up and down. We control its
#   HEIGHT. Main lessons (README section 5): thrust can't go negative (the
#   rotors can only push up, so falling is gravity's job), hover feedforward
#   (it takes thrust = m·g just to stay put), and cascaded loops: an outer
#   height loop that asks an inner vertical-speed loop for a climb rate.
#
# MODEL (all SI units)
#       m·dv/dt = T - m·g - b·v - F_down
#       dh/dt = v
#   T = total rotor thrust [N] (the input, 0 to 25 N), m = mass [kg],
#   b = air drag [N·s/m], F_down = extra downward force (the disturbance,
#   e.g. a gust or a payload). The ground (h = 0) and a ceiling are hard
#   stops (Plant.apply_constraints).
#
#   Defaults: 1 kg, so hovering takes 9.81 N (the ideal kG).
#
# STATE
#   [0] height h (POSITION), [1] vertical velocity v (RATE)
class_name DronePlant
extends Plant

const GRAVITY: float = 9.81
const CEILING: float = 8.0  # TUNABLE: top hard stop [m]


func get_display_name() -> String:
	return "Drone altitude (1D)"


func get_description() -> String:
	return "Your controller sets the rotors' total thrust (it can only push UP; gravity pulls down). Goal: hover at the orange ghost height."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("mass", "Drone mass (m)", "kg") \
			.with_range(0.3, 2.0, 1.0) \
			.with_description("Heavier = more thrust needed just to hover."),
		QuantityInfo.new("drag", "Air drag (b)", "N·s/m") \
			.with_range(0.0, 3.0, 0.4) \
			.with_description("Air resistance that grows with vertical speed."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("height", "Height", "m") \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("velocity", "Vertical velocity", "m/s") \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("thrust", "Rotor thrust", "N") \
		.with_range(0.0, 25.0, 0.0) \
		.with_description("Total upward push of the four rotors. It can't pull down.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("height", "Height", "m") \
		.with_range(0.0, CEILING, 3.0)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("down_force", "Extra downward force", "N") \
		.with_range(-10.0, 10.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0])  # sitting on the landing pad


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var velocity := state[1]
	var mass: float = parameters["mass"]
	var thrust := maxf(applied_input, 0.0)  # rotors can't pull
	var acceleration: float = (thrust - mass * GRAVITY - parameters["drag"] * velocity - disturbance) / mass
	return PackedFloat64Array([velocity, acceleration])


# Ground and ceiling (inelastic: velocity into the stop -> 0).
func apply_constraints(state: PackedFloat64Array) -> PackedFloat64Array:
	if state[0] < 0.0:
		state[0] = 0.0
		state[1] = maxf(state[1], 0.0)
	elif state[0] > CEILING:
		state[0] = CEILING
		state[1] = minf(state[1], 0.0)
	return state


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(4.0, 100.0, 0.0, 50.0, 0.0, 50.0)


func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(2.0, 10.0, 2.0, 25.0)


func get_inner_definition() -> QuantityInfo:
	return QuantityInfo.new("velocity", "Vertical velocity", "m/s") \
		.with_range(-4.0, 4.0, 0.0)


func get_inner_output(state: PackedFloat64Array) -> float:
	return state[1]


# TUNABLE: cascade defaults. Outer: (m/s)/m; inner: N/(m/s).
func get_cascade_gain_definitions() -> Array:
	# The inner Ki learns the hover thrust, so the defaults fly (slowly);
	# an inner kG = m·g makes them much better.
	return make_cascade_gain_definitions([1.5, 20.0, 0.0, 10.0, 0.0, 5.0],
			[8.0, 100.0, 4.0, 100.0, 0.0, 10.0])


func get_inner_setpoint_limit() -> float:
	return 2.0  # TUNABLE: fastest climb/descent the outer loop may ask for [m/s]


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var m := get_parameter("mass")
	var v := state[1]
	var acceleration := compute_derivative(state, plant_input, disturbance, 0.0)[1]
	var ground := "  (on the ground)" if state[0] <= 0.0 else ""
	return "\n".join([
		"m·dv/dt = T - m·g - b·v - F_down",
		"%s·dv/dt = %s - %s - %s - %s" % [num(m), num(maxf(plant_input, 0.0)), num(m * GRAVITY),
			num(get_parameter("drag") * v), num(disturbance)],
		"dv/dt = %s m/s²   (h = %s m, v = %s m/s)%s" % [num(acceleration), num(state[0]),
			num(v), ground],
		"Hover thrust m·g = %s N" % num(get_hover_thrust()),
	])


func get_visual_scene_path() -> String:
	return "res://plants/drone/drone_visual.tscn"


func get_hover_thrust() -> float:
	return get_parameter("mass") * GRAVITY
