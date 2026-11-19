# credits.gd
#
# PURPOSE
#   The in-app credits list (Display & graphics → Credits): every third-party
#   asset, its author, source and license. CREDITS.md is the same list for
#   people reading the code; keep the two in sync (see CREDITS.md).
#
# HOW IT FITS
#   DisplayPanel opens make_dialog() in an AcceptDialog. Plain data + text.
class_name Credits
extends RefCounted

# [what, author, source, license]
const ENTRIES: Array = [
	["Interface sounds (clicks, toggles, chimes)", "Kenney (kenney.nl)",
		"opengameart.org/content/interface-sounds", "CC0"],
	["Hard-stop clunk", "rubberduck", "opengameart.org/content/100-cc0-metal-and-wood-sfx", "CC0"],
	["Car engine loop", "domasx2", "opengameart.org/content/racing-car-engine-sound-loops", "CC0"],
	["Drone propeller loop", "mish7913", "opengameart.org/content/propeller-cartoon-loop", "CC0"],
	["Elevator winch loop", "ycbcr", "opengameart.org/content/generator-loop", "CC0"],
	["Brushed metal texture (Metal 009)", "ambientCG", "ambientcg.com/view?id=Metal009", "CC0"],
	["Concrete texture (Concrete Floor 02)", "Rob Tuytel, Poly Haven",
		"polyhaven.com/a/concrete_floor_02", "CC0"],
	["Asphalt texture (Asphalt 02)", "Rob Tuytel, Poly Haven", "polyhaven.com/a/asphalt_02", "CC0"],
	["Grass texture (Grass Ground)", "Charlotte Baglioni, Poly Haven",
		"polyhaven.com/a/grass_ground", "CC0"],
	["Studio lighting (Studio Small 09 HDRI)", "Sergej Majboroda, Poly Haven",
		"polyhaven.com/a/studio_small_09", "CC0"],
	["Motor whine and heater hiss (synthesized)", "Control Lab", "tools/make_synth_sounds.py",
		"same as Control Lab"],
	["Game engine", "Godot Engine contributors", "godotengine.org", "MIT"],
]


static func get_text() -> String:
	var lines: PackedStringArray = ["Control Lab uses these free assets. Thank you!", ""]
	for entry: Array in ENTRIES:
		lines.append("%s\n    by %s  ·  %s  ·  %s" % entry)
	lines.append("")
	lines.append("CC0 = public domain: free to use, credit appreciated.")
	return "\n".join(lines)


static func make_dialog() -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = "Credits"
	dialog.ok_button_text = "Close"
	# Scrolls, so the Close button stays on screen (also in presenter mode).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880.0, 600.0)  # TUNABLE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var label := Label.new()
	label.text = get_text()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", UiStyle.HINT)
	scroll.add_child(label)
	return dialog
