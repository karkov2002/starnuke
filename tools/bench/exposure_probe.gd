extends Node
## Sonde de l'exposition (éditeur fermé). Deux phases, de jour puis de nuit (Orbit.restart 12 h / 0 h, orbite figée) :
## 1. calibration, fenêtre 1920 × 1080, contrôle d'exposition (nœud Exposure) suspendu : capture avec l'exposition
##    automatique de Godot (après adaptation), puis à plusieurs multiplicateurs fixes
##    (user://bench_shots/exposure_<jour|nuit>_<auto|x…>.png). La luminance moyenne de chaque capture (ffmpeg
##    signalstats, YAVG) donne le multiplicateur qui reproduit le rendu automatique en 16:9 ;
## 2. vérification du contrôle d'exposition : captures en fenêtre 1920 × 1080 puis en plein écran
##    (exposure_ctrl_<largeur>_<jour|nuit>_<n>.png) — même luminance attendue sur le même champ (centre 2560 × 1440 du plein écran 32:9).
## Usage : godot --path . res://tools/bench/exposure_probe.tscn

const MULT_DAY: Array[float] = [0.8, 0.9, 1.0, 1.1]
const MULT_NIGHT: Array[float] = [2.0, 3.0, 4.0, 8.0]
## Formats vérifiés : fenêtre 1920 × 1080, puis vrai plein écran (le cas du bug ; un retour à 1920 × 1080 par
## window_set_size après un passage à la taille de l'écran est ignoré par Godot, d'où le plein écran en dernier).
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i.ZERO]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var attributes := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
	var control: Node = view.get_node("Exposure")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await _frames(60)
	for period: Array in [["jour", 12.0, MULT_DAY], ["nuit", 0.0, MULT_NIGHT]]:
		orbit.restart(period[1])
		orbit.time_scale = 0.0
		# 1. Calibration (contrôle suspendu).
		DisplayServer.window_set_size(SIZES[0])
		control.process_mode = Node.PROCESS_MODE_DISABLED
		attributes.auto_exposure_enabled = true
		attributes.exposure_multiplier = 1.0
		await _seconds(4.0)
		_shot("exposure_%s_auto.png" % period[0])
		attributes.auto_exposure_enabled = false
		for mult: float in period[2]:
			attributes.exposure_multiplier = mult
			await _frames(10)
			_shot("exposure_%s_x%.1f.png" % [period[0], mult])
		# 2. Contrôle d'exposition, aux deux formats.
		control.process_mode = Node.PROCESS_MODE_INHERIT
		for i in SIZES.size():
			var size := SIZES[i]
			if size == Vector2i.ZERO:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				size = DisplayServer.window_get_size()
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(size)
			await _seconds(6.0)
			_shot("exposure_ctrl_%d_%s_%d.png" % [size.x, period[0], i])
			print("%s %d × %d (%d) : facteur %.2f, multiplicateur appliqué %.2f" % [period[0], size.x, size.y, i,
					control.call(&"get_factor"), attributes.exposure_multiplier])
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Attente en temps réel (le lissage de l'exposition est en secondes, pas en images).
func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
