class_name AirlockHazard
extends Node
## Conséquences de l'air de la station pour l'observateur (nœud AirlockHazard de scenes/orbit_view.tscn). Aucun
## verrouillage : la sécurité est l'affaire du joueur. Pressions et courant d'air : StationAtmosphere. Règles de jeu :
## - **expulsion** : porte extérieure du sas ouverte, l'observateur qui se trouve dans un volume qui communique avec
##   l'espace (n'importe quel module, par les écoutilles ouvertes) est porté par le courant d'air à travers la station
##   jusqu'à la sortie, d'autant plus vite que la pression et le nombre de modules reliés sont grands. Il garde ses
##   commandes et peut fermer une écoutille au clic : du bon côté (l'amont), le courant s'arrête ;
## - **mort** : seulement sans combinaison, dans le vide ou presque (pression du volume sous death_pressure, ou dehors).
##   Avec la combinaison, on ne meurt jamais : dehors, son propulseur dorsal amortit l'élan (safer_s) et le joueur peut
##   revenir par la porte extérieure.
## Dehors : sorti du sas par la porte extérieure (hors de tous les volumes, dernier volume : le sas), et dehors
## jusqu'à ce qu'on rentre par le sas (les boîtes des volumes dépassent un peu de la coque) ; Station
## .observer_outside (flashs et exposition). Mort : scripts/death_sequence.gd.

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var atmosphere_path: NodePath = ^"../StationAir"
@export var observer_path: NodePath = ^"../Observer"
## Nœuds coupés pendant la séquence de mort (interactions, poste de pilotage).
@export var disabled_paths: Array[NodePath] = [^"../HatchInteraction"]
## Pression (relative, 0–1) sous laquelle on perd connaissance sans combinaison (~0,3 bar).
@export var death_pressure := 0.3
## Temps de réponse de la poussée (s) : dans le courant d'air, et dans l'air calme (on se rattrape aux mains courantes).
@export var flow_response_s := 0.3
@export var still_air_response_s := 0.8
## Dehors avec la combinaison : amortissement de l'élan par le propulseur dorsal (s).
@export var safer_s := 3.0

var _station: Station
var _atmosphere: StationAtmosphere
var _observer: Observer
## Dernier volume où était l'observateur (les interstices entre volumes ne comptent pas).
var _zone := ""
## Dehors (sorti par la porte extérieure du sas) à l'image précédente.
var _outside := false
var _dead := false


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	_atmosphere = get_node_or_null(atmosphere_path) as StationAtmosphere
	_observer = get_node_or_null(observer_path) as Observer
	if _station == null or _atmosphere == null or _observer == null:
		set_process(false)


func _process(_delta: float) -> void:
	var eye := _eye()
	var zone := _atmosphere.zone_at(eye)
	# Dehors, on ne rentre que par le sas : les coins des boîtes des volumes (StationLayout.ZONES) qui dépassent de la
	# coque (cupola, jonctions) ne comptent pas. Sans cela, frôler la coque faisait « rentrer » l'observateur dans un
	# module : il n'était plus jamais dehors (panneaux de maintenance inutilisables, flashs, exposition).
	if _outside and zone != StationAtmosphere.SAS:
		zone = ""
	var outside := zone == "" and _zone == StationAtmosphere.SAS
	_outside = outside
	if zone != "":
		_zone = zone
	elif _zone == "":
		return
	_station.observer_outside = outside
	var suit := _station.is_suit_worn()
	# Le corps reste porté par le courant après la mort.
	if outside:
		_observer.set_air_flow(Vector3.ZERO, safer_s if suit and not _dead else INF)
	else:
		var flow := _atmosphere.flow_at(eye, _zone)
		_observer.set_air_flow(flow, flow_response_s if flow != Vector3.ZERO else still_air_response_s)
	if not _dead and not suit and (outside or _atmosphere.pressure_of(_zone) < death_pressure):
		_die()


func _die() -> void:
	_dead = true
	var disabled: Array[Node] = []
	for path in disabled_paths:
		var node := get_node_or_null(path)
		if node:
			disabled.append(node)
	var sequence := DeathSequence.new()
	get_tree().current_scene.add_child(sequence)
	sequence.start(_observer, disabled, _station, _atmosphere.zone_center(StationAtmosphere.SAS),
			_station.global_basis.x)


func _eye() -> Vector3:
	var camera := _observer.get_node_or_null("Camera") as Node3D
	return camera.global_position if camera else _observer.global_position
