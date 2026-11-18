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

# Plot furniture.
const PLOT_BACKGROUND: Color = Color(0.09, 0.10, 0.12)
const PLOT_GRID: Color = Color(1.0, 1.0, 1.0, 0.10)
const PLOT_AXIS_TEXT: Color = Color(0.80, 0.82, 0.86)
const PLOT_CROSSHAIR: Color = Color(1.0, 1.0, 1.0, 0.55)
const WARNING_TEXT: Color = Color("#F0E442")
