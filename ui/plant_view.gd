# plant_view.gd
#
# PURPOSE
#   The "animated plant view" panel (README 7.1). Hosts a plant's visual scene
#   inside its own SubViewport and handles camera input.
#
# HOW IT FITS
#   main_screen.gd calls load_plant_visual() once and show_state() every frame.
#   This node forwards the simulation state to the visual; the visual never
#   reaches back into the simulation.
#
# INPUT
#   Left-drag orbits the camera, mouse wheel zooms, "Reset camera" restores the
#   default framing. (Plain left CLICK is reserved for "poke the plant"
#   disturbances in stage 14.)
class_name PlantView
extends Control

var _viewport: SubViewport
var _visual: PlantVisual3D
var _is_orbiting: bool = false


func _init() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(320.0, 220.0)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # we handle input here
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X  # TUNABLE (Graphics "Low" preset will turn off)
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	var reset_camera_button := Button.new()
	reset_camera_button.text = "Reset camera"
	reset_camera_button.focus_mode = Control.FOCUS_NONE
	# Pin the button to the top-right corner, 8 px from the edges.
	reset_camera_button.anchor_left = 1.0
	reset_camera_button.anchor_right = 1.0
	reset_camera_button.offset_left = -128.0
	reset_camera_button.offset_right = -8.0
	reset_camera_button.offset_top = 8.0
	reset_camera_button.offset_bottom = 40.0
	reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	add_child(reset_camera_button)


func load_plant_visual(plant: Plant) -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	var scene_path := plant.get_visual_scene_path()
	if scene_path == "":
		push_warning("Plant '%s' has no visual scene." % plant.get_display_name())
		return
	var scene: PackedScene = load(scene_path)
	_visual = scene.instantiate() as PlantVisual3D
	if _visual == null:
		push_error("Visual scene '%s' must use a PlantVisual3D script." % scene_path)
		return
	_viewport.add_child(_visual)


func show_state(simulation: Simulation) -> void:
	if _visual == null:
		return
	_visual.show_state(simulation.plant, simulation.state, simulation.setpoint,
			simulation.applied_input, simulation.get_time())


func reset_visual() -> void:
	if _visual != null:
		_visual.reset_visual()


func _gui_input(event: InputEvent) -> void:
	if _visual == null or _visual.get_camera() == null:
		return
	var camera := _visual.get_camera()
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_is_orbiting = button.pressed
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(1.0)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(-1.0)
			accept_event()
	elif event is InputEventMouseMotion and _is_orbiting:
		var motion := event as InputEventMouseMotion
		camera.orbit(motion.relative)
		accept_event()


func _on_reset_camera_pressed() -> void:
	if _visual != null and _visual.get_camera() != null:
		_visual.get_camera().reset_view()
