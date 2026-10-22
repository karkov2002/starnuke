@tool
extends EditorScenePostImport
## Script de post-import de la station (assets/station/station_spatiale.glb, paramètre import_script/path de son
## .import). Il retouche la scène importée sans jamais modifier le .glb, réexporté depuis Blender avec les mêmes noms :
## - collisions des portes et trappes (nœuds Blender « -convcolonly », enfants d'une Charniere_* animée) : le corps
##   statique créé par Godot devient un AnimatableBody3D, qui suit le mouvement de la charnière et pousse ce qu'il
##   touche (un corps statique déplacé par une animation ne le fait pas).
## - animations : l'export Blender met dans chaque action tous les objets animés de la scène (73 pistes par
##   animation), avec des valeurs constantes pour ceux qu'elle ne concerne pas. Ces pistes constantes sont retirées :
##   sinon, jouer Lancement_Missile remettrait aussi en place les trappes, radiateurs et panneaux.
## - collisions des objets « Interactif_* » qui n'en ont pas (tubes des silos, consoles, caisses, portables, écrans…) :
##   forme convexe simplifiée (StaticBody3D « Collision » enfant), calculée ici une fois pour toutes ; au démarrage
##   du jeu (StationModelSetup.add_interior_collisions), ce calcul figeait l'écran ~3,5 s.
## Les autres réglages sont dans le .import : boucle des animations Rotation_Panneaux et Balayage_Antennes, LOD,
## collisions par suffixes, échelle 1.

## Préfixe des pivots animés (portes, trappes) : les corps de collision sous un tel pivot doivent suivre le mouvement.
const HINGE_PREFIX := "Charniere_"


func _post_import(scene: Node) -> Object:
	var converted := 0
	for body in scene.find_children("*", "StaticBody3D", true, false):
		if _has_hinge_ancestor(body):
			_to_animatable(body as StaticBody3D)
			converted += 1
	var removed := 0
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for anim_name in player.get_animation_list():
			removed += _remove_constant_tracks(player.get_animation(anim_name))
	var shaped := _add_interactive_collisions(scene)
	print("station_post_import : %d collision(s) de porte ou trappe en AnimatableBody3D, %d piste(s) constante(s) retirée(s), %d forme(s) convexe(s) d'objets interactifs"
			% [converted, removed, shaped])
	return scene


## StaticBody3D « Collision » (forme convexe simplifiée du maillage) sous chaque « Interactif_* » sans collision ;
## rend leur nombre.
func _add_interactive_collisions(scene: Node) -> int:
	var count := 0
	for mesh_instance: MeshInstance3D in scene.find_children("Interactif_*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null or mesh_instance.get_children().any(func(c: Node) -> bool:
				return c is CollisionObject3D):
			continue
		var shape := mesh_instance.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Collision"
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = shape
		body.add_child(collision)
		mesh_instance.add_child(body)
		body.owner = scene
		collision.owner = scene
		count += 1
	return count


## Retire les pistes dont toutes les clés ont la même valeur ; rend leur nombre.
func _remove_constant_tracks(anim: Animation) -> int:
	var removed := 0
	for t in range(anim.get_track_count() - 1, -1, -1):
		var first: Variant = anim.track_get_key_value(t, 0) if anim.track_get_key_count(t) > 0 else null
		var constant := true
		for k in range(1, anim.track_get_key_count(t)):
			if not _same(anim.track_get_key_value(t, k), first):
				constant = false
				break
		if constant:
			anim.remove_track(t)
			removed += 1
	return removed


func _same(a: Variant, b: Variant) -> bool:
	match typeof(a):
		TYPE_QUATERNION:
			return (a as Quaternion).is_equal_approx(b)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b)
		TYPE_FLOAT:
			return is_equal_approx(a, b)
	return a == b


func _has_hinge_ancestor(node: Node) -> bool:
	var parent := node.get_parent()
	while parent:
		if String(parent.name).begins_with(HINGE_PREFIX):
			return true
		parent = parent.get_parent()
	return false


## Remplace body par un AnimatableBody3D de même nom, transformée, calques et formes (enfants déplacés).
func _to_animatable(body: StaticBody3D) -> void:
	var animatable := AnimatableBody3D.new()
	animatable.name = body.name
	animatable.transform = body.transform
	animatable.collision_layer = body.collision_layer
	animatable.collision_mask = body.collision_mask
	for key in body.get_meta_list():
		animatable.set_meta(key, body.get_meta(key))
	var parent := body.get_parent()
	var owner_node := body.owner
	var index := body.get_index()
	var children := body.get_children()
	# Ancien corps retiré d'abord : son nom doit être libre pour le nouveau.
	for child in children:
		body.remove_child(child)
	parent.remove_child(body)
	parent.add_child(animatable)
	parent.move_child(animatable, index)
	animatable.owner = owner_node
	for child in children:
		animatable.add_child(child)
		child.owner = owner_node
	body.free()
