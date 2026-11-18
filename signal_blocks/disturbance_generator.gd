# disturbance_generator.gd
#
# PURPOSE
#   Produces the disturbance d(t), an outside force/torque/heat load acting on
#   the plant, plus "parameter drift" (README 7.5, stage 14). Disturbance
#   rejection is a different job from setpoint tracking, and these make that
#   visible. Every source has its own on/off switch; all are OFF by default.
#
# HOW IT FITS
#   Simulation calls update() once per physics substep and adds the result to
#   the plant's disturbance input. Its units are the plant's disturbance units
#   (Plant.get_disturbance_definition()), e.g. N·m for the flywheel.
#
# SOURCES (they add up)
#   Step load      `step_load` applied from `step_time` onward.
#   Random load    a smoothly wandering random load (an Ornstein-Uhlenbeck
#                  process): x += -x*dt/tau + sigma*sqrt(2*dt/tau)*N(0,1).
#                  `random_std` is its typical size, `random_tau` how slowly it
#                  wanders. Drawn from the run's RNG, so it is reproducible.
#   Poke           poke() (a click on the plant view) applies `poke_strength`
#                  for `poke_duration` seconds. Not reproducible, since it
#                  depends on when the student clicks.
#   Parameter drift  at `drift_time`, plant parameter `drift_key` is multiplied
#                  by `drift_factor` (e.g. the mass doubles at t = 5 s), to show
#                  robustness. reset() puts the original value back.
class_name DisturbanceGenerator
extends RefCounted

var step_enabled: bool = false
var step_load: float = 0.0
var step_time: float = 3.0

var random_enabled: bool = false
var random_std: float = 0.0
var random_tau: float = 0.5   # seconds

var poke_strength: float = 0.0
var poke_duration: float = 0.2  # seconds  TUNABLE

var drift_enabled: bool = false
var drift_key: String = ""
var drift_factor: float = 2.0
var drift_time: float = 5.0

var _random_value: float = 0.0
var _poke_end_time: float = -1.0
var _poke_value: float = 0.0
var _drift_applied: bool = false
var _drift_original_value: float = 0.0


# Called by Simulation.reset(). Undoes any parameter drift from the last run.
func reset(plant: Plant) -> void:
	if _drift_applied and plant.parameters.has(drift_key):
		plant.set_parameter(drift_key, _drift_original_value)
	_drift_applied = false
	_random_value = 0.0
	_poke_end_time = -1.0


# Returns the total disturbance for the substep starting at `time`.
func update(time: float, dt: float, rng: RandomNumberGenerator, plant: Plant) -> float:
	var total := 0.0
	if step_enabled and time >= step_time:
		total += step_load

	if random_enabled and random_std > 0.0:
		var tau := maxf(random_tau, dt)
		_random_value += -_random_value * dt / tau \
				+ random_std * sqrt(2.0 * dt / tau) * rng.randfn(0.0, 1.0)
		total += _random_value

	if time < _poke_end_time:
		total += _poke_value

	if drift_enabled and not _drift_applied and time >= drift_time \
			and plant.parameters.has(drift_key):
		_drift_original_value = plant.get_parameter(drift_key)
		plant.set_parameter(drift_key, _drift_original_value * drift_factor)
		_drift_applied = true
	return total


# A short push (direction +1 or -1) starting now.
func poke(time: float, direction: float) -> void:
	_poke_value = poke_strength * signf(direction)
	_poke_end_time = time + poke_duration


func is_drift_applied() -> bool:
	return _drift_applied
