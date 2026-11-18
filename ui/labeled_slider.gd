# labeled_slider.gd
#
# PURPOSE
#   One row of "name + slider + fine-adjust buttons + numeric field" for a
#   single QuantityInfo (README 7.2). Reused for plant parameters, the manual
#   command, setpoint settings, and the PID gains.
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
#
#   Gains must be able to be exactly 0, which a pure log scale cannot show.
#   If the QuantityInfo has min_value 0 and a log_floor > 0, the far-left
#   slider position means 0 and the rest is logarithmic from log_floor to max.
#
# APPLY ON RELEASE
#   With `apply_on_release = true`, dragging the slider only updates the number
#   shown; the new value is applied once when the mouse is released. Used for
#   the setpoint, so a drag produces ONE clean step instead of a staircase.
#
# SELECTION
#   Clicking the title emits `title_clicked`. The PID panel uses this (and
#   set_highlighted) to pick which gain the [ and ] keys nudge.
class_name LabeledSlider
extends VBoxContainer

signal value_changed_si(si_value: float)
signal title_clicked

# TUNABLE: slider resolution and fine-adjust step.
const SLIDER_RESOLUTION: float = 1000.0     # positions along the slider
const LOG_NUDGE_FACTOR: float = 1.1
const LINEAR_NUDGE_FRACTION: float = 0.01
const HIGHLIGHT_COLOR: Color = Color("#F0E442")
# Nudging a zero-capable log value up from 0 jumps to this fraction of the
# maximum (a useful starting point), and nudging down from there returns to 0.
const NUDGE_FROM_ZERO_FRACTION: float = 0.01

var _info: QuantityInfo
var _value_si: float = 0.0
var _use_log: bool = false
var _log_low: float = 1.0      # lower end of the logarithmic part of the slider
var _has_zero_stop: bool = false  # far-left position means exactly 0
var _updating: bool = false    # stops slider <-> text field feedback loops
var _is_dragging: bool = false

var apply_on_release: bool = false

var _title: Label
var _slider: HSlider
var _number_field: LineEdit


func setup(info: QuantityInfo, initial_si_value: float) -> void:
	_info = info
	_use_log = info.use_log_slider
	if _use_log:
		if info.min_value > 0.0:
			_log_low = info.min_value
		elif info.min_value == 0.0 and info.log_floor > 0.0:
			_log_low = info.log_floor
			_has_zero_stop = true
		else:
			push_warning("Log slider for '%s' needs min > 0 or a log_floor; using linear." % info.key)
			_use_log = false
	_build()
	set_value_si(initial_si_value)


func get_value_si() -> float:
	return _value_si


func get_info() -> QuantityInfo:
	return _info


# Update the display WITHOUT emitting value_changed_si (used when the
# simulation changes the value, e.g. keyboard nudges or a reset).
func set_value_si(si_value: float) -> void:
	_value_si = clampf(si_value, _info.min_value, _info.max_value)
	_updating = true
	_slider.value = _si_to_slider(_value_si)
	_number_field.text = NumberFormat.significant(_info.si_to_shown(_value_si), 4)
	_updating = false


# Fine-adjust by one step: direction +1 = up, -1 = down. Emits value_changed_si.
func nudge(direction: float) -> void:
	if _use_log:
		var first_step := maxf(_info.max_value * NUDGE_FROM_ZERO_FRACTION, _log_low)
		if _value_si <= 0.0 and direction > 0.0:
			_apply_new_value(first_step)  # from 0, jump to a useful first value
		elif _has_zero_stop and direction < 0.0 and _value_si <= first_step * 1.0001:
			_apply_new_value(0.0)         # at or below that value, drop to exactly 0
		else:
			_apply_new_value(_value_si * pow(LOG_NUDGE_FACTOR, direction))
	else:
		var step := (_info.max_value - _info.min_value) * LINEAR_NUDGE_FRACTION
		_apply_new_value(_value_si + step * direction)


func set_title_color(color: Color) -> void:
	_title.add_theme_color_override("font_color", color)


func set_highlighted(highlighted: bool) -> void:
	if highlighted:
		_title.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
		_title.text = "> " + _title_text()
	else:
		_title.remove_theme_color_override("font_color")
		_title.text = _title_text()


func _title_text() -> String:
	return "%s  [%s]" % [_info.display_name, _info.get_shown_unit()]


func _build() -> void:
	add_theme_constant_override("separation", 2)
	tooltip_text = _info.description

	_title = Label.new()
	_title.text = _title_text()
	_title.tooltip_text = _info.description
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.gui_input.connect(_on_title_input)
	add_child(_title)

	var row := HBoxContainer.new()
	add_child(row)

	row.add_child(_make_nudge_button("-", -1.0))

	_slider = HSlider.new()
	# The mouse wheel scrolls the panel, never the value: otherwise scrolling a
	# long side panel silently changes whichever slider passes under the cursor.
	_slider.scrollable = false
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.min_value = 0.0
	_slider.max_value = SLIDER_RESOLUTION
	_slider.step = 1.0
	# No keyboard focus: arrow keys and Space stay free for app shortcuts.
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(120.0, 24.0)
	_slider.value_changed.connect(_on_slider_moved)
	_slider.drag_started.connect(_on_drag_started)
	_slider.drag_ended.connect(_on_drag_ended)
	row.add_child(_slider)

	row.add_child(_make_nudge_button("+", 1.0))

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
	button.pressed.connect(nudge.bind(direction))
	return button


# Slider position (0..SLIDER_RESOLUTION) <-> SI value.
func _slider_to_si(position_value: float) -> float:
	var fraction := position_value / SLIDER_RESOLUTION
	if _use_log:
		if _has_zero_stop and position_value <= 0.0:
			return 0.0
		# value = low * (max/low)^fraction : equal travel = equal ratio
		return _log_low * pow(_info.max_value / _log_low, fraction)
	return lerpf(_info.min_value, _info.max_value, fraction)


func _si_to_slider(si_value: float) -> float:
	var fraction := 0.0
	if _use_log:
		if si_value <= 0.0:
			return 0.0
		fraction = log(si_value / _log_low) / log(_info.max_value / _log_low)
		# Keep tiny non-zero values off the "zero" position.
		if _has_zero_stop:
			fraction = maxf(fraction, 1.0 / SLIDER_RESOLUTION)
	else:
		fraction = inverse_lerp(_info.min_value, _info.max_value, si_value)
	return clampf(fraction, 0.0, 1.0) * SLIDER_RESOLUTION


func _apply_new_value(si_value: float) -> void:
	set_value_si(si_value)
	value_changed_si.emit(_value_si)


func _on_slider_moved(position_value: float) -> void:
	if _updating:
		return
	if apply_on_release and _is_dragging:
		# Preview only: show the number, apply when the drag ends.
		_number_field.text = NumberFormat.significant(
				_info.si_to_shown(_slider_to_si(position_value)), 4)
		return
	_apply_new_value(_slider_to_si(position_value))


func _on_drag_started() -> void:
	_is_dragging = true


func _on_drag_ended(_value_changed: bool) -> void:
	_is_dragging = false
	if apply_on_release:
		_apply_new_value(_slider_to_si(_slider.value))


func _on_title_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		title_clicked.emit()


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
