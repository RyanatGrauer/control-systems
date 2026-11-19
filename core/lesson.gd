# lesson.gd
#
# PURPOSE
#   A guided lesson (README 7.6 mode 2), attached to a Scenario and edited in
#   the inspector: which controls are hidden or locked, and the step-by-step
#   prompts. Example: "Set Ki and Kd to 0. Raise Kp until it oscillates."
#
# HOW IT FITS
#   main_screen.gd shows a Lesson tab (first tab) with the current step and
#   Back / Next buttons, hides the `hidden_controls`, greys out the
#   `locked_controls`, and saves progress per lesson (save.lessons[title]).
#   A step's `unlock_controls` give controls back from that step on, so a
#   lesson can reveal Ki only once P has been explored.
#
# CONTROL NAMES (keys of CONTROL_NAMES). Anything else is reported as a
# problem and fails the scenario tests.
class_name Lesson
extends Resource

const CONTROL_NAMES: Dictionary = {
	"controller_mode": "the Manual / PID menu",
	"kp": "the Kp slider",
	"ki": "the Ki slider",
	"kd": "the Kd slider",
	"output_limits": "the PID output-limit checkbox",
	"feedforward": "the Feedforward section",
	"advanced_pid": "the Advanced PID section",
	"snapshots": "the Snapshots section",
	"setpoint": "the Setpoint section and the setpoint bar (and the S key)",
	"sensor_actuator": "the Sensor & actuator section",
	"disturbances": "the Disturbances section",
	"plant_parameters": "the Plant parameters section",
	"simulation_settings": "the Simulation settings section",
	"poke": "clicking the plant to poke it",
}

## Controls that are not shown at all.
@export var hidden_controls: Array[String] = []
## Controls that are shown but can't be changed (greyed out).
@export var locked_controls: Array[String] = []
@export var steps: Array[LessonStep] = []


func find_problems() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if steps.is_empty():
		problems.append("lesson has no steps")
	for name: String in hidden_controls + locked_controls:
		if not CONTROL_NAMES.has(name):
			problems.append("lesson: unknown control '%s'" % name)
	for i in steps.size():
		var step := steps[i]
		if step == null:
			problems.append("lesson step %d is empty" % (i + 1))
			continue
		if not LessonChecks.CHECKS.has(step.check):
			problems.append("lesson step %d: unknown check '%s'" % [i + 1, step.check])
		for name in step.unlock_controls:
			if not CONTROL_NAMES.has(name):
				problems.append("lesson step %d: unknown control '%s'" % [i + 1, name])
	return problems


# Hidden controls while step `step_index` is shown (unlocks are cumulative).
func get_hidden(step_index: int) -> PackedStringArray:
	return _minus_unlocked(hidden_controls, step_index)


func get_locked(step_index: int) -> PackedStringArray:
	return _minus_unlocked(locked_controls, step_index)


func _minus_unlocked(names: Array[String], step_index: int) -> PackedStringArray:
	var unlocked := {}
	for i in mini(step_index + 1, steps.size()):
		if steps[i] != null:
			for name in steps[i].unlock_controls:
				unlocked[name] = true
	var result: PackedStringArray = PackedStringArray()
	for name in names:
		if not unlocked.has(name):
			result.append(name)
	return result
