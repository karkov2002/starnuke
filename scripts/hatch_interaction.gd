class_name HatchInteraction
extends Node
## Écoutilles, rideaux et sas de sortie manipulables à la souris (nœud HatchInteraction de scenes/orbit_view.tscn).
## Rayon de la caméra contre les collisions (la porte d'une écoutille a son corps de collision, AnimatableBody3D, qui
## suit la charnière ; un rideau, sa zone de clic Area3D, qui suit le tissu) :
## - survol à portée (reach_m) : bulle « Ouvrir / Fermer l'écoutille », « Ouvrir / Fermer le rideau », « Enfiler /
##   Ranger la combinaison », « Vider / Remplir le sas », ou la raison d'un verrouillage (écoutille du sas sous pression
##   ou vide, cycle en cours, écoutilles à fermer avant la valve) ;
## - clic gauche : mouvement animé (Station.toggle_hatch, Station.toggle_curtain ; un clic pendant le mouvement
##   l'inverse), Station.set_suit_worn, Station.toggle_airlock_pressure.
## Inactif au poste de pilotage. Les clics pris avant (tablette, interface) ne lui parviennent pas.

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
@export var console_path: NodePath = ^"../PilotConsole"
## Distance maximale (m) entre l'œil et la porte.
@export var reach_m := 2.5

var _station: Station
var _observer: CollisionObject3D
var _camera: Camera3D
var _console: PilotConsole
var _hover_layer: CanvasLayer
var _hover_label: Label
var _mouse_position := Vector2.ZERO


func _ready() -> void:
	_station = get_node(station_path) as Station
	_observer = get_node(observer_path) as CollisionObject3D
	_camera = _observer.get_node("Camera") as Camera3D
	_console = get_node_or_null(console_path) as PilotConsole
	_hover_layer = CanvasLayer.new()
	_hover_layer.layer = 5
	add_child(_hover_layer)
	_hover_label = Label.new()
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.add_theme_stylebox_override("normal", _bubble_style())
	_hover_label.visible = false
	_hover_layer.add_child(_hover_label)


# En pause (menu Échap), _process s'arrête : la bulle ne doit pas rester figée par-dessus le menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and _hover_label:
		_hover_label.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_position = (event as InputEventMouse).position


func _process(_delta: float) -> void:
	var target := _target_under(_mouse_position) if _active() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else {}
	_hover_label.visible = not target.is_empty()
	if not target.is_empty():
		match target.kind:
			"rideau":
				_hover_label.text = "CURTAIN_OPEN" if _station.is_curtain_closing(target.id) else "CURTAIN_CLOSE"
			"combinaison":
				_hover_label.text = "SUIT_PUT_ON"
			"porte":
				_hover_label.text = "SUIT_STOW"
			"valve":
				var reason := _station.airlock_valve_lock_reason()
				_hover_label.text = reason if reason != "" else \
						("AIRLOCK_DEPRESSURIZE" if _station.get_airlock_pressure() > 0.5 else "AIRLOCK_REPRESSURIZE")
			_:
				var closing := _station.is_hatch_opening(target.id)
				var locked := "" if closing else _station.hatch_lock_reason(target.id)
				_hover_label.text = "HATCH_CLOSE" if closing else (locked if locked != "" else "HATCH_OPEN")
		_hover_label.position = _mouse_position + Vector2(18, 14)
		_hover_label.reset_size()


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
	return {"kind": "ecoutille", "id": hatch} if hatch != "" else {}


func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.8)
	style.border_color = Color(0.55, 0.7, 0.9, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style
