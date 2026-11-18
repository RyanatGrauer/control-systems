# display_panel.gd
#
# PURPOSE
#   The "Display & graphics" panel (README 2 performance budget, 7.6 presenter
#   mode): a Presenter mode switch, a graphics preset (Low / Medium / High),
#   and one switch per visual effect. Changing any single switch makes the
#   preset "Custom".
#
# HOW IT FITS
#   Writes DisplaySettings, then emits settings_changed; main_screen.gd
#   re-applies them (rebuilds the 3D view, redraws the plots).
class_name DisplayPanel
extends VBoxContainer

signal settings_changed
signal presenter_toggled(is_on: bool)

const PRESETS: Array[DisplaySettings.Preset] = [DisplaySettings.Preset.LOW,
	DisplaySettings.Preset.MEDIUM, DisplaySettings.Preset.HIGH, DisplaySettings.Preset.CUSTOM]
const RENDER_SCALES: Array[float] = [0.5, 0.75, 1.0]  # TUNABLE
const MSAA_CHOICES: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X,
	Viewport.MSAA_4X]

var _presenter_check: CheckBox
var _preset_menu: OptionButton
var _shadows_check: CheckBox
var _blur_check: CheckBox
var _ghost_check: CheckBox
var _msaa_menu: OptionButton
var _scale_menu: OptionButton


func setup() -> void:
	add_theme_constant_override("separation", 9)
	_presenter_check = _add_check("Presenter mode (F2)",
			"Bigger text, thicker lines, black plot backgrounds, fewer panels: for projectors.")
	_presenter_check.toggled.connect(func(on: bool) -> void: presenter_toggled.emit(on))

	var preset_row := HBoxContainer.new()
	var preset_label := Label.new()
	preset_label.text = "Graphics"
	preset_row.add_child(preset_label)
	_preset_menu = OptionButton.new()
	_preset_menu.focus_mode = Control.FOCUS_NONE
	_preset_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in PRESETS:
		_preset_menu.add_item(DisplaySettings.get_preset_name(preset), preset)
	_preset_menu.set_item_disabled(_preset_menu.get_item_index(DisplaySettings.Preset.CUSTOM), true)
	_preset_menu.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_menu)
	add_child(preset_row)

	_shadows_check = _add_check("Shadows", "The one shadow-casting light.")
	_blur_check = _add_check("Flywheel motion blur", "The blur disc that fades in at high speed.")
	_ghost_check = _add_check("Glowing setpoint ghost",
			"Rim glow and gentle pulse on the target ghost (off = flat colour).")
	_msaa_menu = _add_menu("Anti-aliasing", ["Off", "2x", "4x"])
	_scale_menu = _add_menu("3D resolution", ["50%", "75%", "100%"])

	_shadows_check.toggled.connect(func(on: bool) -> void:
		DisplaySettings.shadows = on
		_custom_changed())
	_blur_check.toggled.connect(func(on: bool) -> void:
		DisplaySettings.motion_blur = on
		_custom_changed())
	_ghost_check.toggled.connect(func(on: bool) -> void:
		DisplaySettings.animated_ghost = on
		_custom_changed())
	_msaa_menu.item_selected.connect(func(index: int) -> void:
		DisplaySettings.msaa = MSAA_CHOICES[index]
		_custom_changed())
	_scale_menu.item_selected.connect(func(index: int) -> void:
		DisplaySettings.render_scale = RENDER_SCALES[index]
		_custom_changed())
	sync_from_settings()


# Show DisplaySettings' current values without emitting anything.
func sync_from_settings() -> void:
	_presenter_check.set_pressed_no_signal(DisplaySettings.presenter)
	_preset_menu.select(_preset_menu.get_item_index(DisplaySettings.preset))
	_shadows_check.set_pressed_no_signal(DisplaySettings.shadows)
	_blur_check.set_pressed_no_signal(DisplaySettings.motion_blur)
	_ghost_check.set_pressed_no_signal(DisplaySettings.animated_ghost)
	_msaa_menu.select(maxi(MSAA_CHOICES.find(DisplaySettings.msaa), 0))
	_scale_menu.select(maxi(RENDER_SCALES.find(DisplaySettings.render_scale), 0))


func _on_preset_selected(index: int) -> void:
	DisplaySettings.apply_preset(_preset_menu.get_item_id(index) as DisplaySettings.Preset)
	sync_from_settings()
	settings_changed.emit()


func _custom_changed() -> void:
	DisplaySettings.preset = DisplaySettings.Preset.CUSTOM
	_preset_menu.select(_preset_menu.get_item_index(DisplaySettings.Preset.CUSTOM))
	settings_changed.emit()


func _add_check(title: String, tooltip: String) -> CheckBox:
	var check_box := CheckBox.new()
	check_box.text = title
	check_box.tooltip_text = tooltip
	check_box.focus_mode = Control.FOCUS_NONE
	add_child(check_box)
	return check_box


func _add_menu(title: String, items: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var menu := OptionButton.new()
	menu.focus_mode = Control.FOCUS_NONE
	for item in items:
		menu.add_item(item)
	row.add_child(menu)
	add_child(row)
	return menu
