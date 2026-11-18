# term_bars.gd
#
# PURPOSE
#   Live horizontal bars showing how much each PID term (P, I, D, FF) contributes to
#   the command right now, and their sum. Bars grow right for positive and left
#   for negative values, from a centre line at zero. This is the "see the cause
#   and effect" view (README 1): change Kd and watch the D bar react instantly.
#
# HOW IT FITS
#   The PID panel calls set_terms() every frame with the controller's latest
#   term contributions. Drawn with the 2D API, no addons.
class_name TermBars
extends Control

const ROW_HEIGHT: float = 32.0
const LABEL_WIDTH: float = 60.0
const VALUE_WIDTH: float = 120.0
const FONT_SIZE: int = UiStyle.HINT
const TEXT_BASELINE: float = 24.0  # from the top of a row

const ROW_COUNT: int = 5

var _values: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _full_scale: float = 1.0  # the value that fills half the bar width
var _unit: String = ""
var _labels: PackedStringArray = ["P", "I", "D", "FF", "Sum"]
var _colors: Array[Color] = [SignalColors.P_TERM, SignalColors.I_TERM,
		SignalColors.D_TERM, SignalColors.FF_TERM, SignalColors.TERM_SUM]


func _init() -> void:
	custom_minimum_size = Vector2(300.0, ROW_HEIGHT * ROW_COUNT + 4.0)


func set_terms(terms: Dictionary, full_scale: float, unit: String) -> void:
	_values = PackedFloat64Array([terms.get("p", 0.0), terms.get("i", 0.0),
			terms.get("d", 0.0), terms.get("ff", 0.0), terms.get("sum", 0.0)])
	_full_scale = maxf(full_scale, 1e-9)
	_unit = unit
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var bar_left := LABEL_WIDTH
	var bar_width := size.x - LABEL_WIDTH - VALUE_WIDTH
	var center_x := bar_left + bar_width * 0.5
	draw_rect(Rect2(bar_left, 0.0, bar_width, ROW_HEIGHT * ROW_COUNT), SignalColors.PLOT_BACKGROUND)

	for row in ROW_COUNT:
		var top := row * ROW_HEIGHT
		var value := _values[row]
		draw_string(font, Vector2(6.0, top + TEXT_BASELINE), _labels[row], HORIZONTAL_ALIGNMENT_LEFT,
				-1, FONT_SIZE, _colors[row])
		# Bars beyond full scale are clipped and drawn with a marker at the end.
		var fraction := clampf(value / _full_scale, -1.0, 1.0)
		var length := fraction * bar_width * 0.5
		var bar := Rect2(minf(center_x, center_x + length), top + 6.0, absf(length), ROW_HEIGHT - 12.0)
		draw_rect(bar, _colors[row])
		if absf(value) > _full_scale:
			var edge_x := center_x + signf(value) * bar_width * 0.5
			draw_line(Vector2(edge_x, top + 2.0), Vector2(edge_x, top + ROW_HEIGHT - 2.0),
					SignalColors.WARNING_TEXT, 3.0)
		draw_string(font, Vector2(size.x - VALUE_WIDTH + 4.0, top + TEXT_BASELINE),
				"%s %s" % [NumberFormat.significant(value, 3), _unit],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SignalColors.PLOT_AXIS_TEXT)

	draw_line(Vector2(center_x, 0.0), Vector2(center_x, ROW_HEIGHT * ROW_COUNT),
			SignalColors.PLOT_CROSSHAIR, 1.0)
