# drone_visual.gd
#
# PURPOSE
#   3D view of plant #8: a quadcopter above a landing pad, moving only up
#   and down. Its rotors spin faster with more thrust, and a yellow arrow
#   under it shows the thrust (labelled in newtons). A translucent orange
#   ghost drone hovers at the target height; a pole with marks every metre
#   reads the height.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
extends PlantVisual3D

# TUNABLE: layout. Heights are drawn at 0.3 world units per metre so the
# whole 0-8 m range fits on screen.
const METRES_TO_WORLD: float = 0.3
const BASE_Y: float = 0.08
const ROTOR_OFFSET: float = 0.2
const MAX_ROTOR_SPEED: float = 60.0  # rad/s of the drawn rotors at full thrust

var _drone: Node3D
var _ghost: Node3D
var _rotors: Array[MeshInstance3D] = []
var _thrust_arrow: Node3D
var _height_label: Label3D
var _thrust_label: Label3D
var _rotor_angle: float = 0.0
var _last_time: float = 0.0


func _ready() -> void:
	build_studio(Vector3(0.0, 1.25, 0.0), 3.6, 15.0, 6.0)
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.4
	pad_mesh.bottom_radius = 0.4
	pad_mesh.height = 0.03
	apply_surface(add_mesh(self, pad_mesh, Color(0.6, 0.62, 0.66), 0.0, 1.0), Surface.CONCRETE).position = Vector3(0.0, 0.015, 0.0)
	_build_height_pole()

	_drone = _build_drone(false)
	_ghost = _build_drone(true)
	_thrust_arrow = MeshBuilders.build_arrow(SignalColors.APPLIED_INPUT, 0.02, 0.05)
	_thrust_arrow.rotation_degrees = Vector3(0.0, 0.0, 90.0)  # +x -> up
	add_child(_thrust_arrow)
	_height_label = add_label(Vector3(0.6, 0.0, 0.0), 56, SignalColors.MEASUREMENT)
	_thrust_label = add_label(Vector3(0.6, 0.0, 0.0), 36, SignalColors.APPLIED_INPUT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, sim_time: float) -> void:
	var drone_y := BASE_Y + state[0] * METRES_TO_WORLD
	_drone.position = Vector3(0.0, drone_y, 0.0)
	_ghost.position = Vector3(0.0, BASE_Y + clampf(setpoint, 0.0, DronePlant.CEILING) * METRES_TO_WORLD, 0.0)

	var input_info := plant.get_input_definition()
	var thrust_fraction := clampf(applied_input / input_info.max_value, 0.0, 1.0)
	var dt := clampf(sim_time - _last_time, 0.0, 0.1)
	_last_time = sim_time
	_rotor_angle += thrust_fraction * MAX_ROTOR_SPEED * dt
	for index in _rotors.size():
		_rotors[index].rotation = Vector3(0.0, _rotor_angle * (1.0 if index % 2 == 0 else -1.0), 0.0)

	# Thrust arrow points up from under the drone; length grows with thrust.
	_thrust_arrow.visible = thrust_fraction > 0.01
	_thrust_arrow.position = Vector3(0.0, drone_y - 0.05 - 0.45 * thrust_fraction, 0.0)
	_thrust_arrow.scale = Vector3(0.45 * thrust_fraction, 1.0, 1.0)
	_height_label.position.y = drone_y + 0.12
	_height_label.text = "%s m" % String.num(state[0], 2).pad_decimals(2)
	_thrust_label.position.y = drone_y - 0.02
	_thrust_label.text = "thrust %s N" % String.num(applied_input, 1).pad_decimals(1)
	track_hard_stop(state[0] <= 0.0005 or state[0] >= DronePlant.CEILING - 0.0005,
			state[1], SOUND_FULL_IMPACT_SPEED)


func reset_visual() -> void:
	_last_time = 0.0


func _build_drone(is_ghost: bool) -> Node3D:
	var drone := Node3D.new()
	add_child(drone)
	var parts: Array[MeshInstance3D] = []
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.16, 0.06, 0.16)
	parts.append(add_mesh(drone, body_mesh, SignalColors.MEASUREMENT, 0.3, 0.4))
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(ROTOR_OFFSET * 2.0 * 1.414, 0.02, 0.025)
	for angle in [45.0, -45.0]:
		var arm := add_mesh(drone, arm_mesh, Color(0.3, 0.32, 0.36), 0.4, 0.5)
		arm.rotation_degrees = Vector3(0.0, angle, 0.0)
		parts.append(arm)
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 0.09
	rotor_mesh.bottom_radius = 0.09
	rotor_mesh.height = 0.008
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.17, 0.012, 0.025)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var rotor := add_mesh(drone, rotor_mesh, Color(0.5, 0.52, 0.56, 0.35), 0.0, 0.5)
			rotor.position = Vector3(x * ROTOR_OFFSET, 0.04, z * ROTOR_OFFSET)
			parts.append(rotor)
			if not is_ghost:
				(rotor.material_override as StandardMaterial3D).transparency = \
						BaseMaterial3D.TRANSPARENCY_ALPHA
				add_mesh(rotor, blade_mesh, Color(0.85, 0.85, 0.88))
				_rotors.append(rotor)
	if is_ghost:
		var ghost_material := make_ghost_material()
		for part in parts:
			part.material_override = ghost_material
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return drone


func _build_height_pole() -> void:
	var pole_x := -0.75
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.03, DronePlant.CEILING * METRES_TO_WORLD + 0.1, 0.03)
	add_mesh(self, pole_mesh, Color(0.55, 0.57, 0.60), 0.5, 0.5).position = \
			Vector3(pole_x, BASE_Y + DronePlant.CEILING * METRES_TO_WORLD * 0.5, -0.2)
	for metres in range(0, int(DronePlant.CEILING) + 1):
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.1, 0.008, 0.01)
		add_mesh(self, tick_mesh, Color(0.85, 0.87, 0.90)).position = \
				Vector3(pole_x + 0.05, BASE_Y + metres * METRES_TO_WORLD, -0.2)
		if metres % 2 == 0:
			add_label(Vector3(pole_x - 0.12, BASE_Y + metres * METRES_TO_WORLD, -0.2), 28,
					Color(0.80, 0.82, 0.86)).text = "%d m" % metres
	# Ceiling (hard stop).
	var ceiling_mesh := BoxMesh.new()
	ceiling_mesh.size = Vector3(1.2, 0.02, 0.5)
	add_mesh(self, ceiling_mesh, Color(0.8, 0.2, 0.2, 0.6)).position = \
			Vector3(0.0, BASE_Y + DronePlant.CEILING * METRES_TO_WORLD + 0.06, 0.0)


# --- sound: rotor buzz rises with thrust; a clunk on landing / the ceiling ---
const SOUND_FULL_IMPACT_SPEED: float = 3.0  # TUNABLE: m/s for the loudest clunk


func get_sound_loop() -> AudioStream:
	return SoundBank.PROPELLER_LOOP


func get_sound_level(plant: Plant, _state: PackedFloat64Array, applied_input: float) -> Vector2:
	var thrust := sqrt(clampf(applied_input / plant.get_input_definition().max_value, 0.0, 1.0))
	return Vector2(0.6 + 0.8 * thrust, thrust)
