# manual_control_panel.gd
#
# PURPOSE
#   Stage 4: "you are the controller". The student sets a target speed and then
#   tries to hold the wheel there by moving the motor-voltage slider (or holding
#   the Up/Down keys). Live readouts show target, measurement and error.
#
# HOW IT FITS
#   - The target slider writes the SetpointGenerator's value.
#   - The command slider writes ManualController.manual_command.
#   - Up/Down keys are InputMap actions ("manual_command_up"/"manual_command_down"),
#     not hard-coded keys, so a gamepad can be mapped later (README 7.7).
#   The panel never touches the plant directly; everything goes through the
#   signal chain like a real controller would.
class_name ManualControlPanel
extends VBoxContainer

# TUNABLE: how fast holding Up/Down changes the command, in input units per
# second (volts/second for the flywheel).
const KEYBOARD_COMMAND_RATE: float = 4.0

var _simulation: Simulation
var _manual_controller: ManualController
var _target_slider: LabeledSlider
var _command_slider: LabeledSlider
var _readout: Label


func setup(simulation: Simulation, manual_controller: ManualController) -> void:
	_simulation = simulation
	_manual_controller = manual_controller
	add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "You are the controller. Move the motor voltage (or hold Up/Down) to keep the measured speed (blue) on the target (orange dashes)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200.0, 0.0)
	add_child(hint)

	# The target slider uses the same units and range as the plant's output.
	var output_info := simulation.plant.get_output_definition()
	var target_info := QuantityInfo.new("target",
			"Target " + output_info.display_name.to_lower(), output_info.si_unit) \
		.with_range(output_info.min_value, output_info.max_value, output_info.default_value) \
		.with_display(output_info.display_unit, output_info.display_scale) \
		.with_description("The setpoint: the value you are trying to hold.")
	_target_slider = LabeledSlider.new()
	add_child(_target_slider)
	_target_slider.setup(target_info, output_info.default_value)
	_target_slider.value_changed_si.connect(_on_target_changed)
	_on_target_changed(output_info.default_value)

	_command_slider = LabeledSlider.new()
	add_child(_command_slider)
	_command_slider.setup(simulation.plant.get_input_definition(), 0.0)
	_command_slider.value_changed_si.connect(_on_command_changed)

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 15)
	add_child(_readout)


# Called by main_screen.gd every frame.
func update_panel(frame_delta: float) -> void:
	_apply_keyboard_input(frame_delta)

	var output_info := _simulation.plant.get_output_definition()
	var unit := output_info.get_shown_unit()
	var target := output_info.si_to_shown(_simulation.setpoint)
	var measured := output_info.si_to_shown(_simulation.measurement)
	_readout.text = "Target:    %s %s\nMeasured:  %s %s\nError:     %s %s" % [
		NumberFormat.significant(target, 4), unit,
		NumberFormat.significant(measured, 4), unit,
		NumberFormat.significant(target - measured, 3), unit,
	]


# Keep the slider in sync after a reset (the controller sets its command to 0).
func sync_from_simulation() -> void:
	_command_slider.set_value_si(_manual_controller.manual_command)


func _apply_keyboard_input(frame_delta: float) -> void:
	# Ignore keys while the student is typing in a number field.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit:
		return
	var direction := Input.get_axis("manual_command_down", "manual_command_up")
	if direction == 0.0:
		return
	var input_info := _simulation.plant.get_input_definition()
	var new_command := clampf(
			_manual_controller.manual_command + direction * KEYBOARD_COMMAND_RATE * frame_delta,
			input_info.min_value, input_info.max_value)
	_manual_controller.manual_command = new_command
	_command_slider.set_value_si(new_command)


func _on_target_changed(si_value: float) -> void:
	# A target set by hand is a constant setpoint (a "step" at time zero).
	_simulation.setpoint_generator.step_time = 0.0
	_simulation.setpoint_generator.final_value = si_value


func _on_command_changed(si_value: float) -> void:
	_manual_controller.manual_command = si_value
