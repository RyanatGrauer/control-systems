# trapezoidal_profile.gd
#
# PURPOSE
#   A trapezoidal motion profile (README 6.2): instead of jumping straight to
#   a new target, the setpoint speeds up at `max_acceleration`, cruises at
#   `max_velocity`, and slows down to arrive exactly at the target. Plotted
#   speed vs time is a trapezoid (or a triangle for short moves).
#   It also provides the setpoint's velocity and acceleration, which the
#   kV and kA feedforward terms need.
#
# HOW IT FITS
#   Simulation owns one. Each controller tick it passes in the raw setpoint
#   from SetpointGenerator; when that target CHANGES, the profile re-plans
#   from wherever it is now (position AND velocity), so changing the target
#   mid-move is smooth too.
#
# HOW A PLAN IS STORED
#   A list of segments with constant acceleration. Each segment holds
#   [start_time, duration, start_position, start_velocity, acceleration].
#   sample() finds the segment containing t and uses
#       p = p0 + v0*dt + a*dt^2/2,   v = v0 + a*dt.
#
# PLANNING (s = direction toward the target, everything below in that direction)
#   1. If currently moving AWAY from the target, or too fast to stop in time,
#      first brake to a standstill (one segment), then plan from there.
#   2. Otherwise: accelerate (or brake, if above max_velocity) to the peak
#      speed, cruise, then brake to stop exactly at the target. The peak speed
#      is max_velocity, or lower if the move is too short to reach it.
class_name TrapezoidalProfile
extends RefCounted

var max_velocity: float = 1.0       # SI units per second (positive)
var max_acceleration: float = 1.0   # SI units per second² (positive)

var _segments: Array[PackedFloat64Array] = []
var _goal: float = NAN
var _end_position: float = 0.0


# Start at rest at `position` (call at the start of a run).
func reset(position: float) -> void:
	_segments.clear()
	_goal = position
	_end_position = position


func get_goal() -> float:
	return _goal


# Plan a move to `target` starting at `time` from the current motion.
func plan_to(target: float, time: float) -> void:
	var now := sample(time)
	_segments.clear()
	_goal = target
	_end_position = target
	var accel := maxf(max_acceleration, 1e-9)
	var cruise_speed := maxf(max_velocity, 1e-9)
	var position := now[0]
	var velocity := now[1]
	var start := time

	var distance := target - position
	var direction := signf(distance) if distance != 0.0 else -signf(velocity)
	if direction == 0.0:
		return  # already at rest on the target

	# Step 1: moving the wrong way or can't stop in time -> brake to zero first.
	var speed_toward := velocity * direction
	var stopping_distance := speed_toward * speed_toward / (2.0 * accel)
	if speed_toward < 0.0 or stopping_distance > absf(distance):
		var brake_time := absf(velocity) / accel
		_add_segment(start, brake_time, position, velocity, -signf(velocity) * accel)
		position += velocity * brake_time * 0.5
		velocity = 0.0
		start += brake_time
		distance = target - position
		direction = signf(distance)
		if direction == 0.0:
			return
		speed_toward = 0.0

	# Step 2: accelerate/brake to the peak speed, cruise, brake to a stop.
	var remaining := absf(distance)
	var peak := minf(cruise_speed,
			sqrt(accel * remaining + speed_toward * speed_toward * 0.5))
	var ramp_time := absf(peak - speed_toward) / accel
	var ramp_distance := (peak + speed_toward) * 0.5 * ramp_time
	var brake_time_2 := peak / accel
	var brake_distance := peak * peak / (2.0 * accel)
	var cruise_time := maxf(remaining - ramp_distance - brake_distance, 0.0) / peak

	var ramp_accel := direction * accel * signf(peak - speed_toward)
	_add_segment(start, ramp_time, position, velocity, ramp_accel)
	position += direction * ramp_distance
	start += ramp_time
	_add_segment(start, cruise_time, position, direction * peak, 0.0)
	position += direction * peak * cruise_time
	start += cruise_time
	_add_segment(start, brake_time_2, position, direction * peak, -direction * accel)


# [position, velocity, acceleration] at `time`.
func sample(time: float) -> PackedFloat64Array:
	for segment in _segments:
		var segment_start := segment[0]
		var duration := segment[1]
		if time < segment_start + duration:
			var dt := maxf(time - segment_start, 0.0)
			var accel := segment[4]
			return PackedFloat64Array([
				segment[2] + segment[3] * dt + 0.5 * accel * dt * dt,
				segment[3] + accel * dt,
				accel])
	return PackedFloat64Array([_end_position, 0.0, 0.0])


func _add_segment(start: float, duration: float, position: float, velocity: float,
		acceleration: float) -> void:
	if duration > 0.0:
		_segments.append(PackedFloat64Array([start, duration, position, velocity, acceleration]))
