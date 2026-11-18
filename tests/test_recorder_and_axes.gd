# test_recorder_and_axes.gd
#
# Ring-buffer recorder and plot-axis helpers.
extends TestCase


func _make_recorder(capacity: int) -> RunRecorder:
	return RunRecorder.new(PackedStringArray(["time", "value"]), capacity)


func test_recorder_keeps_order_before_wrapping() -> void:
	var recorder := _make_recorder(5)
	for i in 3:
		recorder.record({"time": i * 0.1, "value": i})
	check_equal(recorder.get_count(), 3, "count")
	check_equal(recorder.get_value("value", 0), 0.0, "oldest")
	check_equal(recorder.get_latest("value"), 2.0, "newest")


func test_recorder_overwrites_oldest_when_full() -> void:
	var recorder := _make_recorder(5)
	for i in 8:
		recorder.record({"time": i * 0.1, "value": i})
	check_equal(recorder.get_count(), 5, "count stays at capacity")
	for i in 5:
		check_equal(recorder.get_value("value", i), float(i + 3), "sample %d after wrap" % i)


func test_recorder_finds_times_after_wrapping() -> void:
	var recorder := _make_recorder(5)
	for i in 8:
		recorder.record({"time": float(i), "value": i})
	# Stored times are now 3, 4, 5, 6, 7.
	check_equal(recorder.find_first_index_at_or_after(5.0), 2, "exact time")
	check_equal(recorder.find_first_index_at_or_after(4.5), 2, "between samples")
	check_equal(recorder.find_first_index_at_or_after(0.0), 0, "before all")
	check_equal(recorder.find_first_index_at_or_after(99.0), 5, "after all")


func test_missing_channel_records_zero() -> void:
	var recorder := _make_recorder(3)
	recorder.record({"time": 1.0})
	check_equal(recorder.get_latest("value"), 0.0, "missing channel")


func test_nice_tick_steps() -> void:
	check_near(ChartAxis.nice_step(0.37), 0.5, 1e-12, "0.37")
	check_near(ChartAxis.nice_step(1.3), 2.0, 1e-12, "1.3")
	check_near(ChartAxis.nice_step(7.0), 10.0, 1e-12, "7")
	check_near(ChartAxis.nice_step(1000.0), 1000.0, 1e-9, "1000")
	check_near(ChartAxis.nice_step(0.002), 0.002, 1e-15, "0.002")


func test_tick_values() -> void:
	var ticks := ChartAxis.tick_values(-1.2, 3.4, 1.0)
	check_equal(ticks, PackedFloat64Array([-1.0, 0.0, 1.0, 2.0, 3.0]), "ticks")


func test_number_format() -> void:
	check_equal(NumberFormat.significant(0.0004), "0.0004", "small value")
	check_equal(NumberFormat.significant(3.14159, 3), "3.14", "pi")
	check_equal(NumberFormat.significant(1234.567, 4), "1235", "large value")
	check_equal(NumberFormat.significant(0.0), "0", "zero")
	check_equal(NumberFormat.for_step(2.5, 0.5), "2.5", "half steps")
	check_equal(NumberFormat.for_step(300.0, 100.0), "300", "hundreds")
	check_equal(NumberFormat.for_step(-1e-12, 0.5), "0", "no negative zero")
