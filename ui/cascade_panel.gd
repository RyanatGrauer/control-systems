# cascade_panel.gd
#
# PURPOSE
#   Controls for the Cascaded PID (README 6.2, stage 23): the outer loop's
#   Kp/Ki/Kd (output error -> inner target), the inner loop's Kp/Ki/Kd
#   (inner error -> input), the inner loop's hold/hover feedforward kG, and
#   live term bars for the inner loop (whose terms add up to the input).
#
# HOW IT FITS
#   Shown by main_screen.gd in place of the PID panel when the controller
#   menu says "Cascaded PID". Sliders write the CascadeController's two
#   PidControllers directly (SI units; LabeledSlider converts for display).
class_name CascadePanel
extends VBoxContainer

var _simulation: Simulation
var _cascade: CascadeController
var _term_bars: TermBars


func setup(simulation: Simulation, cascade: CascadeController) -> void:
	_simulation = simulation
	_cascade = cascade
	add_theme_constant_override("separation", 12)
	var plant := simulation.plant
	var output_name := plant.get_output_definition().display_name.to_lower()
	var inner_info := plant.get_inner_definition()
	var inner_name := inner_info.display_name.to_lower()
	var input_name := plant.get_input_definition().display_name.to_lower()
	var gains: Array = plant.get_cascade_gain_definitions()

	add_child(UiStyle.make_hint("Two PIDs in a chain. The OUTER loop turns the %s error into a target %s; the INNER loop turns the %s error into %s. Tune the inner loop first, then the outer. The Inner loop tab plots both." % [
		output_name, inner_name, inner_name, input_name]))

	_add_loop(gains[0], cascade.outer, "Outer loop: %s to target %s" % [output_name, inner_name])
	var limit := plant.get_inner_setpoint_limit()
	add_child(UiStyle.make_hint("The outer loop's output is limited to ±%s %s (its fastest request)." % [
		NumberFormat.significant(inner_info.si_to_shown(limit), 3), inner_info.get_shown_unit()]))
	_add_loop(gains[1], cascade.inner, "Inner loop: %s to %s" % [inner_name, input_name])

	# Hold/hover feedforward on the inner loop: the input needed just to
	# stay put (gravity), so the PIDs only handle the rest.
	var kg_info: QuantityInfo = plant.get_feedforward_definitions()[3]
	var kg_slider := LabeledSlider.new()
	add_child(kg_slider)
	kg_slider.setup(kg_info, cascade.inner.gravity_gain)
	kg_slider.value_changed_si.connect(func(value: float) -> void:
		cascade.inner.gravity_gain = value
		cascade.inner.feedforward_enabled = value != 0.0)
	if plant.get_output_definition().si_unit == "rad":
		var cosine := CheckBox.new()
		cosine.text = "kG × cos(angle)"
		cosine.tooltip_text = "Gravity's pull on an arm depends on its angle: strongest when level, zero when vertical."
		cosine.button_pressed = cascade.inner.gravity_uses_cosine
		cosine.focus_mode = Control.FOCUS_NONE
		cosine.toggled.connect(func(on: bool) -> void: cascade.inner.gravity_uses_cosine = on)
		add_child(cosine)

	var bars_title := Label.new()
	bars_title.text = "Inner loop terms (live)"
	add_child(bars_title)
	_term_bars = TermBars.new()
	add_child(_term_bars)


func update_panel() -> void:
	var input_info := _simulation.plant.get_input_definition()
	var shown_terms := {}
	for key in ["p", "i", "d", "ff", "sum"]:
		shown_terms[key] = input_info.si_to_shown(_cascade.get_term_contributions().get(key, 0.0))
	_term_bars.set_terms(shown_terms, input_info.si_to_shown(input_info.max_value),
			input_info.get_shown_unit())


func _add_loop(trio: Array, pid: PidController, title: String) -> void:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", SignalColors.SETPOINT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size = Vector2(240.0, 0.0)
	add_child(heading)
	var setters: Array[Callable] = [
		func(value: float) -> void: pid.proportional_gain = value,
		func(value: float) -> void: pid.integral_gain = value,
		func(value: float) -> void: pid.derivative_gain = value,
	]
	var values := [pid.proportional_gain, pid.integral_gain, pid.derivative_gain]
	for index in 3:
		var slider := LabeledSlider.new()
		add_child(slider)
		slider.setup(trio[index], values[index])
		slider.value_changed_si.connect(setters[index])
