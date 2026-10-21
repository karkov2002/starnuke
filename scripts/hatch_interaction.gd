class_name HatchInteraction
extends Node
## Écoutilles, rideaux et sas de sortie manipulables à la souris (nœud HatchInteraction de scenes/orbit_view.tscn).
## Rayon de la caméra contre les collisions (la porte d'une écoutille a son corps de collision, AnimatableBody3D, qui
## suit la charnière ; un rideau, sa zone de clic Area3D, qui suit le tissu) :
## - survol à portée (reach_m) : bulle « Ouvrir / Fermer l'écoutille », « Ouvrir / Fermer le rideau », « Enfiler /
##   Ranger la combinaison », « Vider / Remplir le sas », « Dormir » (couchette, en campagne la journée terminée :
##   CampaignDirector.sleep) ;
## - clic gauche : mouvement animé (Station.toggle_hatch, Station.toggle_curtain ; un clic pendant le mouvement
##   l'inverse), Station.set_suit_worn, Station.toggle_airlock_pressure.
## Inactif quand un écran est occupé (ScreenSeat : poste de pilotage, radio, télévision). Les clics pris avant
## (tablette, interface) ne lui parviennent pas.

const BUNK := "Interactif_Couchette"

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
## Distance maximale (m) entre l'œil et la porte.
@export var reach_m := 2.5

var _station: Station
var _observer: CollisionObject3D
var _camera: Camera3D
## Bulle de survol (HoverBubble : masquée en pause, même style que les écrans).
var _bubble: HoverBubble
var _mouse_position := Vector2.ZERO


func _ready() -> void:
	_station = get_node(station_path) as Station
	_observer = get_node(observer_path) as CollisionObject3D
	_camera = _observer.get_node("Camera") as Camera3D
	_bubble = HoverBubble.new("HATCH_OPEN")
	add_child(_bubble)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_position = (event as InputEventMouse).position


func _process(_delta: float) -> void:
	var target := _target_under(_mouse_position) if _active() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else {}
	if not target.is_empty():
		_bubble.set_hover_text(_hover_key(target))
	_bubble.set_hover(not target.is_empty(), _mouse_position)


## Clé de langue de la bulle d'un objet visé.
func _hover_key(target: Dictionary) -> String:
	match target.kind:
		"rideau":
			return "CURTAIN_OPEN" if _station.is_curtain_closing(target.id) else "CURTAIN_CLOSE"
		"combinaison":
			return "SUIT_PUT_ON"
		"porte":
			return "SUIT_STOW"
		"valve":
			return "AIRLOCK_DEPRESSURIZE" if _station.is_airlock_filling() else "AIRLOCK_REPRESSURIZE"
		"couchette":
			return "BUNK_SLEEP"
	return "HATCH_CLOSE" if _station.is_hatch_opening(target.id) else "HATCH_OPEN"


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not _active():
		return
	var target := _target_under(click.position)
	if target.is_empty():
		return
	get_viewport().set_input_as_handled()
	match target.kind:
		"rideau":
			_station.toggle_curtain(target.id)
		"combinaison":
			_station.set_suit_worn(true)
		"porte":
			_station.set_suit_worn(false)
		"valve":
			_station.toggle_airlock_pressure()
		"couchette":
			(get_tree().get_first_node_in_group(CampaignDirector.GROUP) as CampaignDirector).sleep()
		_:
			_station.toggle_hatch(target.id)


func _active() -> bool:
	return _station != null and not ScreenSeat.any_seated(get_tree())


## Écoutille ouvrable, rideau ou pièce du sas sous le curseur, à portée (premier obstacle touché par le rayon, zones
## de clic des rideaux comprises) : {kind : « ecoutille », « rideau », « combinaison », « porte » ou « valve », id},
## vide sinon.
func _target_under(mouse_position: Vector2) -> Dictionary:
	var origin := _camera.project_ray_origin(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(origin,
			origin + _camera.project_ray_normal(mouse_position) * reach_m)
	query.exclude = [_observer.get_rid()]
	query.collide_with_areas = true
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return {}
	var curtain := _station.curtain_id_for(hit.collider as Node)
	if curtain != "":
		return {"kind": "rideau", "id": curtain}
	var part := _station.airlock_part_for(hit.collider as Node)
	if part != "":
		return {"kind": part, "id": ""}
	var hatch := _station.hatch_id_for(hit.collider as Node)
	if hatch != "":
		return {"kind": "ecoutille", "id": hatch}
	# Couchette : cliquable seulement en campagne, la journée terminée (CampaignDirector.can_sleep).
	var director := get_tree().get_first_node_in_group(CampaignDirector.GROUP) as CampaignDirector
	if director and director.can_sleep() and _is_under(hit.collider as Node, BUNK):
		return {"kind": "couchette", "id": ""}
	return {}


static func _is_under(node: Node, ancestor_name: String) -> bool:
	while node:
		if node.name == ancestor_name:
			return true
		node = node.get_parent()
	return false
