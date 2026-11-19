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
#
# SOUND (A/V patch)
#   Plays the visual's looping sound with the pitch/loudness it asks for, and
#   its one-shot sound_events. The loop fades out while simulated time stands
#   still (paused, or scrubbing), so a paused classroom is quiet.
class_name PlantView
extends VBoxContainer

signal poked(direction: float)

const CLICK_SLOP_PIXELS: float = 5.0  # more movement than this = a drag, not a click

var _viewport: SubViewport
var _scene_area: Control
var _caption: Label
var _visual: PlantVisual3D
var _plant: Plant
var _saturation_badge: Label
var _is_orbiting: bool = false
var _drag_distance: float = 0.0
var _loop_player: AudioStreamPlayer
var _event_player: AudioStreamPlayer
var _loop_loudness: float = 0.0   # smoothed 0..1
var _loop_pitch: float = 1.0      # smoothed
var _last_sim_time: float = -1.0

# TUNABLE: plant sound mix and smoothing.
const LOOP_GAIN: float = 0.55        # loop loudness at full level (before master volume)
const EVENT_GAIN: float = 0.9
const SOUND_SMOOTHING_HZ: float = 8.0  # how fast loudness/pitch follow the plant


func _init() -> void:
	custom_minimum_size = Vector2(480.0, 390.0)
	add_theme_constant_override("separation", 6)

	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(300.0, 0.0)
	_caption.add_theme_font_size_override("font_size", UiStyle.HINT)
	_caption.add_theme_color_override("font_color", UiStyle.HINT_COLOR)
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
	_viewport.msaa_3d = DisplaySettings.msaa
	_viewport.scaling_3d_scale = DisplaySettings.render_scale
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	# Red badge while the actuator (or the PID's own limit) clips the command.
	_saturation_badge = Label.new()
	_saturation_badge.text = " SATURATED: the input is at its limit "
	_saturation_badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.75, 0.12, 0.12)
	badge_style.set_corner_radius_all(4)
	_saturation_badge.add_theme_stylebox_override("normal", badge_style)
	_saturation_badge.position = Vector2(12.0, 12.0)
	_saturation_badge.visible = false
	_saturation_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_area.add_child(_saturation_badge)

	var reset_camera_button := Button.new()
	reset_camera_button.text = "Reset camera"
	reset_camera_button.focus_mode = Control.FOCUS_NONE
	# Pin the button to the top-right corner of the scene, 12 px from the
	# edges. It grows LEFT to fit its text, so it is never clipped.
	reset_camera_button.anchor_left = 1.0
	reset_camera_button.anchor_right = 1.0
	reset_camera_button.offset_left = -12.0
	reset_camera_button.offset_right = -12.0
	reset_camera_button.offset_top = 12.0
	reset_camera_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	_scene_area.add_child(reset_camera_button)


# Put a control (the setpoint bar) in the strip under the 3D scene.
func set_bottom_bar(bar: Control) -> void:
	add_child(bar)


func load_plant_visual(plant: Plant) -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	_plant = plant
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
	_visual.sound_event.connect(_on_sound_event)
	_start_loop(_visual.get_sound_loop())


func show_state(simulation: Simulation) -> void:
	if _visual == null:
		return
	_visual.show_state(simulation.plant, simulation.state, simulation.setpoint,
			simulation.applied_input, simulation.get_time())
	var controller := simulation.controller
	var clipped: bool = controller.has_method("is_output_clipped") and controller.call("is_output_clipped")
	var saturated := simulation.actuator.is_saturated or clipped
	_saturation_badge.visible = saturated
	_visual.show_saturation(saturated)
	_update_sound(simulation)


func _start_loop(stream: AudioStream) -> void:
	if _loop_player == null:
		_loop_player = AudioStreamPlayer.new()
		add_child(_loop_player)
		_event_player = AudioStreamPlayer.new()
		_event_player.max_polyphony = 3
		add_child(_event_player)
	_loop_player.stop()
	_loop_player.stream = stream
	_loop_loudness = 0.0
	_loop_player.volume_db = -80.0


func _update_sound(simulation: Simulation) -> void:
	if _loop_player == null or _loop_player.stream == null:
		return
	var sim_time := simulation.get_time()
	var running := sim_time != _last_sim_time
	_last_sim_time = sim_time
	var level := _visual.get_sound_level(simulation.plant, simulation.state, simulation.applied_input)
	var target_loudness := clampf(level.y, 0.0, 1.0) if running else 0.0
	# (A zero delta happens when tests drive _process directly: assume 60 fps.)
	var frame_delta := get_process_delta_time()
	var blend := clampf((frame_delta if frame_delta > 0.0 else 1.0 / 60.0) * SOUND_SMOOTHING_HZ, 0.0, 1.0)
	_loop_loudness = lerpf(_loop_loudness, target_loudness, blend)
	_loop_pitch = lerpf(_loop_pitch, clampf(level.x, 0.25, 4.0), blend)
	var gain := _loop_loudness * LOOP_GAIN * DisplaySettings.get_gain(true)
	if gain < 0.002:
		if _loop_player.playing:
			_loop_player.stop()  # silent: free the voice
		return
	_loop_player.pitch_scale = _loop_pitch
	_loop_player.volume_db = linear_to_db(gain)
	if not _loop_player.playing:
		_loop_player.play()


func _on_sound_event(kind: StringName, strength: float) -> void:
	var gain := strength * EVENT_GAIN * DisplaySettings.get_gain(true)
	if gain < 0.002 or _event_player == null:
		return
	match kind:
		&"hard_stop":
			_event_player.stream = SoundBank.HARD_STOP
	_event_player.volume_db = linear_to_db(gain)
	_event_player.pitch_scale = randf_range(0.92, 1.08)  # not the sim's RNG: sound only
	_event_player.play()


# Re-apply DisplaySettings (Graphics panel). Rebuilds the 3D visual so lights
# and materials pick up the new switches; the camera goes back to its default.
func apply_graphics() -> void:
	_viewport.msaa_3d = DisplaySettings.msaa
	_viewport.scaling_3d_scale = DisplaySettings.render_scale
	if _plant != null:
		load_plant_visual(_plant)


func reset_visual() -> void:
	if _visual != null:
		_visual.reset_visual()
		_visual.reset_hard_stop_tracking()


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
