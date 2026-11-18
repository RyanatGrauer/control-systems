# ui_style.gd
#
# PURPOSE
#   One table of text sizes for the whole UI, so legibility is decided in one
#   place (README 2: readable on a washed-out classroom projector).
#
# HOW SIZES WORK
#   The window is designed at 1920x1080 (project.godot) and stretched
#   ("canvas_items") to whatever size it really is. On a 1280x720 window
#   everything is drawn at 2/3 of these numbers. That's why nothing here goes
#   below SMALLEST (20 px at 1080p, about 13 px at 720p).
#   Godot's built-in controls follow gui/theme/default_theme_scale = 1.5, which
#   makes the default font BODY (16 x 1.5 = 24) and scales checkboxes, scroll
#   bars and margins to match.
#   Custom-drawn controls (charts, term bars, block diagram) use these
#   constants directly.
class_name UiStyle
extends RefCounted

# TUNABLE: text sizes in pixels at 1920x1080.
const BODY: int = 24          # default for every Label/Button (from the theme scale)
const LARGE: int = 27         # live readouts students look at while tuning
const HINT: int = 21          # explanatory text under controls
const SMALLEST: int = 20      # nothing on screen is smaller than this
const CHART_TICK: int = 20    # axis numbers, legend, hover box
const CHART_TITLE: int = 24
const DIAGRAM_BLOCK: int = 24
const DIAGRAM_VALUE: int = 21

# Plot line widths are given at 1280-era sizes; this scales them for 1080p.
const LINE_WIDTH_SCALE: float = 1.5

# Hint text: lighter than the plot-axis grey so it survives a projector.
const HINT_COLOR: Color = Color(0.78, 0.80, 0.85)


# The standard wrapped explanatory label used under controls.
static func make_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(240.0, 0.0)
	label.add_theme_font_size_override("font_size", HINT)
	label.add_theme_color_override("font_color", HINT_COLOR)
	return label
