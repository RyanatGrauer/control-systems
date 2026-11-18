# setpoint_bar.gd
#
# PURPOSE
#   An always-visible strip directly under the 3D plant view for the two
#   things students do most: set a new target, and re-trigger a step response
#   after the system has settled.
#     - Target slider: applies when the mouse is RELEASED, so a drag makes one
#       clean step (and the metrics measure the response to it).
#     - Flip (key S, InputMap action "setpoint_flip"): swaps the start level and
#       the target, so the setpoint jumps back and forth. Press it again any
#       time to see another step response.
#
# HOW IT FITS
#   Edits Simulation.setpoint_generator, like the Setpoint panel in the side
#   bar. Each emits a signal when it changes something so main_screen.gd can
#   refresh the other.
class_name SetpointBar
extends PanelContainer

signal setpoint_changed

var _simulation: Simulation
var _target_slider: LabeledSlider


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.08, 0.10)
	background.set_content_margin_all(6.0)
	background.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", background)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	var output_info := simulation.plant.get_output_definition()
	_target_slider = LabeledSlider.new()
	_target_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_slider.apply_on_release = true
	row.add_child(_target_slider)
	var target_info := SetpointPanel.make_target_info(output_info)
	target_info.display_name = "Setpoint target"
	_target_slider.setup(target_info, simulation.setpoint_generator.target_level)
	_target_slider.set_title_color(SignalColors.SETPOINT)
	_target_slider.value_changed_si.connect(_on_target_changed)

	var flip_button := Button.new()
	flip_button.text = "Flip setpoint (S)"
	flip_button.tooltip_text = "Jump the setpoint between the start level and the target.\nPress again whenever the system has settled to see another step response."
	flip_button.focus_mode = Control.FOCUS_NONE
	flip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flip_button.custom_minimum_size = Vector2(0.0, 60.0)
	flip_button.pressed.connect(flip)
	row.add_child(flip_button)


# Swap the start level and the target. For a step that has already happened,
# the setpoint jumps to the old start level; pressing again jumps back.
func flip() -> void:
	var generator := _simulation.setpoint_generator
	var old_target := generator.target_level
	generator.target_level = generator.start_level
	generator.start_level = old_target
	sync_from_generator()
	setpoint_changed.emit()


func sync_from_generator() -> void:
	_target_slider.set_value_si(_simulation.setpoint_generator.target_level)


func _on_target_changed(si_value: float) -> void:
	_simulation.setpoint_generator.target_level = si_value
	setpoint_changed.emit()
