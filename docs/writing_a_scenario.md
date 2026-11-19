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
| **Start Mode** | Manual (students are the controller), PID, or Cascaded PID (only for plants with an inner loop: arm, drone). |
| **Mystery Mode** | Start with a mystery plant: the parameters are random (½× to 2× normal) and hidden. Students can also switch this on themselves under Plant parameters. |
| **Cascade Outer / Inner Settings** | Overrides for the cascade's two PIDs, same names as Pid Settings (e.g. `gravity_gain: 9.81` on the inner loop for the drone's hover feedforward). |
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

## Making it a challenge (stage 20)

A scenario becomes a challenge when its **Challenge** field is set. In the inspector, choose New Challenge and fill it in. The app then adds a Challenge tab with a Run test button, a results table and the student's best score. The goal also appears at the top of the Notes tab.

| Field | Meaning |
|---|---|
| Goal | One or two sentences telling the student what to achieve. |
| Duration S | Length of the test run, in seconds (at most 60). |
| Random Seed | Fixed seed, so every student's test has the same noise. |
| Start Level, Target Level | The setpoint steps from Start Level to Target Level, in **SI units** (rad/s, rad, m, °C). For example, 3000 RPM is 314.159 rad/s and 90° is 1.5708 rad. |
| Step Time S | When the step happens. |
| Load Enabled, Load Force, Load Time S | Optional constant disturbance that switches on mid-test, in the plant's disturbance units (N·m, N, W). |
| Specs | The goals, as `name: limit`. Every spec means "at most this much". Leave a spec out to not grade it. |

Spec names:

| Name | Graded value |
|---|---|
| `rise_time_s` | 10%→90% rise time (s) |
| `overshoot_percent` | Overshoot, % of the step |
| `settling_time_s` | Time until the output stays within ±2% of the step (s) |
| `steady_state_error` | \|error\| over the last 0.5 s before the load, or before the end (SI output units) |
| `iae` | Integral of \|error\| over the step part (output·s) |
| `peak_input` | Largest \|input\| during the whole test (SI input units) |
| `effort` | Integral of input² over the whole test |
| `load_peak_error` | Largest \|error\| after the load switches on (SI output units) |
| `load_recovery_s` | Time after the load until the output is back within ±2% for good (s) |

A value that can't be measured counts as a fail. Examples: a loop that never settles, or a "steady-state" error that never becomes steady. **Score** = % of specs met. Between equal scores, the lower IAE is better.

**What the test uses.** Everything comes from the scenario file except the student's PID tuning: the plant parameters, sensor and actuator settings, and random disturbances. The physics rate is always the default 1 kHz. So the panels the student fiddled with don't matter, and every computer gives the same grade.

**Make sure it's possible.** Add your challenge's title and a tuning that passes to `REFERENCE_TUNINGS` in `tests/test_challenges.gd`. The tests then check two things: that the tuning scores 100, and that the plant's default gains do **not** pass. Finding the reference tuning by hand is part of writing the challenge. (The shipped ones were found by a grid search, see the Milestone E notes.)

## Making it a guided lesson (stage 21)

A scenario becomes a guided lesson when its **Lesson** field is set (choose New Lesson in the inspector). The app adds a **Lesson** tab, placed first and already selected. It shows one step at a time, with Back / Next / Start over buttons. Progress is saved on each computer, so a student who reloads continues where they stopped. Finishing a lesson unlocks every control.

| Field | Meaning |
|---|---|
| Hidden Controls | Controls the student can't see at all. |
| Locked Controls | Controls the student can see but not change (greyed out). Their keyboard shortcuts are blocked too. |
| Steps | The steps, in order. Each one is a LessonStep. |

Each **LessonStep** has:

| Field | Meaning |
|---|---|
| Prompt | What to do, in one to three short sentences. |
| Check | Leave it empty and Next is always available. Otherwise use a check name from the table below; Next stays disabled until the check passes. Once it passes, it stays passed. |
| Check Value | The number the check compares against, in **SI units** (or %, s, cycles). |
| Unlock Controls | Controls that become visible and usable from this step on. For example, unlock `ki` only once P has been explored. |

Control names: `controller_mode`, `kp`, `ki`, `kd`, `output_limits`, `feedforward`, `advanced_pid`, `snapshots`, `setpoint` (the section, the setpoint bar and the S key), `sensor_actuator`, `disturbances`, `plant_parameters`, `simulation_settings`, `poke` (clicking the plant).

Checks:

| Check | Passes when |
|---|---|
| `mode_pid`, `mode_manual` | The controller menu is on PID / Manual. |
| `kp_at_least`, `ki_at_least`, `kd_at_least` | The gain is at least Check Value (SI gain units, as in the gain sliders). |
| `ki_zero`, `kd_zero` | The gain is exactly 0. |
| `time_at_least` | The run has lasted at least Check Value seconds. |
| `overshoot_at_least` | The current run's step overshoots by at least Check Value %. |
| `overshoot_at_most` | The current run has finished its step (settled or steady), with at most Check Value % overshoot. |
| `steady_state_error_at_most` | The current run settles within Check Value (SI output units) of the target. |
| `oscillating` | The output swung back and forth at least Check Value times in the last 10 s. |

The last four are **run checks**. They only count a run that used the current tuning from t = 0, so the student must press Reset after changing the gains, just as in a real step test. The Lesson tab tells the student this.

**Make sure every step can be done.** Add a test to `tests/test_lessons.gd`, like `test_flywheel_lesson_can_be_completed`. It plays each run check headlessly with gains a student might choose, and also checks that the starting gains don't already pass.

**Technical note:** in your own scripts, use `Array[String]` for lists of names, not `PackedStringArray`. In Godot 4.7.2, PackedStringArray lists in a scenario file loaded empty in the Web build. A test now guards against this.
