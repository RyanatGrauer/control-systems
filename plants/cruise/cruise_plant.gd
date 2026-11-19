# cruise_plant.gd
#
# PURPOSE
#   Plant #7: a car's cruise control on a hilly road. We control its SPEED.
#   Main lesson (README section 5): disturbance rejection. The hills push and
#   pull on the car all the time, which is a different job from following a
#   setpoint change. Watch the I term take over the "hill" force.
#
# MODEL (all SI units)
#   F = drive force [N] (the input; negative = braking). The road's height
#   follows gentle sine-wave hills along the distance travelled x:
#       grade(x) = G·sin(2π·x/λ)            (rise over run, e.g. 0.05 = 5%)
#       m·dv/dt = F - ½·ρ·CdA·v·|v| - Crr·m·g·tanh(v/0.5)
#                   - m·g·grade/√(1+grade²) - F_wind
#       dx/dt = v
#   tanh smooths rolling resistance to zero at standstill (no chatter). The
#   car can't roll backwards: apply_constraints holds v ≥ 0 (handbrake).
#   F_wind (headwind) is the disturbance.
#
#   Defaults: 1500 kg, 5% hills every 500 m. At 90 km/h, air drag is ~260 N,
#   rolling ~150 N, and a 5% hill adds up to ±735 N.
#
# STATE
#   [0] distance x (POSITION), [1] speed v (RATE)
class_name CruisePlant
extends Plant

const GRAVITY: float = 9.81
const AIR_DENSITY: float = 1.2
const MS_TO_KMH: float = 3.6


func get_display_name() -> String:
	return "Cruise control on hills"


func get_description() -> String:
	return "Your controller sets the engine force (negative = brakes). The hills slow the car going up and speed it up going down. Goal: hold the target speed (orange)."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("mass", "Car mass (m)", "kg") \
			.with_range(500.0, 4000.0, 1500.0) \
			.with_description("Heavier = slower to speed up, and hills pull harder."),
		QuantityInfo.new("drag_area", "Drag area (CdA)", "m²") \
			.with_range(0.2, 2.0, 0.7) \
			.with_description("How much air the car pushes aside. Drag grows with speed squared."),
		QuantityInfo.new("rolling_resistance", "Rolling resistance (Crr)", "") \
			.with_range(0.0, 0.05, 0.01) \
			.with_description("Tyre losses: a small, nearly constant drag."),
		QuantityInfo.new("hill_grade", "Hill steepness (G)", "") \
			.with_range(0.0, 0.12, 0.05) \
			.with_display("%", 100.0) \
			.with_description("Steepest slope of the hills. 0 = a flat road."),
		QuantityInfo.new("hill_length", "Hill length (λ)", "m") \
			.with_range(100.0, 2000.0, 500.0) \
			.with_log_slider() \
			.with_description("Distance from one hilltop to the next."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("distance", "Distance", "m") \
			.as_state(QuantityInfo.StateKind.POSITION),
		QuantityInfo.new("speed", "Speed", "m/s") \
			.with_display("km/h", MS_TO_KMH) \
			.as_state(QuantityInfo.StateKind.RATE),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("force", "Drive force", "N") \
		.with_range(-6000.0, 4000.0, 0.0) \
		.with_description("Positive = engine pushes forward, negative = brakes.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("speed", "Car speed", "m/s") \
		.with_range(0.0, 40.0, 25.0) \
		.with_display("km/h", MS_TO_KMH)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("headwind", "Headwind force", "N") \
		.with_range(-2000.0, 2000.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 20.0])  # cruising at 72 km/h


func output_is_rate() -> bool:
	return true


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var speed := state[1]
	var acceleration: float = (applied_input - get_resisting_force(state[0], speed) - disturbance) \
			/ parameters["mass"]
	return PackedFloat64Array([speed, acceleration])


# No rolling backwards (the driver holds the brake at a standstill).
func apply_constraints(state: PackedFloat64Array) -> PackedFloat64Array:
	if state[1] < 0.0:
		state[1] = 0.0
	return state


func get_output(state: PackedFloat64Array) -> float:
	return state[1]


# TUNABLE: default PID gains (P-only start) and slider maxima.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(300.0, 10000.0, 0.0, 5000.0, 0.0, 2000.0)


func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(500.0, 100.0, 3000.0, 4000.0)


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var x := state[0]
	var v := state[1]
	var m := get_parameter("mass")
	var drag := 0.5 * AIR_DENSITY * get_parameter("drag_area") * v * absf(v)
	var hill := get_hill_force(x)
	var rolling := get_resisting_force(x, v) - drag - hill
	var acceleration := compute_derivative(state, plant_input, disturbance, 0.0)[1]
	return "\n".join([
		"m·dv/dt = F - F_air - F_roll - F_hill - F_wind",
		"%s·dv/dt = %s - %s - %s - %s - %s" % [num(m), num(plant_input), num(drag),
			num(rolling), num(hill), num(disturbance)],
		"F_hill = m·g·grade, grade here = %s%%  (uphill > 0)" % num(get_grade(x) * 100.0),
		"dv/dt = %s m/s²   (v = %s km/h)" % [num(acceleration), num(v * MS_TO_KMH)],
	])


func get_visual_scene_path() -> String:
	return "res://plants/cruise/cruise_visual.tscn"


# --- road and forces (also used by the visual) ---

func get_grade(distance: float) -> float:
	return parameters["hill_grade"] * sin(TAU * distance / parameters["hill_length"])


# Road height above the start, the integral of the grade.
func get_road_height(distance: float) -> float:
	var wavelength: float = parameters["hill_length"]
	return parameters["hill_grade"] * wavelength / TAU * (1.0 - cos(TAU * distance / wavelength))


func get_hill_force(distance: float) -> float:
	var grade := get_grade(distance)
	return parameters["mass"] * GRAVITY * grade / sqrt(1.0 + grade * grade)


# Everything that slows the car (air, tyres, hill), positive = backwards.
func get_resisting_force(distance: float, speed: float) -> float:
	var drag: float = 0.5 * AIR_DENSITY * parameters["drag_area"] * speed * absf(speed)
	var rolling: float = parameters["rolling_resistance"] * parameters["mass"] * GRAVITY \
			* tanh(speed / 0.5)
	return drag + rolling + get_hill_force(distance)
