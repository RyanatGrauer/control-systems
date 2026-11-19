# test_mystery.gd
#
# PURPOSE
#   Mystery mode (stage 24): random parameters are seeded (same seed = same
#   plant), stay inside their slider ranges and the ½×-2× spread, differ
#   between seeds; and the UI hides them, and restores the scenario's values.
extends TestCase

const MainScreenScene: PackedScene = preload("res://ui/main_screen.tscn")


func test_every_plant_gets_a_valid_mystery() -> void:
	for index in PlantCatalog.get_count():
		var plant := PlantCatalog.create_plant(index)
		var first := Mystery.make_parameters(plant, 42)
		var again := Mystery.make_parameters(plant, 42)
		var other := Mystery.make_parameters(plant, 43)
		check_equal(first, again, "%s: same seed, same plant" % plant.get_display_name())
		check_true(first != other, "%s: different seed, different plant" % plant.get_display_name())
		for info in plant.get_parameter_definitions():
			if not first.has(info.key):
				continue
			var value: float = first[info.key]
			check_true(value >= info.min_value and value <= info.max_value,
					"%s.%s inside its range" % [plant.get_display_name(), info.key])
			if info.default_value > 0.0:
				var ratio := value / info.default_value
				check_true(ratio >= 1.0 / Mystery.SPREAD - 1e-9 and ratio <= Mystery.SPREAD + 1e-9,
						"%s.%s within the spread" % [plant.get_display_name(), info.key])


func test_mystery_mode_in_the_ui() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var screen := MainScreenScene.instantiate()
	tree.root.add_child(screen)
	var plant: Plant = screen._simulation.plant
	var original: Dictionary = plant.parameters.duplicate()
	screen._set_mystery(true)
	check_true(plant.parameters != original, "parameters changed")
	check_true(not screen._parameter_panel._sliders.values()[0].visible, "sliders hidden")
	check_true(screen._equations_view.hide_plant, "plant equation hidden")
	screen._equations_view.refresh()
	check_true(screen._equations_view.text.contains("Hidden"), "equations tab says hidden")
	var first_mystery: Dictionary = plant.parameters.duplicate()
	screen._on_new_mystery()
	check_true(plant.parameters != first_mystery, "New mystery re-rolls")
	screen._parameter_panel._on_reveal()
	check_true(screen._parameter_panel._reveal_label.visible, "Reveal shows the values")
	screen._set_mystery(false)
	check_equal(plant.parameters, original, "turning it off restores the scenario's values")
	check_true(screen._parameter_panel._sliders.values()[0].visible, "sliders back")
	screen.queue_free()
