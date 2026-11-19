# parameter_panel.gd
#
# PURPOSE
#   Builds one LabeledSlider per plant parameter, straight from the plant's
#   metadata (README 9: "parameter metadata drives the UI"). Add a parameter to
#   a plant and its slider appears here with no UI changes.
#
# HOW IT FITS
#   Writing a slider calls Plant.set_parameter(), which the very next physics
#   substep uses, so changes apply live while the simulation runs.
#
# MYSTERY MODE (stage 24)
#   The checkbox at the top asks main_screen.gd for a mystery plant (random,
#   hidden parameters, see core/mystery.gd). While it is on, the sliders are
#   hidden; "New mystery" re-rolls and "Reveal" lists the true values.
class_name ParameterPanel
extends VBoxContainer

signal mystery_toggled(is_on: bool)
signal new_mystery_requested

var _plant: Plant
var _sliders: Dictionary = {}  # parameter key -> LabeledSlider
var _normal_controls: Array[Control] = []  # hidden in mystery mode
var _mystery_checkbox: CheckBox
var _mystery_box: VBoxContainer
var _mystery_hint: Label
var _reveal_label: Label


func setup(plant: Plant) -> void:
	_plant = plant
	add_theme_constant_override("separation", 12)
	_build_mystery_controls()
	for info in plant.get_parameter_definitions():
		var slider := LabeledSlider.new()
		add_child(slider)
		slider.setup(info, plant.get_parameter(info.key))
		slider.value_changed_si.connect(_on_parameter_changed.bind(info.key))
		_sliders[info.key] = slider
		_normal_controls.append(slider)

	var restore_button := Button.new()
	restore_button.text = "Restore default parameters"
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.pressed.connect(_on_restore_defaults)
	add_child(restore_button)
	_normal_controls.append(restore_button)


# Shows (or hides) mystery mode. `number` labels the current mystery plant.
func show_mystery(is_on: bool, number: int) -> void:
	_mystery_checkbox.set_pressed_no_signal(is_on)
	_mystery_box.visible = is_on
	for control in _normal_controls:
		control.visible = not is_on
	_reveal_label.visible = false
	_mystery_hint.text = "Mystery plant #%d: its parameters are random (between ½× and %s× normal) and hidden. Find good gains by watching how it responds." % [
		number, String.num(Mystery.SPREAD)]
	if not is_on:
		sync_from_plant()


# Slider positions from the plant's current values (after a mystery ends).
func sync_from_plant() -> void:
	for key: String in _sliders:
		(_sliders[key] as LabeledSlider).set_value_si(_plant.get_parameter(key))


func _build_mystery_controls() -> void:
	_mystery_checkbox = CheckBox.new()
	_mystery_checkbox.text = "Mystery plant"
	_mystery_checkbox.tooltip_text = "Randomize this plant's parameters and hide them, so you have to tune by watching, not calculating."
	_mystery_checkbox.focus_mode = Control.FOCUS_NONE
	_mystery_checkbox.toggled.connect(mystery_toggled.emit)
	add_child(_mystery_checkbox)
	_mystery_box = VBoxContainer.new()
	_mystery_box.add_theme_constant_override("separation", 10)
	_mystery_box.visible = false
	add_child(_mystery_box)
	_mystery_hint = UiStyle.make_hint("")
	_mystery_box.add_child(_mystery_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_mystery_box.add_child(row)
	var new_button := Button.new()
	new_button.text = "New mystery"
	new_button.tooltip_text = "Roll a different random plant (starts a new run)."
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.pressed.connect(new_mystery_requested.emit)
	row.add_child(new_button)
	var reveal_button := Button.new()
	reveal_button.text = "Reveal"
	reveal_button.tooltip_text = "Show the true parameter values (for the debrief)."
	reveal_button.focus_mode = Control.FOCUS_NONE
	reveal_button.pressed.connect(_on_reveal)
	row.add_child(reveal_button)
	_reveal_label = Label.new()
	_reveal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal_label.custom_minimum_size = Vector2(240.0, 0.0)
	_reveal_label.visible = false
	_mystery_box.add_child(_reveal_label)


func _on_reveal() -> void:
	var lines: PackedStringArray = []
	for info in _plant.get_parameter_definitions():
		var value := _plant.get_parameter(info.key)
		var ratio := value / info.default_value if info.default_value != 0.0 else NAN
		lines.append("%s: %s %s%s" % [info.display_name,
			NumberFormat.significant(info.si_to_shown(value), 3), info.get_shown_unit(),
			"" if is_nan(ratio) else "  (%s× normal)" % NumberFormat.significant(ratio, 2)])
	_reveal_label.text = "\n".join(lines)
	_reveal_label.visible = true


func _on_parameter_changed(si_value: float, key: String) -> void:
	_plant.set_parameter(key, si_value)


func _on_restore_defaults() -> void:
	for info in _plant.get_parameter_definitions():
		_plant.set_parameter(info.key, info.default_value)
		var slider: LabeledSlider = _sliders[info.key]
		slider.set_value_si(info.default_value)
