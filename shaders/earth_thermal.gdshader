// Surface terrestre vue en infrarouge thermique (caméra nadir de la tablette, mode IR : scripts/orbit/thermal_surface.gd
// porte ce matériau, copie de celui de la surface, sur un calque vu seulement par cette caméra). Niveaux de gris
// « blanc = chaud » (style militaire). Modèle de température affichée (0 froid … 1 très chaud), simple et lisible :
// - mers et océans : tièdes, presque sans cycle jour / nuit (inertie thermique de l'eau) : la nuit, plus clairs que
//   les terres, d'où des côtes bien lisibles ;
// - terres : fraîches la nuit, chauffées par le soleil le jour (plus les sols sombres, qui absorbent davantage) ; un
//   peu du relief de la texture de jour est gardé pour se repérer ;
// - villes : îlots de chaleur, d'après les lumières de la carte de nuit (Black Marble), atténués par le black-out ;
// - plus froid vers les pôles (cosinus de la latitude) ;
// - nuages : sommets froids, sombres (transmittance verticale de la couche nuageuse) ; fumée des incendies : tiède ;
// - incendies et flashs des explosions : blanc saturé.
// Grain du capteur (bruit par pixel, renouvelé à chaque image). La caméra rend en résolution réduite (NadirCamera).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, ambient_light_disabled, fog_disabled;

#include "res://shaders/cloud_density.gdshaderinc"
#include "res://shaders/sun_light.gdshaderinc"
#include "res://nuke/shaders/nuke_flash.gdshaderinc"
#include "res://nuke/shaders/nuke_fire.gdshaderinc"
#include "res://nuke/shaders/nuke_blackout.gdshaderinc"
#include "res://nuke/shaders/nuke_smoke.gdshaderinc"

uniform sampler2D day_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray night_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool night_detail_ready = false;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // espace monde, vers le soleil
uniform float units_to_km = 10.0;
uniform int cloud_shadow_samples = 4;

// Températures affichées (0 à 1).
uniform float ir_land_night = 0.3;
uniform float ir_land_sun = 0.42; // échauffement en plein soleil (sol nu sombre)
uniform float ir_vegetation = 0.2; // fraîcheur de la végétation au soleil (évapotranspiration)
uniform float ir_water = 0.55;
uniform float ir_polar_cooling = 0.12; // retranché aux pôles
uniform float ir_relief = 1.6; // contraste local (luminance moins sa moyenne floue) : vallées, rivières, reliefs
uniform float ir_relief_night = 0.8; // part du contraste local gardée la nuit
uniform float ir_contrast = 1.35; // étirement autour de ir_pivot
uniform float ir_pivot = 0.4;
uniform float ir_city = 0.24;
uniform float ir_cloud_top = 0.05;
uniform float ir_smoke = 0.3;
uniform float ir_fire = 1.2;
uniform float ir_grain = 0.035;
// Gain final (étalonnage de l'exposition de la caméra nadir en mode IR).
uniform float ir_gain = 1.0;

varying vec3 local_km;

void vertex() {
	local_km = VERTEX * units_to_km;
}

// Transmittance de la couche nuageuse le long d'un rayon partant du sol (même calcul que earth_surface.gdshader).
float cloud_transmittance(vec3 n, vec3 l, CloudAdvection adv) {
	float mu = dot(n, l);
	if (mu <= 0.02) {
		return 1.0;
	}
	vec3 ground = n * CLOUD_PLANET_RADIUS_KM;
	float thickness = cloud_top_km - cloud_bottom_km;
	float od = 0.0;
	for (int i = 0; i < cloud_shadow_samples; i++) {
		float h = cloud_bottom_km + (float(i) + 0.5) / float(cloud_shadow_samples) * thickness;
		od += cloud_density(ground + l * (h / mu), TIME, true, 0.0, adv);
	}
	od *= thickness / float(cloud_shadow_samples) / mu;
	return exp(-cloud_extinction_per_km * od);
}

float ir_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 albedo = texture(day_texture, UV).rgb;
	vec3 night = texture(night_texture, UV).rgb;
	// Moyenne floue (mip plus grossier) pour le contraste local.
	vec3 blurred = textureLod(day_texture, UV, 4.0).rgb;
	// Chaleur des villes : lumières de nuit floutées (la chaleur se diffuse ; sans flou, les pixels de la carte de nuit
	// dessinent des carrés).
	vec3 city_heat = textureLod(night_texture, UV, 3.0).rgb;
	vec2 gdx = dFdx(UV * DETAIL_GRID);
	vec2 gdy = dFdy(UV * DETAIL_GRID);
	vec3 tile_uv;
	float blend = detail_lookup(UV, tile_uv);
	if (blend > 0.0) {
		albedo = mix(albedo, textureGrad(detail_tiles, tile_uv, gdx, gdy).rgb, blend);
		blurred = mix(blurred, textureGrad(detail_tiles, tile_uv, gdx * 16.0, gdy * 16.0).rgb, blend);
		if (night_detail_ready) {
			night = mix(night, textureGrad(night_tiles, tile_uv, gdx, gdy).rgb, blend);
			city_heat = mix(city_heat, textureGrad(night_tiles, tile_uv, gdx * 8.0, gdy * 8.0).rgb, blend);
		}
	}
	vec3 n = normalize(local_km);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	float water = max(1.0 - nuke_land_share(n),
			smoothstep(0.015, 0.06, albedo.b - albedo.r) * (1.0 - smoothstep(0.18, 0.3, luma)));
	vec3 l = normalize(transpose(mat3(MODEL_MATRIX)) * sun_direction);
	float mu = dot(n, l);
	float cos_lat = sqrt(max(1.0 - n.y * n.y, 0.0));
	float polar = ir_polar_cooling * (1.0 - cos_lat);

	// Sol : terres (nuit + soleil, sols sombres plus chauds, végétation plus fraîche, contraste local) ou eau.
	float sun = smoothstep(-0.05, 0.9, mu);
	float green = smoothstep(0.0, 0.06, albedo.g - albedo.r);
	float relief = dot(albedo - blurred, vec3(0.299, 0.587, 0.114)) * mix(ir_relief_night, 1.0, sun);
	float land = ir_land_night + sun * (ir_land_sun * (1.1 - 2.0 * luma) - ir_vegetation * green)
			+ ir_relief * relief;
	float t = mix(land, ir_water + 0.03 * sun, water) - polar;
	// Villes : îlots de chaleur (plus marqués la nuit), éteints en partie par le black-out.
	float night_luma = dot(night, vec3(0.299, 0.587, 0.114));
	float urban = smoothstep(0.02, 0.3, dot(city_heat, vec3(0.299, 0.587, 0.114))) * (1.0 - water);
	ivec2 nuke_cell = nuke_ground_cell(n);
	float off = 0.0;
	if (nuke_cell.y > 0 || nuke_ground_country_count > 0) {
		off = nuke_blackout_darkness(n * CLOUD_PLANET_RADIUS_KM, n, nuke_cell);
	}
	t += ir_city * urban * mix(1.0, 0.35, sun) * (1.0 - 0.5 * off);
	// Incendies et trace au sol encore chaude.
	float fire = 0.0;
	if (nuke_cell.y > 0) {
		vec3 state = nuke_fire_state(n * CLOUD_PLANET_RADIUS_KM, nuke_cell, 1.0 - water, smoothstep(0.05, 0.3, night_luma));
		fire = state.x;
		t += 0.12 * state.y * (1.0 - state.z);
	}
	// Fumée (tiède), nuages (sommets froids) ; le feu perce un peu la fumée.
	ivec2 smoke_cell = nuke_smoke_cell(n);
	float smoke_clear = 1.0;
	if (smoke_cell.y > 0) {
		smoke_clear = exp(-nuke_smoke_tau(n, smoke_cell));
		t = mix(ir_smoke, t, smoke_clear);
	}
	CloudAdvection adv = cloud_advection(n);
	float clear = cloud_transmittance(n, n, adv);
	t += ir_fire * fire * mix(0.35, 1.0, smoke_clear);
	t = mix(ir_cloud_top + 0.05 * cos_lat, t, clear);
	if (nuke_flash_count > 0) {
		t += dot(nuke_flash_ground(n * CLOUD_PLANET_RADIUS_KM, n, adv), vec3(0.3333)) * 4.0;
	}
	t = (t - ir_pivot) * ir_contrast + ir_pivot;
	t += (ir_hash(floor(FRAGCOORD.xy) + fract(TIME * 7.13) * 61.0) - 0.5) * ir_grain;
	// Valeur affichée en sRGB : convertie en linéaire pour le rendu.
	ALBEDO = vec3(pow(clamp(t, 0.0, 1.0), 2.2)) * ir_gain;
}
