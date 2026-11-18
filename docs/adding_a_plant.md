# How to add a plant

Use `plants/flywheel/` as the worked example.

1. **Create a folder** `plants/<name>/`.
2. **Physics script** `<name>_plant.gd`: `class_name <Name>Plant`, `extends Plant`. Override:
   * `get_display_name()`
   * `get_parameter_definitions()`: one `QuantityInfo` per tunable parameter, in SI, with `.with_range(min, max, default)` and a one-sentence `.with_description(...)`. Use `.with_log_slider()` for values that span orders of magnitude. Each one automatically gets a slider in the "Plant parameters" panel.
   * `get_state_definitions()`: state components **in order**. Mark each one `.as_state(QuantityInfo.StateKind.POSITION)` or `RATE`. The semi-implicit Euler integrator updates RATE components first, then POSITION components.
   * `get_input_definition()`, `get_output_definition()`, `get_disturbance_definition()`. Use `.with_display("RPM", scale)` if students should see friendlier units.
   * `get_initial_state()`, `compute_derivative(state, applied_input, disturbance, time)` (return d(state)/dt), and `get_output(state)`.
   * Optional: `apply_constraints(state)` for hard stops, stick/slip, and similar effects. This runs between substeps.
   * `get_visual_scene_path()`
   * Put the model equations in the header comment, with every symbol mapped to its variable name.
3. **Visual** `<name>_visual.tscn` with a root `Node3D` whose script extends `PlantVisual3D`. In `_ready()` call `build_studio(look_at, distance, yaw, pitch)`, then build meshes. Use `PlantVisual3D.add_mesh()` for simple lit parts. Override `show_state()`, and `reset_visual()` if you keep animation history. Animate using `sim_time`, not frame time.
4. **Tests** `tests/test_<name>.gd` extending `TestCase`: check equilibrium, a known analytic case, and energy behaviour if the plant is undamped.
5. Until the scenario picker exists (stage 15), try the plant by changing the `FlywheelPlant.new()` line in `ui/main_screen.gd::_ready()`.
