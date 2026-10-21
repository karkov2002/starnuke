class_name MissionScoring
extends RefCounted
## Règles de notation des missions de campagne (calculs purs, sans état ; utilisés par CampaignDirector et, à terme,
## par le banc d'équilibrage). Notes sur 20. Règles de jeu :
## - précision d'un objectif : distance au sol d (km) entre la cible et le point obtenu (photo : point sous la
##   station à la prise de vue ; tir : point d'impact) : 20 jusqu'à tolérance / 4 (zone parfaite), puis décroît en
##   ligne droite jusqu'à 0 à la tolérance ; un objectif non rempli vaut 0 ;
## - précision de la mission : moyenne des précisions des objectifs, pondérée par leur poids (weight) ;
## - facteur temps : 1 tant que le temps écoulé depuis le départ du chrono ne dépasse pas le temps de référence
##   (par), puis décroît en ligne droite jusqu'à time_floor (0,6 par défaut) à l'échéance (deadline) ;
## - note de la mission = précision × facteur temps ; réussite si note ≥ success_score (10 par défaut).
## Temps de référence par défaut (par_hours absent ou null) : passage le plus tôt possible plus une orbite
## (MissionPlanner, CampaignDirector._par_s).

const MAX_SCORE := 20.0
## Part de la tolérance où la précision est parfaite.
const PERFECT_SHARE := 0.25
## Délai (s de jeu) entre l'arrivée du briefing et le départ du chrono : le temps de se promener un peu.
const START_GRACE_S := 600.0


## Distance au sol (km, grand cercle) entre deux points (latitude, longitude en degrés).
static func distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var a := deg_to_rad(lat1)
	var b := deg_to_rad(lat2)
	var d := sin((b - a) * 0.5) ** 2 + cos(a) * cos(b) * sin(deg_to_rad(lon2 - lon1) * 0.5) ** 2
	return 2.0 * OrbitSimulation.EARTH_RADIUS_KM * asin(sqrt(minf(d, 1.0)))


## Précision (0 à 20) d'un résultat à d km de la cible, pour une tolérance (km).
static func precision(d_km: float, tolerance_km: float) -> float:
	var perfect := tolerance_km * PERFECT_SHARE
	if d_km <= perfect:
		return MAX_SCORE
	return MAX_SCORE * clampf(1.0 - (d_km - perfect) / (tolerance_km - perfect), 0.0, 1.0)


## Facteur temps (time_floor à 1) après elapsed_s secondes, temps de référence par_s, échéance deadline_s.
static func time_factor(elapsed_s: float, par_s: float, deadline_s: float, time_floor: float) -> float:
	if elapsed_s <= par_s or deadline_s <= par_s:
		return 1.0
	return lerpf(1.0, time_floor, clampf((elapsed_s - par_s) / (deadline_s - par_s), 0.0, 1.0))


## Précision de la mission : moyenne pondérée des précisions (precisions[i] : NAN si l'objectif n'est pas rempli,
## compté 0), poids weights[i].
static func mission_precision(precisions: Array, weights: Array) -> float:
	var total := 0.0
	var weight_sum := 0.0
	for i in precisions.size():
		var p: float = precisions[i]
		total += (0.0 if is_nan(p) else p) * float(weights[i])
		weight_sum += float(weights[i])
	return total / weight_sum if weight_sum > 0.0 else 0.0
