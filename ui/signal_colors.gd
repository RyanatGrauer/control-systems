# signal_colors.gd
#
# PURPOSE
#   The project's COLOR LANGUAGE (README 4.4): each signal has one color that is
#   used everywhere: plots, 3D scene labels, and (later) the block diagram.
#   Setpoint is always orange, measurement always sky blue, and so on.
#
# WHY THESE COLORS
#   They come from the Okabe-Ito palette, which stays distinguishable for
#   students with common color-vision deficiencies and survives washed-out
#   projectors reasonably well. Color is never the ONLY cue: plots also use
#   line style (setpoint is dashed) and every trace has a text legend.
#
# HOW IT FITS
#   Pure constants; any script may read them. Presenter mode (stage 18) may add
#   a high-contrast variant here.
class_name SignalColors
extends RefCounted

const SETPOINT: Color = Color("#E69F00")       # orange, drawn dashed
const MEASUREMENT: Color = Color("#56B4E9")    # sky blue, solid
const TRUE_OUTPUT: Color = Color("#009E73")    # bluish green, thin
const COMMAND: Color = Color("#CC79A7")        # reddish purple, dashed
const APPLIED_INPUT: Color = Color("#F0E442")  # yellow, solid
const DISTURBANCE: Color = Color("#D55E00")    # vermillion
const ERROR: Color = Color("#E8E8E8")          # near-white

# PID term contributions. These only appear together in the term plot and the
# term bars, so they reuse no signal colours; each also has its own label.
const P_TERM: Color = Color("#FF7F6E")         # coral
const I_TERM: Color = Color("#5FD3B3")         # mint
const D_TERM: Color = Color("#B39DFF")         # lavender
const FF_TERM: Color = Color("#7FB8FF")        # light blue (feedforward)

# Ghost runs (earlier runs drawn faded behind the live traces), oldest first.
const GHOST_COLORS: Array[Color] = [
	Color(0.85, 0.85, 0.85, 0.55),  # grey
	Color(0.95, 0.70, 0.95, 0.55),  # pink
	Color(0.70, 0.95, 0.75, 0.55),  # pale green
]
const TERM_SUM: Color = Color("#FFFFFF")       # white, drawn dashed

# Plot furniture.
# Challenge spec bands (stage 20): where the output must be.
const SPEC_BAND: Color = Color("#6FE08A")      # green: "be inside here"
const SPEC_LIMIT: Color = Color("#FF6B6B")     # red dashed: "stay below this line"
const LOAD_BAND: Color = Color("#FFB86B")      # amber: after the load

const PLOT_BACKGROUND: Color = Color(0.09, 0.10, 0.12)
const PLOT_GRID: Color = Color(1.0, 1.0, 1.0, 0.10)
const PLOT_AXIS_TEXT: Color = Color(0.80, 0.82, 0.86)
const PLOT_CROSSHAIR: Color = Color(1.0, 1.0, 1.0, 0.55)
const WARNING_TEXT: Color = Color("#F0E442")
