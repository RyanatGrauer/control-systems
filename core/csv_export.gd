# csv_export.gd
#
# PURPOSE
#   Turns the current run into a CSV file (README 7.8) that students can open
#   in a spreadsheet or Python: one row per controller tick, SI units, with
#   "#" comment lines at the top recording the scenario, gains, seed and rates
#   so the run can be reproduced.
#
# HOW IT FITS
#   Reads Simulation.recorder (whatever it still holds: the last 120 s).
#   The UI hands the text to WebPlatform / a FileDialog to save it.
class_name CsvExport
extends RefCounted

# Recorder channel -> CSV column title (with SI unit placeholders filled below).
const COLUMNS: Array[Array] = [
	["time", "time_s"], ["setpoint", "setpoint"], ["measurement", "measurement"],
	["true_output", "true_output"], ["command", "command"],
	["applied_input", "applied_input"], ["p_term", "p_term"], ["i_term", "i_term"],
	["d_term", "d_term"], ["ff_term", "ff_term"], ["disturbance", "disturbance"],
]


static func build(simulation: Simulation, scenario_title: String) -> String:
	var plant := simulation.plant
	var output_unit := plant.get_output_definition().si_unit
	var input_unit := plant.get_input_definition().si_unit
	var lines := PackedStringArray()
	lines.append("# Control Lab run export (all values in SI units)")
	lines.append("# scenario: %s; plant: %s" % [_clean(scenario_title), plant.get_display_name()])
	lines.append("# controller: %s" % _describe_controller(simulation.controller))
	lines.append("# seed: %d; physics rate: %s Hz; controller rate: %s Hz" % [
		simulation.random_seed, simulation.physics_rate_hz, simulation.get_actual_controller_rate_hz()])
	lines.append("# units: setpoint/measurement/true_output in %s; command/applied_input/terms in %s; disturbance in %s" % [
		output_unit, input_unit, plant.get_disturbance_definition().si_unit])
	var titles := PackedStringArray()
	for column in COLUMNS:
		titles.append(column[1])
	lines.append(",".join(titles))
	var recorder := simulation.recorder
	for index in recorder.get_count():
		var row := PackedStringArray()
		for column in COLUMNS:
			row.append(String.num(recorder.get_value(column[0], index), 6))
		lines.append(",".join(row))
	return "\n".join(lines) + "\n"


static func make_file_name(scenario_title: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	# Letters and digits only, runs of anything else -> one "_".
	var regex := RegEx.create_from_string("[^a-z0-9]+")
	var safe := regex.sub(scenario_title.to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	return "control_lab_%s_%s.csv" % [safe, stamp]


static func _describe_controller(controller: Controller) -> String:
	var pid := controller as PidController
	if pid == null:
		return controller.get_display_name()
	var text := "PID Kp=%s Ki=%s Kd=%s" % [pid.proportional_gain, pid.integral_gain,
		pid.derivative_gain]
	if pid.feedforward_enabled:
		text += " kS=%s kV=%s kA=%s kG=%s" % [pid.static_gain, pid.velocity_gain,
			pid.acceleration_gain, pid.gravity_gain]
	return text


static func _clean(text: String) -> String:
	return text.replace("\n", " ").replace(",", ";")
