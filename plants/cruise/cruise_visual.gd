# cruise_visual.gd
#
# PURPOSE
#   3D view of plant #7: a car seen from the side on a hilly road. The car
#   stays in the middle of the view and the road scrolls past (distance
#   posts every 25 m show the motion). Hills are drawn 3× steeper than they
#   are, so gentle 5% slopes are visible. Labels show the speed, the target
#   speed (orange) and the drive force (yellow).
#
# HOW IT FITS
#   Loaded by ui/plant_view.gd; show_state() is called every frame. The road
#   is rebuilt every frame with an ImmediateMesh (a few hundred vertices).
#   Display only.
extends PlantVisual3D

# TUNABLE: drawing scale.
const METRES_TO_WORLD: float = 0.05     # 1 m of road = 5 cm on screen
const HILL_EXAGGERATION: float = 3.0
const ROAD_VIEW_M: float = 70.0         # road drawn this far each side of the car
const ROAD_SEGMENT_M: float = 1.0
const ROAD_Y: float = 0.9               # world height of the road under the car
const POST_SPACING_M: float = 25.0
const WHEEL_RADIUS: float = 0.06

var _road_mesh: ImmediateMesh
var _car: Node3D
var _wheels: Array[MeshInstance3D] = []
var _speed_label: Label3D
var _target_label: Label3D
var _force_label: Label3D


func _ready() -> void:
	build_studio(Vector3(0.0, ROAD_Y + 0.1, 0.0), 2.6, 0.0, 6.0)

	_road_mesh = ImmediateMesh.new()
	var road := MeshInstance3D.new()
	road.mesh = _road_mesh
	var road_material := StandardMaterial3D.new()
	road_material.vertex_color_use_as_albedo = true
	road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_material.roughness = 0.9
	road.material_override = road_material
	add_child(road)

	_car = Node3D.new()
	add_child(_car)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.48, 0.1, 0.22)
	add_mesh(_car, body_mesh, SignalColors.MEASUREMENT, 0.3, 0.4).position = Vector3(0.0, WHEEL_RADIUS + 0.06, 0.0)
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(0.24, 0.08, 0.2)
	add_mesh(_car, cabin_mesh, Color(0.2, 0.3, 0.42), 0.3, 0.3).position = Vector3(-0.03, WHEEL_RADIUS + 0.15, 0.0)
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = WHEEL_RADIUS
	wheel_mesh.bottom_radius = WHEEL_RADIUS
	wheel_mesh.height = 0.04
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(WHEEL_RADIUS * 1.8, 0.045, 0.015)
	for x in [-0.15, 0.15]:
		for z in [-0.12, 0.12]:
			var holder := Node3D.new()
			holder.position = Vector3(x, WHEEL_RADIUS, z)
			holder.rotation_degrees = Vector3(90.0, 0.0, 0.0)  # cylinder axis -> z
			_car.add_child(holder)
			var wheel := add_mesh(holder, wheel_mesh, Color(0.12, 0.12, 0.13), 0.1, 0.8)
			add_mesh(wheel, spoke_mesh, Color(0.7, 0.7, 0.72))
			_wheels.append(wheel)

	_speed_label = add_label(Vector3(0.0, ROAD_Y + 0.7, 0.0), 54, SignalColors.MEASUREMENT)
	_target_label = add_label(Vector3(0.0, ROAD_Y + 0.55, 0.0), 36, SignalColors.SETPOINT)
	_force_label = add_label(Vector3(0.0, ROAD_Y - 0.35, 0.3), 32, SignalColors.APPLIED_INPUT)


func show_state(plant: Plant, state: PackedFloat64Array, setpoint: float,
		applied_input: float, _sim_time: float) -> void:
	var cruise := plant as CruisePlant
	var distance := state[0]
	_build_road(cruise, distance)
	var grade := cruise.get_grade(distance) * HILL_EXAGGERATION
	_car.position = Vector3(0.0, ROAD_Y, 0.0)
	_car.rotation = Vector3(0.0, 0.0, atan(grade))
	for wheel in _wheels:
		wheel.rotation = Vector3(0.0, -distance * METRES_TO_WORLD / WHEEL_RADIUS, 0.0)
	_speed_label.text = "%d km/h" % roundi(state[1] * CruisePlant.MS_TO_KMH)
	_target_label.text = "target %d km/h" % roundi(setpoint * CruisePlant.MS_TO_KMH)
	var verb := "engine" if applied_input >= 0.0 else "brakes"
	_force_label.text = "%s %d N   (slope %s%%)" % [verb, roundi(absf(applied_input)),
			String.num(cruise.get_grade(distance) * 100.0, 1)]


# The road profile around the car as a filled strip (dark asphalt on top of
# green ground), plus white distance posts.
func _build_road(cruise: CruisePlant, distance: float) -> void:
	var car_height := cruise.get_road_height(distance)
	var to_world := func(at_x: float) -> Vector2:
		return Vector2((at_x - distance) * METRES_TO_WORLD,
				ROAD_Y + (cruise.get_road_height(at_x) - car_height) * METRES_TO_WORLD * HILL_EXAGGERATION)
	_road_mesh.clear_surfaces()
	_road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var road_x := distance - ROAD_VIEW_M
	while road_x < distance + ROAD_VIEW_M:
		var a: Vector2 = to_world.call(road_x)
		var b: Vector2 = to_world.call(road_x + ROAD_SEGMENT_M)
		_quad(Vector3(a.x, 0.0, -0.2), Vector3(b.x, 0.0, -0.2),
				Vector3(b.x, b.y - 0.03, -0.2), Vector3(a.x, a.y - 0.03, -0.2), Color(0.18, 0.32, 0.2))
		# The road surface: a band with depth, so the car sits ON it.
		_quad(Vector3(a.x, a.y - 0.03, -0.2), Vector3(b.x, b.y - 0.03, -0.2),
				Vector3(b.x, b.y, -0.2), Vector3(a.x, a.y, -0.2), Color(0.3, 0.3, 0.32))
		_quad(Vector3(a.x, a.y, -0.2), Vector3(b.x, b.y, -0.2),
				Vector3(b.x, b.y, 0.2), Vector3(a.x, a.y, 0.2), Color(0.25, 0.25, 0.27))
		road_x += ROAD_SEGMENT_M
	var first_post := ceilf((distance - ROAD_VIEW_M) / POST_SPACING_M) * POST_SPACING_M
	var post_x := first_post
	while post_x < distance + ROAD_VIEW_M:
		var base: Vector2 = to_world.call(post_x)
		_quad(Vector3(base.x - 0.008, base.y, -0.25), Vector3(base.x + 0.008, base.y, -0.25),
				Vector3(base.x + 0.008, base.y + 0.22, -0.25), Vector3(base.x - 0.008, base.y + 0.22, -0.25),
				Color(0.92, 0.92, 0.92))
		post_x += POST_SPACING_M
	_road_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for vertex in [a, b, c, a, c, d]:
		_road_mesh.surface_set_color(color)
		_road_mesh.surface_set_normal(Vector3(0.0, 0.3, 1.0).normalized())
		_road_mesh.surface_add_vertex(vertex)
