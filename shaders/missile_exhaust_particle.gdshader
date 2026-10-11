// Particule du panache du missile (scripts/missile_exhaust.gd) : tache additive douce, toujours face à la caméra.
// Couleur et opacité viennent de la particule (COLOR : rampe du ParticleProcessMaterial, du blanc-jaune à l'orange
// puis au transparent) ; taille selon l'échelle de la particule.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float hdr = 3.0;

void vertex() {
	// Face à la caméra, en gardant l'échelle de la particule.
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(vec4(scale.x, 0.0, 0.0, 0.0), vec4(0.0, scale.y, 0.0, 0.0),
			vec4(0.0, 0.0, scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float soft = exp(-r2 * 3.0) * (1.0 - smoothstep(0.7, 1.0, r2));
	ALBEDO = COLOR.rgb * hdr * intensity;
	ALPHA = soft * COLOR.a;
}
