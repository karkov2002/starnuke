extends Node
## F4 en jeu : simule la touche, capture le panneau de debug ouvert (user://bench_shots/debug_f4.png).
## Usage : godot --path . res://tools/bench/debug_key_probe.tscn


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(3.0).timeout
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F4
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://bench_shots/debug_f4.png")
	print("panneau : %s" % (view.get_node_or_null("DebugPanel") != null))
	get_tree().quit()
