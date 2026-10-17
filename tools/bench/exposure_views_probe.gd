extends Node
## Exposition selon le point de vue (fenêtre 1920 × 1080, luminosité 100 %) : de jour puis de nuit, depuis la cupola,
## caméra vers la Terre (vue par défaut), puis tournée vers le plafond de la cupola (intérieur), puis depuis
## l'intérieur de la station (observateur reculé de 6 m vers l'arrière). Captures user://bench_shots/views_<jour|nuit>_
## <terre|plafond|interieur>.png et facteur / sensibilité imprimés. Attendu : intérieur et plafond à la même
## exposition de jour comme de nuit (pas de saturation), Terre de nuit plus exposée.
## Usage : godot --path . res://tools/bench/exposure_views_probe.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	GameSettings.brightness = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var control: Node = view.get_node("Exposure")
	var attributes := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
	var observer := view.get_node("Observer") as Node3D
	var camera := view.get_node("Observer/Camera") as Camera3D
	var home := observer.position
	var look := camera.basis
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(4.0).timeout
	for period: Array in [["jour", 12.0], ["nuit", 0.0]]:
		orbit.restart(period[1])
		orbit.time_scale = 0.0
		for pose: Array in [["terre", home, look], ["plafond", home, look * Basis(Vector3.RIGHT, PI)],
				["interieur", home + Vector3(0.0, 0.0, 6.0), look * Basis(Vector3.RIGHT, PI * 0.5)]]:
			observer.position = pose[1]
			camera.basis = pose[2]
			await get_tree().create_timer(3.0).timeout
			get_viewport().get_texture().get_image().save_png("user://bench_shots/views_%s_%s.png" % [period[0], pose[0]])
			print("%s %s : facteur %.2f, sensibilité %.0f" % [period[0], pose[0], control.call(&"get_factor"),
					attributes.auto_exposure_min_sensitivity])
	get_tree().quit()
