shader_type spatial;
// Grand écran du poste de pilotage (Interactif_Ecran_Principal, scripts/pilot_console.gd) : affiche l'interface de
// pilotage dessinée dans un SubViewport. Les UV du modèle sont inutilisables (projection en boîte) : la position
// dans l'image vient de la position du sommet dans le rectangle de la dalle (repère du maillage), mesuré au démarrage.

uniform sampler2D screen_texture : source_color, filter_linear;
// Coin haut gauche de la dalle et ses deux côtés (vers la droite, vers le bas), dans le repère du maillage.
uniform vec3 top_left;
uniform vec3 axis_u;
uniform vec3 axis_v;
uniform float energy = 1.0;

varying vec2 screen_uv;

void vertex() {
	vec3 d = VERTEX - top_left;
	screen_uv = vec2(dot(d, axis_u) / dot(axis_u, axis_u), dot(d, axis_v) / dot(axis_v, axis_v));
}

void fragment() {
	// Dalle noire et lisse (léger reflet) ; l'image est émise. Bords biseautés : couleur du bord de l'image.
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.45;
	SPECULAR = 0.15;
	EMISSION = texture(screen_texture, clamp(screen_uv, 0.0, 1.0)).rgb * energy;
}
