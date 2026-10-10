// Surface terrestre.
// - Texture globale Blue Marble NG (16K, ~2,4 km/px) partout.
// - Sous l'observateur : fenêtre de 5 x 5 tuiles de 5° en 500 m/px (Texture2DArray alimenté par
//   scripts/earth_detail_tiles.gd), fondue dans la texture globale sur ses bords.
// - Masque d'eau approximatif (eau = sombre et bleue) pour le reflet spéculaire du soleil sur les océans.
// - Ombres portées des nuages procéduraux (même fonction de densité que cloud_volume.gdshader).
// - Lumières des villes la nuit (Black Marble 2016, globale 16K + tuiles HD), en émission.
// - Éclairage personnalisé (light()) : lumière solaire teintée par la traversée de l'atmosphère
//   (sun_light.gdshaderinc, rougissement puis extinction progressive au terminateur), reflet spéculaire GGX,
//   plus la lumière diffuse du ciel qui persiste au crépuscule (jusqu'à ~12° sous l'horizon).
// La brume / perspective aérienne est calculée par le shader d'atmosphère.
shader_type spatial;
// Pas de lumière ambiante de l'Environment (réglée pour l'intérieur de la station) : vue de l'espace, la face
// nocturne n'est éclairée que par ses propres émissions (villes, lueur du composite NASA, ciel au crépuscule).
render_mode cull_back, ambient_light_disabled;

#include "res://shaders/cloud_density.gdshaderinc"
#include "res://shaders/sun_light.gdshaderinc"
#include "res://nuke/shaders/nuke_flash.gdshaderinc"
#include "res://nuke/shaders/nuke_fire.gdshaderinc"
#include "res://nuke/shaders/nuke_blackout.gdshaderinc"

uniform sampler2D day_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray night_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool night_detail_ready = false;
uniform float land_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float ocean_roughness : hint_range(0.0, 1.0) = 0.22;
uniform float ocean_specular : hint_range(0.0, 1.0) = 0.6;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // espace monde, vers le soleil
uniform float units_to_km = 10.0;
// Part de la lumière supprimée sous un nuage opaque (le reste : lumière diffuse du ciel).
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.8;
uniform int cloud_shadow_samples = 4;
// Lumières nocturnes.
uniform float night_intensity = 1.6;
uniform float night_sun_low = -0.12; // sin(hauteur du soleil) : nuit complète en dessous (~ -7°)
uniform float night_sun_high = 0.03; // lumières éteintes au-dessus (~ +2°)
uniform float night_lights_low = 0.08;
uniform float night_lights_high = 0.3;
uniform float night_land_level = 0.25;
uniform float night_cloud_floor = 0.2; // part de lumière qui traverse un nuage opaque
// Lumière diffuse du ciel (bleutée), qui éclaire encore le sol pendant le crépuscule.
uniform vec3 sky_light_color : source_color = vec3(0.42, 0.5, 0.78);
uniform float sky_light_intensity = 0.2;
uniform float twilight_end = -0.21; // sin(hauteur du soleil) où le ciel ne diffuse plus (~ -12°)

varying vec3 local_km;
// Lumière solaire relative reçue au sol (transmittance atmosphérique × ombre des nuages), lue par light().
varying vec3 v_sun_light;
varying float v_specular;

void vertex() {
	local_km = VERTEX * units_to_km;
}

// Transmittance de la couche nuageuse le long du rayon solaire partant du sol.
float cloud_shadow(vec3 n, vec3 l, CloudAdvection adv) {
	float mu = dot(n, l);
	if (mu <= 0.02) {
		return 1.0;
	}
	vec3 ground = n * CLOUD_PLANET_RADIUS_KM;
	float thickness = cloud_top_km - cloud_bottom_km;
	float od = 0.0;
	for (int i = 0; i < cloud_shadow_samples; i++) {
		float h = cloud_bottom_km + (float(i) + 0.5) / float(cloud_shadow_samples) * thickness;
		od += cloud_density(ground + l * (h / mu), TIME, true, 0.0, adv);
	}
	od *= thickness / float(cloud_shadow_samples) / mu;
	return exp(-cloud_extinction_per_km * od);
}

void fragment() {
	vec3 albedo = texture(day_texture, UV).rgb;
	vec3 night = texture(night_texture, UV).rgb;

	vec2 gdx = dFdx(UV * DETAIL_GRID);
	vec2 gdy = dFdy(UV * DETAIL_GRID);
	vec3 tile_uv;
	float blend = detail_lookup(UV, tile_uv);
	if (blend > 0.0) {
		albedo = mix(albedo, textureGrad(detail_tiles, tile_uv, gdx, gdy).rgb, blend);
		if (night_detail_ready) {
			night = mix(night, textureGrad(night_tiles, tile_uv, gdx, gdy).rgb, blend);
		}
	}

	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	float water = smoothstep(0.015, 0.06, albedo.b - albedo.r) * (1.0 - smoothstep(0.18, 0.3, luma));
	vec3 n = normalize(local_km);
	vec3 l = normalize(transpose(mat3(MODEL_MATRIX)) * sun_direction);
	CloudAdvection adv = cloud_advection(n);
	float shadow = cloud_shadow(n, l, adv);
	float mu = dot(n, l);
	v_sun_light = sun_transmittance_at(n * SUN_PLANET_RADIUS_KM, l) * mix(1.0 - cloud_shadow_strength, 1.0, shadow);
	v_specular = mix(0.25, ocean_specular, water) * shadow;
	ALBEDO = albedo;
	ROUGHNESS = mix(land_roughness, ocean_roughness, water);
	SPECULAR = v_specular;
	vec3 emission = albedo * sky_light_color * sky_light_intensity * smoothstep(twilight_end, 0.05, mu);

	// Lumières nocturnes (Black Marble) : allumées quand le soleil passe sous l'horizon local (crépuscule),
	// voilées par les nuages au-dessus (transmittance verticale). La faible lueur bleutée des terres (clair de
	// lune du composite NASA) est atténuée pour garder les villes dominantes.
	float darkness = 1.0 - smoothstep(night_sun_low, night_sun_high, mu);
	if (darkness > 0.0) {
		float night_luma = dot(night, vec3(0.299, 0.587, 0.114));
		float lights = smoothstep(night_lights_low, night_lights_high, night_luma);
		vec3 glow = night * mix(night_land_level, 1.0, lights);
		// Black-out des explosions (nuke/shaders/nuke_blackout.gdshaderinc) : une ville éteinte retombe à la lueur
		// naturelle des terres alentour (gris bleuté du clair de lune, luminance de la campagne non éclairée),
		// pas à une version atténuée d'elle-même (l'orange des lampes au sodium resterait en tache brune). Rien de
		// visible de jour (darkness = 0).
		if (nuke_blackout_count > 0 || nuke_blackout_country_count > 0) {
			float off = nuke_blackout_darkness(n * CLOUD_PLANET_RADIUS_KM, n);
			vec3 unlit = nuke_blackout_land_tint * (night_land_level * min(night_luma, nuke_blackout_unlit_luma));
			glow = mix(glow, unlit, off);
		}
		float clouds_above = cloud_shadow(n, n, adv);
		emission += glow * night_intensity * darkness * mix(night_cloud_floor, 1.0, clouds_above);
	}
	// Flashs nucléaires (nuke/shaders/nuke_flash.gdshaderinc) : en émission, de jour comme de nuit.
	if (nuke_flash_count > 0) {
		emission += albedo * nuke_flash_color * nuke_flash_ground_gain
				* nuke_flash_ground(n * CLOUD_PLANET_RADIUS_KM, n, adv);
	}
	// Incendies allumés par les explosions (nuke/shaders/nuke_fire.gdshaderinc), voilés par les nuages comme les
	// lumières des villes.
	if (nuke_fire_count > 0) {
		float urban = smoothstep(0.05, 0.3, dot(night, vec3(0.299, 0.587, 0.114)));
		vec3 fire = nuke_fire_emission(n * CLOUD_PLANET_RADIUS_KM, 1.0 - water, urban);
		// Voile des nuages (marche coûteuse) seulement là où il y a du feu, pas sur tout le globe.
		if (fire.r + fire.g + fire.b > 0.0) {
			emission += fire * mix(night_cloud_floor, 1.0, cloud_shadow(n, n, adv));
		}
	}
	EMISSION = emission;
}

// Lambert + GGX, avec la lumière solaire teintée par l'atmosphère (v_sun_light). LIGHT_COLOR inclut un facteur PI.
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 radiance = LIGHT_COLOR * ATTENUATION * v_sun_light;
	DIFFUSE_LIGHT += radiance * ndl / PI;

	vec3 h = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, h), 0.0);
	float ndv = max(dot(NORMAL, VIEW), 1e-4);
	float a = max(ROUGHNESS * ROUGHNESS, 1e-3);
	float a2 = a * a;
	float denom = ndh * ndh * (a2 - 1.0) + 1.0;
	float distribution = a2 / (PI * denom * denom);
	float k = 0.5 * a;
	float visibility = 0.25 / ((ndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float f0 = 0.16 * v_specular * v_specular;
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	SPECULAR_LIGHT += radiance * ndl * distribution * visibility * fresnel / PI;
}
