# block_diagram.gd
#
# PURPOSE
#   The Block diagram tab (README 7.4, signal flow in README 3): the control
#   loop drawn live.
#       setpoint r -> (+) -> e -> [Controller] -> u -> [Actuator] -> u_applied -> [Plant] -> output
#                     (-)                                            d -> ^              |
#                      ^------------- y <- [Sensor] <---------------------------------------
#   Every wire shows its current value in the colour that signal has on the
#   plots. Sensor and actuator list the problems switched on (and glow amber
#   when any is); the actuator (or a clipped PID) turns red when SATURATED.
#   Clicking a block opens its settings in the side panel.
#
# HOW IT FITS
#   Read-only view of the Simulation, drawn with the 2D API. Emits
#   block_clicked(block_id); main_screen.gd decides which section to open.
class_name BlockDiagram
extends Control

signal block_clicked(block_id: String)

# TUNABLE: layout as fractions of the control's size, and text sizes.
const FORWARD_Y: float = 0.36
const FEEDBACK_Y: float = 0.82
const BLOCK_HEIGHT: float = 0.30
const BLOCK_WIDTH: float = 0.125     # controller / actuator / plant / sensor
const SETPOINT_WIDTH: float = 0.105
const VALUE_FONT_SIZE: int = UiStyle.DIAGRAM_VALUE
const BLOCK_FONT_SIZE: int = UiStyle.DIAGRAM_BLOCK
const SMALL_FONT_SIZE: int = UiStyle.SMALLEST
const ACTIVE_BORDER: Color = Color("#F0E442")
const SATURATED_FILL: Color = Color(0.55, 0.10, 0.10)
const BLOCK_FILL: Color = Color(0.16, 0.17, 0.20)

var _simulation: Simulation
var _block_rects: Dictionary = {}  # block id -> Rect2 (for clicks)


func _init() -> void:
	custom_minimum_size = Vector2(480.0, 225.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click a block to open its settings."


func setup(simulation: Simulation) -> void:
	_simulation = simulation


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	for block_id: String in _block_rects:
		var rect: Rect2 = _block_rects[block_id]
		if rect.grow(4.0).has_point(button.position):
			block_clicked.emit(block_id)
			accept_event()
			return


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DisplaySettings.plot_background())
	if _simulation == null:
		return
	var plant := _simulation.plant
	var output_info := plant.get_output_definition()
	var input_info := plant.get_input_definition()
	var disturbance_info := plant.get_disturbance_definition()
	var w := size.x
	var h := size.y
	var forward_y := h * FORWARD_Y
	var feedback_y := h * FEEDBACK_Y
	var block_height := h * BLOCK_HEIGHT
	_block_rects.clear()

	# Left to right: setpoint, sum, controller, actuator, plant, output arrow,
	# with EQUAL gaps between them so every wire has the same room for its
	# label (the labels are what students read).
	var margin := 8.0
	var setpoint_width := w * SETPOINT_WIDTH
	var block_width := w * BLOCK_WIDTH
	var sum_radius := minf(h * 0.07, 18.0)
	var gap := (w - 2.0 * margin - setpoint_width - 2.0 * sum_radius - 3.0 * block_width) / 5.0
	var x := margin
	var setpoint_rect := _block_rect("setpoint", Vector2(x + setpoint_width * 0.5, forward_y),
			Vector2(setpoint_width, block_height))
	x += setpoint_width + gap
	var sum_center := Vector2(x + sum_radius, forward_y)
	x += 2.0 * sum_radius + gap
	var controller_rect := _block_rect("controller", Vector2(x + block_width * 0.5, forward_y),
			Vector2(block_width, block_height))
	x += block_width + gap
	var actuator_rect := _block_rect("actuator", Vector2(x + block_width * 0.5, forward_y),
			Vector2(block_width, block_height))
	x += block_width + gap
	var plant_rect := _block_rect("plant", Vector2(x + block_width * 0.5, forward_y),
			Vector2(block_width, block_height))
	var output_x := w - margin
	var sensor_rect := _block_rect("sensor", Vector2(actuator_rect.get_center().x, feedback_y),
			Vector2(block_width, block_height * 0.85))

	# --- wires (drawn first, blocks on top) ---
	var r_text := _shown(output_info, _simulation.setpoint)
	var e_text := _shown_difference(output_info, _simulation.setpoint - _simulation.measurement)
	var y_text := _shown(output_info, _simulation.measurement)
	var true_text := _shown(output_info, _simulation.get_true_output())
	var u_text := _shown(input_info, _simulation.command)
	var applied_text := _shown(input_info, _simulation.applied_input)
	var d_text := _shown(disturbance_info, _simulation.disturbance)

	_arrow(Vector2(setpoint_rect.end.x, forward_y), sum_center - Vector2(sum_radius, 0.0),
			SignalColors.SETPOINT, "r", r_text)
	_arrow(sum_center + Vector2(sum_radius, 0.0), Vector2(controller_rect.position.x, forward_y),
			SignalColors.ERROR, "e", e_text)
	_arrow(Vector2(controller_rect.end.x, forward_y), Vector2(actuator_rect.position.x, forward_y),
			SignalColors.COMMAND, "u", u_text)
	_arrow(Vector2(actuator_rect.end.x, forward_y), Vector2(plant_rect.position.x, forward_y),
			SignalColors.APPLIED_INPUT, "applied", applied_text)
	_arrow(Vector2(plant_rect.end.x, forward_y), Vector2(output_x, forward_y),
			SignalColors.TRUE_OUTPUT, "output", true_text)
	# Feedback: down from the output, left into the sensor, left and up into (-).
	var feedback_color := SignalColors.MEASUREMENT
	draw_line(Vector2(output_x - 10.0, forward_y), Vector2(output_x - 10.0, feedback_y),
			SignalColors.TRUE_OUTPUT, 3.0)
	_arrow(Vector2(output_x - 10.0, feedback_y), Vector2(sensor_rect.end.x, feedback_y),
			SignalColors.TRUE_OUTPUT, "", "")
	draw_line(Vector2(sensor_rect.position.x, feedback_y), Vector2(sum_center.x, feedback_y),
			feedback_color, 3.0)
	_arrow(Vector2(sum_center.x, feedback_y), sum_center + Vector2(0.0, sum_radius),
			feedback_color, "", "")
	_text(Vector2((sensor_rect.position.x + sum_center.x) * 0.5, feedback_y - 9.0),
			"y = " + y_text, VALUE_FONT_SIZE, feedback_color)
	# Disturbance from above into the plant.
	var d_start := Vector2(plant_rect.get_center().x, maxf(forward_y - block_height * 0.5 - h * 0.2, 24.0))
	_arrow(d_start, Vector2(plant_rect.get_center().x, plant_rect.position.y),
			SignalColors.DISTURBANCE, "", "")
	_text(d_start + Vector2(0.0, -3.0), "d = " + d_text, VALUE_FONT_SIZE, SignalColors.DISTURBANCE)
	_block_rects["disturbance"] = Rect2(d_start - Vector2(60.0, 26.0), Vector2(120.0, 30.0))

	# --- summing junction ---
	draw_circle(sum_center, sum_radius, BLOCK_FILL)
	draw_arc(sum_center, sum_radius, 0.0, TAU, 24, SignalColors.PLOT_AXIS_TEXT, 1.5)
	_text(sum_center + Vector2(-sum_radius - 6.0, -sum_radius + 2.0), "+", SMALL_FONT_SIZE + 2,
			SignalColors.PLOT_AXIS_TEXT)
	_text(sum_center + Vector2(sum_radius + 4.0, sum_radius + 10.0), "-", SMALL_FONT_SIZE + 2,
			SignalColors.PLOT_AXIS_TEXT)

	# --- blocks ---
	var pid := _simulation.controller as PidController
	var clipped := pid != null and pid.is_output_clipped()
	var actuator_effects := _actuator_effects()
	var sensor_effects := _sensor_effects()
	_block(setpoint_rect, "Setpoint", SetpointGenerator.get_pattern_name(
			_simulation.setpoint_generator.pattern), false, false)
	_block(controller_rect, "Controller", "PID%s" % (" (clipped)" if clipped else "")
			if pid != null else "Manual (you)", false, clipped)
	_block(actuator_rect, "Actuator", actuator_effects if actuator_effects != "" else "ideal",
			actuator_effects != "", _simulation.actuator.is_saturated)
	_block(plant_rect, "Plant", "", false, false)  # its name is in the toolbar
	_block(sensor_rect, "Sensor", sensor_effects if sensor_effects != "" else "ideal",
			sensor_effects != "", false)


func _block_rect(block_id: String, center: Vector2, block_size: Vector2) -> Rect2:
	var rect := Rect2(center - block_size * 0.5, block_size)
	_block_rects[block_id] = rect
	return rect


func _block(rect: Rect2, title: String, subtitle: String, active: bool, saturated: bool) -> void:
	draw_rect(rect, SATURATED_FILL if saturated else BLOCK_FILL)
	var border := SignalColors.WARNING_TEXT if saturated else (ACTIVE_BORDER if active else SignalColors.PLOT_AXIS_TEXT)
	draw_rect(rect, border, false, 4.0 if (active or saturated) else 2.0)
	var center := rect.get_center()
	_text(center + Vector2(0.0, -3.0), title, BLOCK_FONT_SIZE, Color.WHITE, rect.size.x - 8.0)
	var sub := "SATURATED" if saturated and title == "Actuator" else subtitle
	_text(center + Vector2(0.0, 21.0), sub, SMALL_FONT_SIZE, SignalColors.PLOT_AXIS_TEXT, rect.size.x - 8.0)


# Line with an arrowhead at `to`. For horizontal wires, the signal's symbol
# goes above the middle and its live value below, both shrunk to the wire.
func _arrow(from: Vector2, to: Vector2, color: Color, symbol: String, value: String) -> void:
	draw_line(from, to, color, 3.0, true)
	var direction := (to - from).normalized()
	if direction == Vector2.ZERO:
		return
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([to, to - direction * 12.0 + side * 7.0,
			to - direction * 12.0 - side * 7.0]), color)
	var room := absf(to.x - from.x) - 4.0
	if symbol != "":
		_text((from + to) * 0.5 + Vector2(0.0, -7.0), symbol, VALUE_FONT_SIZE, color, room)
	if value != "":
		_text((from + to) * 0.5 + Vector2(0.0, 23.0), value, SMALL_FONT_SIZE, color, room)


# Centred text, shrunk to fit `max_width` if given.
func _text(center_bottom: Vector2, text: String, font_size: int, color: Color,
		max_width: float = -1.0) -> void:
	var font := get_theme_default_font()
	var fitted_size := font_size
	while max_width > 0.0 and fitted_size > 14 \
			and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x > max_width:
		fitted_size -= 1
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x
	draw_string(font, Vector2(center_bottom.x - width * 0.5, center_bottom.y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size, color)


func _shown(info: QuantityInfo, si_value: float) -> String:
	return "%s %s" % [NumberFormat.significant(info.si_to_shown(si_value), 3), info.get_shown_unit()]


func _shown_difference(info: QuantityInfo, si_value: float) -> String:
	return _shown(info, si_value)  # display scales have no offset, so differences convert the same


func _sensor_effects() -> String:
	var sensor := _simulation.sensor
	var parts := PackedStringArray()
	if sensor.delay_enabled:
		parts.append("delay")
	if sensor.noise_enabled:
		parts.append("noise")
	if sensor.quantization_enabled:
		parts.append("counts")
	if sensor.lowpass_enabled:
		parts.append("filter")
	return ", ".join(parts)


func _actuator_effects() -> String:
	var actuator := _simulation.actuator
	var parts := PackedStringArray()
	if actuator.deadband_enabled:
		parts.append("deadband")
	if actuator.saturation_enabled:
		parts.append("limits")
	if actuator.slew_enabled:
		parts.append("slew")
	return ", ".join(parts)
