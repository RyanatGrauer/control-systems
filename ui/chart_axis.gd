# chart_axis.gd
#
# PURPOSE
#   Math for plot axes: picking "nice" tick spacings (1, 2, 5 x 10^n) so tick
#   labels read like 0, 500, 1000 instead of 0, 437.2, 874.4.
#
# HOW IT FITS
#   ui/strip_chart.gd calls these when drawing grid lines and tick labels.
#   Kept separate (and static) so the logic can be unit-tested headless.
class_name ChartAxis
extends RefCounted


# Smallest "nice" number >= raw_step, where nice means 1, 2 or 5 times 10^n.
static func nice_step(raw_step: float) -> float:
	if raw_step <= 0.0 or not is_finite(raw_step):
		return 1.0
	var power_of_ten := pow(10.0, floorf(log(raw_step) / log(10.0)))
	var fraction := raw_step / power_of_ten  # between 1 and 10
	var nice_fraction := 10.0
	if fraction <= 1.0001:
		nice_fraction = 1.0
	elif fraction <= 2.0001:
		nice_fraction = 2.0
	elif fraction <= 5.0001:
		nice_fraction = 5.0
	return nice_fraction * power_of_ten


# Tick spacing for a range, aiming for about `target_tick_count` ticks.
static func tick_step_for_range(range_min: float, range_max: float,
		target_tick_count: int) -> float:
	var span := range_max - range_min
	return nice_step(span / maxi(target_tick_count, 1))


# Tick values from the first multiple of `step` at or above `range_min`.
static func tick_values(range_min: float, range_max: float, step: float) -> PackedFloat64Array:
	var ticks := PackedFloat64Array()
	if step <= 0.0:
		return ticks
	var tick := ceilf(range_min / step - 0.0001) * step
	# Safety cap: never produce an absurd number of ticks.
	while tick <= range_max + step * 0.0001 and ticks.size() < 100:
		ticks.append(tick)
		tick += step
	return ticks
