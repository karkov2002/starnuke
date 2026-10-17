class_name FlightComputer
extends Node
## Ordinateur de vol (nœud FlightComputer de scenes/orbit_view.tscn) : planifie les manœuvres orbitales du poste de
## pilotage (scripts/pilot_console.gd). L'orbite elle-même reste dans Orbit (scripts/orbit.gd) ; l'écran ne fait
## qu'afficher et transmettre les commandes.
## - Cible : inclinaison (0–80°) et altitude (400–800 km) visées, et décalage du nœud (rotation de la ligne des nœuds,
##   ΔΩ de ±MAX_NODE_SHIFT_DEG, positif vers l'est, relatif à l'orbite actuelle). Tant que la cible diffère de l'orbite
##   réelle, une manœuvre est prévue (has_plan) et son orbite, la « trace fantôme » (ghost track), est dessinée en
##   pointillés : anneau 3D autour de la Terre (GhostTrack) et trace au sol sur la carte.
## - Point de manœuvre : un changement de plan se fait là où l'orbite actuelle coupe le plan visé (droite
##   d'intersection des deux plans, deux points opposés par orbite) : au nœud (passage à l'équateur) pour un simple
##   changement d'inclinaison (la ligne des nœuds reste en place), près du sommet de l'orbite (latitude maximale)
##   pour un simple décalage du nœud, entre les deux pour une manœuvre combinée. Sans changement de plan (altitude
##   seule), au prochain nœud. L'orbite fantôme passe par ce point ; c'est une orbite fixe dans le repère inertiel
##   (hors précession J2) : la Terre tourne dessous.
## - Poussée, seulement dans la fenêtre du point de manœuvre (WINDOW_S secondes réelles de part et d'autre, soit
##   WINDOW_S × la vitesse du temps en temps de jeu, au plus MAX_WINDOW_GAME_S) :
##   - mode Auto : au passage du point, l'orbite prend exactement la cible ;
##   - mode Manuel : le joueur maintient BURN (temps ramené à ×1). La durée requise croît avec le Δv
##     (required_hold_s). La poussée s'applique progressivement pendant l'appui (fraction = durée tenue / durée
##     requise ; au-delà de 100 %, elle dépasse la cible, jusqu'à MAX_BURN_RATIO où elle s'arrête d'elle-même). Relâché
##     à ±PERFECT_TOLERANCE de la durée requise : poussée parfaite, l'orbite prend exactement la cible. Sinon
##     (sous-poussée ou sur-poussée), la fraction appliquée reste, et l'écart de dosage ajoute des erreurs
##     aléatoires sur l'inclinaison et l'altitude (proportionnelles à l'écart). L'inclinaison et l'altitude visées ne
##     changent pas, le décalage du nœud restant est mis à jour : la manœuvre reste prévue et se corrige au point
##     suivant. L'orbite reste toujours circulaire.

signal plan_changed
## Fin d'une poussée : qualité (BurnQuality) et rapport durée tenue / durée requise (1 en mode Auto).
signal burn_finished(quality: int, ratio: float)

enum Mode { AUTO, MANUAL }
enum BurnQuality { PERFECT, UNDER, OVER }

const GROUP := &"flight_computer"
const MIN_TARGET_ALTITUDE_KM := 400.0
const MAX_TARGET_ALTITUDE_KM := 800.0
const MAX_NODE_SHIFT_DEG := 20.0
## Écarts en deçà desquels la cible est considérée comme atteinte (pas de manœuvre prévue).
const INCLINATION_TOLERANCE_DEG := 0.05
const ALTITUDE_TOLERANCE_KM := 0.5
const NODE_SHIFT_TOLERANCE_DEG := 0.05
## Demi-largeur de la fenêtre du point de manœuvre, en secondes réelles (temps de jeu = × vitesse du temps).
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
## Décalage du nœud visé (degrés, positif vers l'est), relatif à l'orbite actuelle.
var target_node_shift_deg := 0.0
var mode := Mode.MANUAL
## Poussée manuelle en cours, durée tenue et durée requise (s réelles).
var burning := false
var burn_hold_s := 0.0
var burn_required_s := 0.0
## Dernière poussée : {quality, ratio, ticks_ms} (vide avant la première).
var last_burn := {}

var _orbit: OrbitSimulation
## Orbite et cible au début de la poussée en cours (inclinaison, altitude, Ω), et temps du point de manœuvre.
var _burn_start := {}


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
	# Mode Auto : le point de manœuvre vient d'être passé (sa fenêtre est encore ouverte) : orbite visée, la station
	# gardant sa position au point de manœuvre.
	elif mode == Mode.AUTO and has_plan():
		var countdown := get_countdown_s()
		if countdown <= 0.0 and countdown >= -get_window_game_s():
			var burn_time := get_node_time_s()
			_orbit.set_orbit_plane(target_inclination_deg, _target_raan(burn_time), target_altitude_km, burn_time)
			target_node_shift_deg = 0.0
			_finish(BurnQuality.PERFECT, 1.0)


func get_orbit() -> OrbitSimulation:
	return _orbit


## Cible ramenée sur l'orbite réelle (plus de manœuvre prévue).
func reset_target() -> void:
	target_inclination_deg = _orbit.inclination_deg
	target_altitude_km = clampf(_orbit.altitude_km, MIN_TARGET_ALTITUDE_KM, MAX_TARGET_ALTITUDE_KM)
	target_node_shift_deg = 0.0
	plan_changed.emit()


func set_target(inclination_deg: float, altitude_km: float, node_shift_deg := target_node_shift_deg) -> void:
	target_inclination_deg = clampf(inclination_deg, 0.0, OrbitSimulation.MAX_INCLINATION_DEG)
	target_altitude_km = clampf(altitude_km, MIN_TARGET_ALTITUDE_KM, MAX_TARGET_ALTITUDE_KM)
	target_node_shift_deg = clampf(node_shift_deg, -MAX_NODE_SHIFT_DEG, MAX_NODE_SHIFT_DEG)
	plan_changed.emit()


## Une manœuvre est-elle prévue (cible différente de l'orbite réelle) ?
func has_plan() -> bool:
	return absf(target_inclination_deg - _orbit.inclination_deg) > INCLINATION_TOLERANCE_DEG \
			or absf(target_altitude_km - _orbit.altitude_km) > ALTITUDE_TOLERANCE_KM \
			or absf(target_node_shift_deg) > NODE_SHIFT_TOLERANCE_DEG


func set_mode(value: Mode) -> void:
	if burning:
		end_burn()
	mode = value


#region Point de manœuvre

## Temps simulé (s) du point de manœuvre : celui de la poussée en cours, le point tout juste passé tant que sa
## fenêtre est ouverte, sinon le prochain.
func get_node_time_s() -> float:
	if burning:
		return _burn_start.node_time
	var now := _orbit.sim_time_s
	var next_point := _next_burn_time_s(now)
	var previous_point := next_point - PI / _orbit.get_mean_motion()
	if now - previous_point <= get_window_game_s():
		return previous_point
	return next_point


## Temps de jeu (s) restant avant le point de manœuvre (négatif juste après son passage).
func get_countdown_s() -> float:
	return get_node_time_s() - _orbit.sim_time_s


## Demi-largeur de la fenêtre du point de manœuvre en temps de jeu.
func get_window_game_s() -> float:
	return minf(WINDOW_S * maxf(_orbit.time_scale, 1.0), MAX_WINDOW_GAME_S)


## La station est-elle dans la fenêtre du point de manœuvre ?
func is_in_window() -> bool:
	return absf(get_countdown_s()) <= get_window_game_s()


## Le point de manœuvre est-il sur la moitié montante de l'orbite (vers le nord) ?
func is_node_ascending() -> bool:
	return cos(_orbit.get_argument_of_latitude(get_node_time_s())) >= 0.0


## Le point de manœuvre est-il un nœud (passage à l'équateur, à moins de 1° de latitude) ?
func is_burn_at_node() -> bool:
	return absf(_orbit.get_subsatellite_point(get_node_time_s()).x) < 1.0


# Prochain passage (strictement après time_s) sur la droite d'intersection du plan actuel et du plan visé ; sans
# changement de plan, prochain nœud. Les deux points d'intersection sont à π d'argument de latitude l'un de l'autre.
func _next_burn_time_s(time_s: float) -> float:
	var raan := _orbit.get_raan(time_s)
	var inclination := deg_to_rad(_orbit.inclination_deg)
	var old_normal := OrbitSimulation.plane_normal(inclination, raan)
	var new_normal := OrbitSimulation.plane_normal(deg_to_rad(target_inclination_deg), _target_raan(time_s))
	var line := old_normal.cross(new_normal)
	var line_arg_lat := 0.0
	if line.length() > 1e-6:
		var node := Vector3(cos(raan), sin(raan), 0.0)
		var quarter := Vector3(-sin(raan) * cos(inclination), cos(raan) * cos(inclination), sin(inclination))
		line_arg_lat = atan2(line.dot(quarter), line.dot(node))
	var u := _orbit.get_argument_of_latitude(time_s)
	var next := line_arg_lat + (floorf((u - line_arg_lat) / PI) + 1.0) * PI
	return time_s + (next - u) / _orbit.get_mean_motion()


# Ω visé (rad) au temps time_s : celui de l'orbite actuelle plus le décalage du nœud (figé pendant une poussée).
func _target_raan(time_s: float) -> float:
	if burning:
		return _burn_start.target_raan
	return _orbit.get_raan(time_s) + deg_to_rad(target_node_shift_deg)

#endregion

#region Orbite fantôme

## Éléments de l'orbite fantôme (orbite visée, partant du point de manœuvre) : radius_km, inclination (rad),
## raan (rad, au point de manœuvre), raan_rate (précession, rad/s), node_arg_lat (argument de latitude au point de
## manœuvre), node_time_s, mean_motion (rad/s).
func get_ghost() -> Dictionary:
	var node_time := get_node_time_s()
	var inclination := deg_to_rad(target_inclination_deg)
	var raan := _target_raan(node_time)
	var at_point := _orbit.get_position_eci(node_time)
	var node := Vector3(cos(raan), sin(raan), 0.0)
	var quarter := Vector3(-sin(raan) * cos(inclination), cos(raan) * cos(inclination), sin(inclination))
	return {
		"radius_km": OrbitSimulation.EARTH_RADIUS_KM + target_altitude_km,
		"inclination": inclination,
		"raan": raan,
		"raan_rate": OrbitSimulation.raan_rate_at(target_altitude_km, target_inclination_deg) if _orbit.raan_precession else 0.0,
		"node_arg_lat": atan2(at_point.dot(quarter), at_point.dot(node)),
		"node_time_s": node_time,
		"mean_motion": OrbitSimulation.mean_motion_at(target_altitude_km),
	}


## Ω (rad) de l'orbite fantôme ghost au temps time_s (précession comprise).
static func ghost_raan(ghost: Dictionary, time_s: float) -> float:
	return ghost.raan + ghost.raan_rate * (time_s - ghost.node_time_s)


## Point survolé (latitude, longitude en degrés) au temps time_s sur l'orbite fantôme ghost (voir get_ghost).
func ghost_ground_point(ghost: Dictionary, time_s: float) -> Vector2:
	var arg_lat: float = ghost.node_arg_lat + ghost.mean_motion * (time_s - ghost.node_time_s)
	var eci := OrbitSimulation.circular_position_eci(ghost.radius_km, ghost.inclination, ghost_raan(ghost, time_s), arg_lat)
	return OrbitSimulation.ecef_to_lat_lon(_orbit.eci_to_ecef(eci, time_s))


## Δv (km/s) de la manœuvre prévue : changement de plan 2·v·sin(θ/2) (θ : angle entre le plan actuel et le plan
## visé, inclinaison et décalage du nœud compris) plus transfert de Hohmann entre les deux altitudes (somme des deux
## impulsions).
func get_delta_v_km_s() -> float:
	var now := _orbit.sim_time_s
	var old_normal := OrbitSimulation.plane_normal(deg_to_rad(_orbit.inclination_deg), _orbit.get_raan(now))
	var new_normal := OrbitSimulation.plane_normal(deg_to_rad(target_inclination_deg), _target_raan(now))
	var angle := acos(clampf(old_normal.dot(new_normal), -1.0, 1.0))
	var r1 := _orbit.get_semi_major_axis_km()
	var r2 := OrbitSimulation.EARTH_RADIUS_KM + target_altitude_km
	var v1 := sqrt(OrbitSimulation.MU_KM3_S2 / r1)
	var v2 := sqrt(OrbitSimulation.MU_KM3_S2 / r2)
	var transfer := absf(v1 * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)) + absf(v2 * (1.0 - sqrt(2.0 * r1 / (r1 + r2))))
	return 2.0 * v1 * sin(angle * 0.5) + transfer

#endregion

#region Poussée

## Durée (s réelles) d'appui sur BURN requise pour un Δv donné : 1,5 s + 2,5 s × √(Δv en km/s), au plus 8 s
## (~2,3 s pour 100 m/s, ~6,6 s pour 4,2 km/s).
static func required_hold_s(delta_v_km_s: float) -> float:
	return clampf(1.5 + 2.5 * sqrt(delta_v_km_s), 1.5, 8.0)


## BURN utilisable : mode Manuel, manœuvre prévue, fenêtre du point de manœuvre ouverte, pas de poussée en cours.
func can_burn() -> bool:
	return mode == Mode.MANUAL and not burning and has_plan() and is_in_window()


## Début de l'appui sur BURN (temps ramené à ×1). Renvoie false si BURN n'est pas utilisable.
func start_burn() -> bool:
	if not can_burn():
		return false
	_orbit.time_scale = 1.0
	var now := _orbit.sim_time_s
	_burn_start = {"inclination": _orbit.inclination_deg, "altitude": _orbit.altitude_km, "raan": _orbit.get_raan(now),
			"target_inclination": target_inclination_deg, "target_altitude": target_altitude_km,
			"target_raan": _target_raan(now), "node_shift": target_node_shift_deg, "node_time": get_node_time_s()}
	burn_required_s = required_hold_s(get_delta_v_km_s())
	burn_hold_s = 0.0
	burning = true
	return true


## Relâchement de BURN (ou arrêt automatique à MAX_BURN_RATIO) : poussée parfaite ou erreurs de dosage.
func end_burn() -> void:
	if not burning:
		return
	var ratio := burn_hold_s / burn_required_s
	var perfect := absf(ratio - 1.0) <= PERFECT_TOLERANCE
	_apply_fraction(1.0 if perfect else ratio)
	burning = false
	# Décalage du nœud restant (dépassé si négatif par rapport au signe de départ).
	target_node_shift_deg = 0.0 if perfect else _burn_start.node_shift * (1.0 - ratio)
	if perfect:
		_finish(BurnQuality.PERFECT, ratio)
		return
	# Erreurs de dosage appliquées au point courant (la station ne saute pas) : l'erreur d'inclinaison est une erreur
	# de cap de la poussée (Orbit la borne à la latitude courante et recale Ω).
	var error := absf(ratio - 1.0)
	_orbit.altitude_km += randf_range(-1.0, 1.0) * ALTITUDE_ERROR_KM * error
	_orbit.inclination_deg += randf_range(-1.0, 1.0) * INCLINATION_ERROR_DEG * error
	_finish(BurnQuality.UNDER if ratio < 1.0 else BurnQuality.OVER, ratio)


## Part fraction (0 à MAX_BURN_RATIO) de la manœuvre appliquée à l'orbite du début de la poussée (inclinaison,
## altitude et Ω interpolés), la station gardant sa position actuelle.
func _apply_fraction(fraction: float) -> void:
	_orbit.set_orbit_plane(lerpf(_burn_start.inclination, _burn_start.target_inclination, fraction),
			lerpf(_burn_start.raan, _burn_start.target_raan, fraction),
			lerpf(_burn_start.altitude, _burn_start.target_altitude, fraction), _orbit.sim_time_s)


func _finish(quality: BurnQuality, ratio: float) -> void:
	last_burn = {"quality": quality, "ratio": ratio, "ticks_ms": Time.get_ticks_msec()}
	burn_finished.emit(quality, ratio)

#endregion
