# flywheel_visual.gd
#
# PURPOSE
#   3D view of plant #1: a DC motor on a stand spinning a steel flywheel, with a
#   floating speed readout. Built entirely from Godot primitive meshes (no
#   downloaded assets, README 4.4).
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd from flywheel_visual.tscn. show_state() is called
#   every frame with the current simulation state. This script only DISPLAYS the
#   state; it never changes the physics.
#
# ANIMATION NOTES
#   - The physics state is only the wheel's speed. To draw it turning we add up
#     angle += speed * (change in SIMULATED time), so pausing freezes the wheel
#     and slow-motion slows it.
#   - Above a few revolutions per second the spokes would strobe ("wagon-wheel
#     effect") because the screen only updates ~60 times a second. A translucent
#     "blur disc" fades in with speed to show motion blur instead.
extends PlantVisual3D

# TUNABLE: look of the flywheel.
const WHEEL_CENTER: Vector3 = Vector3(0.08, 0.75, 0.0)
const WHEEL_RADIUS: float = 0.48
const WHEEL_THICKNESS: float = 0.06
const BLUR_START_SPEED: float = 25.0   # rad/s where blur starts to appear
const BLUR_FULL_SPEED: float = 250.0   # rad/s where blur is strongest
const BLUR_MAX_ALPHA: float = 0.8

var _spinner: Node3D                 # rotates about its local Y axis (the shaft)
var _blur_material: StandardMaterial3D
var _speed_label: Label3D
var _target_label: Label3D
var _wheel_angle: float = 0.0        # radians, display only
var _last_sim_time: float = 0.0


func _ready() -> void:
	build_studio(Vector3(-0.1, 0.8, 0.0), 2.5, 60.0, 14.0)
	_build_stand_and_motor()
	_build_wheel()
	_build_labels()


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		_applied_input: float, sim_time: float) -> void:
	var angular_velocity := state[0]

	var elapsed := sim_time - _last_sim_time
	if elapsed < 0.0:
		elapsed = 0.0  # time went backwards: the run was reset
	_last_sim_time = sim_time
	_wheel_angle = wrapf(_wheel_angle + angular_velocity * elapsed, 0.0, TAU)
	_spinner.rotation.y = _wheel_angle

	var blur := inverse_lerp(BLUR_START_SPEED, BLUR_FULL_SPEED, absf(angular_velocity))
	_blur_material.albedo_color.a = clampf(blur, 0.0, 1.0) * BLUR_MAX_ALPHA

	# Unit conversion happens here, at the display boundary.
	var output_info := plant.get_output_definition()
	_speed_label.text = "%d %s" % [roundi(output_info.si_to_shown(angular_velocity)),
			output_info.get_shown_unit()]
	_target_label.text = "target %d %s" % [roundi(output_info.si_to_shown(setpoint)),
			output_info.get_shown_unit()]


func reset_visual() -> void:
	_wheel_angle = 0.0
	_last_sim_time = 0.0
	if _spinner != null:
		_spinner.rotation.y = 0.0


func _build_stand_and_motor() -> void:
	var base_plate := BoxMesh.new()
	base_plate.size = Vector3(1.1, 0.04, 0.7)
	add_mesh(self, base_plate, Color(0.25, 0.27, 0.30), 0.3, 0.7).position = Vector3(-0.2, 0.02, 0.0)

	var stand := BoxMesh.new()
	stand.size = Vector3(0.34, 0.56, 0.3)
	add_mesh(self, stand, Color(0.30, 0.32, 0.36), 0.2, 0.6).position = Vector3(-0.45, 0.32, 0.0)

	# Motor body: a cylinder lying along the X axis (the shaft direction).
	var motor_body := CylinderMesh.new()
	motor_body.top_radius = 0.16
	motor_body.bottom_radius = 0.16
	motor_body.height = 0.46
	var motor := add_mesh(self, motor_body, Color(0.18, 0.19, 0.22), 0.6, 0.4)
	motor.position = Vector3(-0.45, WHEEL_CENTER.y, 0.0)
	motor.rotation_degrees = Vector3(0.0, 0.0, 90.0)

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.022
	shaft_mesh.bottom_radius = 0.022
	shaft_mesh.height = 0.36
	var shaft := add_mesh(self, shaft_mesh, Color(0.75, 0.77, 0.80), 0.9, 0.25)
	shaft.position = Vector3(-0.08, WHEEL_CENTER.y, 0.0)
	shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)


func _build_wheel() -> void:
	# The mount turns the wheel so its local Y axis points along world +X.
	var mount := Node3D.new()
	mount.position = WHEEL_CENTER
	mount.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	add_child(mount)

	_spinner = Node3D.new()
	mount.add_child(_spinner)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = WHEEL_RADIUS
	disc_mesh.bottom_radius = WHEEL_RADIUS
	disc_mesh.height = WHEEL_THICKNESS
	disc_mesh.radial_segments = 48
	add_mesh(_spinner, disc_mesh, Color(0.62, 0.65, 0.70), 0.7, 0.35)

	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = WHEEL_RADIUS - 0.04
	rim_mesh.outer_radius = WHEEL_RADIUS + 0.04
	rim_mesh.rings = 48
	add_mesh(_spinner, rim_mesh, Color(0.22, 0.24, 0.28), 0.6, 0.4)

	# Five dark "lightening holes" so rotation is easy to see at low speed.
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = 0.07
	hole_mesh.bottom_radius = 0.07
	hole_mesh.height = WHEEL_THICKNESS + 0.006
	for hole_index in 5:
		var angle := TAU * (hole_index + 0.5) / 5.0
		var hole := add_mesh(_spinner, hole_mesh, Color(0.07, 0.07, 0.09), 0.0, 0.9)
		hole.position = Vector3(cos(angle), 0.0, sin(angle)) * 0.28

	# One bright radial stripe: the "which way is it turning" marker.
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.30, WHEEL_THICKNESS + 0.01, 0.045)
	var stripe := add_mesh(_spinner, stripe_mesh, SignalColors.APPLIED_INPUT, 0.0, 0.5)
	stripe.position = Vector3(0.27, 0.0, 0.0)

	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.07
	hub_mesh.bottom_radius = 0.07
	hub_mesh.height = WHEEL_THICKNESS + 0.06
	add_mesh(_spinner, hub_mesh, Color(0.15, 0.16, 0.18), 0.6, 0.4)

	# Motion-blur disc: does NOT spin; fades in with speed (see header).
	var blur_mesh := CylinderMesh.new()
	blur_mesh.top_radius = WHEEL_RADIUS + 0.05
	blur_mesh.bottom_radius = WHEEL_RADIUS + 0.05
	blur_mesh.height = WHEEL_THICKNESS + 0.02
	blur_mesh.radial_segments = 48
	_blur_material = StandardMaterial3D.new()
	_blur_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blur_material.albedo_color = Color(0.55, 0.58, 0.63, 0.0)
	_blur_material.roughness = 0.5
	var blur_disc := MeshInstance3D.new()
	blur_disc.mesh = blur_mesh
	blur_disc.material_override = _blur_material
	blur_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blur_disc.visible = DisplaySettings.motion_blur  # Graphics setting
	mount.add_child(blur_disc)


func _build_labels() -> void:
	_speed_label = add_label(Vector3(WHEEL_CENTER.x, 1.48, 0.0), 80, SignalColors.MEASUREMENT)
	_target_label = add_label(Vector3(WHEEL_CENTER.x, 1.34, 0.0), 48, SignalColors.SETPOINT)
