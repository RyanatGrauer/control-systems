# Control Lab: A Godot Sandbox for Tuning Control Systems

> **Status:** Blueprint / draft spec. This document is the source of truth for Claude Code.
> Build it in the **stages** below, in order. **Stop for human review at each ⛳ checkpoint.**

---

## 1. Purpose

Control Lab is a teaching tool for high school engineering students. It lets them **tune feedback controllers (mainly PID) on simulated physical systems** and see right away what each change does, both as an animated physical system and as live plots.

The point is to build intuition first and theory second:

- *Feel* the problem: try to control the system by hand, then see what an automatic controller does.
- *See* the cause and effect: every gain change shows up at once in the motion, the plots, and the P/I/D term breakdown.
- *Connect* to the math: the equations, the block diagram, and the discrete-time PID formula are always visible, with live values.
- *Meet real-world messiness*: saturation, noise, delay, friction, and windup can each be switched on one at a time.

The teacher uses it in two ways: **projected on a screen** during demos, and **by students on their own devices** during challenges.

---

## 2. Hard constraints (read first)

1. **Engine:** Godot 4.7 (current stable). The teacher creates the Godot project himself; Claude Code works inside it. **Keep upgrades easy:** use only stable, documented APIs, nothing marked experimental or deprecated, and no engine patches. If something version-specific can't be avoided, isolate it in one place and mark it `# GODOT-VERSION`.
2. **No third-party addons, libraries, or downloaded assets** unless the teacher approves them first. Ask before adding *anything* external. This includes test frameworks, plotting addons, and UI kits.
3. **Readability beats cleverness.** The teacher must be able to read, debug, and change every line. That means:
   - a header comment in every script saying what it is for and how it fits the architecture,
   - descriptive names (`proportional_gain`, not `kp_v`; short math symbols are fine *inside* a formula, with a comment that maps them),
   - no hidden magic: no metaprogramming, no deep inheritance chains, no clever one-liners,
   - constants and tunable values collected in clearly marked places (see §9).
4. **Keep the core in GDScript.** Simulation, controllers, and UI are GDScript so that **Web export works** (GDExtension complicates web builds). C++ GDExtension is **optional and only for heavy batch jobs** (§8). Every C++ feature must have a GDScript fallback that gives the same results.
5. **Physics is our own code, not Godot's physics engine.** Plants are written as ordinary differential equations and integrated by our own fixed-step solver. That makes results deterministic, inspectable, and correct to the textbook. Godot nodes only *show* the state.
6. **Runs on school laptops.** Accuracy and clarity come before visual polish.
7. **SI units inside the code.** The UI may show friendlier units (°C, RPM, cm, degrees), but the conversion happens only at the UI boundary.
8. **Export targets:** Windows, macOS, Linux, and **Web (a first-class target, not an afterthought)**. Mobile is a stretch goal (the UI should not *prevent* it).
9. **Renderer: Compatibility (OpenGL / WebGL2).** Web export only supports the Compatibility renderer. So **all development, shaders, and materials target Compatibility from day one**, and the desktop builds use it too, so everything looks the same on every platform. No Forward+ or Mobile-only features (for example SDFGI, volumetric fog, compute shaders). Test a Web build at the end of every milestone, not just at the end of the project. Export Web **with thread support off** (the default), so the build runs on ordinary static hosting without special server headers. That means the simulation must not depend on worker threads.
10. **3D first.** Plants are shown in 3D wherever it makes sense. 2D is used only where 3D adds nothing or hurts clarity (see §4.4). Plots and UI panels are 2D.

---

## 3. Core concepts and vocabulary

The code should use these words consistently. They match standard control-theory terms.

| Term | Meaning in this project |
|---|---|
| **Plant** | The physical system being controlled (motor, heater, arm...). It holds a state vector and its equations of motion. |
| **State** | The plant's internal variables (for example, position and velocity). |
| **Setpoint / reference (r)** | What we want the output to be. |
| **Measurement (y)** | What the sensor reports. This may be noisy, delayed, or quantized, so it is not always the true state. |
| **Error (e)** | r − y |
| **Controller** | Turns setpoint and measurement into a command. |
| **Command (u)** | The controller's raw output, before the actuator limits it. |
| **Actuator** | Turns the command into a physical input. Saturation, slew rate limits, and deadband live here. |
| **Disturbance (d)** | An outside force or load acting on the plant. |
| **Scenario** | A data file that bundles a plant, its parameters, default controller settings, non-idealities, and (optionally) challenge goals. |
| **Run** | One recorded simulation, from start or reset to stop. |

### Signal flow (one controller tick)

```
 setpoint r ──►(+)── e ──► [Controller] ── u ──► [Actuator] ── u_applied ──► [Plant] ──► true output
               ▲(−)                                                  ▲ disturbance d       │
               │                                                                           │
               └──────────── y ◄── [Sensor: delay, noise, quantization] ◄──────────────────┘
```

---

## 4. Simulation design (the most important section)

### 4.1 Two clocks, deliberately separate

- **Physics rate**: the plant ODE integrates at a high fixed rate (default **1000 Hz**, adjustable).
- **Controller rate**: the controller samples and updates at its own rate (default **100 Hz**, adjustable from about 5 to 1000 Hz). Between ticks the actuator **holds its last value** (zero-order hold), just like real embedded hardware.
- **Render rate**: whatever the display does. The simulation must never depend on the frame rate.

Use a **fixed-timestep accumulator** in `_physics_process` or `_process`: add the elapsed real time (scaled by the time-scale slider), then run as many fixed physics substeps as fit. Cap the substeps per frame so a slow frame can't cause a "spiral of death". If the cap is hit, slow down simulated time and show a small "running slower than real time" indicator rather than skipping steps.

**Teaching payoff:** students can lower the controller rate and watch a well-tuned loop go unstable. That is the sampling and delay lesson for free.

### 4.2 Integrator

- Default: **RK4** (4th-order Runge–Kutta) on the plant state vector.
- Also implement **semi-implicit (symplectic) Euler**, selectable in a debug or advanced menu, so the teacher can *show* integrator differences.
- Hybrid effects that ODE solvers handle badly (hard stops, static friction stick/slip, backlash) are handled **between substeps** as explicit event logic, with clear comments.

### 4.3 Plant interface (logical contract)

Every plant provides:

- a list of **named parameters** with units, defaults, min/max, and a short student-friendly description (this list drives the UI automatically),
- a **state vector** with named components and units,
- a **derivative function**: given state, applied input, disturbance, and time, return d(state)/dt,
- an **output function**: which state value (or combination) is the "controlled variable",
- optional **constraint/event handling** (hard stops, contact),
- a **visual binding**: a separate scene that reads state and animates it. The visual never changes physics.
- optional **linear model data** (A, B, C, D matrices or a transfer function) for the analysis views in §7.4. Nonlinear plants provide a linearization around an operating point.

The plant must not know about the controller, and the controller must not know which plant it drives. They talk only through the signal chain.

### 4.4 Visual presentation

The simulation is the truth and the visuals are a window onto it, but **the window should look good**. Students engage more with something that looks polished.

- **3D by default.** Each plant gets a 3D scene with a camera that frames it well, gentle orbit/zoom controls, and a "reset camera" button. Fixed cameras work best for projection (no camera motion students didn't ask for).
- **2D is allowed when it is clearer.** Candidates include the ball and beam side view and the mass–spring–damper, if a 2D schematic reads better on a projector. Each plant's visual binding declares whether it is 2D or 3D, and the UI hosts either one the same way.
- **Shaders and custom materials are encouraged**, within the Compatibility renderer. Ideas:
  - a heat-glow shader on the hotend that maps temperature to emissive color,
  - motion trails or speed lines on fast-moving parts,
  - a highlight or outline shader on the part currently saturated or at a hard stop,
  - a subtle grid floor and studio-style lighting so objects read clearly,
  - a setpoint "ghost" (translucent copy of the plant at the target position or angle).
- **Visual feedback for physics events:** spring stretch, thruster flame size proportional to thrust, wheel spin blur, and a small shake effect for impacts (optional, can be turned off).
- **Readability first:** a consistent color language across the 3D scene, the plots, and the block diagram (for example, setpoint is always the same color, measurement is always another). Colors must still be distinguishable on a washed-out classroom projector, and the theme should not rely on color alone.
- **Performance budget:** must stay smooth in a browser on a school laptop. Prefer simple meshes, baked or simple lighting, few real-time shadows (one directional shadow at most), and modest post-processing. Every effect has an on/off switch in a Graphics settings panel with a "Low" preset.
- **Assets:** procedural or built from Godot primitives / simple custom meshes for now. No downloaded assets without approval (same rule as §2.2).

### 4.5 Determinism and reproducibility

- All randomness (sensor noise, random disturbances) comes from a **seeded RNG owned by the run**. The same seed and settings give an identical run. The seed is shown in the UI and can be edited.
- This allows fair A/B comparison between tunings, and lets a challenge be graded the same way on every machine.

---

## 5. Plant library (scenarios)

The plants are listed in rough teaching order. Each one exists to teach something specific. Build them in the order given in §10, not all at once.

| # | Plant | Order / type | Main lessons |
|---|---|---|---|
| 1 | **Flywheel / DC motor speed** | 1st order | P alone leaves steady-state error; I removes it; feedforward (kV). Relevant to FTC shooters. |
| 2 | **Hotend / oven temperature** | 1st order + dead time, heat-only (u ≥ 0), slow cooling | Dead time, asymmetric actuators, integral windup, why 3D printers run PID autotune. |
| 3 | **Mass–spring–damper** | 2nd order | Natural frequency, damping ratio, overshoot vs. settling time, what D actually does. |
| 4 | **DC motor position (servo)** | 2nd order with an integrator in the plant | Type-1 systems, why position loops act differently from velocity loops, encoder quantization. |
| 5 | **Elevator / lift with gravity** | 2nd order + constant load | Gravity feedforward (kG), static friction (kS), hard stops at the ends. |
| 6 | **Rotating arm with gravity** | 2nd order, nonlinear (cos θ load) | Feedforward that changes with angle; gains that are "right" at one angle and wrong at another. |
| 7 | **Cruise control on hills** | 1st order + terrain disturbance | Disturbance rejection, which is a different job from setpoint tracking. |
| 8 | **Drone altitude (1D)** | 2nd order, thrust can't go negative, gravity | Saturation, hover feedforward, cascaded loops (altitude → velocity). |
| 9 | **Ball and beam** | 4th order, open-loop unstable-ish | Cascaded control (inner beam angle, outer ball position), why the inner loop must be faster. |
| 10 | **Inverted pendulum on cart** | 4th order, unstable | Stretch goal. PID's limits; a doorway to state feedback / LQR. |

**Every plant has a "mystery mode"**: its parameters are randomized within a range and hidden, so students have to tune by observing, not by calculating.

---

## 6. Controller library

### 6.1 PID (the centerpiece)

A single PID implementation with switchable features. Each feature has an on/off toggle and a one-sentence explanation in the UI.

- **Form:** parallel (Kp, Ki, Kd) by default; optional display in standard/ISA form (Kp, Ti, Td) with automatic conversion. Students should learn that these are the same thing written two ways.
- **Discretization:** document the exact discrete update in the code comments and in the in-app equation panel:
  - P term = Kp · e[k]
  - I term accumulates Ki · e[k] · Δt (forward Euler by default; trapezoidal as an option)
  - D term = Kd · (difference of the chosen signal) / Δt
- **Derivative source:** on error (shows "derivative kick" when the setpoint steps) or on measurement (the fix). The toggle demonstrates the problem directly.
- **Derivative filter:** first-order low-pass with an adjustable time constant or N factor. Needed once noise is turned on.
- **Anti-windup:** none / clamping (conditional integration) / back-calculation (with tracking gain). Pairs with the hotend and drone scenarios.
- **Output limits:** min/max on the command.
- **Setpoint weighting** (b for P, c for D): advanced toggle.
- **Feedforward terms** added to the PID output: kS · sign(v), kV · v_ref, kA · a_ref, kG (constant or cos θ). Matches the conventions FTC/FRC students already see.
- **Integral reset** button and **bumpless transfer** when switching between manual and auto.

The controller exposes **each term's contribution every tick** (P, I, D, FF, total, and post-saturation), so they can be plotted stacked.

### 6.2 Other controllers (so PID has something to be compared with)

- **Manual / human**: the student is the controller (slider, mouse, keyboard, or gamepad). This should be the **first thing students do** in most lessons.
- **Bang-bang** and **on/off with hysteresis** (thermostat-style).
- **Cascaded PID**: an outer loop's output is the inner loop's setpoint. Both loops are tunable and plotted separately.
- **Motion profile + PID**: a trapezoidal profile generates the setpoint (with max velocity and max acceleration settings), and PID plus feedforward tracks it.
- *(Stretch)* **State feedback / LQR** for plants with linear models: Q and R weight sliders, gain K computed and displayed.

### 6.3 Setpoint generators

Step, ramp, square wave (adjustable period), sine (adjustable frequency, which feeds the Bode lesson), trapezoidal profile, and **mouse-drag setpoint** (student drags a target marker in the scene).

---

## 7. User interface

### 7.1 Layout (default screen)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Scenario ▾ │ ▶ ❚❚ ⏭step ⟲reset │ time-scale ━━●━━ │ seed │ Presenter ◐ │
├───────────────────────────────┬──────────────────────────────────────┤
│                               │  Controller panel                    │
│     Animated plant view       │   Kp ━━━●━━━ [  1.20 ]               │
│     (2D or 3D, click to       │   Ki ━●━━━━━ [  0.30 ]               │
│      "poke" = disturbance)    │   Kd ━━●━━━━ [  0.05 ]               │
│                               │   ▸ Advanced (filters, windup, FF)   │
│                               │  Non-idealities panel (toggles)      │
├───────────────────────────────┴──────────────────────────────────────┤
│  Live plots: setpoint vs measurement │ command (raw vs applied) │     │
│  stacked P / I / D / FF contributions │ error                    │     │
│  [ghost traces of previous runs]   Metrics: Mp 12% Tr 0.4s Ts 1.8s… │
├──────────────────────────────────────────────────────────────────────┤
│  Tabs:  Block diagram │ Equations │ Analysis │ Challenge │ Notes    │
└──────────────────────────────────────────────────────────────────────┘
```

Panels should be resizable or collapsible. The animated plant view and the plots are the two things students look at most.

### 7.2 Gain input

- Every gain has **slider + numeric field + fine-adjust**. Gains span orders of magnitude, so sliders use a **logarithmic scale** by default, with a linear option.
- Keyboard shortcuts to nudge the selected gain up or down by ×1.1 / ÷1.1 (for live demos).
- **Changes apply live while the simulation runs.** That is the whole point.
- **Snapshot / compare:** save the current tuning to a named slot (A, B, C...). Switching slots re-runs with the same seed and overlays the results.

### 7.3 Plots (custom-built, no addons)

- Write a reusable **strip-chart Control** that draws with Godot's 2D drawing API, reading from a ring-buffer recorder.
- Features: multiple traces, legend, auto- or fixed-scale axes, grid with readable tick labels, a time-window setting, and hover crosshair readout. Pausing freezes the plot so it can be inspected and scrubbed.
- **Ghost traces:** up to N previous runs drawn faded behind the current one.
- **Shaded spec band** when a challenge is active (for example, the ±2% settling band and the overshoot ceiling).
- Performance: decimate for drawing (keep min/max per pixel column) so long runs stay smooth on laptops.

### 7.4 Teaching tabs

- **Block diagram:** the loop from §3 drawn live. Wires show current values, and blocks light up when they are active or saturated. Clicking a block jumps to its settings.
- **Equations:** the plant's ODE and the discrete PID update rendered as text, with **live numbers substituted in**. Transfer-function and Laplace forms are shown only when Advanced Math is on (§7.9).
- **Analysis** (for plants with linear models). **Hidden by default** (see §7.9):
  - step response with metrics marked on it,
  - pole-zero map of the closed loop that updates as gains change,
  - Bode plot (open loop) with gain and phase margins,
  - *(stretch)* root locus as a single gain sweeps.
  
  Implementation note: compute these from the linear model with our own small math utilities (polynomial roots, complex evaluation, small matrix ops). Write them from scratch, test them, and comment them.
- **Challenge:** see §7.6.
- **Notes:** short, scenario-specific teacher-written text (loaded from the scenario file) that explains what to try.

### 7.5 Non-idealities panel

Each one is an independent toggle with its own parameters, and each is off by default in intro scenarios:

- actuator saturation (min/max), slew-rate limit, deadband
- sensor noise (Gaussian, σ), quantization (encoder counts per unit), measurement delay (samples or ms), sensor low-pass
- Coulomb/static friction, backlash *(stretch)*
- disturbances: step load at time t, impulse "poke" (mouse click in the plant view), random load, terrain (cruise control)
- **parameter drift during a run** (for example, mass doubles at t = 5 s) to show robustness

### 7.6 Modes

1. **Sandbox:** everything unlocked.
2. **Guided lesson:** a scenario file can lock or hide controls and show step-by-step prompts (for example, "Set Ki and Kd to 0. Raise Kp until it oscillates.").
3. **Ziegler–Nichols helper:** guides the student to find the ultimate gain Ku and period Tu (with help measuring the period from the plot), then fills in the classic ZN and Tyreus–Luyben tables. Students then see why ZN tunings are aggressive.
4. **Challenge:** the scenario defines specs (max overshoot %, settling time, steady-state error, max control effort, IAE...). Press "Run test", and a fixed-seed, scripted test sequence runs and is graded pass/fail per spec, with a score. **Results are shown on screen only** (no export or submission in v1). The student's best result per challenge is saved locally (§7.10).
5. **Presenter mode:** large fonts, thick lines, high-contrast theme, simplified panels. Toggled with one key.

### 7.7 Input

Mouse and keyboard only for v1. **No gamepad support for now**, but route manual-control input through Godot's InputMap actions (not hard-coded keys) so a gamepad can be added later without restructuring. Touch-friendly hit sizes where practical.

### 7.8 Data export

- **CSV export of a run**: time, setpoint, measurement, true output, command, applied input, P/I/D/FF terms, disturbance. Header comment row with scenario, gains, seed, and rates. Students can analyze it in Python or a spreadsheet.
- **Save/load tunings** as small human-readable files (JSON or Godot resource text).
- On Web, export by browser download.

### 7.9 Advanced Math toggle

The default experience is time-domain only: motion, plots, gains, metrics, and the ODE and discrete PID equations. A single **"Advanced Math" setting (off by default)** reveals:

- transfer-function and Laplace-domain forms in the Equations tab,
- the Analysis tab (pole-zero map, Bode plot, margins, root locus),
- standard/ISA PID form (Ti, Td) next to parallel form.

Scenario files can force this setting on or off (for example, a lesson for younger students can lock it off). Presenter mode keeps whatever it was set to.

### 7.10 Saving student data

Each student has their own machine, so data is saved locally per device/browser. There are no accounts, no server, and no network calls.

- **What is saved:** named tuning snapshots per scenario, challenge best results and completion status, settings (Advanced Math, graphics preset, presenter mode, last scenario), and lesson progress.
- **Where:** a single versioned save file under `user://`. On desktop that's the normal app-data folder. On Web, Godot maps `user://` to the browser's IndexedDB storage for that site.
- **Safety and robustness:**
  - Save data is **plain data only** (JSON or a typed Dictionary). **Never** load saves as Godot resources or objects, because loading untrusted resource files can run code.
  - A schema version number in the file, plus a migration function for when the format changes.
  - Validate on load: unknown keys are ignored, bad values are replaced with defaults, and a corrupt file is renamed to a backup instead of crashing.
  - Write to a temp file, then replace the real one, so a crash mid-save can't corrupt it.
  - Autosave on meaningful changes (debounced, for example 1–2 s after the last change). **Do not rely on a quit/close event**, because browsers don't reliably give one when a tab closes. Always close the file after writing: on Web, Godot syncs to IndexedDB when a file is closed.
- **Backup / move between devices:** "Export save" and "Import save" (see §7.11 for how this works on itch.io). Browser storage can be wiped by clearing site data, so this is the student's safety net.
- **Reset:** a "Reset all progress" button with a confirmation step.

### 7.11 itch.io hosting requirements

The Web build is published on **itch.io** as an HTML5 game. Design for the following.

**Upload format**
- Upload a single ZIP with `index.html` at its root, so name the Web export `index.html`.
- itch.io limits: at most 1,000 files, 500 MB extracted, and 200 MB per file. A Godot web export is only a handful of files, so this is easy, but **keep the `.pck` small**: no huge textures, and compress where sensible.
- **SharedArrayBuffer support: off** in itch settings (we export without threads, §2.9).

**Embedding**
- itch shows the game inside an iframe on the game's page, at a fixed size set in the itch dashboard, with an optional fullscreen button. The UI must **adapt to any window size** (stretch mode and anchors set so the layout works from about 1280×720 up to fullscreen on a projector) and should offer its own fullscreen toggle.
- Fullscreen in a browser must be triggered by a user click. Never request it automatically.
- Show a clear loading screen; first load downloads the engine and the `.pck`.

**Storage on itch.io (important)**
- The game runs on itch's shared HTML5 hosting domain, **not on its own domain**. Browser storage (IndexedDB) is per domain, so **other Godot games on itch share the same storage area.** Our data must live under a **uniquely named folder** (set a distinctive application name and a custom user-data directory name, for example `control_lab_<something unique>`) so it can never collide with another game's `user://`. Claude Code should **verify** where the save actually lands in a Web build, not assume.
- Modern browsers partition iframe storage by the site showing it. Saves therefore belong to "this game, played through itch.io, in this browser". Students should **always open the game from the same itch.io page link** (not a direct iframe URL), or their saves won't appear.
- Browser storage is "best effort" and can be cleared by the user, by privacy settings, or (on Safari) by eviction after a period of no use. itch has also changed its hosting domain in the past, which would orphan saves. **Export/Import is therefore a required feature, not a nice-to-have.**
- *(Optional)* Ask the browser for persistent storage through Godot's built-in `JavaScriptBridge`. This may not be granted inside an iframe, so the app must work fine either way.

**Export/Import on Web**
- **Export:** download the save as a `.json` file using Godot's built-in `JavaScriptBridge` download function.
- **Import:** browsers don't let Godot's FileDialog reach the student's disk, so use a small, well-commented `JavaScriptBridge` snippet that opens the browser's file picker and passes the file text back to GDScript. As a fallback that always works, also offer **"Copy save code" / "Paste save code"** (the save as compact text through the clipboard).
- All import paths go through the same validation as a normal load (§7.10). An imported file is untrusted data.
- On desktop, use the normal Godot FileDialog.
- Keep all web-specific code in **one script** (for example `core/web_platform.gd`) that checks `OS.has_feature("web")`, so desktop builds never touch it.

**Release checklist (itch)**
1. Export Web (Compatibility renderer, no threads) to a clean folder; confirm `index.html` is at the root of the ZIP.
2. Upload as an HTML game, set viewport size, enable the fullscreen button, and leave SharedArrayBuffer off.
3. Test on the itch page in Chrome, Edge, Firefox, and Safari: it loads, saves, survives a page reload, and export/import round-trips.
4. Test on the slowest school laptop available with the Low graphics preset.

---

## 8. Optional C++ GDExtension (later, only if needed)

GDScript should handle one live simulation at 1 kHz easily. C++ is only worth it for **batch work**:

- parameter sweep heatmaps (for example, a grid of Kp × Kd showing overshoot or stability for each cell),
- Monte Carlo robustness tests (many mystery-plant variants),
- auto-tuning / optimization demos.

Rules:

- Use a **simulation backend interface** with two implementations, GDScript and C++. The batch runner calls the interface and does not care which one it gets.
- The C++ build is optional. If the extension isn't present, batch features fall back to GDScript, possibly with a smaller grid. **Assume the Web build never has the extension.** Web GDExtension builds are possible but add build complexity, so they are out of scope unless approved.
- A test verifies that both backends produce matching results for the same inputs (within a small tolerance).
- Don't start this stage without teacher approval.

---

## 9. Project structure and architecture

Suggested layout (Claude Code may propose changes, but must explain them):

```
res://
  core/            # simulation clock, integrators, signal chain, recorder, RNG, math utils
  plants/          # one script per plant + its visual scene
  controllers/     # PID, bang-bang, cascade, profile, manual, (LQR)
  signal_blocks/   # sensor, actuator, disturbance, setpoint generators
  scenarios/       # .tres scenario files (data only, no code)
  ui/              # panels, strip chart, block diagram, analysis views, themes
  modes/           # sandbox, lesson, ZN helper, challenge, presenter
  tests/           # in-engine test scenes (see §11)
  docs/            # architecture notes, "how to add a plant", "how to write a scenario"
```

Architecture rules:

- **Simulation is UI-independent.** A run can execute headless (tests and batch sweeps depend on this). UI nodes observe through signals and the recorder. They never drive the physics directly.
- **Composable signal chain**: setpoint → controller → actuator → plant → sensor, each a small, single-purpose object with a common "process one tick" contract.
- **Scenarios are data.** The teacher must be able to create a new scenario (pick a plant, set parameters, set default gains, toggle non-idealities, write notes, define challenge specs) **by editing a resource in the inspector, without writing code**.
- **Tunable values live in one place per subsystem** and are marked `# TUNABLE`. A doc page lists them all.
- **Parameter metadata drives the UI.** Adding a parameter to a plant should make its slider appear automatically.
- **Use a small event bus only where it helps.** Prefer direct signals between parent and child nodes.

---

## 10. Build stages

Each stage ends in something runnable and testable. ⛳ = stop for teacher review before continuing.

### Milestone A: Simulation core
1. **Clock and integrator.** Fixed-step accumulator, RK4 and semi-implicit Euler, time scale, pause/step/reset. *Test:* an undamped spring keeps its energy (RK4), and exponential decay matches the exact solution.
2. **Plant #1 (flywheel)** with parameter metadata and a simple 3D visual (spinning wheel with RPM readout, basic lighting, and a camera). Set up the Compatibility renderer and a **Web export preset now** (output `index.html`, no threads), and confirm a blank-ish 3D scene runs in a browser. Set the unique application name and user-data folder name now (§7.11), so storage never needs renaming later.
3. **Recorder** (ring buffer) and **strip chart** Control with 2–3 traces.
4. **Manual controller**: the student drives the flywheel with a slider and tries to hold a target RPM.

⛳ **Review A:** Is the sim correct and readable? Does the plot feel right?

### Milestone B: PID and the core loop
5. **Basic PID** (parallel form, output limits) with separate controller rate and zero-order hold.
6. **Controller panel** with log sliders, numeric fields, live changes, and nudge keys.
7. **Term breakdown plot** (stacked P/I/D) and **metrics** (rise time, overshoot, settling time, steady-state error, IAE, control effort).
8. **Setpoint generators** (step, square, ramp, sine).
9. **Plant #3 (mass–spring–damper)** and **#4 (servo position)**.

⛳ **Review B:** Classroom-ready for the first PID lesson?

### Milestone C: Reality bites
10. **Sensor and actuator blocks**: noise (seeded), quantization, delay, saturation, slew, deadband.
11. **PID advanced features**: derivative on measurement, D filter, anti-windup modes, setpoint weighting, ISA form display.
12. **Plant #2 (hotend)** with dead time and heat-only actuator. **Plant #5 (elevator)** with gravity, friction, and hard stops.
13. **Feedforward** (kS, kV, kA, kG) and **trapezoidal motion profile**.
14. **Disturbances**, including click-to-poke and parameter drift.

⛳ **Review C**

### Milestone D: Teaching features
15. **Scenario resources**, scenario picker, and Notes tab. Convert all existing plants to scenarios.
16. **Snapshots and ghost traces** (A/B compare with the same seed).
17. **Block diagram tab** and **Equations tab** with live values.
18. **Presenter mode**, theme, and a **visual polish pass** on the existing plants: materials, shaders, setpoint ghost, saturation highlight, and the Graphics settings panel with a Low preset.
19. **CSV export** and the **save system** (§7.10): snapshots, settings, export/import, reset, and Web persistence verified in a browser (reload the page and data is still there). Includes the `web_platform.gd` script for downloads, the file-picker import, and copy/paste save codes (§7.11). **Do a private test upload to itch.io at this checkpoint.**

⛳ **Review D:** Ready to hand to students?

### Milestone E: Modes and more plants
20. **Challenge mode** with spec bands and grading.
21. **Guided lesson mode** (locking controls, scripted prompts from the scenario file).
22. **Ziegler–Nichols helper.**
23. **Plants #6 (arm), #7 (cruise control), #8 (drone altitude)**, with **cascaded PID**.
24. **Mystery mode** for every plant.

⛳ **Review E**

### Milestone F: Analysis and stretch goals
25. **Math utils** (complex numbers, polynomial roots, small matrices) with tests.
26. **Analysis tab**: step response, pole-zero map, Bode plot with margins.
27. **Plant #9 (ball and beam).**
28. *(Stretch)* root locus, **plant #10 (inverted pendulum)**, LQR controller.
29. *(Stretch, needs approval)* C++ batch backend and parameter-sweep heatmap.
30. **Export presets** for Windows, macOS, and Linux (Web has existed since stage 2), and the full itch.io release checklist (§7.11).

⛳ **Final review**

---

## 11. Testing (no third-party test framework)

Build a minimal **in-engine test runner**: a scene that finds test scripts in `tests/`, runs them headless, and prints pass/fail with clear messages. It should be runnable from the editor and the command line.

Required test categories:

- **Integrator accuracy:** compare against analytic solutions (first-order step, damped oscillator), and check that error shrinks as expected when the step size is reduced.
- **Plant sanity:** equilibrium points hold, energy behaves as expected when there is no damping, and units are consistent.
- **PID math:** hand-calculated discrete outputs for a short known error sequence. Anti-windup behaves as specified when saturated.
- **Determinism:** same seed and settings give bit-identical recorded runs.
- **Rate independence:** results don't change with render frame rate (simulate with different frame-time patterns).
- **Metrics:** overshoot and settling time computed correctly on synthetic signals with known answers.
- **Math utils:** polynomial roots, Bode magnitude and phase for known transfer functions.

---

## 12. Definition of done (per stage)

- Runs without errors or warnings in the editor.
- At each ⛳ checkpoint: a Web export builds and runs in a browser.
- All tests pass.
- New scripts have header comments, and tricky logic has *why* comments, not just *what*.
- Any new tunable value is marked and documented.
- `docs/` updated if architecture or workflows changed.
- Brief stage summary for the teacher: what was built, how to try it, known limitations, and questions.

---

## 13. Open questions (teacher to decide)

These are tracked here; Claude Code should **not** guess on these. Ask.

**Decided:**
- [x] Web export is a primary target. This means the Compatibility renderer everywhere, with C++ for batch features only.
- [x] 3D wherever it makes sense, 2D where clearer. Shaders and custom materials are welcome; it should look good.
- [x] Transfer functions and frequency-domain analysis are hidden by default behind Advanced Math.

- [x] Godot 4.7 baseline, kept easy to upgrade.
- [x] Runs on laptops (desktop builds) and in the browser. Phones are a stretch goal only.
- [x] Each student has their own machine. Progress and tunings are saved locally (§7.10).
- [x] Challenge results are on screen only.
- [x] Plant build order as listed in §5 / §10.
- [x] Web build hosted on itch.io (§7.11).
- [x] No gamepad support in v1; input goes through InputMap so it can be added later.

Any new decision that comes up during the build: Claude Code asks; it does not guess.
