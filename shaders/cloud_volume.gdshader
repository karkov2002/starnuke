// Nuages volumétriques procéduraux entre cloud_bottom_km et cloud_top_km (3 à 10 km d'altitude), rendus par
// lancer de rayon sur une sphère englobante (faces avant ; la caméra est toujours au-dessus des nuages).
// Éclairage : marche vers le soleil (auto-ombrage, loi de Beer + approximation de la diffusion multiple),
// fonction de phase double Henyey-Greenstein (liseré lumineux à contre-jour), lumière solaire rougie puis éteinte
// progressivement par l'atmosphère (sun_light.gdshaderinc), lumière ambiante du ciel. Ombres au sol : earth_surface.
// Mélange prémultiplié ; rendu avant l'atmosphère (render_priority 0 < 1).
shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/cloud_density.gdshaderinc"
#include "res://shaders/sun_light.gdshaderinc"
#include "res://nuke/shaders/nuke_flash.gdshaderinc"

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // espace monde, vers le soleil
uniform float units_to_km = 10.0;
uniform float sun_intensity = 1.7;
// Part de lumière conservée dans l'épaisseur du nuage (approximation de la diffusion multiple).
uniform float multiple_scattering = 0.4;
uniform vec3 sky_ambient : source_color = vec3(0.45, 0.6, 0.9);
uniform float ambient_intensity = 0.22;
uniform float phase_forward = 0.6;
uniform float phase_backward = -0.25;
uniform float phase_backward_weight = 0.3;
uniform int max_steps = 72;
uniform float min_step_km = 0.2;
uniform int light_steps = 5;
uniform float light_first_step_km = 0.3;

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

float henyey_greenstein(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

void fragment() {
	mat3 to_local = transpose(mat3(MODEL_MATRIX));
	vec3 cam_w = INV_VIEW_MATRIX[3].xyz;
	vec3 frag_w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 ro = to_local * (cam_w - center) * units_to_km;
	vec3 rd = normalize(to_local * (frag_w - cam_w));
	vec3 l = normalize(to_local * sun_direction);

	float rb = CLOUD_PLANET_RADIUS_KM + cloud_bottom_km;
	float rt = CLOUD_PLANET_RADIUS_KM + cloud_top_km;
	vec2 top = ray_sphere(ro, rd, rt);
	if (top.x > 1e8 || top.y < 0.0) {
		discard;
	}
	float t0 = max(top.x, 0.0);
	float t1 = top.y;
	vec2 bottom = ray_sphere(ro, rd, rb);
	if (bottom.x > 0.0 && bottom.x < 1e8) {
		t1 = min(t1, bottom.x);
	}
	if (t1 <= t0) {
		discard;
	}

	float len = t1 - t0;
	int steps = clamp(int(len / min_step_km), 12, max_steps);
	float dt = len / float(steps);
	// Décalage pseudo-aléatoire par pixel (bruit de gradient entrelacé) contre les bandes d'échantillonnage.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	// Taille angulaire d'un pixel : sert à choisir le niveau de détail des tuiles nuageuses selon la distance.
	float pixel_angle = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float mu = dot(rd, l);
	float phase = 4.0 * PI * mix(henyey_greenstein(mu, phase_forward), henyey_greenstein(mu, phase_backward),
			phase_backward_weight);

	// Advection des nuages par le vent, calculée une fois par rayon (au milieu du trajet dans la couche).
	CloudAdvection adv = cloud_advection(normalize(ro + rd * (0.5 * (t0 + t1))));
	// Explosions qui touchent ce rayon (trous dans les nuages) : tri fait une fois ; la marche vers le soleil s'écarte
	// d'au plus ~10 km de l'échantillon (5 pas doublés depuis light_first_step_km).
	float light_reach_km = light_first_step_km * (pow(2.0, float(light_steps)) - 1.0);
	int nuke_mask = nuke_cloud_count > 0
			? nuke_cloud_events_near_segment(ro + rd * t0, ro + rd * t1, light_reach_km + 1.0) : 0;

	float transmittance = 1.0;
	vec3 scattered = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * (t0 + (float(i) + jitter) * dt);
		float t = t0 + (float(i) + jitter) * dt;
		float lod = log2(max(t * pixel_angle / 0.5, 1.0));
		float density = cloud_density_masked(p, TIME, true, lod, adv, nuke_mask);
		if (density <= 0.0) {
			continue;
		}
		vec3 n = normalize(p);

		// Densité optique vers le soleil, pas doublés à chaque échantillon.
		float od = 0.0;
		float tl = 0.0;
		float s = light_first_step_km;
		for (int j = 0; j < light_steps; j++) {
			od += cloud_density_masked(p + l * (tl + 0.5 * s), TIME, false, lod + 1.0, adv, nuke_mask) * s;
			tl += s;
			s *= 2.0;
		}
		float beer = exp(-cloud_extinction_per_km * od);
		float multiple = max(beer, multiple_scattering * exp(-0.25 * cloud_extinction_per_km * od));

		float h = clamp((length(p) - rb) / (rt - rb), 0.0, 1.0);
		float day = smoothstep(-0.15, 0.1, dot(n, l));
		vec3 sun = sun_transmittance_at(p, l) * sun_intensity * multiple * phase;
		vec3 ambient = sky_ambient * ambient_intensity * mix(0.45, 1.0, h) * day;
		// Flashs nucléaires (nuke/shaders/nuke_flash.gdshaderinc), diffusion isotrope.
		if (nuke_flash_count > 0) {
			ambient += nuke_flash_color * sun_intensity * nuke_flash_volume(p, lod, adv, multiple_scattering);
		}

		float sigma = cloud_extinction_per_km * density;
		float attenuation = exp(-sigma * dt);
		scattered += transmittance * (sun + ambient) * (1.0 - attenuation);
		transmittance *= attenuation;
		if (transmittance < 0.01) {
			break;
		}
	}

	ALBEDO = scattered;
	ALPHA = 1.0 - transmittance;
}
