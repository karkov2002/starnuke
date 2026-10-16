extends Node
## Banc de mesure de référence (scène tools/bench/bench.tscn). Charge la scène principale, coupe la synchro verticale,
## met la fenêtre sans bordure à chaque résolution de RESOLUTIONS (rendu 3D à l'échelle 1) et y joue trois scénarios,
## chacun depuis le même état (Orbit.restart à midi au-dessus de Madrid) :
## 1. orbite simple : temps x1, aucune explosion, LIVE_S secondes ;
## 2. MISSILES missiles tirés d'un coup depuis les tubes de la station (animation de sortie, vol, rentrée), mesurés
##    phase par phase jusqu'à l'impact, puis LIVE_S secondes d'explosions à l'arrivée ;
## 3. EXPLOSIONS explosions de YIELD_KT tirées d'un coup (graine fixe), orbite figée, toutes figées à chaque instant
##    de EXPLOSION_TIMES_S (time_override_s) pendant FRAMES images.
## Enfin, à la dernière résolution, la part GPU de chaque effet (en le coupant). Pour chaque mesure : temps CPU par
## image (moyen et pire), temps GPU (RenderingServer), images/s, appels de dessin. Résultats en console et dans un
## fichier Markdown (argument « -- <fichier> », sinon tools/bench/results/bench_<date>.md). Usage :
##   godot --path . res://tools/bench/bench.tscn [-- <résultats.md>]

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440),
		Vector2i(5120, 1440)]
const MISSILES := 8
const EXPLOSIONS := 10
const YIELD_KT := 1000.0
## Instants mesurés (s, physiques) : éclair et onde de choc, montée du champignon, champignon étalé, nuage
## stabilisé, incendies et fumée.
const EXPLOSION_TIMES_S: Array[float] = [5.0, 60.0, 600.0, 1800.0, 21600.0]
const LIVE_S := 4.0
const WARMUP_FRAMES := 30
const FRAMES := 120
const SEED := 1234
## Garde-fou du scénario des missiles (s réelles).
const MISSILES_TIMEOUT_S := 240.0
const RESULTS_DIR := "res://tools/bench/results"
## Capture d'écran après chaque mesure (vérification de ce qui a été mesuré), hors dépôt.
const SHOTS_DIR := "user://bench_shots"

var _lines: Array[String] = []
var _view: Node
var _orbit: OrbitSimulation
var _launcher: NukeLauncher
var _launch_control: LaunchControl
var _station: Station
var _rid: RID
var _released := 0


## Cumul des mesures d'une phase.
class Stats:
	var frames := 0
	var cpu_sum := 0.0
	var cpu_worst := 0.0
	var gpu_sum := 0.0
	var draw_sum := 0.0

	func add(cpu_ms: float, gpu_ms: float, draws: float) -> void:
		frames += 1
		cpu_sum += cpu_ms
		cpu_worst = maxf(cpu_worst, cpu_ms)
		gpu_sum += gpu_ms
		draw_sum += draws

	func cpu_ms() -> float:
		return cpu_sum / maxi(frames, 1)

	func gpu_ms() -> float:
		return gpu_sum / maxi(frames, 1)

	func row(resolution: String, scenario: String, phase: String) -> String:
		if frames == 0:
			return "| %s | %s | %s | — | — | — | — | — |" % [resolution, scenario, phase]
		return "| %s | %s | %s | %.0f | %.2f | %.2f | %.2f | %d |" % [resolution, scenario, phase,
				1000.0 / maxf(cpu_ms(), 0.001), cpu_ms(), cpu_worst, gpu_ms(), roundi(draw_sum / frames)]


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# GameSettings a pu mettre le plein écran et une échelle de rendu : fenêtre sans bordure, rendu à l'échelle 1.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	get_tree().root.scaling_3d_scale = 1.0
	_view = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(_view)
	_orbit = _view.get_node("Orbit") as OrbitSimulation
	_launcher = _view.get_node("NukeLauncher") as NukeLauncher
	_launch_control = _view.find_child("Launch", true, false) as LaunchControl
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	_station.missile_released.connect(func(_s: int, _t: int, _m: Node3D, _v: Vector3) -> void: _released += 1)
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	await _frames(60)

	var screen := DisplayServer.screen_get_size()
	_log("# Banc Star Nuke — %s" % Time.get_datetime_string_from_system(false, true))
	_log("")
	_log("Godot %s, %s (%s), écran %d × %d. V-Sync coupée, fenêtre sans bordure à la résolution mesurée, rendu 3D à "
			% [Engine.get_version_info().string, RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_driver_name(), screen.x, screen.y]
			+ "l'échelle 1. Scénarios : orbite simple (temps x1, %.0f s) ; %d missiles tirés d'un coup, mesurés par "
			% [LIVE_S, MISSILES]
			+ "phase jusqu'à l'impact puis %.0f s d'explosions ; %d explosions de %s figées à chaque instant "
			% [LIVE_S, EXPLOSIONS, NukeScaling.format_yield(YIELD_KT)]
			+ "(%d images). CPU = temps entre deux images (le jeu attend le GPU)." % FRAMES)
	_log("")
	_log("| Résolution | Scénario | Phase | im/s | CPU moy. (ms) | CPU pire (ms) | GPU moy. (ms) | Appels de dessin |")
	_log("|---|---|---|---|---|---|---|---|")
	var notes: Array[String] = []
	for resolution in RESOLUTIONS:
		var label := await _set_resolution(resolution, notes)
		await _scenario_orbit(label)
		await _scenario_missiles(label, notes)
		await _scenario_explosions(label, notes)
	_log("")
	for note in notes:
		_log("- " + note)
	_log("")
	await _breakdown(RESOLUTIONS[-1])
	_write_results()
	get_tree().quit()


## Redimensionne la fenêtre ; renvoie le libellé de la résolution réellement obtenue.
func _set_resolution(resolution: Vector2i, notes: Array[String]) -> String:
	DisplayServer.window_set_size(resolution)
	DisplayServer.window_set_position(Vector2i.ZERO)
	await _frames(10)
	var actual := DisplayServer.window_get_size()
	var label := "%d × %d" % [actual.x, actual.y]
	if actual != resolution:
		notes.append("%d × %d demandé : fenêtre de %s obtenue." % [resolution.x, resolution.y, label])
	return label


func _scenario_orbit(label: String) -> void:
	_reset(1.0)
	await _frames(WARMUP_FRAMES)
	var stats: Dictionary = await _measure_seconds(LIVE_S)
	_log(stats[""].row(label, "Orbite simple", "temps x1"))
	_screenshot(label, "orbite")


## Tire MISSILES missiles sur des cibles autour du point visé et mesure chaque image dans sa phase : sortie du tube
## (animation de la station), propulsion, croisière, rentrée (dès qu'un missile y est), puis explosions à l'arrivée.
func _scenario_missiles(label: String, notes: Array[String]) -> void:
	_reset(1.0)
	await _frames(WARMUP_FRAMES)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var aim := _launcher.get_aim()
	var tubes := _station.available_tubes()
	var fired := 0
	_released = 0
	for i in mini(MISSILES, tubes.size()):
		var target := _launcher.aim_at(aim.latitude + rng.randf_range(-2.0, 2.0),
				aim.longitude + rng.randf_range(-2.5, 2.5))
		if _launch_control.fire_tube(tubes[i], target, YIELD_KT):
			fired += 1
		await get_tree().process_frame
	if fired < MISSILES:
		notes.append("%s : %d missiles tirés sur %d (tubes disponibles : %d)." % [label, fired, MISSILES, tubes.size()])
	var deadline := Time.get_ticks_usec() + int(MISSILES_TIMEOUT_S * 1e6)
	var stats: Dictionary = await _sample(func() -> bool:
		return (_released >= fired and _flights().is_empty()) or Time.get_ticks_usec() > deadline,
		_missile_phase)
	var scenario := "%d missiles" % fired
	for phase: String in ["sortie du tube", "propulsion", "croisière", "rentrée"]:
		if stats.has(phase):
			_log(stats[phase].row(label, scenario, phase))
	var after: Dictionary = await _measure_seconds(LIVE_S)
	_log(after[""].row(label, scenario, "explosions à l'arrivée (0–%.0f s)" % LIVE_S))
	_screenshot(label, "missiles_arrivee")


## Tire EXPLOSIONS explosions d'un coup (orbite figée) et les fige à chaque instant de EXPLOSION_TIMES_S.
func _scenario_explosions(label: String, notes: Array[String]) -> void:
	_reset(0.0)
	await _frames(WARMUP_FRAMES)
	var shot := await _fire(EXPLOSIONS, YIELD_KT)
	notes.append("%s : tir de %d explosions en %.1f ms, pire image après le tir %.1f ms." % [label, EXPLOSIONS, shot.x,
			shot.y])
	var scenario := "%d × %s" % [EXPLOSIONS, NukeScaling.format_yield(YIELD_KT)]
	for t in EXPLOSION_TIMES_S:
		var stats: Dictionary = await _measure_frozen(t)
		_log(stats[""].row(label, scenario, "figées à %s" % _format_time(t)))
		_screenshot(label, "explosions_%s" % _format_time(t).replace(" ", ""))


## Part GPU de chaque effet (EXPLOSIONS explosions à 60 s) : temps GPU sans cet effet.
func _breakdown(resolution: Vector2i) -> void:
	_reset(0.0)
	await _frames(WARMUP_FRAMES)
	await _fire(EXPLOSIONS, YIELD_KT)
	var base: Stats = (await _measure_frozen(60.0))[""]
	_log("Part de chaque effet (%d × %s figées à 60 s, %d × %d) : temps GPU sans cet effet." % [EXPLOSIONS,
			NukeScaling.format_yield(YIELD_KT), resolution.x, resolution.y])
	_log("")
	_log("| Effet coupé | GPU moy. (ms) | Gain (ms) |")
	_log("|---|---|---|")
	_log("| aucun | %.2f | — |" % base.gpu_ms())
	var earth := _view.get_node("Earth")
	var materials: Array[ShaderMaterial] = [earth.get_node("Surface").material_override,
			earth.get_node("CloudLayer").material_override]
	for part in ["Mushroom", "Shock", "nuke_cloud_count", "nuke_ground_count", "nuke_smoke_count"]:
		_toggle(materials, part, false)
		var m: Stats = (await _measure_frozen(60.0))[""]
		_log("| %s | %.2f | %.2f |" % [part, m.gpu_ms(), base.gpu_ms() - m.gpu_ms()])
		_toggle(materials, part, true)


## Même état de départ pour chaque scénario : plus d'explosion, midi au-dessus de Madrid, vitesse du temps donnée.
func _reset(time_scale: float) -> void:
	_launcher.clear_effects()
	_orbit.restart(12.0)
	_orbit.time_scale = time_scale


## Tire count explosions dans le champ de vision (graine fixe). Retour : (durée des appels de tir en ms, pire image
## des 60 suivantes en ms).
func _fire(count: int, yield_kt: float) -> Vector2:
	_launcher.clear_effects()
	await _frames(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var aim := _launcher.get_aim()
	var start := Time.get_ticks_usec()
	for i in count:
		# Jusqu'à ~2,5° autour du point visé.
		_launcher.launch_at(aim.latitude + rng.randf_range(-2.0, 2.0), aim.longitude + rng.randf_range(-2.5, 2.5),
				yield_kt)
	var fire_ms := (Time.get_ticks_usec() - start) / 1000.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for f in 60:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	await _wait_fallout()
	return Vector2(fire_ms, worst)


## Fige les explosions à t (s physiques) et mesure FRAMES images après WARMUP_FRAMES.
func _measure_frozen(t: float) -> Dictionary:
	for effect in _launcher.get_effects():
		effect.time_override_s = t
	await _frames(WARMUP_FRAMES)
	return await _measure_frames(FRAMES)


func _measure_frames(count: int) -> Dictionary:
	var left := {"n": count}
	return await _sample(func() -> bool:
		left.n -= 1
		return left.n <= 0)


func _measure_seconds(seconds: float) -> Dictionary:
	var end := Time.get_ticks_usec() + int(seconds * 1e6)
	return await _sample(func() -> bool: return Time.get_ticks_usec() >= end)


## Mesure image par image jusqu'à ce que done() soit vrai ; chaque image est rangée dans la phase renvoyée par
## phase() : {phase: Stats}.
func _sample(done: Callable, phase: Callable = func() -> String: return "") -> Dictionary:
	var stats := {}
	var last := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var key: String = phase.call()
		if not stats.has(key):
			stats[key] = Stats.new()
		stats[key].add(ms, RenderingServer.viewport_get_measured_render_time_gpu(_rid),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if done.call():
			break
	return stats


## Missiles en vol (ajoutés à la scène courante par LaunchControl).
func _flights() -> Array[MissileFlight]:
	var flights: Array[MissileFlight] = []
	for child in get_children():
		if child is MissileFlight and not child.is_queued_for_deletion():
			flights.append(child)
	return flights


## Phase du vol pour l'image courante : rentrée dès qu'un missile y est, sinon propulsion si un moteur brûle encore.
func _missile_phase() -> String:
	var flights := _flights()
	if flights.is_empty():
		return "sortie du tube"
	for flight in flights:
		if flight.time_left() <= flight.reentry_time():
			return "rentrée"
	for flight in flights:
		if flight.flight_time_s - flight.time_left() < flight.burn_time_s:
			return "propulsion"
	return "croisière"


## Active ou coupe un effet : nœud enfant des explosions (Mushroom, Shock) ou uniforme de compte d'un include (le nœud
## FX qui l'alimente est mis en pause pour qu'il ne le rétablisse pas).
func _toggle(materials: Array[ShaderMaterial], part: String, on: bool) -> void:
	if part.begins_with("nuke_"):
		var fx_name: String = {"nuke_cloud_count": "CloudFX", "nuke_ground_count": "GroundFX",
				"nuke_smoke_count": "GroundFX"}[part]
		var fx := _launcher.get_node(fx_name)
		fx.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if on and fx.has_method(&"refresh"):
			fx.refresh()
		if not on:
			for material in materials:
				if material.shader.get_shader_uniform_list().any(func(u: Dictionary) -> bool: return u.name == part):
					material.set_shader_parameter(part, 0)
		return
	for effect in _launcher.get_effects():
		var node := effect.get_node(part) as Node3D
		node.visible = on
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Attend la fin du calcul des retombées (threads), pour ne pas mesurer leur démarrage.
func _wait_fallout() -> void:
	for i in 600:
		if _launcher.get_effects().all(func(e: NukeEffect) -> bool: return not e.impact_pending and not e.fallout_pending):
			return
		await get_tree().process_frame


## Capture de l'image courante dans SHOTS_DIR/<résolution>_<nom>.png.
func _screenshot(label: String, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS_DIR))
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s_%s.png" % [SHOTS_DIR, label.replace(" × ", "x"), name])


static func _format_time(t: float) -> String:
	if t < 60.0:
		return "%.0f s" % t
	if t < 3600.0:
		return "%.0f min" % (t / 60.0)
	return "%.0f h" % (t / 3600.0)


func _write_results() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String
	if args.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULTS_DIR))
		path = RESULTS_DIR + "/bench_%s.md" % Time.get_datetime_string_from_system().replace(":", "-")
	else:
		path = args[0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(_lines) + "\n")
		print("Résultats : " + path)
	else:
		push_error("Impossible d'écrire " + path)


func _log(line: String) -> void:
	print(line)
	_lines.append(line)
