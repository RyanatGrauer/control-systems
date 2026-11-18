# sim_toolbar.gd
#
# PURPOSE
#   The top bar (README 7.1): scenario name, Play/Pause, Step, Reset, the
#   time-scale slider, the random seed, a simulated-time readout, a "running
#   slower than real time" warning, and a fullscreen toggle.
#
# HOW IT FITS
#   It only emits signals; main_screen.gd decides what they do. That keeps the
#   toolbar free of simulation logic. main_screen.gd calls the update_*()
#   functions every frame so the bar shows the current state.
#   (Scenario picker and Presenter toggle arrive in stages 15 and 18.)
class_name SimToolbar
extends PanelContainer

signal play_pause_pressed
signal step_pressed
signal reset_pressed
signal time_scale_changed(new_scale: float)
signal seed_changed(new_seed: int)

# TUNABLE: how long the "slower than real time" warning stays visible after
# the last slow frame, so it does not flicker.
const SLOW_WARNING_HOLD_S: float = 1.0

var _play_button: Button
var _time_scale_slider: HSlider
var _time_scale_label: Label
var _seed_box: SpinBox
var _time_label: Label
var _slow_label: Label
var _slow_warning_timer: float = 0.0


func _init(scenario_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var title := Label.new()
	title.text = scenario_name
	title.add_theme_font_size_override("font_size", 16)
	row.add_child(title)
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
	row.add_child(seed_title)

	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 999999
	_seed_box.step = 1
	_seed_box.value = Simulation.DEFAULT_SEED
	_seed_box.tooltip_text = seed_title.tooltip_text
	_seed_box.value_changed.connect(_on_seed_changed)
	row.add_child(_seed_box)
	row.add_child(VSeparator.new())

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

	var fullscreen_button := _make_button("Fullscreen", "Toggle fullscreen")
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	row.add_child(fullscreen_button)


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
