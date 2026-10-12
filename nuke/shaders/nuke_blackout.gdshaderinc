// Black-out électrique des explosions nucléaires, appliqué aux lumières des villes dans le sol
// (earth_surface.gdshader). À inclure après cloud_density.gdshaderinc (bruit 3D). Explosions : nuke_ground.gdshaderinc
// (alimenté par nuke/nuke_ground_fx.gd) ; lois et durées : NukeScaling (BLACKOUT_*). Règle de jeu : le black-out dure
// jusqu'à la fin de la partie.
//
// nuke_blackout_darkness() rend la part des lumières éteintes (0 à 1) au point p (km, repère de la planète) :
// - zone détruite (rayon destroyed_km) : éteinte dès l'explosion, bord irrégulier ;
// - panne régionale (rayon region_km) : le front de la cascade avance du centre vers le bord, par plaques (bruit à
//   grosse maille) ;
// - panne nationale : tout le pays (carte nuke_country_ids, indice + 1 sur 16 bits) s'éteint par plaques en
//   national_off_s.
// Chaque plaque bascule sur une fenêtre de temps (pas de saut d'une image à l'autre).
#ifndef NUKE_BLACKOUT_INC
#define NUKE_BLACKOUT_INC

#include "res://nuke/shaders/nuke_ground.gdshaderinc"

// Pays plongés dans le noir : texture indexée par l'indice de pays + 1, temps physique écoulé depuis la panne (s, 0 :
// pas de panne) ; nuke_ground_country_count : nombre de pays dans le noir.
uniform int nuke_ground_country_count = 0;
uniform sampler2D nuke_ground_countries : filter_nearest, repeat_disable;
// Durées (s, temps physique), fournies par NukeGroundFX depuis NukeScaling.
uniform float nuke_blackout_cascade_tau_s = 15.0;
uniform float nuke_blackout_national_off_s = 30.0;
// Taille des plaques (km : quartiers, communes) et irrégularité du bord de la zone détruite (part du rayon).
uniform float nuke_blackout_patch_km = 18.0;
uniform float nuke_blackout_edge_noise = 0.15;
// Ville éteinte : lueur des terres au clair de lune (teinte du composite Black Marble, luminance ~1), luminance de
// la nuit plafonnée à nuke_blackout_unlit_luma, celle de la campagne non éclairée (quasi noire à l'écran, comme les
// zones privées de courant sur les images satellites de vrais black-outs).
uniform vec3 nuke_blackout_land_tint = vec3(0.8, 0.95, 1.35);
uniform float nuke_blackout_unlit_luma = 0.012;

// Bruit de plaques normalisé dans [0, 1] (le bruit fractal varie peu autour de 0,5).
float nuke_blackout_patch(vec3 uvw) {
	return clamp((textureLod(cloud_shape_noise, uvw, 0.0).r - 0.5) * 3.0 + 0.5, 0.0, 1.0);
}

// Plaque éteinte à partir de t_off (s) : 1 = éteinte ; bascule adoucie sur 5 % de la date (au moins 2 s).
float nuke_blackout_off(float t, float t_off) {
	return smoothstep(t_off, t_off + max(0.05 * t_off, 2.0), t);
}

// Part des lumières éteintes au point p (km) de normale n, pour les explosions de la maille cell (nuke_ground_cell).
float nuke_blackout_darkness(vec3 p, vec3 n, ivec2 cell) {
	float dark = 0.0;
	for (int k = cell.x; k < cell.x + cell.y; k++) {
		NukeGroundEvent e = nuke_ground_event(k);
		float t = e.time_s;
		float region = e.region_km;
		if (t <= 0.0) {
			continue;
		}
		vec3 v = p - e.pos_km;
		float d = length(v);
		if (d > region * 1.2) {
			continue;
		}
		// Zone détruite : bord irrégulier, à l'échelle de son rayon (motif fixe, centré sur l'explosion).
		float destroyed = e.destroyed_km;
		float wobble = nuke_blackout_patch(v / max(destroyed * 0.4, 0.5)) - 0.5;
		float r_destroyed = destroyed * (1.0 + 2.0 * nuke_blackout_edge_noise * wobble);
		dark = max(dark, 1.0 - smoothstep(r_destroyed * 0.95, r_destroyed * 1.05, d));
		// Panne régionale : chaque plaque a sa distance « vue par la cascade », éteinte au passage du front (inverse de
		// R · (1 − exp(−t / τ))).
		float patch = nuke_blackout_patch(v / nuke_blackout_patch_km);
		float d_patch = d * mix(0.8, 1.2, patch);
		if (d_patch > region) {
			continue;
		}
		float t_off = -nuke_blackout_cascade_tau_s * log(max(1.0 - d_patch / region, 1e-3));
		dark = max(dark, nuke_blackout_off(t, t_off));
		if (dark >= 1.0) {
			return 1.0;
		}
	}
	if (nuke_ground_country_count > 0) {
		int id = nuke_country_id(n);
		if (id > 0 && id < textureSize(nuke_ground_countries, 0).x) {
			float t = texelFetch(nuke_ground_countries, ivec2(id, 0), 0).r;
			if (t > 0.0) {
				float patch = nuke_blackout_patch(p / (2.0 * nuke_blackout_patch_km) + vec3(7.1, 2.9, 0.4));
				dark = max(dark, nuke_blackout_off(t, mix(0.15, 1.0, patch) * nuke_blackout_national_off_s));
			}
		}
	}
	return dark;
}

#endif
