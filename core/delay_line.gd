# delay_line.gd
#
# PURPOSE
#   A pure time delay: push one value every physics substep, read back the
#   value from N substeps ago. Used for sensor measurement delay and for a
#   plant's dead time (e.g. heat taking time to reach a thermistor).
#
# HOW IT FITS
#   Owned by Sensor and by Simulation (plant dead time). Because it is written
#   exactly once per fixed physics substep, "N substeps ago" is exactly
#   N * dt seconds ago, so the delay is deterministic and frame-rate independent.
#   The delay is rounded to a whole number of substeps (1 ms at 1 kHz).
#
# BEFORE THE BUFFER FILLS
#   At the start of a run there is no history yet. Reading further back than
#   the history goes returns `value_before_start` if it is set (e.g. 0 for a
#   plant input: "nothing was applied before t = 0"), otherwise the oldest
#   value pushed (e.g. for a sensor: "the output was like this before t = 0").
class_name DelayLine
extends RefCounted

var _values: PackedFloat64Array = PackedFloat64Array()
var _next_write: int = 0
var _count: int = 0
var value_before_start: float = NAN   # NAN = "repeat the oldest value"


# max_steps: the longest delay (in substeps) that will ever be asked for.
func _init(max_steps: int = 1) -> void:
	_values.resize(maxi(max_steps, 0) + 1)


func clear() -> void:
	_next_write = 0
	_count = 0


func push(value: float) -> void:
	_values[_next_write] = value
	_next_write = (_next_write + 1) % _values.size()
	_count = mini(_count + 1, _values.size())


# Value pushed `steps_ago` pushes before the newest one (0 = newest).
func read(steps_ago: int) -> float:
	if steps_ago >= _count and not is_nan(value_before_start):
		return value_before_start
	if _count == 0:
		return 0.0
	var clamped := clampi(steps_ago, 0, _count - 1)
	var index := posmod(_next_write - 1 - clamped, _values.size())
	return _values[index]


func get_max_steps() -> int:
	return _values.size() - 1
