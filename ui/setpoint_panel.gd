# setpoint_panel.gd
#
# PURPOSE
#   Chooses what the setpoint does (README 6.3, stage 8): constant, step,
#   square wave, ramp or sine, with only the settings that pattern uses shown.
#   Also shows the live target / measured / error readout.
#
# HOW IT FITS
#   Writes the fields of Simulation.setpoint_generator. Changes apply live.
#   Level settings use the plant's output units (e.g. RPM), converted to SI
#   here at the UI boundary.
class_name SetpointPanel
extends VBoxContainer

signal settings_changed  # so the setpoint bar can stay in sync

var _simulation: Simulation
var _generator: SetpointGenerator
var _pattern_menu: OptionButton
var _sliders: Dictionary = {}  # setting key -> LabeledSlider
var _readout: Label

# Which settings each pattern uses (the rest are hidden).
const SETTINGS_FOR_PATTERN: Dictionary = {
	SetpointGenerator.Pattern.CONSTANT: ["target_level"],
	SetpointGenerator.Pattern.STEP: ["target_level", "start_level", "start_time"],
	SetpointGenerator.Pattern.SQUARE: ["target_level", "start_level", "start_time", "period"],
	SetpointGenerator.Pattern.RAMP: ["target_level", "start_level", "start_time", "ramp_rate"],
	SetpointGenerator.Pattern.SINE: ["target_level", "amplitude", "start_time", "period"],
}


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_generator = simulation.setpoint_generator
	add_theme_constant_override("separation", 8)

	_pattern_menu = OptionButton.new()
	_pattern_menu.focus_mode = Control.FOCUS_NONE
	for pattern: SetpointGenerator.Pattern in SETTINGS_FOR_PATTERN.keys():
		_pattern_menu.add_item(SetpointGenerator.get_pattern_name(pattern), pattern)
	_pattern_menu.select(_pattern_menu.get_item_index(_generator.pattern))
	_pattern_menu.item_selected.connect(_on_pattern_selected)
	add_child(_pattern_menu)

	# Start every setting at its default (they depend on the plant's units).
	for info in _make_setting_definitions():
		_generator.set(info.key, info.default_value)
		var slider := LabeledSlider.new()
		add_child(slider)
		slider.setup(info, info.default_value)
		slider.value_changed_si.connect(_on_setting_changed.bind(info.key))
		_sliders[info.key] = slider

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 15)
	add_child(_readout)
	_update_visible_settings()


# Called by main_screen.gd every frame.
func update_panel() -> void:
	var output_info := _simulation.plant.get_output_definition()
	var unit := output_info.get_shown_unit()
	var target := output_info.si_to_shown(_simulation.setpoint)
	var measured := output_info.si_to_shown(_simulation.measurement)
	_readout.text = "Target:    %s %s\nMeasured:  %s %s\nError:     %s %s" % [
		NumberFormat.significant(target, 4), unit,
		NumberFormat.significant(measured, 4), unit,
		NumberFormat.significant(target - measured, 3), unit,
	]


# The "Target" setting, shared with the setpoint bar on the plant view.
static func make_target_info(output_info: QuantityInfo) -> QuantityInfo:
	return QuantityInfo.new("target_level", "Target", output_info.si_unit) \
		.with_range(output_info.min_value, output_info.max_value, output_info.default_value) \
		.with_display(output_info.display_unit, output_info.display_scale) \
		.with_description("The value the controller should reach (the centre line for a sine).")


# Refresh every control from the generator (after the setpoint bar changed it).
func sync_from_generator() -> void:
	_pattern_menu.select(_pattern_menu.get_item_index(_generator.pattern))
	for key: String in _sliders.keys():
		var slider: LabeledSlider = _sliders[key]
		slider.set_value_si(_generator.get(key))
	_update_visible_settings()


# Slider definitions. The keys match SetpointGenerator's variable names.
func _make_setting_definitions() -> Array[QuantityInfo]:
	var output_info := _simulation.plant.get_output_definition()
	var low := output_info.min_value
	var high := output_info.max_value
	var span := high - low
	var unit := output_info.si_unit
	var shown := output_info.get_shown_unit()
	return [
		make_target_info(output_info),
		QuantityInfo.new("start_level", "Start level", unit) \
			.with_range(low, high, clampf(0.0, low, high)) \
			.with_display(output_info.display_unit, output_info.display_scale) \
			.with_description("The setpoint before the start time (and the low level of a square wave)."),
		QuantityInfo.new("start_time", "Start time", "s") \
			.with_range(0.0, 10.0, 1.0) \
			.with_description("When the step, ramp or wave begins."),
		QuantityInfo.new("period", "Period", "s") \
			.with_range(0.2, 30.0, 4.0) \
			.with_log_slider() \
			.with_description("Time for one full cycle of the wave. Frequency = 1 / period."),
		QuantityInfo.new("ramp_rate", "Ramp rate", unit + "/s") \
			.with_range(span / 100.0, span * 10.0, span / 4.0) \
			.with_display(shown + "/s", output_info.display_scale) \
			.with_log_slider() \
			.with_description("How fast the ramp moves toward the target."),
		QuantityInfo.new("amplitude", "Amplitude", unit) \
			.with_range(0.0, span * 0.5, span / 8.0) \
			.with_display(output_info.display_unit, output_info.display_scale) \
			.with_description("How far the sine swings above and below the target."),
	]


func _on_pattern_selected(index: int) -> void:
	_generator.pattern = _pattern_menu.get_item_id(index) as SetpointGenerator.Pattern
	_update_visible_settings()
	settings_changed.emit()


func _on_setting_changed(si_value: float, key: String) -> void:
	_generator.set(key, si_value)
	settings_changed.emit()


func _update_visible_settings() -> void:
	var used: Array = SETTINGS_FOR_PATTERN[_generator.pattern]
	for key: String in _sliders.keys():
		var slider: LabeledSlider = _sliders[key]
		slider.visible = key in used
