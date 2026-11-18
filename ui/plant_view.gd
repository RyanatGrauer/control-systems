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
#   default framing. A plain left CLICK (no drag) emits poked(+1) and a right
#   click poked(-1): main_screen.gd turns that into a short disturbance.
#
# LAYOUT (top to bottom, so nothing ever covers the 3D scene)
#   caption strip   "what's happening" text from Plant.get_description()
#   scene area      the SubViewport with the 3D visual + "Reset camera" button
#   bottom slot     the setpoint bar (added by main_screen.gd)
class_name PlantView
extends VBoxContainer

signal poked(direction: float)

const CLICK_SLOP_PIXELS: float = 5.0  # more movement than this = a drag, not a click

var _viewport: SubViewport
var _scene_area: Control
var _caption: Label
var _visual: PlantVisual3D
var _is_orbiting: bool = false
var _drag_distance: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(320.0, 260.0)
	add_theme_constant_override("separation", 4)

	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(200.0, 0.0)
	_caption.add_theme_font_size_override("font_size", 14)
	_caption.add_theme_color_override("font_color", SignalColors.PLOT_AXIS_TEXT)
	add_child(_caption)

	_scene_area = Control.new()
	_scene_area.clip_contents = true
	_scene_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_scene_area.gui_input.connect(_on_scene_input)
	add_child(_scene_area)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # input handled by _scene_area
	_scene_area.add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X  # TUNABLE (Graphics "Low" preset will turn off)
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	var reset_camera_button := Button.new()
	reset_camera_button.text = "Reset camera"
	reset_camera_button.focus_mode = Control.FOCUS_NONE
	# Pin the button to the top-right corner of the scene, 8 px from the edges.
	reset_camera_button.anchor_left = 1.0
	reset_camera_button.anchor_right = 1.0
	reset_camera_button.offset_left = -128.0
	reset_camera_button.offset_right = -8.0
	reset_camera_button.offset_top = 8.0
	reset_camera_button.offset_bottom = 40.0
	reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	_scene_area.add_child(reset_camera_button)


# Put a control (the setpoint bar) in the strip under the 3D scene.
func set_bottom_bar(bar: Control) -> void:
	add_child(bar)


func load_plant_visual(plant: Plant) -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	_caption.text = plant.get_description()
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


func _on_scene_input(event: InputEvent) -> void:
	if _visual == null or _visual.get_camera() == null:
		return
	var camera := _visual.get_camera()
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_drag_distance = 0.0
			elif _is_orbiting and _drag_distance < CLICK_SLOP_PIXELS:
				poked.emit(1.0)
			_is_orbiting = button.pressed
			_scene_area.accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
			poked.emit(-1.0)
			_scene_area.accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(1.0)
			_scene_area.accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(-1.0)
			_scene_area.accept_event()
	elif event is InputEventMouseMotion and _is_orbiting:
		var motion := event as InputEventMouseMotion
		_drag_distance += motion.relative.length()
		camera.orbit(motion.relative)
		_scene_area.accept_event()


func _on_reset_camera_pressed() -> void:
	if _visual != null and _visual.get_camera() != null:
		_visual.get_camera().reset_view()
