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
var _ground_material: StandardMaterial3D
var _asphalt_material: StandardMaterial3D
var _post_material: StandardMaterial3D
const TEXTURE_TILE_M: float = 4.0  # TUNABLE: road metres per texture repeat
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
	add_child(road)
	# Three surfaces: grass ground, asphalt road, white posts. The textures
	# use UVs tied to road DISTANCE, so they scroll with the road (a texture
	# fixed in space would make the car look parked).
	_ground_material = _make_road_material(Color(0.18, 0.32, 0.2), PlantVisual3D.Surface.GRASS)
	_asphalt_material = _make_road_material(Color(0.3, 0.3, 0.32), PlantVisual3D.Surface.ASPHALT)
	_post_material = _make_road_material(Color(0.92, 0.92, 0.92), -1)

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
	# Grass: the ground's vertical face under the road. v uses the same
	# metres-per-repeat as u, so the texture isn't stretched.
	var v_per_world := 1.0 / (TEXTURE_TILE_M * METRES_TO_WORLD)
	_road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ground_material)
	var road_x := distance - ROAD_VIEW_M
	while road_x < distance + ROAD_VIEW_M:
		var a: Vector2 = to_world.call(road_x)
		var b: Vector2 = to_world.call(road_x + ROAD_SEGMENT_M)
		var ua := road_x / TEXTURE_TILE_M
		var ub := (road_x + ROAD_SEGMENT_M) / TEXTURE_TILE_M
		_quad(Vector3(a.x, 0.0, -0.2), Vector3(b.x, 0.0, -0.2),
				Vector3(b.x, b.y - 0.03, -0.2), Vector3(a.x, a.y - 0.03, -0.2),
				[Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, (b.y - 0.03) * v_per_world),
				Vector2(ua, (a.y - 0.03) * v_per_world)])
		road_x += ROAD_SEGMENT_M
	_road_mesh.surface_end()
	# Asphalt: the road's front edge and its top.
	_road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _asphalt_material)
	road_x = distance - ROAD_VIEW_M
	while road_x < distance + ROAD_VIEW_M:
		var a: Vector2 = to_world.call(road_x)
		var b: Vector2 = to_world.call(road_x + ROAD_SEGMENT_M)
		var ua := road_x / TEXTURE_TILE_M
		var ub := (road_x + ROAD_SEGMENT_M) / TEXTURE_TILE_M
		# The road surface: a band with depth, so the car sits ON it.
		_quad(Vector3(a.x, a.y - 0.03, -0.2), Vector3(b.x, b.y - 0.03, -0.2),
				Vector3(b.x, b.y, -0.2), Vector3(a.x, a.y, -0.2),
				[Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 0.03), Vector2(ua, 0.03)])
		_quad(Vector3(a.x, a.y, -0.2), Vector3(b.x, b.y, -0.2),
				Vector3(b.x, b.y, 0.2), Vector3(a.x, a.y, 0.2),
				[Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 0.1), Vector2(ua, 0.1)])
		road_x += ROAD_SEGMENT_M
	_road_mesh.surface_end()
	# White distance posts.
	_road_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _post_material)
	var first_post := ceilf((distance - ROAD_VIEW_M) / POST_SPACING_M) * POST_SPACING_M
	var post_x := first_post
	while post_x < distance + ROAD_VIEW_M:
		var base: Vector2 = to_world.call(post_x)
		_quad(Vector3(base.x - 0.008, base.y, -0.25), Vector3(base.x + 0.008, base.y, -0.25),
				Vector3(base.x + 0.008, base.y + 0.22, -0.25), Vector3(base.x - 0.008, base.y + 0.22, -0.25),
				[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		post_x += POST_SPACING_M
	_road_mesh.surface_end()


# A road material: plain `color`, plus `surface`'s textures (UV-mapped) when
# detailed materials are on. surface -1 = plain colour only.
func _make_road_material(color: Color, surface: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	if surface >= 0 and DisplaySettings.detailed_materials:
		material.albedo_color = color.lightened(0.6)  # textures carry their own colour
		if surface == PlantVisual3D.Surface.GRASS:
			material.albedo_color = Color(0.6, 0.95, 0.5)  # TUNABLE: the texture is mostly soil
		PlantVisual3D.set_surface_textures(material, surface as PlantVisual3D.Surface, false)
	return material


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uvs: Array) -> void:
	var corners := [a, b, c, d]
	for index in [0, 1, 2, 0, 2, 3]:
		_road_mesh.surface_set_uv(uvs[index])
		_road_mesh.surface_set_normal(Vector3(0.0, 0.3, 1.0).normalized())
		_road_mesh.surface_add_vertex(corners[index])


# --- sound: engine revs with speed and throttle ---
const SOUND_FULL_SPEED: float = 40.0  # TUNABLE: m/s for the highest pitch


func get_sound_loop() -> AudioStream:
	return SoundBank.ENGINE_LOOP


func get_sound_level(plant: Plant, state: PackedFloat64Array, applied_input: float) -> Vector2:
	var speed := clampf(absf(state[1]) / SOUND_FULL_SPEED, 0.0, 1.0)
	var throttle := clampf(applied_input / plant.get_input_definition().max_value, 0.0, 1.0)
	return Vector2(0.55 + 0.9 * speed + 0.2 * throttle,
			clampf(0.3 + 0.45 * throttle + 0.25 * speed, 0.0, 1.0))
