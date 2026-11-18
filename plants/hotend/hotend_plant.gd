# hotend_plant.gd
#
# PURPOSE
#   Plant #2: a 3D-printer hotend (a small heated aluminium block). We control
#   its TEMPERATURE. Main lessons (README section 5): dead time, an actuator
#   that can only push one way (a heater can't cool), slow cooling, integral
#   windup, and why 3D printers run "PID autotune".
#
# MODEL (SI units; temperature in °C, which is an SI derived unit, and
# temperature DIFFERENCES in °C equal kelvin)
#       C * dT/dt = P_heater(t - L) - (T - T_ambient) / R_th - P_fan
#
#   Symbols: T = block temperature [°C], P_heater = heater power [W] (the input,
#   0 ... 40 W, never negative), C = heat capacity [J/K], R_th = thermal
#   resistance to the room [K/W], T_ambient = room temperature [°C],
#   L = dead time [s] (heat takes time to reach the thermistor), P_fan = heat
#   carried away by the part-cooling fan [W] (the disturbance).
#
#   First order + dead time: time constant tau = R_th * C, and
#   steady-state rise per watt = R_th.
#   Defaults: tau = 36 s, 40 W can hold ~265 °C, dead time 1.5 s; heats to
#   200 °C in about 30 s at full power, like a real printer.
#   It heats in tens of seconds but cools slowly, and can't be cooled actively.
#
# STATE
#   [0] block temperature T (°C)
class_name HotendPlant
extends Plant


func get_display_name() -> String:
	return "Hotend temperature"


func get_description() -> String:
	return "Your controller sets the heater power (it can only heat, never cool). The thermistor reads the block temperature a moment late. Goal: hold the target temperature (orange)."


func get_parameter_definitions() -> Array[QuantityInfo]:
	# TUNABLE: default plant parameters and slider ranges.
	return [
		QuantityInfo.new("heat_capacity", "Heat capacity (C)", "J/K") \
			.with_range(2.0, 50.0, 6.0) \
			.with_log_slider() \
			.with_description("Energy needed to warm the block by 1 °C. Bigger = slower to heat and cool."),
		QuantityInfo.new("thermal_resistance", "Thermal resistance (R)", "K/W") \
			.with_range(1.0, 20.0, 6.0) \
			.with_log_slider() \
			.with_description("How well the block is insulated. Bigger = holds heat longer, reaches higher temperatures."),
		QuantityInfo.new("dead_time", "Dead time (L)", "s") \
			.with_range(0.0, 5.0, 1.5) \
			.with_description("How long before the thermistor notices a change in heater power."),
		QuantityInfo.new("ambient_temperature", "Room temperature", "°C") \
			.with_range(0.0, 40.0, 25.0) \
			.with_description("Where the block cools to when the heater is off."),
	]


func get_state_definitions() -> Array[QuantityInfo]:
	return [
		QuantityInfo.new("temperature", "Block temperature", "°C") \
			.as_state(QuantityInfo.StateKind.POSITION),
	]


func get_input_definition() -> QuantityInfo:
	return QuantityInfo.new("heater_power", "Heater power", "W") \
		.with_range(0.0, 40.0, 0.0) \
		.with_description("Electrical power into the heater cartridge. It can't go below 0: heaters can't cool.")


func get_output_definition() -> QuantityInfo:
	return QuantityInfo.new("temperature", "Hotend temperature", "°C") \
		.with_range(0.0, 300.0, 200.0)


func get_disturbance_definition() -> QuantityInfo:
	return QuantityInfo.new("fan_cooling", "Fan cooling", "W") \
		.with_range(-10.0, 10.0, 0.0)


func get_initial_state() -> PackedFloat64Array:
	return PackedFloat64Array([parameters["ambient_temperature"]])


func get_input_dead_time() -> float:
	return parameters["dead_time"]


func compute_derivative(state: PackedFloat64Array, applied_input: float,
		disturbance: float, _time: float) -> PackedFloat64Array:
	var temperature := state[0]
	var heat_capacity: float = parameters["heat_capacity"]
	var thermal_resistance: float = parameters["thermal_resistance"]
	var ambient: float = parameters["ambient_temperature"]
	# Physical limit: a resistive heater only ever adds heat.
	var heater_power := maxf(applied_input, 0.0)
	var heat_loss := (temperature - ambient) / thermal_resistance
	return PackedFloat64Array([(heater_power - heat_loss - disturbance) / heat_capacity])


func get_output(state: PackedFloat64Array) -> float:
	return state[0]


# TUNABLE: default PID gains (P-only start) and slider maxima.
# Kp = 2 W/K alone settles well short of the target; adding Ki fixes that but
# winds up badly during the long warm-up unless anti-windup is on.
func get_pid_gain_definitions() -> Array[QuantityInfo]:
	return make_pid_gain_definitions(2.0, 50.0, 0.0, 5.0, 0.0, 100.0)


# TUNABLE: feedforward slider maxima. kG works as a constant "bias" here;
# holding 200 °C needs (200 - 25)/R ~ 29 W. kV (W per °C/s) ~ C helps ramps.
func get_feedforward_definitions() -> Array[QuantityInfo]:
	return make_feedforward_definitions(10.0, 50.0, 50.0, 40.0)


func get_equation_text(state: PackedFloat64Array, plant_input: float,
		disturbance: float) -> String:
	var t := state[0]
	var c := get_parameter("heat_capacity")
	var r := get_parameter("thermal_resistance")
	var ambient := get_parameter("ambient_temperature")
	var rate := compute_derivative(state, plant_input, disturbance, 0.0)[0]
	return "\n".join([
		"C·dT/dt = P(t - L) - (T - T_room)/R - P_fan",
		"%s·dT/dt = %s - (%s - %s)/%s - %s" % [num(c), num(maxf(plant_input, 0.0)), num(t),
			num(ambient), num(r), num(disturbance)],
		"dT/dt = %s °C/s" % num(rate),
		"P(t - L) is the heater power from L = %s s ago (dead time)." % num(get_parameter("dead_time")),
	])


func get_visual_scene_path() -> String:
	return "res://plants/hotend/hotend_visual.tscn"


# --- analytic helpers ---

func get_time_constant() -> float:
	return get_parameter("thermal_resistance") * get_parameter("heat_capacity")
