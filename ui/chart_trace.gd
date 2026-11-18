# chart_trace.gd
#
# PURPOSE
#   Describes ONE line on a strip chart: which recorder channel it reads, its
#   legend label, color, width, dash style, and the SI -> display unit scale.
#
# HOW IT FITS
#   ui/main_screen.gd creates ChartTrace objects and gives them to a StripChart.
#   The chart reads values from the RunRecorder and multiplies by
#   `display_scale` while drawing (unit conversion at the UI boundary only).
class_name ChartTrace
extends RefCounted

var channel: String          # recorder channel name, e.g. "measurement"
var label: String            # legend text, e.g. "Measured speed"
var color: Color
var width: float = 2.0       # pixels
var dashed: bool = false     # dashed lines help when color is hard to see
var display_scale: float = 1.0
var visible: bool = true


func _init(new_channel: String, new_label: String, new_color: Color,
		new_display_scale: float = 1.0, new_dashed: bool = false,
		new_width: float = 2.0) -> void:
	channel = new_channel
	label = new_label
	color = new_color
	display_scale = new_display_scale
	dashed = new_dashed
	width = new_width
