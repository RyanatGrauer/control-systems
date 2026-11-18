// ghost.gdshader
//
// PURPOSE
//   The translucent "setpoint ghost" look: the setpoint colour, brighter at
//   the silhouette edges (a rim/fresnel glow) so its outline reads clearly
//   against the floor, with an optional gentle pulse. Unshaded and cheap
//   (Compatibility renderer friendly). Used by PlantVisual3D.make_ghost_material().
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 ghost_color : source_color = vec4(0.9, 0.62, 0.0, 0.35);
uniform float rim_strength = 0.55;   // TUNABLE: how bright the edges get
uniform float pulse_amount = 0.08;   // TUNABLE: 0 = no pulse
uniform float pulse_speed = 3.0;     // TUNABLE: radians per second

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0) * rim_strength;
	float pulse = pulse_amount * sin(TIME * pulse_speed);
	ALBEDO = ghost_color.rgb + vec3(rim * 0.5);
	ALPHA = clamp(ghost_color.a + rim + pulse, 0.0, 1.0);
}
