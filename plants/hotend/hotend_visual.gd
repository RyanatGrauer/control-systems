# hotend_visual.gd
#
# PURPOSE
#   3D view of plant #2: an aluminium heater block with a nozzle, a heater
#   cartridge, and a thermometer column beside it.
#     - The block glows from grey to orange-red as it heats (colour = temperature).
#     - The heater cartridge glows with the APPLIED power (yellow = input colour),
#       so students can see that the heater is on BEFORE the temperature moves
#       (that gap is the dead time).
#     - The thermometer's blue column is the true temperature, and the orange
#       marker is the target.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
extends PlantVisual3D

# TUNABLE: layout (metres) and colour scale.
const BLOCK_SIZE: Vector3 = Vector3(0.5, 0.36, 0.36)
const BLOCK_CENTER: Vector3 = Vector3(-0.25, 0.75, 0.0)
const THERMOMETER_X: float = 0.45
const THERMOMETER_BOTTOM: float = 0.2
const THERMOMETER_HEIGHT: float = 1.0
const GLOW_FULL_AT_C: float = 280.0   # block colour is fully "hot" here
const COLD_COLOR: Color = Color(0.62, 0.64, 0.68)
const HOT_COLOR: Color = Color(1.0, 0.32, 0.08)

var _block_material: StandardMaterial3D
var _cartridge_material: StandardMaterial3D
var _column: MeshInstance3D
var _target_marker: MeshInstance3D
var _temperature_label: Label3D
var _power_label: Label3D
var _output_max: float = 300.0


func _ready() -> void:
	build_studio(Vector3(0.05, 0.7, 0.0), 2.3, 20.0, 12.0)
	_build_hotend()
	_build_thermometer()
	_temperature_label = add_label(Vector3(BLOCK_CENTER.x, 1.3, 0.0), 60, SignalColors.MEASUREMENT)
	_power_label = add_label(Vector3(BLOCK_CENTER.x, 1.12, 0.0), 36, SignalColors.APPLIED_INPUT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, _sim_time: float) -> void:
	var temperature := state[0]
	var output_info := plant.get_output_definition()
	var input_info := plant.get_input_definition()
	_output_max = output_info.max_value

	var heat_fraction := clampf(temperature / GLOW_FULL_AT_C, 0.0, 1.0)
	_block_material.albedo_color = COLD_COLOR.lerp(HOT_COLOR, heat_fraction)
	_block_material.emission = HOT_COLOR
	_block_material.emission_energy_multiplier = heat_fraction * heat_fraction * 1.5

	var power_fraction := clampf(applied_input / input_info.max_value, 0.0, 1.0)
	_cartridge_material.emission_energy_multiplier = power_fraction * 1.2

	var column_fraction := clampf(temperature / _output_max, 0.0, 1.0)
	_column.scale = Vector3(1.0, maxf(column_fraction, 0.001), 1.0)
	_target_marker.position.y = THERMOMETER_BOTTOM \
			+ clampf(setpoint / _output_max, 0.0, 1.0) * THERMOMETER_HEIGHT

	_temperature_label.text = "%d °C" % roundi(temperature)
	_power_label.text = "heater %s W" % String.num(maxf(applied_input, 0.0), 1).pad_decimals(1)


func _build_hotend() -> void:
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.3, 0.06, 0.6)
	apply_surface(add_mesh(self, base_mesh, Color(0.55, 0.56, 0.58), 0.0, 1.0), Surface.CONCRETE).position = Vector3(0.05, 0.03, 0.0)

	# Heat-break tube from above, holding the block in the air.
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.04
	tube_mesh.bottom_radius = 0.04
	tube_mesh.height = 0.5
	add_mesh(self, tube_mesh, Color(0.7, 0.72, 0.75), 0.8, 0.3).position = \
			BLOCK_CENTER + Vector3(0.0, BLOCK_SIZE.y * 0.5 + 0.25, 0.0)

	var block_mesh := BoxMesh.new()
	block_mesh.size = BLOCK_SIZE
	var block := add_mesh(self, block_mesh, COLD_COLOR, 0.6, 0.35)
	block.position = BLOCK_CENTER
	_block_material = block.material_override as StandardMaterial3D
	_block_material.emission_enabled = true

	# Nozzle: a brass cone under the block.
	var nozzle_mesh := CylinderMesh.new()
	nozzle_mesh.top_radius = 0.07
	nozzle_mesh.bottom_radius = 0.01
	nozzle_mesh.height = 0.16
	add_mesh(self, nozzle_mesh, Color(0.85, 0.65, 0.25), 0.9, 0.3).position = \
			BLOCK_CENTER - Vector3(0.0, BLOCK_SIZE.y * 0.5 + 0.08, 0.0)

	# Heater cartridge poking out of the front of the block.
	var cartridge_mesh := CylinderMesh.new()
	cartridge_mesh.top_radius = 0.045
	cartridge_mesh.bottom_radius = 0.045
	cartridge_mesh.height = 0.6
	var cartridge := add_mesh(self, cartridge_mesh, Color(0.35, 0.33, 0.30), 0.4, 0.5)
	cartridge.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	cartridge.position = BLOCK_CENTER + Vector3(0.0, -0.07, BLOCK_SIZE.z * 0.5 - 0.02)
	_cartridge_material = cartridge.material_override as StandardMaterial3D
	_cartridge_material.emission_enabled = true
	_cartridge_material.emission = SignalColors.APPLIED_INPUT
	_cartridge_material.emission_energy_multiplier = 0.0


func _build_thermometer() -> void:
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(0.1, THERMOMETER_HEIGHT, 0.06)
	var glass := add_mesh(self, glass_mesh, Color(0.16, 0.17, 0.20), 0.0, 0.8)
	glass.position = Vector3(THERMOMETER_X, THERMOMETER_BOTTOM + THERMOMETER_HEIGHT * 0.5, -0.01)

	# The column grows upward from the bottom: the mesh is offset so scaling
	# its parent in y stretches it from the base.
	_column = MeshInstance3D.new()
	_column.position = Vector3(THERMOMETER_X, THERMOMETER_BOTTOM, 0.03)
	add_child(_column)
	var column_mesh := BoxMesh.new()
	column_mesh.size = Vector3(0.05, THERMOMETER_HEIGHT, 0.02)
	add_mesh(_column, column_mesh, SignalColors.MEASUREMENT, 0.0, 0.5).position = \
			Vector3(0.0, THERMOMETER_HEIGHT * 0.5, 0.0)

	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.2, 0.018, 0.03)
	_target_marker = add_mesh(self, marker_mesh, SignalColors.SETPOINT)
	_target_marker.position = Vector3(THERMOMETER_X, THERMOMETER_BOTTOM, 0.05)

	# Scale labels every 100 °C (the plot's range is 0 ... 300 °C).
	for degrees in [0, 100, 200, 300]:
		var label := add_label(Vector3(THERMOMETER_X + 0.2,
				THERMOMETER_BOTTOM + degrees / 300.0 * THERMOMETER_HEIGHT, 0.0),
				28, Color(0.80, 0.82, 0.86))
		label.text = "%d" % degrees
	add_label(Vector3(THERMOMETER_X, THERMOMETER_BOTTOM + THERMOMETER_HEIGHT + 0.08, 0.0),
			28, Color(0.80, 0.82, 0.86)).text = "°C"


# --- sound: a soft hiss that grows with heater power ---
func get_sound_loop() -> AudioStream:
	return SoundBank.HEATER_HISS


func get_sound_level(plant: Plant, _state: PackedFloat64Array, applied_input: float) -> Vector2:
	return Vector2(1.0, 0.5 * clampf(applied_input / plant.get_input_definition().max_value, 0.0, 1.0))
