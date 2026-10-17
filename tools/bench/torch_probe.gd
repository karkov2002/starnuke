extends Node
## Lampe torche (fenêtre 1920 × 1080) : station éteinte (« plus de lumière »), caméra vers le plafond de la cupola,
## capture torche éteinte puis allumée par l'action « torch » simulée (user://bench_shots/torch_<off|on>.png).
## Usage : godot --path . res://tools/bench/torch_probe.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var station := view.get_node("Station/StationSpatiale") as Station
	var camera := view.get_node("Observer/Camera") as Camera3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(3.0).timeout
	orbit.restart(0.0)
	orbit.time_scale = 0.0
	var observer := view.get_node("Observer") as Node3D
	station.set_alert(Station.Alert.BLACKOUT)
	await get_tree().create_timer(4.0).timeout
	_shot("torch_off.png")
	var poses := {"plafond": Basis(Vector3.RIGHT, PI * 0.8), "couloir": Basis(Vector3.RIGHT, PI * 0.5), "couloir2": Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI)}
	var rest := camera.basis
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(1.0).timeout
	for pose in poses:
		camera.basis = rest * poses[pose]
		await get_tree().create_timer(1.5).timeout
		_shot("torch_on_%s.png" % pose)
	_shot("torch_on.png")
	print("torche visible : %s" % (view.get_node("Observer/Camera/Torch") as Node3D).visible)
	get_tree().quit()


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)
