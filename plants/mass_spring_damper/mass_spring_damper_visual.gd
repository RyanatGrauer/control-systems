# mass_spring_damper_visual.gd
#
# PURPOSE
#   3D view of plant #3: a wall, a coil spring and a damper (dashpot) holding a
#   block that slides along the floor. Shows:
#     - the spring stretching and squashing with the block,
#     - a yellow arrow on the block for the applied force, labelled in newtons
#       (it always starts at a visible length so small pushes still show),
#     - a translucent orange "ghost" block at the setpoint, plus an orange
#       marker post on the ruler under it,
#     - a ruler on the floor in centimetres.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
#   Scene units are metres, so the block moves exactly as far as the physics says.
extends PlantVisual3D

# TUNABLE: layout of the scene (metres).
const WALL_FACE_X: float = -0.95     # where the spring and damper attach
const BLOCK_SIZE: float = 0.3
const SPRING_HEIGHT: float = 0.21
const DAMPER_HEIGHT: float = 0.08
const ARROW_HEIGHT: float = 0.36           # just above the block's top face
const ARROW_MIN_LENGTH: float = 0.12       # length of the smallest visible push
const ARROW_LENGTH_AT_MAX_FORCE: float = 0.7
const RULER_HALF_RANGE_CM: int = 40

var _block: MeshInstance3D
var _ghost: MeshInstance3D
var _spring: MeshInstance3D
var _damper_rod: MeshInstance3D
var _force_arrow: Node3D
var _position_label: Label3D
var _force_label: Label3D
var _target_marker: MeshInstance3D


func _ready() -> void:
	build_studio(Vector3(-0.25, 0.22, 0.0), 1.9, 12.0, 20.0)
	_build_wall()
	_build_ruler()
	_build_moving_parts()
	_position_label = add_label(Vector3(0.0, 0.64, 0.0), 56, SignalColors.MEASUREMENT)
	_force_label = add_label(Vector3(0.0, 0.47, 0.0), 36, SignalColors.APPLIED_INPUT)
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.012, 0.1, 0.012)
	_target_marker = add_mesh(self, marker_mesh, SignalColors.SETPOINT)
	_target_marker.position = Vector3(0.0, 0.05, 0.26)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, _sim_time: float) -> void:
	var position_m := state[0]
	var block_left_face := position_m - BLOCK_SIZE * 0.5

	_block.position.x = position_m
	_ghost.position.x = setpoint
	_target_marker.position.x = setpoint

	# Spring and damper rod run from the wall to the block's left face.
	_spring.scale.x = maxf(block_left_face - WALL_FACE_X, 0.01)
	_damper_rod.position.x = block_left_face - 0.25

	# Force arrow: starts at the block's centre and points the way the force
	# pushes. Negative x-scale flips it to point left. Hidden when tiny.
	var input_info := plant.get_input_definition()
	var force_fraction := clampf(applied_input / input_info.max_value, -1.0, 1.0)
	_force_arrow.visible = absf(force_fraction) > 0.01
	var arrow_length := ARROW_MIN_LENGTH + absf(force_fraction) * (ARROW_LENGTH_AT_MAX_FORCE - ARROW_MIN_LENGTH)
	_force_arrow.position.x = position_m
	_force_arrow.scale = Vector3(signf(force_fraction) * arrow_length, 1.0, 1.0)
	_force_label.position.x = position_m + signf(force_fraction) * arrow_length * 0.5
	_force_label.text = "push %s %s" % [String.num(applied_input, 1).pad_decimals(1),
			input_info.get_shown_unit()]

	var output_info := plant.get_output_definition()
	_position_label.position.x = position_m
	_position_label.text = "x = %s %s" % [
		String.num(output_info.si_to_shown(position_m), 1).pad_decimals(1),
		output_info.get_shown_unit()]


func _build_wall() -> void:
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.1, 0.7, 0.6)
	apply_surface(add_mesh(self, wall_mesh, Color(0.6, 0.62, 0.66), 0.0, 1.0), Surface.CONCRETE).position = \
			Vector3(WALL_FACE_X - 0.05, 0.35, 0.0)

	# Damper body (the cylinder fixed to the wall).
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.035
	body_mesh.bottom_radius = 0.035
	body_mesh.height = 0.35
	var body := add_mesh(self, body_mesh, Color(0.20, 0.22, 0.26), 0.5, 0.4)
	body.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	body.position = Vector3(WALL_FACE_X + 0.175, DAMPER_HEIGHT, 0.0)


func _build_ruler() -> void:
	# A tick every 10 cm along the floor, numbered every 20 cm (upright
	# billboard numbers stay readable from any camera angle).
	var tick_mesh := BoxMesh.new()
	tick_mesh.size = Vector3(0.006, 0.004, 0.12)
	for centimetres in range(-RULER_HALF_RANGE_CM, RULER_HALF_RANGE_CM + 1, 10):
		var x := centimetres / 100.0
		add_mesh(self, tick_mesh, Color(0.75, 0.77, 0.80)).position = Vector3(x, 0.003, 0.26)
		if centimetres % 20 == 0:
			var label := add_label(Vector3(x, 0.05, 0.36), 28, Color(0.75, 0.77, 0.80))
			label.text = "%d" % centimetres
	var unit_label := add_label(Vector3((RULER_HALF_RANGE_CM + 12) / 100.0, 0.05, 0.36), 28,
			Color(0.75, 0.77, 0.80))
	unit_label.text = "cm"


func _build_moving_parts() -> void:
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3.ONE * BLOCK_SIZE
	_block = add_mesh(self, block_mesh, Color(0.35, 0.55, 0.80), 0.2, 0.5)
	_block.position = Vector3(0.0, BLOCK_SIZE * 0.5, 0.0)

	_ghost = MeshInstance3D.new()
	_ghost.mesh = block_mesh
	_ghost.material_override = make_ghost_material()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.position = Vector3(0.0, BLOCK_SIZE * 0.5, 0.0)
	add_child(_ghost)

	var spring_material := StandardMaterial3D.new()
	spring_material.albedo_color = Color(0.80, 0.82, 0.85)
	spring_material.metallic = 0.8
	spring_material.roughness = 0.3
	spring_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # either winding shows
	_spring = MeshInstance3D.new()
	_spring.mesh = MeshBuilders.build_spring_mesh(10.0, 0.05, 0.008)
	_spring.material_override = spring_material
	_spring.position = Vector3(WALL_FACE_X, SPRING_HEIGHT, 0.0)
	add_child(_spring)

	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.012
	rod_mesh.bottom_radius = 0.012
	rod_mesh.height = 0.5
	_damper_rod = add_mesh(self, rod_mesh, Color(0.75, 0.77, 0.80), 0.9, 0.25)
	_damper_rod.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	_damper_rod.position = Vector3(0.0, DAMPER_HEIGHT, 0.0)

	_force_arrow = MeshBuilders.build_arrow(SignalColors.APPLIED_INPUT, 0.025, 0.06)
	_force_arrow.position = Vector3(0.0, ARROW_HEIGHT, 0.0)
	add_child(_force_arrow)


# --- sound: the actuator motor whines with the force it pushes ---
const SOUND_FULL_SPEED: float = 1.0  # TUNABLE: m/s for the highest pitch


func get_sound_loop() -> AudioStream:
	return SoundBank.MOTOR_WHINE


func get_sound_level(plant: Plant, state: PackedFloat64Array, applied_input: float) -> Vector2:
	var speed := clampf(absf(state[1]) / SOUND_FULL_SPEED, 0.0, 1.0)
	return Vector2(0.8 + 0.6 * speed, clampf(0.7 * effort_fraction(plant, applied_input), 0.0, 1.0))
