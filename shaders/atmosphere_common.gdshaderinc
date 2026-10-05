// Modèle d'atmosphère partagé entre la diffusion atmosphérique (atmosphere.gdshader) et le ciel
// (space_sky.gdshader, qui atténue le disque solaire avec la même extinction que le halo du limbe).
// Distances en km, positions dans le repère de la planète (centre = origine).

uniform float planet_radius_km = 6371.0;
uniform float atmosphere_thickness_km = 100.0;
// Étirement vertical artistique de l'atmosphère : les hauteurs d'échelle sont multipliées et les
// coefficients divisés d'autant. L'opacité à la verticale (voile au-dessus du sol) est inchangée, mais le
// halo du limbe devient plus épais et plus diffus. 1 = Terre réelle.
uniform float height_scale = 2.5;
// Coefficients par km (valeurs terrestres usuelles).
uniform vec3 rayleigh_beta = vec3(5.802e-3, 13.558e-3, 33.1e-3);
uniform float rayleigh_height_km = 8.0;
uniform float mie_beta = 3.996e-3;
uniform float mie_extinction_ratio = 1.11;
uniform float mie_height_km = 1.2;
uniform vec3 ozone_beta = vec3(0.650e-3, 1.881e-3, 0.085e-3);
uniform float ozone_center_km = 25.0;
uniform float ozone_half_width_km = 15.0;


vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

float atmosphere_radius() {
	return planet_radius_km + atmosphere_thickness_km * height_scale;
}

// Densités relatives (Rayleigh, Mie, ozone) à une altitude donnée.
vec3 densities(float h) {
	h = max(h, 0.0) / height_scale;
	return vec3(
		exp(-h / rayleigh_height_km),
		exp(-h / mie_height_km),
		max(0.0, 1.0 - abs(h - ozone_center_km) / ozone_half_width_km));
}

vec3 extinction(vec3 od) {
	return (rayleigh_beta * od.x + vec3(mie_beta * mie_extinction_ratio) * od.y + ozone_beta * od.z) / height_scale;
}
