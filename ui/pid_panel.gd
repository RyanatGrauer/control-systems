# pid_panel.gd
#
# PURPOSE
#   The PID controller panel (README 7.2, stage 6): Kp / Ki / Kd sliders with
#   log scales, numeric fields and fine-adjust buttons, the output-limit switch,
#   a "Reset integral" button, live P / I / D term bars, and an "Advanced PID"
#   section (stage 11) with one toggle per feature, each with a one-sentence
#   explanation (README 6.1), plus the same gains shown in ISA form.
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
var _isa_label: Label
# Lessons (stage 21) hide or lock these by name; see get_lesson_control().
var _limits_checkbox: CheckBox
var _feedforward_section: CollapsibleSection
var _advanced_section: CollapsibleSection


func setup(simulation: Simulation, pid: PidController) -> void:
	_simulation = simulation
	_pid = pid
	add_theme_constant_override("separation", 12)

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

	add_child(UiStyle.make_hint("P / I / D keys select a gain; [ and ] nudge it."))

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
	_limits_checkbox = limits
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

	_build_feedforward_section()
	_build_advanced_section()


# Called by main_screen.gd every frame.
func update_panel() -> void:
	var input_info := _simulation.plant.get_input_definition()
	var shown_terms := {}
	for key in ["p", "i", "d", "ff", "sum"]:
		shown_terms[key] = input_info.si_to_shown(_pid.get_term_contributions().get(key, 0.0))
	_term_bars.set_terms(shown_terms, input_info.si_to_shown(input_info.max_value),
			input_info.get_shown_unit())
	if _isa_label.is_visible_in_tree():
		_isa_label.text = "Same controller in ISA form:\nu = Kp·(e + (1/Ti)·Σ(e·Δt) + Td·Δe/Δt)\nKp = %s,  Ti = %s,  Td = %s" % [
			NumberFormat.significant(_pid.proportional_gain, 3),
			_format_time(_pid.get_integral_time()), _format_time(_pid.get_derivative_time())]


# Lesson.CONTROL_NAMES that live in this panel ("kp", "feedforward"...), or null.
func get_lesson_control(control_name: String) -> Control:
	match control_name:
		"kp":
			return _gain_sliders[0]
		"ki":
			return _gain_sliders[1]
		"kd":
			return _gain_sliders[2]
		"output_limits":
			return _limits_checkbox
		"feedforward":
			return _feedforward_section
		"advanced_pid":
			return _advanced_section
	return null


func get_selected_gain() -> int:
	return _selected_gain


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


func _format_time(seconds: float) -> String:
	if is_inf(seconds):
		return "off"
	return NumberFormat.significant(seconds, 3) + " s"


# --- Feedforward section (stage 13) ---

func _build_feedforward_section() -> void:
	var section := CollapsibleSection.new("Feedforward", false)
	_feedforward_section = section
	add_child(section)
	var box := section.body
	var definitions := _simulation.plant.get_feedforward_definitions()
	# Start the sliders at the controller's values (a scenario may have set them).
	var current := [_pid.static_gain, _pid.velocity_gain, _pid.acceleration_gain, _pid.gravity_gain]
	for index in definitions.size():
		definitions[index].default_value = current[index]
	var setters: Array = [
		func(v: float) -> void: _pid.static_gain = v,
		func(v: float) -> void: _pid.velocity_gain = v,
		func(v: float) -> void: _pid.acceleration_gain = v,
		func(v: float) -> void: _pid.gravity_gain = v,
	]
	_add_toggle(box, "Use feedforward",
			"FF = kS·sign(v) + kV·v + kA·a + kG. It pushes based on what the target is doing, before any error appears; PID only fixes what's left. (v, a = the target's speed and acceleration.)",
			_pid.feedforward_enabled,
			func(on: bool) -> void: _pid.feedforward_enabled = on,
			definitions, setters)
	var cosine := CheckBox.new()
	cosine.text = "kG × cos(angle) (for arms)"
	cosine.tooltip_text = "Gravity's pull on an arm changes with its angle: strongest when level, zero when straight up."
	cosine.focus_mode = Control.FOCUS_NONE
	cosine.button_pressed = _pid.gravity_uses_cosine
	cosine.toggled.connect(func(on: bool) -> void: _pid.gravity_uses_cosine = on)
	box.add_child(cosine)


# --- Advanced PID section (stage 11) ---

func _build_advanced_section() -> void:
	var section := CollapsibleSection.new("Advanced PID", false)
	_advanced_section = section
	add_child(section)
	var box := section.body

	_add_toggle(box, "Derivative on measurement",
			"D reacts only to the measurement moving, so setpoint steps no longer cause a \"derivative kick\".",
			_pid.derivative_on_measurement,
			func(on: bool) -> void: _pid.derivative_on_measurement = on)

	var filter_info := QuantityInfo.new("derivative_filter_tau", "D filter time constant (Tf)", "s") \
		.with_display("ms", 1000.0).with_range(0.001, 1.0, _pid.derivative_filter_tau).with_log_slider()
	_add_toggle(box, "Filter the D term",
			"A low-pass filter on D so sensor noise isn't amplified. Bigger Tf = smoother but slower D.",
			_pid.derivative_filter_enabled,
			func(on: bool) -> void: _pid.derivative_filter_enabled = on,
			[filter_info], [func(v: float) -> void: _pid.derivative_filter_tau = v])

	# Anti-windup: a menu, plus the tracking gain for back-calculation.
	var windup_menu := OptionButton.new()
	windup_menu.focus_mode = Control.FOCUS_NONE
	windup_menu.add_item("Anti-windup: none", PidController.AntiWindup.NONE)
	windup_menu.add_item("Anti-windup: clamping", PidController.AntiWindup.CLAMPING)
	windup_menu.add_item("Anti-windup: back-calculation", PidController.AntiWindup.BACK_CALCULATION)
	windup_menu.select(_pid.anti_windup)
	windup_menu.fit_to_longest_item = false  # don't widen the side panel
	windup_menu.clip_text = true
	box.add_child(windup_menu)
	_add_hint(box, "While the output is stuck at a limit, stop the integral from piling up (\"windup\"), which causes big overshoot later. Needs output limits on.")
	var tracking_slider := LabeledSlider.new()
	box.add_child(tracking_slider)
	tracking_slider.setup(QuantityInfo.new("back_calculation_gain", "Tracking gain (Kb)", "1/s") \
		.with_range(0.1, 1000.0, _pid.back_calculation_gain).with_log_slider() \
		.with_description("How fast back-calculation bleeds the integral back to the limit."),
		_pid.back_calculation_gain)
	tracking_slider.value_changed_si.connect(func(v: float) -> void: _pid.back_calculation_gain = v)
	tracking_slider.visible = _pid.anti_windup == PidController.AntiWindup.BACK_CALCULATION
	windup_menu.item_selected.connect(func(index: int) -> void:
		_pid.anti_windup = index as PidController.AntiWindup
		tracking_slider.visible = _pid.anti_windup == PidController.AntiWindup.BACK_CALCULATION)

	var integral_menu := OptionButton.new()
	integral_menu.focus_mode = Control.FOCUS_NONE
	integral_menu.add_item("Integral: forward Euler (Ki·e·Δt)", PidController.IntegralMethod.FORWARD_EULER)
	integral_menu.add_item("Integral: trapezoidal", PidController.IntegralMethod.TRAPEZOIDAL)
	integral_menu.select(_pid.integral_method)
	integral_menu.fit_to_longest_item = false
	integral_menu.clip_text = true
	integral_menu.tooltip_text = "Trapezoidal integrates the average of the last two errors (slightly more accurate)."
	integral_menu.item_selected.connect(func(index: int) -> void:
		_pid.integral_method = index as PidController.IntegralMethod)
	box.add_child(integral_menu)

	var weight_b := QuantityInfo.new("setpoint_weight_b", "P setpoint weight (b)", "") \
		.with_range(0.0, 1.0, _pid.proportional_setpoint_weight)
	var weight_c := QuantityInfo.new("setpoint_weight_c", "D setpoint weight (c)", "") \
		.with_range(0.0, 1.0, _pid.derivative_setpoint_weight)
	_add_toggle(box, "Setpoint weighting",
			"P uses b·setpoint - measurement and D uses c·setpoint - measurement. b < 1 softens the response to setpoint steps without changing disturbance rejection.",
			_pid.setpoint_weighting_enabled,
			func(on: bool) -> void: _pid.setpoint_weighting_enabled = on,
			[weight_b, weight_c],
			[func(v: float) -> void: _pid.proportional_setpoint_weight = v,
			func(v: float) -> void: _pid.derivative_setpoint_weight = v])

	_add_toggle(box, "Bumpless switch (Manual / PID)",
			"When you switch controllers, the new one starts from the old command instead of jumping. (Switching to PID needs Ki > 0.)",
			_simulation.bumpless_transfer,
			func(on: bool) -> void: _simulation.bumpless_transfer = on)

	_isa_label = Label.new()
	_isa_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_isa_label.custom_minimum_size = Vector2(200.0, 0.0)
	_isa_label.tooltip_text = "Ti = Kp / Ki and Td = Kd / Kp. Same controller, written another way."
	_isa_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_isa_label)


# A checkbox, its one-sentence explanation, and sliders shown while it's on.
func _add_toggle(box: Control, title: String, explanation: String, enabled: bool,
		set_enabled: Callable, infos: Array = [], setters: Array = []) -> void:
	var check_box := CheckBox.new()
	check_box.text = title
	check_box.focus_mode = Control.FOCUS_NONE
	check_box.button_pressed = enabled
	box.add_child(check_box)
	_add_hint(box, explanation)
	var sliders := VBoxContainer.new()
	sliders.visible = enabled
	box.add_child(sliders)
	for index in infos.size():
		var info: QuantityInfo = infos[index]
		var slider := LabeledSlider.new()
		sliders.add_child(slider)
		slider.setup(info, info.default_value)
		slider.value_changed_si.connect(setters[index])
	check_box.toggled.connect(func(on: bool) -> void:
		set_enabled.call(on)
		sliders.visible = on)


func _add_hint(box: Control, text: String) -> void:
	box.add_child(UiStyle.make_hint(text))
