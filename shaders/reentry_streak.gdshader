shader_type spatial;
// Traînée de plasma d'une tête de missile qui rentre dans l'atmosphère, vue depuis l'orbite (scripts/reentry_streak.gd).
// Ruban additif tendu entre la tête (head) et la queue (tail), positions du monde fixées chaque image par le script :
// toujours face à la caméra, effilé vers la queue, jamais plus fin que min_pixels à l'écran. Couleurs d'une rentrée
// observée depuis l'ISS (météores, capsules) : tête blanc-bleuté éblouissante (gaz du choc à ~10 000 K), sillage qui
// passe au jaune puis à l'orange et au rouge sombre en se refroidissant, avec des bouffées (ablation irrégulière du
// bouclier). Test de profondeur actif : la Terre (et les nuages qui écrivent la profondeur) masquent la traînée.
// Mélange par opacité (et non additif) avec des couleurs HDR : en plein jour, devant des nuages blancs, une traînée
// additive se fondrait dans le blanc ; ici elle garde sa couleur, et son éclat (HDR) déborde en halo.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 head;
uniform vec3 tail;
// Demi-largeur réelle de la traînée à la tête (unités de scène).
uniform float half_width = 0.003;
// Angle d'un pixel (radians) et largeur minimale (pixels, demi-largeur) à l'écran.
uniform float pixel_angle = 0.0007;
uniform float min_pixels = 1.6;
uniform float intensity = 1.0;
uniform float seed = 0.0;

varying float along;
varying float across;

void vertex() {
	// QuadMesh de 1 × 1 subdivisé : x (−0,5 à 0,5) le long de la traînée, y (−0,5 à 0,5) en travers.
	along = VERTEX.x + 0.5;
	across = VERTEX.y * 2.0;
	vec3 p = mix(head, tail, along);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 dir = tail - head;
	dir = length(dir) > 1e-6 ? normalize(dir) : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(dir, normalize(eye - p));
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float width = max(half_width, min_pixels * pixel_angle * distance(eye, p));
	// Effilée : pleine largeur derrière la tête, 30 % au bout.
	width *= mix(1.0, 0.3, along);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p + side * across * width, 1.0);
}

float hash(float x) {
	return fract(sin(x * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	float a = clamp(along, 0.0, 1.0);
	float core = exp(-across * across * 5.0);
	// Refroidissement le long du sillage : blanc-bleuté, jaune, orange, rouge sombre.
	vec3 hot = vec3(0.85, 0.92, 1.0);
	vec3 yellow = vec3(1.0, 0.75, 0.3);
	vec3 orange = vec3(1.0, 0.36, 0.06);
	vec3 red = vec3(0.6, 0.06, 0.02);
	vec3 color = a < 0.06 ? mix(hot, yellow, a / 0.06)
			: (a < 0.3 ? mix(yellow, orange, (a - 0.06) / 0.24) : mix(orange, red, (a - 0.3) / 0.7));
	// Éclat : très fort au ras de la tête, décroissance rapide puis longue queue ténue (la couleur, et non la
	// saturation en blanc, doit dominer passé la tête : éclat modéré au-delà).
	float fall = exp(-a * 5.0) * 0.8 + pow(1.0 - a, 1.5) * 0.45;
	// Bouffées d'ablation qui défilent le long du sillage, et léger vacillement d'ensemble.
	float cell = floor(a * 18.0 - TIME * 6.0);
	float puffs = 0.75 + 0.5 * hash(cell);
	float flicker = 0.9 + 0.1 * sin(TIME * 23.0 + seed * 5.0);
	float glow = fall * puffs * flicker;
	ALBEDO = color * (1.0 + 4.0 * glow) * intensity;
	ALPHA = clamp(core * glow * 3.0 * min(intensity, 1.0), 0.0, 1.0);
}
