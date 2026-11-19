# scenario.gd
#
# PURPOSE
#   A scenario (README glossary, 9): one data file that bundles a plant, its
#   parameters, the starting controller and settings, and the teacher's
#   notes. Teachers make new ones in the Godot inspector WITHOUT writing code:
#   duplicate a file in res://scenarios/, open it, and edit the fields.
#   See docs/writing_a_scenario.md.
#
# HOW IT FITS
#   ScenarioCatalog lists the files; the toolbar's scenario picker loads one.
#   main_screen.gd then:
#     1. create_plant()                      plant + parameter overrides
#     2. builds a Simulation + controllers, and applies each panel's
#        plant-scaled defaults (e.g. NonidealityPanel.apply_defaults)
#     3. apply_settings()                    every other override below
#     4. builds the UI, which shows the resulting values.
#
# ALL NUMBERS ARE SI (rad/s, not RPM; m, not cm; °C for temperature). The
# override dictionaries use the exact variable names of the object they
# change, e.g. sensor_settings = { "noise_enabled": true, "noise_std": 5.0 }.
# An unknown name is reported as a warning (and fails the test suite), so
# typos never pass silently.
class_name Scenario
extends Resource

enum StartMode { MANUAL, PID, CASCADED_PID }  # CASCADED_PID: plants with an inner loop only

@export var title: String = "New scenario"
## The plant's physics script, e.g. res://plants/flywheel/flywheel_plant.gd
@export var plant_script: Script
## Shown in the Notes tab: what to try, in a few short lines.
@export_multiline var notes: String = ""
@export var start_mode: StartMode = StartMode.MANUAL
## Controller rate in Hz (the physics rate stays at its default).
@export var controller_rate_hz: float = Simulation.DEFAULT_CONTROLLER_RATE_HZ

# Optional: makes this scenario a challenge (Challenge tab + "Run test").
@export var challenge: Challenge
## Start with a mystery plant: random, hidden parameters (stage 24).
@export var mystery_mode: bool = false
# Optional: makes this scenario a guided lesson (Lesson tab, hidden/locked controls).
@export var lesson: Lesson

@export_group("Overrides (SI units, variable names)")
## Plant parameter key -> value, e.g. "inertia": 0.0008 (see the plant's get_parameter_definitions()).
@export var plant_parameters: Dictionary[String, float] = {}
## PidController variables, e.g. "proportional_gain", "integral_gain", "anti_windup", "feedforward_enabled", "gravity_gain".
@export var pid_settings: Dictionary[String, Variant] = {}
## SetpointGenerator variables: "pattern" (0 constant, 1 step, 2 square, 3 ramp, 4 sine), "target_level", "start_level", "start_time", "period", "ramp_rate", "amplitude".
@export var setpoint_settings: Dictionary[String, Variant] = {}
## Simulation variables: "use_motion_profile", "bumpless_transfer".
@export var simulation_settings: Dictionary[String, Variant] = {}
## TrapezoidalProfile variables: "max_velocity", "max_acceleration".
@export var motion_profile_settings: Dictionary[String, Variant] = {}
## Sensor variables, e.g. "noise_enabled", "noise_std", "delay_enabled", "delay_s".
@export var sensor_settings: Dictionary[String, Variant] = {}
## Actuator variables, e.g. "saturation_enabled", "saturation_min", "slew_enabled".
@export var actuator_settings: Dictionary[String, Variant] = {}
## Cascaded PID (stage 23): the OUTER PidController's variables, e.g. "proportional_gain".
@export var cascade_outer_settings: Dictionary[String, Variant] = {}
## Cascaded PID: the INNER PidController's variables, e.g. "integral_gain", "gravity_gain".
@export var cascade_inner_settings: Dictionary[String, Variant] = {}
## DisturbanceGenerator variables, e.g. "step_enabled", "step_load", "drift_key".
@export var disturbance_settings: Dictionary[String, Variant] = {}

## Problems found while applying (unknown names). Read by the tests.
var problems: PackedStringArray = []
var print_warnings: bool = true  # tests that make typos on purpose turn this off


func create_plant() -> Plant:
	var plant: Plant = plant_script.new()
	for key in plant_parameters:
		if plant.parameters.has(key):
			plant.set_parameter(key, plant_parameters[key])
		else:
			_report("plant has no parameter '%s'" % key)
	return plant


# The cascade's overrides (call after ScenarioSetup.make_cascade). `cascade`
# is null for plants without an inner loop.
func apply_cascade_settings(cascade: CascadeController, plant: Plant) -> void:
	if cascade == null:
		if start_mode == StartMode.CASCADED_PID or not cascade_outer_settings.is_empty() \
				or not cascade_inner_settings.is_empty():
			_report("plant '%s' has no inner loop, so no Cascaded PID" % plant.get_display_name())
		return
	_apply(cascade.outer, cascade_outer_settings, "cascade_outer_settings")
	_apply(cascade.inner, cascade_inner_settings, "cascade_inner_settings")


func apply_settings(simulation: Simulation, pid: PidController) -> void:
	_apply(pid, pid_settings, "pid_settings")
	_apply(simulation.setpoint_generator, setpoint_settings, "setpoint_settings")
	_apply(simulation, simulation_settings, "simulation_settings")
	_apply(simulation.motion_profile, motion_profile_settings, "motion_profile_settings")
	_apply(simulation.sensor, sensor_settings, "sensor_settings")
	_apply(simulation.actuator, actuator_settings, "actuator_settings")
	_apply(simulation.disturbance_generator, disturbance_settings, "disturbance_settings")
	simulation.set_controller_rate_hz(controller_rate_hz)
	if challenge != null:
		for problem in challenge.find_problems():
			_report(problem)
	if lesson != null:
		for problem in lesson.find_problems():
			_report(problem)


func _apply(target: Object, settings: Dictionary, group_name: String) -> void:
	for key: String in settings:
		if not key in target:
			_report("%s has no setting '%s'" % [group_name, key])
			continue
		var value: Variant = settings[key]
		# The inspector may store 50 (int) where a float is meant.
		if typeof(target.get(key)) == TYPE_FLOAT and typeof(value) == TYPE_INT:
			value = float(value)
		target.set(key, value)


func _report(problem: String) -> void:
	problems.append(problem)
	if print_warnings:
		push_warning("Scenario '%s': %s" % [title, problem])
