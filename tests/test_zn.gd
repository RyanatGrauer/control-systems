# test_zn.gd
#
# PURPOSE
#   Ziegler–Nichols helper (stage 22): the table formulas, the dying /
#   steady / growing judgement, and a real ultimate-gain measurement on the
#   mass-spring-damper.
extends TestCase


func _sine_recorder(growth_per_s: float) -> RunRecorder:
	var recorder := RunRecorder.new(PackedStringArray(["time", "true_output"]), 5000)
	for i in 2000:
		var t := i * 0.005
		recorder.record({"time": t, "true_output": exp(growth_per_s * t) * sin(TAU * t / 0.5)})
	return recorder


func test_table_formulas() -> void:
	var rows := ZnTuning.make_table(10.0, 2.0)
	check_equal(rows.size(), 5, "five rules")
	# ZN PID: Kp = 0.6 Ku, Ti = Tu/2, Td = Tu/8.
	check_near(rows[2]["kp"], 6.0, 1e-9, "ZN PID Kp")
	check_near(rows[2]["ki"], 6.0, 1e-9, "ZN PID Ki = Kp/Ti = 6/1")
	check_near(rows[2]["kd"], 1.5, 1e-9, "ZN PID Kd = Kp*Td = 6*0.25")
	check_near(rows[1]["ki"], 0.45 * 10.0 / (2.0 / 1.2), 1e-9, "ZN PI Ki")
	check_equal(rows[0]["ki"], 0.0, "P rule has no I")
	# Tyreus–Luyben PID: Kp = Ku/2.2, Ti = 2.2 Tu, Td = Tu/6.3.
	check_near(rows[4]["kp"], 10.0 / 2.2, 1e-9, "T-L PID Kp")
	check_near(rows[4]["ki"], (10.0 / 2.2) / 4.4, 1e-9, "T-L PID Ki")
	check_near(rows[4]["kd"], (10.0 / 2.2) * 2.0 / 6.3, 1e-9, "T-L PID Kd")
	check_true(rows[4]["kp"] < rows[2]["kp"] and rows[4]["ki"] < rows[2]["ki"], "T-L is gentler than ZN")


func test_judge() -> void:
	check_equal(ZnTuning.judge(Oscillation.analyze(_sine_recorder(0.0), 10.0, 2.0)),
			ZnTuning.Swing.STEADY, "constant sine is steady")
	check_equal(ZnTuning.judge(Oscillation.analyze(_sine_recorder(-0.3), 10.0, 2.0)),
			ZnTuning.Swing.DYING, "decaying sine is dying")
	check_equal(ZnTuning.judge(Oscillation.analyze(_sine_recorder(0.2), 10.0, 20.0)),
			ZnTuning.Swing.GROWING, "growing sine is growing")
	var steady := Oscillation.analyze(_sine_recorder(0.0), 10.0, 2.0)
	check_near(steady.crossing_times[1] - steady.crossing_times[0], 0.5, 0.01, "crossings one period apart")


func test_mass_spring_ultimate_gain() -> void:
	var scenario: Scenario = load("res://scenarios/03_mass_spring_damper.tres")
	var results := {}
	for kp in [100.0, 1000.0]:
		var plant := scenario.create_plant()
		var pid := ScenarioSetup.make_pid(plant)
		var simulation := ScenarioSetup.build_simulation(scenario, plant, pid, pid, 1,
				Simulation.DEFAULT_PHYSICS_RATE_HZ)
		pid.proportional_gain = kp
		pid.integral_gain = 0.0
		pid.derivative_gain = 0.0
		simulation.reset()
		simulation.step_many(roundi(12.0 / simulation.get_physics_dt()))
		var output_info := plant.get_output_definition()
		results[kp] = Oscillation.analyze(simulation.recorder, 10.0,
				output_info.max_value - output_info.min_value)
	check_equal(ZnTuning.judge(results[100.0]), ZnTuning.Swing.DYING, "low Kp dies out")
	check_equal(ZnTuning.judge(results[1000.0]), ZnTuning.Swing.STEADY, "high Kp swings steadily")
	check_near(results[1000.0].period, 0.32, 0.03, "Tu of the mass-spring")


func test_saturated_swing_is_flagged() -> void:
	var recorder := RunRecorder.new(PackedStringArray(["time", "true_output", "applied_input"]), 3000)
	for i in 2000:
		var t := i * 0.005
		var u := clampf(80.0 * sin(TAU * t / 0.5), -50.0, 50.0)
		recorder.record({"time": t, "true_output": sin(TAU * t / 0.5), "applied_input": u})
	var oscillation := Oscillation.analyze(recorder, 10.0, 2.0)
	var pid := PidController.new()
	pid.use_output_limits = true
	pid.output_min = -50.0
	pid.output_max = 50.0
	var actuator := Actuator.new()
	check_true(ZnTuning.hits_input_limit(oscillation, pid, actuator), "clipped at the PID limit")
	pid.output_max = 100.0
	pid.output_min = -100.0
	check_true(not ZnTuning.hits_input_limit(oscillation, pid, actuator), "well inside a wider limit")
