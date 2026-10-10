class_name NukeImpact
extends Node
## Bilan d'une explosion, créé par NukeLauncher (nœud Impact) : à chaque tir (signal detonated), il calcule hors du
## fil principal (WorkerThreadPool) :
## 1. les pertes du souffle et de la chaleur (NukeCasualties.estimate) et l'effet sur le réseau électrique
##    (NukeGridImpact.assess), quelques ms à ~40 ms ;
## 2. les retombées (NukeFallout.estimate), jusqu'à quelques secondes pour 50 Mt ;
## puis renseigne la NukeEffect (casualties, grid, fallout) dans le fil principal et écrit le bilan en console
## (NukeReportText). L'écriture en console coûte plusieurs ms par ligne (sortie de l'éditeur) : elle se fait dans le
## thread de calcul, jamais pendant une image.
## Tant que les résultats manquent, NukeEffect.impact_pending / fallout_pending le signalent (fenêtre de bilan).


func setup(launcher: NukeLauncher) -> void:
	launcher.detonated.connect(_on_detonated)


func _on_detonated(effect: NukeEffect) -> void:
	var params := effect.params
	effect.impact_pending = true
	effect.fallout_pending = NukeScaling.low_burst(params.yield_kt, params.burst_height_km) > 0.01
	WorkerThreadPool.add_task(_compute.bind(effect.get_instance_id(), params))


## Dans un thread : calculs et textes. Les résultats sont remis à l'explosion par _apply (fil principal), désignée par
## son identifiant : elle a pu être effacée entre-temps.
func _compute(effect_id: int, params: NukeParams) -> void:
	var casualties := NukeCasualties.estimate(params)
	var grid := NukeGridImpact.assess(params)
	_apply.call_deferred(effect_id, {"casualties": casualties, "grid": grid})
	print("%s\n%s\n%s" % [NukeReportText.launch(params), NukeReportText.casualties(casualties),
			NukeReportText.grid(grid)])
	if NukeScaling.low_burst(params.yield_kt, params.burst_height_km) > 0.01:
		var fallout := NukeFallout.estimate(params, casualties.radii_km)
		_apply.call_deferred(effect_id, {"fallout": fallout})
		print(NukeReportText.fallout(fallout, params))


func _apply(effect_id: int, results: Dictionary) -> void:
	var effect := instance_from_id(effect_id) as NukeEffect
	if effect == null:
		return
	if results.has("casualties"):
		effect.casualties = results.casualties
		effect.grid = results.grid
		effect.impact_pending = false
	if results.has("fallout"):
		effect.fallout = results.fallout
		effect.fallout_pending = false
