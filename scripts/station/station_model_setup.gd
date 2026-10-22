class_name StationModelSetup
extends RefCounted
## Préparation du modèle Blender de la station au chargement (fonctions statiques, appelées par Station._ready) :
## - calques intérieurs : un maillage entièrement intérieur passe sur Station.INTERIOR_LAYER (éclairé par les lampes
##   intérieures seulement) ; un maillage mixte (coques : surfaces Coque_Silo dehors, Int_Coque dedans) est doublé :
##   l'original ne garde que ses surfaces extérieures, la copie (même maillage, LOD compris, sans ombre portée) ses
##   surfaces intérieures, sur INTERIOR_LAYER ; vitrages (Hublot, Vitrage) des deux côtés, vitrage de la cupola mat ;
## - collisions : parois (« -col », formes concaves) bloquantes des deux côtés ; objets Interactif_* sans collision
##   (tubes des silos, consoles, caisses, couchette…) : forme convexe simplifiée, normalement dès l'import
##   (tools/import/station_import.gd, ~3,5 s), refaite ici seulement pour un objet qui n'en aurait pas ;
## - corps de collision des portes (fit_door_collision), appelé par StationHatches et StationSilos.

## Matériaux des surfaces intérieures d'un maillage mixte, et des vitrages vus des deux côtés.
const INTERIOR_MATERIALS: Array[String] = ["Int_", "Ecran_"]
const BOTH_SIDES_MATERIALS: Array[String] = ["Hublot", "Vitrage"]
## Matériau qui fait disparaître une surface (sommets rejetés hors du champ) sans toucher au maillage partagé.
const HIDDEN_SHADER := "shader_type spatial;\nrender_mode unshaded, skip_vertex_transform;\nvoid vertex() {\n\tPOSITION = vec4(0.0, 0.0, 2.0, 1.0);\n}\n"


## Calques intérieurs puis collisions, dans cet ordre (les copies intérieures n'ont pas de collision propre).
static func prepare(station: Node3D) -> void:
	split_interior_layers(station)
	add_interior_collisions(station)


static func split_interior_layers(station: Node3D) -> void:
	var hidden := ShaderMaterial.new()
	hidden.shader = Shader.new()
	hidden.shader.code = HIDDEN_SHADER
	for mesh_instance: MeshInstance3D in station.find_children("*", "MeshInstance3D", true, false):
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
			mesh_instance.layers |= Station.INTERIOR_LAYER
		elif not interior.is_empty():
			var inside := MeshInstance3D.new()
			inside.name = String(mesh_instance.name) + "_Interieur"
			inside.mesh = mesh_instance.mesh
			inside.layers = mesh_instance.layers | Station.INTERIOR_LAYER
			inside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in exterior:
				inside.set_surface_override_material(s, hidden)
			for s in interior:
				mesh_instance.set_surface_override_material(s, hidden)
			mesh_instance.add_child(inside)


static func add_interior_collisions(station: Node3D) -> void:
	# Parois (« -col », formes concaves) : collision des deux côtés. Par défaut une face ne bloque que du côté où pointe
	# sa normale ; vue de l'intérieur d'une coque (normales vers l'extérieur), on la traverserait.
	for collision: CollisionShape3D in station.find_children("*", "CollisionShape3D", true, false):
		if collision.shape is ConcavePolygonShape3D:
			(collision.shape as ConcavePolygonShape3D).backface_collision = true
	for mesh_instance: MeshInstance3D in station.find_children("Interactif_*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null or mesh_instance.get_children().any(func(c: Node) -> bool:
				return c is CollisionObject3D):
			continue
		var shape := mesh_instance.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Collision"
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		mesh_instance.add_child(body)


## Corps de collision d'une porte (AnimatableBody3D tiré du nœud Blender « -convcolonly », enfant de la porte) : avec
## sync_to_physics, il ne suit que ses propres déplacements, pas ceux de la charnière parente, et restait figé dans la
## pose de l'import (porte fermée traversable, porte ouverte qui bloque encore le passage et le clic). Sans
## sync_to_physics, il suit la porte à chaque image (et pousse toujours l'observateur).
static func fit_door_collision(door: Node) -> void:
	for body in door.get_children():
		if body is AnimatableBody3D:
			(body as AnimatableBody3D).sync_to_physics = false


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
