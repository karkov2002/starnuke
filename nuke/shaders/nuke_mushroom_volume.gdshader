// Champignon atomique volumétrique (nuke/nuke_mushroom.gd, option volumetric) : lancer de rayon dans un champ de
// densité, sur une boîte englobante (BoxMesh 2 × 2 × 2, faces avant ; la caméra est toujours hors de la boîte).
// Toutes les positions sont dans le repère normalisé du nœud Mushroom (sommet final = 1, Y = verticale).
//
// Densité = forme analytique fondue en douceur, érodée par un bruit 3D :
// - chapeau : super-ellipse aplatie (dessus plat, bord arrondi), dessous creusé autour de la tige, lobes ;
// - tige : cylindre évasé au pied et sous le chapeau, qui se dissout avec l'âge (stem_erosion) ;
// - nuage de base : dôme bas qui s'étend avec l'onde de choc (surge_*).
// Asymétrie : déformation basse fréquence du domaine (warp, propre à chaque explosion via seed) et dérive au vent
// (nuke_drift.gdshaderinc : profil vertical du vent réel, chaque altitude dans sa direction). Dissipation après la
// stabilisation : densité × fade (dilution par l'étalement, disparition), trous de plus en plus grands (breakup, bruit
// basse fréquence). Bruit : roulement toroïdal du chapeau (coordonnées méridiennes tournées
// autour de l'anneau), défilement de la tige vers le haut, bouillonnement lent.
// Éclairage comme les nuages (shaders/cloud_volume.gdshader) : marche vers le soleil (auto-ombrage, loi de Beer +
// diffusion multiple approchée), phase de Henyey-Greenstein, soleil filtré par l'atmosphère (sun_light.gdshaderinc),
// ciel ambiant ; lueur de la boule de feu émise au cœur du chapeau.
// Décalage d'échantillonnage fixe par pixel (pas de bruit temporel) : pas de scintillement.
// Profondeur : celle du premier point dense (alpha cumulé > depth_alpha) ; ailleurs, un point juste au-dessus du sol
// (derrière la couche nuageuse). Les nuages et l'atmosphère, rendus après, le recouvrent seulement là où ils sont
// devant lui.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_back, depth_draw_always, shadows_disabled, fog_disabled;

#include "res://shaders/sun_light.gdshaderinc"
#include "res://nuke/shaders/nuke_drift.gdshaderinc"

uniform sampler3D noise_tex : filter_linear_mipmap, repeat_enable;
// Repères : monde → local normalisé, local → monde, local → planète (km).
uniform mat4 world_to_local;
uniform mat4 local_to_world;
uniform mat4 local_to_planet_km;
uniform vec3 box_min = vec3(-1.0, 0.0, -1.0);
uniform vec3 box_max = vec3(1.0, 1.0, 1.0);
// Forme (unités normalisées).
uniform float cap_center = 0.8;
uniform float cap_radius = 0.6;
uniform float cap_half = 0.15;
// Profondeur du dessous du chapeau (part de cap_half), creusement autour de la tige.
uniform float cap_under = 0.6;
uniform float cap_concavity = 0.5;
// Exposant de la super-ellipse du chapeau (2 = ellipse ; plus grand = dessus plus plat).
uniform float cap_power = 2.6;
uniform float stem_radius = 0.08;
uniform float neck_height = 0.6;
uniform float base_flare = 1.2;
uniform float base_flare_height = 0.05;
uniform float stem_erosion = 0.0;
uniform float surge_radius = 0.0;
uniform float surge_height = 0.0;
uniform float surge_density = 0.6;
// Asymétrie : amplitude de la déformation du domaine (part de la taille locale), lobes du chapeau, graine.
uniform float warp = 0.35;
uniform float lobes = 0.18;
// Part verticale de la déformation (1 ; réduite quand le chapeau s'étale en couche mince).
uniform float warp_vertical = 1.0;
uniform vec3 seed = vec3(0.0);
// Bruit : anneau tourbillonnaire (rayon, hauteur), roulement, défilement de la tige, bouillonnement.
uniform vec2 ring = vec2(0.3, 0.8);
uniform float roll_angle = 0.0;
uniform float rise_offset = 0.0;
uniform float boil = 0.0;
uniform float noise_scale = 5.0;
// Largeur de la zone érodée par le bruit, en part de la forme (bords gazeux).
uniform float edge_softness = 0.35;
// Part du cisaillement du vent appliquée au bruit (la forme le subit en entier).
uniform float noise_shear = 0.2;
uniform float ground_fade = 0.04;
// Dissipation : facteur de densité (1 jusqu'à la stabilisation) et seuil des trous (0 = aucun).
uniform float fade = 1.0;
uniform float breakup = 0.0;
// Extinction (par unité normalisée : extinction en km⁻¹ × sommet en km).
uniform float extinction = 30.0;
uniform vec3 albedo : source_color = vec3(0.85);
uniform vec3 glow = vec3(0.0);
// Soleil (repère local, unitaire) et lumière.
uniform vec3 sun_dir_local = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir_planet = vec3(0.0, 1.0, 0.0);
uniform float sun_intensity = 1.7;
uniform float multiple_scattering = 0.4;
uniform vec3 sky_ambient : source_color = vec3(0.45, 0.6, 0.9);
uniform float ambient_intensity = 0.22;
uniform float phase_forward = 0.6;
uniform float phase_backward = -0.25;
uniform float phase_backward_weight = 0.3;
uniform int max_steps = 64;
uniform int light_steps = 5;
// Premier pas de la marche vers le soleil (unités normalisées ; 0,3 km comme les nuages, fourni par le script).
uniform float light_first_step = 0.01;
uniform float depth_alpha = 0.35;

float noise3(vec3 p) {
	return texture(noise_tex, p).r;
}

float fbm(vec3 p) {
	return 0.55 * noise3(p) + 0.3 * noise3(p * 2.03 + vec3(0.31, 0.17, 0.73)) + 0.15 * noise3(p * 4.11 + vec3(0.71, 0.53, 0.29));
}

float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(b, a, h) + k * h * (1.0 - h);
}

// Forme sans bruit fin (> 0 à l'intérieur, ~1 au cœur) au point p (local, dérive déjà retirée), et poids de la tige.
float shape(vec3 p, out float stem_weight) {
	// Déformation basse fréquence du domaine : silhouette irrégulière, propre à chaque explosion.
	vec3 w = vec3(noise3(p * 0.9 + seed), noise3(p * 0.9 + seed + vec3(0.37, 0.61, 0.13)),
			noise3(p * 0.9 + seed + vec3(0.71, 0.23, 0.47))) - 0.5;
	float size = mix(max(stem_radius, 0.02), cap_radius, smoothstep(neck_height * 0.6, cap_center, p.y));
	w.y *= warp_vertical;
	p += w * (2.0 * warp * size);
	float rho = length(p.xz);
	float angle = atan(p.z, p.x);
	// Chapeau : super-ellipse, rayon modulé par des lobes, dessous creusé près de l'axe.
	float lobe = 1.0 + lobes * (noise3(vec3(cos(angle), sin(angle), 0.0) * 0.8 + seed * 1.7) - 0.5) * 2.0;
	float rc = cap_radius * lobe;
	float dy = p.y - cap_center;
	float bb = dy > 0.0 ? cap_half : cap_half * cap_under;
	float e = pow(pow(rho / max(rc, 1e-4), cap_power) + pow(abs(dy) / max(bb, 1e-4), cap_power), 1.0 / cap_power);
	e += cap_concavity * max(-dy / max(bb, 1e-4), 0.0) * (1.0 - smoothstep(0.0, 0.7 * rc, rho));
	float cap = 1.0 - e;
	// Tige : évasée au pied et sous le chapeau, jusqu'au centre du chapeau.
	float r_stem = stem_radius * (1.0 + base_flare * exp(-max(p.y, 0.0) / max(base_flare_height, 1e-4)))
			* (1.0 + 0.8 * smoothstep(neck_height - 2.0 * cap_half, neck_height, p.y));
	// Les parties négatives (hors de la forme) ne sont jamais réduites : sinon le bruit y créerait du brouillard.
	float stem = -10.0;
	if (stem_radius > 1e-4) {
		stem = min(1.0 - rho / max(r_stem, 1e-4), (cap_center - p.y) / max(cap_half, 1e-4));
		stem = min(stem, stem * (1.0 - stem_erosion)) - 0.5 * stem_erosion;
	}
	// Nuage de base.
	float surge = -10.0;
	if (surge_radius > 1e-4) {
		surge = 1.0 - length(vec2(rho / surge_radius, p.y / max(surge_height, 1e-4)));
		surge = min(surge, surge * surge_density) - 0.3 * (1.0 - surge_density);
	}
	stem_weight = clamp((stem - cap) * 4.0 + 0.5, 0.0, 1.0) * step(p.y, cap_center);
	return smax(smax(cap, stem, 0.08), surge, 0.05);
}

// Coordonnées du bruit : chapeau roulant autour de l'anneau, tige qui défile vers le haut.
vec3 noise_coords(vec3 p, float stem_weight) {
	float rho = length(p.xz);
	vec2 dir = rho > 1e-5 ? p.xz / rho : vec2(1.0, 0.0);
	vec2 m = vec2(rho - ring.x, p.y - ring.y);
	float c = cos(roll_angle);
	float s = sin(roll_angle);
	vec2 mr = vec2(c * m.x - s * m.y, s * m.x + c * m.y);
	vec3 cap_q = vec3(dir.x * (ring.x + mr.x), ring.y + mr.y, dir.y * (ring.x + mr.x));
	vec3 stem_q = p - vec3(0.0, rise_offset, 0.0);
	return mix(cap_q, stem_q, stem_weight) * noise_scale + vec3(boil, 0.0, 0.5 * boil) + seed;
}

float density(vec3 p, bool detail, out float core) {
	vec3 shift = nuke_drift(p.y);
	vec3 q = p - shift;
	float stem_weight;
	float s = shape(q, stem_weight);
	core = 0.0;
	if (s <= -edge_softness) {
		return 0.0;
	}
	// Bruit : seulement noise_shear du cisaillement autour du centre du chapeau (sinon, étiré sur des dizaines de km,
	// il se décorrèle d'un pas de la marche à l'autre : grain et stries). La tige garde le sien (elle penche).
	vec3 qn = q + (1.0 - noise_shear) * (1.0 - stem_weight) * (shift - nuke_drift(cap_center));
	float n = detail ? fbm(noise_coords(qn, stem_weight)) : noise3(noise_coords(qn, stem_weight) * 0.5);
	// Bords gazeux : la forme est rongée par le bruit sur une bande de largeur edge_softness.
	float d = clamp((s + edge_softness * (n - 0.35)) / edge_softness, 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	d *= smoothstep(0.0, ground_fade, q.y) * fade;
	if (breakup > 0.0) {
		// Le nuage dilué se fragmente en lambeaux : trous à grande échelle, qui grandissent avec breakup.
		d *= smoothstep(0.5 * breakup, 1.5 * breakup + 1e-3, noise3(qn * 2.0 + seed * 2.3 + vec3(0.0, 0.0, 0.3 * boil)));
	}
	core = clamp(s, 0.0, 1.0) * (1.0 - stem_weight);
	return d;
}

vec2 ray_box(vec3 ro, vec3 rd) {
	vec3 inv = 1.0 / rd;
	vec3 t0 = (box_min - ro) * inv;
	vec3 t1 = (box_max - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	return vec2(max(max(tmin.x, tmin.y), tmin.z), min(min(tmax.x, tmax.y), tmax.z));
}

float henyey_greenstein(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

void fragment() {
	vec3 cam_w = INV_VIEW_MATRIX[3].xyz;
	vec3 frag_w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ro = (world_to_local * vec4(cam_w, 1.0)).xyz;
	vec3 rd = normalize((world_to_local * vec4(frag_w, 1.0)).xyz - ro);
	vec2 hit = ray_box(ro, rd);
	float t0 = max(hit.x, 0.0);
	float t1 = hit.y;
	// Le sol (y = 0) arrête le rayon.
	if (rd.y < 0.0) {
		t1 = min(t1, -ro.y / rd.y);
	}
	if (t1 <= t0) {
		discard;
	}
	float len = t1 - t0;
	float dt = len / float(max_steps);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec3 l = normalize(sun_dir_local);
	float mu = dot(rd, l);
	float phase = 4.0 * PI * mix(henyey_greenstein(mu, phase_forward), henyey_greenstein(mu, phase_backward),
			phase_backward_weight);
	// Lumière du soleil filtrée par l'atmosphère, au milieu du trajet dans la boîte.
	vec3 mid = (local_to_planet_km * vec4(ro + rd * (0.5 * (t0 + t1)), 1.0)).xyz;
	vec3 sun = sun_transmittance_at(mid, normalize(sun_dir_planet)) * sun_intensity;
	float day = smoothstep(-0.2, 0.1, dot(normalize(mid), normalize(sun_dir_planet)));
	vec3 ambient = sky_ambient * ambient_intensity * day;

	float transmittance = 1.0;
	vec3 scattered = vec3(0.0);
	float depth_t = -1.0;
	for (int i = 0; i < max_steps; i++) {
		float t = t0 + (float(i) + jitter) * dt;
		vec3 p = ro + rd * t;
		float core;
		float d = density(p, true, core);
		if (d <= 0.0) {
			continue;
		}
		// Densité optique vers le soleil, pas doublés.
		float od = 0.0;
		float tl = 0.0;
		float s = light_first_step;
		for (int j = 0; j < light_steps; j++) {
			float unused;
			od += density(p + l * (tl + 0.5 * s), false, unused) * s;
			tl += s;
			s *= 2.0;
		}
		float beer = exp(-extinction * od);
		float multiple = max(beer, multiple_scattering * exp(-0.25 * extinction * od));
		float sigma = extinction * d;
		float attenuation = exp(-sigma * dt);
		vec3 light = albedo * (sun * multiple * phase + ambient) + glow * core * core;
		scattered += transmittance * light * (1.0 - attenuation);
		transmittance *= attenuation;
		if (depth_t < 0.0 && 1.0 - transmittance > depth_alpha) {
			depth_t = t;
		}
		if (transmittance < 0.01) {
			break;
		}
	}
	if (transmittance > 0.995) {
		discard;
	}
	ALBEDO = scattered;
	ALPHA = 1.0 - transmittance;
	// Profondeur : premier point dense, sinon juste au-dessus du sol (derrière les nuages, devant le sol).
	if (depth_t < 0.0) {
		depth_t = rd.y < 0.0 ? max((0.01 - ro.y) / rd.y, t0) : t1;
	}
	vec3 p_world = (local_to_world * vec4(ro + rd * depth_t, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p_world, 1.0));
	DEPTH = clip.z / clip.w;
}
