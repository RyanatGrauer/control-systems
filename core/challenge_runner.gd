# challenge_runner.gd
#
# PURPOSE
#   Runs a challenge test start to finish without any UI (README 9: the
#   simulation runs headless). Used by the tests to prove that a challenge is
#   achievable and that the live run in the UI gets the same grade.
#
# HOW IT FITS
#   Builds the simulation with ScenarioSetup exactly like main_screen.gd does
#   for a live test, applies the student's PID tuning, then steps to the end.
class_name ChallengeRunner
extends RefCounted


# Also returns the finished simulation, for callers that want the recording.
static func run(scenario: Scenario, tuning: Dictionary) -> Array:
	var challenge := scenario.challenge
	var plant := scenario.create_plant()
	var pid := ScenarioSetup.make_pid(plant)
	var simulation := ScenarioSetup.build_simulation(scenario, plant, pid, pid,
			challenge.random_seed, Simulation.DEFAULT_PHYSICS_RATE_HZ)
	pid.apply_tuning(tuning)
	challenge.apply_to(simulation)
	simulation.reset()
	simulation.step_many(steps_to_finish(simulation, challenge))
	return [ChallengeGrader.grade(challenge, simulation.recorder, plant), simulation]


# Physics steps from the current time until the test's end time.
static func steps_to_finish(simulation: Simulation, challenge: Challenge) -> int:
	var remaining := challenge.duration_s - simulation.get_time()
	return maxi(ceili(remaining / simulation.get_physics_dt() - 1e-6), 0)
