// Bouffées de fumée des particules du champignon (tige, jupon de condensation, débris ; nuke/nuke_mushroom.gd).
// Billboard face à la caméra (taille du particule conservée), forme procédurale : disque adouci rongé par un bruit 3D
// propre à chaque particule (pas de flipbook dans le projet). Pas de « soft particles » : elles liraient la texture de
// profondeur, peu fiable sous D3D12 dans ce projet ; les bords sont adoucis par la forme elle-même.
// Couleur et opacité : COLOR de ParticleProcessMaterial (rampe d'apparition / disparition). Éclairage : soleil diffus
// (normale de sphère reconstruite), teinté par sun_tint (atmosphère au point, fourni par le script), ciel en émission.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled,
		specular_disabled;

uniform sampler3D noise_tex : filter_linear_mipmap, repeat_enable;
instance uniform vec3 sun_tint = vec3(1.0);
uniform vec3 sky_ambient : source_color = vec3(0.45, 0.6, 0.9);
uniform float ambient_intensity = 0.25;
uniform float density = 1.0;
// Lueur rougeoyante (débris et bas du nuage éclairés par la boule de feu), HDR.
instance uniform vec3 glow = vec3(0.0);

varying float v_seed;
varying float v_rotation;

void vertex() {
	// Billboard (comme StandardMaterial3D, mode particules), en gardant l'échelle du particule.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	v_rotation = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float c = cos(v_rotation);
	float s = sin(v_rotation);
	vec2 ruv = vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
	float r = length(uv);
	vec3 q = vec3(ruv * 0.6, v_seed * 7.0);
	float n = 0.6 * texture(noise_tex, q).r + 0.4 * texture(noise_tex, q * 2.1 + vec3(0.3)).r;
	float shape = (1.0 - smoothstep(0.35, 1.0, r + 0.5 * (n - 0.5)));
	ALPHA = clamp(shape * density * COLOR.a * smoothstep(0.25, 0.6, n + 0.3 * (1.0 - r)), 0.0, 1.0);
	ALBEDO = COLOR.rgb * mix(0.7, 1.1, n);
	NORMAL = normalize(vec3(uv.x, uv.y, sqrt(max(1.0 - r * r, 0.05))));
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * sky_ambient * ambient_intensity * min(dot(sun_tint, vec3(0.33)) * 3.0, 1.0) + glow * shape;
}

void light() {
	float ndl = (dot(NORMAL, LIGHT) + 0.5) / 1.5;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * sun_tint * max(ndl, 0.0) / PI;
}
