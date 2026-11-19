# simulation.gd
#
# PURPOSE
#   One complete, UI-independent simulation run: the plant, its state, the
#   signal chain (setpoint -> controller -> actuator -> plant -> sensor), the
#   seeded random number generator, and the recorder.
#
# HOW IT FITS
#   - The main screen owns a Simulation and a SimClock. Each frame the clock says
#     how many fixed substeps to run, and the screen calls step_physics() that
#     many times. Tests and (later) batch sweeps call step_physics() directly,
#     with no UI at all (README section 9: "simulation is UI-independent").
#   - UI nodes only READ from this object (and from `recorder`). The only things
#     the UI writes are settings and controller inputs (e.g. the manual slider).
#
# TWO CLOCKS (README 4.1)
#   Physics substeps run at `physics_rate_hz` (default 1000 Hz).
#   The controller runs every `controller_period_steps` substeps (default every
#   10 substeps = 100 Hz). Between controller ticks the applied input is HELD
#   (zero-order hold), exactly like an embedded controller.
#   Because the controller period is a whole number of substeps, the actual
#   controller rate is physics_rate / period (e.g. 30 Hz requested -> period of
#   33 steps -> 30.3 Hz actual). get_actual_controller_rate_hz() reports it.
#
# ONE PHYSICS SUBSTEP (in this exact order, see step_physics()):
#   0. Push the true output into the sensor's delay history; update the
#      disturbance d(t) (DisturbanceGenerator).
#   1. If this step is a controller tick: read setpoint (through the motion
#      profile if on), measure, compute the
#      command, pass it through the actuator. Hold the result.
#   2. If this step is a record tick: record all signals at the CURRENT time.
#   3. Integrate the plant ODE across dt with the held input (delayed by the
#      plant's dead time, Plant.get_input_dead_time(), if any).
#   4. Apply plant constraints (hard stops etc.) between substeps.
#   5. Advance the step counter (time = step_count * dt, so no drift builds up).
class_name Simulation
extends RefCounted

# Channel names stored by the recorder. The CSV export (stage 19) will use these.
# Controller term channels (p/i/d/ff/sum) are zero for controllers without terms.
const RECORDED_CHANNELS: PackedStringArray = [
	"time", "setpoint", "measurement", "true_output", "error",
	"command", "applied_input", "disturbance",
	"p_term", "i_term", "d_term", "ff_term", "controller_sum",
	"inner_setpoint", "inner_measurement",  # cascaded PID only (stage 23), else 0
]

# TUNABLE: defaults for a new run.
const DEFAULT_PHYSICS_RATE_HZ: float = 1000.0
const DEFAULT_CONTROLLER_RATE_HZ: float = 100.0
const DEFAULT_RECORD_RATE_HZ: float = 100.0
const DEFAULT_RECORD_SECONDS: float = 120.0  # how much history the plots can show
const DEFAULT_SEED: int = 12345
const MAX_INPUT_DEAD_TIME_S: float = 10.0    # TUNABLE: longest plant dead time supported

# --- the parts of the loop (replaceable) ---
var plant: Plant
var controller: Controller
var setpoint_generator: SetpointGenerator = SetpointGenerator.new()
var sensor: Sensor = Sensor.new()
var actuator: Actuator = Actuator.new()
var disturbance_generator: DisturbanceGenerator = DisturbanceGenerator.new()
var motion_profile: TrapezoidalProfile = TrapezoidalProfile.new()
var use_motion_profile: bool = false  # smooth setpoint changes (stage 13)
var recorder: RunRecorder

# --- settings ---
var bumpless_transfer: bool = true                             # see set_controller()
var integrator_kind: Integrators.Kind = Integrators.Kind.RK4  # may change live
var physics_rate_hz: float = DEFAULT_PHYSICS_RATE_HZ           # applied on reset()
var random_seed: int = DEFAULT_SEED                            # applied on reset()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()   # owned by the run

# --- live signals (most recent values, SI units) ---
var state: PackedFloat64Array = PackedFloat64Array()
var step_count: int = 0
var setpoint: float = 0.0
var measurement: float = 0.0
var command: float = 0.0
var applied_input: float = 0.0
var disturbance: float = 0.0
var plant_input: float = 0.0        # what the ODE saw: applied input after dead time
var controller_terms: Dictionary = {}  # latest P/I/D/FF contributions (may be empty)

var _physics_dt: float = 1.0 / DEFAULT_PHYSICS_RATE_HZ
var _input_delay: DelayLine = DelayLine.new(1)   # plant dead time (see step 3)
var _requested_controller_rate_hz: float = DEFAULT_CONTROLLER_RATE_HZ
var _controller_period_steps: int = 10
var _record_period_steps: int = 10


func _init(new_plant: Plant, new_controller: Controller) -> void:
	plant = new_plant
	controller = new_controller
	var capacity := int(DEFAULT_RECORD_SECONDS * DEFAULT_RECORD_RATE_HZ)
	recorder = RunRecorder.new(RECORDED_CHANNELS, capacity)
	reset()


# Start a fresh run: initial state, time zero, re-seeded RNG, empty recorder.
# Plant PARAMETERS are kept (a student's slider changes survive a reset).
func reset() -> void:
	_physics_dt = 1.0 / physics_rate_hz
	_controller_period_steps = _compute_period_steps(_requested_controller_rate_hz)
	_record_period_steps = _compute_period_steps(DEFAULT_RECORD_RATE_HZ)

	rng.seed = random_seed
	disturbance_generator.reset(plant)  # first: undoes parameter drift before the initial state
	state = plant.get_initial_state()
	step_count = 0
	command = 0.0
	applied_input = 0.0
	plant_input = 0.0
	disturbance = 0.0
	controller_terms = {}
	controller.reset()
	sensor.configure(_physics_dt)
	_input_delay = DelayLine.new(ceili(MAX_INPUT_DEAD_TIME_S / _physics_dt))
	_input_delay.value_before_start = 0.0  # no input was applied before t = 0
	actuator.reset()
	recorder.clear()
	setpoint = setpoint_generator.value_at(0.0)
	motion_profile.reset(setpoint)
	measurement = plant.get_output(state)


# Advance the simulation by exactly one fixed physics substep.
func step_physics() -> void:
	var time := get_time()

	# 0. Inputs that change every substep: sensor history (for its delay) and
	#    the outside disturbance.
	sensor.record_true_output(plant.get_output(state))
	disturbance = disturbance_generator.update(time, _physics_dt, rng, plant)

	# 1. Controller tick (zero-order hold between ticks).
	if step_count % _controller_period_steps == 0:
		var controller_dt := _controller_period_steps * _physics_dt
		_update_setpoint(time)
		measurement = sensor.measure(plant.get_output(state), time, rng, controller_dt)
		var cascade := controller as CascadeController
		if cascade != null:
			# The inner sensor (e.g. a velocity estimate) is ideal: the
			# sensor panel's noise/delay apply to the main measurement.
			cascade.inner_measurement = plant.get_inner_output(state)
		command = controller.compute(setpoint, measurement, controller_dt)
		controller_terms = controller.get_term_contributions()
		applied_input = actuator.apply(command, controller_dt)

	# 2. Record the signals as they are at the START of this substep.
	if step_count % _record_period_steps == 0:
		_record_sample(time)

	# 3. Integrate the plant ODE across one substep with the held input,
	#    delayed by the plant's dead time if it has one.
	_input_delay.push(applied_input)
	plant_input = applied_input
	var dead_time := clampf(plant.get_input_dead_time(), 0.0, MAX_INPUT_DEAD_TIME_S)
	if dead_time > 0.0:
		plant_input = _input_delay.read(roundi(dead_time / _physics_dt))
	state = Integrators.step(integrator_kind, plant, state, plant_input,
			disturbance, time, _physics_dt)

	# 4. Event logic that ODE solvers handle badly (hard stops, etc.).
	state = plant.apply_constraints(state)

	# 5. Time is derived from the step count so rounding never accumulates.
	step_count += 1


# A short "poke" disturbance starting now (click on the plant view).
func poke(direction: float) -> void:
	disturbance_generator.poke(get_time(), direction)


# Run `count` substeps (used by tests and by the "Step" button).
func step_many(count: int) -> void:
	for i in count:
		step_physics()


# How many substeps make one controller tick (the "Step" button runs this many).
func get_controller_period_steps() -> int:
	return _controller_period_steps


func get_time() -> float:
	return step_count * _physics_dt


func get_physics_dt() -> float:
	return _physics_dt


func get_true_output() -> float:
	return plant.get_output(state)


# Swap in a different controller (e.g. Manual <-> PID) without resetting the
# run. The new controller starts with fresh memory.
# With bumpless_transfer on, the new controller picks up from the last command
# instead of jumping (Controller.take_over()).
func set_controller(new_controller: Controller) -> void:
	controller = new_controller
	controller.reset()
	if bumpless_transfer:
		controller.take_over(command, setpoint, measurement)
	controller_terms = {}


# Controller rate may change LIVE: students lower it during a run and watch a
# well-tuned loop go unstable (README 4.1 "teaching payoff").
func set_controller_rate_hz(rate_hz: float) -> void:
	_requested_controller_rate_hz = rate_hz
	_controller_period_steps = _compute_period_steps(rate_hz)


func get_requested_controller_rate_hz() -> float:
	return _requested_controller_rate_hz


func get_actual_controller_rate_hz() -> float:
	return 1.0 / (_controller_period_steps * _physics_dt)


# Setpoint for this controller tick, through the motion profile if it is on,
# plus the reference velocity/acceleration that feedforward uses.
func _update_setpoint(time: float) -> void:
	var raw_setpoint := setpoint_generator.value_at(time)
	var rate := 0.0
	var rate_of_rate := 0.0
	if use_motion_profile:
		if raw_setpoint != motion_profile.get_goal():
			motion_profile.plan_to(raw_setpoint, time)
		var sample := motion_profile.sample(time)
		setpoint = sample[0]
		rate = sample[1]
		rate_of_rate = sample[2]
	else:
		motion_profile.reset(raw_setpoint)  # so turning it on starts from here
		setpoint = raw_setpoint
	if plant.output_is_rate():
		controller.reference_velocity = setpoint
		controller.reference_acceleration = rate
	else:
		controller.reference_velocity = rate
		controller.reference_acceleration = rate_of_rate


func _compute_period_steps(rate_hz: float) -> int:
	var steps := roundi(physics_rate_hz / rate_hz)
	return maxi(steps, 1)


func _record_sample(time: float) -> void:
	recorder.record({
		"time": time,
		"setpoint": setpoint,
		"measurement": measurement,
		"true_output": plant.get_output(state),
		"error": setpoint - measurement,
		"command": command,
		"applied_input": applied_input,
		"disturbance": disturbance,
		"p_term": controller_terms.get("p", 0.0),
		"i_term": controller_terms.get("i", 0.0),
		"d_term": controller_terms.get("d", 0.0),
		"ff_term": controller_terms.get("ff", 0.0),
		"controller_sum": controller_terms.get("sum", command),
		"inner_setpoint": (controller as CascadeController).inner_setpoint \
				if controller is CascadeController else 0.0,
		"inner_measurement": plant.get_inner_output(state),
	})
