// Atmosphère terrestre par diffusion simple (Rayleigh + Mie + absorption de l'ozone), calculée par
// lancer de rayon dans la coquille atmosphérique. Le même shader sert à deux maillages (deux matériaux) :
// - « ciel » (ground_rays = false) : grande sphère dont on ne rend que les faces arrière ; elle couvre tous les
//   rayons qui manquent la Terre, que la caméra soit dans la coquille (orbite basse) ou au-dessus ;
// - « sol » (ground_rays = true) : sphère juste au-dessus des nuages, faces avant ; elle couvre les rayons qui
//   touchent la Terre (sur ces pixels, les faces arrière de la sphère « ciel » sont masquées par le sol).
// Le test de profondeur normal laisse la station masquer l'atmosphère.
// - au-dessus de l'espace : halo du limbe, dégradé blanc-bleu -> bleu profond -> noir ;
// - au-dessus du sol : voile bleuté (perspective aérienne) et atténuation de la lumière du sol.
// Mélange prémultiplié : couleur = diffusion + fond * (1 - opacité).
// Les calculs se font en kilomètres (units_to_km convertit l'échelle de la scène).
shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// false : sphère « ciel » (faces arrière, rayons qui manquent la Terre) ; true : sphère « sol » (faces avant,
// rayons qui touchent la Terre).
uniform bool ground_rays = false;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // espace monde, vers le soleil
uniform float sun_intensity = 9.0;
uniform float units_to_km = 10.0;
uniform float mie_g : hint_range(0.0, 0.99) = 0.8;
uniform int primary_steps = 32;
uniform int light_steps = 8;

#include "res://shaders/atmosphere_common.gdshaderinc"

// Profondeur optique de p vers le soleil ; x < 0 si le point est dans l'ombre de la planète.
vec3 light_depth(vec3 p, vec3 l) {
	vec2 hit = ray_sphere(p, l, planet_radius_km);
	if (hit.x > 0.0 && hit.x < 1e8) {
		return vec3(-1.0);
	}
	float t_exit = ray_sphere(p, l, atmosphere_radius()).y;
	vec3 od = vec3(0.0);
	for (int i = 0; i < light_steps; i++) {
		// Pas quadratiques : plus denses près du point (là où l'air est le plus dense).
		float u0 = float(i) / float(light_steps);
		float u1 = float(i + 1) / float(light_steps);
		float ta = t_exit * u0 * u0;
		float tb = t_exit * u1 * u1;
		vec3 q = p + l * (0.5 * (ta + tb));
		od += densities(length(q) - planet_radius_km) * (tb - ta);
	}
	return od;
}

void fragment() {
	if (FRONT_FACING != ground_rays) {
		discard;
	}
	vec3 cam_w = INV_VIEW_MATRIX[3].xyz;
	vec3 frag_w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 ro = (cam_w - center) * units_to_km;
	vec3 rd = normalize(frag_w - cam_w);
	vec3 l = normalize(sun_direction);

	vec2 atmo = ray_sphere(ro, rd, atmosphere_radius());
	vec2 ground = ray_sphere(ro, rd, planet_radius_km);
	float t0 = max(atmo.x, 0.0);
	float t1 = atmo.y;
	bool hits_ground = ground.x > 0.0 && ground.x < 1e8;
	if (hits_ground != ground_rays) {
		discard;
	}
	if (hits_ground) {
		t1 = min(t1, ground.x);
	}
	if (t1 <= t0) {
		discard;
	}

	// Les échantillons sont resserrés autour du point le plus bas du rayon (tc), où la densité
	// varie le plus vite : cela évite les bandes au niveau du limbe.
	float tc = clamp(-dot(ro, rd), t0, t1);
	int half_steps = max(primary_steps / 2, 1);
	vec3 od_view = vec3(0.0);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
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
			float ds = tb - ta;
			vec3 p = ro + rd * (0.5 * (ta + tb));
			vec3 d = densities(length(p) - planet_radius_km);
			vec3 od_mid = od_view + d * ds * 0.5;
			od_view += d * ds;
			vec3 od_light = light_depth(p, l);
			if (od_light.x < 0.0) {
				continue;
			}
			vec3 t = exp(-extinction(od_mid + od_light));
			sum_r += d.x * ds * t;
			sum_m += d.y * ds * t;
		}
	}

	float mu = dot(rd, l);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g2 = mie_g * mie_g;
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu))
			/ ((2.0 + g2) * pow(1.0 + g2 - 2.0 * mie_g * mu, 1.5));

	vec3 inscatter = sun_intensity / height_scale * (sum_r * rayleigh_beta * phase_r + sum_m * mie_beta * phase_m);
	vec3 transmittance = exp(-extinction(od_view));
	ALBEDO = inscatter;
	ALPHA = clamp(1.0 - dot(transmittance, vec3(1.0 / 3.0)), 0.0, 1.0);
}
