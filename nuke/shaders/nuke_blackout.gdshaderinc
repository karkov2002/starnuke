// Black-out électrique des explosions nucléaires, appliqué aux lumières des villes dans le sol
// (earth_surface.gdshader). À inclure après cloud_density.gdshaderinc (bruit 3D). Les uniforms sont alimentés à chaque
// image par nuke/nuke_blackout.gd ; sans panne (comptes nuls), rien n'est calculé. Lois et durées : NukeScaling
// (BLACKOUT_*).
//
// nuke_blackout_darkness() rend la part des lumières éteintes (0 à 1) au point p (km, repère de la planète) :
// - zone détruite (rayon nuke_blackout_b.x) : éteinte pour de bon, bord irrégulier ;
// - panne régionale (rayon nuke_blackout_b.y) : le front de la cascade avance du centre vers le bord, par plaques
//   (bruit à grosse maille), puis les plaques se rallument une à une, du bord (restore_s.x) vers le centre
//   (restore_s.y) ;
// - panne nationale : tout le pays (carte nuke_country_ids, indice + 1 sur 16 bits) s'éteint par plaques en
//   national_off_s, puis se rallume par plaques entre national_restore_s.x et .y.
// Chaque plaque bascule sur une fenêtre de temps (pas de saut d'une image à l'autre).
#ifndef NUKE_BLACKOUT_INC
#define NUKE_BLACKOUT_INC

const int NUKE_MAX_BLACKOUTS = 16;
const int NUKE_MAX_BLACKOUT_COUNTRIES = 8;

uniform int nuke_blackout_count = 0;
// Événement i : a = (centre x, y, z en km dans le repère de la planète, temps physique écoulé en s),
// b = (rayon détruit en km, rayon de la panne régionale en km, inutilisés).
uniform vec4 nuke_blackout_a[16];
uniform vec4 nuke_blackout_b[16];
uniform int nuke_blackout_country_count = 0;
// Pays plongés dans le noir : indice + 1 dans la carte des pays, et temps physique écoulé (s).
uniform int nuke_blackout_country[8];
uniform float nuke_blackout_country_time[8];
uniform sampler2D nuke_country_ids : filter_nearest, repeat_disable;
// Durées (s, temps physique), fournies par NukeBlackout depuis NukeScaling.
uniform float nuke_blackout_cascade_tau_s = 15.0;
uniform vec2 nuke_blackout_restore_s = vec2(3600.0, 86400.0);
uniform float nuke_blackout_national_off_s = 30.0;
uniform vec2 nuke_blackout_national_restore_s = vec2(7200.0, 43200.0);
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

// Plaque éteinte entre t_off et t_on (s) : 1 = éteinte ; bascules adoucies sur 5 % de la date (au moins 2 s).
float nuke_blackout_window(float t, float t_off, float t_on) {
	float off = smoothstep(t_off, t_off + max(0.05 * t_off, 2.0), t);
	float on = smoothstep(t_on, t_on + max(0.05 * t_on, 2.0), t);
	return off * (1.0 - on);
}

int nuke_country_id(vec3 n) {
	vec2 size = vec2(textureSize(nuke_country_ids, 0));
	// Repère du maillage (+Y nord, +Z vers −180°) : latitude asin(y), longitude atan2(−x, −z).
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(-n.x, -n.z);
	ivec2 texel = ivec2(clamp(vec2((lon + PI) / TAU, 0.5 - lat / PI) * size, vec2(0.0), size - 1.0));
	vec2 rg = texelFetch(nuke_country_ids, texel, 0).rg;
	return int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
}

float nuke_blackout_darkness(vec3 p, vec3 n) {
	float dark = 0.0;
	for (int i = 0; i < NUKE_MAX_BLACKOUTS; i++) {
		if (i >= nuke_blackout_count) {
			break;
		}
		vec3 v = p - nuke_blackout_a[i].xyz;
		float t = nuke_blackout_a[i].w;
		float destroyed = nuke_blackout_b[i].x;
		float region = nuke_blackout_b[i].y;
		float d = length(v);
		if (d > region * 1.2) {
			continue;
		}
		// Zone détruite : bord irrégulier, à l'échelle de son rayon (motif fixe, centré sur l'explosion).
		float wobble = nuke_blackout_patch(v / max(destroyed * 0.4, 0.5)) - 0.5;
		float r_destroyed = destroyed * (1.0 + 2.0 * nuke_blackout_edge_noise * wobble);
		dark = max(dark, 1.0 - smoothstep(r_destroyed * 0.95, r_destroyed * 1.05, d));
		// Panne régionale : chaque plaque a sa distance « vue par la cascade » et sa date de retour.
		float patch_a = nuke_blackout_patch(v / nuke_blackout_patch_km);
		float patch_b = nuke_blackout_patch(v / nuke_blackout_patch_km + vec3(3.7, 1.3, 5.1));
		float d_patch = d * mix(0.8, 1.2, patch_a);
		if (d_patch > region) {
			continue;
		}
		// Date de passage du front (inverse de R · (1 − exp(−t / τ))), puis date de retour : du bord vers le centre.
		float t_off = -nuke_blackout_cascade_tau_s * log(max(1.0 - d_patch / region, 1e-3));
		float u = clamp((d_patch - destroyed) / max(region - destroyed, 1e-3), 0.0, 1.0);
		float t_on = mix(nuke_blackout_restore_s.y, nuke_blackout_restore_s.x, u) * mix(0.7, 1.3, patch_b);
		dark = max(dark, nuke_blackout_window(t, t_off, t_on));
	}
	if (nuke_blackout_country_count > 0) {
		int id = nuke_country_id(n);
		for (int i = 0; i < NUKE_MAX_BLACKOUT_COUNTRIES; i++) {
			if (i >= nuke_blackout_country_count) {
				break;
			}
			if (id != nuke_blackout_country[i]) {
				continue;
			}
			float patch_a = nuke_blackout_patch(p / (2.0 * nuke_blackout_patch_km) + vec3(7.1, 2.9, 0.4));
			float patch_b = nuke_blackout_patch(p / (2.0 * nuke_blackout_patch_km) + vec3(1.9, 6.3, 4.7));
			float t_off = mix(0.15, 1.0, patch_a) * nuke_blackout_national_off_s;
			float t_on = mix(nuke_blackout_national_restore_s.x, nuke_blackout_national_restore_s.y, patch_b);
			dark = max(dark, nuke_blackout_window(nuke_blackout_country_time[i], t_off, t_on));
		}
	}
	return dark;
}

#endif
