# lesson_checks.gd
#
# PURPOSE
#   The checks a guided-lesson step can wait for (LessonStep.check), e.g.
#   "Kp is at least 0.5" or "the output oscillates for 3 cycles". evaluate()
#   returns "" when the check passes, or a short "waiting for ..." sentence
#   the Lesson tab shows the student.
#
# HOW IT FITS
#   Pure function of the simulation and the PID: main_screen.gd calls it
#   every frame (it is cheap except "oscillating", which scans 10 s of
#   samples), and tests/test_lessons.gd calls it headlessly.
#
# RUN-BASED CHECKS (overshoot, steady-state error, oscillating) only count a
# run that used the CURRENT tuning from t = 0 (run_is_clean), so a student
# has to press Reset to test new gains, just like a real step test.
class_name LessonChecks
extends RefCounted

# name -> [kind, text]. kind: "" (no value), "gain" (value in SI gain units),
# "s", "%", "output" (plant output units), "cycles".
const CHECKS: Dictionary = {
	"": ["", ""],
	"mode_pid": ["", "switch the controller to PID"],
	"mode_manual": ["", "switch the controller to Manual"],
	"kp_at_least": ["gain", "Kp at least %s"],
	"ki_at_least": ["gain", "Ki at least %s"],
	"kd_at_least": ["gain", "Kd at least %s"],
	"ki_zero": ["", "Ki set to 0"],
	"kd_zero": ["", "Kd set to 0"],
	"time_at_least": ["s", "let it run for %s"],
	"overshoot_at_least": ["%", "a run (from Reset) with at least %s overshoot"],
	"overshoot_at_most": ["%", "a run (from Reset) that settles with at most %s overshoot"],
	"steady_state_error_at_most": ["output", "a run (from Reset) that settles within %s of the target"],
	"oscillating": ["cycles", "a run (from Reset) that swings back and forth %s times"],
}
const GAIN_INDEX: Dictionary = {"kp_at_least": 0, "ki_at_least": 1, "kd_at_least": 2}
const OSCILLATION_WINDOW_S: float = 10.0  # TUNABLE

# Returns "" when `step` is satisfied, else what the student still has to do.
static func evaluate(step: LessonStep, simulation: Simulation, pid: PidController,
		is_pid_mode: bool, run_is_clean: bool) -> String:
	var value := step.check_value
	var met := false
	match step.check:
		"":
			met = true
		"mode_pid":
			met = is_pid_mode
		"mode_manual":
			met = not is_pid_mode
		"kp_at_least":
			met = pid.proportional_gain >= value
		"ki_at_least":
			met = pid.integral_gain >= value
		"kd_at_least":
			met = pid.derivative_gain >= value
		"ki_zero":
			met = pid.integral_gain == 0.0
		"kd_zero":
			met = pid.derivative_gain == 0.0
		"time_at_least":
			met = simulation.get_time() >= value
		"overshoot_at_least", "overshoot_at_most", "steady_state_error_at_most", "oscillating":
			if not (run_is_clean and is_pid_mode):
				return describe(step, simulation.plant) + "  (press Reset to test your gains)"
			met = _run_check(step, simulation)
	return "" if met else describe(step, simulation.plant)


static func _run_check(step: LessonStep, simulation: Simulation) -> bool:
	if step.check == "oscillating":
		var output_info := simulation.plant.get_output_definition()
		var oscillation := Oscillation.analyze(simulation.recorder, OSCILLATION_WINDOW_S,
				output_info.max_value - output_info.min_value)
		return oscillation.cycles >= roundi(step.check_value)
	var metrics := StepMetrics.analyze_recorder(simulation.recorder)
	match step.check:
		"overshoot_at_least":
			return metrics.overshoot_percent >= step.check_value  # NAN compares false
		"overshoot_at_most":
			# Only once the output has stopped moving (settled, or steady with
			# a P-only offset), or it would pass halfway up the rise.
			var finished := not is_nan(metrics.settling_time) \
					or not is_nan(metrics.steady_state_error)
			return finished and metrics.overshoot_percent <= step.check_value
		"steady_state_error_at_most":
			return metrics.steady_state_error <= step.check_value
	return false


# "Kp at least 0.5 V/(rad/s)", in the units the student sees.
static func describe(step: LessonStep, plant: Plant) -> String:
	var info: Array = CHECKS.get(step.check, ["", ""])
	var text: String = info[1]
	if not text.contains("%s"):
		return text
	var value := step.check_value
	var shown := ""
	match info[0]:
		"gain":
			var gain: QuantityInfo = plant.get_pid_gain_definitions()[GAIN_INDEX[step.check]]
			shown = "%s %s" % [NumberFormat.significant(gain.si_to_shown(value), 3),
					gain.get_shown_unit()]
		"output":
			var output_info := plant.get_output_definition()
			shown = "%s %s" % [NumberFormat.significant(absf(output_info.si_to_shown(value)
					- output_info.si_to_shown(0.0)), 3), output_info.get_shown_unit()]
		"s":
			shown = NumberFormat.significant(value, 3) + " s"
		"%":
			shown = NumberFormat.significant(value, 3) + "%"
		"cycles":
			shown = str(roundi(value))
	return text % shown
