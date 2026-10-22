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
	print("=== %d échec(s)" % _failures)
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)
