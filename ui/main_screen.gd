# main_screen.gd
#
# PURPOSE
#   The default screen (README 7.1): toolbar on top, the animated plant view and
#   a side panel in the middle, live plots and metrics at the bottom. It also
#   runs the main loop that advances the simulation.
#
# HOW IT FITS (data flow each rendered frame)
#   1. SimClock converts the frame's real time into N fixed physics substeps.
#   2. Simulation.step_physics() runs N times (this is the ONLY place the live
#      simulation is advanced).
#   3. UI pieces READ the simulation: plant view, readouts, toolbar, plots.
#   UI widgets only write settings and controller inputs, never plant state.
#
# SWITCHING PLANTS
#   Choosing a plant in the toolbar rebuilds the simulation AND the whole UI
#   (sliders, plots and units all depend on the plant). The seed, time scale
#   and controller mode carry over. Stage 15 replaces the plant picker with
#   scenario files.
extends Control

enum ControllerMode { MANUAL, PID }

# TUNABLE: plot time-window choices (seconds) and the default.
const PLOT_WINDOW_CHOICES_S: Array[float] = [5.0, 10.0, 20.0, 30.0, 60.0]
const DEFAULT_PLOT_WINDOW_INDEX: int = 1
const SIDE_PANEL_MIN_WIDTH: float = 350.0

# Survive a plant switch.
var _plant_index: int = 0
var _controller_mode: ControllerMode = ControllerMode.MANUAL
var _plot_window_index: int = DEFAULT_PLOT_WINDOW_INDEX

var _simulation: Simulation
var _clock: SimClock
var _manual_controller: ManualController
var _pid_controller: PidController
var _pending_physics_rate_hz: float = Simulation.DEFAULT_PHYSICS_RATE_HZ

var _toolbar: SimToolbar
var _plant_view: PlantView
var _manual_panel: ManualControlPanel
var _pid_panel: PidPanel
var _setpoint_panel: SetpointPanel
var _setpoint_bar: SetpointBar
var _settings_panel: SimSettingsPanel
var _metrics_bar: MetricsBar
var _charts: Array[StripChart] = []
var _true_output_trace: ChartTrace


func _ready() -> void:
	_load_plant(0, Simulation.DEFAULT_SEED, 1.0)
	_report_storage_location()


func _process(delta: float) -> void:
	var steps := _clock.consume_frame(delta)
	for i in steps:
		_simulation.step_physics()

	_toolbar.update_time(_simulation.get_time())
	_toolbar.update_slow_warning(_clock.is_running_slow, delta)
	_plant_view.show_state(_simulation)
	_setpoint_panel.update_panel()
	if _controller_mode == ControllerMode.MANUAL:
		_manual_panel.update_panel(delta)
	else:
		_pid_panel.update_panel()
	_metrics_bar.update_bar(delta)
	_true_output_trace.visible = not _simulation.sensor.is_ideal()
	if steps > 0:
		_redraw_charts()


# Keyboard shortcuts come from InputMap actions (Project Settings > Input Map),
# so they can be remapped without code changes.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sim_toggle_pause"):
		_toggle_pause()
	elif event.is_action_pressed("sim_reset"):
		_reset_run()
	elif event.is_action_pressed("sim_step"):
		_step_once()
	elif event.is_action_pressed("setpoint_flip"):
		_setpoint_bar.flip()
	elif not _handle_gain_shortcut(event):
		return
	get_viewport().set_input_as_handled()


# P / I / D select a gain, [ and ] nudge it. Only in PID mode.
func _handle_gain_shortcut(event: InputEvent) -> bool:
	if _controller_mode != ControllerMode.PID:
		return false
	if event.is_action_pressed("gain_select_p"):
		_pid_panel.select_gain(0)
	elif event.is_action_pressed("gain_select_i"):
		_pid_panel.select_gain(1)
	elif event.is_action_pressed("gain_select_d"):
		_pid_panel.select_gain(2)
	elif event.is_action_pressed("gain_nudge_up", true):
		_pid_panel.nudge_selected_gain(1.0)
	elif event.is_action_pressed("gain_nudge_down", true):
		_pid_panel.nudge_selected_gain(-1.0)
	else:
		return false
	return true


# ------------------------------------------------------------------ actions

func _load_plant(index: int, random_seed: int, time_scale: float) -> void:
	_plant_index = index
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_charts.clear()

	var plant := PlantCatalog.create_plant(index)
	_manual_controller = ManualController.new()
	_pid_controller = PidController.new()
	var gains := plant.get_pid_gain_definitions()
	_pid_controller.proportional_gain = gains[0].default_value
	_pid_controller.integral_gain = gains[1].default_value
	_pid_controller.derivative_gain = gains[2].default_value
	_pid_controller.output_min = plant.get_input_definition().min_value
	_pid_controller.output_max = plant.get_input_definition().max_value

	_simulation = Simulation.new(plant, _active_controller())
	_simulation.physics_rate_hz = _pending_physics_rate_hz
	_simulation.random_seed = random_seed
	_clock = SimClock.new(_simulation.get_physics_dt())

	_build_layout()
	_toolbar.set_seed(random_seed)
	_toolbar.set_time_scale(time_scale)
	_plant_view.load_plant_visual(plant)
	_set_paused(false)
	_reset_run()  # applies seed and physics rate, and starts the setpoint at t = 0


func _on_plant_selected(index: int) -> void:
	# Deferred: the toolbar that sent this signal is about to be freed.
	_load_plant.call_deferred(index, _toolbar.get_seed(), _clock.time_scale)


func _active_controller() -> Controller:
	if _controller_mode == ControllerMode.PID:
		return _pid_controller
	return _manual_controller


func _on_controller_mode_selected(index: int) -> void:
	_controller_mode = index as ControllerMode
	_simulation.set_controller(_active_controller())
	_manual_panel.visible = _controller_mode == ControllerMode.MANUAL
	_pid_panel.visible = _controller_mode == ControllerMode.PID
	_manual_panel.sync_from_simulation()


func _toggle_pause() -> void:
	_set_paused(not _clock.is_paused)


func _set_paused(paused: bool) -> void:
	_clock.is_paused = paused
	_toolbar.update_play_state(paused)
	for chart in _charts:
		chart.frozen = paused
	_redraw_charts()


# Advance exactly one controller tick, then stay paused.
func _step_once() -> void:
	if not _clock.is_paused:
		_set_paused(true)
	_simulation.step_many(_simulation.get_controller_period_steps())
	_redraw_charts()
	_metrics_bar.refresh()


func _reset_run() -> void:
	_simulation.random_seed = _toolbar.get_seed()
	_simulation.physics_rate_hz = _pending_physics_rate_hz
	_simulation.reset()
	_clock.physics_dt = _simulation.get_physics_dt()
	_clock.reset()
	_plant_view.reset_visual()
	_manual_panel.sync_from_simulation()
	_settings_panel.refresh()
	_metrics_bar.refresh()
	_redraw_charts()


func _on_physics_rate_changed(rate_hz: float) -> void:
	_pending_physics_rate_hz = rate_hz


func _redraw_charts() -> void:
	for chart in _charts:
		chart.queue_redraw()


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

	_toolbar = SimToolbar.new(PlantCatalog.get_plant_names(), _plant_index)
	_toolbar.play_pause_pressed.connect(_toggle_pause)
	_toolbar.step_pressed.connect(_step_once)
	_toolbar.reset_pressed.connect(_reset_run)
	_toolbar.time_scale_changed.connect(_clock.set_time_scale)
	_toolbar.plant_selected.connect(_on_plant_selected)
	page.add_child(_toolbar)

	# Top half (plant + side panel) and bottom half (plots), resizable.
	var vertical_split := VSplitContainer.new()
	vertical_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(vertical_split)

	var horizontal_split := HSplitContainer.new()
	horizontal_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_split.size_flags_stretch_ratio = 1.5
	vertical_split.add_child(horizontal_split)

	_plant_view = PlantView.new()
	_plant_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_split.add_child(_plant_view)
	horizontal_split.add_child(_build_side_panel())

	# Always-visible setpoint controls right under the 3D scene.
	_plant_view.poked.connect(_simulation.poke)

	_setpoint_bar = SetpointBar.new()
	_setpoint_bar.setup(_simulation)
	_plant_view.set_bottom_bar(_setpoint_bar)
	_setpoint_bar.setpoint_changed.connect(_setpoint_panel.sync_from_generator)
	_setpoint_panel.settings_changed.connect(_setpoint_bar.sync_from_generator)

	vertical_split.add_child(_build_plot_area())


func _build_side_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(SIDE_PANEL_MIN_WIDTH, 0.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)

	# --- Controller: mode picker + the matching panel ---
	var controller_section := CollapsibleSection.new("Controller", true)
	column.add_child(controller_section)
	var mode_menu := OptionButton.new()
	mode_menu.focus_mode = Control.FOCUS_NONE
	mode_menu.add_item("Manual (you are the controller)", ControllerMode.MANUAL)
	mode_menu.add_item("PID", ControllerMode.PID)
	mode_menu.select(_controller_mode)
	mode_menu.item_selected.connect(_on_controller_mode_selected)
	controller_section.body.add_child(mode_menu)

	_manual_panel = ManualControlPanel.new()
	controller_section.body.add_child(_manual_panel)
	_manual_panel.setup(_simulation, _manual_controller)
	_pid_panel = PidPanel.new()
	controller_section.body.add_child(_pid_panel)
	_pid_panel.setup(_simulation, _pid_controller)
	_manual_panel.visible = _controller_mode == ControllerMode.MANUAL
	_pid_panel.visible = _controller_mode == ControllerMode.PID

	# --- Setpoint ---
	var setpoint_section := CollapsibleSection.new("Setpoint", true)
	column.add_child(setpoint_section)
	_setpoint_panel = SetpointPanel.new()
	setpoint_section.body.add_child(_setpoint_panel)
	_setpoint_panel.setup(_simulation)

	# --- Sensor & actuator non-idealities (README 7.5) ---
	var nonideality_section := CollapsibleSection.new("Sensor & actuator", false)
	column.add_child(nonideality_section)
	var nonideality_panel := NonidealityPanel.new()
	nonideality_section.body.add_child(nonideality_panel)
	nonideality_panel.setup(_simulation)

	# --- Disturbances (README 7.5, stage 14) ---
	var disturbance_section := CollapsibleSection.new("Disturbances", false)
	column.add_child(disturbance_section)
	var disturbance_panel := DisturbancePanel.new()
	disturbance_section.body.add_child(disturbance_panel)
	disturbance_panel.setup(_simulation)

	# --- Plant parameters ---
	var parameter_section := CollapsibleSection.new("Plant parameters", false)
	column.add_child(parameter_section)
	var parameter_panel := ParameterPanel.new()
	parameter_section.body.add_child(parameter_panel)
	parameter_panel.setup(_simulation.plant)

	# --- Simulation settings ---
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
	area.custom_minimum_size = Vector2(0.0, 220.0)

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
	window_menu.select(_plot_window_index)
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

	# Output chart on the left; command / PID terms / error as tabs on the right.
	var charts := HBoxContainer.new()
	charts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("separation", 6)
	area.add_child(charts)

	var output_info := _simulation.plant.get_output_definition()
	var input_info := _simulation.plant.get_input_definition()
	var output_scale := output_info.display_scale
	var input_scale := input_info.display_scale

	_true_output_trace = ChartTrace.new("true_output", "True", SignalColors.TRUE_OUTPUT,
			output_scale, false, 1.5)
	var output_chart := _make_chart(output_info.display_name, output_info.get_shown_unit(), [
		ChartTrace.new("setpoint", "Setpoint", SignalColors.SETPOINT, output_scale, true, 2.0),
		ChartTrace.new("measurement", "Measured", SignalColors.MEASUREMENT, output_scale, false, 2.5),
		# Drawn on top, thin, so it stays visible inside a noisy measurement.
		# Shown only while the sensor is non-ideal (otherwise it hides "Measured").
		_true_output_trace,
	])
	output_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_chart.size_flags_stretch_ratio = 1.5
	charts.add_child(output_chart)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	charts.add_child(tabs)

	# Applied input is drawn first so the dashed command shows on top of it.
	var command_chart := _make_chart(input_info.display_name, input_info.get_shown_unit(), [
		ChartTrace.new("applied_input", "Applied", SignalColors.APPLIED_INPUT, input_scale, false, 2.5),
		ChartTrace.new("command", "Command", SignalColors.COMMAND, input_scale, true, 2.0),
	])
	command_chart.name = "Command"
	tabs.add_child(command_chart)

	var terms_chart := _make_chart("PID terms", input_info.get_shown_unit(), [
		ChartTrace.new("p_term", "P", SignalColors.P_TERM, input_scale, false, 2.0),
		ChartTrace.new("i_term", "I", SignalColors.I_TERM, input_scale, false, 2.0),
		ChartTrace.new("d_term", "D", SignalColors.D_TERM, input_scale, false, 2.0),
		ChartTrace.new("ff_term", "FF", SignalColors.FF_TERM, input_scale, false, 2.0),
		ChartTrace.new("controller_sum", "Sum", SignalColors.TERM_SUM, input_scale, true, 1.5),
	])
	terms_chart.name = "Terms"
	tabs.add_child(terms_chart)
	# Node names cannot contain "/", so set the visible tab title directly.
	tabs.set_tab_title(tabs.get_tab_idx_from_control(terms_chart), "P/I/D terms")

	var error_chart := _make_chart("Error (setpoint - measured)", output_info.get_shown_unit(), [
		ChartTrace.new("error", "Error", SignalColors.ERROR, output_scale, false, 2.0),
	])
	error_chart.name = "Error"
	tabs.add_child(error_chart)

	var disturbance_info := _simulation.plant.get_disturbance_definition()
	var disturbance_chart := _make_chart(disturbance_info.display_name,
			disturbance_info.get_shown_unit(), [
		ChartTrace.new("disturbance", "Disturbance", SignalColors.DISTURBANCE,
				disturbance_info.display_scale, false, 2.0),
	])
	disturbance_chart.name = "Disturbance"
	tabs.add_child(disturbance_chart)

	_metrics_bar = MetricsBar.new()
	area.add_child(_metrics_bar)
	_metrics_bar.setup(_simulation)

	_on_plot_window_selected(_plot_window_index)
	return area


func _make_chart(title: String, unit: String, traces: Array[ChartTrace]) -> StripChart:
	var chart := StripChart.new()
	chart.recorder = _simulation.recorder
	chart.chart_title = title
	chart.y_unit = unit
	chart.traces = traces
	_charts.append(chart)
	return chart


func _on_plot_window_selected(index: int) -> void:
	_plot_window_index = index
	for chart in _charts:
		chart.time_window_s = PLOT_WINDOW_CHOICES_S[index]
	_redraw_charts()


func _on_lock_axis_toggled(locked: bool) -> void:
	for chart in _charts:
		chart.set_y_axis_locked(locked)


# README 7.11: we must KNOW where user:// lands (especially on the Web, where
# other itch.io games share browser storage). Printed once at startup; visible
# in the editor Output panel or the browser's developer console.
func _report_storage_location() -> void:
	print("Control Lab: user data folder = ", OS.get_user_data_dir())
	StoragePaths.check_storage_location()
