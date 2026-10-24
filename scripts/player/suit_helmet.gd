class_name SuitHelmet
extends Node3D
## Casque de la combinaison, vu de l'intérieur (nœud Observer/Camera/Helmet de scenes/orbit_view.tscn) : visible tant
## que la combinaison du sas est portée (Station.suit_changed), il suit la tête (enfant de la caméra).
## Maillage généré ici (pas de modèle Blender : une sphère percée d'une fenêtre, dimensionnée sur le champ de vue) :
## - coque intérieure noire mate (sphère de radius_m, centrée center_offset derrière l'œil, comme la tête dans un vrai
##   casque) ; elle encadre la vue : bande en haut, bords sur les côtés, coins arrondis ;
## - fenêtre : ellipse dans le plan de la vue (ronde à l'écran comme vue de l'extérieur, bord haut en dôme : au ras du
##   haut de l'image au centre, descendant sur les côtés), demi-axes ±window_half_width_deg, +window_top_deg /
##   −window_bottom_deg vus de l'œil ; assez large pour la tablette sortie (bas à droite de la vue), qui se tient
##   derrière la visière, à ~15 cm de l'œil ;
## - joint gris foncé au bord de la fenêtre ;
## - visière transparente (shaders/helmet_visor.gdshader : voile teinté vers les bords, Fresnel) et ses reflets en arc
##   (passe additive shaders/helmet_visor_glint.gdshader : en haut à gauche, plus faible en bas à droite).
## Rien ne porte d'ombre ni ne bloque les clics (aucune collision) ; éclairé comme l'habitacle (Station.INTERIOR_LAYER).

const VISOR_SHADER := preload("res://shaders/helmet_visor.gdshader")
const GLINT_SHADER := preload("res://shaders/helmet_visor_glint.gdshader")

## Rayon de la coque (m) et position de son centre par rapport à l'œil (repère de la caméra : −Z vers l'avant).
@export var radius_m := 0.165
@export var center_offset := Vector3(0.0, -0.02, 0.07)
## Fenêtre : ellipse dans le plan de la vue (bord ronde à l'écran, bord haut en dôme), donnée par ses demi-axes en
## angles vus de l'œil depuis l'axe du regard (degrés) ; demi-ellipses différentes en haut et en bas.
@export var window_half_width_deg := 59.0
@export var window_top_deg := 37.0
@export var window_bottom_deg := 46.0
## Largeur du joint (part du rayon de la fenêtre).
@export var seal_width := 0.045
## Plan de coupure proche de la caméra (m) tant que le casque est porté. La coque passe à ~4 cm devant l'œil vers 70°
## de l'axe du regard : avec le plan par défaut (5 cm), elle était coupée sur les côtés d'un écran ultra-large (32:9,
## bord de l'image à 70° pour un champ vertical de 75°) et la station apparaissait au bord. À 1,5 cm, la coque reste
## entière jusqu'à ~80° (profondeur inversée de Godot : sans perte de précision au loin).
@export var helmet_near_m := 0.015

var _station: Station
var _camera: Camera3D
## Plan proche de la caméra sans le casque (rétabli quand on l'ôte).
var _default_near := 0.05


func _ready() -> void:
	visible = false
	_camera = get_parent() as Camera3D
	if _camera:
		_default_near = _camera.near
	_build()
	_connect_station.call_deferred()


func _connect_station() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return
	_station.suit_changed.connect(_on_suit_changed)
	_on_suit_changed(_station.is_suit_worn())


func _on_suit_changed(worn: bool) -> void:
	visible = worn
	if _camera:
		_camera.near = minf(helmet_near_m, _default_near) if worn else _default_near


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.018, 0.018, 0.02)
	shell.roughness = 0.75
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var seal := StandardMaterial3D.new()
	seal.albedo_color = Color(0.09, 0.09, 0.1)
	seal.roughness = 0.45
	seal.metallic = 0.6
	seal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var visor := ShaderMaterial.new()
	visor.shader = VISOR_SHADER
	visor.next_pass = ShaderMaterial.new()
	(visor.next_pass as ShaderMaterial).shader = GLINT_SHADER
	# r : distance au centre de la fenêtre (1 : son bord) ; la coque va jusqu'à r = 14 (~87° de l'axe du regard,
	# au-delà de tout champ de vue), ses rangées resserrées près du joint.
	_add_part("Visiere", 0.0, 1.0, 12, visor, 0.004, 1.0)
	_add_part("Joint", 1.0, 1.0 + seal_width, 2, seal, 0.006, 1.0)
	_add_part("Coque", 1.0 + seal_width, 14.0, 32, shell, 0.0, 2.0)


## Anneau de la fenêtre entre r0 et r1 (rings rangées réparties selon t^spacing, 128 secteurs), rapproché de l'œil
## de inset_m. Fenêtre ellipse dans le plan z = −1 de la caméra : point (X, Y) = r·(cos θ·a, sin θ·b).
func _add_part(part_name: String, r0: float, r1: float, rings: int, material: Material, inset_m: float,
		spacing: float) -> void:
	const SECTORS := 128
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_width := tan(deg_to_rad(window_half_width_deg))
	var top := tan(deg_to_rad(window_top_deg))
	var bottom := tan(deg_to_rad(window_bottom_deg))
	for i in rings + 1:
		var r := lerpf(r0, r1, pow(float(i) / rings, spacing))
		for k in SECTORS + 1:
			var theta := TAU * k / SECTORS
			var uv := Vector2(cos(theta), sin(theta)) * r
			var plane := Vector2(uv.x * half_width, uv.y * (top if uv.y > 0.0 else bottom))
			var point := _on_shell(Vector3(plane.x, plane.y, -1.0).normalized(), radius_m - inset_m)
			vertices.append(point)
			normals.append((center_offset - point).normalized())   # vers l'intérieur : la face vue
			uvs.append(uv)
	for i in rings:
		for k in SECTORS:
			var a := i * (SECTORS + 1) + k
			var b := a + SECTORS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers |= Station.INTERIOR_LAYER
	# Collé à l'œil : jamais hors du champ ni coupé par l'occlusion.
	instance.extra_cull_margin = 1.0
	add_child(instance)


## Point de la sphère (centre center_offset, rayon radius) vu de l'œil dans la direction d (unitaire).
func _on_shell(d: Vector3, radius: float) -> Vector3:
	var b := d.dot(center_offset)
	return d * (b + sqrt(b * b - center_offset.length_squared() + radius * radius))
