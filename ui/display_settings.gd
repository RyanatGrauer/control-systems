# display_settings.gd
#
# PURPOSE
#   App-wide display choices (README 7.6 presenter mode, README 2 performance
#   budget): the Graphics settings and Presenter mode. Every visual effect has
#   its own switch, and presets set them all at once; "Low" is for the
#   slowest school laptops.
#
# HOW IT FITS
#   Plain static variables, read by PlantView / PlantVisual3D (3D effects) and
#   by StripChart / BlockDiagram (line widths, contrast). The Display panel
#   writes them and then asks main_screen.gd to re-apply them. Saved with the
#   other settings by SaveStore (to_save / load_save).
#   Sound settings live here too (stage A/V patch): one place for "how the
#   app looks and sounds", saved the same way.
class_name DisplaySettings
extends RefCounted

enum Preset { LOW, MEDIUM, HIGH, CUSTOM }

# --- graphics (each effect has its own switch) ---
static var msaa: Viewport.MSAA = Viewport.MSAA_2X   # 3D anti-aliasing
static var shadows: bool = true                     # the key light's shadow
static var render_scale: float = 1.0                # 3D resolution (0.5-1.0)
static var motion_blur: bool = true                 # flywheel blur disc
static var animated_ghost: bool = true              # rim glow + gentle pulse on setpoint ghosts
static var detailed_materials: bool = true          # textures + studio reflections (CREDITS.md)
static var preset: Preset = Preset.MEDIUM

# --- sound (not part of the graphics presets) ---
static var sound_on: bool = true          # master mute (toolbar button, M key)
static var sound_volume: float = 0.6      # master volume, 0..1
static var plant_sounds: bool = true      # motor / engine / rotor loops, hard-stop clunks
static var interface_sounds: bool = true  # button clicks, challenge / lesson chimes

# --- presenter mode ---
static var presenter: bool = false

# TUNABLE: what presenter mode changes.
const PRESENTER_UI_SCALE: float = 1.25      # everything (text, buttons) 25% bigger
const PRESENTER_LINE_SCALE: float = 1.7     # thicker plot lines
const PRESENTER_BACKGROUND: Color = Color(0.0, 0.0, 0.0)
const PRESENTER_GRID: Color = Color(1.0, 1.0, 1.0, 0.22)


static func apply_preset(new_preset: Preset) -> void:
	preset = new_preset
	match new_preset:
		Preset.LOW:
			msaa = Viewport.MSAA_DISABLED
			shadows = false
			render_scale = 0.75
			motion_blur = false
			animated_ghost = false
			detailed_materials = false
		Preset.MEDIUM:
			msaa = Viewport.MSAA_2X
			shadows = true
			render_scale = 1.0
			motion_blur = true
			animated_ghost = true
			detailed_materials = true
		Preset.HIGH:
			msaa = Viewport.MSAA_4X
			shadows = true
			render_scale = 1.0
			motion_blur = true
			animated_ghost = true
			detailed_materials = true


static func get_preset_name(which: Preset) -> String:
	return ["Low (school laptops)", "Medium", "High", "Custom"][which]


static func line_scale() -> float:
	return PRESENTER_LINE_SCALE if presenter else 1.0


static func plot_background() -> Color:
	return PRESENTER_BACKGROUND if presenter else SignalColors.PLOT_BACKGROUND


static func plot_grid() -> Color:
	return PRESENTER_GRID if presenter else SignalColors.PLOT_GRID


# --- saving (README 7.10). Plain values only; SaveStore validates them. ---

static func default_save() -> Dictionary:
	return {"graphics_preset": Preset.MEDIUM, "msaa": Viewport.MSAA_2X, "shadows": true,
		"render_scale": 1.0, "motion_blur": true, "animated_ghost": true, "presenter": false,
		"detailed_materials": true, "sound_on": true, "sound_volume": 0.6, "plant_sounds": true,
		"interface_sounds": true}


static func to_save() -> Dictionary:
	return {"graphics_preset": preset, "msaa": msaa, "shadows": shadows,
		"render_scale": render_scale, "motion_blur": motion_blur,
		"animated_ghost": animated_ghost, "presenter": presenter,
		"detailed_materials": detailed_materials, "sound_on": sound_on,
		"sound_volume": sound_volume, "plant_sounds": plant_sounds,
		"interface_sounds": interface_sounds}


# `settings` has already been validated (right keys and types).
static func load_save(settings: Dictionary) -> void:
	preset = clampi(settings["graphics_preset"], 0, Preset.CUSTOM) as Preset
	msaa = clampi(settings["msaa"], 0, Viewport.MSAA_8X) as Viewport.MSAA
	shadows = settings["shadows"]
	render_scale = clampf(settings["render_scale"], 0.25, 1.0)
	motion_blur = settings["motion_blur"]
	animated_ghost = settings["animated_ghost"]
	presenter = settings["presenter"]
	detailed_materials = settings["detailed_materials"]
	sound_on = settings["sound_on"]
	sound_volume = clampf(settings["sound_volume"], 0.0, 1.0)
	plant_sounds = settings["plant_sounds"]
	interface_sounds = settings["interface_sounds"]


# Final loudness (0..1) for a sound of one category, after mute and volume.
static func get_gain(is_plant_sound: bool) -> float:
	if not sound_on:
		return 0.0
	if not (plant_sounds if is_plant_sound else interface_sounds):
		return 0.0
	return sound_volume

