shader_type canvas_item;
// Paupières qui se ferment (séquence de mort, scripts/death_sequence.gd) : deux bords noirs et flous qui arrivent du
// haut et du bas de l'écran. Bord en arc, comme la fente d'un œil : les coins se ferment avant le centre. La vue se
// brouille en même temps (flou de l'écran, mipmaps) et s'assombrit par les bords.

uniform float closure : hint_range(0.0, 1.0) = 0.0;
// Largeur du dégradé des bords (fraction de la hauteur de l'écran).
uniform float softness = 0.09;
// Creux de l'arc au centre (fraction de la hauteur) : paupière du haut, paupière du bas (plus plate).
uniform float upper_arc = 0.16;
uniform float lower_arc = 0.09;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float shape = 1.0 - x * x;
	// Course de chaque paupière au centre : de juste au-dessus du bord (ouverte) à un peu au-delà du milieu (fermée).
	float reach = mix(-softness, 0.5 + upper_arc + softness, closure);
	float upper_edge = reach - upper_arc * shape;
	float lower_edge = mix(-softness, 0.5 + lower_arc + softness, closure) - lower_arc * shape;
	float upper = 1.0 - smoothstep(upper_edge - softness, upper_edge + softness, UV.y);
	float lower = 1.0 - smoothstep(lower_edge - softness, lower_edge + softness, 1.0 - UV.y);
	float vignette = closure * smoothstep(0.35, 1.25, length(vec2(x, UV.y * 2.0 - 1.0)));
	float dark = clamp(max(max(upper, lower), vignette), 0.0, 1.0);
	vec3 view = textureLod(screen_tex, SCREEN_UV, closure * 4.0).rgb;
	COLOR = vec4(view * (1.0 - dark), 1.0);
}
