class_name OrbitSimulation
extends Node
## Mécanique orbitale de la station : orbite circulaire képlérienne autour d'une Terre en rotation.
##
## Repères (km) :
## - ECI (inertiel, équatorial) : x vers le point vernal, z vers le pôle nord céleste. L'orbite et les étoiles y
##   sont fixes ; le soleil s'y déplace d'environ 1° par jour.
## - ECEF (lié à la Terre) : x vers la longitude 0°, y vers 90° E, z vers le pôle nord. ECEF = Rz(-θ)·ECI,
##   θ = angle sidéral de Greenwich (angle de rotation de la Terre, calculé à partir de la date UTC).
## Horloge : date et heure UTC réelles (epoch_unix_s + sim_time_s). Le soleil (position astronomique du jour),
## la rotation de la Terre, les étoiles et l'advection des nuages par le vent en dépendent.
## Position de la station sur l'orbite (a = rayon terrestre + altitude, i = inclinaison, Ω = ascension droite
## du nœud ascendant, u = argument de latitude, qui croît de n = sqrt(μ/a³) rad/s) :
##   r_ECI = a·(cosΩ·cos u − sinΩ·sin u·cos i,  sinΩ·cos u + cosΩ·sin u·cos i,  sin u·sin i)
##
## Rendu : la station et la caméra sont fixes dans la scène ; c'est la Terre (et le soleil) qu'on place autour
## d'elles. Le repère local de la station (zénith = +Y local, direction de vol = −Z local du nœud Station) est
## aligné sur le repère orbital local (zénith = r̂, direction de vol = v̂), puis on en déduit l'orientation de la
## Terre, la direction du soleil et l'orientation du ciel étoilé dans la scène.

signal orbit_changed

const MU_KM3_S2 := 398600.4418
const EARTH_RADIUS_KM := 6371.0
const EARTH_ROTATION_RAD_S := 7.2921159e-5 # rotation sidérale
const SCENE_UNITS_PER_KM := 0.1
const MIN_ALTITUDE_KM := 200.0
const MAX_ALTITUDE_KM := 800.0
## Au-delà, la fenêtre de tuiles HD (en longitude/latitude) se déforme trop près des pôles.
const MAX_INCLINATION_DEG := 70.0

@export_group("Orbite")
@export_range(200.0, 800.0, 1.0, "suffix:km") var altitude_km := 400.0:
	set = set_altitude_km
@export_range(0.0, 70.0, 0.1, "suffix:°") var inclination_deg := 51.6:
	set = set_inclination_deg
## Facteur d'accélération du temps (1 = temps réel).
@export var time_scale := 1.0

@export_group("Conditions initiales")
## Point survolé au démarrage (l'orbite est calculée pour y passer).
@export var start_latitude_deg := 43.0
@export var start_longitude_deg := 14.0
## Station en phase montante (vers le nord) au démarrage.
@export var start_ascending := true
## Date de départ (AAAA-MM-JJ). Le jeu se passe en 2035 ; juillet, comme les textures Blue Marble.
@export var start_date := "2035-07-15"
## Heure solaire locale (vraie) au point de départ : fixe l'heure UTC de départ.
@export_range(0.0, 24.0, 0.1) var start_local_solar_hour := 10.5

@export_group("Nœuds")
@export var earth_path: NodePath = ^"../Earth"
@export var station_path: NodePath = ^"../Station"
@export var observer_path: NodePath = ^"../Camera"
@export var sun_light_path: NodePath = ^"../Sun"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

## Temps simulé écoulé depuis le démarrage (s).
var sim_time_s := 0.0
## Instant UTC (secondes depuis le 1er janvier 1970) correspondant à sim_time_s = 0.
var epoch_unix_s := 0.0

var _raan := 0.0 # Ω (rad)
var _arg_lat_epoch := 0.0 # u à sim_time_s = 0 (rad)
var _earth: Node3D
var _station: Node3D
var _observer: Node3D
var _sun_light: DirectionalLight3D
var _sun_energy := 1.0
var _environment: Environment


func _ready() -> void:
	_earth = get_node(earth_path)
	_station = get_node(station_path)
	_observer = get_node(observer_path)
	_sun_light = get_node_or_null(sun_light_path)
	if _sun_light:
		_sun_energy = _sun_light.light_energy
	var world_env := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_env:
		_environment = world_env.environment
	var date_unix := float(Time.get_unix_time_from_datetime_string(start_date + "T00:00:00"))
	epoch_unix_s = _unix_at_local_solar_hour(date_unix, start_longitude_deg, start_local_solar_hour)
	pass_over(start_latitude_deg, start_longitude_deg, start_ascending)
	_update_scene()


func _process(delta: float) -> void:
	sim_time_s += delta * time_scale
	_update_scene()


#region Paramètres orbitaux

func set_altitude_km(value: float) -> void:
	var keep := _keep_ground_point()
	altitude_km = clampf(value, MIN_ALTITUDE_KM, MAX_ALTITUDE_KM)
	_restore_ground_point(keep)


## Change l'inclinaison au point courant. Elle ne peut pas être inférieure à la latitude actuelle de la station
## (une orbite d'inclinaison i ne dépasse jamais la latitude ±i) : la valeur est bornée en conséquence.
func set_inclination_deg(value: float) -> void:
	var keep := _keep_ground_point()
	var min_inclination := 0.0
	if not keep.is_empty():
		min_inclination = absf((keep[0] as Vector2).x)
	inclination_deg = clampf(maxf(value, min_inclination), 0.0, MAX_INCLINATION_DEG)
	_restore_ground_point(keep)


## Redémarre la simulation (temps remis à zéro) au-dessus du point de départ (start_latitude/longitude, l'Europe
## par défaut), le même jour (date locale du point de départ), à l'heure solaire locale donnée : 12 = midi,
## 0 = minuit. L'altitude est conservée ; l'inclinaison est relevée si nécessaire pour atteindre la latitude de
## départ.
func restart(local_solar_hour: float) -> void:
	var lon_s := start_longitude_deg * 240.0 # décalage de l'heure solaire moyenne locale (s)
	var local_day := floorf((get_utc_unix_s() + lon_s) / 86400.0) * 86400.0
	epoch_unix_s = _unix_at_local_solar_hour(local_day, start_longitude_deg, local_solar_hour)
	sim_time_s = 0.0
	if inclination_deg < absf(start_latitude_deg):
		inclination_deg = absf(start_latitude_deg)
	pass_over(start_latitude_deg, start_longitude_deg, start_ascending)
	_update_scene()


## Recalcule Ω et la phase pour que la station soit, maintenant, à la verticale de (lat, lon), en phase
## montante ou descendante. Nécessite |lat| ≤ inclinaison (sinon la latitude est ramenée à ±inclinaison).
func pass_over(latitude_deg: float, longitude_deg: float, ascending: bool) -> void:
	var i := deg_to_rad(inclination_deg)
	var lat := deg_to_rad(latitude_deg)
	var max_lat := absf(i)
	if absf(lat) > max_lat:
		push_warning("orbit : latitude %.1f° inaccessible avec une inclinaison de %.1f°" % [latitude_deg, inclination_deg])
		lat = clampf(lat, -max_lat, max_lat)
	var u: float
	if sin(i) < 1e-6:
		u = 0.0 # orbite équatoriale : seule la longitude compte
	else:
		u = asin(clampf(sin(lat) / sin(i), -1.0, 1.0))
		if not ascending:
			u = PI - u
	# Longitude (inertielle) du point de l'orbite par rapport au nœud ascendant.
	var node_offset := atan2(cos(i) * sin(u), cos(u))
	var theta := get_sidereal_angle(sim_time_s)
	_raan = wrapf(deg_to_rad(longitude_deg) + theta - node_offset, -PI, PI)
	_arg_lat_epoch = u - get_mean_motion() * sim_time_s
	orbit_changed.emit()

## Change la date et l'heure (instant UTC en secondes Unix) sans déplacer la station : elle reste au-dessus du même
## point, dans le même sens de passage (l'orbite est recalculée). Le soleil, les étoiles et les nuages, eux, se
## placent selon la nouvelle heure.
func set_utc_unix_s(unix_s: float) -> void:
	var keep := _keep_ground_point()
	epoch_unix_s = unix_s - sim_time_s
	_restore_ground_point(keep)

#endregion

#region Date et heure

## Instant UTC (secondes depuis le 1er janvier 1970) au temps simulé time_s.
func get_utc_unix_s(time_s := sim_time_s) -> float:
	return epoch_unix_s + time_s


## Date et heure UTC (clés year, month, day, hour, minute, second de Time.get_datetime_dict_from_unix_time).
func get_utc_datetime(time_s := sim_time_s) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(floorf(get_utc_unix_s(time_s))))


## Heure solaire locale vraie (0–24 h) à une longitude donnée : angle horaire du soleil + 12 h.
func get_local_solar_hour(longitude_deg: float, time_s := sim_time_s) -> float:
	return _local_solar_hour_at_unix(get_utc_unix_s(time_s), longitude_deg)


## Date julienne d'un instant UTC (le temps universel UT1 est assimilé à UTC).
static func julian_date(unix_s: float) -> float:
	return unix_s / 86400.0 + 2440587.5

#endregion

#region Grandeurs dérivées (API pour le gameplay)

## Rayon de l'orbite (km).
func get_semi_major_axis_km() -> float:
	return EARTH_RADIUS_KM + altitude_km


## Vitesse angulaire orbitale n (rad/s).
func get_mean_motion() -> float:
	var a := get_semi_major_axis_km()
	return sqrt(MU_KM3_S2 / (a * a * a))


## Période orbitale (s) : 92,4 min à 400 km, 88,4 min à 200 km, 100,7 min à 800 km.
func get_period_s() -> float:
	return TAU / get_mean_motion()


## Vitesse orbitale (km/s).
func get_orbital_speed_km_s() -> float:
	return get_semi_major_axis_km() * get_mean_motion()


func get_raan_deg() -> float:
	return rad_to_deg(_raan)


func get_argument_of_latitude(time_s: float) -> float:
	return _arg_lat_epoch + get_mean_motion() * time_s


func get_position_eci(time_s: float) -> Vector3:
	var u := get_argument_of_latitude(time_s)
	var i := deg_to_rad(inclination_deg)
	return get_semi_major_axis_km() * Vector3(
		cos(_raan) * cos(u) - sin(_raan) * sin(u) * cos(i),
		sin(_raan) * cos(u) + cos(_raan) * sin(u) * cos(i),
		sin(u) * sin(i))


## Direction de la vitesse inertielle (unitaire).
func get_velocity_direction_eci(time_s: float) -> Vector3:
	var u := get_argument_of_latitude(time_s)
	var i := deg_to_rad(inclination_deg)
	return Vector3(
		-cos(_raan) * sin(u) - sin(_raan) * cos(u) * cos(i),
		-sin(_raan) * sin(u) + cos(_raan) * cos(u) * cos(i),
		cos(u) * sin(i))


func get_position_ecef(time_s: float) -> Vector3:
	return eci_to_ecef(get_position_eci(time_s), time_s)


## Point survolé (latitude, longitude) en degrés.
func get_subsatellite_point(time_s := sim_time_s) -> Vector2:
	return ecef_to_lat_lon(get_position_ecef(time_s))


## Trace au sol sur une durée donnée (points lat/lon en degrés).
func predict_ground_track(duration_s: float, step_s := 30.0) -> PackedVector2Array:
	var track := PackedVector2Array()
	var t := sim_time_s
	while t <= sim_time_s + duration_s:
		track.append(get_subsatellite_point(t))
		t += step_s
	return track


## Fraction du soleil visible depuis la station (0 = éclipse par la Terre, 1 = plein soleil). Ombre
## cylindrique de la Terre, adoucie sur l'épaisseur de l'atmosphère (lever / coucher de soleil orbital).
func get_sunlight_fraction(time_s := sim_time_s) -> float:
	var r := get_position_eci(time_s)
	var sun := get_sun_direction_eci(time_s)
	var along := r.dot(sun)
	if along >= 0.0:
		return 1.0
	var distance_to_axis := (r - sun * along).length()
	return smoothstep(EARTH_RADIUS_KM, EARTH_RADIUS_KM + 60.0, distance_to_axis)


## Station en phase montante (se dirige vers le nord) ?
func is_ascending(time_s := sim_time_s) -> bool:
	return cos(get_argument_of_latitude(time_s)) >= 0.0


## Angle sidéral de Greenwich θ (rad) : rotation de la Terre par rapport au repère inertiel.
func get_sidereal_angle(time_s: float) -> float:
	return _sidereal_angle_at_unix(get_utc_unix_s(time_s))


## Direction du soleil dans le repère inertiel (unitaire).
func get_sun_direction_eci(time_s := sim_time_s) -> Vector3:
	return _sun_direction_at_unix(get_utc_unix_s(time_s))


func eci_to_ecef(v: Vector3, time_s: float) -> Vector3:
	var theta := get_sidereal_angle(time_s)
	return Vector3(v.x * cos(theta) + v.y * sin(theta), -v.x * sin(theta) + v.y * cos(theta), v.z)


static func ecef_to_lat_lon(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(n.z)), rad_to_deg(atan2(n.y, n.x)))

#endregion

#region Interne

# Angle de rotation de la Terre (IAU 2000) : θ = 2π·(0,7790572732640 + 1,00273781191135448·(JD − 2451545)).
static func _sidereal_angle_at_unix(unix_s: float) -> float:
	var days := julian_date(unix_s) - 2451545.0
	return TAU * fposmod(0.7790572732640 + 1.00273781191135448 * days, 1.0)


# Position du soleil (formules de l'Astronomical Almanac, précision ~0,01°) : longitude moyenne, anomalie moyenne,
# longitude écliptique, puis passage au repère équatorial par l'obliquité.
static func _sun_direction_at_unix(unix_s: float) -> Vector3:
	var days := julian_date(unix_s) - 2451545.0
	var mean_lon := deg_to_rad(280.460 + 0.9856474 * days)
	var anomaly := deg_to_rad(357.528 + 0.9856003 * days)
	var ecliptic_lon := mean_lon + deg_to_rad(1.915) * sin(anomaly) + deg_to_rad(0.020) * sin(2.0 * anomaly)
	var obliquity := deg_to_rad(23.439 - 0.0000004 * days)
	return Vector3(cos(ecliptic_lon), cos(obliquity) * sin(ecliptic_lon), sin(obliquity) * sin(ecliptic_lon))


static func _local_solar_hour_at_unix(unix_s: float, longitude_deg: float) -> float:
	var sun := _sun_direction_at_unix(unix_s)
	var hour_angle := _sidereal_angle_at_unix(unix_s) + deg_to_rad(longitude_deg) - atan2(sun.y, sun.x)
	return fposmod(12.0 + rad_to_deg(hour_angle) / 15.0, 24.0)


# Instant UTC où l'heure solaire vraie vaut `hour` à la longitude donnée, pendant la date locale `local_date_unix`
# (exprimée comme l'instant de minuit UTC de cette date). L'équation du temps (±16 min) est corrigée par itérations.
static func _unix_at_local_solar_hour(local_date_unix: float, longitude_deg: float, hour: float) -> float:
	var t := local_date_unix - longitude_deg * 240.0 + hour * 3600.0
	for i in 3:
		var error := fposmod(hour - _local_solar_hour_at_unix(t, longitude_deg) + 12.0, 24.0) - 12.0
		t += error * 3600.0
	return t


func _keep_ground_point() -> Array:
	if not is_node_ready():
		return []
	return [get_subsatellite_point(), is_ascending()]


func _restore_ground_point(keep: Array) -> void:
	if keep.is_empty():
		return
	var point: Vector2 = keep[0]
	pass_over(point.x, point.y, keep[1])


func _update_scene() -> void:
	var up := get_position_ecef(sim_time_s).normalized()
	var along := eci_to_ecef(get_velocity_direction_eci(sim_time_s), sim_time_s)
	along = (along - up * up.dot(along)).normalized()
	var ecef_frame := Basis(up, along, up.cross(along))

	var zenith_w := _station.global_basis.y.normalized()
	var forward_w := -_station.global_basis.z.normalized()
	forward_w = (forward_w - zenith_w * zenith_w.dot(forward_w)).normalized()
	var world_frame := Basis(zenith_w, forward_w, zenith_w.cross(forward_w))
	var ecef_to_world := world_frame * ecef_frame.transposed()

	# Repère du maillage de la Terre (SphereMesh : +Y = nord, u = 0 vers +Z = longitude −180°) vers ECEF.
	var mesh_to_ecef := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
	_earth.global_basis = ecef_to_world * mesh_to_ecef
	_earth.global_position = _observer.global_position - zenith_w * get_semi_major_axis_km() * SCENE_UNITS_PER_KM

	var sun_w := (ecef_to_world * eci_to_ecef(get_sun_direction_eci(), sim_time_s)).normalized()
	if _sun_light:
		var hint := Vector3.UP if absf(sun_w.y) < 0.99 else Vector3.FORWARD
		_sun_light.global_basis = Basis.looking_at(-sun_w, hint)
		_sun_light.light_energy = _sun_energy * get_sunlight_fraction()
	# Ciel étoilé : la carte NASA est en coordonnées équatoriales (ascension droite 0h au centre, croissante
	# vers la gauche, +90° en haut). Le panorama Godot lit la direction locale d avec u = atan2(d.x, −d.z)/2π,
	# v = acos(d.y)/π, d'où d = (y_ECI, z_ECI, x_ECI). sky_rotation = rotation ciel → monde.
	if _environment:
		var sky_to_eci := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		var theta := get_sidereal_angle(sim_time_s)
		var eci_to_ecef_basis := Basis(Vector3(cos(theta), -sin(theta), 0), Vector3(sin(theta), cos(theta), 0), Vector3(0, 0, 1))
		var sky_to_world := (ecef_to_world * eci_to_ecef_basis * sky_to_eci).orthonormalized()
		_environment.sky_rotation = sky_to_world.get_euler()
		# Disque solaire du shader de ciel : soleil et observateur exprimés dans le repère du ciel.
		var sky_material: ShaderMaterial = null
		if _environment.sky:
			sky_material = _environment.sky.sky_material as ShaderMaterial
		if sky_material:
			var world_to_sky := sky_to_world.transposed()
			var observer_km := (_observer.global_position - _earth.global_position) / SCENE_UNITS_PER_KM
			sky_material.set_shader_parameter("sun_direction", world_to_sky * sun_w)
			sky_material.set_shader_parameter("observer_km", world_to_sky * observer_km)

	# Heure UTC du jour pour l'advection des nuages par le vent (surface et couche nuageuse).
	var utc_day_s := fposmod(get_utc_unix_s(), 86400.0)
	for child in _earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			var material := geometry.material_override as ShaderMaterial
			material.set_shader_parameter("sun_direction", sun_w)
			material.set_shader_parameter("cloud_utc_day_s", utc_day_s)

#endregion
