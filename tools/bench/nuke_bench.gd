extends Node
## Banc de mesure des performances avec plusieurs explosions (scène tools/bench/nuke_bench.tscn). Charge la scène
## principale, coupe la synchro verticale, fige l'orbite, puis pour chaque nombre d'explosions de COUNTS : tire dans le
## champ de vision, fige toutes les explosions à chaque instant de TIMES_S (time_override_s) et mesure FRAMES images :
## temps CPU par image (moyenne et pire), temps GPU (RenderingServer). Résultats en console et dans le fichier passé
## en argument (« -- <fichier> »). Usage :
##   godot --path . res://tools/bench/nuke_bench.tscn -- <résultats.txt>

const COUNTS: Array[int] = [0, 1, 4, 8, 16]
## Instants mesurés (s, physiques) : montée du champignon et trous dans les nuages, puis nuage stabilisé.
const TIMES_S: Array[float] = [60.0, 1800.0]
const WARMUP_FRAMES := 30
const FRAMES := 120
const YIELD_KT := 1000.0

var _lines: Array[String] = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _frames(60)
	orbit.time_scale = 0.0
	var aim := launcher.get_aim()
	_log("Banc Star Nuke — %s, %s" % [RenderingServer.get_video_adapter_name(), Time.get_datetime_string_from_system()])
	_log("explosions | instant | CPU moyen (ms) | CPU pire (ms) | GPU moyen (ms) | images/s | tir (ms) | pire image après le tir (ms)")
	for count in COUNTS:
		var shot := await _fire(launcher, aim, count, YIELD_KT)
		for t in TIMES_S:
			var m := await _measure(launcher, t)
			_log("%10d | %6.0f s | %14.2f | %13.2f | %14.2f | %8.0f | %8.1f | %6.1f" % [count, t, m.x, m.y, m.z,
					1000.0 / maxf(m.x, 0.001), shot.x, shot.y])

	_log("")
	_log("Gros champignons : 4 x 50 Mt")
	var big := await _fire(launcher, aim, 4, 50000.0)
	for t in [600.0, 3600.0]:
		var m := await _measure(launcher, t)
		_log("50 Mt x 4 | %6.0f s | CPU %.2f ms (pire %.2f) | GPU %.2f ms | tir %.1f ms, pire image après %.1f ms"
				% [t, m.x, m.y, m.z, big.x, big.y])

	_log("")
	_log("Part de chaque effet (16 x 1 Mt, 60 s) : GPU sans cet effet")
	await _fire(launcher, aim, 16, YIELD_KT)
	var base := await _measure(launcher, 60.0)
	_log("tout actif : GPU %.2f ms" % base.z)
	var earth := view.get_node("Earth")
	var materials: Array[ShaderMaterial] = [earth.get_node("Surface").material_override,
			earth.get_node("CloudLayer").material_override]
	for part in ["Mushroom", "Shock", "nuke_cloud_count", "nuke_fire_count", "nuke_blackout_count"]:
		_toggle(launcher, materials, part, false)
		var m := await _measure(launcher, 60.0)
		_log("sans %-20s : GPU %.2f ms (gain %.2f ms)" % [part, m.z, base.z - m.z])
		_toggle(launcher, materials, part, true)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string("\n".join(_lines) + "\n")
	get_tree().quit()


## Tire count explosions dans le champ de vision (graine fixe). Retour : (durée des appels de tir en ms, pire image
## des 60 suivantes en ms).
func _fire(launcher: NukeLauncher, aim: Dictionary, count: int, yield_kt: float) -> Vector2:
	launcher.clear_effects()
	await _frames(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var start := Time.get_ticks_usec()
	for i in count:
		# Jusqu'à ~2,5° autour du point visé.
		launcher.launch_at(aim.latitude + rng.randf_range(-2.0, 2.0), aim.longitude + rng.randf_range(-2.5, 2.5), yield_kt)
	var fire_ms := (Time.get_ticks_usec() - start) / 1000.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for f in 60:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	await _wait_fallout(launcher)
	return Vector2(fire_ms, worst)


## Fige les explosions à t et mesure FRAMES images : (CPU moyen, CPU pire, GPU moyen) en ms.
func _measure(launcher: NukeLauncher, t: float) -> Vector3:
	for effect in launcher.get_effects():
		effect.time_override_s = t
	await _frames(WARMUP_FRAMES)
	var cpu_sum := 0.0
	var cpu_worst := 0.0
	var gpu_sum := 0.0
	var last := Time.get_ticks_usec()
	for f in FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		cpu_sum += ms
		cpu_worst = maxf(cpu_worst, ms)
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	return Vector3(cpu_sum / FRAMES, cpu_worst, gpu_sum / FRAMES)


## Active ou coupe un effet : nœud enfant des explosions (Mushroom, Shock) ou uniforme de compte d'un include (le nœud
## FX qui l'alimente est mis en pause pour qu'il ne le rétablisse pas).
func _toggle(launcher: NukeLauncher, materials: Array[ShaderMaterial], part: String, on: bool) -> void:
	if part.begins_with("nuke_"):
		var fx_name: String = {"nuke_cloud_count": "CloudFX", "nuke_fire_count": "FireFX",
				"nuke_blackout_count": "BlackoutFX"}[part]
		var fx := launcher.get_node(fx_name)
		fx.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if not on:
			for material in materials:
				if material.shader.get_shader_uniform_list().any(func(u: Dictionary) -> bool: return u.name == part):
					material.set_shader_parameter(part, 0)
		return
	for effect in launcher.get_effects():
		var node := effect.get_node(part) as Node3D
		node.visible = on
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Attend la fin du calcul des retombées (threads), pour ne pas mesurer leur démarrage.
func _wait_fallout(launcher: NukeLauncher) -> void:
	for i in 600:
		if launcher.get_effects().all(func(e: NukeEffect) -> bool: return not e.impact_pending and not e.fallout_pending):
			return
		await get_tree().process_frame


func _log(line: String) -> void:
	print(line)
	_lines.append(line)
