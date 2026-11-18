# sim_toolbar.gd
#
# PURPOSE
#   The top bar (README 7.1): scenario picker, Play/Pause, Step, Reset, the
#   time-scale slider, the random seed, a simulated-time readout, a "running
#   slower than real time" warning, and a fullscreen toggle.
#
# HOW IT FITS
#   It only emits signals; main_screen.gd decides what they do. That keeps the
#   toolbar free of simulation logic. main_screen.gd calls the update_*()
#   functions every frame so the bar shows the current state.
#   (The Presenter toggle arrives in stage 18.)
class_name SimToolbar
extends PanelContainer

signal play_pause_pressed
signal step_pressed
signal reset_pressed
signal time_scale_changed(new_scale: float)
signal seed_changed(new_seed: int)
signal scenario_selected(index: int)
signal presenter_pressed

# TUNABLE: how long the "slower than real time" warning stays visible after
# the last slow frame, so it does not flicker.
const SLOW_WARNING_HOLD_S: float = 1.0

var _presenter_button: Button
var _hidden_when_compact: Array[Control] = []  # presenter mode drops these to fit
var _play_button: Button
var _time_scale_slider: HSlider
var _time_scale_label: Label
var _seed_box: SpinBox
var _time_label: Label
var _slow_label: Label
var _slow_warning_timer: float = 0.0


func _init(scenario_titles: PackedStringArray, selected_scenario: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var scenario_menu := OptionButton.new()
	scenario_menu.focus_mode = Control.FOCUS_NONE
	scenario_menu.tooltip_text = "Choose a scenario (a system to control, set up for a lesson)"
	for scenario_title in scenario_titles:
		scenario_menu.add_item(scenario_title)
	scenario_menu.select(selected_scenario)
	# Fixed width (long titles are clipped) so the toolbar fits presenter mode.
	scenario_menu.fit_to_longest_item = false
	scenario_menu.clip_text = true
	scenario_menu.custom_minimum_size = Vector2(230.0, 0.0)  # TUNABLE
	# The popup's index_pressed fires even when the CURRENT scenario is chosen
	# again, so re-choosing it reloads it (restoring all its settings).
	# (OptionButton.item_selected only fires on a change.)
	scenario_menu.get_popup().index_pressed.connect(scenario_selected.emit)
	row.add_child(scenario_menu)
	row.add_child(VSeparator.new())

	_play_button = _make_button("Play", "Start or pause the simulation (Space)")
	_play_button.custom_minimum_size = Vector2(72.0, 0.0)
	_play_button.pressed.connect(play_pause_pressed.emit)
	row.add_child(_play_button)

	var step_button := _make_button("Step", "Advance one controller tick while paused (.)")
	step_button.pressed.connect(step_pressed.emit)
	row.add_child(step_button)

	var reset_button := _make_button("Reset", "Start a new run from time zero (R)")
	reset_button.pressed.connect(reset_pressed.emit)
	row.add_child(reset_button)
	row.add_child(VSeparator.new())

	var speed_title := Label.new()
	speed_title.text = "Time scale"
	row.add_child(speed_title)
	_hidden_when_compact.append(speed_title)

	# Log mapping: time scale = 4^position. Position 0 is 1x (real time), the
	# right end (1) is 4x, the left end is MIN_TIME_SCALE (0.1x). Equal slider
	# travel multiplies the speed by the same factor.
	_time_scale_slider = HSlider.new()
	_time_scale_slider.min_value = log(SimClock.MIN_TIME_SCALE) / log(4.0)
	_time_scale_slider.max_value = 1.0
	_time_scale_slider.step = 0.01
	_time_scale_slider.value = 0.0
	_time_scale_slider.custom_minimum_size = Vector2(100.0, 0.0)
	_time_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_scale_slider.focus_mode = Control.FOCUS_NONE
	_time_scale_slider.tooltip_text = "Slow motion or fast forward. Double-click the label to reset."
	_time_scale_slider.value_changed.connect(_on_time_scale_slider_changed)
	row.add_child(_time_scale_slider)

	_time_scale_label = Label.new()
	_time_scale_label.custom_minimum_size = Vector2(52.0, 0.0)
	_time_scale_label.text = "1.00×"
	_time_scale_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_time_scale_label.gui_input.connect(_on_time_scale_label_input)
	row.add_child(_time_scale_label)
	row.add_child(VSeparator.new())

	var seed_title := Label.new()
	seed_title.text = "Seed"
	seed_title.tooltip_text = "Random seed for noise and disturbances. Same seed + same settings = identical run. Applied on Reset."
	seed_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_hidden_when_compact.append(seed_title)
	row.add_child(seed_title)

	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 999999
	_seed_box.step = 1
	_seed_box.value = Simulation.DEFAULT_SEED
	_seed_box.tooltip_text = seed_title.tooltip_text
	_seed_box.value_changed.connect(_on_seed_changed)
	row.add_child(_seed_box)
	var seed_separator := VSeparator.new()
	row.add_child(seed_separator)
	_hidden_when_compact.append_array([_seed_box, seed_separator])

	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(_time_label)

	_slow_label = Label.new()
	_slow_label.text = "SLOW"  # short so the toolbar fits 1280 px; tooltip explains
	_slow_label.add_theme_color_override("font_color", SignalColors.WARNING_TEXT)
	_slow_label.tooltip_text = "Running slower than real time: this computer can't keep up, so simulated time is slowed down. No steps are skipped; results are still correct."
	_slow_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_slow_label.modulate.a = 0.0
	row.add_child(_slow_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_presenter_button = _make_button("Presenter", "Presenter mode (F2): bigger text, thicker lines, high contrast, fewer panels")
	_presenter_button.toggle_mode = true
	_presenter_button.pressed.connect(func() -> void: presenter_pressed.emit())
	row.add_child(_presenter_button)

	var fullscreen_button := _make_button("Fullscreen", "Toggle fullscreen")
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	row.add_child(fullscreen_button)


# Presenter mode: the button shows the state, and the toolbar drops the seed
# and the "Time scale" title so it still fits at the bigger UI scale.
func set_presenter(is_on: bool) -> void:
	_presenter_button.set_pressed_no_signal(is_on)
	# Highlighted while on. (Same text both ways: a longer label would make
	# the toolbar too wide for presenter mode.)
	if is_on:
		_presenter_button.add_theme_color_override("font_color", SignalColors.SETPOINT)
		_presenter_button.add_theme_color_override("font_pressed_color", SignalColors.SETPOINT)
	else:
		_presenter_button.remove_theme_color_override("font_color")
		_presenter_button.remove_theme_color_override("font_pressed_color")
	for control in _hidden_when_compact:
		control.visible = not is_on


func update_play_state(is_paused: bool) -> void:
	_play_button.text = "Play" if is_paused else "Pause"


func update_time(sim_time: float) -> void:
	_time_label.text = "t = %s s" % String.num(sim_time, 2).pad_decimals(2)


func update_slow_warning(is_running_slow: bool, frame_delta: float) -> void:
	if is_running_slow:
		_slow_warning_timer = SLOW_WARNING_HOLD_S
	else:
		_slow_warning_timer = maxf(_slow_warning_timer - frame_delta, 0.0)
	# Fade instead of show/hide so the toolbar layout never jumps.
	_slow_label.modulate.a = 1.0 if _slow_warning_timer > 0.0 else 0.0


func get_seed() -> int:
	return int(_seed_box.value)


func set_seed(new_seed: int) -> void:
	_seed_box.set_value_no_signal(new_seed)


# Moves the slider; its value_changed signal then updates the clock.
func set_time_scale(new_scale: float) -> void:
	_time_scale_slider.value = log(new_scale) / log(4.0)


func _make_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	# No keyboard focus, so Space always means play/pause (not "press button").
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_time_scale_slider_changed(position_value: float) -> void:
	var new_scale := pow(4.0, position_value)
	_time_scale_label.text = "%s×" % String.num(new_scale, 2).pad_decimals(2)
	time_scale_changed.emit(new_scale)


func _on_time_scale_label_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.double_click:
		_time_scale_slider.value = 0.0  # back to real time


func _on_seed_changed(value: float) -> void:
	seed_changed.emit(int(value))


func _on_fullscreen_pressed() -> void:
	# Must come from a click: browsers only allow fullscreen after user input.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
