# servo_visual.gd
#
# PURPOSE
#   3D view of plant #4: a motor housing with a dial face. A pointer arm shows
#   the angle, and a translucent orange ghost arm shows the setpoint.
#   0 degrees points right; positive angles turn counter-clockwise (the maths
#   convention), as seen from the default camera.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
extends PlantVisual3D

# TUNABLE: layout (metres).
const DIAL_CENTER: Vector3 = Vector3(0.0, 0.55, 0.16)
const DIAL_RADIUS: float = 0.36
const ARM_LENGTH: float = 0.33

var _arm_pivot: Node3D
var _ghost_pivot: Node3D
var _angle_label: Label3D


func _ready() -> void:
	build_studio(Vector3(0.0, 0.62, 0.0), 1.85, 8.0, 10.0)
	_build_housing_and_dial()
	# The real arm uses the measurement colour; the ghost uses the setpoint's.
	_arm_pivot = _build_arm(SignalColors.MEASUREMENT, null, 0.03)
	_ghost_pivot = _build_arm(Color.WHITE, make_ghost_material(), 0.02)
	_angle_label = add_label(Vector3(0.0, 1.12, 0.0), 64, SignalColors.MEASUREMENT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		_applied_input: float, _sim_time: float) -> void:
	_arm_pivot.rotation.z = state[0]
	_ghost_pivot.rotation.z = setpoint
	var output_info := plant.get_output_definition()
	_angle_label.text = "%s°" % String.num(output_info.si_to_shown(state[0]), 1).pad_decimals(1)


func _build_housing_and_dial() -> void:
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.0, 0.06, 0.6)
	apply_surface(add_mesh(self, base_mesh, Color(0.55, 0.56, 0.58), 0.0, 1.0), Surface.CONCRETE).position = Vector3(0.0, 0.03, 0.0)

	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.86, 0.86, 0.26)
	add_mesh(self, housing_mesh, Color(0.18, 0.19, 0.22), 0.5, 0.45).position = \
			Vector3(0.0, DIAL_CENTER.y, 0.0)

	# Dial face: a flat disc facing the camera (+Z).
	var dial_mesh := CylinderMesh.new()
	dial_mesh.top_radius = DIAL_RADIUS
	dial_mesh.bottom_radius = DIAL_RADIUS
	dial_mesh.height = 0.02
	dial_mesh.radial_segments = 64
	# Dark face so both the blue arm and the translucent orange ghost stand out.
	var dial := add_mesh(self, dial_mesh, Color(0.20, 0.21, 0.24), 0.0, 0.8)
	dial.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	dial.position = DIAL_CENTER - Vector3(0.0, 0.0, 0.02)

	# Tick marks every 30 degrees; longer ones every 90 degrees, with labels.
	for degrees in range(0, 360, 30):
		var is_major := degrees % 90 == 0
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.07 if is_major else 0.04, 0.012, 0.01)
		var angle := deg_to_rad(degrees)
		var radius := DIAL_RADIUS - tick_mesh.size.x * 0.5 - 0.01
		var tick := add_mesh(self, tick_mesh, Color(0.85, 0.87, 0.90))
		tick.position = DIAL_CENTER + Vector3(cos(angle), sin(angle), 0.0) * radius
		tick.rotation.z = angle
		if is_major:
			var label := add_label(DIAL_CENTER + Vector3(cos(angle), sin(angle), 0.02)
					* (DIAL_RADIUS + 0.09), 30, Color(0.80, 0.82, 0.86))
			# Show -90 instead of 270 to match the plot's -180..180 range.
			label.text = "%d°" % (degrees if degrees <= 180 else degrees - 360)


# A pointer arm on its own pivot; rotate the pivot's z to set the angle.
func _build_arm(color: Color, material_override: Material, z_offset: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = DIAL_CENTER + Vector3(0.0, 0.0, z_offset)
	add_child(pivot)

	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(ARM_LENGTH, 0.035, 0.02)
	var arm := add_mesh(pivot, arm_mesh, color, 0.2, 0.5)
	arm.position = Vector3(ARM_LENGTH * 0.5, 0.0, 0.0)
	if material_override != null:
		arm.material_override = material_override
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = 0.04
		hub_mesh.bottom_radius = 0.04
		hub_mesh.height = 0.04
		var hub := add_mesh(pivot, hub_mesh, Color(0.15, 0.15, 0.17), 0.6, 0.4)
		hub.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	return pivot


# --- sound: motor whine while the arm moves or the motor strains ---
const SOUND_FULL_SPEED: float = 15.0  # TUNABLE: rad/s for the highest pitch


func get_sound_loop() -> AudioStream:
	return SoundBank.MOTOR_WHINE


func get_sound_level(plant: Plant, state: PackedFloat64Array, applied_input: float) -> Vector2:
	var speed := clampf(absf(state[1]) / SOUND_FULL_SPEED, 0.0, 1.0)
	return Vector2(0.6 + 1.2 * speed,
			clampf(1.5 * speed + 0.3 * effort_fraction(plant, applied_input), 0.0, 1.0))
