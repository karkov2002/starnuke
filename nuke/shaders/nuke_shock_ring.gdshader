// Traces visibles de l'onde de choc, sur un quad horizontal (PlaneMesh 2 x 2 : VERTEX.xz dans [−1, 1], demi-côté
// extent_km). Le front lui-même est invisible (air transparent après la séparation de la boule de feu) ; on voit :
// - l'anneau de condensation (nuage de Wilson) : la détente derrière le front refroidit l'air humide, qui condense
//   un bref instant. Blanc, il suit le front (montée nette côté intérieur, dégradé vers l'extérieur) ;
// - la poussière soulevée au sol (explosions basses) : jupe gris-brun autour du point zéro, qui s'étend avec le
//   front jusqu'à dust_max_km puis persiste.
//   Sur la mer (instance spray = 1), c'est de l'eau pulvérisée : jupe blanche.
// Matériau éclairé par les lumières de la scène (soleil : blanc de jour, presque invisible de nuit), sans lumière
// ambiante. Réutilisable : centre = origine du maillage ; par instance le rayon du front, sa largeur, les opacités.
// Les largeurs sont élargies à au moins un pixel (fwidth) : un anneau fin ou lointain ne scintille pas.
// Rendu avant les nuages (render_priority −1) : un banc nuageux le voile, l'atmosphère y ajoute sa brume.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled,
		specular_disabled;

instance uniform float radius_km = 0.0;
instance uniform float extent_km = 1.0;
instance uniform float front_width_km = 0.1;
instance uniform float condensation = 0.0;
instance uniform float dust = 0.0;

uniform vec3 condensation_color : source_color = vec3(0.93, 0.94, 0.96);
// Poussière mêlée de fumée : gris-brun, plus sombre que la plupart des sols.
uniform vec3 dust_color : source_color = vec3(0.24, 0.21, 0.19);
// Embruns (explosion sur la mer) : eau pulvérisée, blanche ; part donnée par instance (spray, 0 à 1).
uniform vec3 spray_color : source_color = vec3(0.88, 0.9, 0.93);
instance uniform float spray = 0.0;
// Largeur du côté intérieur du front de condensation, en part de sa largeur (dégradé) extérieure.
uniform float inner_ratio = 0.35;
// Rayon de la jupe de poussière : celui du front, plafonné à dust_max_km (instance), bord adouci sur dust_edge.
instance uniform float dust_max_km = 1.0;
uniform float dust_edge = 0.4;
// Irrégularité (part de l'opacité modulée par un bruit) et taille des irrégularités (part du rayon).
uniform float breakup = 0.5;
uniform float breakup_scale = 0.12;

varying vec2 v_xz;

void vertex() {
	v_xz = VERTEX.xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

// Profil d'un anneau de rayon center : dégradé exponentiel vers l'extérieur (w_out), gaussien vers l'intérieur
// (w_in), pic 1. Largeurs bornées à un pixel (px), pic réduit de la racine du rapport des largeurs.
float ring(float r, float center, float w_out, float w_in, float px) {
	float wo = max(w_out, px);
	float wi = max(w_in, px);
	float x = r - center;
	float v = x >= 0.0 ? exp(-x / wo) : exp(-(x * x) / (wi * wi));
	return v * sqrt((w_out + w_in) / (wo + wi));
}

void fragment() {
	vec2 xz_km = v_xz * extent_km;
	float r = length(xz_km);
	float px = fwidth(r);
	float w = front_width_km;
	float noise = value_noise(xz_km / max(radius_km * breakup_scale, 0.05));
	float irregular = mix(1.0 - breakup, 1.0, noise);

	float a_cond = clamp(ring(r, radius_km, w, w * inner_ratio, px) * condensation * irregular, 0.0, 1.0);
	float dust_radius = min(radius_km, dust_max_km);
	float skirt = 1.0 - smoothstep(dust_radius * (1.0 - dust_edge), dust_radius + px, r);
	float a_dust = clamp(skirt * dust * irregular, 0.0, 1.0);

	ALPHA = 1.0 - (1.0 - a_cond) * (1.0 - a_dust);
	ALBEDO = mix(mix(dust_color, spray_color, spray), condensation_color, a_cond / max(a_cond + a_dust, 1e-4));
	ROUGHNESS = 1.0;
}
