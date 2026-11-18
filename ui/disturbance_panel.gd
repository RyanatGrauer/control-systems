# disturbance_panel.gd
#
# PURPOSE
#   The "Disturbances" panel (README 7.5, stage 14): outside loads that push
#   the plant away from the setpoint, so students can see that REJECTING a
#   disturbance is a different job from TRACKING a setpoint.
#     - step load at a chosen time
#     - random load (smoothly wandering, seeded so runs repeat exactly)
#     - poke strength for clicking the plant view
#     - parameter drift: one plant parameter is multiplied at a chosen time
#       (e.g. the mass doubles at t = 5 s) to test robustness
#   Everything is off by default.
#
# HOW IT FITS
#   Writes into Simulation.disturbance_generator. Sizes are in the plant's
#   disturbance units (Plant.get_disturbance_definition()). Step load and drift
#   take effect at their times in the current run; press Reset to rerun from 0.
class_name DisturbancePanel
extends VBoxContainer

# TUNABLE: defaults, as fractions of the plant's disturbance range maximum.
const STEP_DEFAULT_FRACTION: float = 0.2
const RANDOM_DEFAULT_FRACTION: float = 0.05
const POKE_DEFAULT_FRACTION: float = 1.0

var _simulation: Simulation


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	add_theme_constant_override("separation", 6)
	var generator := simulation.disturbance_generator
	var load_info := simulation.plant.get_disturbance_definition()
	var load_max := maxf(absf(load_info.max_value), absf(load_info.min_value))

	var intro := _make_hint("On this plant the disturbance is the %s (%s). Watch it on the Disturbance plot tab." % [
			load_info.display_name.to_lower(), load_info.get_shown_unit()])
	add_child(intro)

	generator.step_load = load_max * STEP_DEFAULT_FRACTION
	_add_effect("Step load", generator.step_enabled,
			func(on: bool) -> void: generator.step_enabled = on,
			[_load_info(load_info, "step_load", "Load size", -load_max, load_max, generator.step_load,
				"A constant load that switches on at the time below."),
			QuantityInfo.new("step_time", "Starts at", "s").with_range(0.0, 30.0, generator.step_time)
				.with_description("Simulated time when the load switches on.")],
			[func(v: float) -> void: generator.step_load = v,
			func(v: float) -> void: generator.step_time = v])

	generator.random_std = load_max * RANDOM_DEFAULT_FRACTION
	_add_effect("Random load", generator.random_enabled,
			func(on: bool) -> void: generator.random_enabled = on,
			[_load_info(load_info, "random_std", "Typical size", 0.0, load_max, generator.random_std,
				"How big the wandering load usually is."),
			QuantityInfo.new("random_tau", "Wander time", "s") \
				.with_range(0.02, 10.0, generator.random_tau).with_log_slider() \
				.with_description("How slowly it wanders. Small = jittery, large = slow drifts.")],
			[func(v: float) -> void: generator.random_std = v,
			func(v: float) -> void: generator.random_tau = v])

	add_child(_make_hint("Poke: click the plant view (right-click pokes the other way)."))
	generator.poke_strength = load_max * POKE_DEFAULT_FRACTION
	var poke_slider := LabeledSlider.new()
	add_child(poke_slider)
	poke_slider.setup(_load_info(load_info, "poke_strength", "Poke strength", 0.0, load_max,
			generator.poke_strength, "Size of the short push a click gives (0.2 s)."), generator.poke_strength)
	poke_slider.value_changed_si.connect(func(v: float) -> void: generator.poke_strength = v)

	_build_drift_controls(generator)


func _build_drift_controls(generator: DisturbanceGenerator) -> void:
	var definitions := _simulation.plant.get_parameter_definitions()
	if definitions.is_empty():
		return
	var check_box := CheckBox.new()
	check_box.text = "Parameter drift"
	check_box.focus_mode = Control.FOCUS_NONE
	check_box.button_pressed = generator.drift_enabled
	add_child(check_box)
	add_child(_make_hint("At the chosen time, one plant parameter is multiplied (e.g. the load gets heavier). Does your tuning still work? Reset puts it back."))

	var body := VBoxContainer.new()
	body.visible = generator.drift_enabled
	add_child(body)
	var menu := OptionButton.new()
	menu.focus_mode = Control.FOCUS_NONE
	menu.fit_to_longest_item = false
	menu.clip_text = true
	for info in definitions:
		menu.add_item(info.display_name)
	if generator.drift_key == "":
		generator.drift_key = definitions[0].key
	menu.item_selected.connect(func(index: int) -> void:
		generator.drift_key = definitions[index].key)
	body.add_child(menu)
	for pair in [
		[QuantityInfo.new("drift_factor", "Multiply by", "×").with_range(0.1, 10.0, generator.drift_factor)
			.with_log_slider().with_description("2 = doubles, 0.5 = halves."),
			func(v: float) -> void: generator.drift_factor = v],
		[QuantityInfo.new("drift_time", "At time", "s").with_range(0.0, 30.0, generator.drift_time)
			.with_description("Simulated time when the change happens."),
			func(v: float) -> void: generator.drift_time = v],
	]:
		var slider := LabeledSlider.new()
		body.add_child(slider)
		slider.setup(pair[0], (pair[0] as QuantityInfo).default_value)
		slider.value_changed_si.connect(pair[1])
	check_box.toggled.connect(func(on: bool) -> void:
		generator.drift_enabled = on
		body.visible = on)


# A QuantityInfo in the disturbance's units (keeps its display unit/scale).
func _load_info(like: QuantityInfo, key: String, title: String, min_si: float,
		max_si: float, default_si: float, description: String) -> QuantityInfo:
	var info := QuantityInfo.new(key, title, like.si_unit) \
		.with_range(min_si, max_si, default_si).with_description(description)
	if like.display_unit != "":
		info.with_display(like.display_unit, like.display_scale)
	return info


func _make_hint(text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200.0, 0.0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	return hint


# One checkbox plus its sliders (hidden while the box is off).
func _add_effect(title: String, enabled: bool, set_enabled: Callable,
		infos: Array, setters: Array) -> void:
	var check_box := CheckBox.new()
	check_box.text = title
	check_box.focus_mode = Control.FOCUS_NONE
	check_box.button_pressed = enabled
	add_child(check_box)
	var body := VBoxContainer.new()
	body.visible = enabled
	add_child(body)
	for index in infos.size():
		var info: QuantityInfo = infos[index]
		var slider := LabeledSlider.new()
		body.add_child(slider)
		slider.setup(info, info.default_value)
		slider.value_changed_si.connect(setters[index])
	check_box.toggled.connect(func(on: bool) -> void:
		set_enabled.call(on)
		body.visible = on)
