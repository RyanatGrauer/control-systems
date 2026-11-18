# plant_catalog.gd
#
# PURPOSE
#   Every plant TYPE in the project, in teaching order. The app itself picks
#   plants through scenario files (res://scenarios/); this list is for the
#   tests, which check every plant (consistency, UI smoke tests).
#
# HOW IT FITS
#   When you add a plant, append it here so the tests cover it, and add a
#   scenario file so students can choose it.
class_name PlantCatalog
extends RefCounted

const PLANT_SCRIPTS: Array[GDScript] = [
	preload("res://plants/flywheel/flywheel_plant.gd"),
	preload("res://plants/hotend/hotend_plant.gd"),
	preload("res://plants/mass_spring_damper/mass_spring_damper_plant.gd"),
	preload("res://plants/servo/servo_plant.gd"),
	preload("res://plants/elevator/elevator_plant.gd"),
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
