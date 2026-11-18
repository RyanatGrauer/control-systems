# spring_test_plant.gd
#
# PURPOSE
#   Test-only plant: a mass on a spring with optional damping,
#       m * x'' = -k * x - c * x' + u + d
#   With c = 0 (the default) its exact solution is x = x0 * cos(w t),
#   w = sqrt(k/m), and its energy E = 1/2 k x^2 + 1/2 m v^2 must stay
#   constant, which makes it ideal for checking integrators. With c > 0 the
#   damped analytic solution is used instead. Not shown in the app.
#
#   State: [0] position x (m, POSITION), [1] velocity v (m/s, RATE).
extends Plant


func get_display_name() -> String:
	return "Test: mass on a spring"


func get_parameter_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("mass", "Mass", "kg").with_range(0.1, 10.0, 1.0),
		# k = (2*pi)^2 gives w = 2*pi rad/s, i.e. a period of exactly 1 second.
		QuantityInfo.new("stiffness", "Spring stiffness", "N/m").with_range(1.0, 100.0, TAU * TAU),
		QuantityInfo.new("damping", "Damping", "N·s/m").with_range(0.0, 10.0, 0.0),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("position", "Position", "m").as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("velocity", "Velocity", "m/s").as_state(QuantityInfo.StateKind.RATE),
	]


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 0.0])


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var mass: float = parameters["mass"]
	var stiffness: float = parameters["stiffness"]
	var damping: float = parameters["damping"]
	var acceleration := (-stiffness * state[0] - damping * state[1]
			+ applied_input + disturbance) / mass
	return PackedFloat64Array([state[1], acceleration])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


func get_energy(state: PackedFloat64Array) -> float:
	var mass: float = parameters["mass"]
	var stiffness: float = parameters["stiffness"]
	return 0.5 * stiffness * state[0] * state[0] + 0.5 * mass * state[1] * state[1]
