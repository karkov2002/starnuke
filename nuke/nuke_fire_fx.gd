class_name NukeFireFX
extends Node
## Incendies des explosions, créé par NukeLauncher. À chaque image, il calcule pour chaque NukeEffect le rayon et
## l'intensité de la zone en feu (NukeScaling.fire_radius_km, fire_intensity) et alimente les uniforms nuke_fire_*
## des matériaux de la Terre qui les déclarent (sol, cf. nuke/shaders/nuke_fire.gdshaderinc) : les MAX_FIRES
## incendies les plus intenses. Une explosion au large, sans terre à portée (NukeEffect.can_ignite_land), n'en allume
## aucun ; près d'une côte, le shader ne fait brûler que les terres.

const MAX_FIRES := 8

var _launcher: NukeLauncher
var _materials: Array[ShaderMaterial] = []
var _was_active := false


func setup(launcher: NukeLauncher, earth: Node3D) -> void:
	_launcher = launcher
	for child in earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			var material := geometry.material_override as ShaderMaterial
			if material.shader and material.shader.get_shader_uniform_list().any(
					func(u: Dictionary) -> bool: return u.name == "nuke_fire_count"):
				_materials.append(material)


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var fires: Array[Dictionary] = []
	for effect in _launcher.get_effects():
		if not effect.can_ignite_land():
			continue
		var t := effect.get_time_s()
		var intensity := NukeScaling.fire_intensity(t)
		if intensity > 0.001:
			fires.append({
				"pos": effect.position / OrbitSimulation.SCENE_UNITS_PER_KM,
				"radius": NukeScaling.fire_radius_km(effect.params.yield_kt, t),
				"intensity": intensity,
			})
	if fires.is_empty() and not _was_active:
		return
	_was_active = not fires.is_empty()
	fires.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.intensity > b.intensity)

	var positions := PackedVector3Array()
	var radii := PackedFloat32Array()
	var intensities := PackedFloat32Array()
	positions.resize(MAX_FIRES)
	radii.resize(MAX_FIRES)
	intensities.resize(MAX_FIRES)
	var count := mini(fires.size(), MAX_FIRES)
	for i in count:
		positions[i] = fires[i].pos
		radii[i] = fires[i].radius
		intensities[i] = fires[i].intensity
	for material in _materials:
		material.set_shader_parameter("nuke_fire_count", count)
		material.set_shader_parameter("nuke_fire_pos_km", positions)
		material.set_shader_parameter("nuke_fire_radius_km", radii)
		material.set_shader_parameter("nuke_fire_intensity", intensities)
