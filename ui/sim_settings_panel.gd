# sim_settings_panel.gd
#
# PURPOSE
#   "Advanced" simulation settings: integrator choice, physics rate, and
#   controller rate (README 4.1 / 4.2). Collapsed by default so students are
#   not distracted, but the teacher can open it to SHOW integrator and sampling
#   effects.
#
# HOW IT FITS
#   - Integrator and controller rate change the Simulation LIVE.
#   - Physics rate is stored and applied on the next Reset (changing the
#     substep size mid-run would make the time axis inconsistent).
class_name SimSettingsPanel
extends VBoxContainer

signal physics_rate_changed(new_rate_hz: float)

# TUNABLE: physics rates offered in the menu.
const PHYSICS_RATE_CHOICES_HZ: Array[float] = [250.0, 500.0, 1000.0, 2000.0, 5000.0]

var _simulation: Simulation
var _actual_rate_label: Label


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	add_theme_constant_override("separation", 12)

	add_child(_make_label("Integrator"))
	var integrator_menu := OptionButton.new()
	integrator_menu.focus_mode = Control.FOCUS_NONE
	for kind: Integrators.Kind in [Integrators.Kind.RK4, Integrators.Kind.SEMI_IMPLICIT_EULER]:
		integrator_menu.add_item(Integrators.get_kind_name(kind), kind)
	integrator_menu.select(integrator_menu.get_item_index(simulation.integrator_kind))
	integrator_menu.item_selected.connect(_on_integrator_selected.bind(integrator_menu))
	add_child(integrator_menu)

	add_child(_make_label("Physics rate (applied on Reset)"))
	var rate_menu := OptionButton.new()
	rate_menu.focus_mode = Control.FOCUS_NONE
	for rate in PHYSICS_RATE_CHOICES_HZ:
		rate_menu.add_item("%d Hz" % roundi(rate))
		if is_equal_approx(rate, simulation.physics_rate_hz):
			rate_menu.select(rate_menu.item_count - 1)
	rate_menu.item_selected.connect(_on_physics_rate_selected)
	add_child(rate_menu)

	var controller_rate_info := QuantityInfo.new("controller_rate", "Controller rate", "Hz") \
		.with_range(5.0, 1000.0, Simulation.DEFAULT_CONTROLLER_RATE_HZ) \
		.with_log_slider() \
		.with_description("How often the controller reads the sensor and updates its command. Lower it and watch a good loop go unstable.")
	var controller_rate_slider := LabeledSlider.new()
	add_child(controller_rate_slider)
	controller_rate_slider.setup(controller_rate_info, simulation.get_requested_controller_rate_hz())
	controller_rate_slider.value_changed_si.connect(_on_controller_rate_changed)

	_actual_rate_label = Label.new()
	_actual_rate_label.add_theme_font_size_override("font_size", UiStyle.HINT)
	add_child(_actual_rate_label)
	_update_actual_rate_label()


func refresh() -> void:
	_update_actual_rate_label()


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _on_integrator_selected(index: int, menu: OptionButton) -> void:
	_simulation.integrator_kind = menu.get_item_id(index) as Integrators.Kind


func _on_physics_rate_selected(index: int) -> void:
	physics_rate_changed.emit(PHYSICS_RATE_CHOICES_HZ[index])


func _on_controller_rate_changed(rate_hz: float) -> void:
	_simulation.set_controller_rate_hz(rate_hz)
	_update_actual_rate_label()


func _update_actual_rate_label() -> void:
	# The controller ticks every whole number of physics substeps, so the real
	# rate can differ slightly from the slider (see core/simulation.gd).
	_actual_rate_label.text = "Actual: %s Hz (every %d physics steps)" % [
		NumberFormat.significant(_simulation.get_actual_controller_rate_hz(), 4),
		_simulation.get_controller_period_steps(),
	]
