# Control Lab architecture

This file describes the code as it stands now (Milestone D, in progress). README.md is the spec; this is the map.

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
plants/plant_catalog.gd     every plant type (used by the tests to cover all plants)
scenarios/       scenario files (.tres, data only): what the toolbar's picker lists
core/scenario.gd, core/scenario_catalog.gd   the Scenario resource and the folder scan
controllers/     Controller base class, ManualController, PidController
signal_blocks/   SetpointGenerator (constant/step/square/ramp/sine), TrapezoidalProfile,
                 Sensor (noise/quantization/delay/low-pass), Actuator (deadband/saturation/slew),
                 DisturbanceGenerator (step/random/poke/parameter drift)
core/delay_line.gd          fixed-step delay buffer (sensor delay, plant dead time)
core/save_store.gd          the student's save file: schema, validation, temp-file writes, save codes
core/csv_export.gd          a run as CSV (README 7.8)
core/web_platform.gd        ALL browser-only code (downloads, file picker, persistent storage)
core/step_metrics.gd        rise time, overshoot, settling, steady-state error, IAE, effort
ui/              main screen, toolbar, setpoint bar, sliders, strip chart, term bars, metrics bar,
                 panels (controller, PID + feedforward + advanced PID, snapshots, setpoint,
                 sensor & actuator, disturbances, parameters, settings, display & graphics, save & export),
                 block diagram, equations view, ghost runs, DisplaySettings, colour language
plants/common/ghost.gdshader  the glowing setpoint-ghost material
tests/           in-engine test runner, test scripts, test-only plants/controllers
docs/            these notes
```

`modes/` from README §9 will be created when its stage begins (20).

## Scenarios (stage 15)

A `Scenario` resource bundles a plant script, plant parameters, the start mode, notes, and override dictionaries for the PID, setpoint, motion profile, sensor, actuator and disturbances (README §9: "scenarios are data"). See `docs/writing_a_scenario.md`. Loading one (`main_screen._load_scenario`) happens in this order:
1. `create_plant()`.
2. Controllers.
3. Each panel's plant-scaled `apply_defaults()`.
4. `apply_settings()`, which applies the overrides by variable name. An unknown name is a warning in the app and a failure in `test_scenarios.gd`.
5. The UI is built, and only *reads* the resulting values.

Reset restarts the run but keeps the student's changes. Choosing the scenario again reloads it. The Notes tab (first tab, right of the output plot) shows the scenario's notes.

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
* `DisturbanceGenerator`: a step load, a random load (Ornstein–Uhlenbeck: smooth wandering), a poke, and parameter drift. Clicking the plant view (without dragging) pokes +, right-click pokes −. Drift multiplies one plant parameter at a set time, and `reset()` restores it *before* the initial state is computed. Disturbance values are plotted on the **Load** tab.
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

The bottom area has the output chart on the left and tabs on the right: Command, P/I/D terms (plus FF), Error, Load (disturbance), Diagram and Equations. The term plot uses separate lines rather than stacked areas (see the Milestone B review notes). The PID panel also shows live P/I/D/Sum bars. `StripChart` reads a `RunRecorder` (a ring buffer, 120 s at 100 Hz). Features: multiple traces, legend, auto/locked Y axis, nice ticks (`ChartAxis`), hover readout, and scrubbing while paused (drag). It decimates by keeping the min and max per pixel column. Colours come from `SignalColors`. The setpoint is always dashed, so colour is never the only cue.

## Snapshots and ghosts (stage 16)

**Tuning slots A–D** (side panel › Snapshots): **Save** stores `PidController.get_tuning()`, which is every PID setting (gains, switches, feedforward), built from the script's variable list so new settings are included automatically. **Load + rerun** applies a slot's tuning, switches to PID, rebuilds the PID panel, and restarts from t = 0 with the same seed. Slots are kept per scenario for the session; saving them to disk is stage 19.

**Ghost runs**: every Reset (and every Load) turns the run that is ending (if it lasted ≥ 1 s) into a `GhostRun`, a trimmed copy of its recorder. The newest 3 are drawn faded behind the live lines, for traces marked `ghost = true` (Measured, Applied). A ghost is labelled with a slot letter only if the whole run used that slot's exact tuning in PID mode; otherwise it is "run N". Ghosts are cleared when the scenario changes, because a different plant isn't comparable. Plot options: **Ghosts** on/off and **Clear ghosts**.

## Teaching tabs (stage 17)

* **Diagram** (`ui/block_diagram.gd`) draws the loop from README §3 with the 2D API.
  * Each wire shows its symbol above and its live value below, in that signal's plot colour.
  * Sensor and actuator list the effects that are on, with an amber border when any is on. The actuator turns red ("SATURATED") when it clips. The controller says "(clipped)" when the PID's own limits clip.
  * Clicking a block opens and scrolls to its side-panel section.
* **Equations** (`ui/equations_view.gd`) shows `Plant.get_equation_text()` and `Controller.get_equation_text()`: the ODE and the discrete PID update with the current numbers substituted in. It refreshes 8× per second. Each plant writes its own maths next to its code (override `get_equation_text`; the base class falls back to listing the state and its rate of change). The ODE uses `Simulation.plant_input`, the input after any dead time.
* Transfer-function forms wait for the Advanced Math setting.

## Screen size and text sizes

The UI is designed at **1920×1080** (`window/size/viewport_*`) and stretched (`canvas_items`, aspect `expand`) to the real window. On a 1280×720 window, or a smaller itch.io embed, everything is drawn at 2/3 size, evenly.

* Built-in controls are scaled by `gui/theme/default_theme_scale = 1.5`: default font 24 px, plus bigger checkboxes, scroll bars and margins.
* **All other text sizes come from `ui/ui_style.gd` (`UiStyle`).** Nothing is smaller than `UiStyle.SMALLEST` (20 px at 1080p).
  * Explanatory text uses `UiStyle.make_hint()`, which wraps it and uses the lighter hint colour.
  * Long explanations that aren't needed on screen are tooltips (e.g. the motion-profile checkbox).
* Custom-drawn controls (charts, term bars, block diagram) take their fonts from `UiStyle` and their geometry from their own constants, which are sized for 1080p.
* **When you add UI, use `UiStyle`, not literal font sizes.**

## Presenter mode and graphics (stage 18)

`ui/display_settings.gd` (`DisplaySettings`) holds app-wide display choices as static variables.

* **Graphics:** each effect has its own switch: MSAA, shadows, 3D resolution, flywheel motion blur, and the glowing ghost. The Low / Medium / High presets set them all at once, and changing one switch makes the preset "Custom". `PlantView.apply_graphics()` rebuilds the 3D visual so lights and materials pick up the changes (the camera resets).
* **Presenter mode** (F2 or the toolbar button):
  * Sets the window's `content_scale_factor` to 1.25.
  * Plots get 1.7× thicker lines and black backgrounds; the page background turns black.
  * The advanced side-panel sections are hidden (snapshots, plant parameters, simulation settings, save).
  * The toolbar drops Seed and the "Time scale" title so it still fits. `test_presenter_layout_fits` checks the whole layout's minimum size against 1920×1080 / 1.25. **If you add toolbar items, run that test.**
* **Setpoint ghost:** `plants/common/ghost.gdshader` gives a rim glow and a slow pulse. `make_ghost_material()` falls back to a flat colour when the effect is off.
* **Saturation highlight:** while the actuator or the PID's own limit clips the command, the plant view shows a red "SATURATED" badge, and the Diagram tab turns the actuator red. `PlantVisual3D.show_saturation()` is a hook for plant-specific cues.

## Saving and export (stage 19, README §7.8, §7.10, §7.11)

* **`SaveStore`** holds the one save file, `user://save.json`. It contains:
  * settings (graphics, presenter mode, last scenario),
  * tuning snapshots per scenario (keyed by scenario title, so renaming a scenario orphans its snapshots),
  * empty `challenges` / `lessons` sections reserved for Milestone E.
* **Rules** (README §7.10):
  * Saves are JSON only, never Godot resources.
  * Every load path goes through `SaveStore.validate()`: disk, imported file and pasted save code alike. Unknown keys are dropped. Values are converted to the expected type or replaced by their default. A snapshot's wrong-typed values are dropped, so loading leaves those settings unchanged.
  * A file that doesn't parse is renamed `save.corrupt-<time>.json`, and the student is told.
  * Writes go to `save.json.tmp`, which is closed (this flushes to IndexedDB on the Web) and then renamed over `save.json`.
  * There's a `schema_version` plus `migrate()` for future format changes.
* **Autosave:** `main_screen.gd` saves 1.5 s after the last change, never on quit (browsers don't reliably send a quit event). A change made in the last 1.5 s before a tab closes is therefore lost.
* **Save & export panel** (`ui/save_panel.gd`):
  * Export run (CSV): `CsvExport` writes `#` comment lines (scenario, controller and gains, seed, rates, units), then one row per controller tick in SI units.
  * Export / Import save file.
  * Copy / Paste save code: `CLAB1:` + base64(gzip(JSON)).
  * Reset all progress, which asks for confirmation.
* **Web vs desktop:** on the Web, files go through `WebPlatform`: `JavaScriptBridge.download_buffer` for downloads and a hidden `<input type=file>` for import. `WebPlatform` also asks for persistent storage (often refused inside itch.io's iframe; that's fine). On desktop, the panel uses Godot's FileDialog (native).
* **Verified in a Chrome Web build:**
  * The save lands at `/userfs/control_lab_7f3k2q/save.json` in IndexedDB.
  * The scenario and presenter mode survive a page reload.
  * The CSV and save downloads have the right contents.
  * Importing through the browser file picker applies the file.
* **Tests:** the test runner points `SaveStore.save_path` at `user://test_saves/` and deletes it afterwards, so tests never touch a real save.

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
| `presenter_toggle` | F2 (presenter mode) |

Mouse: drag the plant view to orbit and scroll to zoom. Click it to poke the plant, and right-click to poke the other way. The mouse wheel never changes slider values; it only scrolls panels.

Sliders and buttons do not take keyboard focus, so these keys always reach the app. The exception is while typing in a number field.
