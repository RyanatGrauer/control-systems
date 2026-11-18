# snapshot_panel.gd
#
# PURPOSE
#   Tuning slots A-D (README 7.2 "snapshot / compare"). "Save" stores the PID
#   tuning (gains, switches, feedforward) in a slot. "Load" puts it back and
#   re-runs from t = 0 with the same seed; the run you just did stays on the
#   plots as a faded ghost, so you can compare A against B on the same axes.
#
# HOW IT FITS
#   Only emits signals and shows summaries; main_screen.gd owns the slots
#   (one set per scenario) and does the saving, loading and re-running.
#   Slots last for the session; saving them to disk comes in stage 19.
class_name SnapshotPanel
extends VBoxContainer

signal save_requested(slot: String)
signal load_requested(slot: String)

const SLOT_NAMES: PackedStringArray = ["A", "B", "C", "D"]

var _summaries: Dictionary = {}     # slot -> Label
var _load_buttons: Dictionary = {}  # slot -> Button


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var hint := Label.new()
	hint.text = "Save your PID tuning, then load it later to re-run with the same seed. The previous run stays as a faded ghost on the plots."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200.0, 0.0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	add_child(hint)
	for slot in SLOT_NAMES:
		var row := HBoxContainer.new()
		add_child(row)
		var name_label := Label.new()
		name_label.text = slot
		name_label.custom_minimum_size = Vector2(20.0, 0.0)
		row.add_child(name_label)
		var save_button := Button.new()
		save_button.text = "Save"
		save_button.focus_mode = Control.FOCUS_NONE
		save_button.tooltip_text = "Store the current PID tuning in slot %s" % slot
		save_button.pressed.connect(save_requested.emit.bind(slot))
		row.add_child(save_button)
		var load_button := Button.new()
		load_button.text = "Load + rerun"
		load_button.focus_mode = Control.FOCUS_NONE
		load_button.disabled = true
		load_button.tooltip_text = "Use slot %s's tuning and run again from t = 0" % slot
		load_button.pressed.connect(load_requested.emit.bind(slot))
		row.add_child(load_button)
		_load_buttons[slot] = load_button
		var summary := Label.new()
		summary.text = "(empty)"
		summary.clip_text = true
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.add_theme_font_size_override("font_size", 13)
		summary.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
		row.add_child(summary)
		_summaries[slot] = summary


# Show which slots hold a tuning. `slots` maps slot -> tuning Dictionary.
func show_slots(slots: Dictionary) -> void:
	for slot in SLOT_NAMES:
		var has_tuning := slots.has(slot)
		(_load_buttons[slot] as Button).disabled = not has_tuning
		var summary: Label = _summaries[slot]
		if has_tuning:
			var tuning: Dictionary = slots[slot]
			summary.text = "Kp %s  Ki %s  Kd %s" % [
				NumberFormat.significant(tuning.get("proportional_gain", 0.0), 2),
				NumberFormat.significant(tuning.get("integral_gain", 0.0), 2),
				NumberFormat.significant(tuning.get("derivative_gain", 0.0), 2)]
		else:
			summary.text = "(empty)"
		summary.tooltip_text = summary.text
