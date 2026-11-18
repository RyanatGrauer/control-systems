# Tunable values

Every tunable value is a constant marked `# TUNABLE` in its script. To find them all:

```
grep -rn "TUNABLE" --include=*.gd --include=*.gdshader .
```

| File | What you can tune |
|---|---|
| `core/simulation.gd` | Default physics rate (1000 Hz), controller rate (100 Hz), record rate (100 Hz), history length (120 s), default seed |
| `core/sim_clock.gd` | Max substeps per frame (spiral-of-death cap, 400); time-scale limits (0.1×–4×) |
| `plants/flywheel/flywheel_plant.gd` | Default motor/flywheel parameters and slider ranges |
| `plants/flywheel/flywheel_visual.gd` | Wheel size/position, speed at which motion blur appears |
| `plants/common/orbit_camera.gd` | Orbit speed, zoom step, pitch and zoom limits |
| `plants/common/grid_floor.gdshader` | Floor colours, grid spacing, fade distance |
| `ui/plant_view.gd` | 3D anti-aliasing (MSAA 2×) |
| `ui/strip_chart.gd` | Chart margins, font sizes, tick counts, dash pattern, auto-scale padding |
| `ui/labeled_slider.gd` | Slider resolution, fine-adjust step (×1.1 log / 1% linear) |
| `ui/manual_control_panel.gd` | How fast holding Up/Down changes the command (4 V/s) |
| `ui/sim_settings_panel.gd` | Physics-rate menu choices |
| `ui/sim_toolbar.gd` | How long the SLOW warning stays visible |
| `ui/main_screen.gd` | Plot window choices, side-panel width |
| `ui/signal_colors.gd` | The colour language (not marked TUNABLE, but it all lives here) |
