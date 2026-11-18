# equations_view.gd
#
# PURPOSE
#   The Equations tab (README 7.4): the plant's ODE and the controller's
#   discrete update written out, with the live numbers substituted in, so
#   students can connect the sliders and plots to the maths.
#   (Transfer-function / Laplace forms are for the Advanced Math setting, later.)
#
# HOW IT FITS
#   Reads the Simulation; the text itself comes from Plant.get_equation_text()
#   and Controller.get_equation_text(), so each plant/controller documents its
#   own maths next to its code. Refreshes REFRESH_HZ times a second while
#   visible, slow enough to read while the simulation runs.
class_name EquationsView
extends RichTextLabel

const REFRESH_HZ: float = 8.0  # TUNABLE

var _simulation: Simulation
var _timer: float = 0.0


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	bbcode_enabled = true
	scroll_active = true
	selection_enabled = true
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("normal_font_size", UiStyle.HINT + 1)
	add_theme_font_size_override("bold_font_size", UiStyle.HINT + 1)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 and is_visible_in_tree():
		_timer = 1.0 / REFRESH_HZ
		refresh()


func refresh() -> void:
	if _simulation == null:
		return
	var plant := _simulation.plant
	var controller := _simulation.controller
	var period_ms := 1000.0 / _simulation.get_actual_controller_rate_hz()
	var content := "[b][color=#%s]Plant: %s[/color][/b]  (SI units, right now)\n%s\n\n" % [
		SignalColors.TRUE_OUTPUT.to_html(false), plant.get_display_name(),
		plant.get_equation_text(_simulation.state, _simulation.plant_input, _simulation.disturbance)]
	content += "[b][color=#%s]Controller: %s[/color][/b]  (runs every Δt = %s ms; u is held between runs)\n%s" % [
		SignalColors.COMMAND.to_html(false), controller.get_display_name(),
		NumberFormat.significant(period_ms, 3),
		controller.get_equation_text(_simulation.setpoint, _simulation.measurement)]
	content += "\n\n[b]Actuator[/b]: u_applied = %s   [b]Sensor[/b]: y = %s (true output %s)" % [
		NumberFormat.significant(_simulation.applied_input, 3),
		NumberFormat.significant(_simulation.measurement, 3),
		NumberFormat.significant(_simulation.get_true_output(), 3)]
	text = content
