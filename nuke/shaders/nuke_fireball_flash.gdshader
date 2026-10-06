// Boule de feu du flash : sphère émissive additive, luminance HDR fournie par nuke/nuke_flash.gd (instance uniform),
// bord adouci et léger assombrissement centre-bord. Rendue avant les nuages (render_priority −1) : un banc nuageux
// la voile, l'atmosphère y ajoute sa brume.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

instance uniform float radiance = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.94, 0.85);

void fragment() {
	float mu = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color * radiance * mix(0.6, 1.0, mu) * smoothstep(0.0, 0.3, mu);
}
