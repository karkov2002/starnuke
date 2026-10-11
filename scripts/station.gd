class_name Station
extends Node3D
## Station spatiale (racine de scenes/station_spatiale.tscn, scène héritée du modèle Blender
## assets/station/station_spatiale.glb). API de pilotage : écoutilles, trappes des silos, lancement des missiles,
## radiateurs et jauge de chaleur.
##
## Tout est lu dans le modèle, rien n'est codé en dur (le .glb est réexporté depuis Blender avec les mêmes noms) :
## - objets « Interactif_* » : métadonnée « extras » (propriétés Blender) : type (ecoutille, trappe_silo, trappe), id,
##   charniere, silo, tube, ouvrable ;
## - angles et durées : ceux des animations Blender. Pour piloter un objet seul, ses pistes sont rejouées par un Tween
##   (_play_tracks) ; pour un groupe dans le même état (toutes les écoutilles…), l'animation complète est jouée par un
##   AnimationPlayer. Chaque animation a son propre AnimationPlayer (créé ici, bibliothèque partagée) : elles peuvent
##   tourner en même temps (panneaux et antennes en boucle, trappes, radiateurs).
## États au repos (modèle) : écoutilles ouvertes, trappes des silos fermées, radiateurs déployés.
##
## Missiles : un seul est modélisé (Missile_Balistique_1_12, tube 1_12). Pour un autre tube, il est copié et placé à
## l'identique par rapport au Point_Lancement du tube ; le lancement rejoue l'animation Lancement_Missile : ouverture
## de la trappe, descente, allumage de la tuyère (Point_Tuyere : échelle 0 = éteint, 1 = allumé), puis disparition
## (échelle 0, ~30 m sous la station) : missile_released signale le relais vers le système de frappe.
##
## Chaleur (préparation d'une jauge) : heat (0 à 1) monte quand les radiateurs sont repliés (mode furtif : pas de
## rayonnement infrarouge) et redescend quand ils sont déployés, en proportion des radiateurs déployés.

signal hatch_changed(id: String, open: bool)
signal silo_door_changed(silo: int, tube: int, open: bool)
signal radiator_changed(id: String, deployed: bool)
signal missile_ignited(silo: int, tube: int)
## Le missile quitte la scène (relais vers la frappe) : position et orientation (monde) à ce moment.
signal missile_released(silo: int, tube: int, world_transform: Transform3D)
signal heat_changed(heat: float)

const ANIM_HATCHES := &"Fermeture_Ecoutilles"
const ANIM_SILO_DOORS := &"Ouverture_Trappes"
const ANIM_LAUNCH := &"Lancement_Missile"
const ANIM_RADIATORS := &"Retraction_Radiateurs"
const ANIM_PANELS := &"Rotation_Panneaux"
const ANIM_ANTENNAS := &"Balayage_Antennes"
const MODEL_MISSILE := "Missile_Balistique_1_12"
const MODEL_SILO := 1
const MODEL_TUBE := 12
const RADIATOR_IDS: Array[String] = ["Radiateur_D15", "Radiateur_D21", "Radiateur_G15", "Radiateur_G21"]
## Calque des surfaces intérieures (bit 11), seul éclairé par les lampes intérieures.
const INTERIOR_LAYER := 1 << 10
## Matériaux intérieurs (préfixes des noms Blender) ; tous les autres sont extérieurs. Les vitrages et hublots se
## voient des deux côtés : ils sont des deux calques.
const INTERIOR_MATERIALS: Array[String] = ["Int_", "Ecran_"]
const BOTH_SIDES_MATERIALS: Array[String] = ["Hublot", "Vitrage"]
## Surface masquée : rejetée avant tout calcul de pixel (sommets hors du volume de vue).
const HIDDEN_SHADER := "shader_type spatial;\nrender_mode unshaded, skip_vertex_transform;\nvoid vertex() {\n\tPOSITION = vec4(0.0, 0.0, 2.0, 1.0);\n}\n"

@export var animate_solar_panels := true
@export var animate_antennas := true

@export_group("Éclairage intérieur")
## 28 lampes ponctuelles du modèle (Lum_*), recalibrées au démarrage : ambiance ISS (luminaires LED en mode jour,
## ~4 500 K), sans ombres. Elles n'éclairent que les surfaces intérieures (calque INTERIOR_LAYER) : sans ombres, elles
## traverseraient sinon la coque et l'éclaireraient de l'extérieur.
@export var interior_light_energy := 1.2
@export var interior_light_range := 5.5
@export var interior_light_attenuation := 1.3
@export var interior_light_temperature := 4500.0
@export var interior_light_specular := 0.4
@export var interior_shadows := false
## Chaleur : montée par seconde radiateurs tous repliés, descente par seconde radiateurs tous déployés
## (valeurs provisoires, à régler avec la jauge).
@export var heat_rise_per_s := 0.01
@export var heat_fall_per_s := 0.02

## Chaleur accumulée (0 à 1).
var heat := 0.0

## id -> {node, hinge, open, closed : Quaternion, duration, track, is_open, ouvrable, tween}
var _hatches := {}
## Vector2i(silo, tube) -> {node, hinge, closed, open, track, duration, is_open, ouvrable, tween, launch_point, fired}
var _silo_doors := {}
## id -> {tracks : Array[int], is_deployed, tween}
var _radiators := {}
var _players := {}
var _library: AnimationLibrary
## Copie intacte du missile modèle (prise au démarrage) : celui du tube 1_12 disparaît après son lancement.
var _missile_pristine: Node3D


func _ready() -> void:
	var imported := find_children("*", "AnimationPlayer", true, false)
	if imported.is_empty():
		push_error("Station : pas d'AnimationPlayer dans le modèle")
		return
	_library = (imported[0] as AnimationPlayer).get_animation_library(&"")
	for anim_name in _library.get_animation_list():
		var player := AnimationPlayer.new()
		player.name = "Player_" + anim_name
		add_child(player)
		player.root_node = player.get_path_to(self)
		player.add_animation_library(&"", _library)
		_players[anim_name] = player
	_collect_interactives()
	_collect_radiators()
	_setup_interior_lighting()
	var model := _missile_template()
	if model:
		_missile_pristine = model.duplicate() as Node3D
	if animate_solar_panels and _players.has(ANIM_PANELS):
		_players[ANIM_PANELS].play(ANIM_PANELS)
	if animate_antennas and _players.has(ANIM_ANTENNAS):
		_players[ANIM_ANTENNAS].play(ANIM_ANTENNAS)


func _exit_tree() -> void:
	if _missile_pristine:
		_missile_pristine.free()
		_missile_pristine = null


func _process(delta: float) -> void:
	if _radiators.is_empty():
		return
	var deployed := 0.0
	for id: String in _radiators:
		deployed += 1.0 if _radiators[id].is_deployed else 0.0
	var share := deployed / _radiators.size()
	var rate := heat_rise_per_s * (1.0 - share) - heat_fall_per_s * share
	var value := clampf(heat + rate * delta, 0.0, 1.0)
	if not is_equal_approx(value, heat):
		heat = value
		heat_changed.emit(heat)


# --- Écoutilles ---------------------------------------------------------------------------------------------------

func hatch_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_hatches.keys())
	return ids


func is_hatch_open(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].is_open


func is_hatch_openable(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].ouvrable


## Ouvre ou ferme une écoutille (Tween, durée de l'animation Blender). Faux si elle est verrouillée ou inconnue.
func set_hatch_open(id: String, open: bool) -> bool:
	if not is_hatch_openable(id):
		return false
	var hatch: Dictionary = _hatches[id]
	if hatch.is_open == open:
		return true
	# Fermeture_Ecoutilles : début = ouverte, fin = fermée.
	_tween_hinge(hatch, hatch.closed if not open else hatch.open, func() -> void:
		hatch.is_open = open
		hatch_changed.emit(id, open))
	return true


func open_hatch(id: String) -> bool:
	return set_hatch_open(id, true)


func close_hatch(id: String) -> bool:
	return set_hatch_open(id, false)


## Toutes les écoutilles ouvrables : animation complète si elles sont toutes dans le même état, sinon une par une.
func set_all_hatches_open(open: bool) -> void:
	var targets := _hatches.keys().filter(func(id: String) -> bool: return _hatches[id].ouvrable)
	var group := targets.all(func(id: String) -> bool: return _hatches[id].is_open != open and _hatches[id].tween == null)
	if group and targets.size() == _animated_count(ANIM_HATCHES):
		_play_group(ANIM_HATCHES, not open, func() -> void:
			for id: String in targets:
				_hatches[id].is_open = open
				hatch_changed.emit(id, open))
	else:
		for id: String in targets:
			set_hatch_open(id, open)


# --- Trappes des silos ----------------------------------------------------------------------------------------------

func is_silo_door_open(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	return _silo_doors.has(key) and _silo_doors[key].is_open


func set_silo_door_open(silo: int, tube: int, open: bool) -> bool:
	var key := Vector2i(silo, tube)
	if not _silo_doors.has(key) or not _silo_doors[key].ouvrable:
		return false
	var door: Dictionary = _silo_doors[key]
	if door.is_open == open:
		return true
	_tween_hinge(door, door.open if open else door.closed, func() -> void:
		door.is_open = open
		silo_door_changed.emit(silo, tube, open))
	return true


func open_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, true)


func close_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, false)


## Toutes les trappes d'un silo (silo = 0 : les deux) : vague de l'animation si les 48 sont dans le même état.
func set_all_silo_doors_open(open: bool, silo := 0) -> void:
	var keys := _silo_doors.keys().filter(func(k: Vector2i) -> bool:
		return (silo == 0 or k.x == silo) and _silo_doors[k].ouvrable)
	var group := silo == 0 and keys.all(func(k: Vector2i) -> bool:
		return _silo_doors[k].is_open != open and _silo_doors[k].tween == null)
	if group and keys.size() == _animated_count(ANIM_SILO_DOORS):
		_play_group(ANIM_SILO_DOORS, not open, func() -> void:
			for k: Vector2i in keys:
				_silo_doors[k].is_open = open
				silo_door_changed.emit(k.x, k.y, open))
	else:
		for k: Vector2i in keys:
			set_silo_door_open(k.x, k.y, open)


# --- Missiles -------------------------------------------------------------------------------------------------------

## Tubes d'où un missile peut partir (trappe ouvrable, pas encore tiré).
func available_tubes() -> Array[Vector2i]:
	var tubes: Array[Vector2i] = []
	for key: Vector2i in _silo_doors:
		if can_launch(key.x, key.y):
			tubes.append(key)
	tubes.sort()
	return tubes


func can_launch(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	return _silo_doors.has(key) and _silo_doors[key].ouvrable and not _silo_doors[key].fired \
			and _silo_doors[key].launch_point != null and _missile_pristine != null


## Lance le missile du tube : la trappe s'ouvre (si besoin), le missile descend, s'allume, puis quitte la scène
## (missile_released). Faux si le tube ne peut pas tirer.
func launch_missile(silo: int, tube: int) -> bool:
	if not can_launch(silo, tube):
		return false
	var key := Vector2i(silo, tube)
	var door: Dictionary = _silo_doors[key]
	door.fired = true
	var template := _missile_template()
	var missile := template
	if key != Vector2i(MODEL_SILO, MODEL_TUBE):
		missile = _missile_pristine.duplicate() as Node3D
		missile.name = "Missile_Balistique_%d_%02d" % [silo, tube]
		missile.get_child(0).name = "Point_Tuyere_%d_%02d" % [silo, tube]
		add_child(missile)
	var nozzle := missile.get_child(0) as Node3D
	var model_point := get_node_or_null("Point_Lancement_%d_%02d" % [MODEL_SILO, MODEL_TUBE]) as Node3D
	# Missile du tube = repère du tube × (repère du tube modèle)⁻¹ × missile modèle animé.
	var tube_frame: Transform3D = (door.launch_point as Node3D).transform * model_point.transform.affine_inverse()
	var anim := _library.get_animation(ANIM_LAUNCH)
	var position_track := _track_for(anim, MODEL_MISSILE, Animation.TYPE_POSITION_3D)
	var scale_track := _track_for(anim, MODEL_MISSILE, Animation.TYPE_SCALE_3D)
	var nozzle_track := _track_for(anim, MODEL_MISSILE + "/Point_Tuyere_%d_%02d" % [MODEL_SILO, MODEL_TUBE],
			Animation.TYPE_SCALE_3D)
	var model_hinge_track := _track_for(anim, "Charniere_Trappe_Silo_%d_%02d" % [MODEL_SILO, MODEL_TUBE])
	var model_hinge_end: Quaternion = anim.track_get_key_value(model_hinge_track,
			anim.track_get_key_count(model_hinge_track) - 1) if model_hinge_track >= 0 else Quaternion.IDENTITY
	var release_time := _release_time(anim, scale_track)
	var state := {"ignited": false, "released": false}
	var was_open: bool = door.is_open
	var step := func(t: float) -> void:
		# Trappe du tube : même ouverture que la trappe modèle dans l'animation, transposée sur ses angles.
		if model_hinge_track >= 0 and not was_open:
			var q := anim.rotation_track_interpolate(model_hinge_track, t)
			var weight := q.angle_to(Quaternion.IDENTITY) / maxf(model_hinge_end.angle_to(Quaternion.IDENTITY), 1e-4)
			door.hinge.quaternion = (door.closed as Quaternion).slerp(door.open, clampf(weight, 0.0, 1.0))
		var scale_value := anim.scale_track_interpolate(scale_track, t) if scale_track >= 0 else Vector3.ONE
		var model := Transform3D(Basis.IDENTITY.scaled(scale_value), anim.position_track_interpolate(position_track, t))
		missile.transform = tube_frame * model
		if nozzle_track >= 0:
			nozzle.scale = anim.scale_track_interpolate(nozzle_track, t)
			if not state.ignited and nozzle.scale.x > 0.01:
				state.ignited = true
				missile_ignited.emit(silo, tube)
		if not state.released and t >= release_time:
			state.released = true
			missile_released.emit(silo, tube, missile.global_transform)
	var tween := create_tween()
	tween.tween_method(step, 0.0, release_time, release_time)
	tween.tween_callback(func() -> void:
		door.is_open = true
		if not was_open:
			silo_door_changed.emit(silo, tube, true)
		missile.visible = false
		if missile != template:
			missile.queue_free())
	return true


# --- Radiateurs -----------------------------------------------------------------------------------------------------

func radiator_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_radiators.keys())
	return ids


func is_radiator_deployed(id: String) -> bool:
	return _radiators.has(id) and _radiators[id].is_deployed


## Déploie ou replie un radiateur (ses trois articulations, rejouées depuis Retraction_Radiateurs).
func set_radiator_deployed(id: String, deployed: bool) -> bool:
	if not _radiators.has(id):
		return false
	var radiator: Dictionary = _radiators[id]
	if radiator.is_deployed == deployed:
		return true
	if radiator.tween:
		radiator.tween.kill()
	var anim := _library.get_animation(ANIM_RADIATORS)
	# Retraction_Radiateurs : début = déployé, fin = replié.
	var from := 0.0 if deployed == false else anim.length
	var to := anim.length if deployed == false else 0.0
	radiator.tween = _play_tracks(anim, radiator.tracks, from, to, anim.length)
	radiator.tween.tween_callback(func() -> void:
		radiator.tween = null
		radiator.is_deployed = deployed
		radiator_changed.emit(id, deployed))
	return true


## Tous les radiateurs : animation complète s'ils sont tous dans le même état, sinon un par un.
func set_all_radiators_deployed(deployed: bool) -> void:
	var group := _radiators.keys().all(func(id: String) -> bool:
		return _radiators[id].is_deployed != deployed and _radiators[id].tween == null)
	if group:
		_play_group(ANIM_RADIATORS, deployed, func() -> void:
			for id: String in _radiators:
				_radiators[id].is_deployed = deployed
				radiator_changed.emit(id, deployed))
	else:
		for id: String in _radiators:
			set_radiator_deployed(id, deployed)


## Mode furtif : radiateurs repliés (la chaleur monte).
func set_stealth(enabled: bool) -> void:
	set_all_radiators_deployed(not enabled)


# --- Construction ---------------------------------------------------------------------------------------------------

func _collect_interactives() -> void:
	var hatch_anim := _library.get_animation(ANIM_HATCHES) if _library.has_animation(ANIM_HATCHES) else null
	var door_anim := _library.get_animation(ANIM_SILO_DOORS) if _library.has_animation(ANIM_SILO_DOORS) else null
	for node in find_children("Interactif_*", "", true, false):
		# Les corps de collision des portes portent le même nom que leur porte.
		if node is CollisionObject3D:
			continue
		var extras: Dictionary = node.get_meta("extras", {})
		var hinge := get_node_or_null(NodePath(String(extras.get("charniere", "")))) as Node3D \
				if extras.has("charniere") else null
		var ouvrable: bool = extras.get("ouvrable", hinge != null) and hinge != null
		match String(extras.get("type", "")):
			"ecoutille", "trappe":
				# Au repos : écoutilles ouvertes ; trappes verrouillées (sas, nadir) fermées.
				var entry := {"node": node, "hinge": hinge, "ouvrable": ouvrable,
						"is_open": String(extras.get("type")) == "ecoutille", "tween": null}
				if hinge and hatch_anim:
					_fill_hinge(entry, hatch_anim, hinge)
					# Début de Fermeture_Ecoutilles = ouverte.
					entry.open = entry.start
					entry.closed = entry.end
				_hatches[String(extras.get("id", node.name))] = entry
			"trappe_silo":
				var key := Vector2i(int(extras.get("silo", 0)), int(extras.get("tube", 0)))
				var entry := {"node": node, "hinge": hinge, "ouvrable": ouvrable, "is_open": false, "tween": null,
						"fired": false,
						"launch_point": get_node_or_null("Point_Lancement_%d_%02d" % [key.x, key.y])}
				if hinge and door_anim:
					_fill_hinge(entry, door_anim, hinge)
					entry.closed = entry.start
					entry.open = entry.end
				_silo_doors[key] = entry


## Angles de début et de fin et durée de la piste de rotation de la charnière dans l'animation.
func _fill_hinge(entry: Dictionary, anim: Animation, hinge: Node3D) -> void:
	var track := _track_for(anim, hinge.name)
	if track < 0:
		entry.ouvrable = false
		entry.start = hinge.quaternion
		entry.end = hinge.quaternion
		entry.duration = 0.0
		return
	var keys := anim.track_get_key_count(track)
	entry.start = anim.track_get_key_value(track, 0)
	entry.end = anim.track_get_key_value(track, keys - 1)
	entry.duration = maxf(anim.track_get_key_time(track, keys - 1) - anim.track_get_key_time(track, 0), 0.1)


func _collect_radiators() -> void:
	if not _library.has_animation(ANIM_RADIATORS):
		return
	var anim := _library.get_animation(ANIM_RADIATORS)
	for id in RADIATOR_IDS:
		var tracks: Array[int] = []
		for t in anim.get_track_count():
			if String(anim.track_get_path(t)).begins_with(id + "/"):
				tracks.append(t)
		if not tracks.is_empty():
			_radiators[id] = {"tracks": tracks, "is_deployed": true, "tween": null}


## Calques et lampes intérieures. Un maillage entièrement intérieur passe sur INTERIOR_LAYER ; un maillage mixte (coques :
## surfaces Coque_Silo dehors, Int_Coque dedans) est doublé : l'original ne garde que ses surfaces extérieures, la copie
## (même maillage, LOD compris, sans ombre portée) ses surfaces intérieures, sur INTERIOR_LAYER.
func _setup_interior_lighting() -> void:
	var hidden := ShaderMaterial.new()
	hidden.shader = Shader.new()
	hidden.shader.code = HIDDEN_SHADER
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		var interior: Array[int] = []
		var exterior: Array[int] = []
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(s)
			var material_name := material.resource_name if material else ""
			if _has_prefix(material_name, BOTH_SIDES_MATERIALS):
				if material_name.begins_with("Vitrage") and material is BaseMaterial3D:
					mesh_instance.set_surface_override_material(s, _matte_glass(material as BaseMaterial3D))
				continue
			if _has_prefix(material_name, INTERIOR_MATERIALS):
				interior.append(s)
			else:
				exterior.append(s)
		if exterior.is_empty():
			mesh_instance.layers |= INTERIOR_LAYER
		elif not interior.is_empty():
			var inside := MeshInstance3D.new()
			inside.name = String(mesh_instance.name) + "_Interieur"
			inside.mesh = mesh_instance.mesh
			inside.layers = mesh_instance.layers | INTERIOR_LAYER
			inside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in exterior:
				inside.set_surface_override_material(s, hidden)
			for s in interior:
				mesh_instance.set_surface_override_material(s, hidden)
			mesh_instance.add_child(inside)
	for light: OmniLight3D in find_children("Lum_*", "OmniLight3D", true, false):
		light.light_cull_mask = INTERIOR_LAYER
		light.light_energy = interior_light_energy
		light.omni_range = interior_light_range
		light.omni_attenuation = interior_light_attenuation
		light.light_color = Color.WHITE
		light.light_temperature = interior_light_temperature
		light.light_specular = interior_light_specular
		light.shadow_enabled = interior_shadows


## Vitrage de la cupola sans reflet spéculaire : le reflet de l'environnement (disque solaire du ciel) ignore l'ombre
## portée de la station, et faisait briller le soleil dans le hublot du nadir alors que la cupola est à l'ombre.
static func _matte_glass(source: BaseMaterial3D) -> BaseMaterial3D:
	var glass := source.duplicate() as BaseMaterial3D
	glass.metallic = 0.0
	glass.metallic_specular = 0.0
	glass.roughness = 1.0
	return glass


static func _has_prefix(text: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if text.begins_with(prefix):
			return true
	return false


# --- Outils ---------------------------------------------------------------------------------------------------------

## Charnière tournée de son angle courant vers target (durée de l'animation), puis done.
func _tween_hinge(entry: Dictionary, target: Quaternion, done: Callable) -> void:
	if entry.tween:
		entry.tween.kill()
	var hinge: Node3D = entry.hinge
	var start := hinge.quaternion
	entry.tween = create_tween()
	entry.tween.tween_method(func(w: float) -> void: hinge.quaternion = start.slerp(target, w), 0.0, 1.0,
			entry.duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	entry.tween.tween_callback(func() -> void:
		entry.tween = null
		done.call())


## Rejoue les pistes tracks de anim de from_s à to_s (à l'envers si to_s < from_s) en duration secondes.
func _play_tracks(anim: Animation, tracks: Array[int], from_s: float, to_s: float, duration: float) -> Tween:
	var targets: Array[Node3D] = []
	for t in tracks:
		targets.append(get_node_or_null(anim.track_get_path(t)) as Node3D)
	var tween := create_tween()
	tween.tween_method(func(time: float) -> void:
		for i in tracks.size():
			if targets[i]:
				_apply_track(anim, tracks[i], targets[i], time), from_s, to_s, duration)
	return tween


func _apply_track(anim: Animation, track: int, node: Node3D, time: float) -> void:
	match anim.track_get_type(track):
		Animation.TYPE_ROTATION_3D:
			node.quaternion = anim.rotation_track_interpolate(track, time)
		Animation.TYPE_POSITION_3D:
			node.position = anim.position_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			node.scale = anim.scale_track_interpolate(track, time)


## Animation complète (à l'envers si backwards), puis done.
func _play_group(anim_name: StringName, backwards: bool, done: Callable) -> void:
	var player: AnimationPlayer = _players[anim_name]
	if backwards:
		player.play_backwards(anim_name)
	else:
		player.play(anim_name)
	player.animation_finished.connect(func(_name: StringName) -> void: done.call(), CONNECT_ONE_SHOT)


## Nombre de charnières animées par l'animation (pistes de rotation).
func _animated_count(anim_name: StringName) -> int:
	if not _library.has_animation(anim_name):
		return 0
	var anim := _library.get_animation(anim_name)
	var count := 0
	for t in anim.get_track_count():
		count += 1 if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D else 0
	return count


## Piste de l'animation pour le nœud node_path (et du type donné, -1 : n'importe lequel), ou -1.
func _track_for(anim: Animation, node_path: String, type := -1) -> int:
	for t in anim.get_track_count():
		if String(anim.track_get_path(t)) == node_path and (type < 0 or anim.track_get_type(t) == type):
			return t
	return -1


## Instant où le missile disparaît (échelle nulle) dans Lancement_Missile : le relais vers la frappe.
func _release_time(anim: Animation, scale_track: int) -> float:
	if scale_track < 0:
		return anim.length
	for k in anim.track_get_key_count(scale_track):
		if (anim.track_get_key_value(scale_track, k) as Vector3).x < 1e-3:
			return anim.track_get_key_time(scale_track, k)
	return anim.length


func _missile_template() -> Node3D:
	return get_node_or_null(MODEL_MISSILE) as Node3D
