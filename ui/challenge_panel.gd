# challenge_panel.gd
#
# PURPOSE
#   The Challenge tab (README 7.6 mode 4): the goal, the "Run test" button,
#   a table of specs (limit, your result, PASS/FAIL), the score, and the
#   student's best result for this challenge (saved locally).
#   Also builds the spec bands drawn on the output plot (make_bands).
#
# HOW IT FITS
#   Display only. main_screen.gd runs the test (see "Challenge test" there),
#   grades it with ChallengeGrader, and calls show_* here. Values arrive in
#   SI and are converted to the plant's display units here, at the UI boundary.
class_name ChallengePanel
extends ScrollContainer

signal run_requested

var _challenge: Challenge
var _plant: Plant
var _run_button: Button
var _status: Label
var _score: Label
var _best: Label
var _result_labels: Dictionary = {}  # spec key -> [value Label, verdict Label]


func setup(challenge: Challenge, plant: Plant) -> void:
	_challenge = challenge
	_plant = plant
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 15)
	add_child(margin)
	# Side by side on purpose: at 1080p the whole tab (button, score, table)
	# fits without scrolling. The goal sentence is at the top of the Notes
	# tab and in the button's tooltip.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(260.0, 0.0)
	row.add_child(left)
	_run_button = Button.new()
	_run_button.text = "Run test"
	_run_button.focus_mode = Control.FOCUS_NONE
	_run_button.tooltip_text = challenge.goal + "\n\nRestarts from t = 0 with the challenge's fixed setup and seed, using YOUR PID tuning. Everything except the tuning comes from the challenge."
	_run_button.custom_minimum_size = Vector2(200.0, 54.0)
	_run_button.pressed.connect(run_requested.emit)
	left.add_child(_run_button)
	_status = UiStyle.make_hint("")
	_status.custom_minimum_size = Vector2(260.0, 0.0)
	_status.visible = false
	left.add_child(_status)
	_score = Label.new()
	_score.add_theme_font_size_override("font_size", UiStyle.LARGE)
	_score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_score.custom_minimum_size = Vector2(260.0, 0.0)
	left.add_child(_score)
	_best = UiStyle.make_hint("")
	_best.custom_minimum_size = Vector2(260.0, 0.0)
	left.add_child(_best)

	var table := GridContainer.new()
	table.columns = 4
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 24)
	table.add_theme_constant_override("v_separation", 4)
	row.add_child(table)
	for heading in ["Goal", "Limit (max)", "Your result", ""]:
		table.add_child(_cell(heading, UiStyle.HINT_COLOR))
	for key: String in Challenge.SPEC_INFO:
		if not challenge.specs.has(key):
			continue
		var unit_kind: String = Challenge.SPEC_INFO[key][1]
		table.add_child(_cell(Challenge.SPEC_INFO[key][0], Color.WHITE))
		table.add_child(_cell(format_value(unit_kind, challenge.specs[key], plant), Color.WHITE))
		var value := _cell("-", Color.WHITE)
		var verdict := _cell("", Color.WHITE)
		table.add_child(value)
		table.add_child(verdict)
		_result_labels[key] = [value, verdict]


func show_running(time: float) -> void:
	_run_button.disabled = true
	_status.visible = true
	_status.text = "Running: %.1f of %.0f s. Changing the gains cancels it." % [
		time, _challenge.duration_s]
	_status.add_theme_color_override("font_color", SignalColors.WARNING_TEXT)


func show_idle(message: String = "") -> void:
	_run_button.disabled = false
	_status.text = message
	_status.visible = message != ""
	_status.add_theme_color_override("font_color", SignalColors.WARNING_TEXT)


func show_result(result: ChallengeResult) -> void:
	show_idle()
	for row in result.rows:
		var labels: Array = _result_labels[row["key"]]
		var value: float = row["value"]
		(labels[0] as Label).text = format_value(row["unit_kind"], value, _plant) \
				if not is_nan(value) else "not reached"
		var verdict := labels[1] as Label
		verdict.text = "PASS" if row["passed"] else "FAIL"
		verdict.add_theme_color_override("font_color",
				SignalColors.SPEC_BAND if row["passed"] else SignalColors.SPEC_LIMIT)
	_score.text = "Score: %d / 100\n%d of %d goals met" % [result.get_score(),
		result.get_passed_count(), result.rows.size()]
	if result.is_complete():
		_score.text = "Score: 100 / 100\nChallenge complete!"
	_score.add_theme_color_override("font_color",
			SignalColors.SPEC_BAND if result.is_complete() else Color.WHITE)


func clear_result() -> void:
	for key: String in _result_labels:
		(_result_labels[key][0] as Label).text = "-"
		(_result_labels[key][1] as Label).text = ""
	_score.text = ""


# `best` is the saved record ({} if none yet).
func show_best(best: Dictionary) -> void:
	if best.is_empty():
		_best.text = "No result yet"
		return
	_best.text = "Your best: %d%s" % [best["best_score"],
		" (completed)" if best["completed"] else ""]


# A value in the plant's display units, e.g. "4.8 RPM", "0.35 s", "12 %".
static func format_value(unit_kind: String, si_value: float, plant: Plant) -> String:
	var output_info := plant.get_output_definition()
	var input_info := plant.get_input_definition()
	var number := func(value: float) -> String: return NumberFormat.significant(value, 3)
	match unit_kind:
		"s":
			return "%s s" % number.call(si_value)
		"%":
			return "%s %%" % number.call(si_value)
		"output":
			return "%s %s" % [number.call(output_info.si_to_shown(si_value)), output_info.get_shown_unit()]
		"output_s":
			return "%s %s·s" % [number.call(si_value * output_info.display_scale), output_info.get_shown_unit()]
		"input":
			return "%s %s" % [number.call(input_info.si_to_shown(si_value)), input_info.get_shown_unit()]
		"effort":
			var input_scale := input_info.display_scale
			return "%s %s²·s" % [number.call(si_value * input_scale * input_scale), input_info.get_shown_unit()]
	return number.call(si_value)


# Spec bands for the output plot, in DISPLAY units (see StripChart.bands).
static func make_bands(challenge: Challenge, plant: Plant) -> Array[Dictionary]:
	var output_info := plant.get_output_definition()
	var output_scale := output_info.display_scale
	var target := challenge.target_level
	var step := target - challenge.start_level
	var step_end := challenge.load_time_s if challenge.load_enabled else challenge.duration_s
	var settle_band := absf(step) * StepMetrics.SETTLING_BAND_FRACTION
	if settle_band < 1e-12:
		settle_band = (output_info.max_value - output_info.min_value) * StepMetrics.SETTLING_BAND_FRACTION
	var bands: Array[Dictionary] = []
	var specs := challenge.specs
	if specs.has("overshoot_percent"):
		var ceiling := target + step * specs["overshoot_percent"] / 100.0
		bands.append({"t0": challenge.step_time_s, "t1": step_end, "y0": ceiling * output_scale,
			"y1": ceiling * output_scale, "color": SignalColors.SPEC_LIMIT, "label": "overshoot limit"})
	if specs.has("settling_time_s"):
		bands.append({"t0": challenge.step_time_s + specs["settling_time_s"], "t1": step_end,
			"y0": (target - settle_band) * output_scale, "y1": (target + settle_band) * output_scale,
			"color": SignalColors.SPEC_BAND, "label": "settled by here"})
	if specs.has("steady_state_error"):
		var error: float = specs["steady_state_error"]
		bands.append({"t0": step_end - StepMetrics.STEADY_STATE_WINDOW_S, "t1": step_end,
			"y0": (target - error) * output_scale, "y1": (target + error) * output_scale,
			"color": SignalColors.SPEC_BAND, "label": ""})
	if challenge.load_enabled and specs.has("load_peak_error"):
		var peak: float = specs["load_peak_error"]
		bands.append({"t0": challenge.load_time_s, "t1": challenge.duration_s,
			"y0": (target - peak) * output_scale, "y1": (target + peak) * output_scale,
			"color": SignalColors.LOAD_BAND, "label": "load: stay inside"})
	if challenge.load_enabled and specs.has("load_recovery_s"):
		bands.append({"t0": challenge.load_time_s + specs["load_recovery_s"], "t1": challenge.duration_s,
			"y0": (target - settle_band) * output_scale, "y1": (target + settle_band) * output_scale,
			"color": SignalColors.SPEC_BAND, "label": "recovered by here"})
	return bands


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
