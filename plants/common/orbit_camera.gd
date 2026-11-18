# orbit_camera.gd
#
# PURPOSE
#   A camera that circles a target point. Students can drag to orbit and use the
#   mouse wheel to zoom; "Reset camera" returns to the plant's default framing.
#   The camera never moves unless the user asks (good for projection, README 4.4).
#
# HOW IT FITS
#   PlantVisual3D.build_studio() creates one. ui/plant_view.gd calls orbit(),
#   zoom() and reset_view() in response to mouse input on the plant view.
class_name OrbitCamera
extends Camera3D

# TUNABLE: camera control feel and limits.
const ORBIT_DEGREES_PER_PIXEL: float = 0.3
const ZOOM_FACTOR_PER_WHEEL_STEP: float = 1.1
const MIN_PITCH_DEGREES: float = -5.0
const MAX_PITCH_DEGREES: float = 80.0
const MIN_DISTANCE_FACTOR: float = 0.4  # relative to the default distance
const MAX_DISTANCE_FACTOR: float = 3.0

var target: Vector3 = Vector3.ZERO
var distance: float = 3.0
var yaw_degrees: float = 0.0    # rotation around the vertical axis
var pitch_degrees: float = 20.0 # positive = looking down from above

var _default_target: Vector3 = Vector3.ZERO
var _default_distance: float = 3.0
var _default_yaw_degrees: float = 0.0
var _default_pitch_degrees: float = 20.0


func configure_default_view(new_target: Vector3, new_distance: float,
		new_yaw_degrees: float, new_pitch_degrees: float) -> void:
	_default_target = new_target
	_default_distance = new_distance
	_default_yaw_degrees = new_yaw_degrees
	_default_pitch_degrees = new_pitch_degrees
	fov = 40.0
	reset_view()


func reset_view() -> void:
	target = _default_target
	distance = _default_distance
	yaw_degrees = _default_yaw_degrees
	pitch_degrees = _default_pitch_degrees
	_update_transform()


# Drag by `pixel_delta` (from mouse motion).
func orbit(pixel_delta: Vector2) -> void:
	yaw_degrees -= pixel_delta.x * ORBIT_DEGREES_PER_PIXEL
	pitch_degrees = clampf(pitch_degrees + pixel_delta.y * ORBIT_DEGREES_PER_PIXEL,
			MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)
	_update_transform()


# steps > 0 zooms in, steps < 0 zooms out.
func zoom(steps: float) -> void:
	distance = distance / pow(ZOOM_FACTOR_PER_WHEEL_STEP, steps)
	distance = clampf(distance, _default_distance * MIN_DISTANCE_FACTOR,
			_default_distance * MAX_DISTANCE_FACTOR)
	_update_transform()


func _update_transform() -> void:
	# Spherical coordinates around the target: yaw around Y, pitch above the floor.
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)) * distance
	position = target + offset
	# look_at needs the node in the tree for a correct global transform, so we
	# build the basis directly instead (works before and after add_child).
	transform = Transform3D(Basis.looking_at(target - position, Vector3.UP), position)
