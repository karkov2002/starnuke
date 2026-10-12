// Explosions vues par le sol, sans plafond de nombre : textures de données alimentées par nuke/nuke_ground_fx.gd
// (NukeGroundFX), lues par nuke_fire.gdshaderinc (incendies, sol calciné) et nuke_blackout.gdshaderinc (black-out).
// Sans explosion (nuke_ground_count = 0), rien n'est lu.
//
// - nuke_ground_events : une colonne par explosion ; ligne 0 = (centre en km dans le repère de la planète, temps
//   physique écoulé en s), ligne 1 = (rayon détruit, rayon de la panne régionale, rayon initial des incendies (0 : rien
//   ne brûle), portée totale) en km, ligne 2 = (direction où va le vent de la fumée, vitesse en m/s), ligne 3 = (rayon
//   des gravats en km, inutilisés) ;
// - nuke_ground_cells : maille de 1° (longitude × latitude, ligne 0 au nord), (début, nombre) de la liste des
//   explosions dont la portée touche la maille, rangée dans nuke_ground_index (NUKE_GROUND_INDEX_WIDTH de large) ;
//   nuke_smoke_cells et nuke_smoke_index : idem pour les panaches de fumée (nuke_smoke.gdshaderinc).
#ifndef NUKE_GROUND_INC
#define NUKE_GROUND_INC

const int NUKE_GROUND_INDEX_WIDTH = 4096;
const int NUKE_GROUND_CELLS_X = 360;
const int NUKE_GROUND_CELLS_Y = 180;

uniform int nuke_ground_count = 0;
uniform sampler2D nuke_ground_events : filter_nearest, repeat_disable;
uniform sampler2D nuke_ground_cells : filter_nearest, repeat_disable;
uniform sampler2D nuke_ground_index : filter_nearest, repeat_disable;
// Carte des pays (assets/textures/country_ids.png, tools/build_country_mask.gd) : indice du pays + 1 sur 16 bits
// (R = octet faible, G = octet fort ; 0 = mer ou océan), ~2,4 km par pixel, équirectangulaire. Sert au black-out
// national et de masque des terres pour les incendies (le masque d'eau déduit de la couleur du sol ne reconnaît pas les
// mers, trop sombres).
uniform sampler2D nuke_country_ids : filter_nearest, repeat_disable;

// Position du point de normale n dans nuke_country_ids, en pixels (repère du maillage : +Y nord, +Z vers −180° ;
// latitude asin(y), longitude atan2(−x, −z)).
vec2 nuke_country_pixel(vec3 n, vec2 size) {
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(-n.x, -n.z);
	return vec2((lon + PI) / TAU, 0.5 - lat / PI) * size;
}

int nuke_country_id(vec3 n) {
	vec2 size = vec2(textureSize(nuke_country_ids, 0));
	ivec2 texel = ivec2(clamp(nuke_country_pixel(n, size), vec2(0.0), size - 1.0));
	vec2 rg = texelFetch(nuke_country_ids, texel, 0).rg;
	return int(rg.r * 255.0 + 0.5) + 256 * int(rg.g * 255.0 + 0.5);
}

// Part de terre (0 = mer ou océan, 1 = terre) au point de normale n : pixels de nuke_country_ids interpolés (côte
// adoucie sur ~2 km, pas d'escalier).
float nuke_land_share(vec3 n) {
	ivec2 size = textureSize(nuke_country_ids, 0);
	vec2 f = nuke_country_pixel(n, vec2(size)) - 0.5;
	ivec2 i0 = ivec2(floor(f));
	vec2 w = f - vec2(i0);
	float land[4];
	for (int k = 0; k < 4; k++) {
		// Longitude : bouclée ; latitude : bornée.
		ivec2 texel = ivec2((i0.x + (k & 1) + size.x) % size.x, clamp(i0.y + (k >> 1), 0, size.y - 1));
		land[k] = dot(texelFetch(nuke_country_ids, texel, 0).rg, vec2(1.0)) > 0.0 ? 1.0 : 0.0;
	}
	return mix(mix(land[0], land[1], w.x), mix(land[2], land[3], w.x), w.y);
}

struct NukeGroundEvent {
	int id;
	vec3 pos_km;
	float time_s;
	float destroyed_km;
	float region_km;
	float fire_km;
	float reach_km;
};

// Maille de 1° du point de normale n (repère du maillage : +Y nord, longitude atan2(−x, −z)).
ivec2 nuke_ground_texel(vec3 n) {
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	float lon = degrees(atan(-n.x, -n.z));
	return ivec2(clamp(int(floor(lon + 180.0)), 0, NUKE_GROUND_CELLS_X - 1),
			clamp(int(floor(90.0 - lat)), 0, NUKE_GROUND_CELLS_Y - 1));
}

// Explosions proches du point de normale n : (début, nombre) dans nuke_ground_index ; (0, 0) sans explosion.
ivec2 nuke_ground_cell(vec3 n) {
	if (nuke_ground_count <= 0) {
		return ivec2(0);
	}
	vec2 list = texelFetch(nuke_ground_cells, nuke_ground_texel(n), 0).rg;
	return ivec2(int(list.x + 0.5), int(list.y + 0.5));
}

// Explosion d'indice id (colonne de nuke_ground_events), lignes 0 et 1.
NukeGroundEvent nuke_ground_event_at(int id) {
	vec4 a = texelFetch(nuke_ground_events, ivec2(id, 0), 0);
	vec4 b = texelFetch(nuke_ground_events, ivec2(id, 1), 0);
	return NukeGroundEvent(id, a.xyz, a.w, b.x, b.y, b.z, b.w);
}

// k-ième explosion de la liste de nuke_ground_index (k dans [début, début + nombre[).
NukeGroundEvent nuke_ground_event(int k) {
	ivec2 texel = ivec2(k % NUKE_GROUND_INDEX_WIDTH, k / NUKE_GROUND_INDEX_WIDTH);
	return nuke_ground_event_at(int(texelFetch(nuke_ground_index, texel, 0).r + 0.5));
}

// Ligne r (2 : vent de la fumée, 3 : rayon des gravats) de l'explosion id.
vec4 nuke_ground_row(int id, int r) {
	return texelFetch(nuke_ground_events, ivec2(id, r), 0);
}

#endif
