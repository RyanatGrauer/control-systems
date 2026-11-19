# arm_visual.gd
#
# PURPOSE
#   3D view of plant #6: an arm on a post, seen from the side, swinging in a
#   vertical plane with a weight at its tip. A translucent orange ghost arm
#   shows the target angle; angle marks (-90°, 0°, 90°, 180°) ring the pivot;
#   a red arrow under the weight shows gravity, and the yellow label the
#   motor voltage. Red blocks mark the hard stops.
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. Display only.
extends PlantVisual3D

# TUNABLE: layout (metres). The drawn arm length follows the plant's
# length parameter, scaled so the default 0.4 m looks like 0.6 m on screen.
const PIVOT: Vector3 = Vector3(0.0, 1.0, 0.0)
const DRAW_SCALE: float = 1.5
const MARK_RADIUS: float = 0.74

var _arm_pivot: Node3D
var _ghost_pivot: Node3D
var _rod: MeshInstance3D
var _ghost_rod: MeshInstance3D
var _weight: MeshInstance3D
var _ghost_weight: MeshInstance3D
var _gravity_arrow: Node3D
var _angle_label: Label3D
var _voltage_label: Label3D
var _drawn_length: float = -1.0


func _ready() -> void:
	build_studio(PIVOT, 2.8, 0.0, 4.0)
	_build_stand()

	_arm_pivot = Node3D.new()
	_arm_pivot.position = PIVOT + Vector3(0.0, 0.0, 0.08)
	add_child(_arm_pivot)
	_ghost_pivot = Node3D.new()
	_ghost_pivot.position = PIVOT + Vector3(0.0, 0.0, 0.04)
	add_child(_ghost_pivot)

	var rod_mesh := BoxMesh.new()
	rod_mesh.size = Vector3(1.0, 0.05, 0.04)
	_rod = add_mesh(_arm_pivot, rod_mesh, SignalColors.MEASUREMENT, 0.2, 0.5)
	_ghost_rod = add_mesh(_ghost_pivot, rod_mesh, Color.WHITE)
	_ghost_rod.material_override = make_ghost_material()
	var weight_mesh := SphereMesh.new()
	weight_mesh.radius = 0.07
	weight_mesh.height = 0.14
	_weight = add_mesh(_arm_pivot, weight_mesh, Color(0.25, 0.45, 0.7), 0.4, 0.4)
	_ghost_weight = add_mesh(_ghost_pivot, weight_mesh, Color.WHITE)
	_ghost_weight.material_override = make_ghost_material()
	for ghost_part in [_ghost_rod, _ghost_weight]:
		ghost_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Gravity: a short red arrow pointing down from the weight.
	_gravity_arrow = MeshBuilders.build_arrow(Color(0.9, 0.3, 0.3), 0.012, 0.035)
	_gravity_arrow.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	_gravity_arrow.scale = Vector3(0.22, 1.0, 1.0)
	add_child(_gravity_arrow)

	_angle_label = add_label(PIVOT + Vector3(-0.6, 0.45, 0.0), 64, SignalColors.MEASUREMENT)
	_voltage_label = add_label(PIVOT + Vector3(0.6, -0.45, 0.3), 40, SignalColors.APPLIED_INPUT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, _sim_time: float) -> void:
	var length := plant.get_parameter("length") * DRAW_SCALE
	if length != _drawn_length:
		_set_length(length)
	var angle := state[0]
	_arm_pivot.rotation = Vector3(0.0, 0.0, angle)
	_ghost_pivot.rotation = Vector3(0.0, 0.0, clampf(setpoint, ArmPlant.MIN_ANGLE, ArmPlant.MAX_ANGLE))
	var tip := _arm_pivot.position + Vector3(cos(angle), sin(angle), 0.0) * length
	_gravity_arrow.position = tip + Vector3(0.0, -0.08, 0.0)
	_angle_label.text = "%s°" % String.num(rad_to_deg(angle), 1).pad_decimals(1)
	_voltage_label.text = "motor %s V" % String.num(applied_input, 1).pad_decimals(1)


func _set_length(length: float) -> void:
	_drawn_length = length
	for rod in [_rod, _ghost_rod]:
		rod.scale = Vector3(length, 1.0, 1.0)
		rod.position = Vector3(length * 0.5, 0.0, 0.0)
	for weight in [_weight, _ghost_weight]:
		weight.position = Vector3(length, 0.0, 0.0)


func _build_stand() -> void:
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.6, 0.04, 0.4)
	add_mesh(self, base_mesh, Color(0.25, 0.27, 0.30), 0.3, 0.7).position = Vector3(0.0, 0.02, 0.0)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.08, PIVOT.y, 0.08)
	add_mesh(self, post_mesh, Color(0.55, 0.57, 0.60), 0.6, 0.4).position = Vector3(0.0, PIVOT.y * 0.5, -0.04)
	# Motor housing at the pivot (its axis points at the camera).
	var motor_holder := Node3D.new()
	motor_holder.position = PIVOT
	motor_holder.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(motor_holder)
	var motor_mesh := CylinderMesh.new()
	motor_mesh.top_radius = 0.07
	motor_mesh.bottom_radius = 0.07
	motor_mesh.height = 0.12
	add_mesh(motor_holder, motor_mesh, Color(0.22, 0.23, 0.26), 0.5, 0.4)

	# Angle marks around the pivot: a tick every 45°, labels every 90°.
	for degrees in range(-90, 181, 45):
		var radians := deg_to_rad(degrees)
		var direction := Vector3(cos(radians), sin(radians), 0.0)
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.07 if degrees % 90 == 0 else 0.04, 0.01, 0.01)
		var tick := add_mesh(self, tick_mesh, Color(0.85, 0.87, 0.90))
		tick.position = PIVOT + direction * MARK_RADIUS
		tick.rotation = Vector3(0.0, 0.0, radians)
		if degrees % 90 == 0:
			add_label(PIVOT + direction * (MARK_RADIUS + 0.13), 40,
					Color(0.80, 0.82, 0.86)).text = "%d°" % degrees  # 40 px: readable on a projector

	# Hard stops: hanging straight down, and pointing left (180°).
	var stop_mesh := BoxMesh.new()
	stop_mesh.size = Vector3(0.05, 0.05, 0.05)
	add_mesh(self, stop_mesh, Color(0.8, 0.2, 0.2)).position = PIVOT + Vector3(0.07, -0.16, 0.08)
	add_mesh(self, stop_mesh, Color(0.8, 0.2, 0.2)).position = PIVOT + Vector3(-0.16, -0.07, 0.08)
