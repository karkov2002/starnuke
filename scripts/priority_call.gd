class_name PriorityCall
extends Node
## Appel prioritaire (règle de jeu) : à l'arrivée d'un briefing de campagne (CampaignDirector), la station sonne
## par l'interphone (audible partout, même en combinaison ; bus SFX), d'une sonnerie distincte des sirènes d'alerte
## (AlertSirens) :
## - sonnerie : assets/audio/alarms/briefing_call.ogg (deux tons alternés en salves, tools/build_alarm_sounds.ps1) en
##   boucle jusqu'à la lecture du briefing, au plus RING_S ; ensuite un cycle de rappel toutes les REMINDER_S
##   secondes tant qu'il n'est pas lu ;
## - **alerte jaune** jusqu'à la lecture (Station.set_alert : luminaires jaunes ; pendant l'appel, la sirène jaune se
##   tait au profit de la sonnerie), si la station était au niveau normal ; à la lecture, retour au normal, sauf si
##   le niveau a changé entre-temps. Une alerte déjà en cours (jaune, orange, rouge, plus de lumière) est gardée ;
## - la tablette est le récepteur de l'appel, comme un téléphone : son onglet Alertes (scripts/ui/tablet_display.gd)
##   l'affiche (expéditeur, objet, heure de réception, bandeau clignotant PRIORITY_CALL_BANNER) jusqu'à la lecture ;
##   elle s'ouvre sur cet onglet (call_started, call_stopped ; info : from, subject, received_unix).
## stop() à la lecture du briefing.

signal call_started(info: Dictionary)
signal call_stopped

const GROUP := &"priority_call"
const SOUND := preload("res://assets/audio/alarms/briefing_call.ogg")
const RING_S := 20.0
const REMINDER_S := 60.0
## Durée d'un cycle de la sonnerie (s) : un cycle par rappel.
const CYCLE_S := 1.5
const VOLUME_DB := -8.0

## Appel en cours (vide : aucun) : from et subject (textes déjà traduits), received_unix (heure du jeu).
var info := {}

var _player: AudioStreamPlayer
var _station: Station
## Appel en cours, temps écoulé depuis son début (s, temps réel).
var _active := false
var _elapsed := 0.0
var _alert_set := false


func _ready() -> void:
	add_to_group(GROUP)
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	var sound: AudioStreamOggVorbis = SOUND
	sound.loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = sound
	_player.bus = &"SFX"
	_player.volume_db = VOLUME_DB
	add_child(_player)
	set_process(false)


## Début de l'appel (briefing arrivé) ; call_info : from, subject, received_unix (voir info).
func ring(call_info := {}) -> void:
	_active = true
	_elapsed = 0.0
	info = call_info
	_player.play()
	if _station and _station.get_alert() == Station.Alert.NONE:
		_station.set_alert(Station.Alert.YELLOW)
		_alert_set = true
	set_process(true)
	call_started.emit(info)


## Fin de l'appel (briefing lu) : silence, retour au niveau normal si l'alerte jaune de l'appel est toujours là.
func stop() -> void:
	if not _active:
		return
	_active = false
	info = {}
	_player.stop()
	if _alert_set and _station and _station.get_alert() == Station.Alert.YELLOW:
		_station.set_alert(Station.Alert.NONE)
	_alert_set = false
	set_process(false)
	call_stopped.emit()


func is_ringing() -> bool:
	return _active


## Sonnerie continue pendant RING_S, puis un cycle toutes les REMINDER_S.
func _process(delta: float) -> void:
	_elapsed += delta
	var since := _elapsed - RING_S
	var wanted := since < 0.0 or fmod(since, REMINDER_S) < CYCLE_S
	if wanted and not _player.playing:
		_player.play()
	elif not wanted and _player.playing:
		_player.stop()
