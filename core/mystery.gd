# mystery.gd
#
# PURPOSE
#   "Mystery mode" (README section 5): every plant can have its parameters
#   randomized within a range and hidden, so students must tune by observing
#   the response, not by calculating from known values.
#
# METHOD
#   Each parameter is drawn independently from a seeded RNG:
#     default > 0:  default × SPREAD^u, u uniform in [-1, 1]  (log-uniform,
#                   so ×0.5 is as likely as ×2 with SPREAD = 2)
#     default = 0:  uniform in [min, min + ZERO_DEFAULT_FRACTION·(max - min)]
#   then clamped to the parameter's slider range. A plant can keep some
#   parameters fixed (Plant.get_mystery_fixed_keys()).
#   The same seed always gives the same mystery plant (README 4.1: seeded).
class_name Mystery
extends RefCounted

# TUNABLE: how far a mystery parameter may stray from its default.
const SPREAD: float = 2.0
const ZERO_DEFAULT_FRACTION: float = 0.3


static func make_parameters(plant: Plant, mystery_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = mystery_seed
	var fixed := plant.get_mystery_fixed_keys()
	var result := {}
	for info in plant.get_parameter_definitions():
		var draw := rng.randf_range(-1.0, 1.0)  # drawn even when unused: stable sequence
		if fixed.has(info.key):
			continue
		var value: float
		if info.default_value > 0.0:
			value = info.default_value * pow(SPREAD, draw)
		else:
			value = lerpf(info.min_value, lerpf(info.min_value, info.max_value, ZERO_DEFAULT_FRACTION),
					0.5 * (draw + 1.0))
		result[info.key] = clampf(value, info.min_value, info.max_value)
	return result
