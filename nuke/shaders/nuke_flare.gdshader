// Éblouissement du flash (halo + étoile de diffraction), billboard additif de taille angulaire donnée.
// Le quad est construit en espace vue autour du centre de l'effet, ramené à la fraction `pull` de sa distance :
// il passe devant la Terre et les nuages (pas de coupure par le sol) mais reste derrière la station, qui le masque.
// Paramètres par instance (nuke/nuke_flash.gd) : intensité HDR du cœur et rayon angulaire du halo.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float flare_intensity = 0.0;
instance uniform float flare_radius_rad = 0.05;
uniform float pull = 0.5;
uniform vec3 color : source_color = vec3(1.0, 0.9, 0.78);
// Branches de l'étoile : nombre de droites (2 droites = 4 branches) et rotation.
uniform int spike_lines = 2;
uniform float spike_rotation = 0.35;
uniform float spike_width = 90.0;

varying vec2 v_p;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float half_size = tan(flare_radius_rad) * length(center) * pull;
	vec3 view_pos = center * pull + vec3(VERTEX.xy * 2.0 * half_size, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
	v_p = VERTEX.xy * 2.0; // QuadMesh 1 x 1 : [-1, 1]
}

void fragment() {
	float r = length(v_p);
	if (r >= 1.0) {
		discard;
	}
	float core = exp(-r * r * 400.0) + 0.3 * exp(-r * r * 40.0);
	float halo = 0.08 * exp(-r * 6.0) + 0.015 * exp(-r * 2.0);
	float spikes = 0.0;
	for (int i = 0; i < spike_lines; i++) {
		float a = spike_rotation + PI * float(i) / float(spike_lines);
		float across = abs(dot(v_p, vec2(-sin(a), cos(a))));
		spikes += exp(-across * spike_width) * pow(1.0 - r, 3.0);
	}
	float value = (core + halo + 0.25 * spikes) * smoothstep(1.0, 0.7, r);
	ALBEDO = color * flare_intensity * value;
}
