class_name StationAnim
extends RefCounted
## Boîte à outils d'animation de la station (Station, scripts/station.gd) : la bibliothèque d'animations du modèle
## Blender (une piste par charnière, position ou échelle), un AnimationPlayer par animation (créés ici comme enfants
## de la station, bibliothèque partagée : plusieurs animations peuvent tourner en même temps : panneaux et antennes
## en boucle, trappes, radiateurs), et les lecteurs à la pièce : pour piloter un objet seul, ses pistes sont rejouées
## par un Tween (play_tracks, tween_hinge) ; pour un groupe dans le même état (toutes les trappes…), l'animation
## complète est jouée par son AnimationPlayer (play_group). Les angles et durées viennent toujours des animations
## Blender, rien n'est codé en dur.

## Nœud racine des chemins de pistes et parent des lecteurs (la station).
var root: Node3D
var library: AnimationLibrary
## Nom d'animation -> AnimationPlayer.
var players := {}


## Bibliothèque du premier AnimationPlayer importé sous root, un lecteur par animation ; null sans AnimationPlayer.
static func from_model(model_root: Node3D) -> StationAnim:
	var imported := model_root.find_children("*", "AnimationPlayer", true, false)
	if imported.is_empty():
		return null
	var anim := StationAnim.new()
	anim.root = model_root
	anim.library = (imported[0] as AnimationPlayer).get_animation_library(&"")
	for anim_name in anim.library.get_animation_list():
		var player := AnimationPlayer.new()
		player.name = "Player_" + anim_name
		model_root.add_child(player)
		player.root_node = player.get_path_to(model_root)
		player.add_animation_library(&"", anim.library)
		anim.players[anim_name] = player
	return anim


func has(anim_name: StringName) -> bool:
	return library.has_animation(anim_name)


## L'animation, ou null si elle manque.
func animation(anim_name: StringName) -> Animation:
	return library.get_animation(anim_name) if library.has_animation(anim_name) else null


## Joue l'animation en entier (en boucle si elle l'est : antennes).
func play(anim_name: StringName) -> void:
	if players.has(anim_name):
		(players[anim_name] as AnimationPlayer).play(anim_name)


## Animation complète (à l'envers si backwards), puis done.
func play_group(anim_name: StringName, backwards: bool, done: Callable) -> void:
	var player: AnimationPlayer = players[anim_name]
	if backwards:
		player.play_backwards(anim_name)
	else:
		player.play(anim_name)
	player.animation_finished.connect(func(_name: StringName) -> void: done.call(), CONNECT_ONE_SHOT)


## Rejoue les pistes tracks de anim de from_s à to_s (à l'envers si to_s < from_s) en duration secondes.
func play_tracks(anim: Animation, tracks: Array[int], from_s: float, to_s: float, duration: float) -> Tween:
	var targets: Array[Node3D] = []
	for t in tracks:
		targets.append(root.get_node_or_null(anim.track_get_path(t)) as Node3D)
	var tween := root.create_tween()
	tween.tween_method(func(time: float) -> void:
		for i in tracks.size():
			if targets[i]:
				apply_track(anim, tracks[i], targets[i], time), from_s, to_s, duration)
	return tween


## Nœud visé par la piste (chemin relatif à la racine), ou null.
func track_target(anim: Animation, track: int) -> Node3D:
	return root.get_node_or_null(anim.track_get_path(track)) as Node3D


## Charnière tournée de son angle courant vers target en duration secondes (sinusoïdale), puis done ; le Tween est
## rendu (à tuer si une demande inverse arrive avant la fin).
func tween_hinge(hinge: Node3D, target: Quaternion, duration: float, done: Callable) -> Tween:
	var start := hinge.quaternion
	var tween := root.create_tween()
	tween.tween_method(func(w: float) -> void: hinge.quaternion = start.slerp(target, w), 0.0, 1.0,
			duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(done)
	return tween


## Angles de début et de fin et durée de la piste de rotation d'une charnière dans une animation.
class HingeRange:
	## Faux si l'animation n'a pas de piste pour cette charnière (angles figés à sa pose actuelle).
	var animated := false
	var start := Quaternion.IDENTITY
	var end := Quaternion.IDENTITY
	var duration := 0.0


## Angles et durée de la piste de rotation de la charnière dans l'animation (sa pose actuelle, durée nulle, sans piste).
func hinge_range(anim: Animation, hinge: Node3D) -> HingeRange:
	var range := HingeRange.new()
	var track := track_for(anim, hinge.name)
	if track < 0:
		range.start = hinge.quaternion
		range.end = hinge.quaternion
		return range
	var keys := anim.track_get_key_count(track)
	range.animated = true
	range.start = anim.track_get_key_value(track, 0)
	range.end = anim.track_get_key_value(track, keys - 1)
	range.duration = maxf(anim.track_get_key_time(track, keys - 1) - anim.track_get_key_time(track, 0), 0.1)
	return range



## Nombre de charnières animées par l'animation (pistes de rotation).
func animated_count(anim_name: StringName) -> int:
	var anim := animation(anim_name)
	if anim == null:
		return 0
	var count := 0
	for t in anim.get_track_count():
		count += 1 if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D else 0
	return count


## Pose le nœud à l'instant time de la piste (rotation, position ou échelle).
static func apply_track(anim: Animation, track: int, node: Node3D, time: float) -> void:
	match anim.track_get_type(track):
		Animation.TYPE_ROTATION_3D:
			node.quaternion = anim.rotation_track_interpolate(track, time)
		Animation.TYPE_POSITION_3D:
			node.position = anim.position_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			node.scale = anim.scale_track_interpolate(track, time)


## Piste de l'animation pour le nœud node_path (et du type donné, -1 : n'importe lequel), ou -1.
static func track_for(anim: Animation, node_path: String, type := -1) -> int:
	for t in anim.get_track_count():
		if String(anim.track_get_path(t)) == node_path and (type < 0 or anim.track_get_type(t) == type):
			return t
	return -1


## Instant du relais vers le vol (MissileFlight) dans Lancement_Missile : la dernière clé à pleine échelle avant que
## le missile ne s'annule (fin de la ligne droite Blender, ~30 m sous la station), pour ne jamais le voir rétrécir.
static func handoff_time(anim: Animation, scale_track: int) -> float:
	if scale_track < 0:
		return anim.length
	for k in anim.track_get_key_count(scale_track):
		if (anim.track_get_key_value(scale_track, k) as Vector3).x < 1e-3:
			if k > 0 and (anim.track_get_key_value(scale_track, k - 1) as Vector3).x > 0.999:
				return anim.track_get_key_time(scale_track, k - 1)
			return anim.track_get_key_time(scale_track, k)
	return anim.length
