// Densité des nuages, partagée entre le rendu volumétrique (cloud_volume.gdshader) et les ombres portées / le
// voilage des lumières au sol (earth_surface.gdshader). Positions en km dans le repère de la planète (qui tourne
// avec elle) : les nuages restent accrochés aux continents.
//
// - Où et combien : carte de couverture issue d'une vraie journée d'imagerie satellite (VIIRS NOAA-20, 15 juillet
//   2023, couche alpha obtenue par différence avec la Blue Marble sans nuages, cf. tools/build_cloud_tiles.ps1) :
//   globale 16K (~2,4 km/px) et tuiles 500 m/px autour de la station (fenêtre de detail_window.gdshaderinc).
//   Cyclones, fronts, bancs de stratocumulus, amas orageux… viennent directement des données.
// - Épaisseur : la couverture moyenne à grande échelle fixe la hauteur du sommet (cumulus épars ou voile fin = bas,
//   masse étendue et épaisse = haute, jusqu'à cloud_top_km). Le sommet est bosselé par un bruit 3D doux ; les masses restent
//   continues (pas de seuillage d'un bruit cellulaire, qui donnait un aspect « billes de polystyrène »).
// - Détail : un bruit de Worley érode seulement les bords (couverture partielle) pour les effilocher.
#ifndef CLOUD_DENSITY_INC
#define CLOUD_DENSITY_INC

#include "res://shaders/detail_window.gdshaderinc"

uniform sampler2D cloud_coverage : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray cloud_tiles : filter_linear_mipmap, repeat_disable;
uniform bool cloud_detail_ready = false;
uniform sampler3D cloud_shape_noise : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_bottom_km = 3.0;
uniform float cloud_top_km = 10.0;
uniform float cloud_coverage_low = 0.04;
uniform float cloud_coverage_high = 0.85;
// Hauteur relative du sommet d'un voile très fin (1 = cloud_top_km pour une couverture totale).
uniform float cloud_thin_top = 0.15;
// Amplitude du bosselage des sommets (part de la hauteur) et période du bruit correspondant.
uniform float cloud_top_billow = 0.35;
uniform float cloud_shape_period_km = 50.0;
// Relief fin des sommets (aspect « chou-fleur » des nuages convectifs), en part de la hauteur.
uniform float cloud_top_detail = 0.14;
uniform float cloud_top_detail_period_km = 8.0;
uniform float cloud_detail_period_km = 5.0;
uniform float cloud_edge_erosion = 0.55;
// Niveau de mipmap des tuiles 500 m servant à estimer l'étendue d'une masse nuageuse (4 = 8 km).
uniform float cloud_height_lod = 4.0;
uniform float cloud_extinction_per_km = 1.5;
uniform vec3 cloud_wind_km_s = vec3(0.010, 0.0, 0.004);

// Advection par le vent réel : la carte de couverture est un instantané (passage de NOAA-20 vers 13 h 30, heure
// solaire locale, le 15 juillet 2023). Pour l'heure UTC courante, on remonte le vent (cloud_wind : vent moyen GFS du
// même jour, est / nord en m/s, cf. tools/build_wind_field.ps1) jusqu'à l'heure du passage, et on lit la carte au
// point de départ : les nuages dérivent avec la vraie circulation (alizés, courants-jets, rotation des cyclones).
// L'écart de temps est ramené dans [−12 h, +12 h] (la météo du jour se répète chaque jour) ; près de ±12 h, soit vers
// 1 h 30 du matin, côté nuit, on fond les deux trajectoires (−12 h et +12 h) pour éviter un saut.
uniform sampler2D cloud_wind : filter_linear, repeat_enable;
uniform float cloud_utc_day_s = 34200.0; // heure UTC courante, en secondes depuis minuit (fournie par Orbit)
uniform float cloud_snapshot_local_hour = 13.5;
uniform float cloud_wind_scale = 1.0;
uniform float cloud_advection_blend_h = 1.5;
const int CLOUD_ADVECTION_STEPS = 6;

const float CLOUD_PLANET_RADIUS_KM = 6371.0;

// Trous creusés par les explosions nucléaires (seul code des explosions dans ce fichier, avec l'appel dans
// cloud_density) : suivis automatiquement par les ombres au sol, qui lisent la même densité.
#include "res://nuke/shaders/nuke_clouds.gdshaderinc"

// Déplacement (sur la sphère unité) de la position lue dans l'instantané : d0, et d1 pour l'autre trajectoire,
// mélangée avec le poids w (0 hors de la transition de ±12 h).
struct CloudAdvection {
	vec3 d0;
	vec3 d1;
	float w;
};

float cloud_remap(float x, float a, float b, float c, float d) {
	return c + (x - a) / max(b - a, 1e-5) * (d - c);
}

// Même convention que les UV de SphereMesh (u = 0 vers +Z, croissant vers +X ; v = 0 au pôle nord).
vec2 cloud_dir_to_uv(vec3 n) {
	return vec2(fract(atan(n.x, n.z) / TAU), acos(clamp(n.y, -1.0, 1.0)) / PI);
}

// Vent à la position n (sphère unité), en vitesse angulaire tangente (rad/s).
vec3 cloud_wind_at(vec3 n) {
	vec3 east = vec3(n.z, 0.0, -n.x); // = cross(nord du globe, n)
	float len = length(east);
	if (len < 1e-4) {
		return vec3(0.0);
	}
	east /= len;
	vec3 north = cross(n, east);
	vec2 uv = cloud_dir_to_uv(n);
	uv.y = clamp(uv.y, 0.5 / 360.0, 1.0 - 0.5 / 360.0);
	vec2 wind = textureLod(cloud_wind, uv, 0.0).rg;
	return (east * wind.x + north * wind.y) * (cloud_wind_scale / (CLOUD_PLANET_RADIUS_KM * 1000.0));
}

// Position, dans l'instantané, de l'air qui se trouve en n après dt secondes (trajectoire remontée, Runge-Kutta 2).
vec3 cloud_backtrace(vec3 n, float dt) {
	float h = dt / float(CLOUD_ADVECTION_STEPS);
	for (int i = 0; i < CLOUD_ADVECTION_STEPS; i++) {
		vec3 mid = normalize(n - cloud_wind_at(n) * (0.5 * h));
		n = normalize(n - cloud_wind_at(mid) * h);
	}
	return n;
}

// Advection pour un point de référence n (un rayon de vue, un pixel du sol) ; le déplacement obtenu est appliqué
// à tous les échantillons voisins (le champ de vent varie peu à l'échelle d'un rayon).
CloudAdvection cloud_advection(vec3 n) {
	CloudAdvection a;
	float lon_deg = cloud_dir_to_uv(n).x * 360.0 - 180.0;
	float snapshot_utc_s = (cloud_snapshot_local_hour - lon_deg / 15.0) * 3600.0;
	float dt = mod(cloud_utc_day_s - snapshot_utc_s + 43200.0, 86400.0) - 43200.0;
	a.d0 = cloud_backtrace(n, dt) - n;
	a.w = 0.5 * smoothstep(43200.0 - cloud_advection_blend_h * 3600.0, 43200.0, abs(dt));
	a.d1 = a.w > 0.0 ? cloud_backtrace(n, dt - sign(dt) * 86400.0) - n : a.d0;
	return a;
}

CloudAdvection cloud_no_advection() {
	CloudAdvection a;
	a.d0 = vec3(0.0);
	a.d1 = vec3(0.0);
	a.w = 0.0;
	return a;
}

// Couverture locale (x) et couverture moyenne à grande échelle, ~10 km (y), qui fixe l'épaisseur : un petit cumulus
// isolé reste bas même s'il est bien blanc, une masse étendue (front, cyclone) monte haut.
// n : position dans l'instantané (déjà advectée). lod : niveau de mipmap des tuiles 500 m (≈ log2(taille du pixel à
// l'écran / 0,5 km)).
vec2 cloud_coverage_raw(vec3 n, float lod) {
	vec2 uv = cloud_dir_to_uv(n);
	float lod_global = max(lod - 2.0, 0.0); // texture globale : texels 4 fois plus grands
	vec2 c = vec2(textureLod(cloud_coverage, uv, lod_global).r,
			textureLod(cloud_coverage, uv, max(lod_global, cloud_height_lod - 2.0)).r);
	if (cloud_detail_ready) {
		vec3 tile_uv;
		float w = detail_lookup(uv, tile_uv);
		if (w > 0.0) {
			vec2 hd = vec2(textureLod(cloud_tiles, tile_uv, lod).r,
					textureLod(cloud_tiles, tile_uv, max(lod, cloud_height_lod)).r);
			c = mix(c, hd, w);
		}
	}
	return c;
}

vec2 cloud_coverage_at(vec3 n, float lod, CloudAdvection adv) {
	vec2 c = cloud_coverage_raw(normalize(n + adv.d0), lod);
	if (adv.w > 0.0) {
		c = mix(c, cloud_coverage_raw(normalize(n + adv.d1), lod), adv.w);
	}
	return smoothstep(vec2(cloud_coverage_low), vec2(cloud_coverage_high), c);
}

// with_detail = false pour les marches vers le soleil (moins coûteux). nuke_mask : explosions à prendre en compte (bit i
// = explosion i ; NUKE_ALL_EVENTS : toutes). Un rayon de vue calcule son masque une fois (nuke_cloud_events_near_segment)
// au lieu de tester toutes les explosions à chaque échantillon.
float cloud_density_masked(vec3 p, float time, bool with_detail, float lod, CloudAdvection adv, int nuke_mask) {
	float r = length(p);
	float h = (r - CLOUD_PLANET_RADIUS_KM - cloud_bottom_km) / (cloud_top_km - cloud_bottom_km);
	if (h <= 0.0 || h >= 1.0) {
		return 0.0;
	}
	vec3 n = p / r;
	// Explosions (nuke/shaders/nuke_clouds.gdshaderinc) : trou, nuages poussés (carte lue en read_n), bourrelet.
	vec3 read_n = n;
	float rim = 0.0;
	float squeeze = 1.0;
	float keep = nuke_cloud_count > 0 && nuke_mask != 0 ? nuke_cloud_warp(n, read_n, rim, squeeze, nuke_mask) : 1.0;
	vec2 coverage = cloud_coverage_at(read_n, lod + log2(squeeze), adv);
	float cov = coverage.x * keep;
	if (cov <= 0.005) {
		return 0.0;
	}
	// Le relief des sommets suit les nuages (bruit lu, lui aussi, à la position advectée).
	vec3 q = normalize(read_n + adv.d0) * r + cloud_wind_km_s * time;
	float billow = textureLod(cloud_shape_noise, q / cloud_shape_period_km, 0.0).r;
	float bumps = textureLod(cloud_shape_noise, q / cloud_top_detail_period_km + vec3(0.37, 0.11, 0.73), 0.0).r;
	float extent = coverage.y;
	float top = mix(cloud_thin_top, 1.0, extent * extent * cov)
			* (1.0 + cloud_top_billow * (2.0 * billow - 1.0) + cloud_top_detail * (2.0 * bumps - 1.0))
			* (1.0 + nuke_cloud_rim_lift * rim);
	float profile = smoothstep(0.0, 0.06, h) * (1.0 - smoothstep(top * 0.65, top, h));
	float density = cov * profile;
	if (density <= 0.0 || !with_detail) {
		return density * (1.0 + rim);
	}
	float detail = textureLod(cloud_detail_noise, q / cloud_detail_period_km, 0.0).r;
	float erosion = cloud_edge_erosion * (1.0 - cov);
	return clamp(cloud_remap(density, detail * erosion, 1.0, 0.0, 1.0), 0.0, 1.0) * (1.0 + rim);
}

// Densité en tenant compte de toutes les explosions (ombres au sol, lumière des flashs).
float cloud_density(vec3 p, float time, bool with_detail, float lod, CloudAdvection adv) {
	return cloud_density_masked(p, time, with_detail, lod, adv, NUKE_ALL_EVENTS);
}

#endif
