# integrators.gd
#
# PURPOSE
#   Fixed-step numerical integrators that advance a plant's state by one
#   physics substep (README section 4.2). We write our own instead of using
#   Godot's physics engine so results are deterministic and match the textbook.
#
# HOW IT FITS
#   Simulation.step_physics() calls Integrators.step(...) once per substep.
#   The applied input and disturbance are held constant during the substep
#   (zero-order hold), exactly like a real digital controller's output.
#
# AVAILABLE METHODS
#   RK4 (default)
#     Classic 4th-order Runge-Kutta. Very accurate: halving dt cuts the error
#     by about 16x. Tiny, slow energy drift over very long runs.
#   SEMI_IMPLICIT_EULER (a.k.a. symplectic Euler)
#     1st-order accurate, but for oscillators it keeps energy bounded forever
#     (it neither gains nor loses energy on average). Useful for showing the
#     class that "the integrator matters". On a 1st-order plant (no POSITION
#     components) it is identical to plain forward Euler.
class_name Integrators
extends RefCounted

enum Kind { RK4, SEMI_IMPLICIT_EULER }


static func get_kind_name(kind: Kind) -> String:
	match kind:
		Kind.RK4:
			return "RK4 (4th-order Runge-Kutta)"
		Kind.SEMI_IMPLICIT_EULER:
			return "Semi-implicit Euler"
	return "Unknown"


# Advance `state` by `dt` seconds using the chosen method. Returns a NEW array.
static func step(kind: Kind, plant: Plant, state: PackedFloat64Array,
		applied_input: float, disturbance: float, time: float,
		dt: float) -> PackedFloat64Array:
	match kind:
		Kind.SEMI_IMPLICIT_EULER:
			return semi_implicit_euler_step(plant, state, applied_input, disturbance, time, dt)
	return rk4_step(plant, state, applied_input, disturbance, time, dt)


# Classic RK4. With f(x, t) = plant derivative:
#   k1 = f(x,             t)
#   k2 = f(x + dt/2 * k1, t + dt/2)
#   k3 = f(x + dt/2 * k2, t + dt/2)
#   k4 = f(x + dt   * k3, t + dt)
#   x_next = x + dt/6 * (k1 + 2*k2 + 2*k3 + k4)
static func rk4_step(plant: Plant, state: PackedFloat64Array,
		applied_input: float, disturbance: float, time: float,
		dt: float) -> PackedFloat64Array:
	var half_dt := dt * 0.5
	var k1 := plant.compute_derivative(state, applied_input, disturbance, time)
	var k2 := plant.compute_derivative(add_scaled(state, k1, half_dt),
			applied_input, disturbance, time + half_dt)
	var k3 := plant.compute_derivative(add_scaled(state, k2, half_dt),
			applied_input, disturbance, time + half_dt)
	var k4 := plant.compute_derivative(add_scaled(state, k3, dt),
			applied_input, disturbance, time + dt)

	var next_state := PackedFloat64Array()
	next_state.resize(state.size())
	for i in state.size():
		next_state[i] = state[i] + dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return next_state


# Semi-implicit (symplectic) Euler.
#   Pass 1: update every RATE component (e.g. velocity) from the old state.
#   Pass 2: re-evaluate the derivative using the NEW rates, then update every
#           POSITION component (e.g. position) from that.
# For a spring this is:  v_next = v + dt * a(x);  x_next = x + dt * v_next
# Using the new velocity for the position update is what keeps energy bounded.
static func semi_implicit_euler_step(plant: Plant, state: PackedFloat64Array,
		applied_input: float, disturbance: float, time: float,
		dt: float) -> PackedFloat64Array:
	var kinds := plant.get_state_kinds()
	var next_state := state.duplicate()

	var derivative := plant.compute_derivative(state, applied_input, disturbance, time)
	for i in state.size():
		if kinds[i] != QuantityInfo.StateKind.POSITION:
			next_state[i] += dt * derivative[i]

	var derivative_with_new_rates := plant.compute_derivative(next_state,
			applied_input, disturbance, time)
	for i in state.size():
		if kinds[i] == QuantityInfo.StateKind.POSITION:
			next_state[i] += dt * derivative_with_new_rates[i]
	return next_state


# Returns base + scale * direction, element by element (a helper for RK4).
static func add_scaled(base: PackedFloat64Array, direction: PackedFloat64Array,
		scale: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(base.size())
	for i in base.size():
		result[i] = base[i] + scale * direction[i]
	return result
