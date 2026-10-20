// Visière du casque porté (scripts/suit_helmet.gd) : polycarbonate clair vu de l'intérieur, presque invisible au
// centre, teinté gris-bleu vers les bords de la fenêtre et en incidence rasante (Fresnel) : on sent le verre. Éclairée
// par la scène ; les lumières y ajoutent leurs points spéculaires (soleil, lampes, torche). Les reflets en arc sont une
// seconde passe additive (helmet_visor_glint.gdshader).
// UV : coordonnées de la fenêtre du casque (−1..1 sur les deux axes, 0 au centre, v vers le haut).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.7);
// Opacité au centre, sur les bords de la fenêtre (part du rayon où elle commence à monter) et en incidence rasante.
uniform float base_alpha : hint_range(0.0, 0.3) = 0.05;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.28;
uniform float rim_start : hint_range(0.0, 1.0) = 0.7;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;

void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float rim = smoothstep(rim_start, 1.0, length(UV));
	ALBEDO = tint;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.45;
	ALPHA = clamp(base_alpha + rim_alpha * rim + edge_alpha * fresnel, 0.0, 1.0);
}
