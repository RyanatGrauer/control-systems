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
#   plant scene looks consistent. With DisplaySettings.detailed_materials on,
#   a studio HDRI (Poly Haven, CC0) lights the scene and gives metal parts real
#   reflections; the background stays a plain dark colour for projectors.
#
# SURFACES (A/V patch)
#   apply_surface() puts a CC0 texture set (CREDITS.md) on a part. add_mesh()
#   gives every metallic part (metallic >= 0.5) brushed metal automatically.
#   Textures use triplanar mapping, so primitives need no UVs.
#
# SOUND (A/V patch)
#   A visual may return a looping sound (get_sound_loop) and, every frame, its
#   pitch and loudness (get_sound_level). PlantView plays it. One-shot sounds
#   (a carriage hitting its hard stop) go out through the sound_event signal;
#   track_hard_stop() detects those for you.
class_name PlantVisual3D
extends Node3D

## A one-shot sound for PlantView to play: `kind` is &"hard_stop";
## `strength` 0..1 sets the loudness.
signal sound_event(kind: StringName, strength: float)

enum Surface { BRUSHED_METAL, CONCRETE, ASPHALT, GRASS }

const GRID_FLOOR_SHADER: Shader = preload("res://plants/common/grid_floor.gdshader")
const GHOST_SHADER: Shader = preload("res://plants/common/ghost.gdshader")
const STUDIO_HDRI: Texture2D = preload("res://assets/hdri/studio_small_09_1k.hdr")
# Surface -> [albedo, roughness, normal] (null = keep the part's plain colour).
const SURFACE_TEXTURES: Dictionary = {
	Surface.BRUSHED_METAL: [null, preload("res://assets/textures/brushed_metal_rough.jpg"),
		preload("res://assets/textures/brushed_metal_normal.jpg")],
	Surface.CONCRETE: [preload("res://assets/textures/concrete_color.jpg"),
		preload("res://assets/textures/concrete_rough.jpg"), preload("res://assets/textures/concrete_normal.jpg")],
	Surface.ASPHALT: [preload("res://assets/textures/asphalt_color.jpg"),
		preload("res://assets/textures/asphalt_rough.jpg"), preload("res://assets/textures/asphalt_normal.jpg")],
	Surface.GRASS: [preload("res://assets/textures/grass_color.jpg"),
		preload("res://assets/textures/grass_rough.jpg"), preload("res://assets/textures/grass_normal.jpg")],
}
# TUNABLE: texture repeats per metre (triplanar), per surface.
const SURFACE_TILING: Dictionary = {Surface.BRUSHED_METAL: 3.0, Surface.CONCRETE: 1.5,
	Surface.ASPHALT: 2.0, Surface.GRASS: 1.5}
const HARD_STOP_MIN_FRACTION: float = 0.08  # TUNABLE: slower impacts than this are silent

var camera: OrbitCamera
var _stop_contact: int = -1  # hard-stop tracking: -1 unknown, 0 free, 1 touching
var _speed_before_stop: float = 0.0


# --- sound (override in a plant's visual) ---

# The plant's looping sound, or null for a silent plant.
func get_sound_loop() -> AudioStream:
	return null


# x = pitch_scale (1 = as recorded), y = loudness 0..1. Called every frame.
func get_sound_level(_plant: Plant, _state: PackedFloat64Array, _applied_input: float) -> Vector2:
	return Vector2(1.0, 0.0)


# |applied input| as a fraction of the input's largest magnitude (0..1).
static func effort_fraction(plant: Plant, applied_input: float) -> float:
	var info := plant.get_input_definition()
	return clampf(absf(applied_input) / maxf(absf(info.min_value), absf(info.max_value)), 0.0, 1.0)


# Call every frame from show_state() for a part with hard stops. Emits a
# "hard_stop" sound_event when it ARRIVES at a stop fast enough. `speed` is the
# current speed, `full_speed` a speed that should give a full-volume clunk.
func track_hard_stop(at_stop: bool, speed: float, full_speed: float) -> void:
	var touching := 1 if at_stop else 0
	if _stop_contact == 0 and touching == 1:
		var strength := clampf(_speed_before_stop / full_speed, 0.0, 1.0)
		if strength >= HARD_STOP_MIN_FRACTION:
			sound_event.emit(&"hard_stop", strength)
	_stop_contact = touching
	_speed_before_stop = absf(speed)


# Forget hard-stop history (on reset, so a fresh run never clunks).
func reset_hard_stop_tracking() -> void:
	_stop_contact = -1
	_speed_before_stop = 0.0


# Override: update the 3D scene from the simulation.
#   sim_time lets visuals animate in SIMULATED time, so pausing freezes them
#   and the time-scale slider slows them down correctly.
func show_state(_plant: Plant, _state: PackedFloat64Array, _setpoint: float,
		_applied_input: float, _sim_time: float) -> void:
	pass


# Override if a visual needs to forget animation history on reset.
# Called every frame with true while the actuator (or the PID's own output
# limit) is clipping the command. Override to tint the part that shows the
# input (e.g. turn the force arrow red). PlantView also shows a badge.
func show_saturation(_saturated: bool) -> void:
	pass


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
	if DisplaySettings.detailed_materials:
		# The studio HDRI lights the scene and shows in reflections, but the
		# background itself stays the plain colour (sky is not drawn).
		var sky_material := PanoramaSkyMaterial.new()
		sky_material.panorama = STUDIO_HDRI
		# The softboxes are very bright: tone the HDRI down so polished metal
		# (the flywheel disc) reflects them as highlights, not a white blank.
		# (Not background_energy_multiplier: that would darken the plain
		# background colour too.)
		sky_material.energy_multiplier = 0.35  # TUNABLE
		var sky := Sky.new()
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 0.55  # TUNABLE
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	# Key light: the ONE shadow-casting light allowed by the performance budget.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	key_light.light_energy = 1.1
	key_light.shadow_enabled = DisplaySettings.shadows  # off in the "Low" preset
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
	if metallic >= 0.5 and color.a >= 1.0:
		apply_surface(instance, Surface.BRUSHED_METAL)
	return instance


# Gives a part made by add_mesh() a textured surface (Low graphics: no-op).
# The part's colour still tints the texture, so signal colours survive.
static func apply_surface(instance: MeshInstance3D, surface: Surface) -> MeshInstance3D:
	var material := instance.material_override as StandardMaterial3D
	if material == null or not DisplaySettings.detailed_materials:
		return instance
	set_surface_textures(material, surface, true)
	return instance


# Fills `material` with a surface's textures. `triplanar` = map by position
# (primitives); false = use the mesh's own UVs (e.g. the cruise road).
static func set_surface_textures(material: StandardMaterial3D, surface: Surface,
		triplanar: bool) -> void:
	var textures: Array = SURFACE_TEXTURES[surface]
	if textures[0] != null:
		material.albedo_texture = textures[0]
	material.roughness_texture = textures[1]
	material.roughness = 1.0  # the texture now sets roughness
	if surface == Surface.BRUSHED_METAL:
		material.roughness = 0.75  # scales the map: keep polished metal shiny
	material.normal_enabled = true
	material.normal_texture = textures[2]
	material.normal_scale = 0.6  # TUNABLE: subtle, it's a lab not a ruin
	if triplanar:
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * float(SURFACE_TILING[surface])


# Material for the setpoint "ghost": a translucent copy of the plant drawn at
# the target position (README 4.4). With DisplaySettings.animated_ghost it uses
# ghost.gdshader (rim glow + pulse); otherwise a plain flat translucent colour
# (the "Low" graphics preset).
static func make_ghost_material() -> Material:
	if DisplaySettings.animated_ghost:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = GHOST_SHADER
		shader_material.set_shader_parameter("ghost_color", Color(SignalColors.SETPOINT, 0.35))
		return shader_material
	return make_plain_ghost_material()


# Flat translucent setpoint colour, unshaded so it reads as an overlay.
static func make_plain_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(SignalColors.SETPOINT, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


# Billboard text label (always faces the camera, drawn on top of geometry).
func add_label(at: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.pixel_size = 0.0025
	label.outline_size = 16
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.no_depth_test = true
	add_child(label)
	return label
