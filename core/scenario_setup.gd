# scenario_setup.gd
#
# PURPOSE
#   Builds a ready-to-run Simulation from a Scenario, the ONE way it is done
#   everywhere: when the picker loads a scenario, when a challenge test runs
#   live, and when tests grade a challenge headless. Sharing this code is what
#   makes a challenge grade identical on every machine and in the tests.
#
# ORDER (it matters: later steps override earlier ones)
#   1. the plant's defaults and a PID with the plant's default gains/limits
#   2. plant-scaled defaults for setpoint, sensor/actuator and disturbances
#      (the panels' static apply_defaults(); data only, no UI is created)
#   3. the scenario's own overrides
class_name ScenarioSetup
extends RefCounted


# A PID with the plant's default gains and the input range as output limits.
static func make_pid(plant: Plant) -> PidController:
	var pid := PidController.new()
	var gains := plant.get_pid_gain_definitions()
	pid.proportional_gain = gains[0].default_value
	pid.integral_gain = gains[1].default_value
	pid.derivative_gain = gains[2].default_value
	pid.output_min = plant.get_input_definition().min_value
	pid.output_max = plant.get_input_definition().max_value
	return pid


# A cascade (outer + inner PID) with the plant's default cascade gains. The
# outer output is limited to ± the plant's inner setpoint limit, the inner
# to the input range. null if the plant has no inner loop.
static func make_cascade(plant: Plant) -> CascadeController:
	if plant.get_inner_definition() == null:
		return null
	var cascade := CascadeController.new()
	var gains: Array = plant.get_cascade_gain_definitions()
	for loop_index in 2:
		var pid: PidController = cascade.outer if loop_index == 0 else cascade.inner
		var trio: Array = gains[loop_index]
		pid.proportional_gain = (trio[0] as QuantityInfo).default_value
		pid.integral_gain = (trio[1] as QuantityInfo).default_value
		pid.derivative_gain = (trio[2] as QuantityInfo).default_value
	var limit := plant.get_inner_setpoint_limit()
	cascade.outer.output_min = -limit
	cascade.outer.output_max = limit
	cascade.inner.output_min = plant.get_input_definition().min_value
	cascade.inner.output_max = plant.get_input_definition().max_value
	return cascade


# `controller` is what drives the plant (manual or `pid`); `pid` receives the
# scenario's pid_settings either way.
static func build_simulation(scenario: Scenario, plant: Plant, controller: Controller,
		pid: PidController, random_seed: int, physics_rate_hz: float) -> Simulation:
	var simulation := Simulation.new(plant, controller)
	simulation.physics_rate_hz = physics_rate_hz
	simulation.random_seed = random_seed
	SetpointPanel.apply_defaults(simulation)
	NonidealityPanel.apply_defaults(simulation)
	DisturbancePanel.apply_defaults(simulation)
	scenario.apply_settings(simulation, pid)
	return simulation
