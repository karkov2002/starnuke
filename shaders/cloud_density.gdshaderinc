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

const float CLOUD_PLANET_RADIUS_KM = 6371.0;

float cloud_remap(float x, float a, float b, float c, float d) {
	return c + (x - a) / max(b - a, 1e-5) * (d - c);
}

// Même convention que les UV de SphereMesh (u = 0 vers +Z, croissant vers +X ; v = 0 au pôle nord).
vec2 cloud_dir_to_uv(vec3 n) {
	return vec2(fract(atan(n.x, n.z) / TAU), acos(clamp(n.y, -1.0, 1.0)) / PI);
}

// Couverture locale (x) et couverture moyenne à grande échelle, ~10 km (y), qui fixe l'épaisseur : un petit cumulus
// isolé reste bas même s'il est bien blanc, une masse étendue (front, cyclone) monte haut.
// lod : niveau de mipmap des tuiles 500 m (≈ log2(taille du pixel à l'écran / 0,5 km)).
vec2 cloud_coverage_at(vec3 n, float lod) {
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
	return smoothstep(vec2(cloud_coverage_low), vec2(cloud_coverage_high), c);
}

// with_detail = false pour les marches vers le soleil (moins coûteux).
float cloud_density(vec3 p, float time, bool with_detail, float lod) {
	float r = length(p);
	float h = (r - CLOUD_PLANET_RADIUS_KM - cloud_bottom_km) / (cloud_top_km - cloud_bottom_km);
	if (h <= 0.0 || h >= 1.0) {
		return 0.0;
	}
	vec2 coverage = cloud_coverage_at(p / r, lod);
	float cov = coverage.x;
	if (cov <= 0.005) {
		return 0.0;
	}
	vec3 q = p + cloud_wind_km_s * time;
	float billow = textureLod(cloud_shape_noise, q / cloud_shape_period_km, 0.0).r;
	float bumps = textureLod(cloud_shape_noise, q / cloud_top_detail_period_km + vec3(0.37, 0.11, 0.73), 0.0).r;
	float extent = coverage.y;
	float top = mix(cloud_thin_top, 1.0, extent * extent * cov)
			* (1.0 + cloud_top_billow * (2.0 * billow - 1.0) + cloud_top_detail * (2.0 * bumps - 1.0));
	float profile = smoothstep(0.0, 0.06, h) * (1.0 - smoothstep(top * 0.65, top, h));
	float density = cov * profile;
	if (density <= 0.0 || !with_detail) {
		return density;
	}
	float detail = textureLod(cloud_detail_noise, q / cloud_detail_period_km, 0.0).r;
	float erosion = cloud_edge_erosion * (1.0 - cov);
	return clamp(cloud_remap(density, detail * erosion, 1.0, 0.0, 1.0), 0.0, 1.0);
}

#endif
