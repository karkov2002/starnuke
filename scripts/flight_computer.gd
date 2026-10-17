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

signal plan_changed

const GROUP := &"flight_computer"
const MIN_TARGET_ALTITUDE_KM := 400.0
const MAX_TARGET_ALTITUDE_KM := 800.0
## Écarts en deçà desquels la cible est considérée comme atteinte (pas de manœuvre prévue).
const INCLINATION_TOLERANCE_DEG := 0.05
const ALTITUDE_TOLERANCE_KM := 0.5

@export var orbit_path: NodePath = ^"../Orbit"

var target_inclination_deg := 0.0
var target_altitude_km := 400.0

var _orbit: OrbitSimulation


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node(orbit_path) as OrbitSimulation
	reset_target()


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


#region Nœud de la manœuvre

## Temps simulé (s) du prochain nœud (passage à l'équateur).
func get_node_time_s() -> float:
	return _orbit.get_next_node_time_s()


## Temps de jeu (s) restant avant le prochain nœud.
func get_countdown_s() -> float:
	return get_node_time_s() - _orbit.sim_time_s


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
