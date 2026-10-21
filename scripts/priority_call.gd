class_name PriorityCall
extends Node
## Appel prioritaire (règle de jeu) : à l'arrivée d'un briefing de campagne (CampaignDirector) :
## - **alerte jaune simple** jusqu'à la lecture du briefing (Station.set_alert : luminaires jaunes et sirène jaune,
##   AlertSirens ; pas de sonnerie propre), si la station était au niveau normal ; à la lecture, retour au normal,
##   sauf si le niveau a changé entre-temps. Une alerte déjà en cours (jaune, orange, rouge, plus de lumière) est
##   gardée ;
## - la tablette est le récepteur de l'appel, comme un téléphone : son onglet Alertes (scripts/ui/tablet_display.gd)
##   l'affiche (expéditeur, objet, heure de réception, bandeau clignotant PRIORITY_CALL_BANNER) jusqu'à la lecture ;
##   elle s'ouvre sur cet onglet (call_started, call_stopped ; info : from, subject, received_unix).
## stop() à la lecture du briefing.

signal call_started(info: Dictionary)
signal call_stopped

const GROUP := &"priority_call"

## Appel en cours (vide : aucun) : from et subject (textes déjà traduits), received_unix (heure du jeu).
var info := {}

var _station: Station
var _active := false
var _alert_set := false


func _ready() -> void:
	add_to_group(GROUP)
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station


## Début de l'appel (briefing arrivé) ; call_info : from, subject, received_unix (voir info).
func ring(call_info := {}) -> void:
	_active = true
	info = call_info
	if _station and _station.get_alert() == Station.Alert.NONE:
		_station.set_alert(Station.Alert.YELLOW)
		_alert_set = true
	call_started.emit(info)


## Fin de l'appel (briefing lu) : retour au niveau normal si l'alerte jaune de l'appel est toujours là.
func stop() -> void:
	if not _active:
		return
	_active = false
	info = {}
	if _alert_set and _station and _station.get_alert() == Station.Alert.YELLOW:
		_station.set_alert(Station.Alert.NONE)
	_alert_set = false
	call_stopped.emit()


func is_ringing() -> bool:
	return _active
