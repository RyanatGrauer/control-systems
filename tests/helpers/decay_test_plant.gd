# decay_test_plant.gd
#
# PURPOSE
#   Test-only plant: exponential decay, x' = -rate * x.
#   Exact solution x(t) = x0 * exp(-rate * t), so integrator error can be
#   measured exactly. Not shown in the app.
#
#   State: [0] x (RATE kind, since it is a first-order system).
extends Plant


func get_display_name() -> String:
	return "Test: exponential decay"


func get_parameter_definitions() -> Array[QuantityInfo]:
	return [QuantityInfo.new("rate", "Decay rate", "1/s").with_range(0.0, 10.0, 1.0)]


func get_state_definitions() -> Array[QuantityInfo]:
	return [QuantityInfo.new("x", "x", "").as_state(QuantityInfo.StateKind.RATE)]


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([1.0])


func compute_derivative(state: PackedFloat64Array, _applied_input: float,
		_disturbance: float, _time: float) -> PackedFloat64Array:
	var rate: float = parameters["rate"]
	return PackedFloat64Array([-rate * state[0]])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]
