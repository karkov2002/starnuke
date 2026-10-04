// Lumière solaire reçue en un point de l'atmosphère ou du sol, après traversée de l'atmosphère.
// Partagée entre la surface (earth_surface.gdshader) et les nuages (cloud_volume.gdshader), pour que le sol et
// les nuages rougissent puis s'éteignent progressivement au terminateur.
//
// - Soleil au-dessus de l'horizon local : masse d'air de Kasten-Young, pondérée par la densité à l'altitude du
//   point.
// - Soleil sous l'horizon local : le rayon a frôlé la Terre à l'altitude tangente ht ; la colonne d'air traversée
//   vaut ~sqrt(2π·R·H)·exp(−ht/H) (approximation de Chapman). La lumière passe du blanc au rouge puis s'éteint,
//   sans coupure nette (le disque solaire adoucit le passage dans l'ombre de la planète).
// Positions en km dans le repère de la planète, l = direction du soleil (unitaire).

const float SUN_PLANET_RADIUS_KM = 6371.0;
const vec3 SUN_RAYLEIGH_BETA = vec3(5.802e-3, 13.558e-3, 33.1e-3); // par km, au niveau de la mer
const float SUN_MIE_EXTINCTION = 4.4e-3;
const float SUN_RAYLEIGH_HEIGHT_KM = 8.0;
const float SUN_MIE_HEIGHT_KM = 1.2;

vec3 sun_transmittance_at(vec3 p, vec3 l) {
	float r = length(p);
	float h = max(r - SUN_PLANET_RADIUS_KM, 0.0);
	float mu = dot(p / r, l); // cosinus de l'angle zénithal du soleil
	vec2 column; // colonnes Rayleigh / Mie équivalentes au niveau de la mer (km)
	float visibility = 1.0;
	if (mu >= 0.0) {
		float z = degrees(acos(mu));
		float airmass = 1.0 / (mu + 0.50572 * pow(max(96.07995 - z, 0.01), -1.6364));
		column = vec2(SUN_RAYLEIGH_HEIGHT_KM * exp(-h / SUN_RAYLEIGH_HEIGHT_KM),
				SUN_MIE_HEIGHT_KM * exp(-h / SUN_MIE_HEIGHT_KM)) * airmass;
	} else {
		float ht = r * sqrt(1.0 - mu * mu) - SUN_PLANET_RADIUS_KM;
		// Juste sous l'horizon le rayon n'a parcouru qu'une demi-traversée rasante ; plus loin, une entière.
		float path = mix(0.5, 1.0, smoothstep(0.0, 0.05, -mu));
		column = path * vec2(
				sqrt(TAU * SUN_PLANET_RADIUS_KM * SUN_RAYLEIGH_HEIGHT_KM) * exp(-max(ht, 0.0) / SUN_RAYLEIGH_HEIGHT_KM),
				sqrt(TAU * SUN_PLANET_RADIUS_KM * SUN_MIE_HEIGHT_KM) * exp(-max(ht, 0.0) / SUN_MIE_HEIGHT_KM));
		visibility = smoothstep(-3.0, 3.0, ht);
	}
	return visibility * exp(-(SUN_RAYLEIGH_BETA * column.x + vec3(SUN_MIE_EXTINCTION * column.y)));
}
