class_name OrbitSimulation
extends Node
## Mécanique orbitale de la station : orbite circulaire képlérienne autour d'une Terre en rotation.
##
## Repères (km) :
## - ECI (inertiel, équatorial) : x vers le point vernal, z vers le pôle nord céleste. L'orbite, le soleil
##   et les étoiles y sont fixes.
## - ECEF (lié à la Terre) : x vers la longitude 0°, y vers 90° E, z vers le pôle nord. ECEF = Rz(-θ)·ECI,
##   θ = angle sidéral de Greenwich = θ₀ + vitesse de rotation sidérale × temps (θ₀ déduit de l'heure solaire
##   locale de départ et de la position du soleil le jour day_of_year).
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
## Heure solaire locale au point de départ (règle la position du soleil).
@export_range(0.0, 24.0, 0.1) var start_local_solar_hour := 10.5
## Jour de l'année (position du soleil sur l'écliptique) ; juillet, comme les textures Blue Marble.
@export_range(1, 365) var day_of_year := 196

@export_group("Nœuds")
@export var earth_path: NodePath = ^"../Earth"
@export var station_path: NodePath = ^"../Station"
@export var observer_path: NodePath = ^"../Camera"
@export var sun_light_path: NodePath = ^"../Sun"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

## Temps simulé écoulé depuis le démarrage (s).
var sim_time_s := 0.0

var _raan := 0.0 # Ω (rad)
var _arg_lat_epoch := 0.0 # u à sim_time_s = 0 (rad)
var _sun_eci := Vector3.UP
var _gmst_epoch := 0.0 # θ₀ (rad)
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
	_init_sun()
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
## par défaut), à l'heure solaire locale donnée : 12 = midi, 0 = minuit. L'altitude est conservée ; l'inclinaison
## est relevée si nécessaire pour atteindre la latitude de départ.
func restart(local_solar_hour: float) -> void:
	sim_time_s = 0.0
	start_local_solar_hour = local_solar_hour
	_init_sun()
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
	var along := r.dot(_sun_eci)
	if along >= 0.0:
		return 1.0
	var distance_to_axis := (r - _sun_eci * along).length()
	return smoothstep(EARTH_RADIUS_KM, EARTH_RADIUS_KM + 60.0, distance_to_axis)


## Station en phase montante (se dirige vers le nord) ?
func is_ascending(time_s := sim_time_s) -> bool:
	return cos(get_argument_of_latitude(time_s)) >= 0.0


## Angle sidéral de Greenwich θ (rad) : rotation de la Terre par rapport au repère inertiel.
func get_sidereal_angle(time_s: float) -> float:
	return _gmst_epoch + EARTH_ROTATION_RAD_S * time_s


func eci_to_ecef(v: Vector3, time_s: float) -> Vector3:
	var theta := get_sidereal_angle(time_s)
	return Vector3(v.x * cos(theta) + v.y * sin(theta), -v.x * sin(theta) + v.y * cos(theta), v.z)


static func ecef_to_lat_lon(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(n.z)), rad_to_deg(atan2(n.y, n.x)))

#endregion

#region Interne

func _init_sun() -> void:
	# Position du soleil dans le repère équatorial : longitude écliptique ≈ 0 à l'équinoxe de printemps
	# (jour ~80), obliquité 23,44°.
	var ecliptic_lon := TAU * (day_of_year - 80.0) / 365.25
	var obliquity := deg_to_rad(23.44)
	var right_ascension := atan2(cos(obliquity) * sin(ecliptic_lon), cos(ecliptic_lon))
	var declination := asin(sin(obliquity) * sin(ecliptic_lon))
	_sun_eci = Vector3(cos(declination) * cos(right_ascension), cos(declination) * sin(right_ascension), sin(declination))
	# Longitude sub-solaire au départ d'après l'heure solaire locale ; elle vaut aussi α_soleil − θ₀.
	var subsolar_lon := deg_to_rad(start_longitude_deg - (start_local_solar_hour - 12.0) * 15.0)
	_gmst_epoch = right_ascension - subsolar_lon


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

	var sun_w := (ecef_to_world * eci_to_ecef(_sun_eci, sim_time_s)).normalized()
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

	for child in _earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			(geometry.material_override as ShaderMaterial).set_shader_parameter("sun_direction", sun_w)

#endregion
