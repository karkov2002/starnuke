extends Node
## Banc CPU headless (lot 3 de l'audit : boucles par image) : mesure le temps de traitement par image
## (Performance.TIME_PROCESS + TIME_PHYSICS_PROCESS : scripts et moteur, sans rendu) de la scène du jeu dans
## plusieurs états, depuis le même point de départ (orbite placée à une date fixe, temps ×1) : orbite seule ; dix
## explosions de 1 Mt figées à 5 s, 60 s, 1 800 s et 21 600 s ; assis au poste de pilotage ; tablette sortie.
## La machine n'est jamais seule (éditeur, autres programmes) : chaque état est mesuré ROUNDS fois en alternance et
## on garde le meilleur passage (moyenne tronquée sur FRAMES images : 10 % des plus rapides et des plus lentes
## écartées). « --breakdown » ajoute une ventilation par nœud dans deux états : chaque nœud désactivé tour à tour
## (process_mode), avec une mesure de référence juste avant chacun, l'économie étant la différence (bruitée en
## dessous de ~0,5 ms). Résultats en console (Markdown) et dans tools/bench/results/cpu_<date>.md. À comparer en A/B
## entre deux versions du code sur la même machine. Usage :
##   godot --headless --path . res://tools/bench/cpu_probe.tscn [-- [<résultats.md>] [--breakdown]]

const FRAMES := 60
const WARMUP := 20
const ROUNDS := 5
const BREAKDOWN_FRAMES := 80
const EXPLOSIONS := 10
const YIELD_KT := 1000.0
const TIMES_S: Array[float] = [5.0, 60.0, 1800.0, 21600.0]
## Nœuds ventilés dans l'état « 5 s » (coûteux : seulement les candidats plausibles).
const EARLY_CANDIDATES: Array[String] = ["Orbit", "EarthScene", "Earth", "Station", "Observer", "Hud", "Exposure",
		"NukeReport", "NukeLauncher/FlashFX", "NukeLauncher/CloudFX", "NukeLauncher/GroundFX", "NukeLauncher/Impact",
		"Effets/Flash", "Effets/Shock", "Effets/Mushroom"]
const RESULTS_DIR := "res://tools/bench/results"

var _lines: Array[String] = []
var _effects: Array[NukeEffect] = []


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(pred: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _ready() -> void:
	var args := PackedStringArray(OS.get_cmdline_user_args())
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	await _frames(30)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	var pilot := view.get_node("PilotConsole") as ScreenSeatConsole
	var tablet := view.get_node("Observer/Camera/Tablet")
	orbit.place(CampaignData.parse_utc("2035-07-15T06:00:00Z"), 400.0, 51.6, 40.4, -3.7, true)
	orbit.time_scale = 1.0
	# Mise en route (tuiles HD, écrans) hors mesure.
	await _frames(240)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in EXPLOSIONS:
		_effects.append(launcher.launch_at(40.4 + rng.randf_range(-2.0, 2.0), -3.7 + rng.randf_range(-2.5, 2.5),
				YIELD_KT))
	await _until(func() -> bool:
		return _effects.all(func(e: NukeEffect) -> bool:
			return not e.impact_pending and not e.fallout_pending and e.smoke_yield_kg_m2 >= 0.0), 60.0)
	# Explosions mises de côté (hors de l'arbre) pour l'état « orbite seule ».
	var earth := launcher.get_earth()

	var states: Array = [
		["Orbite seule", func() -> void:
			for effect in _effects:
				if effect.get_parent():
					earth.remove_child(effect)],
	]
	for t in TIMES_S:
		states.append(["%d explosions figées à %s" % [EXPLOSIONS, _format_time(t)], func() -> void:
			_restore_effects(earth)
			for effect in _effects:
				effect.time_override_s = t])
	states.append(["Assis au poste de pilotage (explosions à 6 h)", func() -> void:
		_restore_effects(earth)
		for effect in _effects:
			effect.time_override_s = 21600.0
		pilot.call("_sit")])
	states.append(["Tablette sortie (explosions à 6 h)", func() -> void:
		_restore_effects(earth)
		pilot.stand_up()
		tablet.call("_set_wanted", true)])

	_lines.append("| État | ms / image (meilleur passage, moy. tronquée) |")
	_lines.append("|---|---|")
	var best := {}
	for round in ROUNDS:
		for state: Array in states:
			(state[1] as Callable).call()
			await _frames(60)
			var ms := await _sample(FRAMES, WARMUP)
			best[state[0]] = minf(best.get(state[0], INF), ms)
			print("  passage %d, %s : %.3f ms" % [round + 1, state[0], ms])
		tablet.call("_set_wanted", false)
		await _frames(60)
	for state: Array in states:
		_lines.append("| %s | %.3f |" % [state[0], best[state[0]]])

	if args.has("--breakdown"):
		await _breakdown_all(view, launcher, earth)

	var header := "# Banc CPU (headless) — %s\n\n%d explosions de %s ; %d passages par état, %d images chacun.\n\n" % [
			Time.get_datetime_string_from_system(), EXPLOSIONS, NukeScaling.format_yield(YIELD_KT), ROUNDS, FRAMES]
	var report := header + "\n".join(_lines) + "\n"
	print(report)
	var path := RESULTS_DIR.path_join("cpu_%s.md" % Time.get_date_string_from_system())
	if args.size() > 0 and not args[0].begins_with("--"):
		path = args[0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(report)
		print("Résultats : " + ProjectSettings.globalize_path(path))
	get_tree().quit(0)


## Ventilation par nœud : nœuds de premier niveau, nœuds du lanceur, composants des explosions ; à 6 h (tous) puis à
## 5 s (EARLY_CANDIDATES).
func _breakdown_all(view: Node, launcher: NukeLauncher, earth: Node3D) -> void:
	_restore_effects(earth)
	var candidates := {}
	for child in view.get_children():
		if child != launcher:
			candidates[String(child.name)] = [child]
	for child in launcher.get_children():
		candidates["NukeLauncher/" + String(child.name)] = [child]
	for part in ["Flash", "Shock", "Mushroom"]:
		var nodes := []
		for effect in _effects:
			var node := effect.get_node_or_null(part)
			if node:
				nodes.append(node)
		candidates["Effets/" + part] = nodes
	for effect in _effects:
		effect.time_override_s = 21600.0
	await _breakdown("explosions à 6 h", candidates)
	var early := {}
	for name in EARLY_CANDIDATES:
		if candidates.has(name):
			early[name] = candidates[name]
	for effect in _effects:
		effect.time_override_s = 5.0
	await _breakdown("explosions à 5 s", early)


func _restore_effects(earth: Node3D) -> void:
	for effect in _effects:
		if effect.get_parent() == null:
			earth.add_child(effect)


## Moyenne tronquée (ms) du temps de traitement par image sur frames images, après warmup.
func _sample(frames: int, warmup: int) -> float:
	await _frames(warmup)
	var samples := PackedFloat64Array()
	for i in frames:
		await get_tree().process_frame
		samples.append((Performance.get_monitor(Performance.TIME_PROCESS)
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	samples.sort()
	var cut := int(frames * 0.1)
	var total := 0.0
	for i in range(cut, frames - cut):
		total += samples[i]
	return total / float(frames - 2 * cut)


## Part de chaque nœud dans le temps par image : chacun est désactivé tour à tour (process_mode) juste après une
## mesure de référence ; l'économie est la différence (deux passages, le plus grand gardé).
func _breakdown(label: String, candidates: Dictionary) -> void:
	var rows: Array = []
	var references := PackedFloat64Array()
	for name: String in candidates:
		var nodes: Array = candidates[name]
		var saving := -INF
		for round in 2:
			var base := await _sample(BREAKDOWN_FRAMES, 10)
			references.append(base)
			for node: Node in nodes:
				node.process_mode = Node.PROCESS_MODE_DISABLED
			var without := await _sample(BREAKDOWN_FRAMES, 10)
			for node: Node in nodes:
				node.process_mode = Node.PROCESS_MODE_INHERIT
			saving = maxf(saving, base - without)
		rows.append([name, saving])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	references.sort()
	_lines.append("")
	_lines.append("Ventilation — %s (référence médiane %.3f ms) : économie quand le nœud est désactivé" % [label,
			references[references.size() / 2]])
	_lines.append("")
	_lines.append("| Nœud | ms / image |")
	_lines.append("|---|---|")
	for row: Array in rows:
		if row[1] > 0.05:
			_lines.append("| %s | %.3f |" % [row[0], row[1]])
	print("  ventilation %s faite" % label)


static func _format_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % int(seconds)
	if seconds < 3600.0:
		return "%d min" % int(seconds / 60.0)
	return "%d h" % int(seconds / 3600.0)
