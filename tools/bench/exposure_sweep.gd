extends Node
## Balayage de l'exposition par la sensibilité (fenêtre 1920 × 1080, contrôle d'exposition suspendu) : exposition
## automatique activée mais bridée (sensibilité min = max = S, vitesse 20), captures de jour et de nuit pour plusieurs S
## (user://bench_shots/sens_<jour|nuit>_<S>.png), à juger à l'image et par luminance (ffmpeg signalstats). Le
## multiplicateur d'exposition seul n'agit pas sur le rendu dans ce build (voir README « Exposition »).
## Usage : godot --path . res://tools/bench/exposure_sweep.tscn

const DAY: Array[float] = [50.0, 200.0, 800.0, 3200.0, 12800.0]
const NIGHT: Array[float] = [12.0, 50.0, 200.0]


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
	view.get_node("Exposure").process_mode = Node.PROCESS_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(5.0).timeout
	attributes.exposure_multiplier = 1.0
	attributes.auto_exposure_scale = 0.22
	attributes.auto_exposure_speed = 20.0
	attributes.auto_exposure_enabled = true
	for period: Array in [["jour", 12.0, DAY], ["nuit", 0.0, NIGHT]]:
		orbit.restart(period[1])
		orbit.time_scale = 0.0
		await get_tree().create_timer(2.0).timeout
		for s: float in period[2]:
			attributes.auto_exposure_min_sensitivity = s
			attributes.auto_exposure_max_sensitivity = s
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png("user://bench_shots/sens_%s_%d.png" % [period[0], int(s)])
			print("%s S = %d" % [period[0], int(s)])
	get_tree().quit()
