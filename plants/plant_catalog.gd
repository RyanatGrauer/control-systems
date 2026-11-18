# plant_catalog.gd
#
# PURPOSE
#   The list of plants the toolbar's plant picker offers, in teaching order.
#
# HOW IT FITS
#   TEMPORARY: in stage 15 this is replaced by scenario resources (a scenario
#   bundles a plant with its settings), and the picker lists scenarios instead.
#   To add a plant now: append a line to PLANT_SCRIPTS.
class_name PlantCatalog
extends RefCounted

const PLANT_SCRIPTS: Array[GDScript] = [
	preload("res://plants/flywheel/flywheel_plant.gd"),
	preload("res://plants/mass_spring_damper/mass_spring_damper_plant.gd"),
	preload("res://plants/servo/servo_plant.gd"),
]


static func get_count() -> int:
	return PLANT_SCRIPTS.size()


static func create_plant(index: int) -> Plant:
	return PLANT_SCRIPTS[index].new()


static func get_plant_names() -> PackedStringArray:
	var names := PackedStringArray()
	for script in PLANT_SCRIPTS:
		var plant: Plant = script.new()
		names.append(plant.get_display_name())
	return names
