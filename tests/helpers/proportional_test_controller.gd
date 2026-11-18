# proportional_test_controller.gd
#
# PURPOSE
#   Test-only controller: u = gain * (setpoint - measurement), plus a little
#   use of the run's RNG via a "noise" term so determinism tests have
#   something random to reproduce. Gives the rate-independence tests a real
#   feedback loop without depending on the (stage 5) PID class.
extends Controller

var gain: float = 0.05
var rng: RandomNumberGenerator = null  # if set, adds +/- noise_volts of noise
var noise_volts: float = 0.0


func compute(setpoint: float, measurement: float, _dt: float) -> float:
	var noise := 0.0
	if rng != null:
		noise = rng.randf_range(-noise_volts, noise_volts)
	return gain * (setpoint - measurement) + noise
