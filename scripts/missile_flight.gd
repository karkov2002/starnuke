class_name MissileFlight
extends Node3D
## Vol d'un missile après l'animation Blender (Station.missile_released) jusqu'au point d'impact.
##
## Deux phases, en mètres réels (le temps suit l'horloge du jeu : Orbit.time_scale, pause et accélération) :
## 1. Phase spatiale (de 0 à flight_time_s − reentry_time_s), dans le repère de la station (fixe dans la scène ; c'est
##    la Terre qui bouge), vers le point d'entrée dans l'atmosphère (entry_altitude_km au-dessus de la cible, en amont
##    du côté de la station, pente de entry_angle_deg : la rentrée prolonge le vol). Comme un vrai missile, il
##    manœuvre pendant la combustion (burn_time_s) : il part dans l'axe de son tube (ligne droite de Blender), tourne
##    vers le point d'entrée en accélérant, puis le moteur s'éteint et il file sur sa lancée, en ligne droite à
##    vitesse constante (_space_point). La tête, froide, devient alors invisible : on le voit partir vers la cible,
##    puis on le perd de vue bien avant l'impact.
## 2. Rentrée (reentry_time_s) : du point d'entrée au point d'explosion (burst_height_km au-dessus de la cible), en
##    ralentissant ; la tête s'échauffe : tête incandescente et traînée de plasma (ReentryStreak) dont l'éclat suit
##    l'altitude (montée sous 75 km, plein de 60 à 30 km, extinction vers 10 km : la tête a ralenti). arrived à la fin.
##
## Rendu de la phase spatiale à l'échelle préservant la perspective : la Terre est à 1/10 000 ; un objet K fois plus
## proche et K fois plus petit paraît identique depuis la caméra. Le missile, à une distance réelle d de la caméra,
## est dessiné à taille réelle tant qu'il est plus près que le palier F (90 % de la distance de la couche nuageuse
## dans sa direction), puis sur ce palier réduit de F / d (toujours devant les nuages et la Terre), enfin à l'échelle
## exacte de la Terre quand d / 10 000 dépasse F. La rentrée, dans l'atmosphère, est à l'échelle exacte de la Terre.
## Propulsion : panache en coordonnées locales (MissileExhaust.enter_flight) ; halo additif d'au moins
## min_glow_pixels tant que le moteur brûle ; lumière du moteur sur la station en 1/d².

signal arrived

## Mètres réels par unité de scène de la Terre (1 unité = 10 km).
const REAL_M_PER_UNIT := 1000.0 / OrbitSimulation.SCENE_UNITS_PER_KM

## Durée du vol (s, temps de jeu), fixée par le lanceur selon la distance de la cible (cf. nuke/launch_control.gd).
var flight_time_s := 20.0
## Durée de combustion du moteur (s) et durée de son extinction (s).
var burn_time_s := 9.0
var burn_out_s := 0.5
## Accélération le long de la ligne droite de Blender (m/s²), au début de la combustion, avant le virage.
var dive_acceleration := 30.0
## Rotation maximale du missile pour suivre sa trajectoire (rad/s).
var turn_rate := 1.2
## Halo du moteur : rayon réel (m), taille minimale à l'écran (pixels), distance réelle d'apparition (m).
var glow_radius_m := 2.5
var min_glow_pixels := 4.0
var glow_fade_in_m := Vector2(150.0, 1500.0)
## Distance réelle (m) jusqu'à laquelle la lumière du moteur éclaire la station à pleine intensité (puis en 1/d²).
var light_full_m := 40.0
## Rentrée : altitude d'entrée (km), pente (degrés sous l'horizontale), part du vol (bornée en secondes).
var entry_altitude_km := 100.0
## Pente rasante, comme une vraie rentrée depuis l'orbite (quelques degrés) : plus plate que la ligne de visée vers
## la cible (≥ ~10° sous l'horizontale), la traînée arrive à l'écran du bas, du côté de la station, et monte vers la
## cible, dans le sens où le missile est parti. (Une pente égale à celle de la ligne de visée la réduirait à un
## point ; plus raide, elle semblerait tomber du haut de l'écran.)
var entry_angle_deg := 8.0
var reentry_share := 0.2
var reentry_bounds_s := Vector2(6.0, 12.0)
## Éclat de la rentrée selon l'altitude (km) : apparition, plein, fin du plein, extinction.
var reentry_glow_km := PackedFloat32Array([75.0, 60.0, 30.0, 10.0])
## Longueur de la traînée, en secondes de trajet derrière la tête.
var trail_seconds := 3.5

var _missile: Node3D
var _exhaust: MissileExhaust
var _station: Node3D
var _earth: Node3D
var _cloud_radius := 0.0
## Points d'explosion et d'entrée dans l'atmosphère, dans le repère du maillage de la Terre (unités de scène).
var _burst_local := Vector3.ZERO
var _entry_local := Vector3.ZERO
var _start_offset := Vector3.ZERO
var _start_velocity := Vector3.ZERO
var _dive_direction := Vector3.DOWN
var _elapsed := 0.0
var _attitude := Quaternion.IDENTITY
var _last_relative := Vector3.ZERO
var _engine := 1.0
var _glow: MeshInstance3D
var _glow_material: ShaderMaterial
var _streak: ReentryStreak


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
	var up := target_local.normalized()
	var units := OrbitSimulation.SCENE_UNITS_PER_KM
	_burst_local = up * (OrbitSimulation.EARTH_RADIUS_KM + burst_height_km) * units
	# Point d'entrée : dans le prolongement du vol, en amont de la cible du côté de la station (le missile part de la
	# station et file vers la cible : sa tête rentre dans l'atmosphère en venant de là ; à l'écran, la traînée pointe
	# de la station vers la cible). Cible au nadir (pas de direction horizontale) : arrivée de l'arrière, le long de la
	# trace au sol.
	var forward := earth.global_basis.inverse() * station.global_basis.x
	var back := -(forward - up * forward.dot(up))
	back = back.normalized() if back.length() > 1e-4 else up.cross(Vector3.UP).normalized()
	var station_local := earth.global_transform.affine_inverse() * station.global_position
	var sight := station_local - _burst_local
	sight -= up * sight.dot(up)
	var toward := sight.normalized() if sight.length() > 30.0 * units else back
	var drop := entry_altitude_km - burst_height_km
	_entry_local = up * (OrbitSimulation.EARTH_RADIUS_KM + entry_altitude_km) * units \
			+ toward * (drop / tan(deg_to_rad(entry_angle_deg))) * units
	_start_offset = missile.global_position - station.global_position
	_start_velocity = velocity
	_dive_direction = velocity.normalized() if velocity.length() > 0.1 else -station.global_basis.y
	_attitude = missile.global_basis.orthonormalized().get_rotation_quaternion()
	_last_relative = _start_offset
	if _exhaust:
		_exhaust.enter_flight()
	_build_glow()
	_streak = ReentryStreak.new()
	_streak.name = "Reentry"
	add_child(_streak)


## Durée de la rentrée (s, temps de jeu).
func reentry_time() -> float:
	return clampf(flight_time_s * reentry_share, reentry_bounds_s.x, minf(reentry_bounds_s.y, flight_time_s * 0.5))


## Temps restant avant l'impact (s, temps de jeu).
func time_left() -> float:
	return maxf(flight_time_s - _elapsed, 0.0)


func _process(delta: float) -> void:
	if _missile == null or not is_instance_valid(_missile):
		queue_free()
		return
	var orbit := NukeClock.orbit
	var game_delta := delta * (orbit.time_scale if orbit else 1.0)
	_elapsed += game_delta
	var t := _elapsed
	var reentry_s := reentry_time()
	var space_s := flight_time_s - reentry_s

	# Extinction du moteur : la poussée de la propulsion éteint panache, cœur et lumière.
	_engine = clampf(1.0 - (t - burn_time_s) / burn_out_s, 0.0, 1.0)
	if _exhaust:
		_exhaust.throttle = _engine

	if t < space_s:
		var relative := _space_point(t, space_s, _to_relative(_earth.global_transform * _entry_local))
		if game_delta > 0.0:
			var motion := relative - _last_relative
			if motion.length() > 1e-4:
				# Pointe (−Y du missile) dans le sens du déplacement.
				var wanted := Quaternion(Vector3.DOWN, motion.normalized())
				_attitude = _attitude.slerp(wanted,
						clampf(turn_rate * delta / maxf(_attitude.angle_to(wanted), 1e-4), 0.0, 1.0))
		_last_relative = relative
		_place(relative)
		_streak.update(Vector3.ZERO, Vector3.ZERO, 0.0)
	else:
		# Dans l'atmosphère : la tête froide n'est plus visible que par son échauffement.
		_missile.visible = false
		_glow.visible = false
		var v := clampf((t - space_s) / reentry_s, 0.0, 1.0)
		var head_local := _reentry_point(v)
		var tail_local := _reentry_point(maxf(v - trail_seconds / reentry_s, 0.0))
		var altitude_km := head_local.length() / OrbitSimulation.SCENE_UNITS_PER_KM - OrbitSimulation.EARTH_RADIUS_KM
		var e := _earth.global_transform
		_streak.update(e * head_local, e * tail_local, _reentry_glow(altitude_km))
	if t >= flight_time_s:
		arrived.emit()
		_missile.queue_free()
		queue_free()


## Position du missile pendant la phase spatiale (t de 0 à space_s), relative à la station (m réels) ; entry : point
## d'entrée dans l'atmosphère, même repère (recalculé à chaque image : il suit la Terre). Vitesse de croisière V,
## choisie pour arriver au point d'entrée à space_s : la combustion (durée b) couvre ~V · b / 2 en accélérant, la
## croisière le reste, L = V · (b / 2 + (space_s − b)).
## - Combustion : courbe d'Hermite de la sortie (vitesse de Blender) au point de fin de combustion (vitesse V vers le
##   point d'entrée), fondue depuis la ligne droite de Blender (accélérée de dive_acceleration) : le missile part dans
##   l'axe de son tube, puis tourne vers la cible en accélérant.
## - Croisière, moteur éteint : ligne droite à vitesse constante V jusqu'au point d'entrée.
func _space_point(t: float, space_s: float, entry: Vector3) -> Vector3:
	var b := minf(burn_time_s, space_s)
	var to_entry := entry - _start_offset
	var length := maxf(to_entry.length(), 1.0)
	var direction := to_entry / length
	var speed := length / (0.5 * b + (space_s - b))
	var burn_end := _start_offset + direction * (0.5 * speed * b)
	if t >= b:
		return burn_end + direction * speed * (t - b)
	var s := t / b
	var s2 := s * s
	var s3 := s2 * s
	var hermite := _start_offset * (2.0 * s3 - 3.0 * s2 + 1.0) + _start_velocity * b * (s3 - 2.0 * s2 + s) \
			+ burn_end * (3.0 * s2 - 2.0 * s3) + direction * speed * b * (s3 - s2)
	var straight := _start_offset + _start_velocity * t + _dive_direction * (0.5 * dive_acceleration * t * t)
	return straight.lerp(hermite, smoothstep(0.0, 1.0, s))


## Position de la tête pendant la rentrée (v de 0 à 1), repère du maillage de la Terre : ligne droite du point
## d'entrée au point d'explosion, en ralentissant (freinage dans l'air de plus en plus dense).
func _reentry_point(v: float) -> Vector3:
	return _entry_local.lerp(_burst_local, 1.0 - pow(1.0 - v, 1.6))


## Éclat de la rentrée selon l'altitude (km) : 0 au-dessus de reentry_glow_km[0], plein de [1] à [2], 0 sous [3].
func _reentry_glow(altitude_km: float) -> float:
	var g := reentry_glow_km
	var rise := clampf(inverse_lerp(g[0], g[1], altitude_km), 0.0, 1.0)
	var fall := clampf(inverse_lerp(g[3], g[2], altitude_km), 0.0, 1.0)
	return smoothstep(0.0, 1.0, rise) * smoothstep(0.0, 1.0, fall)


## Point de la scène (échelle de la Terre) en mètres réels par rapport à l'origine de la station (repère du monde).
func _to_relative(scene_point: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else _station.global_position
	return (scene_point - eye) * REAL_M_PER_UNIT + (eye - _station.global_position)


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
	# Halo : rayon réel réduit comme le missile, mais jamais moins de min_glow_pixels à l'écran ; il s'éteint avec
	# le moteur.
	_glow.visible = _engine > 0.0
	var shown_nozzle := maxf(eye.distance_to(nozzle), 1e-3)
	var pixel_angle := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var radius := maxf(glow_radius_m * shrink, min_glow_pixels * pixel_angle * shown_nozzle)
	_glow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), nozzle)
	# Apparition au-delà de la propulsion proche (déjà rendue par le panache), puis éclat qui baisse lentement.
	var fade_in := smoothstep(glow_fade_in_m.x, glow_fade_in_m.y, distance)
	var far := lerpf(1.0, 0.45, clampf(distance / 600000.0, 0.0, 1.0))
	_glow_material.set_shader_parameter("intensity", fade_in * far * _engine)


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
