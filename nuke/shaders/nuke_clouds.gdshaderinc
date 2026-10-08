// Interaction des explosions nucléaires avec la couche nuageuse : inclus par shaders/cloud_density.gdshaderinc, donc
// appliqué partout où la densité des nuages est lue (rendu volumétrique, ombres portées au sol, voilage des lumières
// nocturnes, lumière des flashs). Les uniforms sont alimentés à chaque image par nuke/nuke_cloud_fx.gd ; sans
// événement (nuke_cloud_count = 0), rien n'est calculé.
//
// Pour chaque explosion, autour du centre c (km, repère de la planète), à la distance r :
// - trou : à l'intérieur du rayon courant R du front de choc (NukeScaling.shock_front_radius_km, le même que l'anneau
//   de condensation au sol : le front pousse les nuages devant lui), la densité est supprimée ; bord flou et
//   légèrement irrégulier (nuke_cloud_edge_*) ;
// - nuages poussés : la carte est lue plus près du centre (déplacement radial vers l'extérieur), avec un décalage A
//   maximal au front qui décroît en exp(−(r − R) / w) au-delà : la matière balayée est tassée contre le front ;
// - bourrelet : densité (et sommet) renforcés sur le front, même décroissance ;
// - retour des nuages : un point est rouvert depuis le passage du front, t_passage = −τ · ln(1 − r / R_max) ; le trou
//   s'y referme sur nuke_cloud_recovery_s (temps physique de l'explosion), plus vite au bord (nuke_cloud_edge_fill) :
//   les nuages regagnent le trou du bord vers le centre. Décalage et bourrelet s'estompent sur la même durée.
#ifndef NUKE_CLOUDS_INC
#define NUKE_CLOUDS_INC

const int NUKE_MAX_CLOUD_EVENTS = 16;
const float NUKE_CLOUD_PLANET_RADIUS_KM = 6371.0;

uniform int nuke_cloud_count = 0;
// Événement i, deux vec4 (soit deux texels RGBA32F d'une future texture de données, cf. nuke_cloud_event) :
// a = (centre x, y, z en km dans le repère de la planète, rayon courant du trou en km),
// b = (rayon final du trou R_max en km, constante de temps τ de son ouverture en s, temps physique écoulé en s,
// puissance en kt).
uniform vec4 nuke_cloud_a[16];
uniform vec4 nuke_cloud_b[16];
// Durée de retour des nuages (s, temps physique de l'explosion), fournie par NukeCloudFX.
uniform float nuke_cloud_recovery_s = 1200.0;
// Le bord du trou se referme (1 + edge_fill) fois plus vite que le centre.
uniform float nuke_cloud_edge_fill = 1.0;
// Bord flou du trou : largeur en part du rayon, au moins nuke_cloud_edge_km ; irrégularité (part de la largeur,
// bruit de cloud_shape_noise dont la période suit le rayon).
uniform float nuke_cloud_edge_soft = 0.18;
uniform float nuke_cloud_edge_km = 0.6;
uniform float nuke_cloud_edge_noise = 0.6;
// Décalage radial maximal (part du rayon du front) et largeur de la zone tassée au-delà du front (part du rayon).
uniform float nuke_cloud_push = 0.12;
uniform float nuke_cloud_rim_width = 0.08;
// Renfort de densité du bourrelet sur le front (0 = aucun), et part reportée sur la hauteur du sommet.
uniform float nuke_cloud_rim_gain = 0.6;
uniform float nuke_cloud_rim_lift = 0.25;

struct NukeCloudEvent {
	vec3 center_km;
	float radius_km;
	float max_radius_km;
	float tau_s;
	float time_s;
	float yield_kt;
};

// Seul accès aux données d'un événement : pour passer à une texture RGBA32F (2 texels par événement), remplacer les
// deux lectures de tableau par texelFetch(texture, ivec2(0, i), 0) et texelFetch(texture, ivec2(1, i), 0).
NukeCloudEvent nuke_cloud_event(int i) {
	vec4 a = nuke_cloud_a[i];
	vec4 b = nuke_cloud_b[i];
	NukeCloudEvent e;
	e.center_km = a.xyz;
	e.radius_km = a.w;
	e.max_radius_km = b.x;
	e.tau_s = b.y;
	e.time_s = b.z;
	e.yield_kt = b.w;
	return e;
}

// Déformation de la couche nuageuse au point n (sphère unité, repère de la planète). read_n : position où lire la
// carte de couverture (déplacée vers les centres). rim : renfort du bourrelet (≥ 0). Retour : part de densité
// conservée (0 dans un trou ouvert).
float nuke_cloud_warp(vec3 n, out vec3 read_n, out float rim) {
	read_n = n;
	rim = 0.0;
	float keep = 1.0;
	vec3 p = n * NUKE_CLOUD_PLANET_RADIUS_KM;
	for (int i = 0; i < NUKE_MAX_CLOUD_EVENTS; i++) {
		if (i >= nuke_cloud_count) {
			break;
		}
		NukeCloudEvent e = nuke_cloud_event(i);
		float radius = e.radius_km;
		if (radius <= 0.0) {
			continue;
		}
		float w = max(nuke_cloud_rim_width * radius, nuke_cloud_edge_km);
		vec3 v = p - e.center_km;
		float r = length(v);
		if (r > radius + 6.0 * w + nuke_cloud_edge_km) {
			continue;
		}
		// Estompage global (décalage, bourrelet) et retour local des nuages depuis le passage du front.
		float fade = 1.0 - smoothstep(0.0, 1.0, e.time_s / nuke_cloud_recovery_s);
		float since = r < e.max_radius_km ? e.time_s + e.tau_s * log(1.0 - r / e.max_radius_km) : 0.0;
		float heal = smoothstep(0.0, 1.0, max(since, 0.0) / nuke_cloud_recovery_s
				* (1.0 + nuke_cloud_edge_fill * r / radius));
		// Bord flou et irrégulier, centré sur le rayon du trou.
		float edge = max(nuke_cloud_edge_soft * radius, nuke_cloud_edge_km);
		float wobble = clamp((textureLod(cloud_shape_noise, p / max(radius * 0.3, 1.0), 0.0).r - 0.5) * 4.0, -1.0, 1.0);
		float r_edge = r + nuke_cloud_edge_noise * edge * wobble;
		float inside = 1.0 - smoothstep(radius - 0.7 * edge, radius + 0.3 * edge, r_edge);
		keep *= 1.0 - inside * (1.0 - heal);

		// Nuages poussés : le contenu affiché en r vient de r_read < r (continu au front).
		float push = nuke_cloud_push * radius * fade;
		float x = r - radius;
		float r_read = x >= 0.0 ? r - push * exp(-x / w) : r * (radius - push) / radius;
		if (r > 1e-4) {
			vec3 c = normalize(e.center_km);
			vec3 m = read_n - c;
			read_n = normalize(c + m * (r_read / r));
		}
		rim += nuke_cloud_rim_gain * fade * exp(-max(x, 0.0) / w) * (1.0 - inside);
	}
	return keep;
}

#endif
