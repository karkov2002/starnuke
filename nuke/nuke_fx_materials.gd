class_name NukeFXMaterials
extends RefCounted
## Recherche des matériaux de la Terre (sol, nuages, atmosphère : material_override des enfants du nœud Earth) qui
## déclarent un uniform donné : c'est par eux que les nœuds d'effets (NukeFlashFX, NukeFireFX, NukeCloudFX,
## NukeBlackoutFX) transmettent les explosions aux shaders.


## Matériaux des enfants de earth dont le shader déclare l'uniform uniform_name.
static func find(earth: Node3D, uniform_name: StringName) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for child in earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry == null or not geometry.material_override is ShaderMaterial:
			continue
		var material := geometry.material_override as ShaderMaterial
		if material.shader and material.shader.get_shader_uniform_list().any(
				func(u: Dictionary) -> bool: return u.name == uniform_name):
			result.append(material)
	return result
