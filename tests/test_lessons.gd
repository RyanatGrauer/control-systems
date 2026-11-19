# test_lessons.gd
#
# PURPOSE
#   Guided lessons (stage 21): the control-name and check-name validation,
#   cumulative unlocks, the oscillation measurement, and that every step of
#   the shipped lessons can actually be completed (a scripted "student"
#   plays each step headlessly).
extends TestCase


func _run(scenario: Scenario, kp: float, ki: float, kd: float, seconds: float) -> Simulation:
	var plant := scenario.create_plant()
	var pid := ScenarioSetup.make_pid(plant)
	var simulation := ScenarioSetup.build_simulation(scenario, plant, pid, pid, 1,
			Simulation.DEFAULT_PHYSICS_RATE_HZ)
	pid.proportional_gain = kp
	pid.integral_gain = ki
	pid.derivative_gain = kd
	simulation.reset()
	simulation.step_many(roundi(seconds / simulation.get_physics_dt()))
	return simulation


func _step_met(scenario: Scenario, index: int, gains: Array, seconds: float = 10.0) -> bool:
	var simulation := _run(scenario, gains[0], gains[1], gains[2], seconds)
	var step: LessonStep = scenario.lesson.steps[index]
	return LessonChecks.evaluate(step, simulation, simulation.controller as PidController,
			true, true) == ""


func test_flywheel_lesson_can_be_completed() -> void:
	var scenario: Scenario = load("res://scenarios/10_lesson_flywheel_pi.tres")
	check_true(scenario.lesson != null and scenario.lesson.find_problems().is_empty(), "lesson valid")
	check_true(not _step_met(scenario, 2, [0.05, 0.0, 0.0]), "starting Kp is below the step-3 target")
	check_true(_step_met(scenario, 2, [0.5, 0.0, 0.0]), "raising Kp passes step 3")
	check_true(not _step_met(scenario, 4, [0.5, 0.0, 0.0]), "P alone never closes the gap")
	check_true(_step_met(scenario, 4, [0.2, 0.2, 0.0]), "PI closes the gap")
	check_true(_step_met(scenario, 5, [0.2, 3.0, 0.0]), "big Ki overshoots")
	check_true(not _step_met(scenario, 6, [0.2, 3.0, 0.0]), "big Ki fails the gentle step")
	check_true(_step_met(scenario, 6, [0.2, 0.1, 0.0]), "small Ki passes the gentle step")


func test_msd_lesson_can_be_completed() -> void:
	var scenario: Scenario = load("res://scenarios/11_lesson_msd_d.tres")
	check_true(scenario.lesson != null and scenario.lesson.find_problems().is_empty(), "lesson valid")
	check_true(not _step_met(scenario, 0, [20.0, 0.0, 0.0]), "starting Kp doesn't bounce enough")
	check_true(_step_met(scenario, 0, [300.0, 0.0, 0.0]), "high Kp bounces")
	check_true(not _step_met(scenario, 2, [300.0, 0.0, 0.0]), "P alone overshoots")
	check_true(_step_met(scenario, 2, [1000.0, 0.0, 40.0]), "PD settles without overshoot")


func test_run_checks_need_a_clean_run() -> void:
	var scenario: Scenario = load("res://scenarios/11_lesson_msd_d.tres")
	var simulation := _run(scenario, 300.0, 0.0, 0.0, 10.0)
	var waiting := LessonChecks.evaluate(scenario.lesson.steps[0], simulation,
			simulation.controller as PidController, true, false)
	check_true(waiting.contains("Reset"), "asks for a Reset when the gains changed mid-run")


func test_unlocks_are_cumulative() -> void:
	var scenario: Scenario = load("res://scenarios/10_lesson_flywheel_pi.tres")
	var lesson := scenario.lesson
	check_true(lesson.get_locked(0).has("controller_mode"), "mode locked at step 1")
	check_true(not lesson.get_locked(1).has("controller_mode"), "mode unlocked at step 2")
	check_true(not lesson.get_locked(6).has("controller_mode"), "stays unlocked")
	check_true(lesson.get_locked(3).has("ki") and not lesson.get_locked(4).has("ki"), "Ki unlocks at step 5")
	check_true(lesson.get_hidden(6).has("kd"), "Kd stays hidden")


func test_bad_names_are_reported() -> void:
	var lesson := Lesson.new()
	lesson.hidden_controls = ["kp", "warp_drive"]
	var step := LessonStep.new()
	step.check = "kp_atleast"
	step.unlock_controls = ["ki", "nope"]
	lesson.steps = [step]
	var problems := "\n".join(lesson.find_problems())
	check_true(problems.contains("warp_drive"), "unknown hidden control")
	check_true(problems.contains("kp_atleast"), "unknown check")
	check_true(problems.contains("nope"), "unknown unlock")
	check_true(Lesson.new().find_problems().size() == 1, "empty lesson reported")


func test_oscillation_measures_a_sine() -> void:
	var recorder := RunRecorder.new(PackedStringArray(["time", "true_output"]), 5000)
	for i in 2000:
		var t := i * 0.005
		recorder.record({"time": t, "true_output": 2.0 + 0.5 * sin(TAU * t / 0.8)})
	var oscillation := Oscillation.analyze(recorder, 10.0, 4.0)
	check_true(oscillation.cycles >= 11, "about 12 cycles in 10 s")
	check_near(oscillation.period, 0.8, 0.01, "period")
	check_near(oscillation.last_amplitude, 0.5, 0.01, "amplitude")
	check_near(oscillation.get_growth(), 1.0, 0.02, "sustained")
	var flat := RunRecorder.new(PackedStringArray(["time", "true_output"]), 100)
	for i in 100:
		flat.record({"time": i * 0.01, "true_output": 1.0})
	check_equal(Oscillation.analyze(flat, 10.0, 4.0).cycles, 0, "flat line has no cycles")


func test_save_keeps_lesson_progress() -> void:
	var clean := SaveStore.validate({"schema_version": SaveStore.SCHEMA_VERSION,
		"lessons": {"Lesson: P and I": {"step": 3, "finished": false, "completed": true},
			"bad": {"step": "x"}}})
	check_equal(clean["lessons"]["Lesson: P and I"]["step"], 3, "step kept")
	check_equal(clean["lessons"]["Lesson: P and I"]["completed"], true, "completed kept")
	check_equal(clean["lessons"]["bad"]["step"], 0, "bad step defaulted")


# GODOT-VERSION (4.7.2): lesson lists written as PackedStringArray(...) in a
# sub-resource of a .tres loaded EMPTY in the exported Web build (they were
# fine in the editor). Array[String] fields work in both, so scenario data
# classes must not use exported PackedStringArrays.
func test_scenario_data_has_no_packed_string_arrays() -> void:
	for data: Object in [Scenario.new(), Challenge.new(), Lesson.new(), LessonStep.new()]:
		for property in data.get_property_list():
			if property["usage"] & PROPERTY_USAGE_STORAGE and property["type"] == TYPE_PACKED_STRING_ARRAY:
				check_true(false, "%s.%s: use Array[String]" % [data.get_script().get_global_name(), property["name"]])
	check_true(true, "checked")
