// Incendies allumés par le flash des explosions nucléaires et trace qu'ils laissent au sol, dans le sol
// (earth_surface.gdshader). À inclure après cloud_density.gdshaderinc (bruits 3D). Explosions : nuke_ground.gdshaderinc
// (alimenté par nuke/nuke_ground_fx.gd) ; lois et durées : NukeScaling (FIRE_*, SCAR_*), transmises par NukeGroundFX.
//
// Zone du flash (rayon initial R0, exposition thermique suffisante pour enflammer les matériaux) : foyers allumés par
// le flash, qui forment une tempête de feu en ~1 h 30 ; la part du sol en feu y est forte près du centre (l'exposition
// décroît en 1/d²). Le front gagne ensuite les terres alentour sur plusieurs jours (rayon R0 · (1 + s · (1 − e^(−t/S)))) :
// chaque lieu s'embrase à l'arrivée du front, brûle (constante de temps d'extinction nuke_fire_burn_s.x), puis reste
// dévasté pour toujours : noir de charbon (en nuke_fire_burn_s.y), puis brun (cendres envolées, végétation morte) entre
// nuke_scar_brown_s.x et .y après son passage. Dans le rayon des gravats (souffle : bâtiments rasés, forêts couchées),
// le sol est gris-brun dès l'explosion, même sans incendie. Seulement sur les terres ; feux plus forts et plus vifs dans
// les villes (combustible). Depuis l'orbite (~0,5 km par pixel), on ne distingue pas les flammes : on voit leur lueur
// moyenne, modulée par un motif irrégulier de 2 à 12 km (zones qui brûlent plus ou moins), qui scintille. Positions en
// km dans le repère de la planète. La luminance des flammes est faible devant un sol éclairé par le soleil : les feux
// se voient surtout de nuit ; la trace au sol, elle, se voit de jour.
#ifndef NUKE_FIRE_INC
#define NUKE_FIRE_INC

#include "res://nuke/shaders/nuke_ground.gdshaderinc"

uniform vec3 nuke_fire_color : source_color = vec3(1.0, 0.45, 0.12);
// Luminance HDR d'un sol entièrement en feu, à intensité 1 (la tempête de feu culmine vers 0,8).
uniform float nuke_fire_hdr = 1.6;
// Périodes de la texture de bruit pour le motif des zones en feu (km ; une période contient ~4 taches) ; la grande
// vaut 1,2 fois le rayon initial, plafonnée à nuke_fire_coarse_km.
uniform float nuke_fire_fine_km = 8.0;
uniform float nuke_fire_coarse_km = 60.0;
// Lois (NukeScaling, envoyées par NukeGroundFX) : (part des foyers du flash, début et fin de la tempête de feu en s),
// (extension relative du front, sa constante de temps en s), (part du sol en feu au passage du front, durée de
// l'embrasement en s), (constante de temps de l'extinction, durée du noircissement en s), irrégularité du bord,
// (début et fin du brunissement en s).
uniform vec3 nuke_fire_growth_s = vec3(0.25, 120.0, 5400.0);
uniform vec2 nuke_fire_spread = vec2(1.0, 86400.0);
uniform vec2 nuke_fire_front = vec2(0.3, 3600.0);
uniform vec2 nuke_fire_burn_s = vec2(21600.0, 7200.0);
uniform float nuke_fire_edge_noise = 0.35;
uniform vec2 nuke_scar_brown_s = vec2(43200.0, 345600.0);
// Trace au sol, visible de jour : charbon frais, terre brûlée (brun sombre, sans verdure : réflectance de ~5 à 8 %
// comme les cicatrices de brûlis sur les images satellites, plus sombre qu'un sol aride), gravats (gris-brun, villes) et
// part maximale du mélange avec le sol d'origine. Le relief du sol d'origine reste un peu visible (nuke_scar_relief).
uniform vec3 nuke_burn_albedo : source_color = vec3(0.10, 0.09, 0.08);
uniform vec3 nuke_scar_albedo : source_color = vec3(0.23, 0.17, 0.12);
uniform vec3 nuke_rubble_albedo : source_color = vec3(0.33, 0.29, 0.26);
uniform float nuke_scar_strength = 0.95;
uniform float nuke_scar_relief = 0.35;

// Garde l'état de la trace la plus marquée : (dévastation, brunissement).
void nuke_scar_keep(inout vec2 scar, float devastation, float brown) {
	if (devastation > scar.x) {
		scar = vec2(devastation, brown);
	}
}

// État du sol au point p (km), de part de terre land (0 = eau) et d'urbanisation urban (0 à 1), pour les explosions de
// la maille cell (nuke_ground_cell) : (intensité des flammes, à multiplier par nuke_fire_color · nuke_fire_hdr ;
// dévastation, 0 à 1 ; brunissement, 0 = charbon frais, 1 = terre brûlée ou gravats).
vec3 nuke_fire_state(vec3 p, ivec2 cell, float land, float urban) {
	float total = 0.0;
	vec2 scar = vec2(0.0);
	for (int k = cell.x; k < cell.x + cell.y; k++) {
		NukeGroundEvent e = nuke_ground_event(k);
		if (e.time_s <= 0.0) {
			continue;
		}
		float d = length(p - e.pos_km);
		// Gravats (souffle), dès l'explosion. Le rayon des gravats (5 psi) est plus petit que la zone détruite (2 psi).
		if (d < e.destroyed_km) {
			float rubble = nuke_ground_row(e.id, 3).x;
			float wobble = textureLod(cloud_shape_noise, p / max(rubble * 0.5, 0.5) + vec3(0.6, 0.2, 0.9), 0.0).r - 0.5;
			nuke_scar_keep(scar, land * 0.85 * (1.0 - smoothstep(0.8, 1.1, d / max(rubble, 1e-3) + wobble)), 1.0);
		}
		float r0 = e.fire_km;
		if (r0 <= 0.0 || d > r0 * (1.0 + nuke_fire_spread.x + nuke_fire_edge_noise)) {
			continue;
		}
		// Motif irrégulier (zones qui brûlent plus ou moins) à deux échelles : la grande suit la taille de la zone en
		// feu. Le bruit fractal varie peu autour de 0,5 : on le normalise (c dans [−1, 1]) pour obtenir des zones
		// nettement contrastées.
		float coarse_km = min(nuke_fire_coarse_km, r0 * 1.2);
		float c = clamp((textureLod(cloud_shape_noise, p / coarse_km, 0.0).r - 0.5) * 4.0, -1.0, 1.0);
		float f = clamp((textureLod(cloud_shape_noise, p / nuke_fire_fine_km + vec3(0.31, 0.73, 0.17), 0.0).r - 0.5) * 4.0, -1.0, 1.0);
		float pattern = smoothstep(-0.2, 0.5, c * 0.65 + f * 0.35);
		// Distance relative, bord très irrégulier ; date d'embrasement : 0 dans la zone du flash, sinon arrivée du front
		// (inverse de R0 · (1 + s · (1 − e^(−t/S)))). Au-delà de l'extension finale, rien ne brûle.
		float x = d / r0 + nuke_fire_edge_noise * c;
		float t_ignite = 0.0;
		float share;
		if (x <= 1.0) {
			share = mix(0.8, 0.25, clamp(d / r0, 0.0, 1.0));
		} else {
			float u = (x - 1.0) / nuke_fire_spread.x;
			if (u >= 1.0) {
				continue;
			}
			t_ignite = -nuke_fire_spread.y * log(1.0 - u);
			share = nuke_fire_front.x * (1.0 - smoothstep(0.85, 1.0, u));
		}
		float age = e.time_s - t_ignite;
		if (age <= 0.0) {
			continue;
		}
		float growth = x <= 1.0
				? nuke_fire_growth_s.x * smoothstep(0.3, 1.5, age)
						+ (1.0 - nuke_fire_growth_s.x) * smoothstep(nuke_fire_growth_s.y, nuke_fire_growth_s.z, age)
				: smoothstep(0.0, nuke_fire_front.y, age);
		float burning = growth * exp(-age / nuke_fire_burn_s.x);
		// Scintillement des flammes.
		float flicker = 0.85 + 0.15 * sin(TIME * 6.3 + f * 10.0) * sin(TIME * 2.9 + c * 6.0);
		total += share * land * mix(0.6, 1.3, urban) * mix(0.05, 1.0, pattern) * flicker * burning * mix(1.0, 1.6, urban);
		// Sol brûlé : noirci à mesure qu'il brûle (plus complètement dans la zone du flash), définitif ; il brunit
		// ensuite.
		float scorch = smoothstep(0.0, nuke_fire_burn_s.y, age) * mix(0.75, 1.0, pattern)
				* mix(1.0, 0.8, smoothstep(0.8, 1.2, x)) * (1.0 - smoothstep(0.85, 1.0, (x - 1.0) / nuke_fire_spread.x));
		nuke_scar_keep(scar, land * scorch, smoothstep(nuke_scar_brown_s.x, nuke_scar_brown_s.y, age));
	}
	return vec3(total, scar);
}

// Albédo du sol dévasté : charbon, puis terre brûlée (gravats dans les villes), sur le relief atténué du sol d'origine.
vec3 nuke_scar_color(vec3 albedo, vec3 state, float urban) {
	vec3 settled = mix(nuke_scar_albedo, nuke_rubble_albedo, urban * 0.7);
	vec3 scar = mix(nuke_burn_albedo, settled, state.z);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	scar *= mix(1.0 - nuke_scar_relief, 1.0 + nuke_scar_relief, smoothstep(0.02, 0.2, luma));
	return mix(albedo, scar, state.y * nuke_scar_strength);
}

#endif
