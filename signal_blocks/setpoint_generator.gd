# setpoint_generator.gd
#
# PURPOSE
#   Produces the setpoint (reference, r) as a function of simulated time
#   (README 6.3).
#
# HOW IT FITS
#   Simulation asks for value_at(time) on every controller tick. The setpoint
#   panel (ui/setpoint_panel.gd) changes the fields below live.
#
# PATTERNS (all values SI; nothing happens before `start_time`, where the
# setpoint is `start_level`)
#   CONSTANT  r = target_level at all times (start_time is ignored).
#   STEP      jumps from start_level to target_level at start_time.
#   SQUARE    from start_time, alternates target_level / start_level every half
#             period: the first half period is at target_level.
#   RAMP      from start_time, moves from start_level toward target_level at
#             ramp_rate (units per second), then holds target_level.
#   SINE      from start_time, r = target_level + amplitude * sin(2*pi*(t - start_time)/period).
#             The sine is centred on target_level.
#   (Trapezoidal motion profiles and mouse-drag setpoints come in later stages.)
class_name SetpointGenerator
extends RefCounted

enum Pattern { CONSTANT, STEP, SQUARE, RAMP, SINE }

var pattern: Pattern = Pattern.STEP
var start_level: float = 0.0   # SI, before start_time (and the "low" of a square wave)
var target_level: float = 0.0  # SI, the main target
var start_time: float = 0.0    # seconds
var period: float = 4.0        # seconds, for SQUARE and SINE
var ramp_rate: float = 1.0     # SI units per second (always positive), for RAMP
var amplitude: float = 0.0     # SI, for SINE


static func get_pattern_name(which: Pattern) -> String:
	match which:
		Pattern.CONSTANT:
			return "Constant"
		Pattern.STEP:
			return "Step"
		Pattern.SQUARE:
			return "Square wave"
		Pattern.RAMP:
			return "Ramp"
		Pattern.SINE:
			return "Sine wave"
	return "Unknown"


func value_at(time: float) -> float:
	if pattern == Pattern.CONSTANT:
		return target_level
	if time < start_time:
		return start_level

	var elapsed := time - start_time
	match pattern:
		Pattern.STEP:
			return target_level
		Pattern.SQUARE:
			# Which half-period are we in? Even halves = target, odd = start.
			var half_period := maxf(period * 0.5, 1e-6)
			var half_index := floori(elapsed / half_period)
			return target_level if half_index % 2 == 0 else start_level
		Pattern.RAMP:
			var distance := target_level - start_level
			var travelled := minf(ramp_rate * elapsed, absf(distance))
			return start_level + signf(distance) * travelled
		Pattern.SINE:
			return target_level + amplitude * sin(TAU * elapsed / maxf(period, 1e-6))
	return target_level
