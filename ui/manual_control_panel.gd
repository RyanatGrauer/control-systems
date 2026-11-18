# manual_control_panel.gd
#
# PURPOSE
#   Stage 4: "you are the controller". The student tries to hold the setpoint by
#   moving the plant-input slider (or holding the Up/Down keys). The target
#   itself is chosen in the Setpoint panel.
#
# HOW IT FITS
#   - The command slider writes ManualController.manual_command.
#   - Up/Down keys are InputMap actions ("manual_command_up"/"manual_command_down"),
#     not hard-coded keys, so a gamepad can be mapped later (README 7.7).
#   The panel never touches the plant directly; everything goes through the
#   signal chain like a real controller would.
class_name ManualControlPanel
extends VBoxContainer

# TUNABLE: how fast holding Up/Down changes the command, as a fraction of the
# input's full range per second (12 V range -> 4 V/s on the flywheel).
const KEYBOARD_COMMAND_RATE_FRACTION: float = 1.0 / 6.0

var _simulation: Simulation
var _manual_controller: ManualController
var _command_slider: LabeledSlider


func setup(simulation: Simulation, manual_controller: ManualController) -> void:
	_simulation = simulation
	_manual_controller = manual_controller
	add_theme_constant_override("separation", 12)

	var input_info := simulation.plant.get_input_definition()
	add_child(UiStyle.make_hint("You are the controller: move the %s slider (or hold Up/Down) to keep blue on the orange dashes." % input_info.display_name.to_lower()))

	_command_slider = LabeledSlider.new()
	add_child(_command_slider)
	_command_slider.setup(input_info, manual_controller.manual_command)
	_command_slider.value_changed_si.connect(_on_command_changed)


# Called by main_screen.gd every frame while manual control is active.
func update_panel(frame_delta: float) -> void:
	# Ignore keys while the student is typing in a number field.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit:
		return
	var direction := Input.get_axis("manual_command_down", "manual_command_up")
	if direction == 0.0:
		return
	var input_info := _simulation.plant.get_input_definition()
	var rate := (input_info.max_value - input_info.min_value) * KEYBOARD_COMMAND_RATE_FRACTION
	var new_command := clampf(_manual_controller.manual_command + direction * rate * frame_delta,
			input_info.min_value, input_info.max_value)
	_manual_controller.manual_command = new_command
	_command_slider.set_value_si(new_command)


# Keep the slider in sync after a reset (the controller sets its command to 0).
func sync_from_simulation() -> void:
	_command_slider.set_value_si(_manual_controller.manual_command)


func _on_command_changed(si_value: float) -> void:
	_manual_controller.manual_command = si_value
