# pid_panel.gd
#
# PURPOSE
#   The PID controller panel (README 7.2, stage 6): Kp / Ki / Kd sliders with
#   log scales, numeric fields and fine-adjust buttons, the output-limit switch,
#   a "Reset integral" button, and live P / I / D term bars.
#   All changes apply LIVE while the simulation runs.
#
# KEYBOARD (InputMap actions, for live demos)
#   P / I / D select a gain (or click its name); ] and [ nudge the selected
#   gain up / down by x1.1 (main_screen.gd forwards the actions here).
#
# HOW IT FITS
#   Writes gains straight into the PidController object the Simulation uses.
#   Gain slider ranges and defaults come from the plant
#   (Plant.get_pid_gain_definitions()).
class_name PidPanel
extends VBoxContainer

const GAIN_KEYS: PackedStringArray = ["kp", "ki", "kd"]

var _simulation: Simulation
var _pid: PidController
var _gain_sliders: Array[LabeledSlider] = []
var _selected_gain: int = 0
var _term_bars: TermBars


func setup(simulation: Simulation, pid: PidController) -> void:
	_simulation = simulation
	_pid = pid
	add_theme_constant_override("separation", 8)

	var formula := Label.new()
	formula.text = "u = Kp·e + Ki·Σ(e·Δt) + Kd·Δe/Δt"
	formula.tooltip_text = "e = setpoint - measurement. Δt is the controller period."
	formula.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(formula)

	for index in GAIN_KEYS.size():
		var slider := LabeledSlider.new()
		add_child(slider)
		var info: QuantityInfo = simulation.plant.get_pid_gain_definitions()[index]
		slider.setup(info, _get_gain(index))
		slider.value_changed_si.connect(_set_gain.bind(index))
		slider.title_clicked.connect(select_gain.bind(index))
		_gain_sliders.append(slider)
	select_gain(0)

	var hint := Label.new()
	hint.text = "Click a gain name or press P / I / D to select it; [ and ] nudge it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200.0, 0.0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	add_child(hint)

	var input_info := simulation.plant.get_input_definition()
	var limits := CheckBox.new()
	limits.text = "Limit output to %s ... %s %s" % [
		NumberFormat.significant(input_info.si_to_shown(pid.output_min), 3),
		NumberFormat.significant(input_info.si_to_shown(pid.output_max), 3),
		input_info.get_shown_unit()]
	limits.tooltip_text = "Clamp the command to what the actuator can really do."
	limits.button_pressed = pid.use_output_limits
	limits.focus_mode = Control.FOCUS_NONE
	limits.toggled.connect(_on_limits_toggled)
	add_child(limits)

	var reset_integral := Button.new()
	reset_integral.text = "Reset integral"
	reset_integral.tooltip_text = "Forget the accumulated error (sets the I term to zero)."
	reset_integral.focus_mode = Control.FOCUS_NONE
	reset_integral.pressed.connect(pid.reset_integral)
	add_child(reset_integral)

	var bars_title := Label.new()
	bars_title.text = "Term contributions (live)"
	add_child(bars_title)
	_term_bars = TermBars.new()
	add_child(_term_bars)


# Called by main_screen.gd every frame.
func update_panel() -> void:
	var input_info := _simulation.plant.get_input_definition()
	var shown_terms := {}
	for key in ["p", "i", "d", "sum"]:
		shown_terms[key] = input_info.si_to_shown(_pid.get_term_contributions().get(key, 0.0))
	_term_bars.set_terms(shown_terms, input_info.si_to_shown(input_info.max_value),
			input_info.get_shown_unit())


func select_gain(index: int) -> void:
	_selected_gain = index
	for i in _gain_sliders.size():
		_gain_sliders[i].set_highlighted(i == index)


func nudge_selected_gain(direction: float) -> void:
	_gain_sliders[_selected_gain].nudge(direction)


func _get_gain(index: int) -> float:
	match index:
		0:
			return _pid.proportional_gain
		1:
			return _pid.integral_gain
	return _pid.derivative_gain


func _set_gain(si_value: float, index: int) -> void:
	match index:
		0:
			_pid.proportional_gain = si_value
		1:
			_pid.integral_gain = si_value
		2:
			_pid.derivative_gain = si_value


func _on_limits_toggled(enabled: bool) -> void:
	_pid.use_output_limits = enabled
