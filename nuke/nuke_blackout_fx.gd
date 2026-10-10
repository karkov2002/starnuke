class_name NukeBlackoutFX
extends Node
## Rendu du black-out électrique, créé par NukeLauncher (nœud BlackoutFX). Voir NukeScaling (constantes BLACKOUT_*)
## pour les trois couches : zone détruite, panne régionale en cascade, panne nationale (décidée au tir par
## NukeGridImpact, NukeEffect.grid).
##
## À chaque image, il alimente les uniforms nuke_blackout_* des matériaux de la Terre qui les déclarent (sol, cf.
## nuke/shaders/nuke_blackout.gdshaderinc) : les MAX_EVENTS explosions les plus récentes et les MAX_COUNTRIES pannes
## nationales les plus récentes. Le shader n'éteint que les lumières des villes : de jour, rien ne se voit.

const MAX_EVENTS := 16
const MAX_COUNTRIES := 8
const COUNTRY_IDS := preload("res://assets/textures/country_ids.png")

var _launcher: NukeLauncher
var _materials: Array[ShaderMaterial] = []
var _was_active := false


func setup(launcher: NukeLauncher, earth: Node3D) -> void:
	_launcher = launcher
	_materials = NukeFXMaterials.find(earth, &"nuke_blackout_count")
	for material in _materials:
		material.set_shader_parameter("nuke_country_ids", COUNTRY_IDS)
		# Durées : une seule source, NukeScaling.
		material.set_shader_parameter("nuke_blackout_cascade_tau_s", NukeScaling.BLACKOUT_CASCADE_TAU_S)
		material.set_shader_parameter("nuke_blackout_restore_s", Vector2(NukeScaling.BLACKOUT_RESTORE_START_S,
				NukeScaling.BLACKOUT_RESTORE_END_S))
		material.set_shader_parameter("nuke_blackout_national_off_s", NukeScaling.BLACKOUT_NATIONAL_OFF_S)
		material.set_shader_parameter("nuke_blackout_national_restore_s", Vector2(
				NukeScaling.BLACKOUT_NATIONAL_RESTORE_START_S, NukeScaling.BLACKOUT_NATIONAL_RESTORE_END_S))


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var events: Array[Dictionary] = []
	var countries: Array[Dictionary] = []
	for effect in _launcher.get_effects():
		var t := effect.get_time_s()
		if t <= 0.0:
			continue
		var params := effect.params
		events.append({
			"pos": effect.position / OrbitSimulation.SCENE_UNITS_PER_KM,
			"t": t,
			"b": Vector4(NukeScaling.blackout_destroyed_km(params.yield_kt, params.burst_height_km),
					NukeScaling.blackout_region_km(params.yield_kt, params.burst_height_km), 0.0, 0.0),
		})
		if not effect.grid.is_empty() and effect.grid.national >= 0:
			countries.append({"id": effect.grid.national + 1, "t": t})
	if events.is_empty() and countries.is_empty() and not _was_active:
		return
	_was_active = not events.is_empty() or not countries.is_empty()
	# Les plus récentes d'abord.
	events.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)
	countries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)

	var a := PackedVector4Array()
	var b := PackedVector4Array()
	a.resize(MAX_EVENTS)
	b.resize(MAX_EVENTS)
	var count := mini(events.size(), MAX_EVENTS)
	for i in count:
		var pos: Vector3 = events[i].pos
		a[i] = Vector4(pos.x, pos.y, pos.z, events[i].t)
		b[i] = events[i].b
	var ids := PackedInt32Array()
	var times := PackedFloat32Array()
	ids.resize(MAX_COUNTRIES)
	times.resize(MAX_COUNTRIES)
	var country_count := mini(countries.size(), MAX_COUNTRIES)
	for i in country_count:
		ids[i] = countries[i].id
		times[i] = countries[i].t
	for material in _materials:
		material.set_shader_parameter("nuke_blackout_count", count)
		material.set_shader_parameter("nuke_blackout_a", a)
		material.set_shader_parameter("nuke_blackout_b", b)
		material.set_shader_parameter("nuke_blackout_country_count", country_count)
		material.set_shader_parameter("nuke_blackout_country", ids)
		material.set_shader_parameter("nuke_blackout_country_time", times)
