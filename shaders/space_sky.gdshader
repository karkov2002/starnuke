// Ciel vu depuis l'orbite : panorama étoilé HDR (carte NASA en coordonnées équatoriales) + disque solaire.
// Les directions (EYEDIR, sun_direction) sont dans le repère du ciel : Godot applique l'inverse de
// Environment.sky_rotation aux directions de vue, et orbit.gd convertit le soleil et l'observateur dans ce repère.
//
// Disque solaire : rayon angulaire réel (0,267°), assombrissement centre-bord, luminance très supérieure à celle
// du sol éclairé (il sature et le bloom de l'Environment produit l'éblouissement). Près du limbe, son rayon
// traverse l'atmosphère : on applique la transmittance spectrale du même modèle que atmosphere.gdshader. Comme la
// sphère AtmosphereSky, rendue par-dessus, atténue déjà le fond de la transmittance moyenne (alpha gris), le
// ciel n'applique que le rapport T / moyenne(T) : le résultat final vaut T, donc le soleil rougit puis s'éteint
// en passant derrière le limbe. La Terre, opaque, le masque ensuite par simple test de profondeur.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
// Étoiles atténuées : l'exposition automatique (materials/camera_attributes.tres) remonte l'image jusqu'à × 2,5 la
// nuit, où elles retrouvent leur éclat ; de jour, et surtout face au soleil, elles s'effacent.
uniform float panorama_energy = 0.4;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // repère du ciel, vers le soleil
uniform vec3 observer_km = vec3(0.0, 6771.0, 0.0); // position de l'observateur / centre de la Terre, repère du ciel
uniform float sun_angular_radius_deg = 0.2666;
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.95);
// Luminance du disque (unités HDR de la scène). La vraie valeur (~10⁵ fois le sol éclairé) dépasse le format
// flottant du rendu (16 bits, max 65504). 40 000 suffit pour que le disque, quand il est visible, domine la
// luminance moyenne de l'image : l'exposition automatique baisse (Terre plus sombre, étoiles effacées), et le glow
// (niveaux larges, mode additif) en tire l'éblouissement, par-dessus la station. Masqué par la station ou la Terre,
// il ne compte plus.
uniform float sun_disc_energy = 40000.0;
// Assombrissement centre-bord (loi linéaire I = 1 − u·(1 − μ)), plus marqué dans le bleu.
uniform vec3 limb_darkening = vec3(0.5, 0.6, 0.75);
uniform int sun_steps = 24;

#include "res://shaders/atmosphere_common.gdshaderinc"

// Transmittance de l'atmosphère le long du rayon de vue (0 s'il touche la planète).
vec3 view_transmittance(vec3 ro, vec3 rd) {
	vec2 ground = ray_sphere(ro, rd, planet_radius_km);
	if (ground.x > 0.0 && ground.x < 1e8) {
		return vec3(0.0);
	}
	vec2 atmo = ray_sphere(ro, rd, atmosphere_radius());
	float t0 = max(atmo.x, 0.0);
	float t1 = atmo.y;
	if (t1 <= t0) {
		return vec3(1.0);
	}
	// Pas resserrés autour du point le plus bas du rayon (tc), comme dans atmosphere.gdshader.
	float tc = clamp(-dot(ro, rd), t0, t1);
	int half_steps = max(sun_steps / 2, 1);
	vec3 od = vec3(0.0);
	for (int seg = 0; seg < 2; seg++) {
		float len = seg == 0 ? tc - t0 : t1 - tc;
		if (len <= 0.0) {
			continue;
		}
		for (int i = 0; i < half_steps; i++) {
			float u0 = float(i) / float(half_steps);
			float u1 = float(i + 1) / float(half_steps);
			float ta;
			float tb;
			if (seg == 0) {
				ta = tc - len * (1.0 - u0) * (1.0 - u0);
				tb = tc - len * (1.0 - u1) * (1.0 - u1);
			} else {
				ta = tc + len * u0 * u0;
				tb = tc + len * u1 * u1;
			}
			vec3 p = ro + rd * (0.5 * (ta + tb));
			od += densities(length(p) - planet_radius_km) * (tb - ta);
		}
	}
	return exp(-extinction(od));
}

void sky() {
	COLOR = texture(panorama, SKY_COORDS).rgb * panorama_energy;

	// Disque solaire (pas dans la carte de radiance, inutilisée : ambiance et reflets ne viennent pas du ciel).
	vec3 l = normalize(sun_direction);
	float radius = radians(sun_angular_radius_deg);
	float angle = acos(clamp(dot(EYEDIR, l), -1.0, 1.0));
	// Bord du disque anticrénelé sur un pixel (le disque ne fait que quelques pixels de diamètre).
	float pixel = max(fwidth(angle), 1e-6);
	float coverage = clamp((radius - angle) / pixel + 0.5, 0.0, 1.0);
	if (!AT_CUBEMAP_PASS && coverage > 0.0) {
		float r = min(angle / radius, 1.0);
		float mu = sqrt(1.0 - r * r);
		vec3 disc = sun_color * sun_disc_energy * (vec3(1.0) - limb_darkening * (1.0 - mu));
		vec3 t = view_transmittance(observer_km, EYEDIR);
		float t_mean = dot(t, vec3(1.0 / 3.0));
		vec3 tint = t_mean > 1e-4 ? t / t_mean : vec3(0.0);
		COLOR += disc * tint * coverage;
	}
}
