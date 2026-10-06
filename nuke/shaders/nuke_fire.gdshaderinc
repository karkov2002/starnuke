// Incendies allumés par le flash des explosions nucléaires, en émission dans le sol (earth_surface.gdshader).
// À inclure après cloud_density.gdshaderinc (bruits 3D). Les uniforms sont alimentés à chaque image par
// nuke/nuke_fire_fx.gd ; sans incendie (nuke_fire_count = 0), rien n'est calculé.
//
// Dans le disque de rayon nuke_fire_radius_km (exposition thermique suffisante pour enflammer les matériaux), la part
// du sol en feu : forte près du centre (l'exposition décroît en 1/d²), seulement sur les terres, plus forte et plus
// vive dans les villes (combustible). Depuis l'orbite (~0,5 km par pixel), on ne distingue pas les flammes : on voit
// leur lueur moyenne, modulée par un motif irrégulier de 2 à 12 km (zones qui brûlent plus ou moins), qui scintille.
// Positions en km dans le repère de la planète. La luminance des flammes est faible devant un sol éclairé par le
// soleil : les feux se voient surtout de nuit.
#ifndef NUKE_FIRE_INC
#define NUKE_FIRE_INC

const int NUKE_MAX_FIRES = 8;

uniform int nuke_fire_count = 0;
uniform vec3 nuke_fire_pos_km[8];
uniform float nuke_fire_radius_km[8];
uniform float nuke_fire_intensity[8];
uniform vec3 nuke_fire_color : source_color = vec3(1.0, 0.45, 0.12);
// Luminance HDR d'un sol entièrement en feu, à intensité 1 (l'incendie culmine vers 0,7).
uniform float nuke_fire_hdr = 1.6;
// Périodes de la texture de bruit pour le motif des zones en feu (km ; une période contient ~4 taches) ; la grande
// vaut 1,2 fois le rayon de la zone, plafonnée à nuke_fire_coarse_km.
uniform float nuke_fire_fine_km = 8.0;
uniform float nuke_fire_coarse_km = 60.0;

// Émission des incendies au point p (km), sur un sol de part de terre land (0 = eau) et d'urbanisation urban (0 à 1).
vec3 nuke_fire_emission(vec3 p, float land, float urban) {
	float total = 0.0;
	for (int i = 0; i < NUKE_MAX_FIRES; i++) {
		if (i >= nuke_fire_count) {
			break;
		}
		float radius = nuke_fire_radius_km[i];
		float d = length(p - nuke_fire_pos_km[i]);
		if (d > radius * 1.8 || nuke_fire_intensity[i] <= 0.0) {
			continue;
		}
		// Motif irrégulier (zones qui brûlent plus ou moins) à deux échelles : la grande suit la taille de la zone en
		// feu. Le bruit fractal varie peu autour de 0,5 : on le normalise
		// (c dans [−1, 1]) pour obtenir des zones nettement contrastées.
		float coarse_km = min(nuke_fire_coarse_km, radius * 1.2);
		float c = clamp((textureLod(cloud_shape_noise, p / coarse_km, 0.0).r - 0.5) * 4.0, -1.0, 1.0);
		float f = clamp((textureLod(cloud_shape_noise, p / nuke_fire_fine_km + vec3(0.31, 0.73, 0.17), 0.0).r - 0.5) * 4.0, -1.0, 1.0);
		float pattern = smoothstep(-0.2, 0.5, c * 0.65 + f * 0.35);
		// Part du sol en feu : forte au centre, décroissante vers le bord, bord adouci et très irrégulier.
		float edge = d / radius + 0.35 * c;
		float burning = mix(0.8, 0.1, min(d / radius, 1.0)) * (1.0 - smoothstep(0.7, 1.0, edge));
		burning *= land * mix(0.6, 1.3, urban);
		// Scintillement des flammes.
		float flicker = 0.85 + 0.15 * sin(TIME * 6.3 + f * 10.0) * sin(TIME * 2.9 + c * 6.0);
		total += burning * mix(0.05, 1.0, pattern) * flicker * nuke_fire_intensity[i] * mix(1.0, 1.6, urban);
	}
	return nuke_fire_color * nuke_fire_hdr * total;
}

#endif
