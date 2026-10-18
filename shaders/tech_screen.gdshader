shader_type spatial;
// Écrans d'ambiance du module Commande (scripts/tech_screens.gd) : dalle au matériau Ecran_XX des écrans plats et
// portables (UV 0–1 de la dalle, (0, 0) en haut à gauche de l'image), image d'un SubViewport émise telle quelle
// (pas en nits), avec un léger balayage de lignes et un reflet.

uniform sampler2D screen_texture : source_color, filter_linear;
uniform float energy = 1.0;
// Lignes de balayage (nombre sur la hauteur, profondeur).
uniform float scanlines = 260.0;
uniform float scan_depth = 0.12;

void fragment() {
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.4;
	SPECULAR = 0.2;
	float scan = 1.0 - scan_depth * (0.5 + 0.5 * sin(UV.y * scanlines * 6.2831));
	EMISSION = texture(screen_texture, UV).rgb * energy * scan;
}
