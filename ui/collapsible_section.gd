# collapsible_section.gd
#
# PURPOSE
#   A titled panel section whose body can be hidden with one click
#   (README 7.1: panels should be collapsible).
#
# HOW IT FITS
#   Side-panel sections (manual control, plant parameters, simulation settings)
#   are each one of these. Put content into `body`.
class_name CollapsibleSection
extends VBoxContainer

var body: VBoxContainer

var _header: Button
var _title: String


func _init(title: String, start_open: bool = true) -> void:
	_title = title
	add_theme_constant_override("separation", 6)

	_header = Button.new()
	_header.toggle_mode = true
	_header.button_pressed = start_open
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.focus_mode = Control.FOCUS_NONE
	_header.toggled.connect(_on_header_toggled)
	add_child(_header)

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	_on_header_toggled(start_open)


# Open (or close) the section from code, e.g. when a block-diagram block is clicked.
func set_open(is_open: bool) -> void:
	_header.button_pressed = is_open  # emits toggled -> _on_header_toggled


func _on_header_toggled(is_open: bool) -> void:
	body.visible = is_open
	# "v" when open, ">" when closed: plain ASCII so every font can draw it.
	_header.text = ("v  " if is_open else ">  ") + _title
