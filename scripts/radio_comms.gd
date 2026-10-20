class_name RadioComms
extends Node
## Radio de la station (nœud Radio de scenes/orbit_view.tscn) : canaux, liaison avec le sol, messages reçus et
## réponses. Affichée et pilotée par l'écran de communication du module Commande (CommConsole, CommDisplay) ; la
## campagne y postera ses messages (post).
## Règles de jeu :
## - **Liaison** : la station ne communique qu'avec une station au sol en vue (GROUND_STATIONS, réseau de suivi :
##   élévation de la station au-dessus de l'horizon d'au moins MIN_ELEVATION_DEG). Qualité de 0,15 (au ras de
##   l'horizon) à 1 (FULL_ELEVATION_DEG et plus) selon la meilleure élévation ; nulle hors de vue de toutes : coupures
##   sur les océans.
## - **Canal** : un message posté sur un canal (indice de CHANNELS) n'arrive que si la radio est réglée sur ce canal ;
##   canal −1 : sur tous. Un message posté attend (au sol) que la liaison existe et que le bon canal soit choisi.
## - **Réponses** : un message peut proposer des réponses ; en envoyer une demande la liaison (sinon, échec) et le
##   message est alors répondu (une seule réponse).
## Textes des messages (from, subject, body, réponses) : clé des fichiers de langue, texte, ou dictionnaire par langue
## (comme campaign.json, Campaigns.text_of).

signal message_received(message: Dictionary)
## Message lu (affiché à l'écran de communication devant le joueur) : départ du chrono d'une mission de campagne.
signal message_read(message_id: String)
signal replied(message_id: String, choice: int)
signal changed

## Canaux : fréquence (MHz) et bande. Inspirés des liaisons réelles des stations en orbite (VHF phonie, UHF, bande S
## données et vidéo, bande X).
const CHANNELS: Array[Dictionary] = [
	{"mhz": 143.625, "band": "VHF"},
	{"mhz": 145.800, "band": "VHF"},
	{"mhz": 437.800, "band": "UHF"},
	{"mhz": 2265.000, "band": "S"},
	{"mhz": 2287.500, "band": "S"},
	{"mhz": 8400.000, "band": "X"},
]
## Stations au sol (noms propres, non traduits) : latitude, longitude (degrés).
const GROUND_STATIONS: Array[Dictionary] = [
	{"name": "HOUSTON", "lat": 29.56, "lon": -95.09},
	{"name": "WHITE SANDS", "lat": 32.50, "lon": -106.61},
	{"name": "WALLOPS", "lat": 37.94, "lon": -75.46},
	{"name": "HAWAII", "lat": 22.13, "lon": -159.67},
	{"name": "KOUROU", "lat": 5.25, "lon": -52.80},
	{"name": "SANTIAGO", "lat": -33.15, "lon": -70.67},
	{"name": "TOULOUSE", "lat": 43.56, "lon": 1.48},
	{"name": "KIRUNA", "lat": 67.86, "lon": 20.96},
	{"name": "SVALBARD", "lat": 78.23, "lon": 15.40},
	{"name": "KOROLYOV", "lat": 55.91, "lon": 37.81},
	{"name": "MALINDI", "lat": -2.99, "lon": 40.19},
	{"name": "HARTEBEESTHOEK", "lat": -25.89, "lon": 27.69},
	{"name": "BANGALORE", "lat": 13.03, "lon": 77.51},
	{"name": "TANEGASHIMA", "lat": 30.40, "lon": 130.97},
	{"name": "GUAM", "lat": 13.59, "lon": 144.84},
	{"name": "CANBERRA", "lat": -35.40, "lon": 148.98},
]
const GROUP := &"radio"
const MIN_ELEVATION_DEG := 5.0
const FULL_ELEVATION_DEG := 25.0

@export var orbit_path: NodePath = ^"../Orbit"
## Canal réglé au démarrage.
@export var default_channel := 0
## Liaison recalculée toutes les update_s secondes (le point survolé avance de ~2 km/s).
@export var update_s := 0.5

var channel := 0
## Qualité de la liaison (0 à 1) et station au sol qui la porte ("" sans liaison).
var link := 0.0
var link_station := ""
## Messages reçus (les plus récents en dernier) : {id, from, subject, body, channel, replies, received_unix,
## received_channel, read, answer} ; messages postés pas encore reçus.
var inbox: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _orbit: OrbitSimulation
var _since := INF
var _next_id := 1


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	channel = clampi(default_channel, 0, CHANNELS.size() - 1)


func _process(delta: float) -> void:
	_since += delta
	if _since < update_s:
		return
	_since = 0.0
	var before := [link, link_station]
	_update_link()
	_deliver()
	if before != [link, link_station]:
		changed.emit()


## Poste un message (campagne, debug) : clés from, subject, body, channel (−1 : tous), replies (liste). Il arrive dès
## que la liaison et le canal le permettent. Rend son identifiant.
func post(message: Dictionary) -> String:
	var copy := message.duplicate(true)
	if not copy.has("id"):
		copy.id = "msg_%d" % _next_id
		_next_id += 1
	copy.merge({"channel": -1, "replies": [], "read": false, "answer": -1, "received_unix": -1.0})
	_pending.append(copy)
	_deliver()
	return copy.id


func set_channel(index: int) -> void:
	index = wrapi(index, 0, CHANNELS.size())
	if index == channel:
		return
	channel = index
	_deliver()
	changed.emit()


func mark_read(message_id: String) -> void:
	var message := find(message_id)
	if not message.is_empty() and not message.read:
		message.read = true
		message_read.emit(message_id)
		changed.emit()


func unread_count() -> int:
	return inbox.filter(func(m: Dictionary) -> bool: return not m.read).size()


func find(message_id: String) -> Dictionary:
	for message in inbox:
		if message.id == message_id:
			return message
	return {}


## Envoie la réponse choice au message : faux sans liaison, déjà répondu ou réponse inconnue.
func reply(message_id: String, choice: int) -> bool:
	var message := find(message_id)
	if message.is_empty() or message.answer >= 0 or choice < 0 or choice >= (message.replies as Array).size() \
			or link <= 0.0:
		return false
	message.answer = choice
	replied.emit(message_id, choice)
	changed.emit()
	return true


## Heure de jeu (UTC, s).
func now_unix() -> float:
	return _orbit.get_utc_unix_s() if _orbit else 0.0


func _deliver() -> void:
	if link <= 0.0:
		return
	var waiting: Array[Dictionary] = []
	for message in _pending:
		if int(message.channel) < 0 or int(message.channel) == channel:
			message.received_unix = now_unix()
			message.received_channel = channel
			inbox.append(message)
			message_received.emit(message)
		else:
			waiting.append(message)
	if waiting.size() != _pending.size():
		_pending = waiting
		changed.emit()


## Meilleure élévation de la station vue des stations au sol (horizon local), en degrés.
func _update_link() -> void:
	if _orbit == null:
		link = 1.0
		link_station = ""
		return
	var point := _orbit.get_subsatellite_point()
	var ratio := OrbitSimulation.EARTH_RADIUS_KM / (OrbitSimulation.EARTH_RADIUS_KM + _orbit.altitude_km)
	var best := -90.0
	var best_name := ""
	for ground in GROUND_STATIONS:
		var angle := _central_angle(point.x, point.y, ground.lat, ground.lon)
		# Élévation vue du sol : tan ε = (cos γ − R/(R+h)) / sin γ.
		var elevation := rad_to_deg(atan2(cos(angle) - ratio, sin(angle)))
		if elevation > best:
			best = elevation
			best_name = ground.name
	link = lerpf(0.15, 1.0, smoothstep(MIN_ELEVATION_DEG, FULL_ELEVATION_DEG, best)) \
			if best >= MIN_ELEVATION_DEG else 0.0
	link_station = best_name if link > 0.0 else ""


static func _central_angle(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var a := deg_to_rad(lat1)
	var b := deg_to_rad(lat2)
	var d := sin((b - a) * 0.5) ** 2 + cos(a) * cos(b) * sin(deg_to_rad(lon2 - lon1) * 0.5) ** 2
	return 2.0 * asin(sqrt(minf(d, 1.0)))
