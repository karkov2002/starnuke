shader_type canvas_item;
// Titre de l'écran de démarrage (scripts/ui/title_glow.gd) : le texte, rendu en blanc dans un SubViewport, est teinté
// (tint, couleur d'un corps noir) et entouré d'un halo lumineux : flou gaussien de son alpha (deux couronnes de
// 16 échantillons), ajouté autour des lettres dans la même teinte.

uniform vec4 tint : source_color = vec4(1.0);
// Rayon du halo (pixels) et intensité.
uniform float glow_radius = 28.0;
uniform float glow_strength = 1.3;

void fragment() {
	float base = texture(TEXTURE, UV).a;
	float glow = 0.0;
	float total = 0.0;
	for (int ring = 1; ring <= 3; ring++) {
		float r = glow_radius * float(ring) / 3.0;
		float w = exp(-float(ring * ring) * 0.35);
		for (int i = 0; i < 16; i++) {
			float a = 6.2831853 * (float(i) + 0.5 * float(ring)) / 16.0;
			glow += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * r * TEXTURE_PIXEL_SIZE).a * w;
			total += w;
		}
	}
	glow = glow / total * glow_strength;
	float alpha = clamp(base + glow * (1.0 - base), 0.0, 1.0);
	// Lettres : teinte pleine ; halo : même teinte, plus douce.
	vec3 color = tint.rgb * (base + glow * 0.8) / max(alpha, 1e-3);
	COLOR = vec4(color, alpha * tint.a);
}
