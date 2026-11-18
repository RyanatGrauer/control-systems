# main_screen.gd
#
# PURPOSE
#   The default screen (README 7.1): toolbar on top, the animated plant view and
#   a side panel in the middle, live plots at the bottom. It also runs the main
#   loop that advances the simulation.
#
# HOW IT FITS (data flow each rendered frame)
#   1. SimClock converts the frame's real time into N fixed physics substeps.
#   2. Simulation.step_physics() runs N times (this is the ONLY place the live
#      simulation is advanced).
#   3. UI pieces READ the simulation: plant view, readouts, toolbar, plots.
#   UI widgets only write settings and controller inputs, never plant state.
#
# MILESTONE A SCOPE
#   One plant (flywheel) and the manual controller. The scenario picker
#   (stage 15) will replace the hard-coded plant/controller choice in _ready().
extends Control

# TUNABLE: plot time-window choices (seconds) and the default.
const PLOT_WINDOW_CHOICES_S: Array[float] = [5.0, 10.0, 20.0, 30.0, 60.0]
const DEFAULT_PLOT_WINDOW_INDEX: int = 1
const SIDE_PANEL_MIN_WIDTH: float = 340.0

var _simulation: Simulation
var _clock: SimClock
var _manual_controller: ManualController

var _toolbar: SimToolbar
var _plant_view: PlantView
var _manual_panel: ManualControlPanel
var _settings_panel: SimSettingsPanel
var _output_chart: StripChart
var _input_chart: StripChart
var _pending_physics_rate_hz: float = Simulation.DEFAULT_PHYSICS_RATE_HZ


func _ready() -> void:
	_manual_controller = ManualController.new()
	_simulation = Simulation.new(FlywheelPlant.new(), _manual_controller)
	_clock = SimClock.new(_simulation.get_physics_dt())

	_build_layout()
	_plant_view.load_plant_visual(_simulation.plant)
	_toolbar.update_play_state(_clock.is_paused)
	_report_storage_location()


func _process(delta: float) -> void:
	var steps := _clock.consume_frame(delta)
	for i in steps:
		_simulation.step_physics()

	_toolbar.update_time(_simulation.get_time())
	_toolbar.update_slow_warning(_clock.is_running_slow, delta)
	_plant_view.show_state(_simulation)
	_manual_panel.update_panel(delta)
	if steps > 0:
		_output_chart.queue_redraw()
		_input_chart.queue_redraw()


# Keyboard shortcuts come from InputMap actions (Project Settings > Input Map),
# so they can be remapped without code changes.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sim_toggle_pause"):
		_toggle_pause()
	elif event.is_action_pressed("sim_reset"):
		_reset_run()
	elif event.is_action_pressed("sim_step"):
		_step_once()
	else:
		return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ actions

func _toggle_pause() -> void:
	_set_paused(not _clock.is_paused)


func _set_paused(paused: bool) -> void:
	_clock.is_paused = paused
	_toolbar.update_play_state(paused)
	_output_chart.frozen = paused
	_input_chart.frozen = paused
	_output_chart.queue_redraw()
	_input_chart.queue_redraw()


# Advance exactly one controller tick, then stay paused.
func _step_once() -> void:
	if not _clock.is_paused:
		_set_paused(true)
	_simulation.step_many(_simulation.get_controller_period_steps())
	_output_chart.queue_redraw()
	_input_chart.queue_redraw()


func _reset_run() -> void:
	_simulation.random_seed = _toolbar.get_seed()
	_simulation.physics_rate_hz = _pending_physics_rate_hz
	_simulation.reset()
	_clock.physics_dt = _simulation.get_physics_dt()
	_clock.reset()
	_plant_view.reset_visual()
	_manual_panel.sync_from_simulation()
	_settings_panel.refresh()
	_output_chart.queue_redraw()
	_input_chart.queue_redraw()


func _on_physics_rate_changed(rate_hz: float) -> void:
	_pending_physics_rate_hz = rate_hz


# ------------------------------------------------------------------ layout

func _build_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.13, 0.14, 0.16)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)

	_toolbar = SimToolbar.new(_simulation.plant.get_display_name())
	_toolbar.play_pause_pressed.connect(_toggle_pause)
	_toolbar.step_pressed.connect(_step_once)
	_toolbar.reset_pressed.connect(_reset_run)
	_toolbar.time_scale_changed.connect(_clock.set_time_scale)
	page.add_child(_toolbar)

	# Top half (plant + side panel) and bottom half (plots), resizable.
	var vertical_split := VSplitContainer.new()
	vertical_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(vertical_split)

	var horizontal_split := HSplitContainer.new()
	horizontal_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_split.size_flags_stretch_ratio = 1.4
	vertical_split.add_child(horizontal_split)

	_plant_view = PlantView.new()
	_plant_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_split.add_child(_plant_view)
	horizontal_split.add_child(_build_side_panel())

	vertical_split.add_child(_build_plot_area())


func _build_side_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(SIDE_PANEL_MIN_WIDTH, 0.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)

	var manual_section := CollapsibleSection.new("Manual control", true)
	column.add_child(manual_section)
	_manual_panel = ManualControlPanel.new()
	manual_section.body.add_child(_manual_panel)
	_manual_panel.setup(_simulation, _manual_controller)

	var parameter_section := CollapsibleSection.new("Plant parameters", false)
	column.add_child(parameter_section)
	var parameter_panel := ParameterPanel.new()
	parameter_section.body.add_child(parameter_panel)
	parameter_panel.setup(_simulation.plant)

	var settings_section := CollapsibleSection.new("Simulation settings (advanced)", false)
	column.add_child(settings_section)
	_settings_panel = SimSettingsPanel.new()
	settings_section.body.add_child(_settings_panel)
	_settings_panel.setup(_simulation)
	_settings_panel.physics_rate_changed.connect(_on_physics_rate_changed)

	return scroll


func _build_plot_area() -> Control:
	var area := VBoxContainer.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size = Vector2(0.0, 200.0)

	# Plot options row.
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	area.add_child(options)

	var window_label := Label.new()
	window_label.text = "Plot window"
	options.add_child(window_label)
	var window_menu := OptionButton.new()
	window_menu.focus_mode = Control.FOCUS_NONE
	for seconds in PLOT_WINDOW_CHOICES_S:
		window_menu.add_item("%d s" % roundi(seconds))
	window_menu.select(DEFAULT_PLOT_WINDOW_INDEX)
	window_menu.item_selected.connect(_on_plot_window_selected)
	options.add_child(window_menu)

	var lock_axis := CheckBox.new()
	lock_axis.text = "Lock Y axes"
	lock_axis.tooltip_text = "Stop the Y axes from auto-scaling (keeps the current range)."
	lock_axis.focus_mode = Control.FOCUS_NONE
	lock_axis.toggled.connect(_on_lock_axis_toggled)
	options.add_child(lock_axis)

	var hint := Label.new()
	hint.text = "Hover a plot to read values. Pause, then drag a plot to scrub back in time."
	hint.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	hint.add_theme_font_size_override("font_size", 13)
	options.add_child(hint)

	# The two charts, side by side.
	var charts := HBoxContainer.new()
	charts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("separation", 6)
	area.add_child(charts)

	var output_info := _simulation.plant.get_output_definition()
	_output_chart = _make_chart(output_info.display_name, output_info.get_shown_unit(), 2.0)
	_output_chart.traces = [
		ChartTrace.new("setpoint", "Setpoint", SignalColors.SETPOINT,
				output_info.display_scale, true, 2.0),
		ChartTrace.new("measurement", "Measured", SignalColors.MEASUREMENT,
				output_info.display_scale, false, 2.5),
	]
	charts.add_child(_output_chart)

	var input_info := _simulation.plant.get_input_definition()
	_input_chart = _make_chart(input_info.display_name, input_info.get_shown_unit(), 1.0)
	# Applied input is drawn first so the dashed command shows on top of it.
	_input_chart.traces = [
		ChartTrace.new("applied_input", "Applied", SignalColors.APPLIED_INPUT,
				input_info.display_scale, false, 2.5),
		ChartTrace.new("command", "Command", SignalColors.COMMAND,
				input_info.display_scale, true, 2.0),
	]
	charts.add_child(_input_chart)

	_on_plot_window_selected(DEFAULT_PLOT_WINDOW_INDEX)
	return area


func _make_chart(title: String, unit: String, stretch_ratio: float) -> StripChart:
	var chart := StripChart.new()
	chart.recorder = _simulation.recorder
	chart.chart_title = title
	chart.y_unit = unit
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_stretch_ratio = stretch_ratio
	return chart


func _on_plot_window_selected(index: int) -> void:
	_output_chart.time_window_s = PLOT_WINDOW_CHOICES_S[index]
	_input_chart.time_window_s = PLOT_WINDOW_CHOICES_S[index]
	_output_chart.queue_redraw()
	_input_chart.queue_redraw()


func _on_lock_axis_toggled(locked: bool) -> void:
	_output_chart.set_y_axis_locked(locked)
	_input_chart.set_y_axis_locked(locked)


# README 7.11: we must KNOW where user:// lands (especially on the Web, where
# other itch.io games share browser storage). Printed once at startup; visible
# in the editor Output panel or the browser's developer console.
func _report_storage_location() -> void:
	print("Control Lab: user data folder = ", OS.get_user_data_dir())
	StoragePaths.check_storage_location()
