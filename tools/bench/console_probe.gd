extends Node
## Sonde des écrans à vue assise (ScreenConsole / ScreenSeatConsole, lot 2 de l'audit) : charge la vue orbitale, s'installe
## et se relève à chaque console par leur API (clic droit et F10 simulés), éloigne la caméra pour la garde de distance,
## vérifie les états et quitte (code 0 si tout passe). Usage :
##   godot --headless --path . res://tools/bench/console_probe.tscn

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	for i in 30:
		await get_tree().process_frame
	var observer := view.get_node("Observer") as CharacterBody3D
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var tablet := observer.get_node("Camera/Tablet")
	var report := view.get_node("NukeReport")
	_check(report is ScreenConsole and not report is CanvasLayer, "NukeReport est un ScreenConsole (Node)")
	_check(report.get("_screen") != null and report.get("_viewport") != null, "NukeReport : dalle et viewport")
	_check(report.is_processing(), "NukeReport actif")
	var seats := get_tree().get_nodes_in_group(ScreenSeatConsole.GROUP)
	_check(seats.size() == 7, "7 postes dans le groupe, dont 3 panneaux extérieurs (%d)" % seats.size())
	for name in ["PilotConsole", "CommConsole", "TvConsole", "RadarConsole"]:
		var console := view.get_node(name) as ScreenSeatConsole
		print("- " + name)
		_check(console != null and console.is_processing(), "actif")
		var viewport: SubViewport = console.get("_viewport")
		_check(viewport != null and viewport.get_parent() == console, "viewport %s" % [viewport.size if viewport else Vector2i()])
		_check(viewport.get_child_count() == 1, "une interface dans le viewport")
		_check(console.get("_bubble") != null and console.get("_hud") != null, "bulle et Hud")
		_check(console.is_near(), "caméra à portée au départ")
		var start_pos := observer.global_position
		var start_rot: Quaternion = observer.get_node("Camera").quaternion
		orbit.time_scale = 60.0
		console.call("_sit")
		_check(console.is_seated() and ScreenSeatConsole.any_seated(get_tree()), "assis")
		_check(observer.process_mode == Node.PROCESS_MODE_DISABLED, "observateur suspendu")
		_check(not tablet.call("is_out"), "tablette rangée")
		if name == "PilotConsole":
			_check(is_equal_approx(orbit.time_scale, 1.0), "temps ×1 au poste")
		else:
			_check(is_equal_approx(orbit.time_scale, 60.0), "temps inchangé")
		await _wait(0.8)
		_check(not console.get("_moving"), "transition finie")
		_check(observer.global_position.distance_to(start_pos) > 0.05, "œil déplacé face à la dalle")
		# Clic droit : on se relève (événement passé à _input comme le ferait Godot).
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		right.pressed = true
		right.position = Vector2(10, 10)
		console._input(right)
		_check(not console.is_seated(), "relevé au clic droit")
		await _wait(0.8)
		_check(observer.process_mode == Node.PROCESS_MODE_INHERIT, "observateur rendu")
		_check(observer.global_position.distance_to(start_pos) < 0.01, "position de départ retrouvée")
		_check((observer.get_node("Camera").quaternion as Quaternion).angle_to(start_rot) < 0.01, "orientation retrouvée")
		if name == "CommConsole":
			console.call("_sit")
			await _wait(0.8)
			var f10 := InputEventKey.new()
			f10.keycode = KEY_F10
			f10.pressed = true
			console._input(f10)
			_check(not console.is_seated(), "F10 quitte la vue radio")
			await _wait(0.8)
		orbit.time_scale = 1.0
	# Garde de distance : caméra à 100 m.
	var home := observer.global_position
	observer.global_position = home + Vector3(100, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	for name in ["PilotConsole", "CommConsole", "TvConsole", "RadarConsole", "NukeReport"]:
		var console := view.get_node(name) as ScreenConsole
		var viewport: SubViewport = console.get("_viewport")
		_check(not console.is_near() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, name + " : loin, rendu coupé")
		if name != "NukeReport":
			var display: Node = viewport.get_child(0)
			_check(not display.is_processing() if name != "TvConsole" else true, name + " : interface suspendue")
	observer.global_position = home
	await get_tree().process_frame
	await get_tree().process_frame
	for name in ["PilotConsole", "CommConsole", "TvConsole", "RadarConsole", "NukeReport"]:
		var console := view.get_node(name) as ScreenConsole
		var viewport: SubViewport = console.get("_viewport")
		_check(console.is_near() and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, name + " : de retour, rendu repris")
	await _check_tv(view)
	await _check_radar(view)
	_check_bearing(view)
	await _check_tablet(view)
	await _check_station(view)
	await _check_reticle(view)
	await _check_equipment(view)
	print("=== %d échec(s)" % _failures)
	view.queue_free()
	await get_tree().process_frame
	await _check_menu()
	print("=== %d échec(s) au total" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Télévision : modèle des chaînes (TvChannels) et ses deux règles de jeu, hors interface.
func _check_tv(view: Node) -> void:
	print("- TvChannels")
	var tv := view.get_node("TvConsole") as TvConsole
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var channels: TvChannels = tv.get("_channels")
	var display: TvDisplay = tv.get("_display")
	_check(channels != null and channels.has("FRA") and channels.codes().size() > 100, "chaînes chargées (%d)" % channels.codes().size())
	_check(display.channels == channels and display.channel == "FRA", "interface sur la chaîne par défaut")
	_check(channels.name_of("FRA") != "" and channels.lang_of("FRA") == "fr", "nom et langue de la chaîne")
	_check(not channels.is_off_air("FRA") and not channels.is_alert(), "à l'antenne, édition normale")
	_check(not tv.news_preview("FRA").is_empty(), "bandeau composé")
	orbit.time_scale = 0.0
	var changed := [false]
	channels.changed.connect(func() -> void: changed[0] = true)
	launcher.launch_at(48.86, 2.35, 1000.0)
	await get_tree().process_frame
	_check(changed[0] and channels.is_off_air("FRA") and channels.is_alert(), "Paris touchée : hors d'antenne, alerte")
	_check(not channels.is_off_air("DEU"), "Berlin à l'antenne")
	_check(display.is_off_air(), "mire sur la chaîne française")
	launcher.clear_effects()
	orbit.time_scale = 1.0


## Console radar : modèle du récepteur (sources du mode libre, horizon, accord, lobe de l'antenne), boutons et cadrage.
func _check_radar(view: Node) -> void:
	print("- Radar")
	var radar := view.get_node("RadarConsole") as RadarConsole
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var receiver := radar.receiver
	orbit.time_scale = 0.0
	_check(receiver.sources.size() == 2, "2 sources du mode libre")
	var knobs: Dictionary = radar.get("_knobs")
	_check(knobs.size() == 3, "3 boutons trouvés dans le modèle (%d)" % knobs.size())
	# Au-dessus de l'Allemagne : Oslo (VHF 100 MHz) à portée, au nord.
	orbit.pass_over(51.0, 10.0, false)
	receiver.set_band(RadarReceiver.Band.VHF)
	receiver.set_frequency_mhz(100.0)
	var m := radar.current_measure()
	_check(m.id == "oslo" and m.coherence > 0.99, "Oslo accroché à 100 MHz (%.3f)" % m.coherence)
	var bearing: float = m.bearing
	_check(bearing < 15.0 or bearing > 345.0, "cap d'Oslo au nord (%.1f°)" % bearing)
	receiver.set_azimuth_deg(bearing)
	var peak: float = radar.current_measure().amplitude
	receiver.set_azimuth_deg(bearing + 30.0)
	var off: float = radar.current_measure().amplitude
	_check(off < 0.25 * peak, "amplitude maximale dans l'axe (%.2f), faible à 30° (%.2f)" % [peak, off])
	receiver.set_azimuth_deg(bearing + 3.0)
	var near: float = radar.current_measure().amplitude
	_check(near < peak and near > off, "amplitude décroissante autour du cap")
	receiver.set_frequency_mhz(105.0)
	_check(radar.current_measure().coherence < 0.1, "désaccordé de 5 MHz : chaos")
	receiver.set_frequency_mhz(100.0)
	receiver.set_band(RadarReceiver.Band.UHF)
	_check(radar.current_measure().id == "", "Oslo absent en UHF")
	_check(is_equal_approx(receiver.get_frequency_mhz(), RadarReceiver.DEFAULT_MHZ[RadarReceiver.Band.UHF]),
			"chaque bande garde sa fréquence")
	# Au-dessus de Los Angeles : UHF 800 MHz, source sous la station (gain plein).
	orbit.pass_over(34.0, -118.2, true)
	receiver.set_frequency_mhz(800.0)
	m = radar.current_measure()
	_check(m.id == "los_angeles" and m.coherence > 0.99 and m.amplitude > 0.95, "Los Angeles accroché à la verticale")
	# Au-dessus de l'Australie : aucune source au-dessus de l'horizon.
	orbit.pass_over(-30.0, 140.0, true)
	_check(radar.current_measure().coherence == 0.0, "aucune source hors de l'horizon")
	# Boutons : glissements de la souris.
	receiver.set_azimuth_deg(0.0)
	radar.turn(RadarConsole.Knob.AZIMUTH, 40.0)
	_check(is_equal_approx(receiver.azimuth_deg, 10.0), "bouton d'azimut : 40 px = 10°")
	radar.turn(RadarConsole.Knob.AZIMUTH, -80.0)
	_check(is_equal_approx(receiver.azimuth_deg, 350.0), "azimut sur 360° (350°)")
	radar.turn(RadarConsole.Knob.BAND, -30.0)
	_check(receiver.band == RadarReceiver.Band.VHF, "sélecteur glissé à gauche : VHF")
	radar.turn(RadarConsole.Knob.BAND, 30.0)
	_check(receiver.band == RadarReceiver.Band.UHF, "sélecteur glissé à droite : UHF")
	var f0 := receiver.get_frequency_mhz()
	radar.turn(RadarConsole.Knob.FREQUENCY, 100.0)
	_check(is_equal_approx(receiver.get_frequency_mhz() - f0, 135.0), "bouton de fréquence : 100 px = 5 % de la bande")
	receiver.set_band(RadarReceiver.Band.VHF)
	# Vue assise : cadre agrandi vers le bas (bande des boutons).
	var screen: StationScreen = radar.get("_screen")
	var camera := view.get_node("Observer/Camera") as Camera3D
	var plain := screen.seat_pose(camera, 16.0 / 9.0, 0.9)
	var radar_pose: Dictionary = radar.call("_seat_pose")
	var down := (screen.mesh_instance.global_transform.basis * screen.axis_v).normalized()
	_check((radar_pose.eye - plain.eye).dot(down) > 0.05, "vue assise abaissée vers les boutons")
	orbit.time_scale = 1.0


## Rapporteur de la carte du poste (BearingTool, BearingLog) : relevé posé et validé au clic, cap de grand cercle,
## trait borné à la portée du radar, choix, effacement, sauvegarde avec le monde.
func _check_bearing(view: Node) -> void:
	print("- Rapporteur")
	var display: PilotDisplay = view.get_node("PilotConsole").get("_display")
	var map: OrbitalMap = display.get("_map")
	var tool: BearingTool = map.get("_bearing_tool")
	var bearing_log := view.get_node("BearingLog") as BearingLog
	_check(tool != null and bearing_log != null, "outil et journal des relevés")
	bearing_log.clear()
	var start := Vector2(51.0, 10.0)
	var oslo := Vector2(59.91, 10.73)
	tool.toggle()
	_check(tool.mode == BearingTool.Mode.PLACE, "outil démarré")
	_check(tool.click(map.project(start.x, start.y)) and tool.mode == BearingTool.Mode.AIM, "centre posé")
	tool.click(map.project(oslo.x, oslo.y))
	_check(tool.mode == BearingTool.Mode.OFF and bearing_log.bearings.size() == 1, "relevé validé au second clic")
	var b: Dictionary = bearing_log.bearings[0] if bearing_log.bearings.size() > 0 else {}
	var expected := GeoMath.initial_bearing_deg(start.x, start.y, oslo.x, oslo.y)
	_check(not b.is_empty() and absf(angle_difference(deg_to_rad(b.azimuth), deg_to_rad(expected))) < deg_to_rad(1.0),
			"cap du grand cercle vers Oslo (%.1f°, attendu %.1f°)" % [b.get("azimuth", -1.0), expected])
	var end := BearingLog.end_of(b) if not b.is_empty() else Vector2.ZERO
	_check(GeoMath.distance_km(end.x, end.y, oslo.x, oslo.y) < 60.0, "extrémité du trait sur le point visé")
	# Trait borné à la portée du radar (horizon de la station).
	tool.toggle()
	tool.click(map.project(start.x, start.y))
	tool.click(map.project(-30.0, 10.0))
	var far: Dictionary = bearing_log.bearings[-1]
	_check(is_equal_approx(far.length_km, tool.range_km()) and far.range_km > 2000.0 and far.range_km < 2400.0,
			"trait borné à la portée (%.0f km)" % far.range_km)
	# Choix par le centre, effacement.
	bearing_log.select(-1)
	_check(tool.click(map.project(oslo.x, oslo.y)) and bearing_log.selected == 0, "clic sur l'extrémité : relevé choisi")
	bearing_log.remove(bearing_log.selected)
	_check(bearing_log.bearings.size() == 1 and bearing_log.selected == -1, "relevé effacé")
	# Sauvegarde avec le monde.
	var snapshot := WorldSnapshot.new(null, null, null, null, bearing_log)
	var world := snapshot.capture()
	bearing_log.clear()
	snapshot.restore(world)
	_check(bearing_log.bearings.size() == 1 and is_equal_approx(bearing_log.bearings[0].azimuth, 180.0),
			"relevés sauvegardés et recréés")
	bearing_log.clear()


## Tablette : NadirCamera, PhotoPage et AlertsPage (lot 2, étape 3).
func _check_tablet(view: Node) -> void:
	print("- Tablette")
	var tablet := view.get_node("Observer/Camera/Tablet") as Tablet
	var display: TabletDisplay = tablet.get("_display")
	var nadir: NadirCamera = tablet.get("_nadir")
	var station := view.get_node("Station/StationSpatiale") as Station
	_check(display != null and nadir != null and nadir.get_parent() == tablet, "interface et caméra nadir créées")
	_check(not nadir.active and nadir.render_target_update_mode == SubViewport.UPDATE_DISABLED, "nadir inactive, tablette rangée")
	_check(display.get("_photo_page") is PhotoPage and display.get("_pages")[3] is AlertsPage, "pages Photographie et Alertes")
	_check((display.get("_photo_page") as PhotoPage).nadir_texture == nadir.get_texture(), "vue au nadir affichée par la page")
	tablet.call("_set_wanted", true)
	await _wait(0.8)
	_check(tablet.visible and tablet.is_out() and is_equal_approx(tablet.get("_out"), 1.0), "tablette sortie")
	# Tablette prioritaire sur la souris : ce qui est derrière elle (écrans, écoutilles) n'a ni bulle ni clic.
	var body: MeshInstance3D = tablet.get("_body")
	var view_camera := tablet.get_parent() as Camera3D
	var on_tablet := view_camera.unproject_position(body.global_transform * body.get_aabb().get_center())
	_check(Tablet.covers_pointer(get_tree(), on_tablet) and not Tablet.covers_pointer(get_tree(), Vector2(10, 10)),
			"tablette sous le pointeur détectée (coque), pas ailleurs")
	# Combinaison du sas portée : main gantée (gant, bague, manche blanche) à la place de la main nue.
	var model: Node3D = tablet.get("_model")
	var hand_shown := func() -> Array[bool]:
		return [(model.find_child("Main_Droite", true, false) as Node3D).is_visible_in_tree(),
				(model.find_child("Gant_Droit", true, false) as Node3D).is_visible_in_tree()]
	_check(hand_shown.call() == [true, false], "main nue sans la combinaison")
	station.set_suit_worn(true)
	_check(hand_shown.call() == [false, true], "main gantée avec la combinaison")
	station.set_suit_worn(false)
	_check(hand_shown.call() == [true, false], "main nue, combinaison ôtée")
	display.show_tab(TabletDisplay.Tab.PHOTO)
	# Deux images : la tablette active la vue au nadir dans son _process, après le signal process_frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(nadir.active and nadir.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "nadir rendue sur l'onglet Photographie")
	await get_tree().process_frame
	var camera: Camera3D = nadir.get_child(0)
	var toward_earth: Vector3 = ((view.get_node("Earth") as Node3D).global_position - station.global_position).normalized()
	_check(camera.global_basis.z.dot(-toward_earth) > 0.999, "caméra nadir visée vers la Terre")
	# Centre de l'image = point survolé de l'orbite (point des photos de mission) : la Terre est posée sous la caméra
	# de la vue, pas sous l'origine de la station (10 m d'écart : ~100 km au sol).
	var earth := view.get_node("Earth") as Node3D
	var center := GeoMath.mesh_to_lat_lon((earth.global_transform.affine_inverse() * (camera.global_position
			- camera.global_basis.z * 10.0)).normalized())
	var under: Vector2 = (view.get_node("Orbit") as OrbitSimulation).get_subsatellite_point()
	var off_km := GeoMath.distance_km(center.x, center.y, under.x, under.y)
	_check(off_km < 1.0, "centre de la vue au nadir sur le point survolé (%.2f km)" % off_km)
	# Mode infrarouge : Terre thermique seule, dessinée seulement dans ce mode, capteur en résolution réduite.
	var thermal := earth.get_node("ThermalSurface") as ThermalSurface
	var surface_material := (earth.get_node("Surface") as MeshInstance3D).material_override as ShaderMaterial
	var thermal_material := thermal.material_override as ShaderMaterial
	_check(thermal_material.shader == ThermalSurface.SHADER and thermal_material.get_shader_parameter("day_texture")
			== surface_material.get_shader_parameter("day_texture") and not thermal.visible
			and camera.cull_mask & ThermalSurface.LAYER == 0, "Terre thermique : matériau copié, cachée en visible")
	nadir.infrared = true
	_check(camera.cull_mask == ThermalSurface.LAYER and thermal.visible
			and nadir.size == Vector2i(Vector2(NadirCamera.LIVE_SIZE) * NadirCamera.IR_SCALE), "nadir en infrarouge")
	nadir.infrared = false
	_check(camera.cull_mask & ThermalSurface.LAYER == 0 and not thermal.visible and nadir.size == NadirCamera.LIVE_SIZE,
			"nadir revenue en visible")
	_check(nadir.footprint_km(400.0).y > 150.0 and nadir.footprint_km(400.0).y < 160.0, "emprise à 400 km : %.0f km" % nadir.footprint_km(400.0).y)
	# Photo : RenderingServer.frame_post_draw ne vient jamais sans fenêtre (headless) : vérifié seulement avec rendu.
	if DisplayServer.get_name() != "headless":
		var archive := view.get_node("Photos") as PhotoArchive
		var before := archive.photos.size()
		(display.get("_photo_page") as PhotoPage).call("_take_photo")
		await _wait(1.0)
		_check(archive.photos.size() == before + 1, "photo prise par le bouton (%d)" % archive.photos.size())
		_check(nadir.size == NadirCamera.LIVE_SIZE and nadir.active, "vue au nadir revenue en direct")
	else:
		print("  (photo : non testée en headless)")
	display.show_tab(TabletDisplay.Tab.ALERTS)
	station.set_alert(Station.Alert.RED)
	await get_tree().process_frame
	await get_tree().process_frame
	var labels: Array = display.get("_pages")[3].get("_alert_labels")
	_check(labels[Station.Alert.RED].text.begins_with("▲") and not labels[0].text.begins_with("▲"), "niveau d'alerte marqué sur la page")
	_check(not nadir.active, "nadir coupée hors de l'onglet Photographie")
	station.set_alert(Station.Alert.NONE)
	tablet.call("_set_wanted", false)
	await _wait(0.6)
	_check(not tablet.visible, "tablette rangée")


## Menu de démarrage : son décor est la vue orbitale sans lanceur ni poste ; les écrans qui restent (radio,
## télévision, bilan retiré) doivent s'y construire sans erreur (régression du 22/10 : tableau d'explosions non typé).
func _check_menu() -> void:
	print("- Menu de démarrage")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _wait(4.0)
	var backdrop: Node = null
	for child in menu.get_children():
		if child.name == "OrbitView" or child.has_node("Orbit"):
			backdrop = child
			break
	_check(backdrop != null, "décor construit")
	if backdrop:
		_check(backdrop.get_node_or_null("NukeLauncher") == null, "sans lanceur")
		for name in ["TvConsole", "CommConsole", "RadarConsole"]:
			var console := backdrop.get_node_or_null(name) as ScreenConsole
			_check(console != null and console.is_processing() and console.get("_viewport") != null, name + " construit dans le décor")
	menu.queue_free()
	await get_tree().process_frame


## Attend que pred soit vraie (une image à la fois), au plus timeout_s ; rend son dernier état.
func _until(pred: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


## Station : API des écoutilles, trappes, radiateurs et chaleur, cargo, combinaison, valve du sas, alerte et
## lancement d'un missile (lot 2, étape 4 : la découpe en composants ne doit rien y changer).
func _check_station(view: Node) -> void:
	print("- Station")
	var station := view.get_node("Station/StationSpatiale") as Station
	var orbit := view.get_node("Orbit") as OrbitSimulation
	orbit.time_scale = 1.0
	_check(station.hatch_ids().size() >= 8 and station.tube_ids().size() == 48,
			"écoutilles (%d) et tubes (%d)" % [station.hatch_ids().size(), station.tube_ids().size()])
	var hatch := "Ecoutille_Habitation_AR"
	_check(station.is_hatch_openable(hatch) and not station.is_hatch_open(hatch), "écoutille fermée au départ")
	var changes := []
	station.hatch_changed.connect(func(id: String, open: bool) -> void: changes.append([id, open]))
	_check(station.open_hatch(hatch) and station.is_hatch_opening(hatch), "ouverture demandée")
	_check(await _until(func() -> bool: return station.is_hatch_open(hatch), 6.0) and changes == [[hatch, true]], "écoutille ouverte, signal reçu")
	station.toggle_hatch(hatch)
	_check(await _until(func() -> bool: return not station.is_hatch_open(hatch), 6.0), "écoutille refermée")
	_check(not station.is_silo_door_open(1, 1) and station.open_silo_door(1, 1), "trappe 1_01 : ouverture")
	_check(await _until(func() -> bool: return station.is_silo_door_open(1, 1), 6.0), "trappe 1_01 ouverte")
	station.close_silo_door(1, 1)
	_check(await _until(func() -> bool: return not station.is_silo_door_open(1, 1), 6.0), "trappe 1_01 refermée")
	_check(station.radiator_ids().size() == 4 and station.is_radiator_deployed("Radiateur_D15"), "4 radiateurs déployés")
	station.set_stealth(true)
	_check(await _until(func() -> bool: return station.radiator_ids().all(func(id: String) -> bool: return not station.is_radiator_deployed(id)), 20.0), "mode furtif : radiateurs repliés")
	var heat_before: float = station.heat
	await _wait(1.0)
	_check(station.heat > heat_before, "chaleur en hausse (%.3f)" % station.heat)
	station.set_stealth(false)
	_check(await _until(func() -> bool: return station.is_radiator_deployed("Radiateur_G21"), 20.0), "radiateurs redéployés")
	_check(station.is_cargo_docked() and station.set_cargo_docked(false) and station.is_cargo_moving(), "cargo : séparation lancée")
	_check(not station.set_cargo_docked(true), "cargo : refus pendant le mouvement")
	_check(not station.is_suit_worn() and station.set_suit_worn(true) and station.is_suit_worn(), "combinaison enfilée")
	station.set_suit_worn(false)
	_check(station.get_airlock_pressure() >= 0.99 and not station.is_airlock_cycling(), "sas plein, valve fermée")
	_check(station.set_airlock_pressurized(false) and station.get_airlock_valve_mode() == -1, "vidange ouverte")
	_check(await _until(func() -> bool: return station.get_airlock_pressure() < 0.9, 15.0), "pression du sas en baisse (%.2f)" % station.get_airlock_pressure())
	_check(station.set_airlock_pressurized(true) and station.get_airlock_valve_mode() == 1, "remplissage ouvert")
	_check(await _until(func() -> bool: return not station.is_airlock_cycling(), 30.0) and station.get_airlock_pressure() >= 0.99, "sas plein, valve refermée d'elle-même")
	var pivots := station.find_children("Pivot_Panneau_*", "Node3D", false, false)
	_check(pivots.size() == 4 and pivots.all(func(p: Node3D) -> bool: return p.quaternion.is_equal_approx(pivots[0].quaternion)) and absf(pivots[0].quaternion.get_angle()) > 1e-3, "4 panneaux solaires orientés d'un même angle (%.1f°)" % rad_to_deg(pivots[0].quaternion.get_angle()))
	station.set_alert(Station.Alert.RED)
	_check(station.get_alert() == Station.Alert.RED, "alerte rouge")
	station.set_alert(Station.Alert.BLACKOUT)
	_check(await _until(func() -> bool: return station.get_blackout() > 0.9, 5.0), "plus de lumière : black-out fondu")
	station.set_alert(Station.Alert.NONE)
	_check(await _until(func() -> bool: return station.get_blackout() < 0.1, 5.0), "lumière revenue")
	var released := []
	station.missile_released.connect(func(silo: int, tube: int, missile: Node3D, velocity: Vector3) -> void:
		released.append([silo, tube, missile.name, velocity.length()]))
	var ignited := [false]
	station.missile_ignited.connect(func(_silo: int, _tube: int) -> void: ignited[0] = true)
	_check(station.available_tubes().size() == 48 and station.can_launch(2, 5), "48 tubes disponibles")
	_check(station.launch_handoff_s() > 1.0 and station.launch_missile(2, 5), "lancement 2_05 (%.1f s)" % station.launch_handoff_s())
	_check(await _until(func() -> bool: return not released.is_empty(), station.launch_handoff_s() + 3.0), "missile relâché : %s" % str(released))
	_check(ignited[0] and station.is_silo_door_open(2, 5) and not station.can_launch(2, 5) and station.available_tubes().size() == 47, "tuyère allumée, trappe ouverte, tube vidé")


## Équipements extérieurs (StationEquipments) : panneaux de maintenance utilisables seulement dehors, ON / OFF,
## panne et réparation au panneau, effets sur la tablette (caméra hors ligne) et la radio (liaison coupée),
## sauvegarde avec le monde.
func _check_equipment(view: Node) -> void:
	print("- équipements extérieurs")
	var equipments := view.get_node("Equipment") as StationEquipments
	var camera := StationEquipments.find(get_tree(), StationEquipments.CAMERA)
	var antenna := StationEquipments.find(get_tree(), StationEquipments.ANTENNA)
	_check(camera != null and antenna != null and camera.is_operational() and antenna.is_operational(),
			"caméra et antenne en service au départ")
	var station := view.get_node("Station/StationSpatiale") as Station
	for panel_name in ["CameraPanel", "AntennaPanel", "RadarPanel"]:
		var panel := equipments.get_node(panel_name) as EquipmentPanel
		var viewport: SubViewport = panel.get("_viewport") if panel else null
		_check(panel != null and panel.is_processing() and viewport != null and viewport.get_child_count() == 1,
				"%s : dalle, viewport et interface" % panel_name)
		station.observer_outside = false
		_check(not panel.call("_can_use"), "%s : inutilisable depuis l'intérieur" % panel_name)
		station.observer_outside = true
		_check(panel.call("_can_use"), "%s : utilisable dehors" % panel_name)
	station.observer_outside = false
	# Interface du panneau de la caméra : Entrée éteint / rallume, R répare.
	var display := equipments.get_node("CameraPanel").get("_display") as EquipmentDisplay
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	display.handle_key(enter)
	_check(not camera.powered and not camera.is_operational(), "Entrée : caméra éteinte")
	# Caméra hors service : tablette « hors ligne », vue au nadir coupée, pas de photo.
	var tablet := view.get_node("Observer/Camera/Tablet") as Tablet
	var tablet_display := tablet.get_node("Screen/Display") as TabletDisplay
	tablet_display.show_tab(TabletDisplay.Tab.PHOTO)
	tablet.call("_set_wanted", true)
	await _wait(0.6)
	var nadir: NadirCamera = tablet.get("_nadir")
	var page: PhotoPage = tablet_display.get("_photo_page")
	_check(not nadir.active and not page.camera_online and (page.get("_offline_label") as Label).visible
			and (page.get("_shutter_button") as BigRedButton).disabled, "caméra éteinte : tablette hors ligne")
	display.handle_key(enter)
	camera.fail()
	await _wait(0.3)
	_check(camera.powered and camera.failed and not page.camera_online, "caméra en panne : hors ligne")
	var r := InputEventKey.new()
	r.keycode = KEY_R
	r.pressed = true
	display.handle_key(r)
	_check(display.is_playing() and camera.failed, "R : mini-jeu de réparation lancé, toujours en panne")
	# Victoire : la troisième baie remplie répare.
	var game: RepairFrogger = display.get("_game")
	game.bays_filled = [true, true, false]
	game.frog = Vector2(RepairFrogger.BAYS[2], 1)
	game.move(0, -1)
	await _wait(0.3)
	_check(not display.is_playing() and camera.is_operational() and page.camera_online and nadir.active,
			"mini-jeu gagné : réparée, vue au nadir revenue")
	# Chrono à 0 : échec, délai avant un nouvel essai.
	camera.fail(2)
	display.handle_key(r)
	game = display.get("_game")
	_check(game != null and game.level == 2, "panne de niveau 2 : mini-jeu de niveau 2")
	game.time_left = 0.01
	await _wait(0.3)
	_check(not display.is_playing() and camera.failed and camera.retry_in_s > 25.0, "chrono à 0 : échec, délai de 30 s")
	display.handle_key(r)
	_check(not display.is_playing(), "pendant le délai : pas de nouvel essai")
	camera.repair()
	_check(camera.retry_in_s == 0.0 and camera.is_operational(), "réparation directe (debug) : délai effacé")
	_check_frogger()
	tablet.call("_set_wanted", false)
	# Antenne : panne -> ni liaison ni réponse (PANNE RÉCEPTION), arrêt -> idem (ANTENNE ARRÊTÉE).
	var radio := view.get_node("Radio") as RadioComms
	antenna.fail()
	radio.call("_update_link")
	_check(radio.link == 0.0 and not radio.antenna_ok and radio.antenna_failed, "antenne en panne : liaison coupée")
	antenna.repair()
	antenna.set_powered(false)
	radio.call("_update_link")
	_check(radio.link == 0.0 and not radio.antenna_ok and not radio.antenna_failed, "antenne arrêtée : liaison coupée")
	# Sauvegarde : état gardé avec le monde, puis restauré.
	camera.fail()
	var snapshot := WorldSnapshot.new(null, null, null, null, null, equipments)
	var world := snapshot.capture()
	camera.repair()
	antenna.set_powered(true)
	snapshot.restore(world)
	_check(camera.failed and not antenna.powered, "état des équipements sauvegardé et restauré")
	camera.repair()
	antenna.set_powered(true)
	radio.call("_update_link")
	_check(radio.antenna_ok, "antenne remise en service")
	# Radar : en panne ou arrêté -> plus de signal à la console radar, message à l'écran.
	var radar_console := view.get_node("RadarConsole") as RadarConsole
	var radar := StationEquipments.find(get_tree(), StationEquipments.RADAR)
	radar.fail()
	var no_signal := radar_console.current_measure()
	_check(not radar_console.radar_operational() and float(no_signal.coherence) == 0.0 and String(no_signal.id) == "",
			"radar en panne : plus de signal")
	radar.repair()
	_check(radar_console.radar_operational(), "radar réparé")
	# Dehors jusqu'au retour par le sas : frôler la coque (coin de la boîte d'un volume qui en dépasse) ne fait pas
	# « rentrer » dans un module (sinon, plus jamais dehors : panneaux inutilisables).
	var observer := view.get_node("Observer") as CharacterBody3D
	var eye := observer.get_node("Camera") as Node3D
	var air := view.get_node("StationAir") as StationAtmosphere
	var home := observer.global_position
	var to_eye := eye.global_position - observer.global_position
	var at := func(blender: Vector3) -> Vector3:
		return station.to_global(StationLayout.to_godot(blender)) - to_eye
	station.set_suit_worn(true)
	observer.global_position = air.zone_center(StationAtmosphere.SAS) - to_eye
	await _wait(0.1)
	observer.global_position = at.call(Vector3(-10.1, 0.0, -7.0))
	await _wait(0.1)
	_check(station.observer_outside, "sorti par le sas : dehors")
	observer.global_position = at.call(Vector3(5.8, 1.6, -1.95))
	await _wait(0.1)
	_check(air.zone_at(eye.global_position) != "" and station.observer_outside,
			"coin d'un volume hors de la coque : toujours dehors")
	observer.global_position = air.zone_center(StationAtmosphere.SAS) - to_eye
	await _wait(0.1)
	_check(not station.observer_outside, "rentré par le sas : dedans")
	observer.global_position = home
	station.set_suit_worn(false)
	await _wait(0.1)


## Réticule de tir : dans la cupola, seulement la tablette sur l'onglet « Tir de missile ».
func _check_reticle(view: Node) -> void:
	print("- réticule de tir")
	var reticle := view.get_node("Hud/AimReticle") as Control
	var tablet := get_tree().get_first_node_in_group(Tablet.GROUP) as Tablet
	var display := tablet.get("_display") as TabletDisplay
	var station := view.get_node("Station/StationSpatiale") as Station
	_check(station.is_in_cupola(get_viewport().get_camera_3d().global_position), "observateur dans la cupola")
	var before := tablet.current_tab()
	display.show_tab(TabletDisplay.Tab.PILOT)
	await _wait(0.8)
	_check(not reticle.visible, "onglet Pilotage : pas de réticule")
	display.show_tab(TabletDisplay.Tab.MISSILE)
	await _wait(0.8)
	_check(reticle.visible and reticle.modulate.a > 0.99, "onglet Tir de missile : réticule")
	display.show_tab(before)
	await _wait(0.8)


## Mini-jeu de réparation (modèle seul) : voitures, troncs, eau, baies, chrono, niveaux.
func _check_frogger() -> void:
	print("- mini-jeu de réparation")
	var easy := RepairFrogger.new(1)
	var hard := RepairFrogger.new(3)
	var road := easy.lane_at(6)
	_check(absf(hard.lane_speed(road)) > absf(easy.lane_speed(road)) and hard.time_left < easy.time_left,
			"niveau 3 : voies plus rapides, chrono plus court")
	# Voiture : posée sur elle, la grenouille meurt, puis revient au départ.
	var g := RepairFrogger.new(1)
	var car: Vector2 = g.lane_objects(road)[0]
	for o in g.lane_objects(road):
		if o.x > 1.0 and o.x < RepairFrogger.COLS - 3.0:
			car = o
	g.frog = Vector2(car.x, 6)
	g.update(0.01)
	_check(g.dead_s > 0.0 and g.deaths == 1, "voiture : grenouille écrasée")
	g.update(RepairFrogger.RESPAWN_S + 0.1)
	_check(g.dead_s == 0.0 and int(g.frog.y) == RepairFrogger.START_ROW, "retour au départ")
	# Tronc : il porte la grenouille ; à l'eau, elle se noie.
	var river := g.lane_at(3)
	var log_object: Vector2 = g.lane_objects(river)[0]
	for o in g.lane_objects(river):
		if o.x > 2.0 and o.x + o.y < RepairFrogger.COLS - 2.0:
			log_object = o
	g.frog = Vector2(log_object.x + log_object.y * 0.5 - 0.5, 3)
	var x0 := g.frog.x
	g.update(0.2)
	_check(g.dead_s == 0.0 and g.frog.x > x0, "tronc : grenouille portée")
	g.frog = Vector2(log_object.x + log_object.y + 1.0, 3)
	if g.call("_on_log", river):
		g.frog.x = log_object.x - 2.0
	g.update(0.01)
	_check(g.dead_s > 0.0, "eau : grenouille noyée")
	# Baies : contre le mur, mort ; dans une baie, remplie ; trois baies, gagné.
	var h := RepairFrogger.new(1)
	h.frog = Vector2(0, 1)
	h.move(0, -1)
	_check(h.dead_s > 0.0 and not h.bays_filled.has(true), "mur de l'arrivée : mort")
	h = RepairFrogger.new(1)
	for i in RepairFrogger.BAYS.size():
		h.frog = Vector2(RepairFrogger.BAYS[i], 1)
		h.move(0, -1)
	_check(h.state == RepairFrogger.State.WON, "trois baies remplies : gagné")
	h = RepairFrogger.new(3)
	h.update(RepairFrogger.LEVELS[3].time + 1.0)
	_check(h.state == RepairFrogger.State.LOST and h.time_left == 0.0, "chrono à 0 : perdu")
