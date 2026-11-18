# Control Lab architecture

This file describes the code as it stands now (Milestone A). README.md is the spec; this is the map.

## Folder layout

```
core/            simulation clock, integrators, Simulation (one run), recorder, plant base class, storage paths
plants/common/   PlantVisual3D base class, orbit camera, grid floor shader
plants/flywheel/ plant #1: physics (flywheel_plant.gd) + 3D visual (flywheel_visual.tscn/.gd)
controllers/     Controller base class, ManualController (PID arrives in stage 5)
signal_blocks/   SetpointGenerator, Sensor, Actuator (ideal for now; non-idealities in Milestone C)
ui/              main screen, toolbar, panels, sliders, strip chart, colour language
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

1. If this step is a controller tick (every `controller_period_steps` steps): setpoint → sensor → controller → actuator. The result is **held** until the next tick (zero-order hold).
2. If this step is a record tick (100 Hz): record every signal at the current time.
3. Integrate the plant ODE across `dt` (RK4 by default, semi-implicit Euler optional).
4. `plant.apply_constraints()`: event logic such as hard stops (unused by the flywheel).
5. `step_count += 1`. Time is always `step_count * dt`, so rounding never accumulates.

The controller period is a whole number of physics steps. A requested rate of 30 Hz at 1 kHz physics becomes every 33 steps, which is 30.3 Hz. The settings panel shows the actual rate.

## Clocks (`SimClock`)

Each frame: `accumulator += real_delta * time_scale`, then run `floor(accumulator / dt)` substeps. A slow frame or a hidden browser tab is capped at `MAX_STEPS_PER_FRAME`. The backlog is dropped, simulated time slows down, and the toolbar shows **SLOW**. Steps are never skipped *inside* the simulation, so results stay exact. The tests check that different frame-time patterns give bit-identical recordings.

## Plants

A plant extends `Plant` and describes itself with `QuantityInfo` metadata: parameters, state components, input, output, and disturbance. That metadata drives the UI: `ParameterPanel` makes one slider per parameter automatically. All values are SI. `QuantityInfo.display_unit` / `display_scale` tell the UI how to show them (rad/s → RPM), and the conversion happens only in UI code. See `docs/adding_a_plant.md`.

## Determinism

Every run owns `Simulation.rng`, seeded from the toolbar's **Seed** box on Reset. Anything random (noise, random disturbances) must draw from that RNG and nowhere else. Same seed + same settings = bit-identical run (tested).

## Plots

`StripChart` reads a `RunRecorder` (a ring buffer, 120 s at 100 Hz). Features: multiple traces, legend, auto/locked Y axis, nice ticks (`ChartAxis`), hover readout, and scrubbing while paused (drag). It decimates by keeping the min and max per pixel column. Colours come from `SignalColors`. The setpoint is always dashed, so colour is never the only cue.

## Storage (README §7.10–7.11)

`project.godot` sets `application/config/custom_user_dir_name = "control_lab_7f3k2q"`. **Verified** in a Chrome Web build (Godot 4.7.2): `user://` resolves to `/userfs/control_lab_7f3k2q`, inside the IndexedDB database `/userfs` that all Godot games on a domain share. Our folder name keeps us apart from other itch.io games. On desktop it is `~/Library/Application Support/control_lab_7f3k2q` (macOS) or the equivalent folder on other systems. `core/storage_paths.gd` is the only place that builds save paths, and it warns at startup if the setting is lost. **Never rename this folder after release.**

## Running things

| What | How |
|---|---|
| App | Open the project in Godot 4.7 and press Play (main scene `ui/main_screen.tscn`). |
| Tests (editor) | Open `tests/test_runner.tscn` and use Run Current Scene (F6). Results appear in Output. |
| Tests (command line) | `godot --headless --path . res://tests/test_runner.tscn` (exit code 0 = all passed) |
| Web build | `godot --headless --path . --export-release "Web" build/web/index.html`, then serve `build/web/` with any static server (e.g. `python3 -m http.server`). No special headers needed (threads off). |

## Keyboard (InputMap actions, remappable in Project Settings › Input Map)

| Action | Default key |
|---|---|
| `sim_toggle_pause` | Space |
| `sim_reset` | R |
| `sim_step` | . (period) |
| `manual_command_up` / `manual_command_down` | Up / Down arrows (hold) |

Sliders and buttons do not take keyboard focus, so these keys always reach the app. The exception is while typing in a number field.
