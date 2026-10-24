// Cœur du jet du missile (scripts/missile_exhaust.gd) : cône additif le long de +Y (0 = tuyère), éblouissant à la
// sortie de la tuyère (blanc-jaune), qui s'élargit et s'éteint en quelques mètres (orange). Bords adoucis selon
// l'angle de vue (un cône de gaz lumineux est plus épais au centre de sa projection). Le jet dans le vide n'a pas de
// fumée : seul ce cœur et le panache de particules (missile_exhaust_particle.gdshader) se voient.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float length_m = 2.5;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec3 hot_color : source_color = vec3(1.0, 0.96, 0.85);
uniform vec3 cool_color : source_color = vec3(1.0, 0.55, 0.2);
// Luminance HDR au ras de la tuyère (au-dessus du seuil du glow : éblouissement).
uniform float hdr = 24.0;

varying float along;

void vertex() {
	// CylinderMesh centré : y de −longueur/2 (tuyère) à +longueur/2.
	along = clamp(VERTEX.y / length_m + 0.5, 0.0, 1.0);
}

void fragment() {
	// En MSAA, le fragment peut être évalué hors du triangle : variables extrapolées (along > 1, normale nulle). Sans
	// ces bornes, pow() d'une base négative donnait NaN, que le glow étalait en tache blanche clignotante.
	float a = clamp(along, 0.0, 1.0);
	float facing = clamp(abs(dot(NORMAL, VIEW)) / max(length(NORMAL) * length(VIEW), 1e-6), 0.0, 1.0);
	float body = pow(facing, 1.5);
	float fade = pow(1.0 - a, 2.2);
	vec3 color = mix(cool_color, hot_color, pow(1.0 - a, 3.0));
	ALBEDO = color * hdr * intensity;
	ALPHA = body * fade;
}
