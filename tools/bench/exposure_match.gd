extends Node
## Mise en correspondance de l'exposition (fenêtre 1920 × 1080, éditeur fermé) : rendu de l'ancien mécanisme
## (exposition automatique de Godot × luminosité des paramètres, après 10 s d'adaptation depuis un démarrage propre)
## contre le contrôle d'exposition (nœud Exposure), de jour puis de nuit, avec la même luminosité. Captures
## user://bench_shots/match_<ancien|nouveau>_<jour|nuit>.png ; comparer des zones de tons moyens (ffmpeg signalstats).
## Usage : godot --path . res://tools/bench/exposure_match.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var attributes := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
	var control: Node = view.get_node("Exposure")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	print("luminosité des paramètres : %.2f" % GameSettings.brightness)
	# Ancien mécanisme : contrôle suspendu, exposition automatique, multiplicateur = luminosité.
	control.process_mode = Node.PROCESS_MODE_DISABLED
	attributes.exposure_multiplier = GameSettings.brightness
	attributes.auto_exposure_enabled = true
	for period: Array in [["jour", 12.0], ["nuit", 0.0]]:
		orbit.restart(period[1])
		orbit.time_scale = 0.0
		await get_tree().create_timer(10.0).timeout
		_shot("match_ancien_%s.png" % period[0])
	# Nouveau contrôle.
	attributes.auto_exposure_enabled = false
	control.process_mode = Node.PROCESS_MODE_INHERIT
	for period: Array in [["jour", 12.0], ["nuit", 0.0]]:
		orbit.restart(period[1])
		await get_tree().create_timer(6.0).timeout
		_shot("match_nouveau_%s.png" % period[0])
		print("%s : facteur %.2f, multiplicateur %.2f" % [period[0], control.call(&"get_factor"), attributes.exposure_multiplier])
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)
