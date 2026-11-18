# metrics_bar.gd
#
# PURPOSE
#   One line under the plots with the response metrics (README 7.1, stage 7):
#   rise time, overshoot, settling time, steady-state error, IAE, peak input
#   and effort, for the response to the most recent setpoint change.
#
# HOW IT FITS
#   Calls StepMetrics.analyze_recorder() (core logic, tested headless) a few
#   times per second, not every frame, because it scans the whole recording.
#   Unit conversion to display units happens here.
class_name MetricsBar
extends PanelContainer

# TUNABLE: how often the metrics are recomputed (seconds).
const UPDATE_INTERVAL_S: float = 0.25

var _simulation: Simulation
var _label: Label
var _time_until_update: float = 0.0


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.tooltip_text = "Measured on the TRUE output, for the response to the last setpoint change.\nRise: 10% to 90% of the way to the target. Overshoot: % past the target.\nSettling: time to stay within 2% of the step. SS error: average error over the last 0.5 s.\nIAE: integral of |error| (smaller is better). Effort: integral of input squared."
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_label)


# Called every frame; recomputes at most every UPDATE_INTERVAL_S.
func update_bar(frame_delta: float) -> void:
	_time_until_update -= frame_delta
	if _time_until_update > 0.0:
		return
	_time_until_update = UPDATE_INTERVAL_S
	refresh()


func refresh() -> void:
	var metrics := StepMetrics.analyze_recorder(_simulation.recorder)
	var output_info := _simulation.plant.get_output_definition()
	var input_info := _simulation.plant.get_input_definition()
	var out_unit := output_info.get_shown_unit()
	var in_unit := input_info.get_shown_unit()

	var parts := PackedStringArray()
	if metrics.has_step:
		parts.append("Since t = %s s:" % String.num(metrics.step_time, 2))
		parts.append("Rise %s" % _seconds(metrics.rise_time))
		parts.append("Overshoot %s" % _percent(metrics.overshoot_percent))
		parts.append("Settling (2%%) %s" % _seconds(metrics.settling_time))
		parts.append("SS error %s" % _value(output_info.si_to_shown(metrics.steady_state_error), out_unit))
	else:
		parts.append("Setpoint still changing; whole run:")
	parts.append("IAE %s" % _value(output_info.si_to_shown(metrics.integral_abs_error), out_unit + "·s"))
	parts.append("Peak |u| %s" % _value(input_info.si_to_shown(metrics.peak_abs_input), in_unit))
	var shown_scale := input_info.display_scale
	parts.append("Effort %s" % _value(metrics.effort * shown_scale * shown_scale, in_unit + "²·s"))
	_label.text = "   ".join(parts)


static func _seconds(value: float) -> String:
	return "-" if is_nan(value) else "%s s" % NumberFormat.significant(value, 3)


static func _percent(value: float) -> String:
	return "-" if is_nan(value) else "%s%%" % String.num(value, 1)


static func _value(value: float, unit: String) -> String:
	return "-" if is_nan(value) else "%s %s" % [NumberFormat.significant(value, 3), unit]
