# How to add a plant

Use `plants/flywheel/` as the worked example.

1. **Create a folder** `plants/<name>/`.
2. **Physics script** `<name>_plant.gd`: `class_name <Name>Plant`, `extends Plant`. Override:
   * `get_display_name()`, and `get_description()`: one or two plain sentences shown above the plant view (what the controller drives, and what the goal is).
   * `get_parameter_definitions()`: one `QuantityInfo` per tunable parameter, in SI, with `.with_range(min, max, default)` and a one-sentence `.with_description(...)`. Use `.with_log_slider()` for values that span orders of magnitude. Each one automatically gets a slider in the "Plant parameters" panel.
   * `get_state_definitions()`: state components **in order**. Mark each one `.as_state(QuantityInfo.StateKind.POSITION)` or `RATE`. The semi-implicit Euler integrator updates RATE components first, then POSITION components.
   * `get_input_definition()`, `get_output_definition()`, `get_disturbance_definition()`. Use `.with_display("RPM", scale)` if students should see friendlier units.
   * `get_initial_state()`, `compute_derivative(state, applied_input, disturbance, time)` (return d(state)/dt), and `get_output(state)`.
   * Optional: `apply_constraints(state)` for hard stops, stick/slip, and similar effects. This runs between substeps. (For static friction, the elevator instead uses a Karnopp model inside `compute_derivative`.)
   * Optional: `get_input_dead_time()` (seconds) for a pure delay between actuator and plant (see the hotend). `output_is_rate()` returns true if the output is a speed (this changes what kV multiplies).
   * `get_equation_text(state, plant_input, disturbance)`: the ODE in symbols, then with live numbers, for the Equations tab (see the flywheel).
   * `get_feedforward_definitions()`: return `make_feedforward_definitions(ks_max, kv_max, ka_max, kg_max)`. Defaults are 0. Note the ideal values in a comment.
   * `get_pid_gain_definitions()`: return `make_pid_gain_definitions(kp_default, kp_max, ki_default, ki_max, kd_default, kd_max)`. Start P-only (Ki = Kd = 0). Units are generated automatically.
   * Optional, for **Cascaded PID** (stage 23): `get_inner_definition()` (the inner loop's quantity, usually the output's rate, with a ± range), `get_inner_output(state)`, `get_cascade_gain_definitions()` (return `make_cascade_gain_definitions([outer kp, kp_max, ki, ki_max, kd, kd_max], [inner ...])`), and `get_inner_setpoint_limit()` (the outer loop's output limit, e.g. max climb speed). When these are defined, the controller menu offers "Cascaded PID" and an Inner loop plot tab appears. See the drone and the arm.
   * `get_visual_scene_path()`
   * Put the model equations in the header comment, with every symbol mapped to its variable name.
3. **Visual** `<name>_visual.tscn` with a root `Node3D` whose script extends `PlantVisual3D`. In `_ready()` call `build_studio(look_at, distance, yaw, pitch)`, then build meshes. Use `PlantVisual3D.add_mesh()` for simple lit parts. Override `show_state()`, and `reset_visual()` if you keep animation history. Animate using `sim_time`, not frame time.
4. **Tests** `tests/test_<name>.gd` extending `TestCase`: check equilibrium, a known analytic case, and energy behaviour if the plant is undamped.
5. Add the script to `PLANT_SCRIPTS` in `plants/plant_catalog.gd` (in teaching order). It then appears in the toolbar picker, and `test_every_catalog_plant_is_consistent` plus the UI smoke test cover it automatically. (Stage 15 replaces the catalog with scenario files.)
6. Visual conventions: the measured thing uses `SignalColors.MEASUREMENT`, the setpoint ghost uses `make_ghost_material()`, and the applied input (arrow, etc.) uses `SignalColors.APPLIED_INPUT`.
