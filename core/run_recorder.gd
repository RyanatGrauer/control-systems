# run_recorder.gd
#
# PURPOSE
#   Stores the recent history of a run: a fixed-size RING BUFFER per named
#   channel ("time", "setpoint", "measurement", ...). When the buffer is full the
#   oldest sample is overwritten, so memory use never grows during long runs.
#
# HOW IT FITS
#   Simulation writes one sample (all channels at once) at the record rate.
#   Plots (ui/strip_chart.gd), later metrics and CSV export only READ from here.
#   This is how the UI observes the simulation without driving it (README 9).
#
# INDEXING
#   Users of the recorder never see the ring's physical layout. Sample index 0
#   is always the OLDEST stored sample and index (get_count() - 1) the NEWEST.
class_name RunRecorder
extends RefCounted

var _capacity: int
var _channel_names: PackedStringArray
var _channels: Dictionary = {}  # channel name -> PackedFloat64Array (ring storage)
var _count: int = 0             # how many valid samples are stored
var _next_write: int = 0        # physical slot the next sample goes into


func _init(channel_names: PackedStringArray, capacity: int) -> void:
	_capacity = maxi(capacity, 2)
	_channel_names = channel_names
	for channel_name in channel_names:
		var storage := PackedFloat64Array()
		storage.resize(_capacity)
		_channels[channel_name] = storage


func clear() -> void:
	_count = 0
	_next_write = 0


# `values` maps channel name -> float. Channels missing from `values` store 0.
func record(values: Dictionary) -> void:
	for channel_name in _channel_names:
		var storage: PackedFloat64Array = _channels[channel_name]
		# Packed arrays are shared by reference, so this writes into the
		# array stored in the dictionary (no copy is made).
		storage[_next_write] = values.get(channel_name, 0.0)
	_next_write = (_next_write + 1) % _capacity
	_count = mini(_count + 1, _capacity)


func get_count() -> int:
	return _count


func get_capacity() -> int:
	return _capacity


func has_channel(channel_name: String) -> bool:
	return _channels.has(channel_name)


func get_channel_names() -> PackedStringArray:
	return _channel_names


# Value of `channel_name` at logical index (0 = oldest).
func get_value(channel_name: String, index: int) -> float:
	var storage: PackedFloat64Array = _channels[channel_name]
	return storage[_physical_index(index)]


func get_latest(channel_name: String) -> float:
	if _count == 0:
		return 0.0
	return get_value(channel_name, _count - 1)


# Index of the first sample whose "time" is >= `time`. Returns get_count() if
# every sample is earlier. Uses binary search because time always increases.
func find_first_index_at_or_after(time: float) -> int:
	var low := 0
	var high := _count
	while low < high:
		var middle := floori((low + high) / 2.0)
		if get_value("time", middle) < time:
			low = middle + 1
		else:
			high = middle
	return low


func _physical_index(logical_index: int) -> int:
	# When the buffer is not yet full the oldest sample is in slot 0.
	# Once full, the oldest sample is the one about to be overwritten next.
	var oldest_slot := 0
	if _count == _capacity:
		oldest_slot = _next_write
	return (oldest_slot + logical_index) % _capacity
