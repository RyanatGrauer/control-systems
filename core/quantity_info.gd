# quantity_info.gd
#
# PURPOSE
#   Describes ONE named physical quantity: a plant parameter (like inertia),
#   a state component (like angular velocity), the plant's input, or its output.
#
# HOW IT FITS
#   Plants return lists of QuantityInfo objects. The UI reads those lists to
#   build sliders and labels automatically (README section 9: "parameter
#   metadata drives the UI"). Adding a parameter to a plant therefore makes its
#   slider appear without touching any UI code.
#
# UNITS
#   Values stored in the simulation are ALWAYS SI (README section 2.7).
#   `display_unit` and `display_scale` only tell the UI how to show them:
#       shown_value = si_value * display_scale
#   Example: angular velocity in rad/s shown as RPM uses display_scale = 60 / (2*pi).
#
# USAGE (chained setters keep plant definitions short and readable):
#   QuantityInfo.new("inertia", "Flywheel inertia", "kg·m²") \
#       .with_range(0.0001, 0.01, 0.0004) \
#       .with_log_slider() \
#       .with_description("How hard the wheel is to spin up.")
class_name QuantityInfo
extends RefCounted

# For state components only: used by the semi-implicit Euler integrator,
# which updates RATE components first and POSITION components second.
enum StateKind { NOT_A_STATE, POSITION, RATE }

var key: String                 # internal name used in code, e.g. "inertia"
var display_name: String        # what students see, e.g. "Flywheel inertia"
var si_unit: String             # unit of the stored value, e.g. "kg·m²"
var description: String = ""   # one short, student-friendly sentence

var default_value: float = 0.0  # SI
var min_value: float = 0.0      # SI
var max_value: float = 1.0      # SI

var display_unit: String = ""   # empty means "same as si_unit"
var display_scale: float = 1.0  # shown_value = si_value * display_scale

var use_log_slider: bool = false  # true for values that span orders of magnitude
var state_kind: StateKind = StateKind.NOT_A_STATE


func _init(new_key: String, new_display_name: String, new_si_unit: String) -> void:
	key = new_key
	display_name = new_display_name
	si_unit = new_si_unit


func with_range(new_min: float, new_max: float, new_default: float) -> QuantityInfo:
	min_value = new_min
	max_value = new_max
	default_value = new_default
	return self


func with_description(text: String) -> QuantityInfo:
	description = text
	return self


func with_display(unit: String, scale_from_si: float) -> QuantityInfo:
	display_unit = unit
	display_scale = scale_from_si
	return self


func with_log_slider() -> QuantityInfo:
	use_log_slider = true
	return self


func as_state(kind: StateKind) -> QuantityInfo:
	state_kind = kind
	return self


# The unit string the UI should print next to the number.
func get_shown_unit() -> String:
	if display_unit == "":
		return si_unit
	return display_unit


func si_to_shown(si_value: float) -> float:
	return si_value * display_scale


func shown_to_si(shown_value: float) -> float:
	return shown_value / display_scale
