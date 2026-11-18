# test_signal_blocks.gd
#
# Stage 10: delay line, sensor non-idealities, actuator limits, disturbances.
# Every random effect must be reproducible from the seed (README 4.5).
extends TestCase


func test_delay_line() -> void:
	var line := DelayLine.new(5)
	check_equal(line.read(3), 0.0, "empty line reads 0")
	line.push(1.0)
	check_equal(line.read(3), 1.0, "before it fills, returns the oldest value")
	for value in [2.0, 3.0, 4.0, 5.0, 6.0, 7.0]:
		line.push(value)
	check_equal(line.read(0), 7.0, "newest")
	check_equal(line.read(5), 2.0, "5 pushes ago")
	check_equal(line.read(99), 2.0, "requests past the end clamp to the oldest kept")


func test_sensor_delay_is_exact() -> void:
	var sensor := Sensor.new()
	sensor.configure(0.001)
	sensor.delay_enabled = true
	sensor.delay_s = 0.05
	var rng := RandomNumberGenerator.new()
	for step in 200:
		sensor.record_true_output(float(step))
	# Newest is 199; 50 substeps (50 ms) earlier is 149.
	check_equal(sensor.measure(199.0, 0.199, rng), 149.0, "50 ms delay = 50 substeps")


func test_sensor_quantization() -> void:
	var sensor := Sensor.new()
	sensor.configure(0.001)
	sensor.quantization_enabled = true
	sensor.resolution = 0.25
	var rng := RandomNumberGenerator.new()
	check_near(sensor.measure(1.1, 0.0, rng), 1.0, 1e-12, "rounds down")
	check_near(sensor.measure(1.2, 0.0, rng), 1.25, 1e-12, "rounds up")


func test_sensor_noise_is_seeded() -> void:
	var first := _noisy_samples(7)
	var second := _noisy_samples(7)
	var other := _noisy_samples(8)
	check_true(first == second, "same seed gives identical noise")
	check_true(first != other, "different seed gives different noise")
	var mean := 0.0
	var mean_square := 0.0
	for value in first:
		mean += value / first.size()
		mean_square += value * value / first.size()
	check_near(mean, 0.0, 0.05, "noise mean ~0")
	check_near(sqrt(mean_square - mean * mean), 0.5, 0.05, "noise std ~0.5")


func _noisy_samples(seed_value: int) -> PackedFloat64Array:
	var sensor := Sensor.new()
	sensor.configure(0.001)
	sensor.noise_enabled = true
	sensor.noise_std = 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat64Array()
	for i in 2000:
		samples.append(sensor.measure(0.0, 0.0, rng))
	return samples


func test_sensor_lowpass_step() -> void:
	var sensor := Sensor.new()
	sensor.configure(0.001)
	sensor.lowpass_enabled = true
	sensor.lowpass_tau = 0.1
	var rng := RandomNumberGenerator.new()
	sensor.measure(0.0, 0.0, rng, 0.01)  # starts the filter at 0
	var value := 0.0
	for i in 10:  # 0.1 s = one time constant
		value = sensor.measure(1.0, 0.0, rng, 0.01)
	# Discrete filter: 1 - (tau/(tau+dt))^10 = 1 - (0.1/0.11)^10 ~ 0.614 (~63% continuous).
	check_near(value, 1.0 - pow(0.1 / 0.11, 10.0), 1e-9, "filter after one time constant")


func test_actuator_deadband_saturation_slew() -> void:
	var actuator := Actuator.new()
	actuator.deadband_enabled = true
	actuator.deadband = 0.5
	check_equal(actuator.apply(0.4, 0.01), 0.0, "inside deadband")
	check_equal(actuator.apply(0.6, 0.01), 0.6, "outside deadband")

	actuator.reset()
	actuator.deadband_enabled = false
	actuator.saturation_enabled = true
	actuator.saturation_min = -2.0
	actuator.saturation_max = 3.0
	check_equal(actuator.apply(10.0, 0.01), 3.0, "clamped high")
	check_true(actuator.is_saturated, "reports saturation")
	check_equal(actuator.apply(-10.0, 0.01), -2.0, "clamped low")
	check_equal(actuator.apply(1.0, 0.01), 1.0, "inside limits")
	check_true(not actuator.is_saturated, "no longer saturated")

	actuator.reset()
	actuator.saturation_enabled = false
	actuator.slew_enabled = true
	actuator.slew_rate = 100.0  # 1 unit per 10 ms tick
	check_near(actuator.apply(5.0, 0.01), 1.0, 1e-12, "first tick limited")
	check_near(actuator.apply(5.0, 0.01), 2.0, 1e-12, "second tick limited")
	check_near(actuator.apply(-5.0, 0.01), 1.0, 1e-12, "limited going down too")


func test_disturbance_step_and_poke() -> void:
	var plant := FlywheelPlant.new()
	var generator := DisturbanceGenerator.new()
	generator.step_enabled = true
	generator.step_load = 0.01
	generator.step_time = 1.0
	var rng := RandomNumberGenerator.new()
	check_equal(generator.update(0.5, 0.001, rng, plant), 0.0, "before step time")
	check_equal(generator.update(1.0, 0.001, rng, plant), 0.01, "at step time")
	generator.poke_strength = 0.02
	generator.poke_duration = 0.1
	generator.poke(2.0, -1.0)
	check_near(generator.update(2.05, 0.001, rng, plant), -0.01, 1e-12, "poke adds to step")
	check_near(generator.update(2.2, 0.001, rng, plant), 0.01, 1e-12, "poke has ended")


func test_parameter_drift_and_restore() -> void:
	var plant := FlywheelPlant.new()
	var original := plant.get_parameter("inertia")
	var generator := DisturbanceGenerator.new()
	generator.drift_enabled = true
	generator.drift_key = "inertia"
	generator.drift_factor = 2.0
	generator.drift_time = 1.0
	var rng := RandomNumberGenerator.new()
	generator.update(0.5, 0.001, rng, plant)
	check_equal(plant.get_parameter("inertia"), original, "unchanged before drift time")
	generator.update(1.0, 0.001, rng, plant)
	generator.update(1.001, 0.001, rng, plant)
	check_near(plant.get_parameter("inertia"), original * 2.0, 1e-15, "doubled once, not twice")
	generator.reset(plant)
	check_equal(plant.get_parameter("inertia"), original, "reset restores the parameter")


func test_noisy_run_is_reproducible() -> void:
	var first := _noisy_run(42)
	var second := _noisy_run(42)
	check_true(first == second, "same seed -> identical measurements and disturbance")


func _noisy_run(seed_value: int) -> PackedFloat64Array:
	var simulation := Simulation.new(FlywheelPlant.new(), PidController.new())
	simulation.random_seed = seed_value
	simulation.sensor.noise_enabled = true
	simulation.sensor.noise_std = 5.0
	simulation.sensor.delay_enabled = true
	simulation.disturbance_generator.random_enabled = true
	simulation.disturbance_generator.random_std = 0.002
	simulation.reset()
	var trace := PackedFloat64Array()
	for i in 200:
		simulation.step_many(10)
		trace.append(simulation.measurement)
		trace.append(simulation.disturbance)
	return trace


func test_delay_line_value_before_start() -> void:
	var line := DelayLine.new(10)
	line.value_before_start = 0.0
	line.push(5.0)
	check_equal(line.read(0), 5.0, "newest is real data")
	check_equal(line.read(3), 0.0, "before the run started -> value_before_start")
