class_name NukeCloudFX
extends Node
## Trous creusés dans la couche nuageuse par les explosions, créé par NukeLauncher. À chaque image, il décrit chaque
## NukeEffect encore visible dans les nuages et alimente les uniforms nuke_cloud_* des matériaux de la Terre qui les
## déclarent (nuages et sol, via shaders/cloud_density.gdshaderinc ; cf. nuke/shaders/nuke_clouds.gdshaderinc) : les
## MAX_EVENTS explosions les plus récentes.
##
## Un événement = deux Vector4 (soit deux texels RGBA32F) :
##   a = (centre en km dans le repère de la planète, rayon courant du trou en km),
##   b = (rayon final du trou en km, constante de temps τ de son ouverture en s, temps physique écoulé en s,
##   puissance en kt). Rayon et τ : ceux du front de choc (NukeScaling.shock_*), qui pousse les nuages devant lui,
##   comme l'anneau de condensation qu'il porte (NukeShock).
## Le centre dérive avec le vent du point d'impact (NukeParams, vent réel GFS) : le trou suit la masse d'air, comme
## les nuages qui l'entourent (même champ de vent que leur advection).
## L'envoi est isolé dans _upload() : pour passer à une texture de données (Image FORMAT_RGBAF, 2 × MAX_EVENTS), seul
## ce bloc et nuke_cloud_event() du shader changent.

const MAX_EVENTS := 16

## Durée de retour des nuages dans le trou (s, temps physique de l'explosion ; 1 200 s ≈ 2 min d'horloge après
## l'accélération). Le bord se referme plus vite que le centre (nuke_cloud_edge_fill du matériau).
@export var recovery_s := 1200.0

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
					func(u: Dictionary) -> bool: return u.name == "nuke_cloud_count"):
				_materials.append(material)


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var events: Array[Dictionary] = []
	for effect in _launcher.get_effects():
		var event := _describe(effect)
		if not event.is_empty():
			events.append(event)
	if events.is_empty() and not _was_active:
		return
	_was_active = not events.is_empty()
	# Les plus récentes d'abord.
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.b.z < b.b.z)
	_upload(events.slice(0, MAX_EVENTS))


## Événement d'une explosion, ou {} si elle n'a pas encore eu lieu ou si les nuages sont revenus.
func _describe(effect: NukeEffect) -> Dictionary:
	var params := effect.params
	var t := effect.get_time_s()
	var tau := NukeScaling.shock_tau_s(params.yield_kt)
	# Le trou est refermé partout après son ouverture complète (~4 τ) et recovery_s.
	if t <= 0.0 or t > recovery_s + 4.0 * tau:
		return {}
	var units := OrbitSimulation.SCENE_UNITS_PER_KM
	var basis := effect.transform.basis
	var east := basis.x.normalized()
	var north := -basis.z.normalized()
	# Vent : la direction est celle d'où il vient (convention météo), l'air va à l'opposé.
	var from := deg_to_rad(params.wind_direction_deg)
	var drift_km := -(east * sin(from) + north * cos(from)) * (params.wind_speed_m_s * t / 1000.0)
	var center := (effect.position / units + drift_km).normalized() * OrbitSimulation.EARTH_RADIUS_KM
	return {
		"a": Vector4(center.x, center.y, center.z, NukeScaling.shock_front_radius_km(params.yield_kt, t)),
		"b": Vector4(NukeScaling.shock_max_radius_km(params.yield_kt), tau, t, params.yield_kt),
	}


func _upload(events: Array[Dictionary]) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	a.resize(MAX_EVENTS)
	b.resize(MAX_EVENTS)
	for i in events.size():
		a[i] = events[i].a
		b[i] = events[i].b
	for material in _materials:
		material.set_shader_parameter("nuke_cloud_count", events.size())
		material.set_shader_parameter("nuke_cloud_a", a)
		material.set_shader_parameter("nuke_cloud_b", b)
		material.set_shader_parameter("nuke_cloud_recovery_s", recovery_s)
