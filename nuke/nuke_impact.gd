class_name NukeImpact
extends Node
## Bilan d'une explosion, créé par NukeLauncher (nœud Impact) : à chaque tir (signal detonated), il calcule hors du
## fil principal (WorkerThreadPool) :
## 1. les pertes du souffle et de la chaleur (NukeCasualties.estimate) et l'effet sur le réseau électrique
##    (NukeGridImpact.assess), quelques ms à ~40 ms, et la fumée des incendies par m² en feu, selon la population
##    (NukeSmokeYield.estimate) ;
## 2. les retombées (NukeFallout.estimate), jusqu'à quelques secondes pour 50 Mt ;
## puis renseigne la NukeEffect (casualties, grid, smoke_yield_kg_m2, fallout) dans le fil principal et écrit le bilan
## en console (NukeReportText). L'écriture en console coûte plusieurs ms par ligne (sortie de l'éditeur) : elle se fait dans le
## thread de calcul, jamais pendant une image.
## Tant que les résultats manquent, NukeEffect.impact_pending / fallout_pending le signalent (fenêtre de bilan).
##
## Fin de partie ou du jeu (_exit_tree) : un bilan de 50 Mt prend plusieurs secondes (dix d'un coup : ~12 s) ; les
## tâches sont abandonnées (NukePopulationScan.abort, testé à chaque ligne de la grille) puis attendues — les tâches
## finies aussi, sinon elles ne sont jamais libérées — pour que rien ne tourne plus pendant la destruction de la scène
## (sinon : attente à la fermeture, puis plantage).

## Tâches en cours ou terminées non encore attendues (identifiants WorkerThreadPool).
var _tasks: Array[int] = []


func setup(launcher: NukeLauncher) -> void:
	launcher.detonated.connect(_on_detonated)


func _exit_tree() -> void:
	NukePopulationScan.abort = true
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	NukePopulationScan.abort = false


func _on_detonated(effect: NukeEffect) -> void:
	var params := effect.params
	effect.impact_pending = true
	effect.fallout_pending = NukeScaling.low_burst(params.yield_kt, params.burst_height_km) > 0.01
	# Les tâches finies sont attendues (libérées) au passage.
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	_tasks.append(WorkerThreadPool.add_task(_compute.bind(effect.get_instance_id(), params)))


## Dans un thread : calculs et textes. Les résultats sont remis à l'explosion par _apply (fil principal), désignée par
## son identifiant : elle a pu être effacée entre-temps. Abandon (NukePopulationScan.abort) : résultats partiels jetés.
func _compute(effect_id: int, params: NukeParams) -> void:
	var casualties := NukeCasualties.estimate(params)
	if NukePopulationScan.abort:
		return
	var grid := NukeGridImpact.assess(params)
	var smoke := NukeSmokeYield.estimate(params)
	_apply.call_deferred(effect_id, {"casualties": casualties, "grid": grid, "smoke": smoke})
	print("%s\n%s\n%s" % [NukeReportText.launch(params), NukeReportText.casualties(casualties),
			NukeReportText.grid(grid)])
	if NukeScaling.low_burst(params.yield_kt, params.burst_height_km) > 0.01:
		var fallout := NukeFallout.estimate(params, casualties.radii_km)
		if NukePopulationScan.abort:
			return
		_apply.call_deferred(effect_id, {"fallout": fallout})
		print(NukeReportText.fallout(fallout, params))


func _apply(effect_id: int, results: Dictionary) -> void:
	var effect := instance_from_id(effect_id) as NukeEffect
	if effect == null:
		return
	if results.has("casualties"):
		effect.casualties = results.casualties
		effect.grid = results.grid
		effect.smoke_yield_kg_m2 = results.smoke
		effect.impact_pending = false
	if results.has("fallout"):
		effect.fallout = results.fallout
		effect.fallout_pending = false
