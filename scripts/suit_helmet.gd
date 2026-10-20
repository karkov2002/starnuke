class_name SuitHelmet
extends Node3D
## Casque de la combinaison, vu de l'intérieur (nœud Observer/Camera/Helmet de scenes/orbit_view.tscn) : visible tant
## que la combinaison du sas est portée (Station.suit_changed), il suit la tête (enfant de la caméra).
## Maillage généré ici (pas de modèle Blender : une sphère percée d'une fenêtre, dimensionnée sur le champ de vue) :
## - coque intérieure noire mate (sphère de radius_m, centrée center_offset derrière l'œil, comme la tête dans un vrai
##   casque) ; elle encadre la vue : bande en haut, bords sur les côtés, coins arrondis ;
## - fenêtre : superellipse dans l'espace des angles vus de l'œil (azimut ±window_half_width_deg, élévation
##   +window_top_deg / −window_bottom_deg, exposant window_squareness) ; assez large pour la tablette sortie (bas à
##   droite de la vue), qui se tient derrière la visière, à ~15 cm de l'œil ;
## - joint gris foncé au bord de la fenêtre ;
## - visière transparente (shaders/helmet_visor.gdshader : voile teinté vers les bords, Fresnel) et ses reflets en arc
##   (passe additive shaders/helmet_visor_glint.gdshader : en haut à gauche, plus faible en bas à droite).
## Rien ne porte d'ombre ni ne bloque les clics (aucune collision) ; éclairé comme l'habitacle (Station.INTERIOR_LAYER).

const VISOR_SHADER := preload("res://shaders/helmet_visor.gdshader")
const GLINT_SHADER := preload("res://shaders/helmet_visor_glint.gdshader")

## Rayon de la coque (m) et position de son centre par rapport à l'œil (repère de la caméra : −Z vers l'avant).
@export var radius_m := 0.165
@export var center_offset := Vector3(0.0, -0.02, 0.07)
## Fenêtre, en angles vus de l'œil (degrés).
@export var window_half_width_deg := 56.0
@export var window_top_deg := 33.0
@export var window_bottom_deg := 48.0
@export var window_squareness := 2.6
## Largeur du joint (part du rayon de la fenêtre).
@export var seal_width := 0.045

var _station: Station


func _ready() -> void:
	visible = false
	_build()
	_connect_station.call_deferred()


func _connect_station() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return
	_station.suit_changed.connect(_on_suit_changed)
	visible = _station.is_suit_worn()


func _on_suit_changed(worn: bool) -> void:
	visible = worn


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
	# r : distance au centre de la fenêtre (1 : son bord) ; la coque va jusqu'à r = 4, derrière la tête.
	_add_part("Visiere", 0.0, 1.0, 12, visor, 0.004)
	_add_part("Joint", 1.0, 1.0 + seal_width, 2, seal, 0.006)
	_add_part("Coque", 1.0 + seal_width, 4.0, 24, shell, 0.0)


## Anneau de la fenêtre entre r0 et r1 (rings rangées, 96 secteurs), rapproché de l'œil de inset_m.
func _add_part(part_name: String, r0: float, r1: float, rings: int, material: Material, inset_m: float) -> void:
	const SECTORS := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var exponent := 2.0 / window_squareness
	for i in rings + 1:
		var r := lerpf(r0, r1, float(i) / rings)
		for k in SECTORS + 1:
			var theta := TAU * k / SECTORS
			var c := cos(theta)
			var s := sin(theta)
			var uv := Vector2(signf(c) * pow(absf(c), exponent), signf(s) * pow(absf(s), exponent)) * r
			var azimuth := clampf(uv.x * window_half_width_deg, -175.0, 175.0)
			var elevation := clampf(uv.y * (window_top_deg if uv.y > 0.0 else window_bottom_deg), -85.0, 85.0)
			var point := _on_shell(deg_to_rad(azimuth), deg_to_rad(elevation), radius_m - inset_m)
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


## Point de la sphère (centre center_offset, rayon radius) vu de l'œil dans la direction (azimut, élévation).
func _on_shell(azimuth: float, elevation: float, radius: float) -> Vector3:
	var d := Vector3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
	var b := d.dot(center_offset)
	return d * (b + sqrt(b * b - center_offset.length_squared() + radius * radius))
