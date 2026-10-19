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
## Facteur final = GameSettings.brightness × ce facteur × dazzle (éblouissement du flash, NukeFlashFX).
##
## Application : par l'exposition automatique de Godot **bridée** — sensibilité minimale = maximale = base_sensitivity
## / facteur (auto_exposure_scale 0,22, vitesse 20 : elle suit la consigne en quelques images, le lissage est fait
## ici). CameraAttributes.exposure_multiplier n'agit pas sur le rendu dans ce build (Godot 4.7, D3D12, Forward+ :
## à 0, l'image de jour reste presque inchangée ; seule la voie automatique expose réellement l'image, mesure
## tools/bench/exposure_sweep.tscn). La sensibilité imposée ne dépend pas du contenu de l'image : même rendu en
## 16:9 et en 32:9. base_sensitivity 200 : rendu de jour de référence (nuages texturés, océan profond) ; nuit ×2,85 →
## sensibilité 70, le plafond de l'ancienne exposition automatique.

const GROUP := &"exposure_control"

@export var orbit_path: NodePath = ^"../Orbit"
@export var earth_path: NodePath = ^"../Earth"
@export var sun_path: NodePath = ^"../Sun"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
@export var station_path: NodePath = ^"../Station/StationSpatiale"
## Sensibilité (ISO) de jour à luminosité 100 % et facteur 1 ; l'exposition en est l'inverse.
@export var base_sensitivity := 200.0
## Facteurs d'exposition de jour et de nuit (×1 : sensibilité base_sensitivity), et de l'intérieur de la station
## (lumières artificielles constantes : la même exposition de jour comme de nuit, sinon l'intérieur sature la nuit).
## L'écran est partagé entre Terre et intérieur selon la part des rayons d'une grille VIEW_GRID × VIEW_GRID qui
## touchent la Terre ; le facteur est interpolé (géométriquement) entre les deux.
@export var day_multiplier := 1.0
@export var night_multiplier := 2.85
@export var interior_multiplier := 1.0
## Hors de la cupola et à moins de cette distance (m) de la station, l'œil est dans les modules : facteur
## interior_multiplier seul (ni Terre, ni soleil, ni flash : la coque les cache).
@export var outside_distance_m := 25.0
const VIEW_GRID := 3
## Hauteur du soleil (degrés) au point regardé : plein jour au-dessus, pleine nuit en dessous.
@export var day_elevation_deg := 8.0
@export var night_elevation_deg := -12.0
## Face au soleil : division de l'exposition quand le disque est dans le champ, progressive sur sun_dimming_deg
## de part et d'autre du bord du champ (demi-diagonale).
@export var sun_dimming := 5.0
@export var sun_dimming_deg := 10.0
## Constantes de temps de l'adaptation (s, temps réel) : vers le clair (scène qui s'assombrit : lente, comme l'œil)
## et vers le sombre (scène qui s'éclaire, flash : rapide — c'est elle qui garde un flash concentré).
@export var adaptation_s := 1.0
@export var darkening_s := 0.25

## Facteur d'éblouissement du flash (1 = aucun) et flux de flash reçu par la caméra (soleils), fournis par
## NukeFlashFX. L'éblouissement est bref et appliqué tel quel ; le flux reçu abaisse l'exposition (lissée, comme
## l'œil s'adapte à une scène qui s'éclaire) : c'est ce que faisait l'exposition automatique, et sans cela un flash
## éclaire toute la scène au lieu de rester concentré.
var dazzle := 1.0
var flash_received := 0.0
## Baisse de l'exposition par soleil de flux de flash reçu : facteur 1 / (1 + flash_adapt_gain × flux).
@export var flash_adapt_gain := 8.0

var _orbit: OrbitSimulation
var _earth: Node3D
var _sun: DirectionalLight3D
## Station (scripts/station.gd), pour savoir si l'observateur est dans la cupola.
var _station: Node
var _attributes: CameraAttributes
var _log_factor := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_earth = get_node_or_null(earth_path) as Node3D
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_station = get_node_or_null(station_path)
	var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_environment:
		_attributes = world_environment.camera_attributes
	_log_factor = log(_target_factor())
	_apply()


func _process(delta: float) -> void:
	var target := log(_target_factor())
	var tau := darkening_s if target < _log_factor else adaptation_s
	_log_factor += (target - _log_factor) * (1.0 - exp(-delta / maxf(tau, 1e-3)))
	_apply()


## Facteur courant (sans la luminosité ni l'éblouissement).
func get_factor() -> float:
	return exp(_log_factor)


func _apply() -> void:
	var practical := _attributes as CameraAttributesPractical
	if practical == null:
		return
	var sensitivity := base_sensitivity / maxf(GameSettings.brightness * exp(_log_factor) * dazzle, 1e-4)
	practical.auto_exposure_enabled = true
	practical.auto_exposure_min_sensitivity = sensitivity
	practical.auto_exposure_max_sensitivity = sensitivity
	# Le multiplicateur a un effet partiel (ciel, glow) : neutralisé, tout passe par la sensibilité.
	practical.exposure_multiplier = 1.0


## Facteur cible : intérieur de la station (interior_multiplier) fondu, selon la part de l'écran occupée par la Terre,
## avec le facteur jour / nuit du point regardé ; divisé par l'éblouissement du soleil dans le champ (depuis la cupola
## seulement : ailleurs la coque le cache) et par l'adaptation au flash.
func _target_factor() -> float:
	# Hors de la cupola, dans les modules, la coque cache la Terre et les flashs : l'œil reste réglé sur l'éclairage
	# intérieur (les rayons de _earth_view traversent la coque). Dehors (éjection), comme dans la cupola.
	if not _in_cupola() and not _outside():
		return interior_multiplier
	var view := _earth_view()
	var night := 1.0 - smoothstep(night_elevation_deg, day_elevation_deg, view.elevation)
	var earth_factor := lerpf(log(day_multiplier), log(night_multiplier), night)
	# Les montants de la cupola occupent une part fixe de l'écran : la Terre domine dès qu'elle en couvre ~60 %.
	var factor := exp(lerpf(log(interior_multiplier), earth_factor, smoothstep(0.0, 0.6, view.fraction)))
	var sun := _sun_in_view() if _in_cupola() else 0.0
	return factor / lerpf(1.0, sun_dimming, sun) / (1.0 + flash_adapt_gain * maxf(flash_received, 0.0))


## Part (0 à 1) de l'éblouissement par le disque solaire : 1 quand il est dans le champ (demi-diagonale) et
## au-dessus du limbe terrestre vu de la caméra.
func _sun_in_view() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _sun == null or _earth == null:
		return 0.0
	var sun_dir := _sun.global_basis.z.normalized()
	# Les fenêtres de la cupola donnent vers la Terre : un soleil au-dessus de l'horizontale de la station est caché
	# par la coque (sinon, viser le plafond avec le soleil derrière assombrissait la vue).
	var oc := camera.global_position - _earth.global_position
	if sun_dir.dot(-oc.normalized()) < -0.05:
		return 0.0
	# Soleil derrière la Terre : le rayon caméra → soleil traverse la sphère.
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
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
## Vue de la Terre : {fraction : part des rayons de la grille VIEW_GRID × VIEW_GRID qui touchent la Terre,
## elevation : hauteur du soleil (degrés) au point moyen touché (sinon au point survolé)}.
func _earth_view() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if _earth == null or _sun == null or camera == null:
		return {"fraction": 1.0, "elevation": 90.0}
	var size := get_viewport().get_visible_rect().size
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	var hits := 0
	var up := Vector3.ZERO
	for i in VIEW_GRID:
		for j in VIEW_GRID:
			var point := Vector2((i + 0.5) / VIEW_GRID, (j + 0.5) / VIEW_GRID) * size
			var origin := camera.project_ray_origin(point)
			var direction := camera.project_ray_normal(point)
			var oc := origin - _earth.global_position
			var b := oc.dot(direction)
			var discriminant := b * b - (oc.length_squared() - radius * radius)
			if discriminant < 0.0:
				continue
			var t := -b - sqrt(discriminant)
			if t > 0.0:
				hits += 1
				up += (oc + direction * t).normalized()
	if hits == 0:
		# Point survolé : la station est au zénith de ce point.
		up = camera.global_position - _earth.global_position
	# La lumière Sun regarde vers −sun : +Z de sa base pointe vers le soleil.
	var sun_dir := _sun.global_basis.z.normalized()
	var elevation := rad_to_deg(asin(clampf(up.normalized().dot(sun_dir), -1.0, 1.0)))
	return {"fraction": float(hits) / float(VIEW_GRID * VIEW_GRID), "elevation": elevation}


## L'observateur est-il dans la cupola (Station.is_in_cupola) ? Sinon (intérieur de la station), le soleil n'est
## jamais en vue.
func _in_cupola() -> bool:
	var camera := get_viewport().get_camera_3d()
	return _station != null and camera != null and _station.call(&"is_in_cupola", camera.global_position)


## La caméra est-elle hors de la station ? Éjection (Station.observer_outside), caméra à plus de outside_distance_m
## de la station (décor du menu : caméra extérieure), ou pas de station.
func _outside() -> bool:
	var camera := get_viewport().get_camera_3d()
	if _station == null or camera == null:
		return true
	return bool(_station.get(&"observer_outside")) \
			or camera.global_position.distance_to((_station as Node3D).global_position) > outside_distance_m
