class_name NukeMushroom
extends Node3D
## Champignon atomique (scène nuke/nuke_mushroom.tscn, enfant d'une NukeEffect ; repère local en km, Y = verticale).
##
## Le nœud est mis à l'échelle NukeScaling.cloud_top_km : tout ce qu'il contient est en unités normalisées (sommet
## final = 1, chapeau final de rayon CAP_RADIUS_PER_TOP = 0,6). Le même champignon fait 8 km de haut à 10 kt et 65 km
## à 50 Mt, particules comprises.
##
## Ce nœud garde les réglages (Curves, couleurs, mouvements : lus en âge normalisé a = t / NukeScaling.MUSHROOM_RISE_S,
## temps physique ; stabilisation en ~10 min, ~1 min 36 s d'horloge) et orchestre ses composants à chaque image :
## - NukeMushroomShape : forme et couleurs à l'instant t (calcul pur : sommet, chapeau, tige, dissipation, lueur) ;
## - NukeMushroomMesh : rendu par maillage de révolution (Cloud, BaseSurge : nuage de base des explosions basses),
##   conservé pour comparaison ; le nuage de base (rayon, hauteur, opacité) sert aussi au volume ;
## - NukeMushroomVolume (volumetric, par défaut) : lancer de rayon dans un champ de densité (nœud Volume, boîte
##   englobante recalculée ici : chapeau, nuage de base, dérive des hauteurs occupées) ;
## - NukeMushroomDrift : dérive au vent (profil vertical du vent réel GFS, pied ancré, cisaillement), interpolée par
##   les shaders (nuke/shaders/nuke_drift.gdshaderinc) ;
## - NukeMushroomParticles : fumée de la tige, jupon de condensation, débris au pied.
## Courbes : height_curve (sommet, part du sommet final ; Glasstone & Dolan 1977, §2.12), cap_radius_curve (rayon
## du chapeau, jamais moins que la boule de feu : rayon du flash), cap_aspect_curve (épaisseur / diamètre, 1 = la
## boule de feu du début), stem_curve (rayon de la tige / rayon du chapeau), erosion_curve (domaine 0 à 3 :
## dissolution de la tige après la stabilisation). Couleurs : albedo_gradient (en a : roux des oxydes d'azote, puis
## blanc-gris), lueur glow_gradient × glow_curve × glow_hdr en g = t / NukeScaling.fireball_glow_s. Chapeau roulant :
## tour en roll_period_s au début, ralenti (ω = ω0 / (1 + t / roll_slowdown_s), intégré : rejouable au scrubber).
## Explosion basse sur la mer (NukeParams.over_ocean) : nuage de vapeur d'eau (steam_*), affaissement et disparition
## en moins d'une heure (NukeScaling.steam_sink / steam_fade). Sous CLOUD_FADE_MIN, le champignon est masqué.

## Rendu volumétrique (NukeMushroomVolume) au lieu du maillage de révolution (NukeMushroomMesh), conservé pour
## comparaison.
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

var _effect: NukeEffect
var _sun: DirectionalLight3D
var _last_t := -1.0
var _mesh: NukeMushroomMesh
var _volume: NukeMushroomVolume
var _drift: NukeMushroomDrift
var _particles: NukeMushroomParticles
## Part « nuage de vapeur » (0 à 1) : explosion basse sur la mer.
var _steam := 0.0


func _ready() -> void:
	_effect = get_parent() as NukeEffect
	var earth := _effect.get_parent() if _effect else null
	if earth and earth.get_parent():
		_sun = earth.get_parent().get_node_or_null(^"Sun") as DirectionalLight3D
	var cloud := $Cloud as MeshInstance3D
	_mesh = NukeMushroomMesh.new(self, cloud)
	_volume = NukeMushroomVolume.new(self, cloud.extra_cull_margin)
	_particles = NukeMushroomParticles.new(self, stem_color, skirt_color, debris_color)
	if _effect and _effect.params:
		_drift = NukeMushroomDrift.new(_effect.params, height_curve, drift_shear)
		_volume.setup(_effect.params, NukeScaling.cloud_top_km(_effect.params.yield_kt))
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
	var t := _effect.get_time_s()
	visible = t > 0.0
	if not visible:
		_last_t = t
		return
	var flash := _effect.get_flash()
	var fireball_km := NukeScaling.fireball_radius_km(params.yield_kt)
	if flash and flash.radius_km > 0.0:
		fireball_km = flash.radius_km
	var s := NukeMushroomShape.new(self, params, t, fireball_km, _steam)
	scale = Vector3.ONE * s.top_km
	if not s.visible:
		visible = false
		_last_t = t
		return

	# Repère de la planète (km) et soleil, pour la lumière filtrée par l'atmosphère.
	var units := OrbitSimulation.SCENE_UNITS_PER_KM
	var to_planet := Transform3D(Basis.from_scale(Vector3.ONE / units), Vector3.ZERO) * _effect.transform * transform
	var sun_dir := Vector3.UP
	var earth := _effect.get_parent() as Node3D
	var has_sun := _sun != null and earth != null
	if has_sun:
		sun_dir = (earth.global_basis.inverse() * _sun.global_basis.z).normalized()
	# Dérive au vent (profil vertical), partagée par les matériaux du champignon.
	_drift.update(t, s.top_km, maxf(s.yc, 0.05))
	var surge := _mesh.surge_state(s, params.yield_kt, _steam)
	# Rendu volumétrique : les maillages restent cachés, rien n'est posé sur leurs matériaux.
	if not volumetric:
		_mesh.update(s, to_planet, sun_dir, has_sun)
		_mesh.set_drift(_drift.samples)
		_mesh.apply_surge(s, surge, to_planet, sun_dir)
	else:
		_mesh.hide()
	_volume.material.set_shader_parameter("drift_profile", _drift.samples)
	# Boîte englobante : chapeau, nuage de base, dérive des hauteurs occupées. La densité s'étend jusqu'à ~1,2 fois la
	# forme (bord rongé par le bruit) ; avec les lobes (+18 %) et la déformation (0,35 × rayon, verticale réduite de
	# 1 / spread) : ~1,75 fois le rayon du chapeau. Une fois la tige dissoute (et le nuage de base retombé), la boîte ne
	# descend plus jusqu'au sol : le chapeau peut être à des centaines de km du point zéro.
	var extent := maxf(maxf(s.rc * 1.8, surge.x * 1.15), s.rs * 4.0) + 0.02
	var y_low := 0.0
	if s.erosion >= 0.89 and surge.z <= 0.0:
		y_low = maxf(s.yc - 1.25 * s.under * 0.5 * s.hc - 0.35 * s.rc / s.spread - 0.02, 0.0)
	var y_high := maxf(s.h + 0.6 * s.hc_rise, s.yc + 1.25 * 0.5 * s.hc + 0.35 * s.rc / s.spread) + 0.02
	var drift_range := _drift.extent(y_low, y_high)
	var box_min := Vector3(drift_range[0].x - extent, y_low, drift_range[0].z - extent)
	var box_max := Vector3(drift_range[1].x + extent, y_high, drift_range[1].z + extent)
	_volume.node.visible = volumetric
	if volumetric:
		_volume.update(s, surge, box_min, box_max, extent, y_low, y_high, to_planet, sun_dir, global_transform)
	else:
		_mesh.set_bounds(AABB(box_min, box_max - box_min))
	# Particules : vitesse du temps physique (pause, temps réel, accélération de l'horloge) et lumière du soleil au
	# milieu du nuage (atmosphère traversée vers le soleil ; nulle de nuit).
	var speed := (t - _last_t) / delta if _last_t >= 0.0 and delta > 0.0 else 0.0
	var mid := to_planet * Vector3(0.0, 0.5 * s.h, 0.0)
	var tint := NukeAtmosphere.transmittance(mid, mid + sun_dir * 3000.0)
	tint *= smoothstep(-0.12, 0.05, mid.normalized().dot(sun_dir))
	_particles.update(speed, s.a, s.rs, s.y_neck, s.yb, s.rf, tint, s.glow, _drift, stem_rise_speed, volumetric)
	_last_t = t
