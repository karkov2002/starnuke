extends Node
## Vérification des paramètres vidéo (fenêtre 1920 × 1080) : ouvre l'écran des paramètres (scenes/ui/settings_menu.tscn)
## sur la vue orbitale, capture (user://bench_shots/settings_menu.png), puis règle l'éclairage intérieur à 100 % et
## 25 % avec la caméra tournée vers le plafond de la cupola, de nuit (settings_light_<100|25>.png).
## Usage : godot --path . res://tools/bench/settings_probe.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var camera := view.get_node("Observer/Camera") as Camera3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(3.0).timeout
	var settings: Control = load("res://scenes/ui/settings_menu.tscn").instantiate()
	settings.set("in_game", true)
	add_child(settings)
	await get_tree().create_timer(1.0).timeout
	_shot("settings_menu.png")
	settings.queue_free()
	orbit.restart(0.0)
	orbit.time_scale = 0.0
	camera.basis = camera.basis * Basis(Vector3.RIGHT, PI)
	for percent in [100, 25]:
		GameSettings.set_interior_light(percent / 100.0)
		await get_tree().create_timer(2.0).timeout
		_shot("settings_light_%d.png" % percent)
	GameSettings.set_interior_light(1.0)
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)
