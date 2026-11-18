# How to write a scenario

A scenario is one file in `res://scenarios/`. It picks a plant, changes any settings you like, and holds your notes for students. You make one in the Godot editor **without writing code**.

## Make a new one

1. In the FileSystem dock, open `scenarios/`, right-click an existing scenario (e.g. `01_flywheel.tres`) and choose **Duplicate**.
2. Name it with a number first. The number sets its place in the scenario menu, e.g. `07_flywheel_noisy.tres`.
3. Double-click it. The **Inspector** shows its fields. Edit them and save (Ctrl/Cmd+S).
4. Run the project. Your scenario is in the menu at the top-left.

## The fields

| Field | What it does |
|---|---|
| **Title** | The name in the scenario menu. |
| **Plant Script** | Which plant. Drag one of these in from `plants/`: `flywheel/flywheel_plant.gd`, `hotend/hotend_plant.gd`, `mass_spring_damper/mass_spring_damper_plant.gd`, `servo/servo_plant.gd`, `elevator/elevator_plant.gd`. |
| **Notes** | Shown in the **Notes** tab. Write a few short numbered steps: what to try, and what to look for. |
| **Start Mode** | Manual (students are the controller) or PID. |
| **Controller Rate Hz** | How often the controller runs (default 100). |

Under **Overrides**, each box is a list of *name → value* pairs. Leave a box empty to keep the defaults. Click **Add Key/Value Pair**, type the name exactly as shown below, and pick the value's type (bool for on/off, float for numbers, int for menu choices).

**All numbers are SI units**: rad/s (not RPM), m (not cm), seconds, volts, newtons, °C. (1000 RPM = 104.72 rad/s; 1° = 0.017453 rad.)

| Box | Useful names |
|---|---|
| Plant Parameters | Each plant's parameter keys. Flywheel: `inertia`, `torque_constant`, `resistance`, `viscous_friction`. Hotend: `heat_capacity`, `thermal_resistance`, `dead_time`, `ambient_temperature`. Mass–spring–damper: `mass`, `stiffness`, `damping`. Servo: `inertia`, `torque_constant`, `resistance`, `viscous_friction`. Elevator: `mass`, `motor_constant`, `resistance`, `static_friction`, `kinetic_friction`, `viscous_friction`. |
| Pid Settings | `proportional_gain`, `integral_gain`, `derivative_gain`, `use_output_limits`, `derivative_on_measurement`, `derivative_filter_enabled`, `derivative_filter_tau`, `anti_windup` (0 none, 1 clamping, 2 back-calculation), `back_calculation_gain`, `integral_method` (0 Euler, 1 trapezoidal), `setpoint_weighting_enabled`, `proportional_setpoint_weight`, `derivative_setpoint_weight`, `feedforward_enabled`, `static_gain`, `velocity_gain`, `acceleration_gain`, `gravity_gain`, `gravity_uses_cosine` |
| Setpoint Settings | `pattern` (0 constant, 1 step, 2 square, 3 ramp, 4 sine), `target_level`, `start_level`, `start_time`, `period`, `ramp_rate`, `amplitude` |
| Simulation Settings | `use_motion_profile`, `bumpless_transfer` |
| Motion Profile Settings | `max_velocity`, `max_acceleration` |
| Sensor Settings | `noise_enabled`, `noise_std`, `quantization_enabled`, `resolution`, `delay_enabled`, `delay_s`, `lowpass_enabled`, `lowpass_tau` |
| Actuator Settings | `deadband_enabled`, `deadband`, `saturation_enabled`, `saturation_min`, `saturation_max`, `slew_enabled`, `slew_rate` |
| Disturbance Settings | `step_enabled`, `step_load`, `step_time`, `random_enabled`, `random_std`, `random_tau`, `poke_strength`, `poke_duration`, `drift_enabled`, `drift_key` (a plant parameter name, as text), `drift_factor`, `drift_time` |

Example (`06_hotend_windup.tres`): Start Mode = PID, Pid Settings = `proportional_gain: 2.0`, `integral_gain: 0.1`, `anti_windup: 0`.

## Checking your scenario

Run the tests (open `tests/test_runner.tscn`, press F6). `test_scenarios.gd` loads **every** scenario. A misspelled name fails the test and tells you which name and which box. In the app, a misspelled name is ignored with a warning in the Output panel.
