# ghost_run.gd
#
# PURPOSE
#   A finished run kept for comparison (README 7.3 "ghost traces"): a copy of
#   a few recorder channels, a label ("A", "run 3"...) and a faded colour.
#   Strip charts draw ghosts behind the live traces so two tunings can be
#   compared on the same axes (A/B compare, README 7.2).
#
# HOW IT FITS
#   main_screen.gd makes one on every Reset (if the run lasted long enough)
#   and keeps the newest few. Every StripChart shares that list and draws, for
#   each ghost, the traces marked `ghost = true` (e.g. the measurement).
class_name GhostRun
extends RefCounted

var recorder: RunRecorder
var label: String
var color: Color


func _init(source: RunRecorder, channels: PackedStringArray, new_label: String,
		new_color: Color) -> void:
	recorder = source.copy_channels(channels)
	label = new_label
	color = new_color
