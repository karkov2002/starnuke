class_name NukeLauncher
extends Node
## Tir d'un missile sur le point de la Terre visé par l'observateur (centre de la vue), ou sur des coordonnées.
##
## La visée est un rayon partant de la caméra par le centre de l'écran, intersecté avec la sphère terrestre
## (rayon réel × SCENE_UNITS_PER_KM). S'il manque la Terre (ciel, limbe), il ne se passe rien. Le point touché est
## exprimé dans le repère local du nœud Earth (qui tourne avec la planète, cf. scripts/orbit.gd) et en lat/lon.
## Chaque tir crée une NukeEffect (nuke/nuke_effect.tscn), enfant de Earth. Le lanceur crée aussi les nœuds qui
## traitent les explosions en cours : effets globaux (FlashFX, CloudFX, GroundFX) et bilan (Impact, calculé
## hors du fil principal : un tir ne coûte que la création de la scène).

## Émis à chaque tir réussi.
signal detonated(effect: NukeEffect)
## Liste des explosions changée (tir, effacement) : les effets globaux reconstruisent leurs tableaux.
signal effects_changed

const GROUP := &"nuke_launcher"
const YIELDS_KT: Array[float] = [10.0, 100.0, 500.0, 1000.0, 10000.0, 50000.0]
const EFFECT_SCENE := preload("res://nuke/nuke_effect.tscn")

@export var earth_path: NodePath = ^"../Earth"
## Orbite dont l'horloge des explosions (NukeClock) suit l'accélération du temps.
@export var orbit_path: NodePath = ^"../Orbit"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
@export var station_path: NodePath = ^"../Station"

var _earth: Node3D
## Explosions de la partie (enfants de Earth), dans l'ordre des tirs ; une explosion en sort quand elle quitte l'arbre.
var _effects: Array[NukeEffect] = []
## Tâche de préchargement des cartes de vent, attendue à la sortie (rien ne doit tourner pendant la destruction).
var _preload_task := -1


func _exit_tree() -> void:
	if _preload_task != -1:
		WorkerThreadPool.wait_for_task_completion(_preload_task)
		_preload_task = -1


func _ready() -> void:
	add_to_group(GROUP)
	_earth = get_node(earth_path)
	# Données chargées en tâche de fond dès le démarrage (~0,5 s pour les pays, ~15 ms pour les cartes de vent) : pas
	# d'à-coup au premier tir (load() attend la fin du chargement s'il n'est pas terminé).
	for path in [OceanMask.PATH, CountryMask.PATH, PowerPlants.PATH]:
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)
	_preload_task = WorkerThreadPool.add_task(NukeWind.preload_maps)
	NukeClock.orbit = get_node_or_null(orbit_path) as OrbitSimulation
	var flash_fx := NukeFlashFX.new()
	flash_fx.name = "FlashFX"
	add_child(flash_fx)
	flash_fx.setup(self, get_node_or_null(world_environment_path) as WorldEnvironment, _earth,
			get_node_or_null(station_path) as Node3D)
	var cloud_fx := NukeCloudFX.new()
	cloud_fx.name = "CloudFX"
	add_child(cloud_fx)
	cloud_fx.setup(self, _earth)
	var ground_fx := NukeGroundFX.new()
	ground_fx.name = "GroundFX"
	add_child(ground_fx)
	ground_fx.setup(self, _earth)
	var impact := NukeImpact.new()
	impact.name = "Impact"
	add_child(impact)
	impact.setup(self)


## Nœud de la Terre (repère des explosions et du point visé).
func get_earth() -> Node3D:
	return _earth


## Point visé par le centre de la vue : {local (repère de Earth), latitude, longitude} en degrés, ou {} si le
## rayon manque la Terre.
func get_aim() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _earth == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	var oc := origin - _earth.global_position
	var b := oc.dot(direction)
	var discriminant := b * b - (oc.length_squared() - radius * radius)
	if discriminant < 0.0:
		return {}
	var t := -b - sqrt(discriminant)
	if t <= 0.0:
		return {}
	var local := _earth.global_transform.affine_inverse() * (origin + direction * t)
	# Repère du maillage (SphereMesh : +Y = nord, +Z = longitude −180°) vers ECEF, cf. Orbit.mesh_to_ecef.
	var lat_lon := OrbitSimulation.ecef_to_lat_lon(Vector3(-local.z, -local.x, local.y))
	return {"local": local, "latitude": lat_lon.x, "longitude": lat_lon.y}


## Point de coordonnées données (degrés), dans la même forme que get_aim : {local (repère de Earth), latitude,
## longitude}.
func aim_at(latitude_deg: float, longitude_deg: float) -> Dictionary:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	# ECEF vers le repère du maillage (SphereMesh : +Y nord, +Z vers −180°), cf. NukeEffect.place.
	var up := Vector3(-cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
	return {"local": up * OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM,
			"latitude": latitude_deg, "longitude": longitude_deg}


## Tire sur le point visé. Retourne null (et ne fait rien) si la vue ne vise pas la Terre.
func launch(yield_kt: float) -> NukeEffect:
	var aim := get_aim()
	if aim.is_empty():
		return null
	return launch_at(aim.latitude, aim.longitude, yield_kt)


## Tire sur des coordonnées données (degrés). Le vent est le vent réel GFS du point (NukeWind) : celui de la couche
## nuageuse (trou dans les nuages) et le profil vertical (dérive du champignon).
func launch_at(latitude_deg: float, longitude_deg: float, yield_kt: float) -> NukeEffect:
	var params := NukeParams.new()
	params.yield_kt = clampf(yield_kt, NukeScaling.MIN_YIELD_KT, NukeScaling.MAX_YIELD_KT)
	params.latitude_deg = latitude_deg
	params.longitude_deg = longitude_deg
	params.start_time_s = NukeClock.time_s
	if NukeClock.orbit:
		params.detonation_utc_s = NukeClock.orbit.get_utc_unix_s()
	_fill_place(params)
	return fire(params)


## Recrée une explosion passée (chargement d'une sauvegarde) : même point et même puissance, âgée de clock_age_s sur
## l'horloge des explosions (incendies, traces au sol, black-out où ils en étaient) ; marquée restored (pas un nouveau
## tir : ni objectif de mission, ni édition spéciale de la télévision).
func restore_at(latitude_deg: float, longitude_deg: float, yield_kt: float, clock_age_s: float,
		utc_unix_s: float) -> NukeEffect:
	var params := NukeParams.new()
	params.yield_kt = clampf(yield_kt, NukeScaling.MIN_YIELD_KT, NukeScaling.MAX_YIELD_KT)
	params.latitude_deg = latitude_deg
	params.longitude_deg = longitude_deg
	params.start_time_s = NukeClock.time_s - maxf(clock_age_s, 0.0)
	params.detonation_utc_s = utc_unix_s
	params.restored = true
	_fill_place(params)
	return fire(params)


## Vent réel GFS, mer ou terre, pays du point d'impact.
func _fill_place(params: NukeParams) -> void:
	var latitude_deg := params.latitude_deg
	var longitude_deg := params.longitude_deg
	var wind := NukeWind.sample(latitude_deg, longitude_deg)
	if wind != Vector2.ZERO:
		params.wind_direction_deg = NukeWind.from_direction_deg(wind)
		params.wind_speed_m_s = wind.length()
	params.wind_profile = NukeWind.sample_profile(latitude_deg, longitude_deg)
	params.over_ocean = OceanMask.is_ocean(latitude_deg, longitude_deg)
	params.country_code = CountryMask.country_at(latitude_deg, longitude_deg).get("code", "")


## Crée l'explosion décrite par params. Son bilan (pertes, réseau électrique, retombées) est calculé par le nœud
## Impact, à l'écoute de detonated.
func fire(params: NukeParams) -> NukeEffect:
	var effect := EFFECT_SCENE.instantiate() as NukeEffect
	effect.params = params
	_earth.add_child(effect)
	_effects.append(effect)
	effect.tree_exited.connect(func() -> void:
		_effects.erase(effect)
		effects_changed.emit())
	effects_changed.emit()
	detonated.emit(effect)
	return effect


## Explosions de la partie (enfants de Earth), qui restent en place jusqu'à la fin : leurs effets au sol persistent.
## Liste tenue à jour (effects_changed), à lire sans la modifier.
func get_effects() -> Array[NukeEffect]:
	return _effects


func clear_effects() -> void:
	for effect in _effects.duplicate():
		effect.queue_free()
