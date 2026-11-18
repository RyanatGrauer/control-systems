# Tunable values

Every tunable value is a constant marked `# TUNABLE` in its script. To find them all:

```
grep -rn "TUNABLE" --include=*.gd --include=*.gdshader .
```

| File | What you can tune |
|---|---|
| `core/simulation.gd` | Default physics rate (1000 Hz), controller rate (100 Hz), record rate (100 Hz), history length (120 s), default seed |
| `core/sim_clock.gd` | Max substeps per frame (spiral-of-death cap, 400); time-scale limits (0.1×–4×) |
| `plants/flywheel/flywheel_plant.gd` | Default motor/flywheel parameters, slider ranges, default PID gains |
| `plants/mass_spring_damper/mass_spring_damper_plant.gd` | Mass/spring/damper defaults, slider ranges, default PID gains |
| `plants/mass_spring_damper/mass_spring_damper_visual.gd` | Scene layout, force-arrow scale, ruler range |
| `plants/servo/servo_plant.gd` | Servo motor defaults, slider ranges, default PID gains |
| `plants/servo/servo_visual.gd` | Dial size and position |
| `plants/hotend/hotend_plant.gd`, `hotend_visual.gd` | Hotend defaults (C, R, dead time, room temperature), PID/FF ranges; glow colour scale |
| `plants/elevator/elevator_plant.gd`, `elevator_visual.gd` | Rail height, stick threshold, elevator defaults, PID/FF ranges; layout |
| `signal_blocks/sensor.gd` | Longest supported sensor delay (2 s) |
| `signal_blocks/disturbance_generator.gd` | Poke duration (0.2 s) |
| `ui/nonideality_panel.gd` | Default sizes and slider ranges for noise, resolution, delay, filter, deadband, slew (as fractions of each plant's range) |
| `ui/disturbance_panel.gd` | Default step/random/poke sizes (fractions of the disturbance range) |
| `ui/setpoint_panel.gd` | Default motion-profile speed and acceleration |
| `core/simulation.gd` (also) | Longest supported plant dead time (10 s) |
| `core/step_metrics.gd` | Rise thresholds (10/90%), settling band (2%), steady-state window (0.5 s) |
| `ui/metrics_bar.gd` | How often metrics are recomputed (4 Hz) |
| `plants/flywheel/flywheel_visual.gd` | Wheel size/position, speed at which motion blur appears |
| `plants/common/orbit_camera.gd` | Orbit speed, zoom step, pitch and zoom limits |
| `plants/common/grid_floor.gdshader` | Floor colours, grid spacing, fade distance |
| `ui/display_settings.gd` | What each graphics preset turns on/off; presenter UI scale (1.25×), line scale (1.7×) and colours |
| `ui/display_panel.gd` | 3D resolution choices (50/75/100%) |
| `plants/common/ghost.gdshader` | Ghost rim-glow strength, pulse size and speed |
| `core/save_store.gd` | Autosave delay (1.5 s) |
| `ui/block_diagram.gd` | Diagram layout fractions, font sizes, highlight colours |
| `ui/equations_view.gd` | Equations refresh rate (8 Hz) |
| `ui/strip_chart.gd` | Chart margins, font sizes, tick counts, dash pattern, auto-scale padding |
| `ui/labeled_slider.gd` | Slider resolution, fine-adjust step (×1.1 log / 1% linear), first nudge up from 0 (1% of max) |
| `ui/manual_control_panel.gd` | How fast holding Up/Down changes the command (1/6 of the input range per second) |
| `ui/sim_settings_panel.gd` | Physics-rate menu choices |
| `ui/sim_toolbar.gd` | How long the SLOW warning stays visible; scenario menu width |
| `ui/main_screen.gd` | Plot window choices, side-panel width |
| `ui/signal_colors.gd` | The colour language (not marked TUNABLE, but it all lives here) |
