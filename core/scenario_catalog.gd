# scenario_catalog.gd
#
# PURPOSE
#   Finds every scenario file in res://scenarios/ for the toolbar's picker.
#   Files are listed in filename order, so a number prefix sets the teaching
#   order: "01_flywheel.tres", "02_hotend.tres"...
#
# HOW IT FITS
#   Adding a scenario = adding a .tres file to res://scenarios/. No code changes.
class_name ScenarioCatalog
extends RefCounted

const SCENARIO_FOLDER: String = "res://scenarios/"


static func load_all() -> Array[Scenario]:
	var scenarios: Array[Scenario] = []
	# GODOT-VERSION: ResourceLoader.list_directory (Godot 4.4+) also works in
	# exported builds, where resource files are renamed/remapped.
	var file_names := Array(ResourceLoader.list_directory(SCENARIO_FOLDER))
	file_names.sort()
	for file_name: String in file_names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var scenario := load(SCENARIO_FOLDER + file_name) as Scenario
		if scenario == null or scenario.plant_script == null:
			push_warning("Skipping '%s': not a Scenario with a plant." % file_name)
			continue
		scenarios.append(scenario)
	return scenarios
