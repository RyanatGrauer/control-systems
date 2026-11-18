# plant.gd
#
# PURPOSE
#   Base class (the "contract") for every simulated physical system.
#   README section 4.3 lists what a plant must provide; each item below maps
#   to one function you override.
#
# HOW IT FITS
#   Simulation (core/simulation.gd) owns one Plant. Every physics substep it asks
#   the plant for d(state)/dt and hands that to an integrator (core/integrators.gd).
#   The plant never knows which controller drives it, and never touches Godot
#   nodes. Its visual is a separate scene (see get_visual_scene_path()).
#
# HOW TO WRITE A NEW PLANT
#   See docs/adding_a_plant.md. In short: extend Plant, override the
#   get_*_definitions() functions, compute_derivative(), and get_output().
class_name Plant
extends RefCounted

# Current parameter values, in SI units. Key = QuantityInfo.key.
# The UI writes here when a student moves a parameter slider; the derivative
# function reads from here every substep, so changes apply live.
var parameters: Dictionary = {}

# Cached once at construction so the integrator does not rebuild the list
# thousands of times per second.
var _state_kinds: Array[QuantityInfo.StateKind] = []


func _init() -> void:
	for info in get_parameter_definitions():
		parameters[info.key] = info.default_value
	for info in get_state_definitions():
		_state_kinds.append(info.state_kind)


# ---------------------------------------------------------------- override these

# Short name shown in the UI, e.g. "Flywheel / DC motor speed".
func get_display_name() -> String:
	return "Unnamed plant"


# One or two plain sentences shown over the plant view: what the controller
# is physically doing and what the goal is.
func get_description() -> String:
	return ""


# Tunable physical parameters (drive the "Plant parameters" panel).
func get_parameter_definitions() -> Array[QuantityInfo]:
	return []


# Named components of the state vector, IN ORDER. Each must be marked with
# as_state(POSITION) or as_state(RATE) for the semi-implicit Euler integrator.
func get_state_definitions() -> Array[QuantityInfo]:
	return []


# The physical input the actuator applies (e.g. motor voltage).
func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("input", "Input", "")


# The controlled variable (what the sensor measures and the setpoint targets).
func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("output", "Output", "")


# The disturbance the plant accepts (e.g. load torque). Used by later stages.
func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("disturbance", "Disturbance", "")


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array()


# The equations of motion: return d(state)/dt.
#   state          current state vector (SI)
#   applied_input  the actuator's output, held constant during the substep
#   disturbance    outside load/force acting on the plant (SI)
#   time           simulated time in seconds (for time-varying plants)
func compute_derivative(_state: PackedFloat64Array, _applied_input: float,
		_disturbance: float, _time: float) -> PackedFloat64Array:
	return PackedFloat64Array()


# Which value the controller is trying to control.
func get_output(_state: PackedFloat64Array) -> float:
	return 0.0


# Optional "event" logic run BETWEEN substeps for things ODE solvers handle
# badly: hard stops, static friction stick/slip, backlash (README 4.2).
# Return the (possibly corrected) state. Default: no constraints.
func apply_constraints(state: PackedFloat64Array) -> PackedFloat64Array:
	return state


# PID gain sliders for this plant: Kp, Ki, Kd as QuantityInfo (defaults and
# ranges differ hugely between plants). Use make_pid_gain_definitions().
# Scenario files (stage 15) will be able to override the defaults.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(1.0, 100.0, 0.0, 100.0, 0.0, 10.0)


# res:// path of the scene that draws this plant.
func get_visual_scene_path() -> String:
	return ""


# ---------------------------------------------------------------- helpers

# Builds Kp/Ki/Kd slider definitions with correct units, e.g. for a plant whose
# input is V and output is rad/s: Kp in V/(rad/s), Ki in V/((rad/s)·s),
# Kd in V·s/(rad/s). Each gain can be 0 (far left of its log slider);
# otherwise its slider spans 4 decades below its maximum.
func make_pid_gain_definitions(kp_default: float, kp_max: float,
		ki_default: float, ki_max: float,
		kd_default: float, kd_max: float) -> Array[QuantityInfo]:
	var input_unit := get_input_definition().si_unit
	var output_unit := _wrap_unit(get_output_definition().si_unit)
	return [
		QuantityInfo.new("kp", "Kp (proportional)", "%s/%s" % [input_unit, output_unit]) \
			.with_range(0.0, kp_max, kp_default).with_log_slider(kp_max * 1e-4) \
			.with_description("Pushes in proportion to the error right now. More Kp = faster, but more overshoot."),
		QuantityInfo.new("ki", "Ki (integral)", "%s/(%s·s)" % [input_unit, output_unit]) \
			.with_range(0.0, ki_max, ki_default).with_log_slider(ki_max * 1e-4) \
			.with_description("Pushes harder the longer an error lasts. Removes steady-state error, but can overshoot."),
		QuantityInfo.new("kd", "Kd (derivative)", "%s·s/%s" % [input_unit, output_unit]) \
			.with_range(0.0, kd_max, kd_default).with_log_slider(kd_max * 1e-4) \
			.with_description("Pushes against fast changes in the error, like a brake. Reduces overshoot; amplifies noise."),
	]


# "rad/s" -> "(rad/s)" so compound units stay unambiguous.
static func _wrap_unit(unit: String) -> String:
	if "/" in unit:
		return "(%s)" % unit
	return unit


func get_state_kinds() -> Array[QuantityInfo.StateKind]:
	return _state_kinds


func get_parameter(key: String) -> float:
	return parameters[key]


func set_parameter(key: String, si_value: float) -> void:
	if not parameters.has(key):
		push_error("Plant '%s' has no parameter '%s'" % [get_display_name(), key])
		return
	parameters[key] = si_value
