class_name LaunchSequencer
extends RefCounted
## Séquence de tir d'un missile, sans interface (la commande de tir de la tablette, LaunchControl, et le banc de
## mesure l'appellent) : le point visé et la puissance sont figés au tir ; le missile du tube sort par l'animation de
## lancement (Station.launch_missile) ; à la fin de l'animation (Station.missile_released), il vole vers le point visé
## (MissileFlight, ajouté à la scène courante) et l'explosion a lieu à son arrivée (NukeLauncher.launch_at).
## Durée du vol (temps de jeu) : proportionnelle à la distance de la cible, de flight_time_range.x quand on vise le
## nadir (distance = altitude) à flight_time_range.y quand on vise l'horizon (√((R + h)² − R²), ~2 290 km à 400 km).
## Rien ne se passe sans tube, sans point visé ou si le tube ne peut pas tirer ; 48 missiles en tout, un par tube :
## un tube vide ne se recharge pas. Une seule séquence par station : un second abonné à missile_released
## libérerait le missile.

## Tir accepté : tube (silo, tube) et shot ({latitude, longitude, local, yield_kt, flight_time, fired_at, handoff},
## puis flight une fois le missile en vol).
signal fired(key: Vector2i, shot: Dictionary)

## Durée du vol (s, temps de jeu) : visée au nadir, visée à l'horizon (règle de jeu : plus rapide que la réalité, où
## une frappe depuis l'orbite prend plusieurs minutes, pour garder la tension d'une attente de torpille).
var flight_time_range := Vector2(20.0, 120.0)

var _station: Station
var _launcher: NukeLauncher
var _root: Viewport
var _flights_parent: Node
## Vector2i(silo, tube) -> shot : missiles lancés, en attente de leur sortie de la station.
var _pending := {}


## station : la station qui lance ; launcher : le lanceur (null : les missiles ne partent pas) ; root : fenêtre de la
## vue principale (caméra, pour la durée du vol) ; flights_parent : nœud qui reçoit les vols.
func _init(station: Station, launcher: NukeLauncher, root: Viewport, flights_parent: Node) -> void:
	_station = station
	_launcher = launcher
	_root = root
	_flights_parent = flights_parent
	_station.missile_released.connect(_on_missile_released)


## Tire le missile du tube key sur le point aim ({local, latitude, longitude}, cf. NukeLauncher.get_aim et aim_at)
## avec la puissance yield_kt. Rend le shot (voir fired), ou {} (et rien ne se passe) sans tube, sans point visé, ou
## si le tube ne peut pas tirer.
func fire_tube(key: Vector2i, aim: Dictionary, yield_kt: float) -> Dictionary:
	if key == SiloPanel.NONE or aim.is_empty() or _launcher == null or _station == null:
		return {}
	if not _station.launch_missile(key.x, key.y):
		return {}
	var flight_time := _flight_time(_launcher.get_earth().global_transform * (aim.local as Vector3))
	var shot := {"latitude": aim.latitude, "longitude": aim.longitude, "local": aim.local, "yield_kt": yield_kt,
			"flight_time": flight_time, "fired_at": Time.get_ticks_msec() / 1000.0,
			"handoff": _station.launch_handoff_s()}
	_pending[key] = shot
	fired.emit(key, shot)
	return shot


## Missile du tube key lancé mais pas encore sorti de la station (sa trappe doit rester ouverte).
func is_pending(key: Vector2i) -> bool:
	return _pending.has(key)


## Temps restant avant l'impact d'un tir (s) : animation de sortie (temps réel) puis vol (temps de jeu,
## MissileFlight.time_left) ; 0 une fois arrivé.
func time_left(shot: Dictionary) -> float:
	if shot.has("flight"):
		# Vol terminé : le nœud est libéré (tester avant toute affectation typée).
		if not is_instance_valid(shot.flight):
			return 0.0
		return (shot.flight as MissileFlight).time_left()
	return maxf(float(shot.handoff) - (Time.get_ticks_msec() / 1000.0 - float(shot.fired_at)), 0.0) \
			+ float(shot.flight_time)


## Durée du vol (s, temps de jeu) vers un point de la scène, proportionnelle à sa distance (du nadir à l'horizon).
func _flight_time(target_scene: Vector3) -> float:
	var camera := _root.get_camera_3d()
	var orbit := NukeClock.orbit
	if camera == null or orbit == null:
		return flight_time_range.x
	var distance_km := camera.global_position.distance_to(target_scene) / OrbitSimulation.SCENE_UNITS_PER_KM
	var altitude := orbit.altitude_km
	var radius := OrbitSimulation.EARTH_RADIUS_KM
	var horizon := sqrt((radius + altitude) * (radius + altitude) - radius * radius)
	var share := clampf(inverse_lerp(altitude, horizon, distance_km), 0.0, 1.0)
	return lerpf(flight_time_range.x, flight_time_range.y, share)


func _on_missile_released(silo: int, tube: int, missile: Node3D, velocity: Vector3) -> void:
	var key := Vector2i(silo, tube)
	# Le missile a quitté le tube : gyrophare éteint, trappe refermée (station furtive).
	_station.set_silo_beacon(silo, tube, false)
	_station.close_silo_door(silo, tube)
	if not _pending.has(key) or _launcher == null:
		missile.queue_free()
		return
	var shot: Dictionary = _pending[key]
	_pending.erase(key)
	var flight := MissileFlight.new()
	flight.name = "MissileFlight_%d_%02d" % [silo, tube]
	flight.flight_time_s = shot.flight_time
	shot.flight = flight
	_flights_parent.add_child(flight)
	flight.setup(missile, velocity, _station, _launcher.get_earth(), shot.local, NukeScaling.DEFAULT_BURST_HEIGHT_KM)
	flight.arrived.connect(func() -> void: _launcher.launch_at(shot.latitude, shot.longitude, shot.yield_kt))
