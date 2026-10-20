class_name CampaignDirector
extends Node
## Déroulement d'une campagne (nœud CampaignDirector de scenes/orbit_view.tscn), actif seulement en mode campagne
## (Campaigns.mode, choisi à l'écran de démarrage) ; en mode libre, il ne fait rien.
## Pour l'instant (étape 3 du plan des campagnes) : au lancement, applique le départ de la journée en cours
## (CampaignData.start_of_day : heure UTC, altitude, inclinaison, point survolé et sens de passage de la station,
## Orbit.place ; la manœuvre en préparation est annulée). Briefings, missions et notes : étape 4.

signal day_started(day_index: int)

@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"

var _orbit: OrbitSimulation
var _flight_computer: FlightComputer


func _ready() -> void:
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_flight_computer = get_node_or_null(flight_computer_path) as FlightComputer
	if is_active():
		# Après la mise en place de l'orbite (son _ready).
		start_day.call_deferred(Campaigns.day_index)


func is_active() -> bool:
	return Campaigns.mode == Campaigns.Mode.CAMPAIGN and Campaigns.current != null


## Commence la journée day_index : départ appliqué s'il est défini (sinon, la station reste où elle est).
func start_day(day_index: int) -> void:
	if not is_active() or day_index < 0 or day_index >= Campaigns.current.days().size():
		return
	Campaigns.day_index = day_index
	apply_start(Campaigns.current.start_of_day(day_index))
	day_started.emit(day_index)


## Place la station selon un départ (format de CampaignData) ; rien si start est vide.
func apply_start(start: Dictionary) -> void:
	if start.is_empty() or _orbit == null:
		return
	var orbit: Dictionary = start.orbit
	var over: Dictionary = orbit.over
	_orbit.place(CampaignData.parse_utc(str(start.utc)), float(orbit.altitude_km), float(orbit.inclination_deg),
			float(over.lat), float(over.lon), bool(orbit.get("ascending", true)))
	if _flight_computer:
		_flight_computer.reset_target()
