# test_challenges.gd
#
# PURPOSE
#   Challenge mode (README 7.6, stage 20): the grader on synthetic signals
#   with known answers, scoring, determinism, and that every challenge
#   shipped in scenarios/ is achievable (a reference tuning passes it) but
#   not trivial (the plant's default tuning fails it).
extends TestCase

# A tuning that passes each shipped challenge (found by grid search; see
# the stage 20 notes in docs/writing_a_scenario.md).
const REFERENCE_TUNINGS: Dictionary = {
	"Challenge: flywheel": {"proportional_gain": 1.0, "integral_gain": 1.0,
		"derivative_gain": 0.0, "anti_windup": PidController.AntiWindup.CLAMPING},
	"Challenge: servo": {"proportional_gain": 35.0, "integral_gain": 0.0,
		"derivative_gain": 4.0},
	"Challenge: elevator load": {"proportional_gain": 80.0, "integral_gain": 80.0,
		"derivative_gain": 2.5, "anti_windup": PidController.AntiWindup.CLAMPING},
}


func _challenge_scenarios() -> Array[Scenario]:
	var found: Array[Scenario] = []
	for scenario in ScenarioCatalog.load_all():
		if scenario.challenge != null:
			found.append(scenario)
	return found


func test_every_challenge_is_achievable_but_not_trivial() -> void:
	var scenarios := _challenge_scenarios()
	check_true(scenarios.size() >= 3, "challenge scenarios exist")
	for scenario in scenarios:
		check_true(REFERENCE_TUNINGS.has(scenario.title),
				"'%s' needs a reference tuning in this test" % scenario.title)
		if not REFERENCE_TUNINGS.has(scenario.title):
			continue
		var plant := scenario.create_plant()
		var tuning := ScenarioSetup.make_pid(plant).get_tuning()
		var default_result: ChallengeResult = ChallengeRunner.run(scenario, tuning)[0]
		check_true(not default_result.is_complete(), "%s: default gains must not pass" % scenario.title)
		tuning.merge(REFERENCE_TUNINGS[scenario.title], true)
		var result: ChallengeResult = ChallengeRunner.run(scenario, tuning)[0]
		for row in result.rows:
			check_true(row["passed"], "%s: reference tuning passes %s (got %s, limit %s)" % [
				scenario.title, row["key"], row["value"], row["limit"]])
		check_equal(result.get_score(), 100, "%s: reference scores 100" % scenario.title)


func test_runs_are_deterministic() -> void:
	var scenario := _challenge_scenarios()[0]
	var tuning := ScenarioSetup.make_pid(scenario.create_plant()).get_tuning()
	tuning.merge(REFERENCE_TUNINGS.get(scenario.title, {}), true)
	var first: ChallengeResult = ChallengeRunner.run(scenario, tuning)[0]
	var second: ChallengeResult = ChallengeRunner.run(scenario, tuning)[0]
	for i in first.rows.size():
		check_equal(first.rows[i]["value"], second.rows[i]["value"], "same value twice: " + first.rows[i]["key"])


# A hand-made recording: step 0 -> 1 at t = 1, output overshoots to 1.2 at
# t = 2, back on target from t = 3; a load at t = 5 knocks it to 0.9 until
# t = 6, then it recovers.
func _synthetic_recorder() -> RunRecorder:
	var recorder := RunRecorder.new(Simulation.RECORDED_CHANNELS, 2000)
	for i in 801:
		var t := i * 0.01
		var setpoint := 1.0 if t >= 1.0 else 0.0
		var output := 0.0
		if t >= 1.0 and t < 2.0:
			output = 1.2 * (t - 1.0)
		elif t >= 2.0 and t < 3.0:
			output = 1.2 - 0.2 * (t - 2.0)
		elif t >= 3.0:
			output = 1.0
		if t >= 5.0 and t < 6.0:
			output = 0.9
		recorder.record({"time": t, "setpoint": setpoint, "true_output": output,
			"measurement": output, "applied_input": 2.0 if t >= 1.0 else 0.0})
	return recorder


func test_grader_on_known_signal() -> void:
	var challenge := Challenge.new()
	challenge.duration_s = 8.0
	challenge.step_time_s = 1.0
	challenge.load_enabled = true
	challenge.load_time_s = 5.0
	challenge.specs = {"overshoot_percent": 25.0, "load_peak_error": 0.05,
		"load_recovery_s": 2.0, "peak_input": 2.0, "effort": 100.0}
	var result := ChallengeGrader.grade(challenge, _synthetic_recorder(), FlywheelPlant.new())
	var values := {}
	for row in result.rows:
		values[row["key"]] = row
	check_near(values["overshoot_percent"]["value"], 20.0, 0.5, "overshoot measured before the load")
	check_true(values["overshoot_percent"]["passed"], "20% <= 25% passes")
	check_near(values["load_peak_error"]["value"], 0.1, 1e-9, "worst error after the load")
	check_true(not values["load_peak_error"]["passed"], "0.1 > 0.05 fails")
	check_near(values["load_recovery_s"]["value"], 1.0, 0.011, "back inside the band 1 s after the load")
	check_near(values["peak_input"]["value"], 2.0, 1e-9, "peak input")
	check_near(values["effort"]["value"], 4.0 * 7.0, 0.05, "effort = u^2 x time")
	check_equal(result.get_passed_count(), 4, "4 of 5 pass")
	check_equal(result.get_score(), 80, "score is % of specs passed")
	check_equal(result.rows[0]["key"], "overshoot_percent", "rows in a fixed order")


func test_unmeasurable_values_fail() -> void:
	var challenge := Challenge.new()
	challenge.duration_s = 8.0
	challenge.load_enabled = true
	challenge.load_time_s = 5.0
	challenge.specs = {"load_recovery_s": 100.0}
	var recorder := RunRecorder.new(Simulation.RECORDED_CHANNELS, 2000)
	for i in 801:
		var t := i * 0.01
		recorder.record({"time": t, "setpoint": 1.0 if t >= 1.0 else 0.0,
			"true_output": (0.5 if t >= 5.0 else 1.0) if t >= 1.0 else 0.0, "applied_input": 0.0})
	var result := ChallengeGrader.grade(challenge, recorder, FlywheelPlant.new())
	check_true(is_nan(result.rows[0]["value"]), "never recovered -> no value")
	check_true(not result.rows[0]["passed"], "and that fails, whatever the limit")


func test_samples_after_the_end_are_ignored() -> void:
	var challenge := Challenge.new()
	challenge.duration_s = 4.0
	challenge.specs = {"peak_input": 1.0}
	var recorder := RunRecorder.new(Simulation.RECORDED_CHANNELS, 2000)
	for i in 801:
		var t := i * 0.01
		recorder.record({"time": t, "setpoint": 0.0, "true_output": 0.0,
			"applied_input": 5.0 if t > 4.5 else 0.5})
	var result := ChallengeGrader.grade(challenge, recorder, FlywheelPlant.new())
	check_near(result.rows[0]["value"], 0.5, 1e-9, "input after duration_s doesn't count")


func test_best_result_ordering() -> void:
	var result := ChallengeResult.new()
	result.rows = [{"passed": true}, {"passed": false}]
	result.iae = 2.0
	check_equal(result.get_score(), 50, "half")
	check_true(result.is_better_than(0, INF), "beats nothing")
	check_true(result.is_better_than(50, 3.0), "same score, lower IAE wins")
	check_true(not result.is_better_than(50, 1.0), "same score, higher IAE loses")
	check_true(not result.is_better_than(100, 9.0), "lower score loses")


func test_bad_challenge_data_is_reported() -> void:
	var challenge := Challenge.new()
	challenge.specs = {"overshot_percent": 5.0}
	challenge.duration_s = 0.5
	var problems := challenge.find_problems()
	check_true(problems.size() >= 2, "typo and bad duration both reported")
	check_true("overshot_percent" in problems[0], "names the typo")
