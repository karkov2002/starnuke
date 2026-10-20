// Reflets en arc de la visière du casque porté (passe suivante de helmet_visor.gdshader, scripts/suit_helmet.gd) :
// additifs (ils n'assombrissent jamais ce qu'on voit à travers), nets sur fond sombre (espace, mer, nuit), discrets sur
// fond clair. Un arc en haut à gauche, un plus faible en bas à droite, courbés comme le bord de la fenêtre.
// UV : coordonnées de la fenêtre du casque (−1..1 sur les deux axes, 0 au centre, v vers le haut).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled;

uniform vec3 glint_color : source_color = vec3(0.85, 0.9, 1.0);
uniform float energy : hint_range(0.0, 2.0) = 0.22;
// Direction (vers le bord où se trouve l'arc principal), distance au centre de la fenêtre, largeur.
uniform vec2 streak_dir = vec2(-0.5, 1.0);
uniform float streak_offset : hint_range(0.0, 1.0) = 0.66;
uniform float streak_width : hint_range(0.01, 0.3) = 0.05;
uniform float second_share : hint_range(0.0, 1.0) = 0.45;

float arc(vec2 w, vec2 dir, float offset, float width) {
	float along = dot(w, dir);
	float across = dot(w, vec2(dir.y, -dir.x));
	// Courbé comme le bord de la fenêtre ; s'estompe vers ses extrémités.
	return exp(-pow((along + 0.6 * across * across - offset) / width, 2.0)) * smoothstep(0.5, 0.05, abs(across));
}

void fragment() {
	vec2 dir = normalize(streak_dir);
	float glint = arc(UV, dir, streak_offset, streak_width)
			+ second_share * arc(UV, -dir, streak_offset + 0.1, streak_width * 0.7);
	ALBEDO = glint_color * glint * energy;
}
