class_name MissionRun
extends RefCounted
## Mission de campagne en cours (CampaignDirector en crée une à la réception du briefing et la lâche à la fin) :
## chrono, temps de référence, objectifs remplis et note. Règles de jeu :
## - le chrono part à started_unix (arrivée du briefing) ; échéance deadline_s après (CampaignData.deadline_s) ;
## - temps de référence (plan) : par_hours, sinon le passage le plus tôt possible pour tous les objectifs,
##   manœuvres comprises (MissionPlanner), plus une orbite ; au plus l'échéance (CampaignData.par_s) ;
## - un impact (record) à moins de la tolérance d'une cible remplit le premier objectif « strike » encore ouvert dont
##   l'objectif préalable « after » est rempli, avec la précision obtenue (MissionScoring.precision) ; plus loin, il
##   ne compte pas ;
## - une photo envoyée au sol (record avec min_precision = success_score, CampaignDirector.send_photo) est notée
##   comme un impact (précision sur 20 selon la distance du point photographié à la cible) mais ne remplit l'objectif
##   « photo » que si sa note atteint success_score (photo valide) ; sinon on peut en envoyer une autre ;
## - note (result) : mission complète : précision pondérée × facteur temps (MissionScoring), réussite si
##   ≥ success_score ; échéance atteinte avant la fin : mission échouée, note 0 (expired).

var id := ""
var mission := {}
## Départ du chrono (heure UTC, s), échéance et temps de référence (s, depuis le départ), passage le plus tôt
## possible (s ; INF : impossible à temps).
var started_unix := 0.0
var deadline_s := 0.0
var par_s := 0.0
var earliest_s := INF
## Précision de chaque objectif (NAN : pas rempli).
var precisions: Array[float] = []

var _defaults := {}


func _init(mission_id: String, mission_data: Dictionary, defaults: Dictionary, now_unix: float) -> void:
	id = mission_id
	mission = mission_data
	_defaults = defaults
	started_unix = now_unix
	deadline_s = CampaignData.deadline_s(mission)
	par_s = deadline_s
	for _objective in mission.objectives:
		precisions.append(NAN)


## Passage le plus tôt possible depuis maintenant (MissionPlanner, depuis l'état de l'orbite) et temps de référence ;
## sans orbite, le temps de référence vaut par_hours, sinon l'échéance.
func plan(orbit: OrbitSimulation) -> void:
	earliest_s = INF
	var period := 0.0
	if orbit:
		var state := MissionPlanner.state_of(orbit)
		earliest_s = MissionPlanner.earliest(state, mission.objectives, 0.0, deadline_s).time
		period = MissionPlanner.period_s(state)
	par_s = CampaignData.par_s(mission, earliest_s, period)


## Temps écoulé depuis le départ du chrono (s).
func elapsed_s(now_unix: float) -> float:
	return now_unix - started_unix


## Échéance atteinte.
func is_due(now_unix: float) -> bool:
	return elapsed_s(now_unix) >= deadline_s


## Tous les objectifs remplis.
func is_complete() -> bool:
	return not precisions.any(func(p: float) -> bool: return is_nan(p))


## Photo ou impact (type) en (lat, lon) : remplit au plus un objectif, si sa précision atteint min_precision. Rend
## {nearest_km : distance à la cible de ce type la plus proche (−1 : aucune), objective : indice de l'objectif rempli
## (−1 : aucun), precision : celle de l'objectif rempli, sinon la meilleure obtenue sur un objectif ouvert (0 : hors
## tolérance de tous)}.
func record(type: String, lat: float, lon: float, min_precision := 0.0) -> Dictionary:
	var objectives: Array = mission.objectives
	var nearest := INF
	var filled := -1
	var best := 0.0
	for k in objectives.size():
		var objective: Dictionary = objectives[k]
		if objective.type != type:
			continue
		var d := GeoMath.distance_km(lat, lon, float(objective.target.lat), float(objective.target.lon))
		nearest = minf(nearest, d)
		if filled >= 0 or not is_nan(precisions[k]):
			continue
		if objective.has("after") and is_nan(precisions[int(objective.after)]):
			continue
		var tolerance := MissionScoring.tolerance_km(objective, _defaults)
		if d >= tolerance:
			continue
		var precision := MissionScoring.precision(d, tolerance)
		best = maxf(best, precision)
		if precision >= min_precision:
			precisions[k] = precision
			filled = k
	return {"nearest_km": nearest if nearest < INF else -1.0, "objective": filled,
			"precision": precisions[filled] if filled >= 0 else best}


## Un objectif de ce type est-il encore ouvert (son objectif préalable « after » rempli) ?
func has_open(type: String) -> bool:
	var objectives: Array = mission.objectives
	for k in objectives.size():
		var objective: Dictionary = objectives[k]
		if objective.type == type and is_nan(precisions[k]) \
				and not (objective.has("after") and is_nan(precisions[int(objective.after)])):
			return true
	return false


## Note de la mission à now_unix : {score, success, precision, time_factor, expired, day : day_id} (forme retenue dans
## CampaignSession.results et la sauvegarde) ; incomplète (échéance atteinte) : échouée, note 0.
func result(now_unix: float, day_id: String) -> Dictionary:
	if not is_complete():
		return {"score": 0.0, "success": false, "precision": 0.0, "time_factor": 0.0, "expired": true, "day": day_id}
	var weights: Array = mission.objectives.map(func(o: Dictionary) -> float: return float(o.get("weight", 1.0)))
	var precision := MissionScoring.mission_precision(precisions, weights)
	var factor := MissionScoring.time_factor(elapsed_s(now_unix), par_s, deadline_s,
			float(_defaults.get("time_floor", 0.6)))
	var score := precision * factor
	return {"score": score, "success": score >= float(_defaults.get("success_score", 10.0)),
			"precision": precision, "time_factor": factor, "expired": false, "day": day_id}


## Détail pour le journal de partie : temps écoulé, référence, échéance, mission complète, précisions (−1 : objectif
## non rempli).
func report(now_unix: float) -> Dictionary:
	return {"elapsed_s": elapsed_s(now_unix), "par_s": par_s, "deadline_s": deadline_s, "complete": is_complete(),
			"precisions": precisions.map(func(p: float) -> float: return -1.0 if is_nan(p) else p)}
