extends Node
## Rendu du flash en direct (fenêtre 1920 × 1080) : tire 5 × 50 Mt d'un coup (temps x1) et capture la vue à plusieurs
## instants réels après le tir (user://bench_shots/look_<ms>.png), luminosité à 70 %. Pour juger l'adaptation de
## l'exposition au flash (nœud Exposure) : le flash doit rester un disque concentré, la scène s'assombrir autour.
## Usage : godot --path . res://tools/bench/flash_look_probe.tscn

const YIELD_KT := 50000.0
const TIMES_MS: Array[int] = [300, 1000, 2000, 5000, 10000, 20000]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	GameSettings.brightness = 0.7
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	await get_tree().create_timer(3.0).timeout
	orbit.restart(12.0)
	orbit.time_scale = 1.0
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("user://bench_shots/look_avant.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var aim := launcher.get_aim()
	for i in 5:
		launcher.launch_at(aim.latitude + rng.randf_range(-1.0, 1.0), aim.longitude + rng.randf_range(-1.5, 1.5), YIELD_KT)
	var start := Time.get_ticks_msec()
	for t in TIMES_MS:
		while Time.get_ticks_msec() - start < t:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://bench_shots/look_%d.png" % t)
		var control: Node = view.get_node("Exposure")
		var attributes := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
		print("t = %d ms : facteur %.3f, multiplicateur %.3f, flux reçu %.2f, éblouissement %.2f" % [t,
				control.call(&"get_factor"), attributes.exposure_multiplier, control.get(&"flash_received"),
				control.get(&"dazzle")])
	while launcher.get_effects().any(func(e: NukeEffect) -> bool: return e.impact_pending or e.fallout_pending):
		await get_tree().process_frame
	get_tree().quit()
