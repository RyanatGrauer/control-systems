# test_simulation_loop.gd
#
# Clock, determinism and rate independence (README 4.1, 4.5, 11).
extends TestCase

const ProportionalTestController = preload("res://tests/helpers/proportional_test_controller.gd")


# A small closed loop with a step setpoint and RNG noise in the controller.
func _make_loop(random_seed: int) -> Simulation:
	var controller := ProportionalTestController.new()
	var simulation := Simulation.new(FlywheelPlant.new(), controller)
	controller.rng = simulation.rng
	controller.noise_volts = 0.5
	controller.gain = 0.2
	simulation.setpoint_generator.start_time = 0.5
	simulation.setpoint_generator.target_level = 300.0
	simulation.random_seed = random_seed
	simulation.reset()
	return simulation


# Drive a simulation with a repeating pattern of frame times until it has
# taken exactly `target_steps` physics substeps.
func _run_with_frames(simulation: Simulation, frame_times: Array[float], target_steps: int) -> void:
	var clock := SimClock.new(simulation.get_physics_dt())
	var frame := 0
	while simulation.step_count < target_steps:
		var steps := clock.consume_frame(frame_times[frame % frame_times.size()])
		for i in steps:
			if simulation.step_count < target_steps:
				simulation.step_physics()
		frame += 1


func _recordings_identical(a: Simulation, b: Simulation) -> bool:
	if a.recorder.get_count() != b.recorder.get_count():
		return false
	for channel in Simulation.RECORDED_CHANNELS:
		for i in a.recorder.get_count():
			if a.recorder.get_value(channel, i) != b.recorder.get_value(channel, i):
				return false
	return true


func test_same_seed_gives_bit_identical_runs() -> void:
	var first := _make_loop(42)
	var second := _make_loop(42)
	first.step_many(3000)
	second.step_many(3000)
	check_true(_recordings_identical(first, second), "two runs with seed 42 differ")


func test_different_seed_gives_different_runs() -> void:
	var first := _make_loop(42)
	var second := _make_loop(43)
	first.step_many(3000)
	second.step_many(3000)
	check_true(not _recordings_identical(first, second), "seeds 42 and 43 should differ")


func test_reset_reproduces_the_run() -> void:
	var simulation := _make_loop(7)
	simulation.step_many(2000)
	var first_final := simulation.state[0]
	simulation.reset()
	simulation.step_many(2000)
	check_equal(simulation.state[0], first_final, "final speed after reset + rerun")


func test_results_do_not_depend_on_frame_rate() -> void:
	var patterns: Array = [
		[1.0 / 60.0] as Array[float],
		[1.0 / 144.0] as Array[float],
		[1.0 / 30.0] as Array[float],
		[0.004, 0.031, 0.017, 0.0005, 0.05] as Array[float],  # jittery frames
	]
	var reference_run := _make_loop(99)
	reference_run.step_many(3000)
	for pattern: Array[float] in patterns:
		var simulation := _make_loop(99)
		_run_with_frames(simulation, pattern, 3000)
		check_true(_recordings_identical(reference_run, simulation),
				"frame pattern %s changed the results" % [pattern])


func test_clock_counts_fixed_steps() -> void:
	var clock := SimClock.new(0.001)
	check_equal(clock.consume_frame(0.0105), 10, "10.5 ms -> 10 steps")
	check_equal(clock.consume_frame(0.0105), 11, "leftover 0.5 ms carries over")
	clock.set_time_scale(2.0)
	check_equal(clock.consume_frame(0.010), 20, "2x time scale doubles the steps")


func test_clock_caps_slow_frames() -> void:
	var clock := SimClock.new(0.001)
	var steps := clock.consume_frame(5.0)  # a 5-second hiccup
	check_equal(steps, SimClock.MAX_STEPS_PER_FRAME, "steps capped")
	check_true(clock.is_running_slow, "slow flag set")
	check_equal(clock.consume_frame(0.001), 1, "backlog dropped, normal next frame")
	check_true(not clock.is_running_slow, "slow flag cleared")


func test_clock_paused_takes_no_steps() -> void:
	var clock := SimClock.new(0.001)
	clock.is_paused = true
	check_equal(clock.consume_frame(0.1), 0, "no steps while paused")


func test_controller_runs_at_its_own_rate() -> void:
	# A 25 Hz controller (every 40 physics steps at 1 kHz) must hold its
	# command constant (zero-order hold) between ticks.
	var simulation := _make_loop(1)
	simulation.set_controller_rate_hz(25.0)
	check_equal(simulation.get_controller_period_steps(), 40, "period in steps")
	simulation.step_many(1)
	var held_command := simulation.command
	simulation.step_many(39)
	check_equal(simulation.command, held_command, "command held for 40 steps")
	simulation.step_many(1)
	check_true(simulation.command != held_command, "command updates on the next tick")
