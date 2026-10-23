class_name MissionRun
extends RefCounted
## Mission de campagne en cours (CampaignDirector en crée une à la réception du briefing et la lâche à la fin) :
## chrono, temps de référence, objectifs remplis et note. Règles de jeu :
## - le chrono part à started_unix (arrivée du briefing) ; échéance deadline_s après (CampaignData.deadline_s) ;
## - temps de référence (plan) : par_hours, sinon le passage le plus tôt possible pour tous les objectifs,
##   manœuvres comprises (MissionPlanner), plus une orbite ; au plus l'échéance (CampaignData.par_s) ;
## - une photo ou un impact (record) à moins de la tolérance d'une cible remplit le premier objectif encore ouvert de
##   ce type dont l'objectif préalable « after » est rempli, avec la précision obtenue (MissionScoring.precision) ;
##   plus loin, il ne compte pas ;
## - note (result) : précision pondérée × facteur temps (MissionScoring), réussite si ≥ success_score ; un objectif
##   non rempli vaut 0.

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


## Photo ou impact (type) en (lat, lon) : remplit au plus un objectif. Rend {nearest_km : distance à la cible de ce
## type la plus proche (−1 : aucune), objective : indice de l'objectif rempli (−1 : aucun), precision}.
func record(type: String, lat: float, lon: float) -> Dictionary:
	var objectives: Array = mission.objectives
	var nearest := INF
	var filled := -1
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
		if d < tolerance:
			precisions[k] = MissionScoring.precision(d, tolerance)
			filled = k
	return {"nearest_km": nearest if nearest < INF else -1.0, "objective": filled,
			"precision": precisions[filled] if filled >= 0 else 0.0}


## Note de la mission à now_unix : {score, success, precision, time_factor, day : day_id} (forme retenue dans
## Campaigns.results et la sauvegarde).
func result(now_unix: float, day_id: String) -> Dictionary:
	var weights: Array = mission.objectives.map(func(o: Dictionary) -> float: return float(o.get("weight", 1.0)))
	var precision := MissionScoring.mission_precision(precisions, weights)
	var factor := MissionScoring.time_factor(elapsed_s(now_unix), par_s, deadline_s,
			float(_defaults.get("time_floor", 0.6)))
	var score := precision * factor
	return {"score": score, "success": score >= float(_defaults.get("success_score", 10.0)),
			"precision": precision, "time_factor": factor, "day": day_id}


## Détail pour le journal de partie : temps écoulé, référence, échéance, mission complète, précisions (−1 : objectif
## non rempli).
func report(now_unix: float) -> Dictionary:
	return {"elapsed_s": elapsed_s(now_unix), "par_s": par_s, "deadline_s": deadline_s, "complete": is_complete(),
			"precisions": precisions.map(func(p: float) -> float: return -1.0 if is_nan(p) else p)}
