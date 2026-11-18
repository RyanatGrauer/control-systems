# strip_chart.gd
#
# PURPOSE
#   A reusable scrolling plot ("strip chart") drawn with Godot's 2D drawing API.
#   No plotting addons (README 2.2 / 7.3).
#
# HOW IT FITS
#   It READS from a RunRecorder and never touches the simulation. The main
#   screen calls queue_redraw() after the simulation advances.
#
# FEATURES
#   - several traces (ChartTrace), each with a legend entry; dashed or solid
#   - auto-scaled or fixed Y axis; grid with "nice" tick labels (ChartAxis)
#   - adjustable time window (seconds of history shown)
#   - hover crosshair with a readout of every trace at that time
#   - when `frozen` (simulation paused) the plot stops scrolling and the user
#     can drag left/right to scrub back through history
#   - drawing is DECIMATED: for each pixel column we keep only the min and max
#     sample, so long runs stay smooth on school laptops
#   - ghost runs (GhostRun): earlier runs drawn faded behind the live traces,
#     for every trace marked `ghost = true`. Challenge spec bands come later.
class_name StripChart
extends Control

# TUNABLE: chart layout and text sizes (pixels).
const MARGIN_LEFT: float = 62.0
const MARGIN_RIGHT: float = 12.0
const MARGIN_TOP: float = 30.0
const MARGIN_BOTTOM: float = 24.0
const TICK_FONT_SIZE: int = 13
const TITLE_FONT_SIZE: int = 15
const TARGET_Y_TICKS: int = 5
const TARGET_X_TICKS: int = 6
const DASH_LENGTH: float = 9.0
const GAP_LENGTH: float = 6.0
const AUTO_SCALE_PADDING: float = 0.08  # fraction of the data span added above/below

var recorder: RunRecorder
var traces: Array[ChartTrace] = []
var ghosts: Array[GhostRun] = []  # shared with the owner; drawn oldest first
var show_ghosts: bool = true
var chart_title: String = ""
var y_unit: String = ""
var time_window_s: float = 10.0
var auto_scale: bool = true
var auto_scale_includes_zero: bool = true
var fixed_y_min: float = 0.0  # display units, used when auto_scale is false
var fixed_y_max: float = 1.0
var frozen: bool = false:      # set by the owner while the simulation is paused
	set(value):
		frozen = value
		if not frozen:
			_scrub_end_time = -1.0  # resume following the newest data

var _hover_position: Vector2 = Vector2(-1.0, -1.0)
var _is_dragging: bool = false
var _scrub_end_time: float = -1.0  # < 0 means "follow the newest sample"


func _init() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(240.0, 140.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_position = Vector2(-1.0, -1.0)
		_is_dragging = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_hover_position = motion.position
		if _is_dragging and frozen:
			_scrub_by_pixels(motion.relative.x)
		queue_redraw()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = button.pressed
			accept_event()


# Lock the Y axis to whatever range is showing right now, or go back to
# auto-scaling. Useful for comparing runs without the axis moving.
func set_y_axis_locked(locked: bool) -> void:
	if locked:
		var time_range := _get_visible_time_range()
		var y_range := _get_y_range(time_range.x, time_range.y)
		fixed_y_min = y_range.x
		fixed_y_max = y_range.y
	auto_scale = not locked
	queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var plot_rect := _get_plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), DisplaySettings.plot_background())
	if plot_rect.size.x < 10.0 or plot_rect.size.y < 10.0:
		return

	var time_range := _get_visible_time_range()
	var y_range := _get_y_range(time_range.x, time_range.y)

	_draw_grid(plot_rect, time_range, y_range)
	if show_ghosts:
		for ghost in ghosts:
			for trace in traces:
				if trace.visible and trace.ghost:
					_draw_series(ghost.recorder, trace.channel, trace.display_scale,
							ghost.color, trace.width * DisplaySettings.line_scale(), false, plot_rect, time_range, y_range)
	for trace in traces:
		if trace.visible:
			_draw_series(recorder, trace.channel, trace.display_scale, trace.color,
					trace.width * DisplaySettings.line_scale(), trace.dashed, plot_rect, time_range, y_range)
	_draw_title_and_legend()
	_draw_hover_readout(plot_rect, time_range, y_range)
	if frozen:
		_draw_text(Vector2(plot_rect.end.x - 4.0, plot_rect.position.y + 14.0),
				"paused: drag to scrub", TICK_FONT_SIZE, SignalColors.WARNING_TEXT,
				HORIZONTAL_ALIGNMENT_RIGHT)


func _get_plot_rect() -> Rect2:
	return Rect2(MARGIN_LEFT, MARGIN_TOP,
			size.x - MARGIN_LEFT - MARGIN_RIGHT,
			size.y - MARGIN_TOP - MARGIN_BOTTOM)


# Returns Vector2(start_time, end_time) of the window being shown.
func _get_visible_time_range() -> Vector2:
	var newest_time := 0.0
	if recorder != null and recorder.get_count() > 0:
		newest_time = recorder.get_latest("time")
	var end_time := newest_time
	if _scrub_end_time >= 0.0:
		end_time = _scrub_end_time
	# At the start of a run, fill the window from the left instead of scrolling.
	end_time = maxf(end_time, time_window_s)
	return Vector2(end_time - time_window_s, end_time)


# Returns Vector2(y_min, y_max) in DISPLAY units.
func _get_y_range(start_time: float, end_time: float) -> Vector2:
	if not auto_scale:
		return Vector2(fixed_y_min, fixed_y_max)

	var data_min := INF
	var data_max := -INF
	if auto_scale_includes_zero:
		data_min = 0.0
		data_max = 0.0
	if recorder != null:
		var first := recorder.find_first_index_at_or_after(start_time)
		var last := recorder.find_first_index_at_or_after(end_time)
		last = mini(last, recorder.get_count() - 1)
		for trace in traces:
			if not trace.visible:
				continue
			for i in range(first, last + 1):
				var value := recorder.get_value(trace.channel, i) * trace.display_scale
				data_min = minf(data_min, value)
				data_max = maxf(data_max, value)
	# Ghosts count too, so a compared run is never cut off the top.
	if show_ghosts:
		for ghost in ghosts:
			var ghost_first := ghost.recorder.find_first_index_at_or_after(start_time)
			var ghost_last := mini(ghost.recorder.find_first_index_at_or_after(end_time),
					ghost.recorder.get_count() - 1)
			for trace in traces:
				if not (trace.visible and trace.ghost):
					continue
				for i in range(ghost_first, ghost_last + 1):
					var value := ghost.recorder.get_value(trace.channel, i) * trace.display_scale
					data_min = minf(data_min, value)
					data_max = maxf(data_max, value)

	if data_min == INF:  # no data at all
		return Vector2(0.0, 1.0)
	var span := data_max - data_min
	if span < 1e-9:
		# A flat line: make up a sensible range around it.
		span = maxf(absf(data_max) * 0.2, 1.0)
		data_min -= span * 0.5
		data_max += span * 0.5
	# Pad the range, but never push an all-positive (or all-negative) plot
	# across zero: a speed axis starting at -1000 RPM would look like a bug.
	var all_positive := data_min >= 0.0
	var all_negative := data_max <= 0.0
	data_min -= span * AUTO_SCALE_PADDING
	data_max += span * AUTO_SCALE_PADDING
	if all_positive:
		data_min = maxf(data_min, 0.0)
	if all_negative:
		data_max = minf(data_max, 0.0)
	# Snap the range out to whole tick steps so the axis does not jitter.
	var step := ChartAxis.tick_step_for_range(data_min, data_max, TARGET_Y_TICKS)
	return Vector2(floorf(data_min / step) * step, ceilf(data_max / step) * step)


func _time_to_x(time: float, plot_rect: Rect2, time_range: Vector2) -> float:
	var fraction := (time - time_range.x) / (time_range.y - time_range.x)
	return plot_rect.position.x + fraction * plot_rect.size.x


func _value_to_y(value: float, plot_rect: Rect2, y_range: Vector2) -> float:
	var fraction := (value - y_range.x) / (y_range.y - y_range.x)
	var y := plot_rect.end.y - fraction * plot_rect.size.y
	# Keep off-scale values on the edge instead of drawing outside the plot.
	return clampf(y, plot_rect.position.y, plot_rect.end.y)


func _draw_grid(plot_rect: Rect2, time_range: Vector2, y_range: Vector2) -> void:
	var y_step := ChartAxis.tick_step_for_range(y_range.x, y_range.y, TARGET_Y_TICKS)
	for tick in ChartAxis.tick_values(y_range.x, y_range.y, y_step):
		var y := _value_to_y(tick, plot_rect, y_range)
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y),
				DisplaySettings.plot_grid(), 1.0)
		_draw_text(Vector2(plot_rect.position.x - 6.0, y + 4.0),
				NumberFormat.for_step(tick, y_step), TICK_FONT_SIZE,
				SignalColors.PLOT_AXIS_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)

	var x_step := ChartAxis.tick_step_for_range(time_range.x, time_range.y, TARGET_X_TICKS)
	for tick in ChartAxis.tick_values(time_range.x, time_range.y, x_step):
		var x := _time_to_x(tick, plot_rect, time_range)
		draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y),
				DisplaySettings.plot_grid(), 1.0)
		_draw_text(Vector2(x, plot_rect.end.y + 16.0),
				NumberFormat.for_step(tick, x_step) + " s", TICK_FONT_SIZE,
				SignalColors.PLOT_AXIS_TEXT, HORIZONTAL_ALIGNMENT_CENTER)

	draw_rect(plot_rect, DisplaySettings.plot_grid(), false, 1.0)


# Draws one channel of `source` (the live recorder or a ghost's copy).
func _draw_series(source: RunRecorder, channel: String, display_scale: float,
		color: Color, width: float, dashed: bool, plot_rect: Rect2,
		time_range: Vector2, y_range: Vector2) -> void:
	if source == null or source.get_count() == 0:
		return
	# Include one sample on each side of the window so the line reaches the edges.
	var first := maxi(source.find_first_index_at_or_after(time_range.x) - 1, 0)
	var last := mini(source.find_first_index_at_or_after(time_range.y),
			source.get_count() - 1)
	if last <= first:
		return

	# DECIMATION: walk the samples; for every pixel column keep only the
	# lowest and highest value (in the order they happened). A 10-second window
	# at 100 Hz is 1000 samples but maybe 400 pixel columns wide.
	var points := PackedVector2Array()
	var column := -1
	var column_x := 0.0
	var column_min := 0.0
	var column_max := 0.0
	var min_came_first := true
	for i in range(first, last + 1):
		var x := _time_to_x(source.get_value("time", i), plot_rect, time_range)
		var value := source.get_value(channel, i) * display_scale
		var this_column := floori(x)
		if this_column != column:
			if column >= 0:
				_append_column(points, column_x, column_min, column_max,
						min_came_first, plot_rect, y_range)
			column = this_column
			column_x = x
			column_min = value
			column_max = value
			min_came_first = true
		else:
			if value < column_min:
				column_min = value
				min_came_first = false
			if value > column_max:
				column_max = value
				min_came_first = true
	_append_column(points, column_x, column_min, column_max, min_came_first,
			plot_rect, y_range)

	if points.size() < 2:
		return
	if dashed:
		_draw_dashed_polyline(points, color, width)
	else:
		draw_polyline(points, color, width, true)


func _append_column(points: PackedVector2Array, x: float, column_min: float,
		column_max: float, min_came_first: bool, plot_rect: Rect2,
		y_range: Vector2) -> void:
	var y_min := _value_to_y(column_min, plot_rect, y_range)
	var y_max := _value_to_y(column_max, plot_rect, y_range)
	if is_equal_approx(y_min, y_max):
		points.append(Vector2(x, y_min))
	elif min_came_first:
		points.append(Vector2(x, y_min))
		points.append(Vector2(x, y_max))
	else:
		points.append(Vector2(x, y_max))
		points.append(Vector2(x, y_min))


# Draws a polyline as dashes by walking along it and switching the "pen"
# on and off every DASH_LENGTH / GAP_LENGTH pixels.
func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	var pen_down := true
	var distance_left := DASH_LENGTH
	var current_dash := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var from := points[i - 1]
		var to := points[i]
		var segment_length := from.distance_to(to)
		var travelled := 0.0
		while segment_length - travelled > distance_left:
			travelled += distance_left
			var switch_point := from.lerp(to, travelled / segment_length)
			if pen_down:
				current_dash.append(switch_point)
				if current_dash.size() >= 2:
					draw_polyline(current_dash, color, width, true)
				distance_left = GAP_LENGTH
			else:
				current_dash = PackedVector2Array([switch_point])
				distance_left = DASH_LENGTH
			pen_down = not pen_down
		distance_left -= segment_length - travelled
		if pen_down:
			current_dash.append(to)
	if pen_down and current_dash.size() >= 2:
		draw_polyline(current_dash, color, width, true)


func _draw_title_and_legend() -> void:
	var title_text := chart_title
	if y_unit != "":
		title_text += " (%s)" % y_unit
	_draw_text(Vector2(MARGIN_LEFT, 19.0), title_text, TITLE_FONT_SIZE,
			SignalColors.PLOT_AXIS_TEXT, HORIZONTAL_ALIGNMENT_LEFT)

	# Legend entries flow to the right of the title.
	var font := get_theme_default_font()
	var x := MARGIN_LEFT + font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, TITLE_FONT_SIZE).x + 20.0
	for trace in traces:
		if not trace.visible:
			continue
		var sample_line := PackedVector2Array([Vector2(x, 14.0), Vector2(x + 22.0, 14.0)])
		if trace.dashed:
			draw_line(sample_line[0], Vector2(x + 9.0, 14.0), trace.color, trace.width)
			draw_line(Vector2(x + 14.0, 14.0), sample_line[1], trace.color, trace.width)
		else:
			draw_polyline(sample_line, trace.color, trace.width)
		_draw_text(Vector2(x + 27.0, 19.0), trace.label, TICK_FONT_SIZE,
				SignalColors.PLOT_AXIS_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		x += 40.0 + font.get_string_size(trace.label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				TICK_FONT_SIZE).x
	if not show_ghosts or not traces.any(func(t: ChartTrace) -> bool: return t.ghost):
		return
	for ghost in ghosts:
		draw_line(Vector2(x, 14.0), Vector2(x + 22.0, 14.0), ghost.color, 2.5)
		_draw_text(Vector2(x + 27.0, 19.0), ghost.label, TICK_FONT_SIZE,
				ghost.color, HORIZONTAL_ALIGNMENT_LEFT)
		x += 40.0 + font.get_string_size(ghost.label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				TICK_FONT_SIZE).x


func _draw_hover_readout(plot_rect: Rect2, time_range: Vector2, y_range: Vector2) -> void:
	if recorder == null or recorder.get_count() == 0:
		return
	if not plot_rect.has_point(_hover_position):
		return

	var fraction := (_hover_position.x - plot_rect.position.x) / plot_rect.size.x
	var hover_time := time_range.x + fraction * (time_range.y - time_range.x)
	var index := mini(recorder.find_first_index_at_or_after(hover_time),
			recorder.get_count() - 1)
	var sample_time := recorder.get_value("time", index)
	if sample_time < time_range.x or sample_time > time_range.y:
		return

	var x := _time_to_x(sample_time, plot_rect, time_range)
	draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y),
			SignalColors.PLOT_CROSSHAIR, 1.0)

	var lines: Array[String] = ["t = %s s" % String.num(sample_time, 2)]
	var line_colors: Array[Color] = [SignalColors.PLOT_AXIS_TEXT]
	for trace in traces:
		if not trace.visible:
			continue
		var value := recorder.get_value(trace.channel, index) * trace.display_scale
		draw_circle(Vector2(x, _value_to_y(value, plot_rect, y_range)), 3.5, trace.color)
		lines.append("%s: %s %s" % [trace.label, NumberFormat.significant(value, 4), y_unit])
		line_colors.append(trace.color)

	# Readout box, flipped to the left of the cursor near the right edge.
	var font := get_theme_default_font()
	var box_width := 0.0
	for line in lines:
		box_width = maxf(box_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT,
				-1, TICK_FONT_SIZE).x)
	box_width += 12.0
	var line_height := TICK_FONT_SIZE + 4.0
	var box_height := lines.size() * line_height + 8.0
	var box_x := x + 10.0
	if box_x + box_width > plot_rect.end.x:
		box_x = x - 10.0 - box_width
	var box_y := plot_rect.position.y + 6.0
	draw_rect(Rect2(box_x, box_y, box_width, box_height), Color(0.0, 0.0, 0.0, 0.75))
	for i in lines.size():
		_draw_text(Vector2(box_x + 6.0, box_y + 4.0 + (i + 1) * line_height - 4.0),
				lines[i], TICK_FONT_SIZE, line_colors[i], HORIZONTAL_ALIGNMENT_LEFT)


# draw_string() wrapper. For RIGHT/CENTER alignment `at.x` is the anchor point.
func _draw_text(at: Vector2, text: String, font_size: int, color: Color,
		alignment: HorizontalAlignment) -> void:
	var font := get_theme_default_font()
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var left := at.x
	if alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		left = at.x - text_width
	elif alignment == HORIZONTAL_ALIGNMENT_CENTER:
		left = at.x - text_width * 0.5
	draw_string(font, Vector2(left, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)


# ------------------------------------------------------------------ scrubbing

func _scrub_by_pixels(pixel_delta: float) -> void:
	if recorder == null or recorder.get_count() == 0:
		return
	var plot_width := maxf(_get_plot_rect().size.x, 1.0)
	var current_end := _get_visible_time_range().y
	var new_end := current_end - pixel_delta / plot_width * time_window_s
	var oldest := recorder.get_value("time", 0)
	var newest := recorder.get_latest("time")
	_scrub_end_time = clampf(new_end, minf(oldest + time_window_s, newest), newest)
