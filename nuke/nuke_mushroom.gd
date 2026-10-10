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
## Dérive au vent : NukeMushroomDrift (profil vertical du vent réel GFS, pied ancré, cisaillement : le chapeau s'étire
## et se tord dans le sens du vent), interpolée par les shaders (nuke/shaders/nuke_drift.gdshaderinc).
##
## Dissipation (après la stabilisation, NukeScaling.cloud_spread_ratio / cloud_fade) : le chapeau s'étale par la
## turbulence (rayon), s'amincit, sa densité baisse (masse diluée, puis disparition plus lente au-dessus de la
## tropopause) et il se fragmente en lambeaux (breakup du shader). Sous CLOUD_FADE_MIN, le champignon est masqué.
##
## Nuage de base (BaseSurge, explosions basses) : dôme de poussière au pied, même shader et même couleur que le
## champignon, qui s'étend vers l'extérieur avec l'onde de choc (surge_shock_ratio × rayon du front) et s'estompe en
## même temps que la tige se dissout. Avec le fondu du champignon près du sol (ground_fade du shader), il adoucit le
## contact entre la tige et le sol.
##
## Explosion basse sur la mer (NukeParams.over_ocean) : nuage de vapeur d'eau. Chapeau plus rond (steam_aspect) et
## blanc (steam_albedo), nuage de base d'embruns, débris remplacés par des embruns ; après la stabilisation, il
## s'affaisse (NukeScaling.steam_sink) et disparaît en moins d'une heure (NukeScaling.steam_fade).
##
## Particules (fumée de la tige, jupon de condensation, débris au pied) : NukeMushroomParticles.

const PROFILE_POINTS := 48
const STEM_POINTS := 16
## Maillage : anneaux (le profil est interpolé entre ses points) × segments autour de l'axe.
const RINGS := 96
const SEGMENTS := 128
## Fragmentation du nuage dilué (breakup du shader volumétrique) : BREAKUP_MAX × (1 − √fade).
const BREAKUP_MAX := 0.55
const SHAPE_NOISE := preload("res://materials/cloud_shape_noise.tres")
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
## Ancrage du pied : sous le centre du chapeau, la dérive est multipliée par (y / centre du chapeau)^drift_shear.
@export var drift_shear := 1.5
@export_group("Nuage de base")
## Rayon du dôme : part du rayon courant du front de choc ; hauteur : part de son rayon.
@export var surge_shock_ratio := 0.8
@export var surge_aspect := 0.08
@export var surge_opacity := 0.6
@export_group("Explosion sur la mer")
## Nuage de vapeur d'eau (NukeParams.over_ocean, explosion basse) : chapeau plus rond (épaisseur / diamètre d'au
## moins steam_aspect), blanchi vers steam_albedo, nuage de base d'embruns plus large et plus dense. Affaissement et
## disparition : NukeScaling.steam_sink / steam_fade.
@export var steam_aspect := 0.75
@export var steam_albedo := Color(0.93, 0.94, 0.96)
@export var steam_whiteness := 0.85
@export var steam_surge_ratio := 1.0
@export var steam_surge_opacity := 0.85
@export_group("Particules")
@export var stem_color := Color(0.5, 0.45, 0.4)
@export var skirt_color := Color(0.92, 0.93, 0.95)
@export var debris_color := Color(0.38, 0.32, 0.27)

static var _mesh: ArrayMesh

var _effect: NukeEffect
var _material: ShaderMaterial
var _surge_material: ShaderMaterial
var _surge: MeshInstance3D
var _volume: MeshInstance3D
var _volume_material: ShaderMaterial
var _sun: DirectionalLight3D
var _last_t := -1.0
var _drift: NukeMushroomDrift
var _particles: NukeMushroomParticles
## Part « nuage de vapeur » (0 à 1) : explosion basse sur la mer.
var _steam := 0.0

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
	_particles = NukeMushroomParticles.new(self, stem_color, skirt_color, debris_color)
	if _effect and _effect.params:
		_drift = NukeMushroomDrift.new(_effect.params, height_curve, drift_shear)
		if _effect.params.over_ocean:
			_steam = NukeScaling.low_burst(_effect.params.yield_kt, _effect.params.burst_height_km)
			# Au pied, des embruns plutôt que des débris.
			_particles.set_debris_color(debris_color.lerp(skirt_color, _steam))
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
	var aspect := cap_aspect_curve.sample(a1)
	var hc := 2.0 * rc * lerpf(aspect, maxf(aspect, steam_aspect), _steam)
	var h := maxf(yb + 0.5 * hc, height_curve.sample(a1))
	var rs := stem_curve.sample(a1) * rc
	var under := lerpf(1.0, neck_drop, clampf(rs / (0.1 * rc), 0.0, 1.0))
	var yc := h - 0.5 * hc
	var y_neck := yc - under * 0.5 * hc
	# Nuage de vapeur (explosion sur la mer) : après la stabilisation, l'eau retombe en pluie, le nuage s'affaisse.
	if _steam > 0.0:
		yc *= lerpf(1.0, NukeScaling.steam_sink(t), _steam)
		h = yc + 0.5 * hc
		y_neck = yc - under * 0.5 * hc

	# Dissipation après la stabilisation : étalement, amincissement (centre du chapeau fixe), dilution, disparition
	# (bien plus rapide pour le nuage de vapeur).
	var spread := NukeScaling.cloud_spread_ratio(w, t)
	var fade := NukeScaling.cloud_fade(t, spread, yc * top_km, params.latitude_deg) \
			* lerpf(1.0, NukeScaling.steam_fade(t), _steam)
	if fade < NukeScaling.CLOUD_FADE_MIN:
		visible = false
		_last_t = t
		return
	var hc_rise := hc
	if spread > 1.0:
		rc *= spread
		hc /= pow(spread, NukeScaling.CLOUD_THIN_EXP)
		h = yc + 0.5 * hc
		y_neck = yc - under * 0.5 * hc
	_material.set_shader_parameter("opacity", fade)
	_material.set_shader_parameter("profile", _profile(yc, 0.5 * hc, rc, rs, y_neck, h))
	_material.set_shader_parameter("stem_fraction", float(STEM_POINTS - 1) / float(PROFILE_POINTS - 1))
	_material.set_shader_parameter("ring", Vector2(0.55 * rc, yc))
	var slow := roll_slowdown_s * log(1.0 + t / roll_slowdown_s)
	_material.set_shader_parameter("roll_angle", TAU / roll_period_s * slow)
	_material.set_shader_parameter("rise_offset", stem_rise_speed * slow)
	_material.set_shader_parameter("boil", boil_rate * t)
	_material.set_shader_parameter("erosion", erosion_curve.sample(minf(a, erosion_curve.max_domain)))
	_material.set_shader_parameter("ground_fade", 0.04)

	var albedo := albedo_gradient.sample(a1).lerp(steam_albedo, _steam * steam_whiteness)
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

	# Dérive au vent (profil vertical), partagée par tous les matériaux du champignon.
	_drift.update(t, top_km, maxf(yc, 0.05))
	for m: ShaderMaterial in [_material, _surge_material, _volume_material]:
		m.set_shader_parameter("drift_profile", _drift.samples)
		m.set_shader_parameter("drift_top", NukeMushroomDrift.TOP)

	var erosion := erosion_curve.sample(minf(a, erosion_curve.max_domain))
	var surge := _update_surge(t, a, yb, rf, top_km, erosion, albedo, glow, to_planet, sun_dir)
	# Boîte englobante : chapeau, nuage de base, dérive des hauteurs occupées. La densité s'étend jusqu'à ~1,2 fois la
	# forme (bord rongé par le bruit) ; avec les lobes (+18 %) et la déformation (0,35 × rayon, verticale réduite de
	# 1 / spread) : ~1,75 fois le rayon du chapeau. Une fois la tige dissoute (et le nuage de base retombé), la boîte ne
	# descend plus jusqu'au sol : le chapeau peut être à des centaines de km du point zéro.
	var extent := maxf(maxf(rc * 1.8, surge.x * 1.15), rs * 4.0) + 0.02
	var y_low := 0.0
	if erosion >= 0.89 and surge.z <= 0.0:
		y_low = maxf(yc - 1.25 * under * 0.5 * hc - 0.35 * rc / spread - 0.02, 0.0)
	var y_high := maxf(h + 0.6 * hc_rise, yc + 1.25 * 0.5 * hc + 0.35 * rc / spread) + 0.02
	var drift_range := _drift.extent(y_low, y_high)
	var box_min := Vector3(drift_range[0].x - extent, y_low, drift_range[0].z - extent)
	var box_max := Vector3(drift_range[1].x + extent, y_high, drift_range[1].z + extent)
	_cloud.custom_aabb = AABB(box_min, box_max - box_min)
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
		m.set_shader_parameter("fade", fade)
		m.set_shader_parameter("breakup", BREAKUP_MAX * (1.0 - sqrt(fade)))
		m.set_shader_parameter("warp_vertical", 1.0 / spread)
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
		m.set_shader_parameter("box_min", box_min)
		m.set_shader_parameter("box_max", box_max)
		_volume.transform = Transform3D(Basis.from_scale(0.5 * (box_max - box_min)), 0.5 * (box_min + box_max))
	# Particules : vitesse du temps physique (pause, temps réel, accélération de l'horloge) et lumière du soleil au
	# milieu du nuage (atmosphère traversée vers le soleil ; nulle de nuit).
	var speed := (t - _last_t) / delta if _last_t >= 0.0 and delta > 0.0 else 0.0
	var mid := to_planet * Vector3(0.0, 0.5 * h, 0.0)
	var tint := NukeAtmosphere.transmittance(mid, mid + sun_dir * 3000.0)
	tint *= smoothstep(-0.12, 0.05, mid.normalized().dot(sun_dir))
	_particles.update(speed, a, rs, y_neck, yb, rf, tint, glow, _drift, stem_rise_speed, volumetric)
	_last_t = t


## Nuage de base : dôme de poussière bas, rayon = surge_shock_ratio × front de choc, même couleur que le champignon,
## qui s'estompe avec l'érosion de la tige. Seulement pour les explosions basses. Retourne (rayon, hauteur, opacité),
## nuls sans nuage de base (repris par le rendu volumétrique).
func _update_surge(t: float, a: float, yb: float, rf: float, top_km: float, erosion: float, albedo: Color,
		glow: Color, to_planet: Transform3D, sun_dir: Vector3) -> Vector3:
	var w := _effect.params.yield_kt
	var radius := lerpf(surge_shock_ratio, steam_surge_ratio, _steam) * NukeScaling.shock_front_radius_km(w, t) / top_km
	var fade := lerpf(surge_opacity, steam_surge_opacity, _steam) * smoothstep(0.0, 0.02, a) * (1.0 - smoothstep(0.0, 0.7, erosion))
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
