# mass_spring_damper_plant.gd
#
# PURPOSE
#   Plant #3: a block on a spring with a damper, pushed by a force. We control
#   its POSITION. Second-order system. Main lessons (README section 5): natural
#   frequency, damping ratio, overshoot vs. settling time, and what D really does
#   (it acts like extra damping).
#
# MODEL (all SI units)
#       m * x'' = F - k * x - c * x' + F_dist
#
#   Symbols: x = position [m] (0 = spring relaxed), x' = velocity [m/s],
#   F = applied force [N] (the input), m = mass [kg], k = spring stiffness [N/m],
#   c = damping coefficient [N·s/m], F_dist = disturbance force [N].
#
#   Natural frequency  wn   = sqrt(k / m)            [rad/s]
#   Damping ratio      zeta = c / (2 * sqrt(k * m))  (< 1 means it oscillates)
#   Defaults: wn ~ 6.3 rad/s (about 1 bounce per second), zeta ~ 0.16.
#
# STATE
#   [0] position x (POSITION), [1] velocity v (RATE)
class_name MassSpringDamperPlant
extends Plant

const METRES_TO_CM: float = 100.0


func get_display_name() -> String:
	return "Mass-spring-damper"


func get_description() -> String:
	return "Your controller pushes the blue block with a force (yellow arrow). The spring pulls it back toward 0 cm and the damper resists motion. Goal: hold the block at the orange ghost."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("mass", "Mass (m)", "kg") \
			.with_range(0.1, 10.0, 1.0) \
			.with_log_slider() \
			.with_description("How heavy the block is. Heavier = slower and bouncier."),
		QuantityInfo.new("stiffness", "Spring stiffness (k)", "N/m") \
			.with_range(1.0, 500.0, 40.0) \
			.with_log_slider() \
			.with_description("How hard the spring pulls back per metre of stretch. Stiffer = faster bouncing."),
		QuantityInfo.new("damping", "Damping (c)", "N·s/m") \
			.with_range(0.0, 40.0, 2.0) \
			.with_description("Friction that grows with speed (like a shock absorber). More = less bouncing."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("position", "Position", "m") \
			.with_display("cm", METRES_TO_CM) \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("velocity", "Velocity", "m/s") \
			.with_display("cm/s", METRES_TO_CM) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("force", "Push force", "N") \
		.with_range(-50.0, 50.0, 0.0) \
		.with_description("The force you push the block with. Positive pushes it right.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("position", "Block position", "m") \
		.with_range(-0.4, 0.4, 0.2) \
		.with_display("cm", METRES_TO_CM)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("disturbance_force", "Disturbance force", "N") \
		.with_range(-50.0, 50.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0])


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var position := state[0]
	var velocity := state[1]
	var mass: float = parameters["mass"]
	var stiffness: float = parameters["stiffness"]
	var damping: float = parameters["damping"]

	var spring_force := -stiffness * position
	var damper_force := -damping * velocity
	var acceleration := (applied_input + spring_force + damper_force + disturbance) / mass
	return PackedFloat64Array([velocity, acceleration])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
# Kp = 100 N/m alone: total stiffness 140 N/m, so it stops ~29% short and rings.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(100.0, 2000.0, 0.0, 2000.0, 0.0, 200.0)


# TUNABLE: feedforward slider maxima. Ideal kV = c (2 N·s/m), kA = m (1 kg).
# (The spring's k·x is a position term, which plain kS/kV/kA/kG can't cancel.)
func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(10.0, 20.0, 10.0, 50.0)


func get_visual_scene_path() -> String:
	return "res://plants/mass_spring_damper/mass_spring_damper_visual.tscn"


# --- analytic helpers (tests, and later the Equations tab) ---

func get_natural_frequency() -> float:
	return sqrt(get_parameter("stiffness") / get_parameter("mass"))


func get_damping_ratio() -> float:
	return get_parameter("damping") / (2.0 * sqrt(get_parameter("stiffness") * get_parameter("mass")))
