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
	// Taille d'un pixel dans le repère du quad. Pour un petit halo (faibles puissances), le cœur et les branches
	// deviendraient plus fins qu'un pixel et scintilleraient en se déplaçant : on les élargit à au moins un pixel en
	// conservant leur énergie (pic × largeur² pour le cœur, pic × largeur pour les branches).
	float px = length(fwidth(v_p));
	float core = 0.0;
	for (int k = 0; k < 2; k++) {
		float w2 = k == 0 ? 1.0 / 400.0 : 1.0 / 40.0;
		float wide2 = max(w2, px * px);
		core += (k == 0 ? 1.0 : 0.3) * exp(-r * r / wide2) * (w2 / wide2);
	}
	float halo = 0.08 * exp(-r * 6.0) + 0.015 * exp(-r * 2.0);
	float spikes = 0.0;
	float width = 1.0 / spike_width;
	float wide = max(width, px);
	for (int i = 0; i < spike_lines; i++) {
		float a = spike_rotation + PI * float(i) / float(spike_lines);
		float across = abs(dot(v_p, vec2(-sin(a), cos(a))));
		spikes += exp(-across / wide) * (width / wide) * pow(1.0 - r, 3.0);
	}
	float value = (core + halo + 0.25 * spikes) * smoothstep(1.0, 0.7, r);
	ALBEDO = color * flare_intensity * value;
}
