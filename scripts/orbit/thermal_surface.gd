class_name ThermalSurface
extends MeshInstance3D
## Surface de la Terre en infrarouge thermique (shaders/earth_thermal.gdshader), vue seulement par la caméra nadir de la
## tablette en mode IR (NadirCamera.infrared). Enfant du nœud Earth, à côté de Surface : à son entrée dans l'arbre
## (avant tout _ready), elle reprend le maillage de Surface et une copie de son matériau (textures, nuages, réglages)
## avec le shader thermique ; les nœuds qui alimentent les matériaux de la Terre (EarthSceneDriver : soleil ; tuiles
## HD ; explosions : NukeFXMaterials) la trouvent donc comme les autres. Sur son propre calque (LAYER), retiré de la
## caméra de la vue, et cachée hors du mode IR : rien n'est dessiné en temps normal.

const LAYER := 1 << 16
const SHADER := preload("res://shaders/earth_thermal.gdshader")

@export var surface_path: NodePath = ^"../Surface"


func _enter_tree() -> void:
	if material_override:
		return
	var surface := get_node_or_null(surface_path) as MeshInstance3D
	if surface == null or not surface.material_override is ShaderMaterial:
		push_error("ThermalSurface : surface %s introuvable" % surface_path)
		return
	mesh = surface.mesh
	var material := surface.material_override.duplicate() as ShaderMaterial
	material.shader = SHADER
	material_override = material
	layers = LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _ready() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		camera.cull_mask &= ~LAYER
