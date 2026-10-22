class_name StationSilos
extends RefCounted
## Silos de la station (composant de Station, scripts/station.gd, qui garde les signaux silo_door_changed,
## missile_ignited, missile_released et les réglages exportés) : les 48 trappes (objets Interactif_* d'extras type
## « trappe_silo » : silo, tube, charniere ; angles et durée lus dans l'animation Ouverture_Trappes), le gyrophare du
## tube choisi, et le lancement des missiles.
## Missiles : un seul est modélisé (Missile_Balistique_1_12, tube 1_12). Pour un autre tube, il est copié et placé à
## l'identique par rapport au Point_Lancement du tube ; le lancement rejoue l'animation Lancement_Missile : ouverture
## de la trappe, descente, allumage de la tuyère (Point_Tuyere : échelle 0 = éteint, 1 = allumé), jusqu'à ~30 m sous
## la station ; missile_released passe alors le missile au vol vers la cible (scripts/missile_flight.gd).

## Trappe d'un tube : charnière, angles fermé / ouvert, état atteint et état visé, tir fait.
class SiloDoor:
	var node: Node
	var hinge: Node3D
	var launch_point: Node3D
	var ouvrable := false
	var is_open := false
	## État visé (celui vers lequel elle bouge, ou son état au repos).
	var target := false
	var fired := false
	var closed := Quaternion.IDENTITY
	var open := Quaternion.IDENTITY
	var duration := 0.0
	var tween: Tween

var _station: Station
var _anim: StationAnim
## Vector2i(silo, tube) -> SiloDoor.
var _doors := {}
## Vector2i(silo, tube) -> gyrophare (Node3D : Lampe, Lumiere).
var _beacons := {}
var _beacon_time := 0.0
## Copie intacte du missile modèle (prise au démarrage) : celui du tube 1_12 disparaît après son lancement.
var _missile_pristine: Node3D


func _init(station: Station, anim: StationAnim) -> void:
	_station = station
	_anim = anim
	var door_anim := anim.animation(Station.ANIM_SILO_DOORS)
	for node in station.find_children("Interactif_*", "", true, false):
		# Les corps de collision des portes portent le même nom que leur porte.
		if node is CollisionObject3D:
			continue
		var extras: Dictionary = node.get_meta("extras", {})
		if String(extras.get("type", "")) != "trappe_silo":
			continue
		var door := SiloDoor.new()
		door.node = node
		door.hinge = station.get_node_or_null(NodePath(String(extras.get("charniere", "")))) as Node3D \
				if extras.has("charniere") else null
		door.ouvrable = extras.get("ouvrable", door.hinge != null) and door.hinge != null
		var key := Vector2i(int(extras.get("silo", 0)), int(extras.get("tube", 0)))
		door.launch_point = station.get_node_or_null("Point_Lancement_%d_%02d" % [key.x, key.y]) as Node3D
		if door.hinge and door_anim:
			# Ouverture_Trappes : début = fermée, fin = ouverte.
			var range := anim.hinge_range(door_anim, door.hinge)
			door.ouvrable = door.ouvrable and range.animated
			door.closed = range.start
			door.open = range.end
			door.duration = range.duration
		StationModelSetup.fit_door_collision(node)
		_doors[key] = door
	var model := _missile_template()
	if model:
		_missile_pristine = model.duplicate() as Node3D


## La station quitte l'arbre : la copie du missile modèle (hors arbre) est libérée.
func dispose() -> void:
	if _missile_pristine:
		_missile_pristine.free()
		_missile_pristine = null


## Gyrophares : éclat bref puis extinction, montée et descente rapides pour éviter un clignotement sec.
func update(delta: float) -> void:
	if _beacons.is_empty():
		return
	var period := _station.beacon_period_s
	_beacon_time = fmod(_beacon_time + delta, period)
	var phase := _beacon_time / period
	var duty := _station.beacon_duty
	var level := smoothstep(0.0, 0.05, phase) * (1.0 - smoothstep(duty - 0.05, duty, phase))
	for beacon: Node3D in _beacons.values():
		var lamp := beacon.get_node("Lampe") as MeshInstance3D
		((lamp.mesh as SphereMesh).material as StandardMaterial3D).emission_energy_multiplier = 8.0 * level
		(beacon.get_node("Lumiere") as OmniLight3D).light_energy = _station.beacon_energy * level


# --- Trappes --------------------------------------------------------------------------------------------------------

func is_door_open(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	return _doors.has(key) and _doors[key].is_open


func set_door_open(silo: int, tube: int, open: bool) -> bool:
	var key := Vector2i(silo, tube)
	if not _doors.has(key) or not _doors[key].ouvrable:
		return false
	var door: SiloDoor = _doors[key]
	# État visé (et non l'état atteint) : une demande inverse en cours de mouvement repart de la position actuelle.
	if door.target == open:
		return true
	door.target = open
	if door.tween:
		door.tween.kill()
	door.tween = _anim.tween_hinge(door.hinge, door.open if open else door.closed, door.duration, func() -> void:
		door.tween = null
		door.is_open = open
		_station.silo_door_changed.emit(silo, tube, open))
	return true


## Toutes les trappes d'un silo (silo = 0 : les deux) : vague de l'animation si les 48 sont dans le même état.
func set_all_doors_open(open: bool, silo := 0) -> void:
	var keys := _doors.keys().filter(func(k: Vector2i) -> bool:
		return (silo == 0 or k.x == silo) and _doors[k].ouvrable)
	var group := silo == 0 and keys.all(func(k: Vector2i) -> bool:
		return _doors[k].is_open != open and _doors[k].tween == null)
	if group and keys.size() == _anim.animated_count(Station.ANIM_SILO_DOORS):
		_anim.play_group(Station.ANIM_SILO_DOORS, not open, func() -> void:
			for k: Vector2i in keys:
				_doors[k].is_open = open
				_doors[k].target = open
				_station.silo_door_changed.emit(k.x, k.y, open))
	else:
		for k: Vector2i in keys:
			set_door_open(k.x, k.y, open)


# --- Missiles -------------------------------------------------------------------------------------------------------

## Gyrophare rouge à côté de la trappe du tube (tube choisi pour le tir) : petite lampe émissive et lumière rouge
## clignotante (beacon_period_s), qui éclaire la trappe et le dessous de la coque pour qu'on voie la trappe s'ouvrir.
func set_beacon(silo: int, tube: int, on: bool) -> void:
	var key := Vector2i(silo, tube)
	if not on:
		if _beacons.has(key):
			(_beacons[key] as Node3D).queue_free()
			_beacons.erase(key)
		return
	if _beacons.has(key) or not _doors.has(key) or _doors[key].launch_point == null:
		return
	var point := _station.to_local((_doors[key].launch_point as Node3D).global_position)
	var beacon := Node3D.new()
	beacon.name = "Gyrophare_%d_%02d" % [silo, tube]
	# Juste sous la coque, décalé vers l'extérieur de la rangée de tubes (avant/arrière), entre deux trappes.
	var side := signf(point.x) if absf(point.x) > 0.1 else 1.0
	var offset := _station.beacon_offset
	beacon.position = point + Vector3(offset.x * side, offset.y, offset.z)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lampe"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.0, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.05, 0.02)
	material.emission_energy_multiplier = 0.0
	sphere.material = material
	lamp.mesh = sphere
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(lamp)
	var light := OmniLight3D.new()
	light.name = "Lumiere"
	light.light_color = Color(1.0, 0.08, 0.04)
	light.omni_range = _station.beacon_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.light_cull_mask = 0xFFFFF & ~Station.INTERIOR_LAYER
	light.position = Vector3(0.0, -0.1, 0.0)
	beacon.add_child(light)
	_station.add_child(beacon)
	_beacons[key] = beacon


## Tous les tubes de lancement, triés (silo, puis tube).
func tube_ids() -> Array[Vector2i]:
	var tubes: Array[Vector2i] = []
	tubes.assign(_doors.keys())
	tubes.sort()
	return tubes


## Position du tube (repère Point_Lancement) dans le repère de la station : +X vers l'avant, +Z vers la droite.
func tube_position(silo: int, tube: int) -> Vector3:
	var key := Vector2i(silo, tube)
	if not _doors.has(key) or _doors[key].launch_point == null:
		return Vector3.ZERO
	return _station.global_transform.affine_inverse() * (_doors[key].launch_point as Node3D).global_position


## Durée de l'animation de lancement jusqu'au relais vers le vol (s) : missile_released arrive autant après
## launch_missile.
func launch_handoff_s() -> float:
	var anim := _anim.animation(Station.ANIM_LAUNCH)
	if anim == null:
		return 0.0
	return StationAnim.handoff_time(anim, StationAnim.track_for(anim, Station.MODEL_MISSILE, Animation.TYPE_SCALE_3D))


## Tubes d'où un missile peut partir (trappe ouvrable, pas encore tiré).
func available_tubes() -> Array[Vector2i]:
	var tubes: Array[Vector2i] = []
	for key: Vector2i in _doors:
		if can_launch(key.x, key.y):
			tubes.append(key)
	tubes.sort()
	return tubes


func can_launch(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	if not _doors.has(key):
		return false
	var door: SiloDoor = _doors[key]
	return door.ouvrable and not door.fired and door.launch_point != null and _missile_pristine != null


## Lance le missile du tube : la trappe s'ouvre (si besoin), le missile descend, s'allume, puis quitte la scène
## (missile_released). Faux si le tube ne peut pas tirer.
func launch_missile(silo: int, tube: int) -> bool:
	if not can_launch(silo, tube):
		return false
	var key := Vector2i(silo, tube)
	var door: SiloDoor = _doors[key]
	door.fired = true
	var template := _missile_template()
	var missile := template
	if key != Vector2i(Station.MODEL_SILO, Station.MODEL_TUBE):
		missile = _missile_pristine.duplicate() as Node3D
		missile.name = "Missile_Balistique_%d_%02d" % [silo, tube]
		missile.get_child(0).name = "Point_Tuyere_%d_%02d" % [silo, tube]
		_station.add_child(missile)
	var nozzle := missile.get_child(0) as Node3D
	# Repère de la tuyère à l'arrière du missile (bout +Y du maillage, la pointe est en −Y) : dans le modèle
	# réexporté, Point_Tuyere est au centre du missile, et la propulsion semblait sortir du milieu de la coque.
	var hull := (missile as MeshInstance3D).mesh.get_aabb() if missile is MeshInstance3D else AABB()
	if hull.size.y > 0.0:
		nozzle.position = Vector3(0.0, hull.end.y + _station.nozzle_offset_m, 0.0)
	var model_point := _station.get_node_or_null("Point_Lancement_%d_%02d" % [Station.MODEL_SILO, Station.MODEL_TUBE]) as Node3D
	# Missile du tube = repère du tube × (repère du tube modèle)⁻¹ × missile modèle animé.
	var tube_frame: Transform3D = door.launch_point.transform * model_point.transform.affine_inverse()
	var anim := _anim.animation(Station.ANIM_LAUNCH)
	var position_track := StationAnim.track_for(anim, Station.MODEL_MISSILE, Animation.TYPE_POSITION_3D)
	var scale_track := StationAnim.track_for(anim, Station.MODEL_MISSILE, Animation.TYPE_SCALE_3D)
	var nozzle_track := StationAnim.track_for(anim, Station.MODEL_MISSILE + "/Point_Tuyere_%d_%02d" % [Station.MODEL_SILO, Station.MODEL_TUBE],
			Animation.TYPE_SCALE_3D)
	var model_hinge_track := StationAnim.track_for(anim, "Charniere_Trappe_Silo_%d_%02d" % [Station.MODEL_SILO, Station.MODEL_TUBE])
	var model_hinge_end: Quaternion = anim.track_get_key_value(model_hinge_track,
			anim.track_get_key_count(model_hinge_track) - 1) if model_hinge_track >= 0 else Quaternion.IDENTITY
	var release_time := StationAnim.handoff_time(anim, scale_track)
	var state := {"ignited": false}
	var was_open := door.is_open
	# Trappe déjà ouverte ou en mouvement (choix du tube sur le panneau) : l'animation la reprend où elle est.
	if door.tween:
		door.tween.kill()
		door.tween = null
	door.target = true
	var hinge_start := door.hinge.quaternion
	var step := func(t: float) -> void:
		# Trappe du tube : même ouverture que la trappe modèle dans l'animation, transposée sur ses angles.
		if model_hinge_track >= 0:
			var q := anim.rotation_track_interpolate(model_hinge_track, t)
			var weight := q.angle_to(Quaternion.IDENTITY) / maxf(model_hinge_end.angle_to(Quaternion.IDENTITY), 1e-4)
			door.hinge.quaternion = hinge_start.slerp(door.open, clampf(weight, 0.0, 1.0))
		var scale_value := anim.scale_track_interpolate(scale_track, t) if scale_track >= 0 else Vector3.ONE
		var model := Transform3D(Basis.IDENTITY.scaled(scale_value), anim.position_track_interpolate(position_track, t))
		missile.transform = tube_frame * model
		if nozzle_track >= 0:
			nozzle.scale = anim.scale_track_interpolate(nozzle_track, t)
			if not state.ignited and nozzle.scale.x > 0.01:
				state.ignited = true
				_station.missile_ignited.emit(silo, tube)
	var tween := _station.create_tween()
	tween.tween_method(step, 0.0, release_time, release_time)
	tween.tween_callback(func() -> void:
		door.is_open = true
		if not was_open:
			_station.silo_door_changed.emit(silo, tube, true)
		# Vitesse de sortie (monde) : dérivée de la piste de position de l'animation, transposée sur le tube.
		var dt := minf(0.05, release_time)
		var model_velocity := (anim.position_track_interpolate(position_track, release_time)
				- anim.position_track_interpolate(position_track, release_time - dt)) / maxf(dt, 1e-3)
		var velocity := _station.global_basis * (tube_frame.basis * model_velocity)
		if _station.missile_released.get_connections().is_empty():
			missile.visible = false
			if missile != template:
				missile.queue_free()
		else:
			_station.missile_released.emit(silo, tube, missile, velocity))
	return true


func _missile_template() -> Node3D:
	return _station.get_node_or_null(Station.MODEL_MISSILE) as Node3D
