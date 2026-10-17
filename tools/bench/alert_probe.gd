extends Node
## Niveaux d'alerte de la station (fenêtre 1920 × 1080, de nuit, caméra vers le plafond de la cupola) : capture à
## chaque niveau (user://bench_shots/alert_<0..3>.png) après le fondu, puis deux captures en alerte rouge à une
## demi-période d'écart (pulsation). Usage : godot --path . res://tools/bench/alert_probe.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var station := view.get_node("Station/StationSpatiale") as Station
	var camera := view.get_node("Observer/Camera") as Camera3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(3.0).timeout
	orbit.restart(0.0)
	orbit.time_scale = 0.0
	camera.basis = camera.basis * Basis(Vector3.RIGHT, PI)
	for level in 4:
		station.set_alert(level as Station.Alert)
		await get_tree().create_timer(2.5).timeout
		_shot("alert_%d.png" % level)
	await get_tree().create_timer(station.red_alert_period_s * 0.5).timeout
	_shot("alert_3_demi_periode.png")
	station.set_alert(Station.Alert.NONE)
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)
