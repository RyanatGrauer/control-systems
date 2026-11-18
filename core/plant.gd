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


# res:// path of the scene that draws this plant.
func get_visual_scene_path() -> String:
	return ""


# ---------------------------------------------------------------- helpers

func get_state_kinds() -> Array[QuantityInfo.StateKind]:
	return _state_kinds


func get_parameter(key: String) -> float:
	return parameters[key]


func set_parameter(key: String, si_value: float) -> void:
	if not parameters.has(key):
		push_error("Plant '%s' has no parameter '%s'" % [get_display_name(), key])
		return
	parameters[key] = si_value
