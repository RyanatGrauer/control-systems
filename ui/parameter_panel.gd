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
class_name ParameterPanel
extends VBoxContainer

var _plant: Plant
var _sliders: Dictionary = {}  # parameter key -> LabeledSlider


func setup(plant: Plant) -> void:
	_plant = plant
	add_theme_constant_override("separation", 8)
	for info in plant.get_parameter_definitions():
		var slider := LabeledSlider.new()
		add_child(slider)
		slider.setup(info, plant.get_parameter(info.key))
		slider.value_changed_si.connect(_on_parameter_changed.bind(info.key))
		_sliders[info.key] = slider

	var restore_button := Button.new()
	restore_button.text = "Restore default parameters"
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.pressed.connect(_on_restore_defaults)
	add_child(restore_button)


func _on_parameter_changed(si_value: float, key: String) -> void:
	_plant.set_parameter(key, si_value)


func _on_restore_defaults() -> void:
	for info in _plant.get_parameter_definitions():
		_plant.set_parameter(info.key, info.default_value)
		var slider: LabeledSlider = _sliders[info.key]
		slider.set_value_si(info.default_value)
