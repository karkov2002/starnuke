extends Node
## Parcours réel pour comparer deux versions du jeu (fenêtre 1920 × 1080, luminosité 70 %) : écran de démarrage
## (scenes/ui/main_menu.tscn) pendant 4 s, « Start Game », 5 s de partie, capture (flow_jeu.png), puis un 50 Mt au
## point visé et captures à 1, 2, 5, 10 et 20 s réelles (flow_<ms>.png), dans user://bench_shots/. À lancer sur
## chaque version (git worktree) et comparer. Usage : godot --path . res://tools/bench/flow_probe.tscn

const TIMES_MS: Array[int] = [1000, 2000, 5000, 10000, 20000]


func _ready() -> void:
	# La scène lancée est remplacée par l'écran de démarrage (et libérée) : le parcours tourne depuis un nœud
	# persistant ajouté à la racine, qui porte ce même script.
	if get_tree().current_scene == self:
		var runner := Node.new()
		runner.name = "FlowRunner"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	GameSettings.brightness = 0.7
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	# Changement de scène impossible pendant _ready (arbre occupé) : à l'image suivante.
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await get_tree().create_timer(4.0).timeout
	_shot("flow_menu.png")
	if not get_tree().current_scene.has_method(&"_on_start"):
		push_error("écran de démarrage non chargé")
		get_tree().quit()
		return
	get_tree().current_scene.call(&"_on_start")
	await get_tree().create_timer(5.0).timeout
	var game := get_tree().current_scene
	var launcher := game.get_node("NukeLauncher") as NukeLauncher
	_shot("flow_jeu.png")
	var aim := launcher.get_aim()
	launcher.launch_at(aim.latitude, aim.longitude, 50000.0)
	var start := Time.get_ticks_msec()
	for t in TIMES_MS:
		while Time.get_ticks_msec() - start < t:
			await get_tree().process_frame
		_shot("flow_%d.png" % t)
	while launcher.get_effects().any(func(e: NukeEffect) -> bool: return e.impact_pending or e.fallout_pending):
		await get_tree().process_frame
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)
