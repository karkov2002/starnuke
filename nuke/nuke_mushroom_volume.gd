class_name NukeMushroomVolume
extends RefCounted
## Rendu volumétrique du champignon (composant de NukeMushroom, nœud Volume créé ici) : lancer de rayon dans un champ
## de densité (nuke/shaders/nuke_mushroom_volume.gdshader) sur une boîte englobante recalculée à chaque image.
## Chapeau, tige et nuage de base y sont des formes analytiques fondues en douceur et érodées par un bruit 3D,
## éclairées comme les nuages (auto-ombrage) ; silhouette déformée par une déformation basse fréquence propre à
## chaque explosion (seed) ; nuage dilué fragmenté en lambeaux (breakup) ; pas de la marche vers le soleil réduits
## quand le nuage est dilué (LIGHT_STEPS_BY_FADE).

## Fragmentation du nuage dilué (breakup du shader volumétrique) : BREAKUP_MAX × (1 − √fade).
const BREAKUP_MAX := 0.55
## Pas de la marche vers le soleil (auto-ombrage) selon la densité fade : (seuil, pas), du plus dense au plus dilué.
## Un voile dilué n'a presque plus d'ombre propre (mesure : 2 pas au lieu de 5 à 3 % de densité, PSNR > 65 dB), et
## cette marche est ~45 % du coût du volume à ce stade.
const LIGHT_STEPS_BY_FADE: Array[Vector2] = [Vector2(0.25, 5.0), Vector2(0.08, 3.0), Vector2(0.0, 2.0)]
const SHAPE_NOISE := preload("res://materials/cloud_shape_noise.tres")
const VOLUME_SHADER := preload("res://nuke/shaders/nuke_mushroom_volume.gdshader")

var node: MeshInstance3D
var material: ShaderMaterial
var _m: NukeMushroom


## Crée le nœud Volume (boîte unité) sous le champignon m, avec la marge de culling de son nuage.
func _init(m: NukeMushroom, cull_margin: float) -> void:
	_m = m
	material = ShaderMaterial.new()
	material.shader = VOLUME_SHADER
	material.render_priority = -1
	material.set_shader_parameter("noise_tex", SHAPE_NOISE)
	material.set_shader_parameter("base_flare", m.base_flare)
	material.set_shader_parameter("drift_top", NukeMushroomDrift.TOP)
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	node = MeshInstance3D.new()
	node.name = "Volume"
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = cull_margin
	m.add_child(node)


## Uniforms propres à l'explosion, posés une fois : extinction et premier pas de lumière (échelle du nœud), graine de
## la déformation (point et puissance).
func setup(params: NukeParams, top_km: float) -> void:
	material.set_shader_parameter("extinction", _m.volume_extinction_per_km * top_km)
	material.set_shader_parameter("light_first_step", 0.3 / top_km)
	material.set_shader_parameter("seed", Vector3(fposmod(params.latitude_deg * 0.731, 7.0),
			fposmod(params.longitude_deg * 0.377, 7.0), fposmod(params.yield_kt * 0.0013, 7.0)))


## Uniforms et boîte du volume : forme s, nuage de base (rayon, hauteur, opacité), boîte englobante (box_min, box_max,
## dérive comprise) et boîte cœur (extent, y_low, y_high : sans la dérive, là où le shader marche), repère de la
## planète, soleil, repère du champignon dans le monde, graine de la déformation.
func update(s: NukeMushroomShape, surge: Vector3, box_min: Vector3, box_max: Vector3, extent: float, y_low: float,
		y_high: float, to_planet: Transform3D, sun_dir: Vector3, world: Transform3D) -> void:
	var m := material
	m.set_shader_parameter("cap_center", s.yc)
	m.set_shader_parameter("cap_radius", s.rc)
	m.set_shader_parameter("cap_half", 0.5 * s.hc)
	m.set_shader_parameter("cap_under", s.under)
	m.set_shader_parameter("stem_radius", s.rs)
	m.set_shader_parameter("neck_height", s.y_neck)
	m.set_shader_parameter("base_flare_height", _m.base_flare_height * s.h)
	m.set_shader_parameter("stem_erosion", clampf(s.erosion, 0.0, 1.0))
	m.set_shader_parameter("surge_radius", surge.x)
	m.set_shader_parameter("surge_height", surge.y)
	m.set_shader_parameter("surge_density", surge.z)
	m.set_shader_parameter("ring", Vector2(0.55 * s.rc, s.yc))
	m.set_shader_parameter("roll_angle", s.roll_angle(_m))
	m.set_shader_parameter("rise_offset", s.rise_offset(_m))
	m.set_shader_parameter("boil", _m.boil_rate * s.t)
	m.set_shader_parameter("fade", s.fade)
	m.set_shader_parameter("breakup", BREAKUP_MAX * (1.0 - sqrt(s.fade)))
	for level in LIGHT_STEPS_BY_FADE:
		if s.fade >= level.x:
			m.set_shader_parameter("light_steps", int(level.y))
			break
	m.set_shader_parameter("warp_vertical", 1.0 / s.spread)
	m.set_shader_parameter("albedo", s.albedo_vec())
	m.set_shader_parameter("glow", s.glow_vec())
	m.set_shader_parameter("sun_dir_planet", sun_dir)
	m.set_shader_parameter("sun_dir_local", (to_planet.basis.inverse() * sun_dir).normalized())
	m.set_shader_parameter("local_to_planet_km", Projection(to_planet))
	m.set_shader_parameter("local_to_world", Projection(world))
	m.set_shader_parameter("world_to_local", Projection(world.affine_inverse()))
	m.set_shader_parameter("box_min", box_min)
	m.set_shader_parameter("box_max", box_max)
	# Boîte cœur (sans la dérive) : le shader ne marche que là où le rayon, dérive retirée, la traverse.
	m.set_shader_parameter("core_min", Vector3(-extent, y_low, -extent))
	m.set_shader_parameter("core_max", Vector3(extent, y_high, extent))
	node.transform = Transform3D(Basis.from_scale(0.5 * (box_max - box_min)), 0.5 * (box_min + box_max))
