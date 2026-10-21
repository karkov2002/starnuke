class_name PriorityCall
extends Node
## Appel prioritaire (règle de jeu) : à l'arrivée d'un briefing de campagne (CampaignDirector), la station sonne
## comme une alarme de la station spatiale internationale, par l'interphone (audible partout, même en combinaison ;
## bus SFX) :
## - sonnerie : deux tons alternés (TONES_HZ, TONE_S chacun) en salves de BURST_S, séparées de PAUSE_S de silence,
##   jusqu'à la lecture du briefing, au plus RING_S ; ensuite un bip de rappel (une paire de tons) toutes les
##   REMINDER_S secondes tant qu'il n'est pas lu ;
## - luminaires de la station à l'orange pendant la sonnerie (Station.set_alert), puis retour au niveau d'avant, sauf
##   si une alerte plus grave était déjà en cours (rouge, plus de lumière) ou si le niveau a changé entre-temps ;
## - bandeau clignotant en haut de l'écran (PRIORITY_CALL_BANNER) jusqu'à la lecture.
## Son synthétisé (AudioStreamGenerator), sans fichier audio. stop() à la lecture du briefing.

const TONES_HZ: Array[float] = [880.0, 1175.0]
const TONE_S := 0.12
const BURST_S := 0.72
const PAUSE_S := 0.78
const RING_S := 20.0
const REMINDER_S := 60.0
const VOLUME_DB := -8.0
const MIX_RATE := 44100.0
## Montée et descente de chaque ton (s) : pas de clic.
const EDGE_S := 0.006
const BLINK_S := 0.5

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _banner: PanelContainer
var _station: Station
## Appel en cours, temps écoulé depuis son début (s, temps réel), position dans le son (échantillons).
var _active := false
var _elapsed := 0.0
var _sample := 0
var _alert_set := false
var _alert_before := Station.Alert.NONE


func _ready() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.2
	_player.stream = stream
	_player.bus = &"SFX"
	_player.volume_db = VOLUME_DB
	add_child(_player)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	# Bandeau : texte orange sur fond sombre (lisible même dans la station éclairée en orange), centré en haut.
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 80.0
	layer.add_child(row)
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.03, 0.02, 0.85)
	style.border_color = Color(1.0, 0.55, 0.12)
	style.set_border_width_all(2)
	style.set_content_margin_all(12.0)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	_banner.add_theme_stylebox_override("panel", style)
	_banner.visible = false
	row.add_child(_banner)
	var label := Label.new()
	label.text = "PRIORITY_CALL_BANNER"
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.18))
	_banner.add_child(label)
	set_process(false)


## Début de l'appel (briefing arrivé).
func ring() -> void:
	_active = true
	_elapsed = 0.0
	_sample = 0
	_banner.visible = true
	_player.play()
	_playback = _player.get_stream_playback()
	if _station and _station.get_alert() in [Station.Alert.NONE, Station.Alert.YELLOW]:
		_alert_before = _station.get_alert()
		_station.set_alert(Station.Alert.ORANGE)
		_alert_set = true
	set_process(true)


## Fin de l'appel (briefing lu).
func stop() -> void:
	if not _active:
		return
	_active = false
	_banner.visible = false
	_player.stop()
	_restore_alert()
	set_process(false)


func is_ringing() -> bool:
	return _active


func _process(delta: float) -> void:
	_elapsed += delta
	_banner.modulate.a = 1.0 if fmod(_elapsed, BLINK_S * 2.0) < BLINK_S else 0.35
	if _elapsed >= RING_S:
		_restore_alert()
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for _i in frames:
		var v := _amplitude(_sample / MIX_RATE)
		_playback.push_frame(Vector2(v, v))
		_sample += 1


## Signal à l'instant t (s depuis le début de l'appel) : salves pendant RING_S, puis une paire de tons toutes les
## REMINDER_S.
func _amplitude(t: float) -> float:
	var local: float
	var length: float
	if t < RING_S:
		local = fmod(t, BURST_S + PAUSE_S)
		length = BURST_S
	else:
		local = fmod(t - RING_S, REMINDER_S)
		length = TONE_S * 2.0
	if local >= length:
		return 0.0
	var tone := int(local / TONE_S)
	var in_tone := local - tone * TONE_S
	var edge := clampf(minf(in_tone, TONE_S - in_tone) / EDGE_S, 0.0, 1.0)
	var phase := TAU * TONES_HZ[tone % 2] * t
	# Ton d'alarme électronique : fondamentale et un peu de troisième harmonique.
	return edge * (0.8 * sin(phase) + 0.2 * sin(3.0 * phase)) * 0.6


func _restore_alert() -> void:
	if not _alert_set:
		return
	_alert_set = false
	if _station and _station.get_alert() == Station.Alert.ORANGE:
		_station.set_alert(_alert_before)
