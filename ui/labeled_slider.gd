# labeled_slider.gd
#
# PURPOSE
#   One row of "name + slider + fine-adjust buttons + numeric field" for a
#   single QuantityInfo (README 7.2). Reused for plant parameters, the manual
#   command, the target, and (stage 6) the PID gains.
#
# HOW IT FITS
#   Built from a QuantityInfo, so plants never need UI code: their parameter
#   metadata creates these rows automatically. The slider works in DISPLAY
#   units (e.g. RPM); `value_changed_si` always reports SI values, so unit
#   conversion happens only here, at the UI boundary.
#
# LOG SCALE
#   Values like inertia span orders of magnitude (0.00005 to 0.01). With a
#   log slider, each centimetre of travel multiplies the value by the same
#   factor, so small values are as easy to set as large ones. The fine-adjust
#   buttons multiply/divide by 1.1 on a log slider and add/subtract 1% of the
#   range on a linear one.
class_name LabeledSlider
extends VBoxContainer

signal value_changed_si(si_value: float)

# TUNABLE: slider resolution and fine-adjust step.
const SLIDER_RESOLUTION: float = 1000.0     # positions along the slider
const LOG_NUDGE_FACTOR: float = 1.1
const LINEAR_NUDGE_FRACTION: float = 0.01

var _info: QuantityInfo
var _value_si: float = 0.0
var _use_log: bool = false
var _updating: bool = false  # stops slider <-> text field feedback loops

var _slider: HSlider
var _number_field: LineEdit


func setup(info: QuantityInfo, initial_si_value: float) -> void:
	_info = info
	_use_log = info.use_log_slider
	if _use_log and info.min_value <= 0.0:
		push_warning("Log slider for '%s' needs min > 0; using linear." % info.key)
		_use_log = false
	_build()
	set_value_si(initial_si_value)


func get_value_si() -> float:
	return _value_si


# Update the display WITHOUT emitting value_changed_si (used when the
# simulation changes the value, e.g. keyboard nudges or a reset).
func set_value_si(si_value: float) -> void:
	_value_si = clampf(si_value, _info.min_value, _info.max_value)
	_updating = true
	_slider.value = _si_to_slider(_value_si)
	_number_field.text = NumberFormat.significant(_info.si_to_shown(_value_si), 4)
	_updating = false


func _build() -> void:
	add_theme_constant_override("separation", 2)
	tooltip_text = _info.description

	var title := Label.new()
	title.text = "%s  [%s]" % [_info.display_name, _info.get_shown_unit()]
	title.tooltip_text = _info.description
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(title)

	var row := HBoxContainer.new()
	add_child(row)

	var minus := _make_nudge_button("-", -1.0)
	row.add_child(minus)

	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.min_value = 0.0
	_slider.max_value = SLIDER_RESOLUTION
	_slider.step = 1.0
	# No keyboard focus: arrow keys and Space stay free for app shortcuts.
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(120.0, 24.0)
	_slider.value_changed.connect(_on_slider_moved)
	row.add_child(_slider)

	var plus := _make_nudge_button("+", 1.0)
	row.add_child(plus)

	_number_field = LineEdit.new()
	_number_field.custom_minimum_size = Vector2(76.0, 0.0)
	_number_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_number_field.text_submitted.connect(_on_text_submitted)
	_number_field.focus_exited.connect(_on_text_focus_lost)
	row.add_child(_number_field)


func _make_nudge_button(text: String, direction: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28.0, 28.0)
	button.tooltip_text = "Fine adjust"
	button.pressed.connect(_on_nudge.bind(direction))
	return button


# Slider position (0..SLIDER_RESOLUTION) <-> SI value.
func _slider_to_si(position_value: float) -> float:
	var fraction := position_value / SLIDER_RESOLUTION
	if _use_log:
		# value = min * (max/min)^fraction : equal travel = equal ratio
		return _info.min_value * pow(_info.max_value / _info.min_value, fraction)
	return lerpf(_info.min_value, _info.max_value, fraction)


func _si_to_slider(si_value: float) -> float:
	var fraction := 0.0
	if _use_log:
		fraction = log(si_value / _info.min_value) / log(_info.max_value / _info.min_value)
	else:
		fraction = inverse_lerp(_info.min_value, _info.max_value, si_value)
	return clampf(fraction, 0.0, 1.0) * SLIDER_RESOLUTION


func _apply_new_value(si_value: float) -> void:
	set_value_si(si_value)
	value_changed_si.emit(_value_si)


func _on_slider_moved(position_value: float) -> void:
	if _updating:
		return
	_apply_new_value(_slider_to_si(position_value))


func _on_nudge(direction: float) -> void:
	if _use_log:
		_apply_new_value(_value_si * pow(LOG_NUDGE_FACTOR, direction))
	else:
		var step := (_info.max_value - _info.min_value) * LINEAR_NUDGE_FRACTION
		_apply_new_value(_value_si + step * direction)


func _on_text_submitted(text: String) -> void:
	_read_number_field(text)
	_number_field.release_focus()


func _on_text_focus_lost() -> void:
	_read_number_field(_number_field.text)


func _read_number_field(text: String) -> void:
	if not text.strip_edges().is_valid_float():
		set_value_si(_value_si)  # put the old value back
		return
	_apply_new_value(_info.shown_to_si(text.to_float()))
