class_name NukeMushroom
extends Node3D
## Champignon atomique (scène nuke/nuke_mushroom.tscn, enfant d'une NukeEffect ; repère local en km, Y = verticale).
##
## Le nœud est mis à l'échelle NukeScaling.cloud_top_km : tout ce qu'il contient est en unités normalisées (sommet
## final = 1, chapeau final de rayon CAP_RADIUS_PER_TOP = 0,6). Le même champignon fait 10 km de haut à 10 kt et 65 km
## à 50 Mt, particules comprises.
##
## Profil (méridienne de PROFILE_POINTS points, tige puis chapeau), recalculé à chaque image et posé par le vertex
## shader (nuke/shaders/nuke_mushroom.gdshader) sur un maillage de révolution fixe. Les Curves sont lues en âge
## normalisé a = t / NukeScaling.MUSHROOM_RISE_S (temps physique ; stabilisation en ~10 min, ~1 min 36 s d'horloge) :
## - height_curve : sommet (part du sommet final ; Glasstone & Dolan, table 2.12) ;
## - cap_radius_curve : rayon du chapeau (part du rayon final) ; jamais moins que la boule de feu (rayon du flash) ;
## - cap_aspect_curve : épaisseur du chapeau / son diamètre (1 = sphère : la boule de feu du début) ;
## - stem_curve : rayon de la tige / rayon du chapeau ;
## - erosion_curve (domaine 0 à 3) : dissolution progressive de la tige, après la stabilisation.
## Au départ, le « chapeau » est la boule de feu, centrée à la hauteur d'explosion : le flash s'estompe en la révélant.
##
## Couleurs selon l'âge : albedo_gradient (en a : roux des oxydes d'azote, puis blanc-gris de la condensation) et
## lueur de la boule de feu, glow_gradient × glow_curve × glow_hdr en g = t / NukeScaling.fireball_glow_s (blanc,
## jaune, orange, rouge sombre, éteint).
## Chapeau roulant : angle de roulement autour de l'anneau tourbillonnaire, tour en roll_period_s au début, de plus en
## plus lent (ω = ω0 / (1 + t / roll_slowdown_s), intégré analytiquement : rejouable au scrubber).
##
## Particules (GPUParticles3D, nuke/shaders/nuke_smoke.gdshader) : fumée de la tige, jupon de condensation autour de
## la tige pendant la montée, débris soulevés au pied (explosions basses). Leur vitesse suit celle du temps physique
## (speed_scale = d(temps physique) / d(temps réel) : pause et accélération de l'horloge) ; elles ne se rejouent pas
## au scrubber.

const PROFILE_POINTS := 48
const STEM_POINTS := 16
const SEGMENTS := 64
const MAX_PARTICLE_SPEED := 20.0
const SHAPE_NOISE := preload("res://materials/cloud_shape_noise.tres")
const SMOKE_SHADER := preload("res://nuke/shaders/nuke_smoke.gdshader")

@export_group("Profil")
@export var height_curve: Curve
@export var cap_radius_curve: Curve
@export var cap_aspect_curve: Curve
@export var stem_curve: Curve
@export var erosion_curve: Curve
@export_group("Forme")
## Profondeur du dessous du chapeau sous son centre (part de sa demi-épaisseur), quand la tige existe.
@export var neck_drop := 0.6
## Évasement de la tige sous le chapeau (rayon du col / rayon de la tige).
@export var neck_flare := 1.8
## Évasement du pied de la tige (part du rayon) et sa hauteur (part du sommet courant).
@export var base_flare := 1.2
@export var base_flare_height := 0.05
## Exposants du profil du chapeau (cos φ^e) : petit = dessus plat et bord arrondi.
@export var cap_top_exponent := 0.45
@export var cap_under_exponent := 0.7
@export_group("Couleurs")
@export var albedo_gradient: Gradient
@export var glow_gradient: Gradient
@export var glow_curve: Curve
## Luminance HDR de la lueur à g = 0 (le soleil éclaire un nuage blanc à ~1,6).
@export var glow_hdr := 200.0
@export_group("Mouvement")
## Durée d'un tour de l'anneau tourbillonnaire au début (s physiques), et ralentissement.
@export var roll_period_s := 90.0
@export var roll_slowdown_s := 300.0
## Défilement du bruit de la tige vers le haut (unités normalisées par s physique, ralenti comme le roulement).
@export var stem_rise_speed := 0.004
@export var boil_rate := 0.0015
@export_group("Particules")
@export var stem_color := Color(0.5, 0.45, 0.4)
@export var skirt_color := Color(0.92, 0.93, 0.95)
@export var debris_color := Color(0.38, 0.32, 0.27)

static var _mesh: ArrayMesh
static var _smoke_mesh: QuadMesh

var _effect: NukeEffect
var _material: ShaderMaterial
var _sun: DirectionalLight3D
var _last_t := -1.0
var _stem: GPUParticles3D
var _skirt: GPUParticles3D
var _debris: GPUParticles3D

@onready var _cloud: MeshInstance3D = $Cloud


func _ready() -> void:
	_effect = get_parent() as NukeEffect
	var earth := _effect.get_parent() if _effect else null
	if earth and earth.get_parent():
		_sun = earth.get_parent().get_node_or_null(^"Sun") as DirectionalLight3D
	_material = (_cloud.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	_cloud.material_override = _material
	_cloud.mesh = _get_mesh()
	_stem = _make_particles("Stem", 40, 150.0, stem_color)
	_skirt = _make_particles("Skirt", 36, 80.0, skirt_color)
	_debris = _make_particles("Debris", 48, 120.0, debris_color)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	if _effect == null or _effect.params == null:
		return
	var params := _effect.params
	var w := params.yield_kt
	var t := _effect.get_time_s()
	visible = t > 0.0
	if not visible:
		_last_t = t
		return
	var top_km := NukeScaling.cloud_top_km(w)
	scale = Vector3.ONE * top_km

	# Forme à l'âge a (Curves) ; au départ, une sphère de la taille de la boule de feu.
	var a := t / NukeScaling.MUSHROOM_RISE_S
	var a1 := minf(a, 1.0)
	var flash := _effect.get_flash()
	var fireball_km := NukeScaling.fireball_radius_km(w)
	if flash and flash.radius_km > 0.0:
		fireball_km = flash.radius_km
	var rf := fireball_km / top_km
	var yb := params.burst_height_km / top_km
	var rc := maxf(rf, cap_radius_curve.sample(a1) * NukeScaling.CAP_RADIUS_PER_TOP)
	var hc := 2.0 * rc * cap_aspect_curve.sample(a1)
	var h := maxf(yb + 0.5 * hc, height_curve.sample(a1))
	var rs := stem_curve.sample(a1) * rc
	var under := lerpf(1.0, neck_drop, clampf(rs / (0.1 * rc), 0.0, 1.0))
	var yc := h - 0.5 * hc
	var y_neck := yc - under * 0.5 * hc
	_material.set_shader_parameter("profile", _profile(yc, 0.5 * hc, rc, rs, y_neck, h))
	_material.set_shader_parameter("stem_fraction", float(STEM_POINTS - 1) / float(PROFILE_POINTS - 1))
	_material.set_shader_parameter("ring", Vector2(0.55 * rc, yc))
	var slow := roll_slowdown_s * log(1.0 + t / roll_slowdown_s)
	_material.set_shader_parameter("roll_angle", TAU / roll_period_s * slow)
	_material.set_shader_parameter("rise_offset", stem_rise_speed * slow)
	_material.set_shader_parameter("boil", boil_rate * t)
	_material.set_shader_parameter("erosion", erosion_curve.sample(minf(a, erosion_curve.max_domain)))

	var albedo := albedo_gradient.sample(a1)
	_material.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	var g := minf(t / NukeScaling.fireball_glow_s(w), 1.0)
	var glow := glow_gradient.sample(g) * (glow_hdr * maxf(glow_curve.sample(g), 0.0))
	_material.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))

	# Repère de la planète (km) et soleil, pour la lumière filtrée par l'atmosphère.
	var units := OrbitSimulation.SCENE_UNITS_PER_KM
	var to_planet := Transform3D(Basis.from_scale(Vector3.ONE / units), Vector3.ZERO) * _effect.transform * transform
	_material.set_shader_parameter("local_to_planet_km", Projection(to_planet))
	var sun_dir := Vector3.UP
	var earth := _effect.get_parent() as Node3D
	if _sun and earth:
		sun_dir = (earth.global_basis.inverse() * _sun.global_basis.z).normalized()
		_material.set_shader_parameter("sun_dir_planet", sun_dir)

	_update_particles(delta, t, a, rs, y_neck, h, yb, rf, to_planet, sun_dir, glow)
	_last_t = t


## Méridienne : tige (STEM_POINTS points, du sol au col, pied et col évasés) puis chapeau (dessous, bord arrondi,
## dessus jusqu'à l'axe). Ordre de bas en haut le long de la surface extérieure : la normale (t.y, −t.x) est sortante.
func _profile(yc: float, b: float, rc: float, rs: float, y_neck: float, h: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(PROFILE_POINTS)
	var r_neck := minf(rs * neck_flare, rc)
	var y0 := minf(0.0, y_neck)
	for i in STEM_POINTS:
		var s := float(i) / float(STEM_POINTS - 1)
		var y := lerpf(y0, y_neck, s)
		var r := rs * (1.0 + base_flare * exp(-(y - y0) / maxf(base_flare_height * h, 1e-4)))
		points[i] = Vector2(lerpf(r, r_neck, smoothstep(0.7, 1.0, s)), y)
	var cap_points := PROFILE_POINTS - STEM_POINTS
	var under := (yc - y_neck) / maxf(b, 1e-6)
	for k in cap_points:
		var phi := -PI * 0.5 + PI * float(k + 1) / float(cap_points)
		var c := maxf(cos(phi), 0.0)
		if phi < 0.0:
			points[STEM_POINTS + k] = Vector2(r_neck + (rc - r_neck) * pow(c, cap_under_exponent), yc + b * under * sin(phi))
		else:
			points[STEM_POINTS + k] = Vector2(rc * pow(c, cap_top_exponent), yc + b * sin(phi))
	return points


func _update_particles(delta: float, t: float, a: float, rs: float, y_neck: float, h: float, yb: float,
		rf: float, to_planet: Transform3D, sun_dir: Vector3, glow: Color) -> void:
	# Vitesse du temps physique : pause, temps réel, accélération de l'horloge.
	var speed := 0.0
	if _last_t >= 0.0 and delta > 0.0:
		speed = clampf((t - _last_t) / delta, 0.0, MAX_PARTICLE_SPEED)
	# Lumière du soleil au milieu du nuage (atmosphère traversée vers le soleil ; nulle de nuit).
	var mid := to_planet * Vector3(0.0, 0.5 * h, 0.0)
	var tint := NukeAtmosphere.transmittance(mid, mid + sun_dir * 3000.0)
	tint *= smoothstep(-0.12, 0.05, mid.normalized().dot(sun_dir))
	var debris_glow := glow * 0.02
	for particles in [_stem, _skirt, _debris]:
		particles.speed_scale = speed
		particles.set_instance_shader_parameter("sun_tint", tint)
		particles.set_instance_shader_parameter("glow", Vector3(debris_glow.r, debris_glow.g, debris_glow.b))

	var stem_height := maxf(y_neck, 0.0)
	_stem.emitting = rs > 0.004 and a < 2.5 and stem_height > 0.02
	if _stem.emitting:
		var process := _stem.process_material as ParticleProcessMaterial
		_stem.position = Vector3(0.0, 0.5 * stem_height, 0.0)
		process.emission_box_extents = Vector3(rs * 0.7, 0.5 * stem_height, rs * 0.7)
		process.scale_min = rs * 2.0
		process.scale_max = rs * 3.2
		process.initial_velocity_min = stem_rise_speed * 0.3
		process.initial_velocity_max = stem_rise_speed * 0.8

	# Jupon de condensation : anneaux autour de la tige pendant la traversée des couches humides.
	_skirt.emitting = a > 0.03 and a < 0.3 and rs > 0.004
	if _skirt.emitting:
		var process := _skirt.process_material as ParticleProcessMaterial
		_skirt.position = Vector3(0.0, 0.45 * stem_height, 0.0)
		process.emission_ring_radius = rs * 2.4
		process.emission_ring_inner_radius = rs * 1.4
		process.scale_min = rs * 1.5
		process.scale_max = rs * 2.6

	# Débris et poussière aspirés au pied (explosions basses).
	_debris.emitting = a < 0.5 and yb < 2.0 * rf
	if _debris.emitting:
		var process := _debris.process_material as ParticleProcessMaterial
		process.emission_ring_radius = maxf(rs * 3.0, 0.02)
		process.emission_ring_inner_radius = 0.0
		process.scale_min = maxf(rs, 0.01) * 1.5
		process.scale_max = maxf(rs, 0.01) * 2.5


func _make_particles(node_name: String, amount: int, lifetime: float, color: Color) -> GPUParticles3D:
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
	add_child(particles)
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


## Maillage de révolution fixe : PROFILE_POINTS anneaux de SEGMENTS + 1 sommets (UV.x = angle, UV.y = position sur le
## profil) ; les positions sont posées par le vertex shader. Faces avant dans le sens horaire (convention Godot).
static func _get_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in PROFILE_POINTS:
		for j in SEGMENTS + 1:
			vertices.append(Vector3.ZERO)
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(j) / SEGMENTS, float(i) / (PROFILE_POINTS - 1)))
	for i in PROFILE_POINTS - 1:
		for j in SEGMENTS:
			var v := i * (SEGMENTS + 1) + j
			var above := v + SEGMENTS + 1
			indices.append_array([v, v + 1, above, v + 1, above + 1, above])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 1.6, 2.4))
	return _mesh
