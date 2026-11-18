# test_runner.gd
#
# PURPOSE
#   Minimal in-engine test runner (README section 11). Finds every
#   res://tests/test_*.gd script, runs each function starting with "test_",
#   and prints PASS/FAIL with clear messages.
#
# HOW TO RUN
#   Editor:        open tests/test_runner.tscn and press "Run Current Scene" (F6).
#                  Results appear in the Output panel.
#   Command line:  godot --headless --path . res://tests/test_runner.tscn
#                  Exit code is 0 if everything passed, 1 otherwise.
#
# HOW TESTS ARE FOUND
#   We list the script files in res://tests/, then ask each script object for
#   its method list and call the ones named test_*. That is the only
#   "reflection" in the project and it is limited to this file.
#
# CATCHING CRASHES
#   If a test hits a script error (e.g. calling a function on null), Godot
#   aborts that test function but the runner keeps going, so the test would
#   look like a pass. ErrorCounter (below) is registered with OS.add_logger()
#   and counts every error Godot reports; any error during a test fails it.
extends Node

const TEST_FOLDER: String = "res://tests/"


# Counts errors reported by the engine (script errors, push_error, ...).
# GODOT-VERSION: the Logger class and OS.add_logger() need Godot 4.5 or newer.
class ErrorCounter:
	extends Logger
	var error_count: int = 0
	var last_message: String = ""

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		error_count += 1
		var message := rationale if rationale != "" else code
		last_message = "%s (%s:%d in %s)" % [message, file, line, function]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	# Deferred: while _ready() runs the scene root is still setting up its
	# children, so tests that add nodes to the tree (UI smoke tests) would fail.
	_run_all_tests.call_deferred()


func _run_all_tests() -> void:
	var total_tests := 0
	var failed_tests := 0
	var error_counter := ErrorCounter.new()
	OS.add_logger(error_counter)

	for file_name in _find_test_files():
		var script: GDScript = load(TEST_FOLDER + file_name)
		var test_object: TestCase = script.new()
		print("\n== %s" % file_name)
		for method in test_object.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total_tests += 1
			test_object.failures.clear()
			var errors_before := error_counter.error_count
			test_object.call(method_name)
			if error_counter.error_count > errors_before:
				test_object.failures.append("engine/script error: " + error_counter.last_message)
			if test_object.failures.is_empty():
				print("  PASS  %s" % method_name)
			else:
				failed_tests += 1
				print("  FAIL  %s" % method_name)
				for message in test_object.failures:
					print("          - %s" % message)

	print("\n%d tests, %d passed, %d failed" % [total_tests, total_tests - failed_tests,
			failed_tests])
	print("ALL TESTS PASSED" if failed_tests == 0 else "SOME TESTS FAILED")
	OS.remove_logger(error_counter)
	get_tree().quit(0 if failed_tests == 0 else 1)


func _find_test_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(TEST_FOLDER):
		if file_name.begins_with("test_") and file_name.ends_with(".gd") \
				and file_name != "test_runner.gd" and file_name != "test_case.gd":
			found.append(file_name)
	found.sort()
	return found
