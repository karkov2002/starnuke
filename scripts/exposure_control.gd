class_name ExposureControl
extends Node
## Exposition de la caméra (nœud Exposure de orbit_view.tscn), à la place de l'exposition automatique de Godot.
##
## L'exposition automatique se règle sur la luminance moyenne de toute l'image : en 32:9, ou en plein écran, le ciel
## noir pèse davantage qu'en 16:9, la moyenne chute et l'exposition monte — la Terre et la station blanchissent. Ici,
## l'exposition ne dépend que de l'éclairement du point de la Terre regardé (centre de la vue, sinon le point survolé),
## comme un œil adapté à l'extérieur : day_multiplier quand le soleil y est haut (hauteur ≥ day_elevation_deg),
## night_multiplier quand il est sous l'horizon (≤ night_elevation_deg), interpolation géométrique entre les deux
## (crépuscule), lissée en adaptation_s. Valeurs calibrées pour reproduire le rendu de l'exposition automatique en
## 16:9 (tools/bench/exposure_probe.tscn) : ×1 de jour, ×3 de nuit. Face au soleil (disque dans le champ, au-dessus
## du limbe), l'exposition est divisée par sun_dimming, comme l'œil ébloui : la Terre s'assombrit, les étoiles
## s'effacent (c'est ce que faisait l'exposition automatique, dominée par le disque).
## Multiplicateur final = GameSettings.brightness × ce facteur × dazzle (éblouissement du flash, NukeFlashFX).

const GROUP := &"exposure_control"

@export var orbit_path: NodePath = ^"../Orbit"
@export var earth_path: NodePath = ^"../Earth"
@export var sun_path: NodePath = ^"../Sun"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
## Base de jour et de nuit (multiplicateur d'exposition à luminosité 100 %). Calibration provisoire du 2026-10-16 :
## ×1 de jour reproduisait l'exposition automatique « à froid » en 16:9, mais l'utilisateur voyait un rendu nettement
## plus sombre (l'auto dépendait de l'historique de la session) : base abaissée à ×0,5, à ajuster avec le curseur de
## luminosité (25 à 150 %) puis à normaliser.
@export var day_multiplier := 0.5
@export var night_multiplier := 1.5
## Hauteur du soleil (degrés) au point regardé : plein jour au-dessus, pleine nuit en dessous.
@export var day_elevation_deg := 8.0
@export var night_elevation_deg := -12.0
## Face au soleil : division de l'exposition quand le disque est dans le champ, progressive sur sun_dimming_deg
## de part et d'autre du bord du champ (demi-diagonale).
@export var sun_dimming := 5.0
@export var sun_dimming_deg := 10.0
## Constante de temps de l'adaptation (s, temps réel).
@export var adaptation_s := 1.0

## Facteur d'éblouissement du flash (1 = aucun) et flux de flash reçu par la caméra (soleils), fournis par
## NukeFlashFX. L'éblouissement est bref et appliqué tel quel ; le flux reçu abaisse l'exposition (lissée, comme
## l'œil s'adapte à une scène qui s'éclaire) : c'est ce que faisait l'exposition automatique, et sans cela un flash
## éclaire toute la scène au lieu de rester concentré.
var dazzle := 1.0
var flash_received := 0.0
## Baisse de l'exposition par soleil de flux de flash reçu : facteur 1 / (1 + flash_adapt_gain × flux).
@export var flash_adapt_gain := 4.0

var _orbit: OrbitSimulation
var _earth: Node3D
var _sun: DirectionalLight3D
var _attributes: CameraAttributes
var _log_factor := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_earth = get_node_or_null(earth_path) as Node3D
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_environment:
		_attributes = world_environment.camera_attributes
	_log_factor = log(_target_factor())
	_apply()


func _process(delta: float) -> void:
	var target := log(_target_factor())
	_log_factor += (target - _log_factor) * (1.0 - exp(-delta / maxf(adaptation_s, 1e-3)))
	_apply()


## Facteur courant (sans la luminosité ni l'éblouissement).
func get_factor() -> float:
	return exp(_log_factor)


func _apply() -> void:
	if _attributes:
		_attributes.exposure_multiplier = GameSettings.brightness * exp(_log_factor) * dazzle


## Facteur cible d'après la hauteur du soleil au point regardé, divisé par l'éblouissement du soleil dans le champ.
func _target_factor() -> float:
	var elevation := _sun_elevation_deg()
	var night := 1.0 - smoothstep(night_elevation_deg, day_elevation_deg, elevation)
	var factor := exp(lerpf(log(day_multiplier), log(night_multiplier), night))
	return factor / lerpf(1.0, sun_dimming, _sun_in_view()) / (1.0 + flash_adapt_gain * maxf(flash_received, 0.0))


## Part (0 à 1) de l'éblouissement par le disque solaire : 1 quand il est dans le champ (demi-diagonale) et
## au-dessus du limbe terrestre vu de la caméra.
func _sun_in_view() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _sun == null or _earth == null:
		return 0.0
	var sun_dir := _sun.global_basis.z.normalized()
	# Soleil derrière la Terre : le rayon caméra → soleil traverse la sphère.
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	var oc := camera.global_position - _earth.global_position
	var b := oc.dot(sun_dir)
	if b < 0.0 and b * b - (oc.length_squared() - radius * radius) > 0.0:
		return 0.0
	var size := get_viewport().get_visible_rect().size
	var half_vertical := deg_to_rad(camera.fov) * 0.5
	var half_diagonal := atan(tan(half_vertical) * Vector2(size.x / maxf(size.y, 1.0), 1.0).length())
	var angle := acos(clampf(-camera.global_basis.z.dot(sun_dir), -1.0, 1.0))
	var edge := rad_to_deg(half_diagonal)
	return 1.0 - smoothstep(edge - sun_dimming_deg, edge + sun_dimming_deg, rad_to_deg(angle))


## Hauteur du soleil (degrés) au point de la Terre visé par le centre de la vue, sinon au point survolé.
func _sun_elevation_deg() -> float:
	if _earth == null or _sun == null:
		return 90.0
	var up := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera:
		var center := get_viewport().get_visible_rect().size * 0.5
		var origin := camera.project_ray_origin(center)
		var direction := camera.project_ray_normal(center)
		var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
		var oc := origin - _earth.global_position
		var b := oc.dot(direction)
		var discriminant := b * b - (oc.length_squared() - radius * radius)
		if discriminant >= 0.0:
			var t := -b - sqrt(discriminant)
			if t > 0.0:
				up = (oc + direction * t).normalized()
	if up == Vector3.ZERO:
		# Point survolé : la station est au zénith de ce point.
		var station_up := (get_viewport().get_camera_3d().global_position - _earth.global_position) if camera \
				else Vector3.UP
		up = station_up.normalized()
	# La lumière Sun regarde vers −sun : +Z de sa base pointe vers le soleil.
	var sun_dir := _sun.global_basis.z.normalized()
	return rad_to_deg(asin(clampf(up.dot(sun_dir), -1.0, 1.0)))
