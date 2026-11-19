# zn_tuning.gd
#
# PURPOSE
#   The Ziegler–Nichols "ultimate gain" method (README 7.6 mode 3):
#     1. P only (Ki = Kd = 0). Raise Kp until the output swings with a
#        CONSTANT size: neither dying out nor growing. That Kp is the
#        ultimate gain Ku, and the swing's period is the ultimate period Tu.
#     2. Read the gains off a table.
#   judge() decides whether a measured swing is dying, steady or growing;
#   make_table() fills in the classic ZN rows and the gentler
#   Tyreus–Luyben rows, in parallel form (Kp, Ki = Kp/Ti, Kd = Kp·Td).
#
# WHY TWO TABLES
#   ZN was designed for "quarter-amplitude decay": each overshoot is 1/4 of
#   the one before. That's fast but very oscillatory (often ~50% overshoot).
#   Tyreus–Luyben (1992) uses a smaller Kp and a much longer Ti, trading
#   speed for calm. Students apply both and compare the ghosts.
class_name ZnTuning
extends RefCounted

enum Swing { NONE, DYING, STEADY, GROWING }

# TUNABLE: a swing is "steady" if the last cycle is within this factor of
# the first one (0.9-1.1 by default), measured over at least MIN_CYCLES.
const STEADY_TOLERANCE: float = 0.1
const MIN_CYCLES: int = 3

# [name, Kp/Ku, Ti/Tu (0 = no I), Td/Tu (0 = no D), note]
const RULES: Array = [
	["ZN  P", 0.5, 0.0, 0.0, "P only: keeps a steady-state error"],
	["ZN  PI", 0.45, 1.0 / 1.2, 0.0, "fast, overshoots"],
	["ZN  PID", 0.6, 0.5, 0.125, "quarter-decay: very aggressive"],
	["T-L  PI", 1.0 / 3.2, 2.2, 0.0, "Tyreus–Luyben: calmer"],
	["T-L  PID", 1.0 / 2.2, 2.2, 1.0 / 6.3, "Tyreus–Luyben: calmer"],
]


static func judge(oscillation: Oscillation) -> Swing:
	if oscillation.cycles < MIN_CYCLES:
		return Swing.NONE
	var growth := oscillation.get_growth()
	if growth < 1.0 - STEADY_TOLERANCE:
		return Swing.DYING
	if growth > 1.0 + STEADY_TOLERANCE:
		return Swing.GROWING
	return Swing.STEADY


# True if the input reached the PID's output limit or the actuator's
# saturation during the measured swing. Then the swing is a "limit cycle"
# shaped by the limit, not by the loop, and Ku comes out too high.
static func hits_input_limit(oscillation: Oscillation, pid: PidController,
		actuator: Actuator) -> bool:
	var limits: Array[Vector2] = []
	if pid.use_output_limits:
		limits.append(Vector2(pid.output_min, pid.output_max))
	if actuator.saturation_enabled:
		limits.append(Vector2(actuator.saturation_min, actuator.saturation_max))
	for limit in limits:
		var margin := 0.005 * (limit.y - limit.x)
		if oscillation.input_high >= limit.y - margin or oscillation.input_low <= limit.x + margin:
			return true
	return false


# Rows of {name, kp, ki, kd, note} in SI parallel form.
static func make_table(ultimate_gain: float, ultimate_period: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for rule: Array in RULES:
		var kp: float = rule[1] * ultimate_gain
		var integral_time: float = rule[2] * ultimate_period
		var derivative_time: float = rule[3] * ultimate_period
		rows.append({
			"name": rule[0],
			"kp": kp,
			"ki": kp / integral_time if integral_time > 0.0 else 0.0,
			"kd": kp * derivative_time,
			"note": rule[4],
		})
	return rows
