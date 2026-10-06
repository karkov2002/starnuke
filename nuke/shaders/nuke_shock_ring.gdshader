// Anneau d'onde de choc, sur un quad horizontal (PlaneMesh 2 x 2 : VERTEX.xz dans [−1, 1], demi-côté extent_km).
// Réutilisable : centre = origine du maillage, et par instance le rayon du front, sa largeur et l'intensité.
// - Front émissif : montée nette côté intérieur, dégradé exponentiel vers l'extérieur.
// - Second anneau plus diffus, légèrement derrière (vers le centre).
// Les largeurs sont élargies à au moins un pixel : un anneau fin ou lointain ne scintille pas.
// Additif, rendu avant les nuages (render_priority −1) : un banc nuageux le voile, l'atmosphère y ajoute sa brume.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float radius_km = 0.0;
instance uniform float extent_km = 1.0;
instance uniform float front_width_km = 0.1;
instance uniform float intensity = 0.0;

uniform vec3 front_color : source_color = vec3(1.0, 0.5, 0.12);
uniform vec3 trail_color : source_color = vec3(1.0, 0.32, 0.08);
// Largeur du côté intérieur du front, en part de sa largeur (dégradé) extérieure.
uniform float inner_ratio = 0.35;
// Second anneau : retard (part du rayon), largeur (× celle du front), intensité relative.
uniform float trail_lag = 0.12;
uniform float trail_width = 4.0;
uniform float trail_intensity = 0.3;

varying vec2 v_xz;

void vertex() {
	v_xz = VERTEX.xz;
}

// Profil d'un anneau de rayon center : dégradé exponentiel vers l'extérieur (w_out), gaussien vers l'intérieur
// (w_in). Largeurs bornées à un pixel (px) ; le pic n'est réduit que de la racine du rapport des largeurs (à énergie
// strictement constante, un front plus fin qu'un pixel deviendrait trop pâle pour être vu).
float ring(float r, float center, float w_out, float w_in, float px) {
	float wo = max(w_out, px);
	float wi = max(w_in, px);
	float x = r - center;
	float v = x >= 0.0 ? exp(-x / wo) : exp(-(x * x) / (wi * wi));
	return v * sqrt((w_out + w_in) / (wo + wi));
}

void fragment() {
	float r = length(v_xz) * extent_km;
	float px = fwidth(r);
	float w = front_width_km;
	float front = ring(r, radius_km, w, w * inner_ratio, px);
	float trail = ring(r, radius_km * (1.0 - trail_lag), w * trail_width, w * trail_width, px);
	ALBEDO = (front_color * front + trail_color * trail * trail_intensity) * intensity;
}
