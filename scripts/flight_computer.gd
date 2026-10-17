class_name FlightComputer
extends Node
## Ordinateur de vol (nœud FlightComputer de scenes/orbit_view.tscn) : planifie les manœuvres orbitales du poste de
## pilotage (scripts/pilot_console.gd). L'orbite elle-même reste dans Orbit (scripts/orbit.gd) ; l'écran ne fait
## qu'afficher et transmettre les commandes.
## - Cible : inclinaison (0–80°) et altitude (400–800 km) visées. Tant qu'elles diffèrent de l'orbite réelle, une
##   manœuvre est prévue (has_plan) et son orbite, la « trace fantôme » (ghost track), est dessinée en pointillés :
##   anneau 3D autour de la Terre (GhostTrack) et trace au sol sur la carte.
## - La manœuvre se fait au prochain nœud (passage à l'équateur) : l'orbite fantôme passe par ce point, avec
##   l'inclinaison et l'altitude visées ; un changement de plan au nœud fait tourner l'orbite autour de la ligne des
##   nœuds, qui reste en place (même Ω). C'est une orbite fixe dans le repère inertiel : la Terre tourne dessous.
## - Poussée, seulement dans la fenêtre du nœud (WINDOW_S secondes réelles de part et d'autre, soit WINDOW_S × la
##   vitesse du temps en temps de jeu, au plus MAX_WINDOW_GAME_S) :
##   - mode Auto : au passage du nœud, l'orbite prend exactement l'inclinaison et l'altitude visées ;
##   - mode Manuel : le joueur maintient BURN (temps ramené à ×1). La durée requise croît avec le Δv
##     (required_hold_s). La poussée s'applique progressivement pendant l'appui (fraction = durée tenue / durée
##     requise ; au-delà de 100 %, elle dépasse la cible, jusqu'à MAX_BURN_RATIO où elle s'arrête d'elle-même). Relâché
##     à ±PERFECT_TOLERANCE de la durée requise : poussée parfaite, l'orbite prend exactement la cible. Sinon
##     (sous-poussée ou sur-poussée), la fraction appliquée reste, et l'écart de dosage ajoute des erreurs
##     aléatoires sur l'inclinaison et l'altitude (proportionnelles à l'écart). La cible ne change pas : la manœuvre
##     reste prévue et se corrige au nœud suivant. L'orbite reste toujours circulaire.

signal plan_changed
## Fin d'une poussée : qualité (BurnQuality) et rapport durée tenue / durée requise (1 en mode Auto).
signal burn_finished(quality: int, ratio: float)

enum Mode { AUTO, MANUAL }
enum BurnQuality { PERFECT, UNDER, OVER }

const GROUP := &"flight_computer"
const MIN_TARGET_ALTITUDE_KM := 400.0
const MAX_TARGET_ALTITUDE_KM := 800.0
## Écarts en deçà desquels la cible est considérée comme atteinte (pas de manœuvre prévue).
const INCLINATION_TOLERANCE_DEG := 0.05
const ALTITUDE_TOLERANCE_KM := 0.5
## Demi-largeur de la fenêtre du nœud, en secondes réelles (temps de jeu = × vitesse du temps).
const WINDOW_S := 5.0
const MAX_WINDOW_GAME_S := 60.0
## Poussée parfaite : relâchée à ±5 % de la durée requise.
const PERFECT_TOLERANCE := 0.05
## La poussée s'arrête d'elle-même à 150 % de la durée requise.
const MAX_BURN_RATIO := 1.5
## Erreurs aléatoires (amplitude maximale) pour un écart de dosage de 100 % ; proportionnelles à l'écart.
const INCLINATION_ERROR_DEG := 2.0
const ALTITUDE_ERROR_KM := 60.0

@export var orbit_path: NodePath = ^"../Orbit"

var target_inclination_deg := 0.0
var target_altitude_km := 400.0
var mode := Mode.MANUAL
## Poussée manuelle en cours, durée tenue et durée requise (s réelles).
var burning := false
var burn_hold_s := 0.0
var burn_required_s := 0.0
## Dernière poussée : {quality, ratio, ticks_ms} (vide avant la première).
var last_burn := {}

var _orbit: OrbitSimulation
## Orbite et cible au début de la poussée en cours, et nœud de la poussée.
var _burn_start := {}
## Prochain nœud à l'image précédente (mode Auto : détection du passage).
var _previous_next_node := NAN


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node(orbit_path) as OrbitSimulation
	reset_target()


func _process(delta: float) -> void:
	if burning:
		burn_hold_s += delta
		_apply_fraction(burn_hold_s / burn_required_s)
		if burn_hold_s >= burn_required_s * MAX_BURN_RATIO:
			end_burn()
	var next_node := _orbit.get_next_node_time_s()
	# Mode Auto : le prochain nœud a changé parce que la station vient de passer l'équateur (et non parce que
	# l'orbite a été modifiée : le nœud passé est tout proche).
	if mode == Mode.AUTO and has_plan() and not is_nan(_previous_next_node) and next_node > _previous_next_node + 1.0 \
			and absf(_previous_next_node - _orbit.sim_time_s) <= get_window_game_s():
		_orbit.altitude_km = target_altitude_km
		_orbit.inclination_deg = target_inclination_deg
		_finish(BurnQuality.PERFECT, 1.0)
	_previous_next_node = next_node


func get_orbit() -> OrbitSimulation:
	return _orbit


## Cible ramenée sur l'orbite réelle (plus de manœuvre prévue).
func reset_target() -> void:
	target_inclination_deg = _orbit.inclination_deg
	target_altitude_km = clampf(_orbit.altitude_km, MIN_TARGET_ALTITUDE_KM, MAX_TARGET_ALTITUDE_KM)
	plan_changed.emit()


func set_target(inclination_deg: float, altitude_km: float) -> void:
	target_inclination_deg = clampf(inclination_deg, 0.0, OrbitSimulation.MAX_INCLINATION_DEG)
	target_altitude_km = clampf(altitude_km, MIN_TARGET_ALTITUDE_KM, MAX_TARGET_ALTITUDE_KM)
	plan_changed.emit()


## Une manœuvre est-elle prévue (cible différente de l'orbite réelle) ?
func has_plan() -> bool:
	return absf(target_inclination_deg - _orbit.inclination_deg) > INCLINATION_TOLERANCE_DEG \
			or absf(target_altitude_km - _orbit.altitude_km) > ALTITUDE_TOLERANCE_KM


func set_mode(value: Mode) -> void:
	if burning:
		end_burn()
	mode = value


#region Nœud de la manœuvre

## Temps simulé (s) du nœud de la manœuvre : celui de la poussée en cours, le nœud tout juste passé tant que sa
## fenêtre est ouverte, sinon le prochain.
func get_node_time_s() -> float:
	if burning:
		return _burn_start.node_time
	var next_node := _orbit.get_next_node_time_s()
	if _orbit.inclination_deg >= 0.01:
		var previous_node := next_node - PI / _orbit.get_mean_motion()
		if _orbit.sim_time_s - previous_node <= get_window_game_s():
			return previous_node
	return next_node


## Temps de jeu (s) restant avant le nœud de la manœuvre (négatif juste après son passage).
func get_countdown_s() -> float:
	return get_node_time_s() - _orbit.sim_time_s


## Demi-largeur de la fenêtre du nœud en temps de jeu.
func get_window_game_s() -> float:
	return minf(WINDOW_S * maxf(_orbit.time_scale, 1.0), MAX_WINDOW_GAME_S)


## La station est-elle dans la fenêtre du nœud (orbite équatoriale : toujours) ?
func is_in_window() -> bool:
	return _orbit.inclination_deg < 0.01 or absf(get_countdown_s()) <= get_window_game_s()


func is_node_ascending() -> bool:
	return _orbit.is_ascending_node_at(get_node_time_s())

#endregion

#region Orbite fantôme

## Éléments de l'orbite fantôme (orbite visée, partant du prochain nœud) : radius_km, inclination (rad),
## raan (rad), node_arg_lat (argument de latitude au nœud : 0 ascendant, π descendant), node_time_s,
## mean_motion (rad/s).
func get_ghost() -> Dictionary:
	var node_time := get_node_time_s()
	var at_node := _orbit.get_position_eci(node_time)
	var ascending := is_node_ascending() or _orbit.inclination_deg < 0.01
	var raan := atan2(at_node.y, at_node.x)
	if not ascending:
		raan += PI
	return {
		"radius_km": OrbitSimulation.EARTH_RADIUS_KM + target_altitude_km,
		"inclination": deg_to_rad(target_inclination_deg),
		"raan": raan,
		"node_arg_lat": 0.0 if ascending else PI,
		"node_time_s": node_time,
		"mean_motion": OrbitSimulation.mean_motion_at(target_altitude_km),
	}


## Point survolé (latitude, longitude en degrés) au temps time_s sur l'orbite fantôme ghost (voir get_ghost).
func ghost_ground_point(ghost: Dictionary, time_s: float) -> Vector2:
	var arg_lat: float = ghost.node_arg_lat + ghost.mean_motion * (time_s - ghost.node_time_s)
	var eci := OrbitSimulation.circular_position_eci(ghost.radius_km, ghost.inclination, ghost.raan, arg_lat)
	return OrbitSimulation.ecef_to_lat_lon(_orbit.eci_to_ecef(eci, time_s))


## Δv (km/s) de la manœuvre prévue : changement de plan 2·v·sin(Δi/2) plus transfert de Hohmann entre les deux
## altitudes (somme des deux impulsions).
func get_delta_v_km_s() -> float:
	var r1 := _orbit.get_semi_major_axis_km()
	var r2 := OrbitSimulation.EARTH_RADIUS_KM + target_altitude_km
	var v1 := sqrt(OrbitSimulation.MU_KM3_S2 / r1)
	var v2 := sqrt(OrbitSimulation.MU_KM3_S2 / r2)
	var plane := 2.0 * v1 * sin(deg_to_rad(absf(target_inclination_deg - _orbit.inclination_deg)) * 0.5)
	var transfer := absf(v1 * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)) + absf(v2 * (1.0 - sqrt(2.0 * r1 / (r1 + r2))))
	return plane + transfer

#endregion

#region Poussée

## Durée (s réelles) d'appui sur BURN requise pour un Δv donné : 1,5 s + 2,5 s × √(Δv en km/s), au plus 8 s
## (~2,3 s pour 100 m/s, ~6,6 s pour 4,2 km/s).
static func required_hold_s(delta_v_km_s: float) -> float:
	return clampf(1.5 + 2.5 * sqrt(delta_v_km_s), 1.5, 8.0)


## BURN utilisable : mode Manuel, manœuvre prévue, fenêtre du nœud ouverte, pas de poussée en cours.
func can_burn() -> bool:
	return mode == Mode.MANUAL and not burning and has_plan() and is_in_window()


## Début de l'appui sur BURN (temps ramené à ×1). Renvoie false si BURN n'est pas utilisable.
func start_burn() -> bool:
	if not can_burn():
		return false
	_orbit.time_scale = 1.0
	_burn_start = {"inclination": _orbit.inclination_deg, "altitude": _orbit.altitude_km,
			"target_inclination": target_inclination_deg, "target_altitude": target_altitude_km,
			"node_time": get_node_time_s()}
	burn_required_s = required_hold_s(get_delta_v_km_s())
	burn_hold_s = 0.0
	burning = true
	return true


## Relâchement de BURN (ou arrêt automatique à MAX_BURN_RATIO) : poussée parfaite ou erreurs de dosage.
func end_burn() -> void:
	if not burning:
		return
	burning = false
	var ratio := burn_hold_s / burn_required_s
	if absf(ratio - 1.0) <= PERFECT_TOLERANCE:
		_apply_fraction(1.0)
		_finish(BurnQuality.PERFECT, ratio)
		return
	_apply_fraction(ratio)
	var error := absf(ratio - 1.0)
	_orbit.altitude_km = clampf(_orbit.altitude_km + randf_range(-1.0, 1.0) * ALTITUDE_ERROR_KM * error,
			OrbitSimulation.MIN_ALTITUDE_KM, OrbitSimulation.MAX_ALTITUDE_KM)
	_orbit.inclination_deg = clampf(_orbit.inclination_deg + randf_range(-1.0, 1.0) * INCLINATION_ERROR_DEG * error,
			0.0, OrbitSimulation.MAX_INCLINATION_DEG)
	_finish(BurnQuality.UNDER if ratio < 1.0 else BurnQuality.OVER, ratio)


## Part fraction (0 à MAX_BURN_RATIO) de la manœuvre appliquée à l'orbite du début de la poussée, au point courant.
func _apply_fraction(fraction: float) -> void:
	_orbit.altitude_km = clampf(lerpf(_burn_start.altitude, _burn_start.target_altitude, fraction),
			OrbitSimulation.MIN_ALTITUDE_KM, OrbitSimulation.MAX_ALTITUDE_KM)
	_orbit.inclination_deg = clampf(lerpf(_burn_start.inclination, _burn_start.target_inclination, fraction),
			0.0, OrbitSimulation.MAX_INCLINATION_DEG)


func _finish(quality: BurnQuality, ratio: float) -> void:
	last_burn = {"quality": quality, "ratio": ratio, "ticks_ms": Time.get_ticks_msec()}
	burn_finished.emit(quality, ratio)

#endregion
