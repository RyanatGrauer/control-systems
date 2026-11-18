# Control Lab architecture

This file describes the code as it stands now (Milestone C). README.md is the spec; this is the map.

## Folder layout

```
core/            simulation clock, integrators, Simulation (one run), recorder, plant base class, storage paths
plants/common/   PlantVisual3D base class, orbit camera, grid floor shader
plants/common/   ...also MeshBuilders (coil spring, arrow)
plants/flywheel/ plant #1: physics (flywheel_plant.gd) + 3D visual (flywheel_visual.tscn/.gd)
plants/hotend/   plant #2 (temperature, dead time, heat-only)
plants/mass_spring_damper/  plant #3
plants/servo/    plant #4 (DC motor position)
plants/elevator/ plant #5 (gravity, static friction, hard stops)
plants/plant_catalog.gd     list of plants for the toolbar picker (replaced by scenarios in stage 15)
controllers/     Controller base class, ManualController, PidController
signal_blocks/   SetpointGenerator (constant/step/square/ramp/sine), TrapezoidalProfile,
                 Sensor (noise/quantization/delay/low-pass), Actuator (deadband/saturation/slew),
                 DisturbanceGenerator (step/random/poke/parameter drift)
core/delay_line.gd          fixed-step delay buffer (sensor delay, plant dead time)
core/step_metrics.gd        rise time, overshoot, settling, steady-state error, IAE, effort
ui/              main screen, toolbar, panels (controller, PID + feedforward + advanced PID, setpoint,
                 parameters, settings,
                 sensor & actuator, disturbances), setpoint bar, sliders, strip chart,
                 term bars, metrics bar, colour language
tests/           in-engine test runner, test scripts, test-only plants/controllers
docs/            these notes
```

`scenarios/` and `modes/` from README §9 will be created when their stages begin (15 and 20).

## The big rule: the simulation never depends on the UI

```
          SimClock                  Simulation (core/simulation.gd)                     UI (ui/*)
 frame ──► how many fixed  ──► step_physics() × N ──► RunRecorder ──────────► StripChart (reads)
 delta     substeps?             │                     state, signals ───────► PlantView, readouts (read)
                                 │
                 setpoint ─► controller ─► actuator ─► plant ODE (Integrators) ─► sensor
```

* `Simulation` is a plain `RefCounted` object. Tests create one and call `step_physics()` with no scene tree at all.
* The UI **reads** the simulation (state, signals, recorder). It **writes** only settings and controller inputs (manual slider, target, plant parameters, controller rate, integrator).
* Visuals (`PlantVisual3D`) receive state and draw it. They never change physics.

## One physics substep (`Simulation.step_physics`)

0. Push the true output into the sensor's delay history, and update the disturbance `d(t)`.
1. If this step is a controller tick (every `controller_period_steps` steps): setpoint (through the motion profile if on) → sensor → controller → actuator. The result is **held** until the next tick (zero-order hold).
2. If this step is a record tick (100 Hz): record every signal at the current time.
3. Integrate the plant ODE across `dt` (RK4 by default, semi-implicit Euler optional). If the plant has dead time (`Plant.get_input_dead_time()`, the hotend), the ODE sees the applied input from that long ago. Before t = 0 the delayed input is 0.
4. `plant.apply_constraints()`: event logic such as the elevator's hard stops.
5. `step_count += 1`. Time is always `step_count * dt`, so rounding never accumulates.

The controller period is a whole number of physics steps. A requested rate of 30 Hz at 1 kHz physics becomes every 33 steps, which is 30.3 Hz. The settings panel shows the actual rate.

## Clocks (`SimClock`)

Each frame: `accumulator += real_delta * time_scale`, then run `floor(accumulator / dt)` substeps. A slow frame or a hidden browser tab is capped at `MAX_STEPS_PER_FRAME`. The backlog is dropped, simulated time slows down, and the toolbar shows **SLOW**. Steps are never skipped *inside* the simulation, so results stay exact. The tests check that different frame-time patterns give bit-identical recordings.

## Plants

A plant extends `Plant` and describes itself with `QuantityInfo` metadata: parameters, state components, input, output, and disturbance. That metadata drives the UI: `ParameterPanel` makes one slider per parameter automatically. All values are SI. `QuantityInfo.display_unit` / `display_scale` tell the UI how to show them (rad/s → RPM), and the conversion happens only in UI code. See `docs/adding_a_plant.md`.

## Sensor, actuator and disturbances (stages 10 and 14)

Every non-ideality is a separate checkbox, off by default (side panel: **Sensor & actuator**, **Disturbances**).
* `Sensor`: delay → noise → quantization → low-pass, in that order. Its delay reads a `DelayLine` filled every physics substep, so it's exact to 1 ms. While any sensor effect is on, the output plot also shows the green **True** output.
* `Actuator`: deadband → saturation → slew limit. This is separate from the PID's own "Limit output" (the controller's limits, which anti-windup watches).
* `DisturbanceGenerator`: a step load, a random load (Ornstein–Uhlenbeck: smooth wandering), a poke, and parameter drift. Clicking the plant view (without dragging) pokes +, right-click pokes −. Drift multiplies one plant parameter at a set time, and `reset()` restores it *before* the initial state is computed. Disturbance values are plotted on the **Disturbance** tab.
* Slider ranges for all of these are scaled from each plant's own input/output/disturbance ranges, so there is no per-plant UI code.

## Determinism

Every run owns `Simulation.rng`, seeded from the toolbar's **Seed** box on Reset. Anything random (noise, random disturbances) must draw from that RNG and nowhere else. Same seed + same settings = bit-identical run (tested).

## Controllers

`PidController` is parallel-form PID with optional output limits. The exact discrete update is written in its header comment: P = Kp·e, I += Ki·e·Δt, D = Kd·Δe/Δt on error, and D = 0 on the first tick. The integral stores the already-Ki-weighted sum, so changing Ki live never makes the output jump.

Stage 11 features are all **off by default**, so students see each problem before its fix. They are in the PID panel's **Advanced PID** section, each with a one-sentence explanation:
* derivative on measurement;
* a first-order D filter (time constant Tf);
* anti-windup: none / clamping (conditional integration) / back-calculation (tracking gain Kb);
* forward-Euler or trapezoidal integration;
* setpoint weighting (b, c);
* bumpless transfer.

The same section shows the gains in ISA form (Ti = Kp/Ki, Td = Kd/Kp).

**Bumpless transfer** (`Controller.take_over()`, on by default): Manual → PID preloads the integral so the first PID command equals the last manual one. This only happens when Ki > 0, because with Ki = 0 the preload would never decay. PID → Manual sets the manual slider to the last command.

**Feedforward** (stage 13, PID panel › Feedforward): FF = kS·sign(v) + kV·v + kA·a + kG, with kG optionally × cos(measured angle). The controller gets the reference velocity v and acceleration a from `Simulation`:
* for a speed output (`Plant.output_is_rate()`, the flywheel), v is the setpoint itself;
* for position outputs, v and a come from the **trapezoidal motion profile** (Setpoint panel › "Smooth with a motion profile"), and are zero without one.

The profile re-plans from its current position *and* velocity whenever the target changes, so Flip mid-move stays smooth. Each plant gives its own FF slider ranges (`get_feedforward_definitions()`); the ideal values are noted in each plant's comments.

The Controller section switches Manual ⇄ PID without resetting the run (`Simulation.set_controller`). Each controller reports its term contributions (`get_term_contributions()`), and the Simulation records them as `p_term`, `i_term`, `d_term`, `ff_term` and `controller_sum` (the sum *before* output limits).

Each plant supplies its own PID slider ranges and defaults through `get_pid_gain_definitions()`. Every plant starts **P-only**. Gain sliders are logarithmic with a "zero" stop at the far left.

## Metrics

`StepMetrics.analyze_recorder()` measures the **true output's** response to the most recent setpoint change. It is computed 4× per second, not every frame. The definitions are in the file header. Notable choices:
* Rise time and settling are measured against the **setpoint**, not the final value. A P-only loop that stops short therefore shows "-", which is part of the lesson.
* Steady-state error is shown only once the output has stopped moving.

## Plots

The bottom area has the output chart on the left and tabs on the right: Command, P/I/D terms (plus FF), Error, and Disturbance. The term plot uses separate lines rather than stacked areas (see the Milestone B review notes). The PID panel also shows live P/I/D/Sum bars. `StripChart` reads a `RunRecorder` (a ring buffer, 120 s at 100 Hz). Features: multiple traces, legend, auto/locked Y axis, nice ticks (`ChartAxis`), hover readout, and scrubbing while paused (drag). It decimates by keeping the min and max per pixel column. Colours come from `SignalColors`. The setpoint is always dashed, so colour is never the only cue.

## Storage (README §7.10–7.11)

`project.godot` sets `application/config/custom_user_dir_name = "control_lab_7f3k2q"`. **Verified** in a Chrome Web build (Godot 4.7.2): `user://` resolves to `/userfs/control_lab_7f3k2q`, inside the IndexedDB database `/userfs` that all Godot games on a domain share. Our folder name keeps us apart from other itch.io games. On desktop it is `~/Library/Application Support/control_lab_7f3k2q` (macOS) or the equivalent folder on other systems. `core/storage_paths.gd` is the only place that builds save paths, and it warns at startup if the setting is lost. **Never rename this folder after release.**

## Running things

| What | How |
|---|---|
| App | Open the project in Godot 4.7 and press Play (main scene `ui/main_screen.tscn`). |
| Tests (editor) | Open `tests/test_runner.tscn` and use Run Current Scene (F6). Results appear in Output. |
| Tests (command line) | `godot --headless --path . res://tests/test_runner.tscn` (exit code 0 = all passed). Any engine/script error during a test fails it (the runner listens through `OS.add_logger`). `test_ui_smoke.gd` builds the real UI and drives every plant and mode. |
| Web build | `godot --headless --path . --export-release "Web" build/web/index.html`, then serve `build/web/` with any static server (e.g. `python3 -m http.server`). No special headers needed (threads off). |

## Keyboard (InputMap actions, remappable in Project Settings › Input Map)

| Action | Default key |
|---|---|
| `sim_toggle_pause` | Space |
| `sim_reset` | R |
| `sim_step` | . (period) |
| `manual_command_up` / `manual_command_down` | Up / Down arrows (hold), Manual mode |
| `gain_select_p` / `gain_select_i` / `gain_select_d` | P / I / D, PID mode |
| `gain_nudge_up` / `gain_nudge_down` | ] / [ (×1.1 / ÷1.1 on the selected gain; from 0, ] jumps to 1% of the gain's max) |
| `setpoint_flip` | S (swap target and start level, to re-trigger a step response) |

Mouse: drag the plant view to orbit and scroll to zoom. Click it to poke the plant, and right-click to poke the other way. The mouse wheel never changes slider values; it only scrolls panels.

Sliders and buttons do not take keyboard focus, so these keys always reach the app. The exception is while typing in a number field.
