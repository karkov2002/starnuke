class_name NukeBlackout
extends Node
## Black-out électrique des explosions, créé par NukeLauncher (nœud BlackoutFX). Voir NukeScaling (constantes
## BLACKOUT_*) pour les trois couches : zone détruite, panne régionale en cascade, panne nationale.
##
## Au tir, assess() cherche les centrales détruites (PowerPlants, rayon de BLACKOUT_PLANT_PSI) et décide d'une panne
## nationale. À chaque image, le nœud alimente les uniforms nuke_blackout_* des matériaux de la Terre qui les
## déclarent (sol, cf. nuke/shaders/nuke_blackout.gdshaderinc) : les MAX_EVENTS explosions les plus récentes et les
## MAX_COUNTRIES pannes nationales les plus récentes. Le shader n'éteint que les lumières des villes : de jour, rien
## ne se voit.

const MAX_EVENTS := 16
const MAX_COUNTRIES := 8
const COUNTRY_IDS := preload("res://assets/textures/country_ids.png")

var _launcher: NukeLauncher
var _materials: Array[ShaderMaterial] = []
var _was_active := false


## Bilan électrique d'une explosion : {plants : [{name, fuel, capacity_mw, country}] détruites (de la plus puissante
## à la moins puissante), lost_mw, country_index (pays du point zéro, -1 en mer), country_capacity_mw, share (part de
## la capacité du pays perdue), national (indice du pays plongé dans le noir, -1 sinon)}.
static func assess(params: NukeParams) -> Dictionary:
	var result := {"plants": [], "lost_mw": 0.0, "country_index": -1, "country_capacity_mw": 0.0, "share": 0.0,
			"national": -1}
	var plants := PowerPlants.get_plants()
	var mask := CountryMask.get_mask()
	if plants == null or mask == null:
		return result
	var radius := NukeScaling.overpressure_range_km(params.yield_kt, NukeScaling.BLACKOUT_PLANT_PSI, params.burst_height_km)
	var lost_by_country := {}
	var hit: Array[Dictionary] = []
	for i in plants.within(params.latitude_deg, params.longitude_deg, radius):
		var country := plants.countries[i]
		hit.append({"name": plants.names[i], "fuel": plants.fuels[i], "capacity_mw": plants.capacities_mw[i],
				"country": country})
		lost_by_country[country] = lost_by_country.get(country, 0.0) + plants.capacities_mw[i]
		result.lost_mw += plants.capacities_mw[i]
	hit.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.capacity_mw > b.capacity_mw)
	result.plants = hit
	# Pays : celui du point zéro, à défaut (en mer, près d'une côte) celui qui perd le plus de capacité.
	var index := mask.index_at_row(CountryMask._row_of(params.latitude_deg), wrapf(params.longitude_deg, -180.0, 180.0))
	if index < 0:
		for country: int in lost_by_country:
			if country >= 0 and (index < 0 or lost_by_country[country] > lost_by_country[index]):
				index = country
	result.country_index = index
	if index >= 0:
		var capacity := plants.country_capacity_mw[index]
		result.country_capacity_mw = capacity
		result.share = lost_by_country.get(index, 0.0) / capacity if capacity > 0.0 else 0.0
		if result.share >= NukeScaling.BLACKOUT_NATIONAL_SHARE:
			result.national = index
	return result


## Résumé lisible (console).
static func format_report(result: Dictionary) -> String:
	var plants: Array = result.plants
	if plants.is_empty():
		return "  réseau électrique : aucune centrale recensée détruite"
	var names: Array[String] = []
	for plant: Dictionary in plants.slice(0, 3):
		names.append("%s (%s, %d MW)" % [plant.name, plant.fuel, roundi(plant.capacity_mw)])
	var line := "  réseau électrique : %d centrale(s) détruite(s), %d MW : %s%s" % [plants.size(), roundi(result.lost_mw),
			", ".join(names), "…" if plants.size() > 3 else ""]
	if result.country_index >= 0 and result.country_capacity_mw > 0.0:
		var mask := CountryMask.get_mask()
		var country_name: String = mask.countries[result.country_index].name_fr
		line += "\n    %s perd %s %% de sa capacité (%d MW)" % [country_name, ("%.1f" % (100.0 * result.share)).replace(".", ","),
				roundi(result.country_capacity_mw)]
		if result.national >= 0:
			line += " : black-out national"
	return line


func setup(launcher: NukeLauncher, earth: Node3D) -> void:
	_launcher = launcher
	for child in earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			var material := geometry.material_override as ShaderMaterial
			if material.shader and material.shader.get_shader_uniform_list().any(
					func(u: Dictionary) -> bool: return u.name == "nuke_blackout_count"):
				material.set_shader_parameter("nuke_country_ids", COUNTRY_IDS)
				# Durées : une seule source, NukeScaling.
				material.set_shader_parameter("nuke_blackout_cascade_tau_s", NukeScaling.BLACKOUT_CASCADE_TAU_S)
				material.set_shader_parameter("nuke_blackout_restore_s", Vector2(NukeScaling.BLACKOUT_RESTORE_START_S,
						NukeScaling.BLACKOUT_RESTORE_END_S))
				material.set_shader_parameter("nuke_blackout_national_off_s", NukeScaling.BLACKOUT_NATIONAL_OFF_S)
				material.set_shader_parameter("nuke_blackout_national_restore_s", Vector2(
						NukeScaling.BLACKOUT_NATIONAL_RESTORE_START_S, NukeScaling.BLACKOUT_NATIONAL_RESTORE_END_S))
				_materials.append(material)


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var events: Array[Dictionary] = []
	var countries: Array[Dictionary] = []
	for effect in _launcher.get_effects():
		var t := effect.get_time_s()
		if t <= 0.0 or effect.blackout.is_empty():
			continue
		var params := effect.params
		events.append({
			"a": Vector4(0, 0, 0, t),
			"pos": effect.position / OrbitSimulation.SCENE_UNITS_PER_KM,
			"b": Vector4(NukeScaling.blackout_destroyed_km(params.yield_kt, params.burst_height_km),
					NukeScaling.blackout_region_km(params.yield_kt, params.burst_height_km), 0.0, 0.0),
		})
		if effect.blackout.national >= 0:
			countries.append({"id": effect.blackout.national + 1, "t": t})
	if events.is_empty() and countries.is_empty() and not _was_active:
		return
	_was_active = not events.is_empty() or not countries.is_empty()
	# Les plus récentes d'abord.
	events.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.a.w < y.a.w)
	countries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.t < y.t)

	var a := PackedVector4Array()
	var b := PackedVector4Array()
	a.resize(MAX_EVENTS)
	b.resize(MAX_EVENTS)
	var count := mini(events.size(), MAX_EVENTS)
	for i in count:
		var pos: Vector3 = events[i].pos
		a[i] = Vector4(pos.x, pos.y, pos.z, events[i].a.w)
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
