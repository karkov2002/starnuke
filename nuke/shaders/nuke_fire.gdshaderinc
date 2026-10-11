// Incendies allumés par le flash des explosions nucléaires et sol calciné qu'ils laissent, dans le sol
// (earth_surface.gdshader). À inclure après cloud_density.gdshaderinc (bruits 3D). Explosions : nuke_ground.gdshaderinc
// (alimenté par nuke/nuke_ground_fx.gd) ; lois et durées : NukeScaling (FIRE_*), transmises par NukeGroundFX.
//
// Zone du flash (rayon initial R0, exposition thermique suffisante pour enflammer les matériaux) : foyers allumés par
// le flash, qui forment une tempête de feu en ~1 h 30 ; la part du sol en feu y est forte près du centre (l'exposition
// décroît en 1/d²). Le front gagne ensuite les terres alentour sur plusieurs jours (rayon R0 · (1 + s · (1 − e^(−t/S)))) :
// chaque lieu s'embrase à l'arrivée du front, brûle (constante de temps d'extinction nuke_fire_burn_s.x), puis reste
// calciné pour toujours (noirci en nuke_fire_burn_s.y). Seulement sur les terres ; plus fort et plus vif dans les villes
// (combustible). Depuis l'orbite (~0,5 km par pixel), on ne distingue pas les flammes : on voit leur lueur moyenne,
// modulée par un motif irrégulier de 2 à 12 km (zones qui brûlent plus ou moins), qui scintille. Positions en km dans le
// repère de la planète. La luminance des flammes est faible devant un sol éclairé par le soleil : les feux se voient
// surtout de nuit ; le sol calciné, lui, se voit de jour.
#ifndef NUKE_FIRE_INC
#define NUKE_FIRE_INC

#include "res://nuke/shaders/nuke_ground.gdshaderinc"

uniform vec3 nuke_fire_color : source_color = vec3(1.0, 0.45, 0.12);
// Luminance HDR d'un sol entièrement en feu, à intensité 1 (la tempête de feu culmine vers 0,7).
uniform float nuke_fire_hdr = 1.6;
// Périodes de la texture de bruit pour le motif des zones en feu (km ; une période contient ~4 taches) ; la grande
// vaut 1,2 fois le rayon initial, plafonnée à nuke_fire_coarse_km.
uniform float nuke_fire_fine_km = 8.0;
uniform float nuke_fire_coarse_km = 60.0;
// Lois (NukeScaling, envoyées par NukeGroundFX) : (part des foyers du flash, début et fin de la tempête de feu en s),
// (extension relative du front, sa constante de temps en s), (part du sol en feu au passage du front, durée de
// l'embrasement en s), (constante de temps de l'extinction, durée du noircissement en s), irrégularité du bord.
uniform vec3 nuke_fire_growth_s = vec3(0.25, 120.0, 5400.0);
uniform vec2 nuke_fire_spread = vec2(1.0, 86400.0);
uniform vec2 nuke_fire_front = vec2(0.3, 3600.0);
uniform vec2 nuke_fire_burn_s = vec2(21600.0, 7200.0);
uniform float nuke_fire_edge_noise = 0.35;
// Sol calciné (cendres, végétation et bâtiments brûlés), visible de jour : albédo et part maximale du mélange.
uniform vec3 nuke_burn_albedo : source_color = vec3(0.16, 0.14, 0.12);
uniform float nuke_burn_strength = 0.85;

// État du sol au point p (km), de part de terre land (0 = eau) et d'urbanisation urban (0 à 1), pour les explosions de
// la maille cell (nuke_ground_cell) : (intensité des flammes, à multiplier par nuke_fire_color · nuke_fire_hdr ; part
// calcinée, 0 à 1).
vec2 nuke_fire_state(vec3 p, ivec2 cell, float land, float urban) {
	float total = 0.0;
	float charred = 0.0;
	for (int k = cell.x; k < cell.x + cell.y; k++) {
		NukeGroundEvent e = nuke_ground_event(k);
		float r0 = e.fire_km;
		if (r0 <= 0.0 || e.time_s <= 0.0) {
			continue;
		}
		float d = length(p - e.pos_km);
		if (d > r0 * (1.0 + nuke_fire_spread.x + nuke_fire_edge_noise)) {
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
		// Sol calciné : noirci à mesure qu'il brûle, plus nettement dans la zone du flash, définitif.
		float scorch = smoothstep(0.0, nuke_fire_burn_s.y, age) * mix(0.45, 1.0, pattern)
				* mix(1.0, 0.7, smoothstep(0.8, 1.2, x)) * (1.0 - smoothstep(0.85, 1.0, (x - 1.0) / nuke_fire_spread.x));
		charred = max(charred, land * scorch);
	}
	return vec2(total, charred);
}

#endif
