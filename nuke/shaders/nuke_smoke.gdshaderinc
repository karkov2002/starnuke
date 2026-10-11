// Fumée des incendies des explosions nucléaires, dans le sol (earth_surface.gdshader). À inclure après
// cloud_density.gdshaderinc. Explosions : nuke_ground.gdshaderinc (alimenté par nuke/nuke_ground_fx.gd) ; lois :
// NukeScaling (SMOKE_*), transmises par NukeGroundFX. Sans panache (nuke_smoke_count = 0), rien n'est calculé.
//
// Panache gaussien intégré sur la verticale : la fumée émise à l'instant t − a se trouve à la distance u · a sous le
// vent (le long du grand cercle qui part du point zéro dans la direction du vent), étalée latéralement sur
// σ(a)² = σ0² + 2 K a, et se dépose (e^(−a / L)). Épaisseur optique verticale :
//   τ = MEE · Q(t − a) · e^(−a / L) / (u · √(2π) · σ(a)) · exp(−y² / 2σ²),
// Q = débit de fumée (kg/s) = émission par km² en feu × R0² × f(t − a), f lue dans nuke_smoke_rate (surface en feu en
// R0², même loi que les incendies de nuke_fire.gdshaderinc). Rendue comme une couche plate, sous les nuages (fumée de
// 1 à 6 km d'altitude ; vue de 400 km, sa parallaxe est négligeable) : elle voile le sol (albédo gris-brun éclairé par
// le soleil, rien la nuit), les lumières des villes et les reflets.
#ifndef NUKE_SMOKE_INC
#define NUKE_SMOKE_INC

#include "res://nuke/shaders/nuke_ground.gdshaderinc"

uniform int nuke_smoke_count = 0;
uniform sampler2D nuke_smoke_cells : filter_nearest, repeat_disable;
uniform sampler2D nuke_smoke_index : filter_nearest, repeat_disable;
// f(t) (NukeScaling.smoke_table), t en échelle log : coordonnée log(1 + t / 60) / nuke_smoke_rate_scale.
uniform sampler2D nuke_smoke_rate : filter_linear, repeat_disable;
uniform float nuke_smoke_rate_scale = 9.57;
// (émission en kg/s par km² en feu, efficacité d'extinction massique en m²/kg, diffusion horizontale K en m²/s,
// durée de vie L en s), (taille du foyer en part de R0, âge maximal du panache en s).
uniform vec4 nuke_smoke_physics = vec4(30.0, 5000.0, 5.0e4, 345600.0);
uniform vec2 nuke_smoke_source = vec2(0.7, 172800.0);
// Albédo d'une fumée épaisse vue de dessus (suie et goudrons : gris-brun) ; part de la lueur des incendies qui traverse
// une fumée opaque (diffusée par le panache).
uniform vec3 nuke_smoke_albedo : source_color = vec3(0.46, 0.39, 0.31);
uniform float nuke_smoke_fire_glow = 0.3;
// Structure du panache (volutes, traînées) : bruit à deux échelles (km), qui module l'épaisseur optique de
// ±nuke_smoke_structure ; il dérive lentement (nuke_smoke_drift_km_s) pour que le panache vive.
uniform vec2 nuke_smoke_scales_km = vec2(70.0, 18.0);
uniform float nuke_smoke_structure = 0.7;
uniform float nuke_smoke_drift_km_s = 0.004;

// Panaches qui passent sur le point de normale n : (début, nombre) dans nuke_smoke_index ; (0, 0) sans panache.
ivec2 nuke_smoke_cell(vec3 n) {
	if (nuke_smoke_count <= 0) {
		return ivec2(0);
	}
	vec2 list = texelFetch(nuke_smoke_cells, nuke_ground_texel(n), 0).rg;
	return ivec2(int(list.x + 0.5), int(list.y + 0.5));
}

// Surface en feu f (R0²) au temps t (s) depuis l'explosion ; 0 avant l'explosion et après la table (tout est éteint).
float nuke_smoke_burning(float t) {
	if (t <= 0.0) {
		return 0.0;
	}
	float coord = log(1.0 + t / 60.0) / nuke_smoke_rate_scale;
	if (coord >= 1.0) {
		return 0.0;
	}
	float size = float(textureSize(nuke_smoke_rate, 0).x);
	return textureLod(nuke_smoke_rate, vec2((coord * (size - 1.0) + 0.5) / size, 0.5), 0.0).r;
}

// Épaisseur optique verticale de la fumée au point de normale n, pour les panaches de la maille cell.
float nuke_smoke_tau(vec3 n, ivec2 cell) {
	float tau = 0.0;
	for (int k = cell.x; k < cell.x + cell.y; k++) {
		ivec2 texel = ivec2(k % NUKE_GROUND_INDEX_WIDTH, k / NUKE_GROUND_INDEX_WIDTH);
		NukeGroundEvent e = nuke_ground_event_at(int(texelFetch(nuke_smoke_index, texel, 0).r + 0.5));
		vec4 wind = nuke_ground_row(e.id, 2);
		vec3 origin = normalize(e.pos_km);
		vec3 left = cross(origin, wind.xyz);
		// Repère du panache : distance sous le vent le long du grand cercle, écart latéral (m).
		float along = CLOUD_PLANET_RADIUS_KM * 1000.0 * atan(dot(n, wind.xyz), dot(n, origin));
		float lateral = CLOUD_PLANET_RADIUS_KM * 1000.0 * asin(clamp(dot(n, left), -1.0, 1.0));
		float age = max(along, 0.0) / wind.w;
		if (age > nuke_smoke_source.y) {
			continue;
		}
		float burning = nuke_smoke_burning(e.time_s - age);
		if (burning <= 0.0) {
			continue;
		}
		float sigma0 = nuke_smoke_source.x * e.fire_km * 1000.0;
		float sigma2 = sigma0 * sigma0 + 2.0 * nuke_smoke_physics.z * age;
		// Au vent du foyer, la fumée ne déborde que de la taille du foyer.
		float upwind = along < 0.0 ? exp(-along * along / (2.0 * sigma0 * sigma0)) : 1.0;
		float rate = nuke_smoke_physics.x * e.fire_km * e.fire_km * burning;
		// Fin du panache (âge maximal) adoucie : la fumée diluée s'y fond dans le voile général.
		float tail = 1.0 - smoothstep(0.6 * nuke_smoke_source.y, nuke_smoke_source.y, age);
		float column = rate * exp(-age / nuke_smoke_physics.w) / (wind.w * 2.5066283 * sqrt(sigma2))
				* exp(-lateral * lateral / (2.0 * sigma2)) * upwind * tail;
		tau += nuke_smoke_physics.y * column;
	}
	if (tau <= 0.0) {
		return 0.0;
	}
	// Volutes : le bruit fractal varie peu autour de 0,5, normalisé dans [−1, 1].
	vec3 p = n * CLOUD_PLANET_RADIUS_KM + vec3(TIME * nuke_smoke_drift_km_s);
	float coarse = textureLod(cloud_shape_noise, p / nuke_smoke_scales_km.x + vec3(0.17, 0.41, 0.83), 0.0).r;
	float fine = textureLod(cloud_shape_noise, p / nuke_smoke_scales_km.y + vec3(0.62, 0.05, 0.37), 0.0).r;
	float structure = clamp(((coarse - 0.5) * 0.65 + (fine - 0.5) * 0.35) * 4.0, -1.0, 1.0);
	return tau * max(1.0 + nuke_smoke_structure * structure, 0.05);
}

#endif
