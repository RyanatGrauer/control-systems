# challenge_result.gd
#
# PURPOSE
#   The outcome of one challenge test: one row per spec (limit, measured
#   value, pass/fail) and the score.
#
# SCORING (README 7.6: pass/fail per spec, with a score)
#   score = 100 x (specs passed) / (specs graded), rounded down.
#   Between two runs with the same score, the lower IAE (total error) is
#   better (is_better_than). No partial credit for a near miss: a spec is
#   met or it isn't, which is how a real specification works.
class_name ChallengeResult
extends RefCounted

# Each row: {"key", "title", "unit_kind", "limit", "value", "passed"}.
# "value" is NAN when it could not be measured (e.g. never settled) and that
# counts as a fail.
var rows: Array[Dictionary] = []
var iae: float = INF


func get_passed_count() -> int:
	return rows.filter(func(row: Dictionary) -> bool: return row["passed"]).size()


func get_score() -> int:
	if rows.is_empty():
		return 0
	return floori(100.0 * get_passed_count() / rows.size())


func is_complete() -> bool:
	return not rows.is_empty() and get_passed_count() == rows.size()


func is_better_than(score: int, other_iae: float) -> bool:
	return get_score() > score or (get_score() == score and iae < other_iae)
