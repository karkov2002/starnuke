// Explosions vues par le sol, sans plafond de nombre : textures de données alimentées par nuke/nuke_ground_fx.gd
// (NukeGroundFX), lues par nuke_fire.gdshaderinc (incendies, sol calciné) et nuke_blackout.gdshaderinc (black-out).
// Sans explosion (nuke_ground_count = 0), rien n'est lu.
//
// - nuke_ground_events : une colonne par explosion ; ligne 0 = (centre en km dans le repère de la planète, temps
//   physique écoulé en s), ligne 1 = (rayon détruit, rayon de la panne régionale, rayon initial des incendies (0 : rien
//   ne brûle), portée totale), en km ;
// - nuke_ground_cells : maille de 1° (longitude × latitude, ligne 0 au nord), (début, nombre) de la liste des
//   explosions dont la portée touche la maille, rangée dans nuke_ground_index (NUKE_GROUND_INDEX_WIDTH de large).
#ifndef NUKE_GROUND_INC
#define NUKE_GROUND_INC

const int NUKE_GROUND_INDEX_WIDTH = 4096;
const int NUKE_GROUND_CELLS_X = 360;
const int NUKE_GROUND_CELLS_Y = 180;

uniform int nuke_ground_count = 0;
uniform sampler2D nuke_ground_events : filter_nearest, repeat_disable;
uniform sampler2D nuke_ground_cells : filter_nearest, repeat_disable;
uniform sampler2D nuke_ground_index : filter_nearest, repeat_disable;

struct NukeGroundEvent {
	vec3 pos_km;
	float time_s;
	float destroyed_km;
	float region_km;
	float fire_km;
	float reach_km;
};

// Explosions proches du point de normale n (repère du maillage : +Y nord, longitude atan2(−x, −z)) : (début, nombre)
// dans nuke_ground_index ; (0, 0) sans explosion.
ivec2 nuke_ground_cell(vec3 n) {
	if (nuke_ground_count <= 0) {
		return ivec2(0);
	}
	float lat = degrees(asin(clamp(n.y, -1.0, 1.0)));
	float lon = degrees(atan(-n.x, -n.z));
	ivec2 c = ivec2(clamp(int(floor(lon + 180.0)), 0, NUKE_GROUND_CELLS_X - 1),
			clamp(int(floor(90.0 - lat)), 0, NUKE_GROUND_CELLS_Y - 1));
	vec2 list = texelFetch(nuke_ground_cells, c, 0).rg;
	return ivec2(int(list.x + 0.5), int(list.y + 0.5));
}

// k-ième explosion de la liste (k dans [début, début + nombre[).
NukeGroundEvent nuke_ground_event(int k) {
	int id = int(texelFetch(nuke_ground_index, ivec2(k % NUKE_GROUND_INDEX_WIDTH, k / NUKE_GROUND_INDEX_WIDTH), 0).r + 0.5);
	vec4 a = texelFetch(nuke_ground_events, ivec2(id, 0), 0);
	vec4 b = texelFetch(nuke_ground_events, ivec2(id, 1), 0);
	return NukeGroundEvent(a.xyz, a.w, b.x, b.y, b.z, b.w);
}

#endif
