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
# SWITCHING SCENARIOS
#   Choosing a scenario (res://scenarios/*.tres) in the toolbar rebuilds the
#   simulation AND the whole UI (sliders, plots and units all depend on the
#   plant). The order is: plant + parameter overrides -> controllers and
#   plant-scaled panel defaults -> the scenario's other overrides -> UI.
#   The seed and time scale carry over; the controller mode comes from the
#   scenario. Reset restarts the run but keeps the student's changes.
extends Control

enum ControllerMode { MANUAL, PID, CASCADED_PID }  # same order as Scenario.StartMode

# TUNABLE: plot time-window choices (seconds) and the default.
const PLOT_WINDOW_CHOICES_S: Array[float] = [5.0, 10.0, 20.0, 30.0, 60.0]
const DEFAULT_PLOT_WINDOW_INDEX: int = 1
const SIDE_PANEL_MIN_WIDTH: float = 520.0
# TUNABLE: ghost runs (README 7.3): how many to keep, and the shortest run
# worth keeping (shorter runs are just restarts).
const MAX_GHOSTS: int = 3
const MIN_GHOST_RUN_S: float = 1.0
# Which recorder channels a ghost keeps (the traces marked ghost = true).
const GHOST_CHANNELS: PackedStringArray = ["measurement", "applied_input"]

# Survive a scenario switch.
var _scenarios: Array[Scenario] = []
var _scenario_index: int = 0
# Saved data (README 7.10): snapshots live in _save_store.data["snapshots"]
# as { scenario title -> { slot letter -> PID tuning } }.
var _save_store := SaveStore.new()
var _save_countdown: float = -1.0  # seconds until the debounced autosave; < 0 = nothing pending
var _save_message: String = ""
var _save_panel: SavePanel
var _controller_mode: ControllerMode = ControllerMode.MANUAL
var _plot_window_index: int = DEFAULT_PLOT_WINDOW_INDEX

var _simulation: Simulation
var _clock: SimClock
var _manual_controller: ManualController
var _pid_controller: PidController
var _cascade_controller: CascadeController  # null if the plant has no inner loop
var _pending_physics_rate_hz: float = Simulation.DEFAULT_PHYSICS_RATE_HZ

var _toolbar: SimToolbar
var _plant_view: PlantView
var _manual_panel: ManualControlPanel
var _pid_panel: PidPanel
var _cascade_panel: CascadePanel  # null if the plant has no inner loop
var _setpoint_panel: SetpointPanel
var _setpoint_bar: SetpointBar
var _settings_panel: SimSettingsPanel
var _metrics_bar: MetricsBar
var _charts: Array[StripChart] = []
var _true_output_trace: ChartTrace
var _mode_menu: OptionButton
var _snapshot_panel: SnapshotPanel
var _side_scroll: ScrollContainer
var _background: ColorRect
var _display_panel: DisplayPanel
var _advanced_sections: Array[Control] = []  # hidden in presenter mode
var _locked_sections: Array[Control] = []    # hidden while a challenge test runs

# Challenge test (stage 20). See "Challenge test" below.
enum ChallengeState { IDLE, RUNNING, FINISHED }
var _challenge_state: ChallengeState = ChallengeState.IDLE
var _test_tuning: Dictionary = {}  # the PID tuning under test ({} = no test)
var _challenge_panel: ChallengePanel
var _output_chart: StripChart
var _sections: Dictionary = {}  # block-diagram block id -> CollapsibleSection

# Guided lesson (stage 21). See "Guided lesson" below.
const LESSON_CHECK_INTERVAL_S: float = 0.25  # TUNABLE: run-based checks scan the recorder
var _lesson_panel: LessonPanel
var _lesson_step: int = 0
var _lesson_finished: bool = false
var _lesson_step_done: bool = false  # latched: once met, a step stays done
var _lesson_check_timer: float = 0.0
var _lesson_controls: Dictionary = {}  # Lesson.CONTROL_NAMES key -> Control
var _lesson_hidden: Dictionary = {}    # names hidden right now
var _lesson_blocked: Dictionary = {}   # names hidden OR locked right now

# Ziegler–Nichols helper (stage 22). See "Ziegler–Nichols helper" below.
const ZN_UPDATE_INTERVAL_S: float = 0.25  # TUNABLE: the swing measurement scans 10 s of samples
const ZN_WINDOW_S: float = 10.0           # TUNABLE: how far back the swing is measured
var _zn_panel: ZnPanel
var _zn_section: CollapsibleSection
var _zn_timer: float = 0.0
var _zn_oscillation: Oscillation
var _zn_bands_shown: bool = false
var _run_label: String = ""  # ghost label for this run ("ZN PID"...), "" = automatic

# Mystery mode (stage 24). See "Mystery plant" below.
var _mystery_on: bool = false
var _mystery_number: int = 0  # which roll (1, 2, ...) for this scenario
var _parameter_panel: ParameterPanel
var _equations_view: EquationsView
var _ghosts: Array[GhostRun] = []  # shared with every chart
var _ghosts_made: int = 0          # for "run N" labels and colours
var _run_start_tuning: Dictionary = {}  # PID tuning at t = 0 ({} = run wasn't pure PID)


func _ready() -> void:
	_scenarios = ScenarioCatalog.load_all()
	if _scenarios.is_empty():
		push_error("No scenarios found in %s" % ScenarioCatalog.SCENARIO_FOLDER)
		return
	_report_storage_location()
	_save_message = _save_store.load_from_disk()
	DisplaySettings.load_save(_save_store.data["settings"])
	WebPlatform.request_persistent_storage()
	add_child(SoundFx.new())  # interface sounds for every button (A/V patch)
	_load_scenario(_find_scenario(_save_store.data["settings"]["last_scenario"]),
			Simulation.DEFAULT_SEED, 1.0)


func _process(delta: float) -> void:
	_autosave_tick(delta)
	var steps := _clock.consume_frame(delta)
	if _challenge_state == ChallengeState.RUNNING:  # stop exactly at the end of the test
		steps = mini(steps, ChallengeRunner.steps_to_finish(_simulation, _current_challenge()))
	for i in steps:
		_simulation.step_physics()
	if _challenge_state == ChallengeState.RUNNING:
		_update_challenge_test()
	_update_lesson(delta)
	_update_zn_helper(delta)

	_toolbar.update_time(_simulation.get_time())
	_toolbar.update_slow_warning(_clock.is_running_slow, delta)
	_plant_view.show_state(_simulation)
	_setpoint_panel.update_panel()
	match _controller_mode:
		ControllerMode.MANUAL:
			_manual_panel.update_panel(delta)
		ControllerMode.PID:
			_pid_panel.update_panel()
		ControllerMode.CASCADED_PID:
			_cascade_panel.update_panel()
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
		_on_user_reset()
	elif event.is_action_pressed("sim_step"):
		_step_once()
	elif event.is_action_pressed("setpoint_flip"):
		if not _lesson_blocked.has("setpoint"):
			_setpoint_bar.flip()
	elif event.is_action_pressed("presenter_toggle"):
		_toggle_presenter()
	elif event.is_action_pressed("sound_mute_toggle"):
		_toggle_sound()
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
		if not _is_selected_gain_blocked():
			_pid_panel.nudge_selected_gain(1.0)
	elif event.is_action_pressed("gain_nudge_down", true):
		if not _is_selected_gain_blocked():
			_pid_panel.nudge_selected_gain(-1.0)
	else:
		return false
	return true


# ------------------------------------------------------------------ actions

func _load_scenario(index: int, random_seed: int, time_scale: float) -> void:
	_scenario_index = index
	var scenario := _scenarios[index]
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_charts.clear()

	# A challenge test reloads the SAME scenario, so its ghosts stay comparable.
	var starting_test := not _test_tuning.is_empty() and scenario.challenge != null
	if not starting_test:
		_test_tuning = {}
		_ghosts.clear()  # a different plant: old runs aren't comparable
		_ghosts_made = 0
	_challenge_state = ChallengeState.IDLE
	_run_start_tuning = {}
	var plant := scenario.create_plant()
	_controller_mode = scenario.start_mode as int as ControllerMode
	if starting_test:
		_controller_mode = ControllerMode.PID
	_manual_controller = ManualController.new()
	_pid_controller = ScenarioSetup.make_pid(plant)
	_cascade_controller = ScenarioSetup.make_cascade(plant)
	if _controller_mode == ControllerMode.CASCADED_PID and _cascade_controller == null:
		_controller_mode = ControllerMode.PID  # reported by apply_cascade_settings
	# Same construction as ChallengeRunner (headless grading in the tests).
	_simulation = ScenarioSetup.build_simulation(scenario, plant, _active_controller(),
			_pid_controller, random_seed,
			Simulation.DEFAULT_PHYSICS_RATE_HZ if starting_test else _pending_physics_rate_hz)
	scenario.apply_cascade_settings(_cascade_controller, plant)
	if starting_test:
		_pid_controller.apply_tuning(_test_tuning)  # the student's tuning wins
		scenario.challenge.apply_to(_simulation)
		_challenge_state = ChallengeState.RUNNING
	_clock = SimClock.new(_simulation.get_physics_dt())
	_restore_lesson_progress()
	_mystery_on = false
	_mystery_number = 0

	_build_layout()
	_toolbar.set_seed(random_seed)
	_toolbar.set_time_scale(time_scale)
	_plant_view.load_plant_visual(plant)
	_set_presenter(DisplaySettings.presenter)  # the layout was rebuilt
	_save_panel.show_status(_save_message)
	_save_message = ""
	_remember_setting("last_scenario", scenario.title)
	_set_paused(false)
	_reset_run()  # applies seed and physics rate, and starts the setpoint at t = 0
	_apply_lesson_step()
	if scenario.mystery_mode and not starting_test:
		_set_mystery(true)
	if starting_test:
		_begin_challenge_display()


func _on_scenario_selected(index: int) -> void:
	_test_tuning = {}
	# Deferred: the toolbar that sent this signal is about to be freed.
	_load_scenario.call_deferred(index, _toolbar.get_seed(), _clock.time_scale)


func _active_controller() -> Controller:
	if _controller_mode == ControllerMode.PID:
		return _pid_controller
	if _controller_mode == ControllerMode.CASCADED_PID:
		return _cascade_controller
	return _manual_controller


func _on_controller_mode_selected(index: int) -> void:
	_controller_mode = index as ControllerMode
	if _challenge_state == ChallengeState.RUNNING:
		_cancel_challenge_test("You switched the controller, so the test was cancelled.")
	_run_start_tuning = {}  # this run mixed Manual and PID
	_simulation.set_controller(_active_controller())
	_show_controller_panel()
	_manual_panel.sync_from_simulation()


func _show_controller_panel() -> void:
	_manual_panel.visible = _controller_mode == ControllerMode.MANUAL
	_pid_panel.visible = _controller_mode == ControllerMode.PID
	if _cascade_panel != null:
		_cascade_panel.visible = _controller_mode == ControllerMode.CASCADED_PID


# The active controller's whole tuning ({} in manual): a run whose tuning at
# t = 0 equals this one now used ONE tuning throughout (ghost labels, lesson
# and ZN "press Reset" checks).
func _current_tuning() -> Dictionary:
	match _controller_mode:
		ControllerMode.PID:
			return _pid_controller.get_tuning()
		ControllerMode.CASCADED_PID:
			return {"cascade": _cascade_controller.get_tuning()}
	return {}


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
	var steps := _simulation.get_controller_period_steps()
	if _challenge_state == ChallengeState.RUNNING:
		steps = mini(steps, ChallengeRunner.steps_to_finish(_simulation, _current_challenge()))
	_simulation.step_many(steps)
	if _challenge_state == ChallengeState.RUNNING:
		_update_challenge_test()
	_redraw_charts()
	_metrics_bar.refresh()


func _reset_run(keep_ghost: bool = true) -> void:
	if keep_ghost:
		_keep_run_as_ghost()
	_simulation.random_seed = _toolbar.get_seed()
	if _challenge_state != ChallengeState.RUNNING:  # a test keeps the default rate
		_simulation.physics_rate_hz = _pending_physics_rate_hz
	_simulation.reset()
	_run_start_tuning = _current_tuning()
	_run_label = ""
	_clock.physics_dt = _simulation.get_physics_dt()
	_clock.reset()
	_plant_view.reset_visual()
	_manual_panel.sync_from_simulation()
	_settings_panel.refresh()
	_metrics_bar.refresh()
	_redraw_charts()


# The run that is ending becomes a faded ghost on the plots (if long enough).
# It is labelled with a slot letter only if the WHOLE run used that slot's
# exact tuning in PID mode (same at t = 0 and now); otherwise "run N".
func _keep_run_as_ghost() -> void:
	if _simulation.get_time() < MIN_GHOST_RUN_S:
		return
	var label := "run %d" % (_ghosts_made + 1)
	var tuning_now := _pid_controller.get_tuning()
	if not _run_start_tuning.is_empty() and _run_start_tuning == _current_tuning():
		if _run_label != "":
			label = _run_label
	if _controller_mode == ControllerMode.PID and _run_start_tuning == tuning_now:
		var slots := _get_slots()
		for slot in SnapshotPanel.SLOT_NAMES:
			if slots.has(slot) and slots[slot] == tuning_now:
				label = slot
				break
	var color := SignalColors.GHOST_COLORS[_ghosts_made % SignalColors.GHOST_COLORS.size()]
	_ghosts.append(GhostRun.new(_simulation.recorder, GHOST_CHANNELS, label, color))
	_ghosts_made += 1
	while _ghosts.size() > MAX_GHOSTS:
		_ghosts.remove_at(0)


func _get_slots() -> Dictionary:
	var title := _scenarios[_scenario_index].title
	var snapshots: Dictionary = _save_store.data["snapshots"]
	if not snapshots.has(title):
		snapshots[title] = {}
	return snapshots[title]


func _on_snapshot_save(slot: String) -> void:
	_get_slots()[slot] = _pid_controller.get_tuning()
	_snapshot_panel.show_slots(_get_slots())
	_mark_save_dirty()


# Load a slot's tuning into the PID, switch to PID mode, and re-run from 0
# with the same seed (the run so far becomes a ghost for comparison).
func _on_snapshot_load(slot: String) -> void:
	var slots := _get_slots()
	if not slots.has(slot):
		return
	_keep_run_as_ghost()  # first, while the controller still has the old tuning
	_pid_controller.apply_tuning(slots[slot])
	if _controller_mode != ControllerMode.PID:
		_mode_menu.select(ControllerMode.PID)
		_on_controller_mode_selected(ControllerMode.PID)
	_rebuild_pid_panel()
	_reset_run(false)


# Recreate the PID panel so every slider and switch shows the controller's
# current values (after loading a snapshot).
func _rebuild_pid_panel() -> void:
	var parent := _pid_panel.get_parent()
	var position_in_parent := _pid_panel.get_index()
	var was_visible := _pid_panel.visible
	parent.remove_child(_pid_panel)
	_pid_panel.queue_free()
	_pid_panel = PidPanel.new()
	parent.add_child(_pid_panel)
	parent.move_child(_pid_panel, position_in_parent)
	_pid_panel.setup(_simulation, _pid_controller)
	_pid_panel.visible = was_visible
	_register_pid_lesson_controls()  # the old sliders are gone
	_apply_lesson_controls()


func _register_pid_lesson_controls() -> void:
	for control_name in ["kp", "ki", "kd", "output_limits", "feedforward", "advanced_pid"]:
		_lesson_controls[control_name] = _pid_panel.get_lesson_control(control_name)


# --- Presenter mode and graphics (stage 18) ---

func _toggle_presenter() -> void:
	_set_presenter(not DisplaySettings.presenter)


# Presenter mode: everything bigger (window content scale), thicker plot
# lines and black plot backgrounds (DisplaySettings), and the advanced
# sections hidden so the projector shows only what the lesson needs.
func _set_presenter(is_on: bool) -> void:
	if DisplaySettings.presenter != is_on:
		DisplaySettings.presenter = is_on
		_save_display_settings()
	get_tree().root.content_scale_factor = DisplaySettings.PRESENTER_UI_SCALE if is_on else 1.0
	_background.color = Color(0.0, 0.0, 0.0) if is_on else Color(0.13, 0.14, 0.16)
	_update_section_visibility()
	_toolbar.set_presenter(is_on)
	_display_panel.sync_from_settings()
	for chart in _charts:
		chart.queue_redraw()


func _on_display_settings_changed() -> void:
	_plant_view.apply_graphics()
	_save_display_settings()


# Sound-only changes (volume, mute, categories): no need to rebuild the 3D view.
func _on_sound_settings_changed() -> void:
	_toolbar.show_sound(DisplaySettings.sound_on)
	_save_display_settings()


func _toggle_sound() -> void:
	DisplaySettings.sound_on = not DisplaySettings.sound_on
	_display_panel.sync_from_settings()
	_on_sound_settings_changed()


# --- Saving (stage 19, README 7.10) ---

func _find_scenario(title: String) -> int:
	for index in _scenarios.size():
		if _scenarios[index].title == title:
			return index
	return 0


func _save_display_settings() -> void:
	(_save_store.data["settings"] as Dictionary).merge(DisplaySettings.to_save(), true)
	_mark_save_dirty()


func _remember_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = _save_store.data["settings"]
	if settings.get(key) != value:
		settings[key] = value
		_mark_save_dirty()


# Debounced autosave: wait until changes stop for a moment, then write once.
# (Never rely on a quit event; browsers don't reliably send one.)
func _mark_save_dirty() -> void:
	_save_countdown = SaveStore.AUTOSAVE_DELAY_S


func _autosave_tick(delta: float) -> void:
	if _save_countdown < 0.0:
		return
	_save_countdown -= delta
	if _save_countdown < 0.0:
		_save_store.write_to_disk()


# After an import or reset: apply the new settings and rebuild the screen.
func _on_save_replaced() -> void:
	_save_countdown = -1.0  # the store just wrote itself
	DisplaySettings.load_save(_save_store.data["settings"])
	_save_message = "Done: your saved tunings and settings are now the ones shown."
	_load_scenario.call_deferred(_scenario_index, _toolbar.get_seed(), _clock.time_scale)


# --- Challenge test (stage 20, README 7.6) ---
# "Run test" reloads the scenario from its file, keeping only the student's
# PID tuning, applies the challenge's scripted setup (fixed seed, step, load)
# and plays it live. The run stops exactly at duration_s and is graded with
# ChallengeGrader, the same code the tests use with ChallengeRunner. While it
# runs, the settings that would change the result are hidden, poking is off,
# and changing the tuning, the controller or pressing Reset cancels it.

func _current_challenge() -> Challenge:
	return _scenarios[_scenario_index].challenge


func _on_run_test_requested() -> void:
	_keep_run_as_ghost()  # compare this attempt with the last one
	_test_tuning = _pid_controller.get_tuning()
	# Deferred: the button that sent this is freed by the reload.
	_load_scenario.call_deferred(_scenario_index, _current_challenge().random_seed,
			_clock.time_scale)


func _begin_challenge_display() -> void:
	_output_chart.bands = ChallengePanel.make_bands(_current_challenge(), _simulation.plant)
	_challenge_panel.clear_result()
	_challenge_panel.show_running(0.0)
	_update_section_visibility()
	var tabs := _challenge_panel.get_parent() as TabContainer
	tabs.current_tab = _challenge_panel.get_index()


func _update_challenge_test() -> void:
	if _pid_controller.get_tuning() != _test_tuning:
		_cancel_challenge_test("You changed the tuning, so the test was cancelled. Press Run test to try it.")
		return
	if ChallengeRunner.steps_to_finish(_simulation, _current_challenge()) > 0:
		_challenge_panel.show_running(_simulation.get_time())
		return
	# Finished: grade, show, remember the best.
	_challenge_state = ChallengeState.FINISHED
	_set_paused(true)
	var result := ChallengeGrader.grade(_current_challenge(), _simulation.recorder,
			_simulation.plant)
	_challenge_panel.show_result(result)
	SoundFx.play(SoundBank.SUCCESS if result.get_passed_count() == result.rows.size() else SoundBank.FAIL)
	_record_challenge_result(result)
	_challenge_panel.show_best(_get_challenge_record())
	_end_test_lock()


func _cancel_challenge_test(message: String) -> void:
	_challenge_state = ChallengeState.IDLE
	_output_chart.bands = []
	_challenge_panel.show_idle(message)
	_end_test_lock()


func _end_test_lock() -> void:
	_test_tuning = {}
	_update_section_visibility()
	_redraw_charts()


func _on_user_reset() -> void:
	if _challenge_state == ChallengeState.RUNNING:
		_cancel_challenge_test("Reset cancelled the test.")
	elif _challenge_state == ChallengeState.FINISHED:
		_challenge_state = ChallengeState.IDLE
		_output_chart.bands = []
	_reset_run()


# Three things hide controls: presenter mode (the advanced sections), a
# running challenge test (anything that would change the graded result) and
# the lesson step (its hidden controls). A control shows if none hides it.
func _update_section_visibility() -> void:
	var hidden_now: Array[Control] = []
	if DisplaySettings.presenter:
		hidden_now.append_array(_advanced_sections)
	var test_running := _challenge_state == ChallengeState.RUNNING
	if test_running:
		hidden_now.append_array(_locked_sections)
	for control_name: String in _lesson_hidden:
		hidden_now.append(_lesson_controls[control_name])
	var hideable: Array[Control] = []
	hideable.append_array(_advanced_sections + _locked_sections)
	for control: Control in _lesson_controls.values():
		hideable.append(control)
	for control in hideable:
		control.visible = not hidden_now.has(control)
	_setpoint_bar.visible = not test_running and not _lesson_hidden.has("setpoint")


# Saved per challenge (README 7.10): {"best_score", "best_iae", "completed"}.
func _get_challenge_record() -> Dictionary:
	var records: Dictionary = _save_store.data["challenges"]
	return records.get(_scenarios[_scenario_index].title, {})


func _record_challenge_result(result: ChallengeResult) -> void:
	var record := _get_challenge_record()
	var best_score: int = record.get("best_score", -1)
	var best_iae: float = record.get("best_iae", INF)
	if not record.is_empty() and not result.is_better_than(best_score, best_iae):
		return
	(_save_store.data["challenges"] as Dictionary)[_scenarios[_scenario_index].title] = {
		"best_score": result.get_score(), "best_iae": result.iae,
		"completed": result.is_complete() or record.get("completed", false)}
	_mark_save_dirty()


# --- Guided lesson (stage 21, README 7.6 mode 2) ---
# A scenario with a Lesson gets a Lesson tab (first, and selected). Each step
# shows a prompt; if it has a check, Next unlocks once LessonChecks says it
# is met (latched, so it doesn't flicker off). The step decides which
# controls are hidden or locked (Lesson.get_hidden/get_locked). Finishing
# unlocks everything. Progress is saved per lesson title.

func _current_lesson() -> Lesson:
	return _scenarios[_scenario_index].lesson


func _restore_lesson_progress() -> void:
	_lesson_step = 0
	_lesson_finished = false
	var lesson := _current_lesson()
	if lesson == null:
		return
	var record: Dictionary = (_save_store.data["lessons"] as Dictionary).get(
			_scenarios[_scenario_index].title, {})
	_lesson_step = clampi(record.get("step", 0), 0, lesson.steps.size() - 1)
	_lesson_finished = record.get("finished", false)


func _save_lesson_progress() -> void:
	var lessons: Dictionary = _save_store.data["lessons"]
	var title := _scenarios[_scenario_index].title
	var was_completed: bool = (lessons.get(title, {}) as Dictionary).get("completed", false)
	lessons[title] = {"step": _lesson_step, "finished": _lesson_finished,
		"completed": was_completed or _lesson_finished}
	_mark_save_dirty()


# Shows the current step and applies its hidden / locked controls.
func _apply_lesson_step() -> void:
	_apply_lesson_controls()
	_lesson_step_done = false
	_lesson_check_timer = 0.0
	if _lesson_panel == null:
		return
	var lesson := _current_lesson()
	if _lesson_finished:
		_lesson_panel.show_step(lesson.steps.size() - 1, lesson.steps.size(),
				"You finished this lesson, and every control is unlocked now. Explore! (Start over to repeat it.)",
				true)
		_lesson_panel.show_status("", false)
	else:
		var step := lesson.steps[_lesson_step]
		_lesson_panel.show_step(_lesson_step, lesson.steps.size(), step.prompt, false)
		_update_lesson(LESSON_CHECK_INTERVAL_S)


func _apply_lesson_controls() -> void:
	_lesson_hidden = {}
	_lesson_blocked = {}
	var lesson := _current_lesson()
	if lesson != null and not _lesson_finished:
		for control_name in lesson.get_hidden(_lesson_step):
			_lesson_hidden[control_name] = true
			_lesson_blocked[control_name] = true
		for control_name in lesson.get_locked(_lesson_step):
			_lesson_blocked[control_name] = true
	for control_name: String in _lesson_controls:
		var control: Control = _lesson_controls[control_name]
		var section := control as CollapsibleSection
		# A locked section can still be opened and read, just not changed.
		UiStyle.set_locked(section.body if section != null else control,
				_lesson_blocked.has(control_name) and not _lesson_hidden.has(control_name))
	_update_section_visibility()


func _update_lesson(delta: float) -> void:
	if _lesson_panel == null or _lesson_finished or _lesson_step_done:
		return
	_lesson_check_timer -= delta
	if _lesson_check_timer > 0.0:
		return
	_lesson_check_timer = LESSON_CHECK_INTERVAL_S
	var step := _current_lesson().steps[_lesson_step]
	var is_pid := _controller_mode == ControllerMode.PID
	var run_is_clean := is_pid and _run_start_tuning == _pid_controller.get_tuning()
	var waiting_for := LessonChecks.evaluate(step, _simulation, _pid_controller, is_pid,
			run_is_clean)
	_lesson_step_done = waiting_for == ""
	if _lesson_step_done and step.check != "":
		SoundFx.play(SoundBank.STEP_DONE)
	_lesson_panel.show_status(waiting_for, step.check != "")


func _on_lesson_next() -> void:
	if _lesson_step >= _current_lesson().steps.size() - 1:
		_lesson_finished = true
	else:
		_lesson_step += 1
	_save_lesson_progress()
	_apply_lesson_step()


func _on_lesson_back() -> void:
	if _lesson_finished:
		_lesson_finished = false
	else:
		_lesson_step = maxi(_lesson_step - 1, 0)
	_save_lesson_progress()
	_apply_lesson_step()


func _on_lesson_restart() -> void:
	_lesson_step = 0
	_lesson_finished = false
	_save_lesson_progress()
	_apply_lesson_step()


func _is_selected_gain_blocked() -> bool:
	return _lesson_blocked.has(["kp", "ki", "kd"][_pid_panel.get_selected_gain()])


# --- Ziegler–Nichols helper (stage 22, README 7.6 mode 3) ---
# While the section is open (and in PID mode), the swing of the last
# ZN_WINDOW_S is measured 4 times a second and judged dying / steady /
# growing (ZnTuning.judge). The measured cycles are shaded on the output plot
# (alternate cycles, with "1 cycle = Tu") unless a challenge owns the bands.
# Applying a table row keeps the old run as a ghost and labels the new run
# with the rule's name, so ZN and Tyreus–Luyben can be compared directly.

func _update_zn_helper(delta: float) -> void:
	if _zn_section == null or not _zn_section.is_visible_in_tree() or not _zn_section.body.visible:
		_clear_zn_bands()
		return
	_zn_timer -= delta
	if _zn_timer > 0.0:
		return
	_zn_timer = ZN_UPDATE_INTERVAL_S
	if _controller_mode != ControllerMode.PID:
		_zn_oscillation = null
		_zn_panel.show_state("Switch the controller to PID first.", UiStyle.HINT_COLOR, false)
		_clear_zn_bands()
		return
	var output_info := _simulation.plant.get_output_definition()
	_zn_oscillation = Oscillation.analyze(_simulation.recorder, ZN_WINDOW_S,
			output_info.max_value - output_info.min_value)
	var swing := ZnTuning.judge(_zn_oscillation)
	var is_p_only := _pid_controller.integral_gain == 0.0 and _pid_controller.derivative_gain == 0.0
	var run_is_clean := _run_start_tuning == _pid_controller.get_tuning()
	var text := ""
	var color := UiStyle.HINT_COLOR
	if not is_p_only:
		text = "Set Ki and Kd to 0 first (button 1)."
	elif not run_is_clean:
		text = "You changed the gains: press Reset (R) to test them."
	else:
		match swing:
			ZnTuning.Swing.NONE:
				text = "No steady swing yet (%d cycles). Raise Kp and press Reset.\nSome plants never swing with P alone: a 1st-order plant with no delay has no Ku. Try the hotend, or add sensor delay." % _zn_oscillation.cycles
			ZnTuning.Swing.DYING:
				text = "Swinging, but dying out (each swing ×%s of the first). Raise Kp a bit and press Reset." % NumberFormat.significant(_zn_oscillation.get_growth(), 2)
				color = SignalColors.WARNING_TEXT
			ZnTuning.Swing.GROWING:
				text = "The swing is GROWING (×%s): Kp is past Ku. Lower it a little and press Reset." % NumberFormat.significant(_zn_oscillation.get_growth(), 2)
				color = SignalColors.SPEC_LIMIT
			ZnTuning.Swing.STEADY:
				text = "STEADY swing! Period Tu = %s s. Press 3." % NumberFormat.significant(_zn_oscillation.period, 3)
				color = SignalColors.SPEC_BAND
		if swing != ZnTuning.Swing.NONE and ZnTuning.hits_input_limit(_zn_oscillation,
				_pid_controller, _simulation.actuator):
			text += "\nCareful: the input is hitting its limit (SATURATED), so the limit is shaping this swing and Ku will come out too high. Try a smaller setpoint step."
			if swing == ZnTuning.Swing.STEADY:
				color = SignalColors.WARNING_TEXT
	var can_capture := is_p_only and run_is_clean and swing == ZnTuning.Swing.STEADY
	_zn_panel.show_state(text, color, can_capture)
	_show_zn_bands(output_info)


func _show_zn_bands(output_info: QuantityInfo) -> void:
	var challenge_owns_bands := not _zn_bands_shown and not _output_chart.bands.is_empty()
	if challenge_owns_bands:
		return
	if _zn_oscillation == null or _zn_oscillation.cycles < 2:
		_clear_zn_bands()
		return
	var bands: Array[Dictionary] = []
	var times := _zn_oscillation.crossing_times
	var low := output_info.si_to_shown(_zn_oscillation.low)
	var high := output_info.si_to_shown(_zn_oscillation.high)
	for i in range(0, times.size() - 1, 2):  # every other cycle, so each one is visible
		bands.append({"t0": times[i], "t1": times[i + 1], "y0": minf(low, high), "y1": maxf(low, high),
			"color": SignalColors.FF_TERM,
			"label": "1 cycle = %s s" % NumberFormat.significant(times[i + 1] - times[i], 2) if i == 0 else ""})
	_output_chart.bands = bands
	_zn_bands_shown = true
	_output_chart.queue_redraw()


func _clear_zn_bands() -> void:
	if _zn_bands_shown:
		_zn_bands_shown = false
		_output_chart.bands = []
		_output_chart.queue_redraw()


func _zn_gains_blocked() -> bool:
	return _lesson_blocked.has("kp") or _lesson_blocked.has("ki") or _lesson_blocked.has("kd")


func _on_zn_p_only() -> void:
	if _zn_gains_blocked():
		return
	_apply_gains_and_restart(_pid_controller.proportional_gain, 0.0, 0.0, "")


func _on_zn_capture() -> void:
	if _zn_oscillation == null or is_nan(_zn_oscillation.period):
		return
	_zn_panel.show_table(_pid_controller.proportional_gain, _zn_oscillation.period)


func _on_zn_apply(row: Dictionary) -> void:
	if _zn_gains_blocked():
		return
	_apply_gains_and_restart(row["kp"], row["ki"], row["kd"], row["name"])


# Keeps the current run as a ghost, sets the gains, starts a fresh run, and
# labels it (the label shows on its ghost later).
func _apply_gains_and_restart(kp: float, ki: float, kd: float, label: String) -> void:
	_keep_run_as_ghost()
	_pid_controller.proportional_gain = kp
	_pid_controller.integral_gain = ki
	_pid_controller.derivative_gain = kd
	_pid_controller.reset_integral()
	if _controller_mode != ControllerMode.PID:
		_mode_menu.select(ControllerMode.PID)
		_on_controller_mode_selected(ControllerMode.PID)
	_rebuild_pid_panel()
	_reset_run(false)
	_run_label = label
	_zn_timer = 0.0


# --- Mystery plant (stage 24, README section 5) ---
# Random, hidden parameters (Mystery.make_parameters), seeded from the
# toolbar seed and the roll number so a class can share "seed 42, mystery #1".
# The plant's equation is hidden too. Turning it off restores the scenario's
# parameters. Ghosts are cleared: runs on different plants aren't comparable.

func _set_mystery(is_on: bool) -> void:
	_mystery_on = is_on
	var plant := _simulation.plant
	# Undo any parameter drift first, or the reset below would put the
	# drifted parameter's OLD value back over the new one.
	_simulation.disturbance_generator.reset(plant)
	if is_on:
		_mystery_number = maxi(_mystery_number + 1, 1)
		var values := Mystery.make_parameters(plant, _toolbar.get_seed() * 7919 + _mystery_number)
		for key: String in values:
			plant.set_parameter(key, values[key])
	else:
		var original := _scenarios[_scenario_index].create_plant()
		for key: String in original.parameters:
			plant.set_parameter(key, original.parameters[key])
	_parameter_panel.show_mystery(is_on, _mystery_number)
	_equations_view.hide_plant = is_on
	_equations_view.refresh()
	_on_clear_ghosts()
	_reset_run(false)


func _on_new_mystery() -> void:
	_set_mystery(true)


# Block diagram click: open that block's settings and scroll them into view.
func _on_block_clicked(block_id: String) -> void:
	if not _sections.has(block_id):
		return
	var section: CollapsibleSection = _sections[block_id]
	section.set_open(true)
	_scroll_to_section.call_deferred(section)  # after the layout updates


func _scroll_to_section(section: Control) -> void:
	_side_scroll.scroll_vertical = int(section.position.y)


func _on_show_ghosts_toggled(visible_now: bool) -> void:
	for chart in _charts:
		chart.show_ghosts = visible_now
	_redraw_charts()


func _on_clear_ghosts() -> void:
	_ghosts.clear()
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
	_background = background
	background.color = Color(0.13, 0.14, 0.16)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 9)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 9)
	margin.add_child(page)

	var titles := PackedStringArray()
	for scenario in _scenarios:
		titles.append(scenario.title)
	_toolbar = SimToolbar.new(titles, _scenario_index)
	_toolbar.play_pause_pressed.connect(_toggle_pause)
	_toolbar.step_pressed.connect(_step_once)
	_toolbar.reset_pressed.connect(_on_user_reset)
	_toolbar.time_scale_changed.connect(_clock.set_time_scale)
	_toolbar.scenario_selected.connect(_on_scenario_selected)
	_toolbar.presenter_pressed.connect(_toggle_presenter)
	_toolbar.sound_pressed.connect(_toggle_sound)
	_toolbar.show_sound(DisplaySettings.sound_on)
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
	_plant_view.poked.connect(func(direction: float) -> void:
		if _challenge_state != ChallengeState.RUNNING and not _lesson_blocked.has("poke"):
			_simulation.poke(direction))

	_setpoint_bar = SetpointBar.new()
	_setpoint_bar.setup(_simulation)
	_plant_view.set_bottom_bar(_setpoint_bar)
	_setpoint_bar.setpoint_changed.connect(_setpoint_panel.sync_from_generator)
	_setpoint_panel.settings_changed.connect(_setpoint_bar.sync_from_generator)

	vertical_split.add_child(_build_plot_area())


func _build_side_panel() -> Control:
	var scroll := ScrollContainer.new()
	_side_scroll = scroll
	scroll.custom_minimum_size = Vector2(SIDE_PANEL_MIN_WIDTH, 0.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	scroll.add_child(column)

	# --- Controller: mode picker + the matching panel ---
	var controller_section := CollapsibleSection.new("Controller", true)
	column.add_child(controller_section)
	_sections["controller"] = controller_section
	_mode_menu = OptionButton.new()
	_mode_menu.focus_mode = Control.FOCUS_NONE
	_mode_menu.add_item("Manual (you are the controller)", ControllerMode.MANUAL)
	_mode_menu.add_item("PID", ControllerMode.PID)
	if _cascade_controller != null:
		_mode_menu.add_item("Cascaded PID (outer + inner loop)", ControllerMode.CASCADED_PID)
	_mode_menu.select(_controller_mode)
	_mode_menu.item_selected.connect(_on_controller_mode_selected)
	controller_section.body.add_child(_mode_menu)

	_manual_panel = ManualControlPanel.new()
	controller_section.body.add_child(_manual_panel)
	_manual_panel.setup(_simulation, _manual_controller)
	_pid_panel = PidPanel.new()
	controller_section.body.add_child(_pid_panel)
	_pid_panel.setup(_simulation, _pid_controller)
	_cascade_panel = null
	if _cascade_controller != null:
		_cascade_panel = CascadePanel.new()
		controller_section.body.add_child(_cascade_panel)
		_cascade_panel.setup(_simulation, _cascade_controller)
	_show_controller_panel()

	# --- Ziegler–Nichols helper (stage 22) ---
	_zn_section = CollapsibleSection.new("Ziegler–Nichols helper", false)
	column.add_child(_zn_section)
	_zn_panel = ZnPanel.new()
	_zn_section.body.add_child(_zn_panel)
	_zn_panel.setup(_simulation.plant)
	_zn_panel.p_only_requested.connect(_on_zn_p_only)
	_zn_panel.capture_requested.connect(_on_zn_capture)
	_zn_panel.apply_requested.connect(_on_zn_apply)
	_zn_bands_shown = false

	# --- Tuning snapshots A-D (stage 16) ---
	var snapshot_section := CollapsibleSection.new("Snapshots (compare tunings)", false)
	column.add_child(snapshot_section)
	_snapshot_panel = SnapshotPanel.new()
	snapshot_section.body.add_child(_snapshot_panel)
	_snapshot_panel.show_slots(_get_slots())
	_snapshot_panel.save_requested.connect(_on_snapshot_save)
	_snapshot_panel.load_requested.connect(_on_snapshot_load)

	# --- Setpoint ---
	var setpoint_section := CollapsibleSection.new("Setpoint", true)
	column.add_child(setpoint_section)
	_sections["setpoint"] = setpoint_section
	_setpoint_panel = SetpointPanel.new()
	setpoint_section.body.add_child(_setpoint_panel)
	_setpoint_panel.setup(_simulation)

	# --- Sensor & actuator non-idealities (README 7.5) ---
	var nonideality_section := CollapsibleSection.new("Sensor & actuator", false)
	column.add_child(nonideality_section)
	_sections["sensor"] = nonideality_section
	_sections["actuator"] = nonideality_section
	var nonideality_panel := NonidealityPanel.new()
	nonideality_section.body.add_child(nonideality_panel)
	nonideality_panel.setup(_simulation)

	# --- Disturbances (README 7.5, stage 14) ---
	var disturbance_section := CollapsibleSection.new("Disturbances", false)
	column.add_child(disturbance_section)
	_sections["disturbance"] = disturbance_section
	var disturbance_panel := DisturbancePanel.new()
	disturbance_section.body.add_child(disturbance_panel)
	disturbance_panel.setup(_simulation)

	# --- Plant parameters ---
	var parameter_section := CollapsibleSection.new("Plant parameters", false)
	column.add_child(parameter_section)
	_sections["plant"] = parameter_section
	_parameter_panel = ParameterPanel.new()
	parameter_section.body.add_child(_parameter_panel)
	_parameter_panel.setup(_simulation.plant)
	_parameter_panel.mystery_toggled.connect(_set_mystery)
	_parameter_panel.new_mystery_requested.connect(_on_new_mystery)

	# --- Simulation settings ---
	var settings_section := CollapsibleSection.new("Simulation settings (advanced)", false)
	column.add_child(settings_section)
	_settings_panel = SimSettingsPanel.new()
	settings_section.body.add_child(_settings_panel)
	_settings_panel.setup(_simulation)
	_settings_panel.physics_rate_changed.connect(_on_physics_rate_changed)

	# --- Display & graphics (stage 18) ---
	var display_section := CollapsibleSection.new("Display & graphics", false)
	column.add_child(display_section)
	_display_panel = DisplayPanel.new()
	display_section.body.add_child(_display_panel)
	_display_panel.setup()
	_display_panel.settings_changed.connect(_on_display_settings_changed)
	_display_panel.sound_settings_changed.connect(_on_sound_settings_changed)
	_display_panel.presenter_toggled.connect(_set_presenter)

	# --- Save & export (stage 19) ---
	var save_section := CollapsibleSection.new("Save & export", false)
	column.add_child(save_section)
	_save_panel = SavePanel.new()
	save_section.body.add_child(_save_panel)
	_save_panel.setup(_save_store, func() -> Array:
		var title := _scenarios[_scenario_index].title
		return [CsvExport.make_file_name(title), CsvExport.build(_simulation, title)])
	_save_panel.save_replaced.connect(_on_save_replaced)
	_advanced_sections = [snapshot_section, parameter_section, settings_section, save_section]
	_lesson_controls = {
		"controller_mode": _mode_menu,
		"zn_helper": _zn_section,
		"snapshots": snapshot_section,
		"setpoint": setpoint_section,
		"sensor_actuator": nonideality_section,
		"disturbances": disturbance_section,
		"plant_parameters": parameter_section,
		"simulation_settings": settings_section,
	}
	_register_pid_lesson_controls()
	_locked_sections = [_zn_section, snapshot_section, setpoint_section, nonideality_section,
		disturbance_section, parameter_section, settings_section]

	return scroll


func _build_plot_area() -> Control:
	var area := VBoxContainer.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size = Vector2(0.0, 330.0)

	# Plot options row.
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 15)
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

	var show_ghosts := CheckBox.new()
	show_ghosts.text = "Ghosts"
	show_ghosts.button_pressed = true
	show_ghosts.tooltip_text = "Show earlier runs (kept on every Reset) faded behind the live lines."
	show_ghosts.focus_mode = Control.FOCUS_NONE
	show_ghosts.toggled.connect(_on_show_ghosts_toggled)
	options.add_child(show_ghosts)
	var clear_ghosts := Button.new()
	clear_ghosts.text = "Clear ghosts"
	clear_ghosts.focus_mode = Control.FOCUS_NONE
	clear_ghosts.pressed.connect(_on_clear_ghosts)
	options.add_child(clear_ghosts)

	var hint := Label.new()
	hint.text = "Hover to read values; pause and drag to scrub."
	hint.add_theme_color_override("font_color", UiStyle.HINT_COLOR)
	hint.add_theme_font_size_override("font_size", UiStyle.HINT)
	options.add_child(hint)

	# Output chart on the left; command / PID terms / error as tabs on the right.
	var charts := HBoxContainer.new()
	charts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charts.add_theme_constant_override("separation", 9)
	area.add_child(charts)

	var output_info := _simulation.plant.get_output_definition()
	var input_info := _simulation.plant.get_input_definition()
	var output_scale := output_info.display_scale
	var input_scale := input_info.display_scale

	_true_output_trace = ChartTrace.new("true_output", "True", SignalColors.TRUE_OUTPUT,
			output_scale, false, 1.5)
	_output_chart = _make_chart(output_info.display_name, output_info.get_shown_unit(), [
		ChartTrace.new("setpoint", "Setpoint", SignalColors.SETPOINT, output_scale, true, 2.0),
		_ghosted(ChartTrace.new("measurement", "Measured", SignalColors.MEASUREMENT, output_scale, false, 2.5)),
		# Drawn on top, thin, so it stays visible inside a noisy measurement.
		# Shown only while the sensor is non-ideal (otherwise it hides "Measured").
		_true_output_trace,
	])
	_output_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_chart.size_flags_stretch_ratio = 1.0  # half the width: room for all tab titles
	charts.add_child(_output_chart)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Slightly smaller titles so all eight tabs fit side by side at 1080p.
	tabs.add_theme_font_size_override("font_size", UiStyle.HINT + 1)
	tabs.focus_mode = Control.FOCUS_NONE
	charts.add_child(tabs)

	# Notes (README 7.4): the scenario's "what to try" text, shown first.
	var notes := RichTextLabel.new()
	notes.text = _scenarios[_scenario_index].notes
	if _scenarios[_scenario_index].challenge != null:  # the goal first
		notes.text = "Goal: %s\n\n%s" % [_scenarios[_scenario_index].challenge.goal, notes.text]
	notes.fit_content = false
	notes.scroll_active = true
	notes.selection_enabled = true
	notes.focus_mode = Control.FOCUS_NONE
	notes.add_theme_font_size_override("normal_font_size", UiStyle.BODY)
	var notes_margin := MarginContainer.new()
	notes_margin.name = "Notes"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		notes_margin.add_theme_constant_override(side, 15)
	notes_margin.add_child(notes)
	# Lesson tab (stage 21): first, and selected, when the scenario has one.
	if _current_lesson() != null:
		_lesson_panel = LessonPanel.new()
		_lesson_panel.name = "Lesson"
		_lesson_panel.next_pressed.connect(_on_lesson_next)
		_lesson_panel.back_pressed.connect(_on_lesson_back)
		_lesson_panel.restart_pressed.connect(_on_lesson_restart)
		tabs.add_child(_lesson_panel)
	else:
		_lesson_panel = null
	tabs.add_child(notes_margin)

	# Challenge tab (stage 20), only for scenarios that define a challenge.
	var challenge := _current_challenge()
	if challenge != null:
		_challenge_panel = ChallengePanel.new()
		_challenge_panel.name = "Challenge"
		_challenge_panel.setup(challenge, _simulation.plant)
		_challenge_panel.show_best(_get_challenge_record())
		_challenge_panel.run_requested.connect(_on_run_test_requested)
		tabs.add_child(_challenge_panel)
	else:
		_challenge_panel = null

	# Applied input is drawn first so the dashed command shows on top of it.
	var command_chart := _make_chart(input_info.display_name, input_info.get_shown_unit(), [
		_ghosted(ChartTrace.new("applied_input", "Applied", SignalColors.APPLIED_INPUT, input_scale, false, 2.5)),
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
	tabs.set_tab_title(tabs.get_tab_idx_from_control(terms_chart), "Terms")

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
	disturbance_chart.name = "Load"  # short, so every tab title fits
	tabs.add_child(disturbance_chart)

	# Inner loop (stage 23): the cascade's inner target vs. the inner measurement.
	if _cascade_controller != null:
		var inner_info := _simulation.plant.get_inner_definition()
		var inner_chart := _make_chart(inner_info.display_name, inner_info.get_shown_unit(), [
			ChartTrace.new("inner_setpoint", "Inner target", SignalColors.SETPOINT,
					inner_info.display_scale, true, 2.0),
			ChartTrace.new("inner_measurement", "Inner measured", SignalColors.MEASUREMENT,
					inner_info.display_scale, false, 2.5),
		])
		inner_chart.name = "Inner loop"
		tabs.add_child(inner_chart)

	# Teaching tabs (README 7.4).
	var diagram := BlockDiagram.new()
	diagram.name = "Diagram"
	diagram.setup(_simulation)
	diagram.block_clicked.connect(_on_block_clicked)
	tabs.add_child(diagram)
	var equations := EquationsView.new()
	equations.name = "Equations"
	equations.setup(_simulation)
	_equations_view = equations
	tabs.add_child(equations)

	_metrics_bar = MetricsBar.new()
	area.add_child(_metrics_bar)
	_metrics_bar.setup(_simulation)

	_on_plot_window_selected(_plot_window_index)
	return area


func _ghosted(trace: ChartTrace) -> ChartTrace:
	trace.ghost = true
	return trace


func _make_chart(title: String, unit: String, traces: Array[ChartTrace]) -> StripChart:
	var chart := StripChart.new()
	chart.recorder = _simulation.recorder
	chart.chart_title = title
	chart.y_unit = unit
	chart.traces = traces
	chart.ghosts = _ghosts
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
