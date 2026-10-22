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
	_check(seats.size() == 3, "3 postes dans le groupe (%d)" % seats.size())
	for name in ["PilotConsole", "CommConsole", "TvConsole"]:
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
	for name in ["PilotConsole", "CommConsole", "TvConsole", "NukeReport"]:
		var console := view.get_node(name) as ScreenConsole
		var viewport: SubViewport = console.get("_viewport")
		_check(not console.is_near() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, name + " : loin, rendu coupé")
		if name != "NukeReport":
			var display: Node = viewport.get_child(0)
			_check(not display.is_processing() if name != "TvConsole" else true, name + " : interface suspendue")
	observer.global_position = home
	await get_tree().process_frame
	await get_tree().process_frame
	for name in ["PilotConsole", "CommConsole", "TvConsole", "NukeReport"]:
		var console := view.get_node(name) as ScreenConsole
		var viewport: SubViewport = console.get("_viewport")
		_check(console.is_near() and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, name + " : de retour, rendu repris")
	await _check_tv(view)
	await _check_tablet(view)
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
	display.show_tab(TabletDisplay.Tab.PHOTO)
	# Deux images : la tablette active la vue au nadir dans son _process, après le signal process_frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(nadir.active and nadir.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "nadir rendue sur l'onglet Photographie")
	await get_tree().process_frame
	var camera: Camera3D = nadir.get_child(0)
	var toward_earth: Vector3 = ((view.get_node("Earth") as Node3D).global_position - station.global_position).normalized()
	_check(camera.global_basis.z.dot(-toward_earth) > 0.999, "caméra nadir visée vers la Terre")
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
		for name in ["TvConsole", "CommConsole"]:
			var console := backdrop.get_node_or_null(name) as ScreenConsole
			_check(console != null and console.is_processing() and console.get("_viewport") != null, name + " construit dans le décor")
	menu.queue_free()
	await get_tree().process_frame
