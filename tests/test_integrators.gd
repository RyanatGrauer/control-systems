# test_integrators.gd
#
# Integrator accuracy against exact (analytic) solutions (README 10.1, 11).
extends TestCase

const SpringTestPlant = preload("res://tests/helpers/spring_test_plant.gd")
const DecayTestPlant = preload("res://tests/helpers/decay_test_plant.gd")


# Run `steps` substeps of `kind` from the plant's initial state.
func _integrate(plant: Plant, kind: Integrators.Kind, dt: float, steps: int) -> PackedFloat64Array:
	var state := plant.get_initial_state()
	for i in steps:
		state = Integrators.step(kind, plant, state, 0.0, 0.0, i * dt, dt)
	return state


func test_rk4_undamped_spring_keeps_energy() -> void:
	var plant := SpringTestPlant.new()
	var initial_energy: float = plant.get_energy(plant.get_initial_state())
	# 10 full periods (period = 1 s) at 1 kHz.
	var state := _integrate(plant, Integrators.Kind.RK4, 0.001, 10000)
	var energy: float = plant.get_energy(state)
	check_near(energy / initial_energy, 1.0, 1e-8, "relative energy after 10 periods")
	check_near(state[0], 1.0, 1e-6, "position back at start after 10 periods")
	check_near(state[1], 0.0, 1e-5, "velocity back at zero after 10 periods")


func test_semi_implicit_euler_spring_energy_stays_bounded() -> void:
	# Symplectic Euler does not conserve energy exactly, but the error stays
	# small and does NOT grow over time (unlike forward Euler).
	var plant := SpringTestPlant.new()
	var initial_energy: float = plant.get_energy(plant.get_initial_state())
	var dt := 0.001
	var state := plant.get_initial_state()
	var worst_first_period := 0.0
	var worst_last_period := 0.0
	var steps := 100000  # 100 periods
	for i in steps:
		state = Integrators.step(Integrators.Kind.SEMI_IMPLICIT_EULER, plant, state,
				0.0, 0.0, i * dt, dt)
		var deviation := absf(plant.get_energy(state) / initial_energy - 1.0)
		if i < 1000:
			worst_first_period = maxf(worst_first_period, deviation)
		if i >= steps - 1000:
			worst_last_period = maxf(worst_last_period, deviation)
	check_true(worst_last_period < 0.01, "energy within 1%% after 100 periods (got %s)" % worst_last_period)
	check_near(worst_last_period, worst_first_period, worst_first_period * 0.05,
			"energy error in the last period matches the first period (no drift)")


func test_rk4_damped_spring_matches_analytic() -> void:
	var plant := SpringTestPlant.new()
	plant.set_parameter("damping", 1.0)  # c = 1, m = 1, k = 4 pi^2: underdamped
	var natural_frequency := sqrt(plant.get_parameter("stiffness") / plant.get_parameter("mass"))
	var damping_ratio := plant.get_parameter("damping") / (2.0 * sqrt(
			plant.get_parameter("stiffness") * plant.get_parameter("mass")))
	var damped_frequency := natural_frequency * sqrt(1.0 - damping_ratio * damping_ratio)
	var decay := damping_ratio * natural_frequency

	var dt := 0.001
	var steps := 2500  # t = 2.5 s
	var state := _integrate(plant, Integrators.Kind.RK4, dt, steps)
	var t := steps * dt
	# x(t) for x(0) = 1, v(0) = 0:
	var exact := exp(-decay * t) * (cos(damped_frequency * t)
			+ decay / damped_frequency * sin(damped_frequency * t))
	check_near(state[0], exact, 1e-9, "damped position at t = 2.5 s")


func test_rk4_exponential_decay_matches_exact() -> void:
	var plant := DecayTestPlant.new()
	var state := _integrate(plant, Integrators.Kind.RK4, 0.001, 1000)
	check_near(state[0], exp(-1.0), 1e-12, "x(1) = e^-1")


func test_rk4_error_shrinks_16x_when_dt_halves() -> void:
	# 4th-order method: error ~ dt^4, so halving dt divides the error by ~16.
	var plant := DecayTestPlant.new()
	var coarse_error := absf(_integrate(plant, Integrators.Kind.RK4, 0.1, 10)[0] - exp(-1.0))
	var fine_error := absf(_integrate(plant, Integrators.Kind.RK4, 0.05, 20)[0] - exp(-1.0))
	var ratio := coarse_error / fine_error
	check_true(ratio > 14.0 and ratio < 18.0, "RK4 error ratio should be ~16, got %s" % ratio)


func test_euler_error_shrinks_2x_when_dt_halves() -> void:
	# On a first-order plant semi-implicit Euler is plain Euler: error ~ dt.
	var plant := DecayTestPlant.new()
	var kind := Integrators.Kind.SEMI_IMPLICIT_EULER
	var coarse_error := absf(_integrate(plant, kind, 0.01, 100)[0] - exp(-1.0))
	var fine_error := absf(_integrate(plant, kind, 0.005, 200)[0] - exp(-1.0))
	var ratio := coarse_error / fine_error
	check_true(ratio > 1.9 and ratio < 2.1, "Euler error ratio should be ~2, got %s" % ratio)
