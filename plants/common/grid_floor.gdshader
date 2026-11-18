// grid_floor.gdshader
//
// PURPOSE
//   A subtle studio floor with grid lines that fade out with distance, so 3D
//   objects have a sense of scale and position. Compatibility-renderer safe
//   (WebGL2): only basic math and fwidth().
//
// HOW IT FITS
//   PlantVisual3D.build_studio() puts this on a large plane under every plant.
shader_type spatial;

// TUNABLE: floor look.
uniform vec3 base_color : source_color = vec3(0.16, 0.17, 0.20);
uniform vec3 line_color : source_color = vec3(0.34, 0.36, 0.42);
uniform float cell_size = 0.25;      // metres between minor lines
uniform float major_every = 4.0;     // a brighter line every N cells
uniform float fade_distance = 5.0;   // metres from the origin where lines vanish

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1.0 on a grid line, 0.0 between lines. fwidth() keeps lines about one pixel
// wide at any distance, which avoids flicker (aliasing).
float grid_line(vec2 coordinate) {
	vec2 distance_to_line = abs(fract(coordinate - 0.5) - 0.5) / fwidth(coordinate);
	return 1.0 - min(min(distance_to_line.x, distance_to_line.y), 1.0);
}

void fragment() {
	vec2 cell_coordinate = world_position.xz / cell_size;
	float minor_line = grid_line(cell_coordinate) * 0.5;
	float major_line = grid_line(cell_coordinate / major_every);
	float line_strength = max(minor_line, major_line);

	float fade = 1.0 - smoothstep(fade_distance * 0.4, fade_distance, length(world_position.xz));
	ALBEDO = mix(base_color, line_color, line_strength * fade);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
