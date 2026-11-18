# number_format.gd
#
# PURPOSE
#   Small helpers for turning numbers into readable text in the UI, e.g.
#   0.000400 -> "0.0004", 1234.567 -> "1235", 3.14159 -> "3.14".
#
# HOW IT FITS
#   Used by sliders, readouts and plot tick labels. Pure functions, no state.
class_name NumberFormat
extends RefCounted


# Show `value` with about `significant_digits` meaningful digits.
static func significant(value: float, significant_digits: int = 3) -> String:
	if not is_finite(value):
		return str(value)  # "inf" or "nan": show it rather than hide a bug
	if value == 0.0:
		return "0"
	var magnitude := floori(log(absf(value)) / log(10.0))  # 1234 -> 3, 0.05 -> -2
	var decimals := clampi(significant_digits - 1 - magnitude, 0, 9)
	return String.num(value, decimals)


# Show `value` with exactly enough decimals for a tick spacing of `step`.
# Example: step 0.5 -> "2.5"; step 100 -> "300".
static func for_step(value: float, step: float) -> String:
	if step <= 0.0:
		return significant(value)
	# Rounding can leave a tick at -0.0000001, which would print as "-0".
	if absf(value) < step * 1e-6:
		return "0"
	var decimals := clampi(-floori(log(step) / log(10.0) + 0.0001), 0, 9)
	return String.num(value, decimals)
