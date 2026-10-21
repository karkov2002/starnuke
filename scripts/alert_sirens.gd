class_name AlertSirens
extends Node
## Sirènes d'alerte de la station (nœud AlertSirens de scenes/orbit_view.tscn), règle de jeu : tant que la station
## est en alerte jaune, orange ou rouge (Station.set_alert : tablette, panneau de debug, sas), le son de ce niveau
## passe en boucle par l'interphone, audible partout dans la station (bus SFX, sans position) : jaune, carillon doux
## toutes les 4 s ; orange, trois bips secs ; rouge, sirène montante continue (assets/audio/alarms, générés par
## tools/build_alarm_sounds.ps1 ; remplaçables par des sons faits à la main, même nom, Ogg Vorbis : le fichier entier
## est joué en boucle). Normal et « plus de lumière » (courant coupé) : silence. Un appel prioritaire (PriorityCall)
## met la station en alerte jaune : c'est la sirène jaune qui l'annonce.

const SOUNDS := {
	Station.Alert.YELLOW: preload("res://assets/audio/alarms/alert_yellow.ogg"),
	Station.Alert.ORANGE: preload("res://assets/audio/alarms/alert_orange.ogg"),
	Station.Alert.RED: preload("res://assets/audio/alarms/alert_red.ogg"),
}
## Volume par niveau (dB) : l'urgence monte avec l'alerte.
const VOLUMES_DB := {Station.Alert.YELLOW: -12.0, Station.Alert.ORANGE: -9.0, Station.Alert.RED: -8.0}

var _player: AudioStreamPlayer
## Niveau dont le son joue (−1 : aucun).
var _playing := -1


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"SFX"
	add_child(_player)
	for level: int in SOUNDS:
		var sound: AudioStreamOggVorbis = SOUNDS[level]
		sound.loop = true


func _process(_delta: float) -> void:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	var level := station.get_alert() if station else Station.Alert.NONE
	var wanted: int = level if SOUNDS.has(level) else -1
	if wanted == _playing:
		return
	_playing = wanted
	_player.stop()
	if wanted >= 0:
		_player.stream = SOUNDS[wanted]
		_player.volume_db = VOLUMES_DB[wanted]
		_player.play()
