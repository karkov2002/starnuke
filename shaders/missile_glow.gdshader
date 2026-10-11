shader_type spatial;
// Halo du moteur d'un missile lointain (scripts/missile_flight.gd) : disque additif toujours face à la caméra, cœur
// blanc-jaune et auréole orangée. Sa taille (en unités de scène) est fixée chaque image par le script : jamais moins
// de quelques pixels, pour que le moteur reste un point lumineux jusqu'à l'impact. Test de profondeur actif : la Terre
// et les nuages le masquent.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 halo_color : source_color = vec3(1.0, 0.55, 0.18);

void vertex() {
	// Panneau face à la caméra, sans rotation ni échelle du nœud (taille portée par le maillage).
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 9.0);
	float halo = exp(-r * r * 3.0) * (1.0 - smoothstep(0.75, 1.0, r));
	ALBEDO = (core_color * core * 8.0 + halo_color * halo * 1.6) * intensity;
}
