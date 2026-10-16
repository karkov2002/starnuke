extends Node
## Reproduction du plantage à la fermeture (corrigé le 2026-10-16, abandon des bilans dans NukeImpact._exit_tree) :
## 10 × 50 Mt figés à 6 h, puis quit() après la variante demandée (« -- <variante> ») : none (rien : bilans en cours),
## clear (clear_effects), t60 (figés à 60 s), hide (nœud Mushroom masqué), free (orbit_view libérée : retour au menu),
## wait (attendre la fin des calculs de bilan, ~12 s). Attendu : sortie en quelques secondes, code 0. Usage :
##   godot --path . res://tools/bench/quit_probe.tscn -- none

const YIELD_KT := 50000.0


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var args := OS.get_cmdline_user_args()
	var variant := args[0] if not args.is_empty() else "none"
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	await _frames(60)
	orbit.restart(12.0)
	orbit.time_scale = 0.0
	await _frames(10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var aim := launcher.get_aim()
	for i in 10:
		launcher.launch_at(aim.latitude + rng.randf_range(-2.0, 2.0), aim.longitude + rng.randf_range(-2.5, 2.5), YIELD_KT)
	await _frames(60)
	for effect in launcher.get_effects():
		effect.time_override_s = 21600.0
	await _frames(60)
	match variant:
		"clear":
			launcher.clear_effects()
			await _frames(10)
		"t60":
			for effect in launcher.get_effects():
				effect.time_override_s = 60.0
			await _frames(10)
		"hide":
			for effect in launcher.get_effects():
				effect.get_node("Mushroom").visible = false
			await _frames(10)
		"free":
			view.queue_free()
			await _frames(10)
		"wait":
			while launcher.get_effects().any(func(e: NukeEffect) -> bool: return e.impact_pending or e.fallout_pending):
				await _frames(10)
	print("quit (%s)" % variant)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
