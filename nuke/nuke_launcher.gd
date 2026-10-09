class_name NukeLauncher
extends Node
## Tir d'un missile sur le point de la Terre visé par l'observateur (centre de la vue), ou sur des coordonnées.
##
## La visée est un rayon partant de la caméra par le centre de l'écran, intersecté avec la sphère terrestre
## (rayon réel × SCENE_UNITS_PER_KM). S'il manque la Terre (ciel, limbe), il ne se passe rien. Le point touché est
## exprimé dans le repère local du nœud Earth (qui tourne avec la planète, cf. scripts/orbit.gd) et en lat/lon.
## Chaque tir crée une NukeEffect (nuke/nuke_effect.tscn), enfant de Earth.

## Émis à chaque tir réussi.
signal detonated(effect: NukeEffect)

const GROUP := &"nuke_launcher"
const YIELDS_KT: Array[float] = [10.0, 100.0, 500.0, 1000.0, 10000.0, 50000.0]
const EFFECT_SCENE := preload("res://nuke/nuke_effect.tscn")

@export var earth_path: NodePath = ^"../Earth"
## Orbite dont l'horloge des explosions (NukeClock) suit l'accélération du temps.
@export var orbit_path: NodePath = ^"../Orbit"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
@export var station_path: NodePath = ^"../Station"

var _earth: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	_earth = get_node(earth_path)
	NukeClock.orbit = get_node_or_null(orbit_path) as OrbitSimulation
	var flash_fx := NukeFlashFX.new()
	flash_fx.name = "FlashFX"
	add_child(flash_fx)
	flash_fx.setup(self, get_node_or_null(world_environment_path) as WorldEnvironment, _earth,
			get_node_or_null(station_path) as Node3D)
	var fire_fx := NukeFireFX.new()
	fire_fx.name = "FireFX"
	add_child(fire_fx)
	fire_fx.setup(self, _earth)
	var cloud_fx := NukeCloudFX.new()
	cloud_fx.name = "CloudFX"
	add_child(cloud_fx)
	cloud_fx.setup(self, _earth)


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
	var wind := NukeWind.sample(latitude_deg, longitude_deg)
	if wind != Vector2.ZERO:
		params.wind_direction_deg = NukeWind.from_direction_deg(wind)
		params.wind_speed_m_s = wind.length()
	params.wind_profile = NukeWind.sample_profile(latitude_deg, longitude_deg)
	return fire(params)


## Crée l'explosion décrite par params.
func fire(params: NukeParams) -> NukeEffect:
	var effect := EFFECT_SCENE.instantiate() as NukeEffect
	effect.params = params
	_earth.add_child(effect)
	print("NukeLauncher : %s sur %.2f°, %.2f° (vent du %03d°, %.1f m/s)" % [NukeScaling.format_yield(params.yield_kt),
			params.latitude_deg, params.longitude_deg, roundi(params.wind_direction_deg), params.wind_speed_m_s])
	if not params.wind_profile.is_empty():
		# Vent à l'altitude du chapeau stabilisé (~3/4 du sommet).
		var cap_km := 0.75 * NukeScaling.cloud_top_km(params.yield_kt)
		var cap_wind := params.wind_at(cap_km)
		print("  vent à %.0f km (chapeau) : du %03d°, %.1f m/s" % [cap_km, roundi(NukeWind.from_direction_deg(cap_wind)),
				cap_wind.length()])
	detonated.emit(effect)
	return effect


## Explosions en cours (enfants de Earth).
func get_effects() -> Array[NukeEffect]:
	var effects: Array[NukeEffect] = []
	for child in _earth.get_children():
		if child is NukeEffect:
			effects.append(child)
	return effects


func clear_effects() -> void:
	for effect in get_effects():
		effect.queue_free()
