class_name EarthSceneDriver
extends Node
## Pose de la scène d'après l'orbite (nœud EarthScene de scenes/orbit_view.tscn, juste après Orbit dans l'arbre :
## il s'exécute après lui à chaque image, et aussitôt à chaque orbit_changed). La station et la caméra sont fixes
## dans la scène ; c'est la Terre (et le soleil) qu'on place autour d'elles : le repère local de la station (zénith =
## +Y local, direction de vol = −Z local du nœud Station) est aligné sur le repère orbital local (zénith = r̂,
## direction de vol = v̂), d'où l'orientation de la Terre, la direction du soleil (lumière, énergie selon l'éclipse)
## et l'orientation du ciel étoilé, puis les uniforms des matériaux de la Terre (sun_direction, cloud_utc_day_s :
## heure UTC du jour pour l'advection des nuages) et du ciel (disque solaire). La rotation ECEF → scène est écrite
## dans Orbit.ecef_to_world (lue par Orbit.get_eci_to_world : orbites fixes dans le repère inertiel, GhostTrack).
## OrbitSimulation reste un modèle pur (mécanique, date, repères).

## Repère du maillage de la Terre (SphereMesh : +Y = nord, u = 0 vers +Z = longitude −180°) vers ECEF.
const MESH_TO_ECEF := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
## Ciel étoilé : la carte NASA est en coordonnées équatoriales (ascension droite 0h au centre, croissante vers la
## gauche, +90° en haut). Le panorama Godot lit la direction locale d avec u = atan2(d.x, −d.z)/2π, v = acos(d.y)/π,
## d'où d = (y_ECI, z_ECI, x_ECI).
const SKY_TO_ECI := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))

@export var orbit_path: NodePath = ^"../Orbit"
@export var earth_path: NodePath = ^"../Earth"
@export var station_path: NodePath = ^"../Station"
@export var observer_path: NodePath = ^"../Observer/Camera"
@export var sun_light_path: NodePath = ^"../Sun"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

var _orbit: OrbitSimulation
var _earth: Node3D
var _station: Node3D
var _observer: Node3D
var _sun_light: DirectionalLight3D
var _sun_energy := 1.0
var _environment: Environment
## Matériaux des enfants de la Terre (sol, nuages, atmosphère), tenus à jour quand ses enfants changent.
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_orbit = get_node(orbit_path)
	_earth = get_node(earth_path)
	_station = get_node(station_path)
	_observer = get_node(observer_path)
	_sun_light = get_node_or_null(sun_light_path)
	if _sun_light:
		_sun_energy = _sun_light.light_energy
	var world_env := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_env:
		_environment = world_env.environment
	_collect_materials()
	_earth.child_entered_tree.connect(func(_child: Node) -> void: _collect_materials())
	# L'enfant est encore dans l'arbre à child_exiting_tree : liste refaite une fois qu'il est parti.
	_earth.child_exiting_tree.connect(func(_child: Node) -> void: _collect_materials.call_deferred())
	_orbit.orbit_changed.connect(update)
	update()


func _process(_delta: float) -> void:
	update()


func _collect_materials() -> void:
	_materials.clear()
	for child in _earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			_materials.append(geometry.material_override as ShaderMaterial)


## Place la Terre, le soleil et le ciel d'après l'orbite à l'instant courant.
func update() -> void:
	var orbit := _orbit
	var t := orbit.sim_time_s
	var up := orbit.get_position_ecef(t).normalized()
	var along := orbit.eci_to_ecef(orbit.get_velocity_direction_eci(t), t)
	along = (along - up * up.dot(along)).normalized()
	var ecef_frame := Basis(up, along, up.cross(along))

	var zenith_w := _station.global_basis.y.normalized()
	var forward_w := -_station.global_basis.z.normalized()
	forward_w = (forward_w - zenith_w * zenith_w.dot(forward_w)).normalized()
	var world_frame := Basis(zenith_w, forward_w, zenith_w.cross(forward_w))
	var ecef_to_world := world_frame * ecef_frame.transposed()
	orbit.ecef_to_world = ecef_to_world

	_earth.global_basis = ecef_to_world * MESH_TO_ECEF
	_earth.global_position = _observer.global_position \
			- zenith_w * orbit.get_semi_major_axis_km() * OrbitSimulation.SCENE_UNITS_PER_KM

	var sun_w := (ecef_to_world * orbit.eci_to_ecef(orbit.get_sun_direction_eci(), t)).normalized()
	if _sun_light:
		var hint := Vector3.UP if absf(sun_w.y) < 0.99 else Vector3.FORWARD
		_sun_light.global_basis = Basis.looking_at(-sun_w, hint)
		_sun_light.light_energy = _sun_energy * orbit.get_sunlight_fraction()
	# sky_rotation = rotation ciel → monde.
	if _environment:
		var theta := orbit.get_sidereal_angle(t)
		var eci_to_ecef_basis := Basis(Vector3(cos(theta), -sin(theta), 0), Vector3(sin(theta), cos(theta), 0),
				Vector3(0, 0, 1))
		var sky_to_world := (ecef_to_world * eci_to_ecef_basis * SKY_TO_ECI).orthonormalized()
		_environment.sky_rotation = sky_to_world.get_euler()
		# Disque solaire du shader de ciel : soleil et observateur exprimés dans le repère du ciel.
		var sky_material: ShaderMaterial = null
		if _environment.sky:
			sky_material = _environment.sky.sky_material as ShaderMaterial
		if sky_material:
			var world_to_sky := sky_to_world.transposed()
			var observer_km := (_observer.global_position - _earth.global_position) / OrbitSimulation.SCENE_UNITS_PER_KM
			sky_material.set_shader_parameter("sun_direction", world_to_sky * sun_w)
			sky_material.set_shader_parameter("observer_km", world_to_sky * observer_km)

	# Heure UTC du jour pour l'advection des nuages par le vent (surface et couche nuageuse).
	var utc_day_s := fposmod(orbit.get_utc_unix_s(), 86400.0)
	for material in _materials:
		material.set_shader_parameter("sun_direction", sun_w)
		material.set_shader_parameter("cloud_utc_day_s", utc_day_s)
