class_name MissileFlight
extends Node3D
## Vol d'un missile après l'animation Blender (Station.missile_released) jusqu'au point d'impact.
##
## Trajectoire, en mètres réels, dans le repère de la station (fixe dans la scène ; c'est la Terre qui bouge) :
## - le missile poursuit d'abord la ligne droite de Blender (vitesse de sortie) en accélérant (dive_acceleration) ;
## - il s'incurve vers le point d'impact (500 m au-dessus de la cible, qui suit la Terre en mouvement) selon une loi
##   exponentielle g(u) = (e^(λu) − 1 − λu) / (e^λ − 1 − λ), u = temps de vol écoulé / durée (pente nulle au départ :
##   pas d'à-coup au relais) : il prend doucement ses distances avec la station, puis file vers la cible ; il y arrive
##   exactement à la fin du vol (arrived).
## Le temps de vol suit l'horloge du jeu (Orbit.time_scale : pause, accélération).
##
## Rendu à l'échelle préservant la perspective : la Terre est à 1/10 000 ; un objet K fois plus proche et K fois plus
## petit paraît identique depuis la caméra. Le missile, à une distance réelle d de la caméra, est dessiné à f(d) :
## - à taille réelle tant qu'il est plus près que le palier F (90 % de la distance de la couche nuageuse dans sa
##   direction) ;
## - au-delà, sur le palier F, réduit d'autant (F / d) : toujours devant les nuages et la Terre ;
## - enfin, quand d / 10 000 dépasse F (bas de l'atmosphère), à l'échelle exacte de la Terre : les nuages le masquent
##   comme il se doit.
## Sa propulsion le suit (panache en coordonnées locales, cf. MissileExhaust.enter_flight) ; un halo additif garde un
## point lumineux d'au moins min_glow_pixels jusqu'à l'impact ; la lumière du moteur sur la station décroît en 1/d².

signal arrived

## Mètres réels par unité de scène de la Terre (1 unité = 10 km).
const REAL_M_PER_UNIT := 1000.0 / OrbitSimulation.SCENE_UNITS_PER_KM

## Durée du vol (s, temps de jeu) : provisoire, en attendant une durée de vol réaliste.
var flight_time_s := 10.0
## Accélération le long de la ligne droite de Blender (m/s²) avant la courbe vers la cible.
var dive_acceleration := 30.0
## Raideur de la loi exponentielle (plus grand : le missile reste plus longtemps près de la station).
var curve_steepness := 9.0
## Rotation maximale du missile pour suivre sa trajectoire (rad/s).
var turn_rate := 1.2
## Halo : rayon réel (m), taille minimale à l'écran (pixels), distance réelle d'apparition (m).
var glow_radius_m := 2.5
var min_glow_pixels := 4.0
var glow_fade_in_m := Vector2(150.0, 1500.0)
## Distance réelle (m) jusqu'à laquelle la lumière du moteur éclaire la station à pleine intensité (puis en 1/d²).
var light_full_m := 40.0

var _missile: Node3D
var _exhaust: MissileExhaust
var _station: Node3D
var _earth: Node3D
var _cloud_radius := 0.0
## Point d'impact dans le repère du maillage de la Terre (unités de scène).
var _target_local := Vector3.ZERO
var _start_offset := Vector3.ZERO
var _start_velocity := Vector3.ZERO
var _dive_direction := Vector3.DOWN
var _elapsed := 0.0
var _attitude := Quaternion.IDENTITY
var _last_relative := Vector3.ZERO
var _glow: MeshInstance3D
var _glow_material: ShaderMaterial


## missile : nœud du missile (propulsion allumée), velocity : vitesse de sortie (monde, m/s) ; target_local : point
## visé sur le maillage de la Terre (NukeLauncher.get_aim().local) ; burst_height_km : altitude de l'explosion.
func setup(missile: Node3D, velocity: Vector3, station: Node3D, earth: Node3D, target_local: Vector3,
		burst_height_km: float) -> void:
	_missile = missile
	_station = station
	_earth = earth
	for node in missile.find_children("*", "Node3D", true, false):
		if node is MissileExhaust:
			_exhaust = node
			break
	var clouds := earth.get_node_or_null("CloudLayer") as MeshInstance3D
	_cloud_radius = (clouds.mesh as SphereMesh).radius if clouds and clouds.mesh is SphereMesh \
			else OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	_target_local = target_local.normalized() \
			* (OrbitSimulation.EARTH_RADIUS_KM + burst_height_km) * OrbitSimulation.SCENE_UNITS_PER_KM
	_start_offset = missile.global_position - station.global_position
	_start_velocity = velocity
	_dive_direction = velocity.normalized() if velocity.length() > 0.1 else -station.global_basis.y
	_attitude = missile.global_basis.orthonormalized().get_rotation_quaternion()
	_last_relative = _start_offset
	if _exhaust:
		_exhaust.enter_flight()
	_build_glow()


func _process(delta: float) -> void:
	if _missile == null or not is_instance_valid(_missile):
		queue_free()
		return
	var orbit := NukeClock.orbit
	var game_delta := delta * (orbit.time_scale if orbit else 1.0)
	_elapsed += game_delta
	var u := clampf(_elapsed / flight_time_s, 0.0, 1.0)
	var t := _elapsed
	var straight := _start_offset + _start_velocity * t + _dive_direction * (0.5 * dive_acceleration * t * t)
	var k := curve_steepness
	var g := (exp(k * u) - 1.0 - k * u) / (exp(k) - 1.0 - k)
	var relative := straight.lerp(_target_relative(), g)

	if game_delta > 0.0:
		var motion := relative - _last_relative
		if motion.length() > 1e-4:
			# Pointe (−Y du missile) dans le sens du déplacement.
			var wanted := Quaternion(Vector3.DOWN, motion.normalized())
			_attitude = _attitude.slerp(wanted, clampf(turn_rate * delta / maxf(_attitude.angle_to(wanted), 1e-4), 0.0, 1.0))
	_last_relative = relative
	_place(relative)
	if u >= 1.0:
		arrived.emit()
		_missile.queue_free()
		queue_free()


## Point d'impact, en mètres réels, par rapport à l'origine de la station (repère du monde).
func _target_relative() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else _station.global_position
	var target_scene := _earth.global_transform * _target_local
	return (target_scene - eye) * REAL_M_PER_UNIT + (eye - _station.global_position)


## Place le missile (position réelle relative à la station) à sa position de rendu, réduit d'autant.
func _place(relative: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var view := _station.global_position + relative - eye
	var distance := maxf(view.length(), 1e-3)
	var direction := view / distance
	var shown := maxf(minf(distance, _plateau(eye, direction)), distance / REAL_M_PER_UNIT)
	var shrink := shown / distance
	_missile.global_transform = Transform3D(Basis(_attitude).scaled(Vector3.ONE * shrink), eye + direction * shown)

	var nozzle := _exhaust.global_position if _exhaust else _missile.global_position
	if _exhaust:
		_exhaust.jet_direction = Basis(_attitude) * Vector3.UP
		_exhaust.light_scale = clampf(pow(light_full_m / distance, 2.0), 0.0, 1.0)
	# Halo : rayon réel réduit comme le missile, mais jamais moins de min_glow_pixels à l'écran.
	var shown_nozzle := maxf(eye.distance_to(nozzle), 1e-3)
	var pixel_angle := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var radius := maxf(glow_radius_m * shrink, min_glow_pixels * pixel_angle * shown_nozzle)
	_glow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), nozzle)
	# Apparition au-delà de la propulsion proche (déjà rendue par le panache), puis éclat qui baisse lentement.
	var fade_in := smoothstep(glow_fade_in_m.x, glow_fade_in_m.y, distance)
	var far := lerpf(1.0, 0.45, clampf(distance / 600000.0, 0.0, 1.0))
	_glow_material.set_shader_parameter("intensity", fade_in * far)


## Distance de rendu maximale dans une direction : 90 % de la distance à la couche nuageuse (ou au centre de la
## Terre si le rayon la manque).
func _plateau(eye: Vector3, direction: Vector3) -> float:
	var to_center := _earth.global_position - eye
	var along := to_center.dot(direction)
	var miss_sq := to_center.length_squared() - along * along
	var radius_sq := _cloud_radius * _cloud_radius
	if along <= 0.0 or miss_sq > radius_sq:
		return to_center.length()
	return 0.9 * (along - sqrt(radius_sq - miss_sq))


func _build_glow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = preload("res://shaders/missile_glow.gdshader")
	_glow_material.set_shader_parameter("intensity", 0.0)
	quad.material = _glow_material
	_glow = MeshInstance3D.new()
	_glow.name = "MissileGlow"
	_glow.mesh = quad
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le panneau est tourné vers la caméra par le shader : boîte englobante large pour ne jamais être éliminé.
	_glow.extra_cull_margin = 4.0
	add_child(_glow)
