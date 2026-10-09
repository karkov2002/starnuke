// Champignon atomique (nuke/nuke_mushroom.gd) : maillage de révolution dont le profil (méridienne, PROFILE_POINTS
// points (r, y) en unités normalisées, sommet final = 1) est recalculé à chaque image à partir des Curves et posé
// ici dans le vertex shader. UV.x = angle autour de l'axe, UV.y = position le long du profil (tige puis chapeau),
// interpolée entre les points : le maillage peut avoir plus d'anneaux que le profil n'a de points.
// Le même shader dessine le nuage de base (dôme de poussière au pied, autre profil, stem_fraction = 0).
// - Relief : bruit 3D (3 octaves) et bourgeons « chou-fleur » (bruit en valeur absolue, plus fin) déplaçant les
//   sommets le long de la normale ; au pixel, la normale est perturbée par le gradient du bruit (détail plus fin que
//   le maillage, essentiel vu d'en haut).
// - Chapeau « roulant » : le bruit y est lu dans des coordonnées tournées, dans chaque plan méridien, autour de
//   l'anneau tourbillonnaire (ring) : l'air monte au centre, s'écarte au sommet, redescend au bord et rentre
//   par-dessous. La tige fait défiler son bruit vers le haut (aspiration).
// - Dérive au vent : déplacement horizontal selon la hauteur (nuke_drift.gdshaderinc, profil du vent réel) :
//   pied fixe, tige penchée, chapeau entraîné et cisaillé.
// - Contact avec le sol adouci : opacité nulle au sol, pleine à ground_fade (part du sommet final).
// - Éclairage : soleil seulement (lumière Sun), diffus enveloppant, teinté et éteint par l'atmosphère au point
//   (sun_light.gdshaderinc, positions en km dans le repère de la planète) ; lumière du ciel en émission.
// - Lueur de la boule de feu (glow, couleur et intensité selon l'âge fournies par le script), au cœur du chapeau.
// - Fresnel : silhouette adoucie ; érosion : la tige se dissout (erosion), les bords du chapeau s'effilochent.
// Rendu avant les nuages (render_priority −1) avec pré-passe de profondeur : les nuages et l'atmosphère, rendus
// après, ne le recouvrent pas là où il les dépasse.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, shadows_disabled, ambient_light_disabled, fog_disabled,
		specular_disabled;

#include "res://shaders/sun_light.gdshaderinc"
#include "res://nuke/shaders/nuke_drift.gdshaderinc"

const int PROFILE_POINTS = 48;

uniform vec2 profile[48];
// UV.y du col (fin de la tige) ; la tige est en dessous.
uniform float stem_fraction = 0.33;
// Anneau tourbillonnaire du chapeau (rayon, hauteur), angle de roulement (rad) et défilement de la tige.
uniform vec2 ring = vec2(0.3, 0.8);
uniform float roll_angle = 0.0;
uniform float rise_offset = 0.0;
// Évolution lente du bruit (« bouillonnement »).
uniform float boil = 0.0;
uniform sampler3D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 7.0;
// Amplitude du relief, en part de la taille locale (rayon de la tige ou du chapeau), et part des bourgeons fins.
uniform float displacement = 0.45;
uniform float cauliflower = 0.4;
uniform float cauliflower_scale = 2.0;
// Perturbation de la normale au pixel par le gradient du bruit.
uniform float bump = 0.9;
uniform vec3 albedo : source_color = vec3(0.8);
// Lueur (couleur × luminance HDR) et concentration au cœur (puissance du terme 1 − fresnel).
uniform vec3 glow = vec3(0.0);
uniform float glow_core_power = 1.5;
uniform float erosion = 0.0;
uniform float edge_erosion = 0.25;
uniform float opacity = 1.0;
// Hauteur (unités normalisées) sur laquelle l'opacité monte depuis le sol.
uniform float ground_fade = 0.04;
// Repère : local (normalisé) → planète (km), et direction du soleil dans le repère de la planète.
uniform mat4 local_to_planet_km;
uniform vec3 sun_dir_planet = vec3(0.0, 1.0, 0.0);
uniform vec3 sky_ambient : source_color = vec3(0.45, 0.6, 0.9);
uniform float ambient_intensity = 0.25;
// Diffus enveloppant (0 = Lambert) : un nuage épais reste éclairé un peu au-delà du terminateur local.
uniform float wrap = 0.15;

varying vec3 v_noise;
varying vec3 v_planet;
varying float v_stem;
varying float v_size;
varying float v_up;
varying float v_height;
varying vec3 v_sun;

float fbm(vec3 p) {
	return 0.55 * texture(noise_tex, p).r + 0.3 * texture(noise_tex, p * 2.03 + vec3(0.31, 0.17, 0.73)).r
			+ 0.15 * texture(noise_tex, p * 4.11 + vec3(0.71, 0.53, 0.29)).r;
}

// Bourgeons : bruit « en valeur absolue » inversé (bosses arrondies séparées par des creux nets), 2 octaves.
float cauli(vec3 p) {
	float a = 1.0 - abs(2.0 * texture(noise_tex, p).r - 1.0);
	float b = 1.0 - abs(2.0 * texture(noise_tex, p * 2.17 + vec3(0.57, 0.11, 0.37)).r - 1.0);
	return 0.65 * a * a + 0.35 * b * b;
}

// Relief total (≈ −1 à 1) au point q de l'espace du bruit.
float relief(vec3 q) {
	return (2.0 * fbm(q) - 1.0) + cauliflower * (2.0 * cauli(q * cauliflower_scale) - 1.0);
}

// Normale méridienne (sortante) au point i du profil, par différence centrée.
vec2 profile_normal(int i) {
	vec2 t = profile[min(i + 1, PROFILE_POINTS - 1)] - profile[max(i - 1, 0)];
	return length(t) > 1e-6 ? normalize(vec2(t.y, -t.x)) : vec2(0.0, 1.0);
}

void vertex() {
	float f = clamp(UV.y, 0.0, 1.0) * float(PROFILE_POINTS - 1);
	int i0 = min(int(floor(f)), PROFILE_POINTS - 2);
	float k = f - float(i0);
	vec2 p = mix(profile[i0], profile[i0 + 1], k);
	vec2 n2 = normalize(mix(profile_normal(i0), profile_normal(i0 + 1), k) + vec2(1e-6, 0.0));
	float a = UV.x * TAU;
	vec3 dir = vec3(cos(a), 0.0, sin(a));
	vec3 pos = vec3(dir.x * p.x, p.y, dir.z * p.x);
	vec3 nrm = normalize(vec3(dir.x * n2.x, n2.y, dir.z * n2.x));

	v_stem = stem_fraction > 0.0 ? 1.0 - smoothstep(stem_fraction - 0.04, stem_fraction + 0.02, UV.y) : 0.0;
	// Chapeau : coordonnées méridiennes autour de l'anneau, tournées de roll_angle (le motif roule vers l'extérieur
	// au sommet). Tige : défilement vers le haut.
	vec2 m = vec2(p.x - ring.x, p.y - ring.y);
	float c = cos(roll_angle);
	float s = sin(roll_angle);
	vec2 mr = vec2(c * m.x - s * m.y, s * m.x + c * m.y);
	vec3 cap_q = vec3(dir.x * (ring.x + mr.x), ring.y + mr.y, dir.z * (ring.x + mr.x));
	vec3 stem_q = pos - vec3(0.0, rise_offset, 0.0);
	v_noise = mix(cap_q, stem_q, v_stem) * noise_scale + vec3(boil, 0.0, 0.5 * boil);

	v_size = mix(max(ring.x, 0.02), max(p.x, 0.005), v_stem);
	VERTEX = pos + nrm * (displacement * v_size * relief(v_noise));
	v_height = VERTEX.y;
	VERTEX += nuke_drift(VERTEX.y);
	NORMAL = nrm;
	v_up = nrm.y;
	v_planet = (local_to_planet_km * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(v_noise * 1.7 + vec3(0.13));
	// Normale perturbée par le gradient du relief fin (différences finies dans l'espace du bruit ≈ espace local).
	vec3 q = v_noise * 2.3;
	float e = 0.03;
	// Détail atténué quand il devient plus fin que le pixel (crénelage en grains sombres sinon).
	float detail = 1.0 - smoothstep(0.12, 0.45, length(fwidth(q)));
	float r0 = mix(0.5, cauli(q), detail);
	vec3 grad = vec3(cauli(q + vec3(e, 0.0, 0.0)) - r0, cauli(q + vec3(0.0, e, 0.0)) - r0,
			cauli(q + vec3(0.0, 0.0, e)) - r0) / e;
	vec3 grad_view = mat3(VIEW_MATRIX) * normalize(mat3(MODEL_MATRIX) * grad + vec3(1e-6));
	grad_view -= NORMAL * dot(grad_view, NORMAL);
	NORMAL = normalize(NORMAL - bump * detail * min(length(grad) * 0.05, 1.0) * grad_view);

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 1.0 - facing;
	// Érosion : la tige se dissout là où le bruit est faible ; les bords rasants s'effilochent.
	float erode = v_stem * erosion + edge_erosion * fresnel * fresnel;
	float alpha = opacity * smoothstep(erode, erode + 0.12, n) * mix(1.0, 0.55, smoothstep(0.6, 1.0, fresnel));
	// Contact avec le sol adouci (rongé par le bruit pour éviter une ligne nette).
	alpha *= smoothstep(0.0, ground_fade, v_height + ground_fade * 0.6 * (n - 0.5));
	ALPHA = clamp(alpha, 0.0, 1.0);
	// Creux du relief plus sombres, dessous du chapeau dans l'ombre de sa propre masse (occlusion approchée).
	float occlusion = mix(0.55, 1.0, smoothstep(-0.7, 0.5, v_up)) * mix(0.45, 1.1, smoothstep(0.15, 0.8, r0))
			* mix(0.7, 1.05, n);
	ALBEDO = albedo * occlusion;
	ROUGHNESS = 1.0;
	v_sun = sun_transmittance_at(v_planet, normalize(sun_dir_planet));
	float day = smoothstep(-0.2, 0.1, dot(normalize(v_planet), normalize(sun_dir_planet)));
	vec3 emission = ALBEDO * sky_ambient * ambient_intensity * day;
	// Lueur de la boule de feu : au cœur du chapeau (faces vues de face), plus vive dans les creux du bruit.
	emission += glow * (1.0 - v_stem) * pow(facing, glow_core_power) * mix(1.4, 0.4, n);
	EMISSION = emission;
}

void light() {
	float ndl = (dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * v_sun * max(ndl, 0.0) / PI;
}
