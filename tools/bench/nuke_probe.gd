extends Node
## Sonde du code des explosions (lot 2, étape 6 de l'audit : la découpe de nuke/ ne doit rien changer au rendu ni aux
## bilans) : en headless, sans rendu, elle enregistre ce que le code remet aux shaders et aux bilans, et le compare à
## une référence prise avant la découpe (tools/bench/results/nuke_probe_reference.txt, var_to_str) :
## - bilans purs : pertes (NukeCasualties.estimate), retombées (NukeFallout.estimate), réseau (NukeGridImpact.assess),
##   fumée par m² (NukeSmokeYield.estimate) pour trois explosions (1 Mt au sol, 100 kt en mer, 50 Mt en altitude) ;
## - champignon : à chaque instant de TIMES_S (time_override_s), tous les uniforms des trois matériaux (Cloud,
##   BaseSurge, Volume), visibilités, boîte englobante, transformation du volume ;
## - sol (NukeGroundFX) : compteurs et contenu des textures de données (événements, mailles, index, fumée, pays) ;
## - séquence de tir (LaunchControl.fire_tube → station → MissileFlight → NukeLauncher) : explosion au point visé ;
## - panneau de debug construit et animé sans erreur.
## Usage :
##   godot --headless --path . res://tools/bench/nuke_probe.tscn            compare à la référence (code 0 si identique)
##   godot --headless --path . res://tools/bench/nuke_probe.tscn -- ref     (ré)écrit la référence

const ProbeCompare := preload("res://tools/bench/probe_compare.gd")
const REFERENCE := "res://tools/bench/results/nuke_probe_reference.txt"
const TIMES_S: Array[float] = [0.5, 30.0, 300.0, 900.0, 3600.0, 21600.0, 86400.0]
const GROUND_TIMES_S: Array[float] = [10.0, 3600.0, 86400.0, 259200.0]
## (latitude, longitude, puissance kt, hauteur km) : Tokyo au sol, Atlantique bas, région de Moscou en altitude.
const SHOTS: Array[Array] = [[35.68, 139.69, 1000.0, 0.0], [30.0, -40.0, 100.0, 0.5], [55.75, 37.6, 50000.0, 5.0]]
const CLOUD_UNIFORMS: Array[StringName] = [&"opacity", &"profile", &"stem_fraction", &"ring", &"roll_angle",
		&"rise_offset", &"boil", &"erosion", &"ground_fade", &"albedo", &"glow", &"local_to_planet_km",
		&"sun_dir_planet", &"drift_profile", &"drift_top"]
const SURGE_UNIFORMS: Array[StringName] = [&"profile", &"ring", &"roll_angle", &"boil", &"opacity", &"ground_fade",
		&"edge_erosion", &"albedo", &"glow", &"local_to_planet_km", &"sun_dir_planet", &"stem_fraction",
		&"drift_profile", &"drift_top"]
const VOLUME_UNIFORMS: Array[StringName] = [&"cap_center", &"cap_radius", &"cap_half", &"cap_under", &"stem_radius",
		&"neck_height", &"base_flare", &"base_flare_height", &"stem_erosion", &"surge_radius", &"surge_height",
		&"surge_density", &"ring", &"roll_angle", &"rise_offset", &"boil", &"fade", &"breakup", &"light_steps",
		&"warp_vertical", &"extinction", &"light_first_step", &"albedo", &"glow", &"sun_dir_planet", &"sun_dir_local",
		&"local_to_planet_km", &"local_to_world", &"world_to_local", &"seed", &"box_min", &"box_max", &"core_min",
		&"core_max", &"drift_profile", &"drift_top", &"noise_tex"]
const GROUND_UNIFORMS: Array[StringName] = [&"nuke_ground_count", &"nuke_smoke_count", &"nuke_ground_country_count",
		&"nuke_ground_events", &"nuke_ground_cells", &"nuke_ground_index", &"nuke_smoke_cells", &"nuke_smoke_index",
		&"nuke_ground_countries"]

var _failures := 0
var _record := {}


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


func _until(pred: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	var write_reference := OS.get_cmdline_user_args().has("ref")
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	await _frames(30)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	# Scène figée à une date fixe (soleil, Terre) : tout est rejouable.
	orbit.place(CampaignData.parse_utc("2035-07-15T06:00:00Z"), 400.0, 51.6, 40.4, -3.7, true)
	orbit.time_scale = 0.0
	await _frames(2)

	print("- Explosions")
	var effects: Array[NukeEffect] = []
	for shot in SHOTS:
		var params := NukeParams.new()
		params.latitude_deg = shot[0]
		params.longitude_deg = shot[1]
		params.yield_kt = shot[2]
		params.burst_height_km = shot[3]
		params.start_time_s = NukeClock.time_s
		launcher.call("_fill_place", params)
		effects.append(launcher.fire(params))
	_check(launcher.get_effects().size() == 3, "3 explosions")
	var ok := await _until(func() -> bool:
		return effects.all(func(e: NukeEffect) -> bool:
			return not e.impact_pending and not e.fallout_pending and e.smoke_yield_kg_m2 >= 0.0), 60.0)
	_check(ok, "bilans calculés (NukeImpact)")

	print("- Bilans")
	for i in effects.size():
		var p := effects[i].params
		var key := "shot%d" % i
		_record[key + "/params"] = {"over_ocean": p.over_ocean, "country": p.country_code,
				"wind_dir": p.wind_direction_deg, "wind_speed": p.wind_speed_m_s, "profile": p.wind_profile}
		var casualties := NukeCasualties.estimate(p)
		_record[key + "/casualties"] = _trim(casualties)
		_record[key + "/fallout"] = _trim(NukeFallout.estimate(p, casualties.radii_km))
		_record[key + "/grid"] = NukeGridImpact.assess(p)
		_record[key + "/smoke_yield"] = NukeSmokeYield.estimate(p)
		_record[key + "/effect"] = {"casualties": _trim(effects[i].casualties), "grid": effects[i].grid,
				"smoke": effects[i].smoke_yield_kg_m2, "fallout_countries": effects[i].fallout.get("countries", []).size()}
		print("  %s : %.0f morts, fumée %.3f kg/m², pays %s" % [key, casualties.killed, effects[i].smoke_yield_kg_m2,
				p.country_code])

	print("- Champignons")
	for t in TIMES_S:
		for effect in effects:
			effect.time_override_s = t
		await _frames(2)
		for i in effects.size():
			var mushroom := effects[i].get_node("Mushroom") as NukeMushroom
			var cloud := mushroom.get_node("Cloud") as MeshInstance3D
			var surge := mushroom.get_node("BaseSurge") as MeshInstance3D
			var volume := mushroom.get_node("Volume") as MeshInstance3D
			var key := "shot%d/t%s" % [i, t]
			_record[key + "/mushroom"] = {"visible": mushroom.visible, "scale": mushroom.scale,
					"cloud_visible": cloud.visible, "surge_visible": surge.visible, "volume_visible": volume.visible,
					"cloud_aabb": cloud.custom_aabb if not mushroom.volumetric else AABB(),
					"volume_transform": volume.transform}
			# Maillages (Cloud, BaseSurge) : relevés seulement en rendu par maillage ; en volumétrique (défaut), ils sont
			# invisibles et leurs uniforms ne sont plus posés (lot 3).
			if not mushroom.volumetric:
				_record[key + "/cloud"] = _uniforms(cloud.material_override as ShaderMaterial, CLOUD_UNIFORMS)
				_record[key + "/surge"] = _uniforms(surge.material_override as ShaderMaterial, SURGE_UNIFORMS)
			_record[key + "/volume"] = _uniforms(volume.material_override as ShaderMaterial, VOLUME_UNIFORMS)
	print("  %d instants × 3 champignons relevés" % TIMES_S.size())

	print("- Sol")
	var ground_materials := NukeFXMaterials.find(launcher.get_earth(), &"nuke_ground_count")
	_check(not ground_materials.is_empty(), "%d matériau(x) du sol" % ground_materials.size())
	for t in GROUND_TIMES_S:
		for effect in effects:
			effect.time_override_s = t
		await _frames(3)
		var key := "ground/t%s" % t
		_record[key] = _uniforms(ground_materials[0], GROUND_UNIFORMS) if not ground_materials.is_empty() else {}
		print("  t = %s s : %d explosion(s), %d panache(s), %d pays" % [t, _record[key].get("nuke_ground_count", -1),
				_record[key].get("nuke_smoke_count", -1), _record[key].get("nuke_ground_country_count", -1)])

	print("- Séquence de tir")
	await _check_launch(view, launcher)

	print("- Panneau de debug")
	var panel := DebugPanel.new()
	add_child(panel)
	await _frames(5)
	_check(panel.get_child_count() > 0 and panel.find_children("*", "NukeDebugSection", true, false).size() == 1
			and panel.find_children("*", "OrbitDebugSection", true, false).size() == 1, "panneau construit (3 sections)")
	panel.queue_free()

	print("- Référence")
	var result := ProbeCompare.check(_record, REFERENCE, write_reference)
	if result.written:
		print("  référence écrite : " + ProjectSettings.globalize_path(REFERENCE))
	elif result.missing:
		_check(false, "pas de référence (lancer avec -- ref)")
	else:
		for d: String in result.diffs.slice(0, 40):
			print("  ≠ " + d)
		_check(result.diffs.is_empty(), "identique à la référence (%d écart(s))" % result.diffs.size())
	print("=== %d échec(s) au total" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Tir par la commande de tir (LaunchControl.fire_tube, comme la tablette et le banc) : sortie du tube par la
## station, vol (MissileFlight), explosion au point visé avec la puissance choisie.
func _check_launch(view: Node, launcher: NukeLauncher) -> void:
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	# La commande de tir de la tablette (comme le banc) : une seule par partie, abonnée à la station.
	var control := view.find_child("Launch", true, false) as LaunchControl
	_check(control != null, "commande de tir de la tablette")
	if control == null:
		return
	var before := launcher.get_effects().size()
	var aim := launcher.aim_at(48.86, 2.35)
	_check(control.fire_tube(Vector2i(2, 5), aim, 300.0), "fire_tube accepté")
	_check(not control.fire_tube(Vector2i(2, 5), aim, 300.0), "tube vide : refus")
	var released := [false]
	station.missile_released.connect(func(_s: int, _t: int, _m: Node3D, _v: Vector3) -> void: released[0] = true)
	var ok := await _until(func() -> bool: return released[0], 15.0)
	_check(ok, "missile relâché par la station")
	await _frames(2)
	var flights := get_tree().root.find_children("MissileFlight_2_05", "", true, false)
	var flight := flights[0] as MissileFlight if not flights.is_empty() else null
	_check(flight != null, "vol en cours (MissileFlight_2_05%s)" % (" sous " + str(flight.get_parent().name) if flight else ""))
	if flight:
		_record["launch/flight_time_s"] = flight.flight_time_s
		print("  vol : %.1f s de jeu" % flight.flight_time_s)
	# Le vol se déroule en temps de jeu : temps accéléré jusqu'à l'impact.
	orbit.time_scale = 16.0
	ok = await _until(func() -> bool: return launcher.get_effects().size() > before, 60.0)
	orbit.time_scale = 0.0
	_check(ok, "explosion à l'arrivée")
	if ok:
		var p := launcher.get_effects()[-1].params
		_check(absf(p.latitude_deg - 48.86) < 1e-3 and absf(p.longitude_deg - 2.35) < 1e-3
				and is_equal_approx(p.yield_kt, 300.0), "au point visé, 300 kt")


func _uniforms(material: ShaderMaterial, names: Array[StringName]) -> Dictionary:
	var out := {}
	if material == null:
		return out
	for name in names:
		out[name] = ProbeCompare.portable(material.get_shader_parameter(name))
	return out
## Bilan sans les textes par pays (noms), gardant codes et nombres.
func _trim(report: Dictionary) -> Dictionary:
	var out := report.duplicate(true)
	if out.has("countries"):
		var countries: Array = []
		for c: Dictionary in out.countries:
			var entry := c.duplicate()
			entry.erase("name_fr")
			entry.erase("sovereign_fr")
			countries.append(entry)
		out.countries = countries
	return out
