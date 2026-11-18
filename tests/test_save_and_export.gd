# test_save_and_export.gd
#
# PURPOSE
#   Tests for the save system (README 7.10) and CSV export (README 7.8):
#   round trips, validation of untrusted data, corrupt-file recovery, save
#   codes, and the CSV header/rows. Uses the scratch save path that the test
#   runner sets, never a real student save.
extends TestCase


func _fresh_store() -> SaveStore:
	DirAccess.make_dir_recursive_absolute(SaveStore.save_path.get_base_dir())
	for file_name in DirAccess.get_files_at(SaveStore.save_path.get_base_dir()):
		DirAccess.remove_absolute(SaveStore.save_path.get_base_dir().path_join(file_name))
	return SaveStore.new()


func test_round_trip_through_disk() -> void:
	var store := _fresh_store()
	var pid := PidController.new()
	pid.proportional_gain = 3.5
	pid.anti_windup = PidController.AntiWindup.BACK_CALCULATION
	store.data["snapshots"]["Flywheel"] = {"A": pid.get_tuning()}
	store.data["settings"]["presenter"] = true
	check_true(store.write_to_disk(), "write succeeds")
	check_true(not FileAccess.file_exists(SaveStore.save_path + ".tmp"), "temp file replaced the save")

	var loaded := SaveStore.new()
	check_equal(loaded.load_from_disk(), "", "loads without complaint")
	var tuning: Dictionary = loaded.data["snapshots"]["Flywheel"]["A"]
	check_near(tuning["proportional_gain"], 3.5, 1e-12, "gain survives")
	check_equal(typeof(tuning["anti_windup"]), TYPE_INT, "enum comes back as an int, not a JSON float")
	check_equal(tuning["anti_windup"], PidController.AntiWindup.BACK_CALCULATION, "enum value survives")
	check_equal(loaded.data["settings"]["presenter"], true, "settings survive")


func test_validation_rejects_junk() -> void:
	var clean := SaveStore.validate({
		"schema_version": 1,
		"settings": {"presenter": "yes please", "render_scale": INF, "evil": "x", "shadows": false},
		"snapshots": {"Flywheel": {"A": {"proportional_gain": 2.0, "queue_free": 1.0,
			"integral_gain": "lots"}, "Z": {"proportional_gain": 9.0}}, "Bad": 5},
		"script": "res://hack.gd",
	})
	check_true(not clean.has("script"), "unknown top-level key dropped")
	check_equal(clean["settings"]["presenter"], false, "wrong type -> default")
	check_near(clean["settings"]["render_scale"], 1.0, 1e-12, "non-finite number -> default")
	check_equal(clean["settings"]["shadows"], false, "good value kept")
	check_true(not clean["settings"].has("evil"), "unknown setting dropped")
	var slots: Dictionary = clean["snapshots"]["Flywheel"]
	check_true(not slots.has("Z"), "unknown slot dropped")
	check_true(not slots["A"].has("queue_free"), "non-PID key dropped")
	check_true(not slots["A"].has("integral_gain"), "wrong-typed gain dropped")
	check_true(not clean["snapshots"].has("Bad"), "malformed scenario entry dropped")


func test_corrupt_file_is_set_aside() -> void:
	_fresh_store()
	var file := FileAccess.open(SaveStore.save_path, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var store := SaveStore.new()
	SaveStore.print_warnings = false  # this corrupt file is on purpose
	var message := store.load_from_disk()
	SaveStore.print_warnings = true
	check_true(message != "", "the student is told")
	check_true(not FileAccess.file_exists(SaveStore.save_path), "corrupt file moved away")
	var backups := Array(DirAccess.get_files_at(SaveStore.save_path.get_base_dir())).filter(
			func(name: String) -> bool: return name.contains("corrupt"))
	check_equal(backups.size(), 1, "one backup kept")
	check_equal(store.data["snapshots"], {}, "fresh defaults")


func test_save_code_round_trip() -> void:
	var store := _fresh_store()
	store.data["snapshots"]["Servo"] = {"B": {"proportional_gain": 7.0}}
	var code := store.to_save_code()
	check_true(code.begins_with(SaveStore.SAVE_CODE_PREFIX), "code has its prefix")
	var other := SaveStore.new()
	check_equal(other.import_save_code("  " + code + "\n"), "", "code imports (whitespace ignored)")
	check_near(other.data["snapshots"]["Servo"]["B"]["proportional_gain"], 7.0, 1e-12, "data survives")
	check_true(other.import_save_code("hello") != "", "garbage code rejected")
	check_true(other.import_save_code(SaveStore.SAVE_CODE_PREFIX + "AAAA") != "", "damaged code rejected")
	check_true(other.import_json_text("[1, 2, 3]") != "", "non-save JSON rejected")
	check_near(other.data["snapshots"]["Servo"]["B"]["proportional_gain"], 7.0, 1e-12,
			"a rejected import leaves the save alone")


func test_csv_export() -> void:
	var plant := FlywheelPlant.new()
	var pid := PidController.new()
	pid.proportional_gain = 0.5
	var simulation := Simulation.new(plant, pid)
	simulation.reset()
	for i in 1000:
		simulation.step_physics()
	var csv := CsvExport.build(simulation, "Flywheel, basic")
	var lines := csv.strip_edges().split("\n")
	check_true(lines[0].begins_with("#"), "comment header first")
	check_true("Kp=0.5" in csv, "gains recorded")
	check_true("seed: %d" % simulation.random_seed in csv, "seed recorded")
	var header_index := 0
	while lines[header_index].begins_with("#"):
		header_index += 1
	check_true(lines[header_index].begins_with("time_s,setpoint,measurement"), "column titles")
	check_equal(lines.size() - header_index - 1, simulation.recorder.get_count(), "one row per sample")
	check_equal(lines[header_index + 1].split(",").size(), CsvExport.COLUMNS.size(), "full rows")
	check_true(CsvExport.make_file_name("Hotend: windup!").ends_with(".csv"), "file name")
	check_true(not CsvExport.make_file_name("a/b:c").contains("/"), "file name is safe")
