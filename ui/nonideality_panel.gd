# nonideality_panel.gd
#
# PURPOSE
#   The "Sensor & actuator" panel (README 7.5): one checkbox per real-world
#   problem, and the problem's sliders, shown only while it is switched on.
#   Everything starts OFF, so the default loop is ideal.
#
# HOW IT FITS
#   Shows the current settings (defaults from apply_defaults(), possibly
#   changed by a scenario) and writes into Simulation.sensor/actuator; the very
#   next controller tick uses the new settings (they work live, mid-run).
#   Slider ranges are scaled from the plant's own input/output ranges, so the
#   same panel suits every plant with no per-plant UI code.
#
#   The "True output" trace on the output plot shows the difference between
#   what really happened and what the sensor reported.
class_name NonidealityPanel
extends VBoxContainer

# TUNABLE: slider ranges as fractions of the plant's output span
# (max - min of the output range) or input span.
const NOISE_MAX_FRACTION: float = 0.1
const NOISE_DEFAULT_FRACTION: float = 0.01
const RESOLUTION_MIN_FRACTION: float = 0.0001
const RESOLUTION_MAX_FRACTION: float = 0.1
const RESOLUTION_DEFAULT_FRACTION: float = 0.01
const DEADBAND_MAX_FRACTION: float = 0.25
const DEADBAND_DEFAULT_FRACTION: float = 0.05
const SLEW_MIN_SPANS_PER_S: float = 0.1
const SLEW_MAX_SPANS_PER_S: float = 100.0
const SLEW_DEFAULT_SPANS_PER_S: float = 2.0
const DELAY_MAX_S: float = 0.5
const DELAY_DEFAULT_S: float = 0.05
const LOWPASS_MIN_S: float = 0.001
const LOWPASS_MAX_S: float = 1.0
const LOWPASS_DEFAULT_S: float = 0.05

var _simulation: Simulation


# Plant-scaled starting values for every setting (effects stay OFF). Called
# once when a scenario loads, BEFORE the scenario's own overrides, so the
# panel below only reads the values and never overwrites a scenario's choice.
static func apply_defaults(simulation: Simulation) -> void:
	var output_info := simulation.plant.get_output_definition()
	var input_info := simulation.plant.get_input_definition()
	var output_span := output_info.max_value - output_info.min_value
	var input_span := input_info.max_value - input_info.min_value
	var sensor := simulation.sensor
	var actuator := simulation.actuator
	sensor.noise_std = output_span * NOISE_DEFAULT_FRACTION
	sensor.resolution = output_span * RESOLUTION_DEFAULT_FRACTION
	sensor.delay_s = DELAY_DEFAULT_S
	sensor.lowpass_tau = LOWPASS_DEFAULT_S
	actuator.saturation_min = input_info.min_value
	actuator.saturation_max = input_info.max_value
	actuator.slew_rate = input_span * SLEW_DEFAULT_SPANS_PER_S
	actuator.deadband = input_span * DEADBAND_DEFAULT_FRACTION


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	add_theme_constant_override("separation", 6)
	var sensor := simulation.sensor
	var actuator := simulation.actuator
	var output_info := simulation.plant.get_output_definition()
	var input_info := simulation.plant.get_input_definition()
	var output_span := output_info.max_value - output_info.min_value
	var input_span := input_info.max_value - input_info.min_value

	_add_heading("Sensor (what the controller sees)")

	_add_effect("Noise", sensor.noise_enabled,
			func(on: bool) -> void: sensor.noise_enabled = on,
			[_scaled_like(output_info, "noise_std", "Noise size (σ)",
				0.0, output_span * NOISE_MAX_FRACTION, sensor.noise_std,
				"Typical size of the random error added to each reading.")],
			[func(value: float) -> void: sensor.noise_std = value])

	_add_effect("Quantization", sensor.quantization_enabled,
			func(on: bool) -> void: sensor.quantization_enabled = on,
			[_scaled_like(output_info, "resolution", "Resolution (one count)",
				output_span * RESOLUTION_MIN_FRACTION, output_span * RESOLUTION_MAX_FRACTION,
				sensor.resolution,
				"Readings snap to whole multiples of this, like encoder ticks.").with_log_slider()],
			[func(value: float) -> void: sensor.resolution = value])

	_add_effect("Measurement delay", sensor.delay_enabled,
			func(on: bool) -> void: sensor.delay_enabled = on,
			[QuantityInfo.new("delay", "Delay", "s").with_display("ms", 1000.0) \
				.with_range(0.0, DELAY_MAX_S, sensor.delay_s) \
				.with_description("How old each reading is when the controller gets it.")],
			[func(value: float) -> void: sensor.delay_s = value])

	_add_effect("Low-pass filter", sensor.lowpass_enabled,
			func(on: bool) -> void: sensor.lowpass_enabled = on,
			[QuantityInfo.new("lowpass_tau", "Filter time constant (τ)", "s") \
				.with_display("ms", 1000.0) \
				.with_range(LOWPASS_MIN_S, LOWPASS_MAX_S, sensor.lowpass_tau).with_log_slider() \
				.with_description("Smooths noise, but the reading lags behind by about τ.")],
			[func(value: float) -> void: sensor.lowpass_tau = value])

	_add_heading("Actuator (what reaches the plant)")

	_add_effect("Saturation", actuator.saturation_enabled,
			func(on: bool) -> void: actuator.saturation_enabled = on,
			[_scaled_like(input_info, "saturation_min", "Lowest output",
				input_info.min_value, input_info.max_value, actuator.saturation_min,
				"The actuator can't go below this (e.g. a battery's negative rail)."),
			_scaled_like(input_info, "saturation_max", "Highest output",
				input_info.min_value, input_info.max_value, actuator.saturation_max,
				"The actuator can't go above this (e.g. a battery's voltage).")],
			[func(value: float) -> void: actuator.saturation_min = value,
			func(value: float) -> void: actuator.saturation_max = value])

	_add_effect("Slew-rate limit", actuator.slew_enabled,
			func(on: bool) -> void: actuator.slew_enabled = on,
			[_scaled_like(input_info, "slew_rate", "Fastest change",
				input_span * SLEW_MIN_SPANS_PER_S, input_span * SLEW_MAX_SPANS_PER_S,
				actuator.slew_rate,
				"How fast the actuator output can change, per second.",
				"/s").with_log_slider()],
			[func(value: float) -> void: actuator.slew_rate = value])

	_add_effect("Deadband", actuator.deadband_enabled,
			func(on: bool) -> void: actuator.deadband_enabled = on,
			[_scaled_like(input_info, "deadband", "Deadband size",
				0.0, input_span * DEADBAND_MAX_FRACTION, actuator.deadband,
				"Commands smaller than this do nothing (sticky motor, cheap driver).")],
			[func(value: float) -> void: actuator.deadband = value])


# A new QuantityInfo in the same units as `like` (e.g. noise in RPM for the
# flywheel). `unit_suffix` appends e.g. "/s" for rates.
func _scaled_like(like: QuantityInfo, key: String, title: String, min_si: float,
		max_si: float, default_si: float, description: String,
		unit_suffix: String = "") -> QuantityInfo:
	var info := QuantityInfo.new(key, title, like.si_unit + unit_suffix) \
		.with_range(min_si, max_si, default_si) \
		.with_description(description)
	if like.display_unit != "":
		info.with_display(like.display_unit + unit_suffix, like.display_scale)
	return info


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	add_child(label)


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
