class_name NukeMushroom
extends Node3D
## Champignon atomique (scène nuke/nuke_mushroom.tscn, enfant d'une NukeEffect ; repère local en km, Y = verticale).
##
## Le nœud est mis à l'échelle NukeScaling.cloud_top_km : tout ce qu'il contient est en unités normalisées (sommet
## final = 1, chapeau final de rayon CAP_RADIUS_PER_TOP = 0,6). Le même champignon fait 8 km de haut à 10 kt et 65 km
## à 50 Mt, particules comprises.
##
## Rendu (volumetric, par défaut) : lancer de rayon dans un champ de densité (nuke/shaders/nuke_mushroom_volume.gdshader,
## nœud Volume : boîte englobante recalculée à chaque image). Chapeau, tige et nuage de base y sont des formes
## analytiques fondues en douceur et érodées par un bruit 3D, éclairées comme les nuages (auto-ombrage) : aspect gazeux,
## sans scintillement. La silhouette est rendue irrégulière par une déformation basse fréquence du domaine, propre à
## chaque explosion. Sinon, rendu par maillage (Cloud, BaseSurge), conservé pour comparaison.
##
## Profil (méridienne de PROFILE_POINTS points, tige puis chapeau), recalculé à chaque image et posé par le vertex
## shader (nuke/shaders/nuke_mushroom.gdshader) sur un maillage de révolution fixe. Les Curves sont lues en âge
## normalisé a = t / NukeScaling.MUSHROOM_RISE_S (temps physique ; stabilisation en ~10 min, ~1 min 36 s d'horloge) :
## - height_curve : sommet (part du sommet final ; Glasstone & Dolan 1977, §2.12) ;
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
## Dérive au vent (vent réel GFS du point d'impact, NukeParams ; le même que la dérive du trou dans les nuages) : le
## nuage est entraîné de v · t, le pied restant au point zéro. Le déplacement croît avec la hauteur jusqu'au centre du
## chapeau (puissance drift_shear) : la tige penche, le chapeau part en entier.
##
## Nuage de base (BaseSurge, explosions basses) : dôme de poussière au pied, même shader et même couleur que le
## champignon, qui s'étend vers l'extérieur avec l'onde de choc (surge_shock_ratio × rayon du front) et s'estompe en
## même temps que la tige se dissout. Avec le fondu du champignon près du sol (ground_fade du shader), il adoucit le
## contact entre la tige et le sol.
##
## Particules (GPUParticles3D, nuke/shaders/nuke_smoke.gdshader) : fumée de la tige, jupon de condensation autour de
## la tige pendant la montée, débris soulevés au pied (explosions basses). Leur vitesse suit celle du temps physique
## (speed_scale = d(temps physique) / d(temps réel) : pause et accélération de l'horloge) ; elles ne se rejouent pas
## au scrubber.

const PROFILE_POINTS := 48
const STEM_POINTS := 16
## Maillage : anneaux (le profil est interpolé entre ses points) × segments autour de l'axe.
const RINGS := 96
const SEGMENTS := 128
const MAX_PARTICLE_SPEED := 20.0
const SHAPE_NOISE := preload("res://materials/cloud_shape_noise.tres")
const SMOKE_SHADER := preload("res://nuke/shaders/nuke_smoke.gdshader")
const VOLUME_SHADER := preload("res://nuke/shaders/nuke_mushroom_volume.gdshader")

## Rendu volumétrique (lancer de rayon dans un champ de densité, nuke/shaders/nuke_mushroom_volume.gdshader) au lieu
## du maillage de révolution (Cloud, BaseSurge), conservé pour comparaison.
@export var volumetric := true
## Coefficient d'extinction du nuage (km⁻¹ ; les nuages de la couche : 1,5).
@export var volume_extinction_per_km := 1.0

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
## Durée d'un tour de l'anneau tourbillonnaire au début (s physiques), et ralentissement. 15 min : circulation de
## quelques dizaines de m/s autour d'un anneau de plusieurs km (avec l'horloge accélérée ×10, ~1 min 30 à l'écran).
@export var roll_period_s := 900.0
@export var roll_slowdown_s := 300.0
## Défilement du bruit de la tige vers le haut (unités normalisées par s physique, ralenti comme le roulement) :
## 0,0015 × sommet, soit ~35 m/s à 1 Mt et ~100 m/s à 50 Mt (courant ascendant de la tige).
@export var stem_rise_speed := 0.0015
@export var boil_rate := 0.0003
## Profil vertical de la dérive au vent (exposant de la hauteur relative au centre du chapeau).
@export var drift_shear := 1.5
@export_group("Nuage de base")
## Rayon du dôme : part du rayon courant du front de choc ; hauteur : part de son rayon.
@export var surge_shock_ratio := 0.8
@export var surge_aspect := 0.08
@export var surge_opacity := 0.6
@export_group("Particules")
@export var stem_color := Color(0.5, 0.45, 0.4)
@export var skirt_color := Color(0.92, 0.93, 0.95)
@export var debris_color := Color(0.38, 0.32, 0.27)

static var _mesh: ArrayMesh
static var _smoke_mesh: QuadMesh

var _effect: NukeEffect
var _material: ShaderMaterial
var _surge_material: ShaderMaterial
var _surge: MeshInstance3D
var _volume: MeshInstance3D
var _volume_material: ShaderMaterial
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
	_surge_material = _material.duplicate() as ShaderMaterial
	_surge_material.set_shader_parameter("stem_fraction", 0.0)
	_surge = MeshInstance3D.new()
	_surge.name = "BaseSurge"
	_surge.mesh = _cloud.mesh
	_surge.material_override = _surge_material
	_surge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surge.extra_cull_margin = _cloud.extra_cull_margin
	add_child(_surge)
	_volume_material = ShaderMaterial.new()
	_volume_material.shader = VOLUME_SHADER
	_volume_material.render_priority = -1
	_volume_material.set_shader_parameter("noise_tex", SHAPE_NOISE)
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	_volume = MeshInstance3D.new()
	_volume.name = "Volume"
	_volume.mesh = box
	_volume.material_override = _volume_material
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.extra_cull_margin = _cloud.extra_cull_margin
	add_child(_volume)
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
	_material.set_shader_parameter("ground_fade", 0.04)

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

	# Dérive au vent : la direction est celle d'où il vient (convention météo), l'air va à l'opposé. Repère local :
	# X = est, −Z = nord. Unités normalisées (vitesse en km/s rapportée au sommet final).
	var from := deg_to_rad(params.wind_direction_deg)
	var drift := Vector3(-sin(from), 0.0, cos(from)) * (params.wind_speed_m_s * 0.001 * t / top_km)
	var drift_height := maxf(yc, 0.05)
	_material.set_shader_parameter("drift", drift)
	_material.set_shader_parameter("drift_height", drift_height)
	_material.set_shader_parameter("drift_shear", drift_shear)

	var erosion := erosion_curve.sample(minf(a, erosion_curve.max_domain))
	var surge := _update_surge(t, a, yb, rf, top_km, erosion, albedo, glow, to_planet, sun_dir, drift, drift_height)
	_cloud.visible = not volumetric
	_surge.visible = _surge.visible and not volumetric
	_volume.visible = volumetric
	if volumetric:
		var m := _volume_material
		m.set_shader_parameter("cap_center", yc)
		m.set_shader_parameter("cap_radius", rc)
		m.set_shader_parameter("cap_half", 0.5 * hc)
		m.set_shader_parameter("cap_under", under)
		m.set_shader_parameter("stem_radius", rs)
		m.set_shader_parameter("neck_height", y_neck)
		m.set_shader_parameter("base_flare", base_flare)
		m.set_shader_parameter("base_flare_height", base_flare_height * h)
		m.set_shader_parameter("stem_erosion", clampf(erosion, 0.0, 1.0))
		m.set_shader_parameter("surge_radius", surge.x)
		m.set_shader_parameter("surge_height", surge.y)
		m.set_shader_parameter("surge_density", surge.z)
		m.set_shader_parameter("ring", Vector2(0.55 * rc, yc))
		m.set_shader_parameter("roll_angle", TAU / roll_period_s * slow)
		m.set_shader_parameter("rise_offset", stem_rise_speed * slow)
		m.set_shader_parameter("boil", boil_rate * t)
		m.set_shader_parameter("drift", drift)
		m.set_shader_parameter("drift_height", drift_height)
		m.set_shader_parameter("drift_shear", drift_shear)
		m.set_shader_parameter("extinction", volume_extinction_per_km * top_km)
		m.set_shader_parameter("light_first_step", 0.3 / top_km)
		m.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
		m.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))
		m.set_shader_parameter("sun_dir_planet", sun_dir)
		m.set_shader_parameter("sun_dir_local", (to_planet.basis.inverse() * sun_dir).normalized())
		m.set_shader_parameter("local_to_planet_km", Projection(to_planet))
		m.set_shader_parameter("local_to_world", Projection(global_transform))
		m.set_shader_parameter("world_to_local", Projection(global_transform.affine_inverse()))
		m.set_shader_parameter("seed", Vector3(fposmod(params.latitude_deg * 0.731, 7.0),
				fposmod(params.longitude_deg * 0.377, 7.0), fposmod(params.yield_kt * 0.0013, 7.0)))
		# Boîte englobante : chapeau (avec marge pour les lobes et la déformation), nuage de base, dérive.
		var extent := maxf(maxf(rc * 1.6, surge.x * 1.15), rs * 4.0) + 0.02
		var box_min := Vector3(minf(drift.x, 0.0) - extent, 0.0, minf(drift.z, 0.0) - extent)
		var box_max := Vector3(maxf(drift.x, 0.0) + extent, h + 0.6 * hc + 0.02, maxf(drift.z, 0.0) + extent)
		m.set_shader_parameter("box_min", box_min)
		m.set_shader_parameter("box_max", box_max)
		_volume.transform = Transform3D(Basis.from_scale(0.5 * (box_max - box_min)), 0.5 * (box_min + box_max))
	_update_particles(delta, t, a, rs, y_neck, h, yb, rf, to_planet, sun_dir, glow, drift, drift_height)
	_last_t = t


## Nuage de base : dôme de poussière bas, rayon = surge_shock_ratio × front de choc, même couleur que le champignon,
## qui s'estompe avec l'érosion de la tige. Seulement pour les explosions basses. Retourne (rayon, hauteur, opacité),
## nuls sans nuage de base (repris par le rendu volumétrique).
func _update_surge(t: float, a: float, yb: float, rf: float, top_km: float, erosion: float, albedo: Color,
		glow: Color, to_planet: Transform3D, sun_dir: Vector3, drift: Vector3, drift_height: float) -> Vector3:
	var w := _effect.params.yield_kt
	var radius := surge_shock_ratio * NukeScaling.shock_front_radius_km(w, t) / top_km
	var fade := surge_opacity * smoothstep(0.0, 0.02, a) * (1.0 - smoothstep(0.0, 0.7, erosion))
	_surge.visible = yb < 2.0 * rf and radius > 0.002 and fade > 0.005
	if not _surge.visible:
		return Vector3.ZERO
	var height := surge_aspect * radius
	var points := PackedVector2Array()
	points.resize(PROFILE_POINTS)
	for i in PROFILE_POINTS:
		var phi := PI * 0.5 * float(i) / float(PROFILE_POINTS - 1)
		points[i] = Vector2(radius * pow(maxf(cos(phi), 0.0), 0.35), height * sin(phi))
	var m := _surge_material
	m.set_shader_parameter("profile", points)
	m.set_shader_parameter("ring", Vector2(0.6 * radius, 0.4 * height))
	m.set_shader_parameter("roll_angle", -0.5 * _material.get_shader_parameter("roll_angle"))
	m.set_shader_parameter("boil", _material.get_shader_parameter("boil"))
	m.set_shader_parameter("opacity", fade)
	m.set_shader_parameter("ground_fade", height)
	m.set_shader_parameter("edge_erosion", 0.6)
	m.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	m.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b) * 0.03)
	m.set_shader_parameter("local_to_planet_km", Projection(to_planet))
	m.set_shader_parameter("sun_dir_planet", sun_dir)
	m.set_shader_parameter("drift", drift)
	m.set_shader_parameter("drift_height", drift_height)
	m.set_shader_parameter("drift_shear", drift_shear)
	return Vector3(radius, height, fade)


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


## Dérive au vent à la hauteur y (même loi que le vertex shader).
func _drift_at(y: float, drift: Vector3, drift_height: float) -> Vector3:
	return drift * pow(clampf(y / maxf(drift_height, 1e-4), 0.0, 1.0), drift_shear)


func _update_particles(delta: float, t: float, a: float, rs: float, y_neck: float, h: float, yb: float,
		rf: float, to_planet: Transform3D, sun_dir: Vector3, glow: Color, drift: Vector3, drift_height: float) -> void:
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

	# Les émetteurs suivent la dérive au vent à leur hauteur (même loi que le shader).
	var stem_height := maxf(y_neck, 0.0)
	_stem.position = Vector3(0.0, 0.5 * stem_height, 0.0) + _drift_at(0.5 * stem_height, drift, drift_height)
	_skirt.position = Vector3(0.0, 0.45 * stem_height, 0.0) + _drift_at(0.45 * stem_height, drift, drift_height)
	# En rendu volumétrique, la tige est déjà dans le volume : sa fumée ferait doublon (taches sombres).
	_stem.visible = not volumetric
	_stem.emitting = not volumetric and rs > 0.004 and a < 2.5 and stem_height > 0.02
	if _stem.emitting:
		var process := _stem.process_material as ParticleProcessMaterial
		process.emission_box_extents = Vector3(rs * 0.7, 0.5 * stem_height, rs * 0.7)
		process.scale_min = rs * 2.0
		process.scale_max = rs * 3.2
		process.initial_velocity_min = stem_rise_speed * 0.3
		process.initial_velocity_max = stem_rise_speed * 0.8

	# Jupon de condensation : anneaux autour de la tige pendant la traversée des couches humides.
	_skirt.emitting = a > 0.03 and a < 0.3 and rs > 0.004
	if _skirt.emitting:
		var process := _skirt.process_material as ParticleProcessMaterial
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


## Maillage de révolution fixe : RINGS anneaux de SEGMENTS + 1 sommets (UV.x = angle, UV.y = position sur le profil,
## interpolé entre ses points) ; les positions sont posées par le vertex shader. Faces avant dans le sens horaire
## (convention Godot).
static func _get_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in RINGS:
		for j in SEGMENTS + 1:
			vertices.append(Vector3.ZERO)
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(j) / SEGMENTS, float(i) / (RINGS - 1)))
	for i in RINGS - 1:
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
