# elevator_visual.gd
#
# PURPOSE
#   3D view of plant #5: a carriage on two vertical rails, hung from a cable
#   wound on a motor drum at the top. A translucent orange ghost carriage marks
#   the target height, and a ruler shows height in cm. The drum (with a yellow
#   stripe) turns as cable winds in, and red hard stops mark both ends of
#   the rail.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
extends PlantVisual3D

# TUNABLE: layout (metres). Height 0 is the carriage resting on the bottom stop.
const BASE_Y: float = 0.12              # world y of the carriage centre at height 0
const CARRIAGE_SIZE: Vector3 = Vector3(0.36, 0.2, 0.2)
const RAIL_SPACING: float = 0.5
const TOP_Y: float = BASE_Y + ElevatorPlant.RAIL_HEIGHT + 0.25

var _carriage: MeshInstance3D
var _ghost: MeshInstance3D
var _cable: MeshInstance3D
var _drum: MeshInstance3D
var _height_label: Label3D
var _voltage_label: Label3D
var _drum_angle: float = 0.0
var _last_height: float = 0.0


func _ready() -> void:
	build_studio(Vector3(0.1, 0.95, 0.0), 2.6, 18.0, 6.0)
	_build_frame()

	var carriage_mesh := BoxMesh.new()
	carriage_mesh.size = CARRIAGE_SIZE
	_carriage = add_mesh(self, carriage_mesh, SignalColors.MEASUREMENT, 0.2, 0.5)
	_ghost = add_mesh(self, carriage_mesh, Color.WHITE)
	_ghost.material_override = make_ghost_material()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.006
	cable_mesh.bottom_radius = 0.006
	cable_mesh.height = 1.0
	_cable = add_mesh(self, cable_mesh, Color(0.85, 0.85, 0.85), 0.6, 0.4)

	_height_label = add_label(Vector3(-0.55, 0.0, 0.0), 48, SignalColors.MEASUREMENT)
	_voltage_label = add_label(Vector3(0.0, TOP_Y + 0.2, 0.0), 34, SignalColors.APPLIED_INPUT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, _sim_time: float) -> void:
	var height := state[0]
	var carriage_y := BASE_Y + height
	_carriage.position = Vector3(0.0, carriage_y, 0.0)
	_ghost.position = Vector3(0.0, BASE_Y + clampf(setpoint, 0.0, ElevatorPlant.RAIL_HEIGHT), 0.0)

	# Cable from the drum down to the top of the carriage.
	var cable_top := TOP_Y - 0.08
	var cable_bottom := carriage_y + CARRIAGE_SIZE.y * 0.5
	_cable.scale = Vector3(1.0, maxf(cable_top - cable_bottom, 0.001), 1.0)
	_cable.position = Vector3(0.0, (cable_top + cable_bottom) * 0.5, 0.0)

	# Drum turns as cable is wound in (radius 0.08 m).
	_drum_angle += (height - _last_height) / 0.08
	_last_height = height
	_drum.rotation = Vector3(0.0, -_drum_angle, 0.0)  # about the drum's axis

	var output_info := plant.get_output_definition()
	_height_label.position.y = carriage_y
	_height_label.text = "%s cm" % String.num(output_info.si_to_shown(height), 1).pad_decimals(1)
	_voltage_label.text = "motor %s V" % String.num(applied_input, 1).pad_decimals(1)
	track_hard_stop(height <= 0.0005 or height >= ElevatorPlant.RAIL_HEIGHT - 0.0005,
			state[1], SOUND_FULL_SPEED)


func reset_visual() -> void:
	_drum_angle = 0.0
	_last_height = 0.0


func _build_frame() -> void:
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.0, 0.04, 0.5)
	apply_surface(add_mesh(self, base_mesh, Color(0.55, 0.56, 0.58), 0.0, 1.0), Surface.CONCRETE).position = Vector3(0.0, -0.02, 0.0)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.04, TOP_Y, 0.04)
	for side in [-1.0, 1.0]:
		add_mesh(self, rail_mesh, Color(0.55, 0.57, 0.60), 0.7, 0.4).position = \
				Vector3(side * RAIL_SPACING * 0.5, TOP_Y * 0.5, -0.1)

	var top_bar_mesh := BoxMesh.new()
	top_bar_mesh.size = Vector3(RAIL_SPACING + 0.1, 0.05, 0.08)
	add_mesh(self, top_bar_mesh, Color(0.45, 0.47, 0.50), 0.6, 0.4).position = \
			Vector3(0.0, TOP_Y, -0.1)

	# Motor drum (with a stripe so its rotation is visible). CylinderMesh's
	# axis is y, so a holder turns it to face the camera; show_state() then
	# spins the drum about its own axis.
	var drum_holder := Node3D.new()
	drum_holder.position = Vector3(0.0, TOP_Y, 0.0)
	drum_holder.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(drum_holder)
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.08
	drum_mesh.bottom_radius = 0.08
	drum_mesh.height = 0.12
	_drum = add_mesh(drum_holder, drum_mesh, Color(0.22, 0.23, 0.26), 0.5, 0.4)
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.14, 0.13, 0.015)
	add_mesh(_drum, stripe_mesh, SignalColors.APPLIED_INPUT, 0.0, 0.6)

	# Hard stops: red blocks at the bottom and top of the travel.
	var stop_mesh := BoxMesh.new()
	stop_mesh.size = Vector3(0.1, 0.03, 0.1)
	for side in [-1.0, 1.0]:
		add_mesh(self, stop_mesh, Color(0.8, 0.2, 0.2)).position = Vector3(
				side * RAIL_SPACING * 0.5, BASE_Y - CARRIAGE_SIZE.y * 0.5 - 0.015, -0.1)
		add_mesh(self, stop_mesh, Color(0.8, 0.2, 0.2)).position = Vector3(
				side * RAIL_SPACING * 0.5,
				BASE_Y + ElevatorPlant.RAIL_HEIGHT + CARRIAGE_SIZE.y * 0.5 + 0.015, -0.1)

	# Ruler on the right: a tick every 25 cm, labelled every 50 cm.
	for step in range(0, 7):
		var height := step * 0.25
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.06 if step % 2 == 0 else 0.035, 0.008, 0.01)
		add_mesh(self, tick_mesh, Color(0.85, 0.87, 0.90)).position = \
				Vector3(RAIL_SPACING * 0.5 + 0.08, BASE_Y + height, 0.0)
		if step % 2 == 0:
			add_label(Vector3(RAIL_SPACING * 0.5 + 0.2, BASE_Y + height, 0.0), 28,
					Color(0.80, 0.82, 0.86)).text = "%d" % roundi(height * 100.0)
	add_label(Vector3(RAIL_SPACING * 0.5 + 0.2, BASE_Y + ElevatorPlant.RAIL_HEIGHT + 0.12, 0.0),
			28, Color(0.80, 0.82, 0.86)).text = "cm"


# --- sound: the winch hums while it works, the carriage clunks on the stops ---
const SOUND_FULL_SPEED: float = 0.8  # TUNABLE: m/s for the highest pitch / loudest clunk


func get_sound_loop() -> AudioStream:
	return SoundBank.WINCH_LOOP


func get_sound_level(plant: Plant, state: PackedFloat64Array, applied_input: float) -> Vector2:
	var speed := clampf(absf(state[1]) / SOUND_FULL_SPEED, 0.0, 1.0)
	return Vector2(0.7 + 0.8 * speed,
			clampf(1.2 * speed + 0.45 * effort_fraction(plant, applied_input), 0.0, 1.0))
