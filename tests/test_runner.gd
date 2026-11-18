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
extends Node

const TEST_FOLDER: String = "res://tests/"


func _ready() -> void:
	var total_tests := 0
	var failed_tests := 0

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
			test_object.call(method_name)
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
	get_tree().quit(0 if failed_tests == 0 else 1)


func _find_test_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(TEST_FOLDER):
		if file_name.begins_with("test_") and file_name.ends_with(".gd") \
				and file_name != "test_runner.gd" and file_name != "test_case.gd":
			found.append(file_name)
	found.sort()
	return found
