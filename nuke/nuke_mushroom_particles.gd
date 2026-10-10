class_name NukeMushroomParticles
extends RefCounted
## Particules d'un champignon (GPUParticles3D ajoutés comme enfants du nœud Mushroom ; bouffées procédurales par
## bruit, nuke/shaders/nuke_smoke.gdshader, éclairées comme le nuage) :
## - fumée le long de la tige (rendu par maillage seulement : en volumétrique, elle ferait doublon avec la tige du
##   volume) ;
## - jupon de condensation : anneaux autour de la tige pendant la traversée des couches humides (âge 0,03 à 0,3) ;
## - débris et poussière aspirés au pied (explosions basses, âge < 0,5) ; embruns sur la mer (set_debris_color).
## Leur vitesse suit celle du temps physique (speed_scale : pause et accélération de l'horloge) ; elles ne se rejouent
## pas au scrubber. Les émetteurs suivent la dérive au vent à leur hauteur (NukeMushroomDrift).

const MAX_SPEED := 20.0
const SHAPE_NOISE := preload("res://materials/cloud_shape_noise.tres")
const SMOKE_SHADER := preload("res://nuke/shaders/nuke_smoke.gdshader")

static var _smoke_mesh: QuadMesh

var _stem: GPUParticles3D
var _skirt: GPUParticles3D
var _debris: GPUParticles3D


func _init(parent: Node3D, stem_color: Color, skirt_color: Color, debris_color: Color) -> void:
	_stem = _make(parent, "Stem", 40, 150.0, stem_color)
	_skirt = _make(parent, "Skirt", 36, 80.0, skirt_color)
	_debris = _make(parent, "Debris", 48, 120.0, debris_color)


func set_debris_color(color: Color) -> void:
	(_debris.process_material as ParticleProcessMaterial).color = color


## Mise à jour par image. speed : vitesse du temps physique (d t_physique / d t_réel) ; a : âge du champignon ;
## rs, y_neck, h : rayon de la tige, hauteur du col, sommet (unités normalisées) ; yb, rf : hauteur d'explosion et
## rayon de la boule de feu ; tint : lumière du soleil au milieu du nuage ; glow : lueur de la boule de feu ;
## rise_speed : défilement de la tige ; volumetric : rendu volumétrique (pas de fumée de tige).
func update(speed: float, a: float, rs: float, y_neck: float, yb: float, rf: float, tint: Vector3, glow: Color,
		drift: NukeMushroomDrift, rise_speed: float, volumetric: bool) -> void:
	var debris_glow := glow * 0.02
	for particles in [_stem, _skirt, _debris]:
		particles.speed_scale = clampf(speed, 0.0, MAX_SPEED)
		particles.set_instance_shader_parameter("sun_tint", tint)
		particles.set_instance_shader_parameter("glow", Vector3(debris_glow.r, debris_glow.g, debris_glow.b))

	var stem_height := maxf(y_neck, 0.0)
	_stem.position = Vector3(0.0, 0.5 * stem_height, 0.0) + drift.at(0.5 * stem_height)
	_skirt.position = Vector3(0.0, 0.45 * stem_height, 0.0) + drift.at(0.45 * stem_height)
	# En rendu volumétrique, la tige est déjà dans le volume : sa fumée ferait doublon (taches sombres).
	_stem.visible = not volumetric
	_stem.emitting = not volumetric and rs > 0.004 and a < 2.5 and stem_height > 0.02
	if _stem.emitting:
		var process := _stem.process_material as ParticleProcessMaterial
		process.emission_box_extents = Vector3(rs * 0.7, 0.5 * stem_height, rs * 0.7)
		process.scale_min = rs * 2.0
		process.scale_max = rs * 3.2
		process.initial_velocity_min = rise_speed * 0.3
		process.initial_velocity_max = rise_speed * 0.8

	_skirt.emitting = a > 0.03 and a < 0.3 and rs > 0.004
	if _skirt.emitting:
		var process := _skirt.process_material as ParticleProcessMaterial
		process.emission_ring_radius = rs * 2.4
		process.emission_ring_inner_radius = rs * 1.4
		process.scale_min = rs * 1.5
		process.scale_max = rs * 2.6

	_debris.emitting = a < 0.5 and yb < 2.0 * rf
	if _debris.emitting:
		var process := _debris.process_material as ParticleProcessMaterial
		process.emission_ring_radius = maxf(rs * 3.0, 0.02)
		process.emission_ring_inner_radius = 0.0
		process.scale_min = maxf(rs, 0.01) * 1.5
		process.scale_max = maxf(rs, 0.01) * 2.5


static func _make(parent: Node3D, node_name: String, amount: int, lifetime: float, color: Color) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.direction = Vector3.UP
	process.spread = 20.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color = color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	match node_name:
		"Stem":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		"Skirt":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_height = 0.01
			process.radial_velocity_min = 0.0002
			process.radial_velocity_max = 0.0006
			process.spread = 5.0
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.0002
		"Debris":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_height = 0.005
			process.radial_velocity_min = -0.0008
			process.radial_velocity_max = -0.0002
			process.initial_velocity_min = 0.0015
			process.initial_velocity_max = 0.004
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = true
	particles.process_material = process
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.visibility_aabb = AABB(Vector3(-1.5, -0.3, -1.5), Vector3(3.0, 1.8, 3.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_pass_1 = _get_smoke_mesh()
	particles.emitting = false
	parent.add_child(particles)
	return particles


static func _get_smoke_mesh() -> QuadMesh:
	if _smoke_mesh == null:
		var material := ShaderMaterial.new()
		material.shader = SMOKE_SHADER
		material.render_priority = -1
		material.set_shader_parameter("noise_tex", SHAPE_NOISE)
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.material = material
	return _smoke_mesh
