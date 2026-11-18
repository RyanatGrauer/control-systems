# plant_visual_3d.gd
#
# PURPOSE
#   Base class for a plant's 3D "visual binding" (README 4.3 / 4.4): a scene
#   that READS the plant state and animates it. A visual must never change the
#   physics; it is only a window onto the simulation.
#
# HOW IT FITS
#   ui/plant_view.gd loads the scene named by Plant.get_visual_scene_path(),
#   puts it inside a SubViewport, and calls show_state() every rendered frame.
#   It also forwards mouse drags / wheel to the camera returned by get_camera().
#   A 2D base class for plants that read better flat will be added later and
#   hosted the same way.
#
# STUDIO SETUP
#   build_studio() adds the shared look: a grid floor, one shadowed key light,
#   a fill light, and an environment. Subclasses call it from _ready() so every
#   plant scene looks consistent.
class_name PlantVisual3D
extends Node3D

const GRID_FLOOR_SHADER: Shader = preload("res://plants/common/grid_floor.gdshader")

var camera: OrbitCamera


# Override: update the 3D scene from the simulation.
#   sim_time lets visuals animate in SIMULATED time, so pausing freezes them
#   and the time-scale slider slows them down correctly.
func show_state(_plant: Plant, _state: PackedFloat64Array, _setpoint: float,
		_applied_input: float, _sim_time: float) -> void:
	pass


# Override if a visual needs to forget animation history on reset.
func reset_visual() -> void:
	pass


func get_camera() -> OrbitCamera:
	return camera


# Shared lighting, floor and camera. `look_at_point`, `distance`, `yaw_degrees`
# and `pitch_degrees` set the camera's default (and "reset camera") framing.
func build_studio(look_at_point: Vector3, distance: float, yaw_degrees: float,
		pitch_degrees: float) -> void:
	# Environment: plain dark background (reads well on projectors) + ambient fill.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.11, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	# Key light: the ONE shadow-casting light allowed by the performance budget.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	key_light.light_energy = 1.1
	key_light.shadow_enabled = true
	add_child(key_light)

	# Fill light from the other side, no shadows (cheap).
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill_light.light_energy = 0.35
	fill_light.shadow_enabled = false
	add_child(fill_light)

	# Grid floor.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12.0, 12.0)
	var floor_material := ShaderMaterial.new()
	floor_material.shader = GRID_FLOOR_SHADER
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_material
	add_child(floor_instance)

	camera = OrbitCamera.new()
	camera.configure_default_view(look_at_point, distance, yaw_degrees, pitch_degrees)
	add_child(camera)
	camera.current = true


# Small helper: a mesh instance with a simple lit material, added to `parent`.
static func add_mesh(parent: Node3D, mesh: Mesh, color: Color,
		metallic: float = 0.0, roughness: float = 0.6) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance
