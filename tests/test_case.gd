# test_case.gd
#
# PURPOSE
#   Base class for every test script (README section 11: no third-party test
#   framework). A test script extends TestCase and defines functions whose
#   names start with "test_". Each one uses the check_*() helpers below.
#
# HOW IT FITS
#   tests/test_runner.gd finds every tests/test_*.gd file, creates the script,
#   calls each test_ function, and reads `failures` afterwards.
class_name TestCase
extends RefCounted

# Messages for failed checks in the CURRENT test function (runner clears it).
var failures: PackedStringArray = []


func check_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


# Passes when |actual - expected| <= tolerance.
func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not is_finite(actual) or absf(actual - expected) > tolerance:
		failures.append("%s: expected %s +/- %s, got %s (off by %s)" % [
			message, expected, tolerance, actual, absf(actual - expected)])


func check_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, expected, actual])
