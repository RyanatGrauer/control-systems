# sim_clock.gd
#
# PURPOSE
#   Turns real (wall-clock) frame time into a whole number of fixed physics
#   substeps. This is the "fixed-timestep accumulator" from README section 4.1.
#
# HOW IT FITS
#   The main screen calls `consume_frame(delta)` once per rendered frame and then
#   runs Simulation.step_physics() that many times. Because the simulation only
#   ever advances in identical fixed steps, results do NOT depend on frame rate.
#
# SPIRAL OF DEATH PROTECTION
#   If a frame is very slow (or the browser tab was hidden), the accumulator
#   could ask for thousands of steps, which makes the next frame slow too, and so
#   on. We cap the steps per frame. When the cap is hit we throw away the
#   backlog (simulated time runs slower than real time for a moment) and set
#   `is_running_slow` so the UI can show a small warning. We never skip steps
#   inside the simulation itself.
class_name SimClock
extends RefCounted

# TUNABLE: most physics substeps allowed in one rendered frame.
# 1000 Hz physics x 4x time-scale at 60 fps needs ~67; 400 leaves headroom.
const MAX_STEPS_PER_FRAME: int = 400

# TUNABLE: time-scale slider limits (1.0 = real time).
const MIN_TIME_SCALE: float = 0.1
const MAX_TIME_SCALE: float = 4.0

var physics_dt: float = 0.001   # seconds per substep (set from the physics rate)
var time_scale: float = 1.0     # simulated seconds per real second
var is_paused: bool = false
var is_running_slow: bool = false  # true if the LAST frame hit the step cap

var _accumulator: float = 0.0   # simulated time owed but not yet stepped


func _init(new_physics_dt: float = 0.001) -> void:
	physics_dt = new_physics_dt


# Returns how many fixed substeps to run for a frame that took `real_delta`
# seconds of wall-clock time.
func consume_frame(real_delta: float) -> int:
	is_running_slow = false
	if is_paused:
		return 0

	_accumulator += real_delta * time_scale
	var steps := int(floorf(_accumulator / physics_dt))

	if steps > MAX_STEPS_PER_FRAME:
		steps = MAX_STEPS_PER_FRAME
		_accumulator = 0.0  # drop the backlog instead of trying to catch up
		is_running_slow = true
	else:
		_accumulator -= steps * physics_dt
	return steps


func set_time_scale(new_scale: float) -> void:
	time_scale = clampf(new_scale, MIN_TIME_SCALE, MAX_TIME_SCALE)


func reset() -> void:
	_accumulator = 0.0
	is_running_slow = false
