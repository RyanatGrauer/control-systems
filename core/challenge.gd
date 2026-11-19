# challenge.gd
#
# PURPOSE
#   The goals of a challenge (README 7.6 mode 4), attached to a Scenario and
#   edited in the inspector. "Run test" plays a scripted, fixed-seed run:
#       the setpoint steps from start_level to target_level at step_time_s,
#       optionally a constant load (disturbance) switches on at load_time_s,
#       and the run lasts duration_s.
#   Every other setting (sensor, actuator, plant parameters, random loads...)
#   comes from the scenario file, NOT from the student's panels. Only the
#   student's PID tuning is theirs. ChallengeGrader then checks each spec.
#
# SPECS
#   `specs` maps a spec name to its LIMIT (every spec is "at most"). All
#   values are SI, like the rest of the scenario (rad/s, m, °C, V...).
#   Leave a spec out to not grade it. Valid names are the keys of SPEC_INFO;
#   anything else is reported as a problem (and fails the scenario tests).
class_name Challenge
extends Resource

# name -> [title shown to students, unit kind]
# unit kinds: "s", "%", "output" (plant output units), "output_s" (output x s),
# "input" (plant input units), "effort" (input^2 x s)
const SPEC_INFO: Dictionary = {
	"rise_time_s": ["Rise time", "s"],
	"overshoot_percent": ["Overshoot", "%"],
	"settling_time_s": ["Settling time", "s"],
	"steady_state_error": ["Steady-state error", "output"],
	"iae": ["Total error (IAE)", "output_s"],
	"peak_input": ["Peak input", "input"],
	"effort": ["Control effort", "effort"],
	"load_peak_error": ["Worst error, load", "output"],
	"load_recovery_s": ["Recovery, load", "s"],
}
const MAX_DURATION_S: float = 60.0  # the recorder keeps 120 s; leave headroom

@export_multiline var goal: String = ""
@export var duration_s: float = 8.0
@export var random_seed: int = 1
@export var start_level: float = 0.0     # SI output units
@export var target_level: float = 1.0    # SI output units
@export var step_time_s: float = 1.0
@export var load_enabled: bool = false
@export var load_force: float = 0.0      # SI disturbance units (N, N·m, W...)
@export var load_time_s: float = 5.0
@export var specs: Dictionary[String, float] = {}


# Problems with this challenge's data (empty = fine).
func find_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for key: String in specs:
		if not SPEC_INFO.has(key):
			problems.append("challenge spec '%s' is not a known spec (valid: %s)" % [
				key, ", ".join(PackedStringArray(SPEC_INFO.keys()))])
	if duration_s <= step_time_s or duration_s > MAX_DURATION_S:
		problems.append("challenge duration_s must be after step_time_s and at most %d s" % MAX_DURATION_S)
	if load_enabled and (load_time_s <= step_time_s or load_time_s >= duration_s):
		problems.append("challenge load_time_s must be between step_time_s and duration_s")
	if (specs.has("load_peak_error") or specs.has("load_recovery_s")) and not load_enabled:
		problems.append("challenge has load specs but load_enabled is false")
	return problems


# The scripted part of the test, applied on top of the scenario's settings.
func apply_to(simulation: Simulation) -> void:
	simulation.random_seed = random_seed
	var generator := simulation.setpoint_generator
	generator.pattern = SetpointGenerator.Pattern.STEP
	generator.start_level = start_level
	generator.target_level = target_level
	generator.start_time = step_time_s
	var disturbance := simulation.disturbance_generator
	disturbance.step_enabled = load_enabled
	disturbance.step_load = load_force
	disturbance.step_time = load_time_s
