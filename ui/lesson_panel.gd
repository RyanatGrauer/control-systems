# lesson_panel.gd
#
# PURPOSE
#   The Lesson tab (README 7.6 mode 2): "Step 2 of 5", the prompt, what the
#   step is still waiting for (or "Done!"), and Back / Next / Start over.
#
# HOW IT FITS
#   Display only. main_screen.gd owns the step index, evaluates the step's
#   check with LessonChecks every frame, applies the hidden/locked controls,
#   saves progress, and calls show_step() / show_status() here.
class_name LessonPanel
extends ScrollContainer

signal back_pressed
signal next_pressed
signal restart_pressed

var _step_label: Label
var _prompt: Label
var _status: Label
var _back_button: Button
var _next_button: Button
var _last_status: String = "-"  # avoids re-setting the same text every frame


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 15)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 15)
	column.add_child(top_row)
	_step_label = Label.new()
	_step_label.add_theme_color_override("font_color", SignalColors.SETPOINT)
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_step_label)
	_back_button = _make_button("Back", "Go back one step.")
	_back_button.pressed.connect(back_pressed.emit)
	top_row.add_child(_back_button)
	_next_button = _make_button("Next", "Go to the next step. Unlocks when the step is done.")
	_next_button.custom_minimum_size = Vector2(150.0, 0.0)
	_next_button.pressed.connect(next_pressed.emit)
	top_row.add_child(_next_button)
	var restart := _make_button("Start over", "Go back to step 1 (the controls lock again).")
	restart.pressed.connect(restart_pressed.emit)
	top_row.add_child(restart)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", UiStyle.LARGE)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(300.0, 0.0)
	column.add_child(_prompt)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300.0, 0.0)
	column.add_child(_status)


func show_step(index: int, total: int, prompt: String, is_finished: bool) -> void:
	_step_label.text = "Lesson complete" if is_finished else "Step %d of %d" % [index + 1, total]
	_prompt.text = prompt
	_back_button.disabled = index == 0 and not is_finished
	_next_button.visible = not is_finished
	_next_button.text = "Finish" if index == total - 1 else "Next"
	_last_status = "-"


# waiting_for = "" when the step is done.
func show_status(waiting_for: String, has_check: bool) -> void:
	if waiting_for == _last_status:
		return
	_last_status = waiting_for
	_next_button.disabled = waiting_for != ""
	if waiting_for != "":
		_status.text = "Waiting for: " + waiting_for
		_status.add_theme_color_override("font_color", UiStyle.HINT_COLOR)
		_next_button.remove_theme_color_override("font_color")
	elif has_check:
		_status.text = "Done! Press Next."
		_status.add_theme_color_override("font_color", SignalColors.SPEC_BAND)
		_next_button.add_theme_color_override("font_color", SignalColors.SPEC_BAND)
	else:
		_status.text = ""
		_next_button.remove_theme_color_override("font_color")


func _make_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	return button
