// Fenêtre de tuiles haute résolution (5 x 5 tuiles de 5°) alimentée par scripts/earth_detail_tiles.gd et
// partagée par tous les jeux de tuiles (jour, nuit, nuages) : ils ont le même découpage et la même attribution
// des couches dans leurs Texture2DArray. Inclus par earth_surface.gdshader et cloud_density.gdshaderinc.
#ifndef DETAIL_WINDOW_INC
#define DETAIL_WINDOW_INC

uniform bool detail_ready = false;
uniform ivec2 detail_origin;
uniform int detail_layer_map[25];

const vec2 DETAIL_GRID = vec2(72.0, 36.0);
const int DETAIL_WINDOW = 5;

// Poids de la tuile HD en uv (0 hors de la fenêtre, fondu sur ses bords) et coordonnées dans le Texture2DArray.
float detail_lookup(vec2 uv, out vec3 tile_uv) {
	tile_uv = vec3(0.0);
	if (!detail_ready) {
		return 0.0;
	}
	vec2 g = uv * DETAIL_GRID;
	ivec2 cell = ivec2(floor(g));
	int dc = (cell.x - detail_origin.x + 72) % 72;
	int dr = cell.y - detail_origin.y;
	if (dc >= DETAIL_WINDOW || dr < 0 || dr >= DETAIL_WINDOW) {
		return 0.0;
	}
	tile_uv = vec3(fract(g), float(detail_layer_map[dc + DETAIL_WINDOW * dr]));
	vec2 w = vec2(float(dc), float(dr)) + fract(g);
	float edge = min(min(w.x, float(DETAIL_WINDOW) - w.x), min(w.y, float(DETAIL_WINDOW) - w.y));
	return smoothstep(0.0, 0.6, edge);
}

#endif
