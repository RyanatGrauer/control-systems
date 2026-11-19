# zn_panel.gd
#
# PURPOSE
#   The Ziegler–Nichols helper (README 7.6 mode 3), a section of the side
#   panel. It walks the student through the ultimate-gain method:
#     1. "P only" button: sets Ki = Kd = 0.
#     2. Raise Kp (and press Reset) until the live readout says the swing is
#        STEADY. The cycles are shaded on the output plot, so the student can
#        see the period Tu being measured.
#     3. "Use this Kp as Ku": fills in the ZN and Tyreus–Luyben table.
#     4. "Apply" a row, watch the run, compare it with the others (ghosts).
#
# HOW IT FITS
#   Display only. main_screen.gd measures the swing (Oscillation, ZnTuning)
#   4 times a second and calls show_state(); the buttons emit signals that
#   main_screen.gd turns into gain changes. Gains arrive in SI.
class_name ZnPanel
extends VBoxContainer

signal p_only_requested
signal capture_requested
signal apply_requested(row: Dictionary)

var _plant: Plant
var _state: Label
var _capture_button: Button
var _result: Label
var _table: GridContainer


func setup(plant: Plant) -> void:
	_plant = plant
	add_theme_constant_override("separation", 12)
	add_child(UiStyle.make_hint("Find the gain where the loop JUST keeps swinging (the ultimate gain Ku) and the swing's period Tu. Classic tables then turn Ku and Tu into PID gains."))

	var p_only := Button.new()
	p_only.text = "1. P only (set Ki = Kd = 0)"
	p_only.focus_mode = Control.FOCUS_NONE
	p_only.pressed.connect(p_only_requested.emit)
	add_child(p_only)
	add_child(UiStyle.make_hint("2. Raise Kp, then press Reset (R) to test it. Repeat until the swing below says STEADY. Too much Kp and the swing grows; too little and it dies out."))

	_state = Label.new()
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.custom_minimum_size = Vector2(240.0, 0.0)
	add_child(_state)

	_capture_button = Button.new()
	_capture_button.text = "3. Use this Kp as Ku"
	_capture_button.focus_mode = Control.FOCUS_NONE
	_capture_button.disabled = true
	_capture_button.pressed.connect(capture_requested.emit)
	add_child(_capture_button)

	_result = Label.new()
	_result.visible = false
	add_child(_result)
	_table = GridContainer.new()
	_table.columns = 5
	_table.add_theme_constant_override("h_separation", 15)
	_table.add_theme_constant_override("v_separation", 6)
	_table.visible = false
	add_child(_table)
	var why := UiStyle.make_hint("ZN aims for each overshoot to be a quarter of the one before: fast, but very bouncy. Tyreus–Luyben (T-L) is calmer. Apply both and compare the ghosts.")
	why.visible = false
	_table.set_meta("why", why)
	add_child(why)


# state_text: what to do next; is_steady: Ku can be captured.
func show_state(state_text: String, color: Color, is_steady: bool) -> void:
	if _state.text != state_text:
		_state.text = state_text
	_state.add_theme_color_override("font_color", color)
	_capture_button.disabled = not is_steady


func show_table(ultimate_gain: float, ultimate_period: float) -> void:
	var gains := _plant.get_pid_gain_definitions()
	var number := func(value: float, index: int) -> String:
		if value == 0.0:
			return "-"
		return NumberFormat.significant(gains[index].si_to_shown(value), 3)
	_result.text = "Ku = %s %s,   Tu = %s s" % [number.call(ultimate_gain, 0),
			gains[0].get_shown_unit(), NumberFormat.significant(ultimate_period, 3)]
	_result.visible = true
	for child in _table.get_children():
		child.queue_free()
	for heading in ["Rule", "Kp", "Ki", "Kd", ""]:
		_table.add_child(_cell(heading, UiStyle.HINT_COLOR))
	for row: Dictionary in ZnTuning.make_table(ultimate_gain, ultimate_period):
		var name_cell := _cell(row["name"], Color.WHITE)
		name_cell.tooltip_text = row["note"]
		name_cell.mouse_filter = Control.MOUSE_FILTER_PASS
		_table.add_child(name_cell)
		_table.add_child(_cell(number.call(row["kp"], 0), Color.WHITE))
		_table.add_child(_cell(number.call(row["ki"], 1), Color.WHITE))
		_table.add_child(_cell(number.call(row["kd"], 2), Color.WHITE))
		var apply := Button.new()
		apply.text = "Apply"
		apply.tooltip_text = "Set these gains and start a new run. %s." % row["note"]
		apply.focus_mode = Control.FOCUS_NONE
		apply.pressed.connect(apply_requested.emit.bind(row))
		_table.add_child(apply)
	_table.visible = true
	(_table.get_meta("why") as Control).visible = true


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
