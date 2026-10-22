class_name ScreenSeatConsole
extends ScreenConsole
## Écran devant lequel on s'installe (poste de pilotage, radio, télévision) : base commune de PilotConsole,
## CommConsole et TvConsole, qui n'ont plus que leur interface, leurs dépendances et quelques réactions propres.
## - Survol de la dalle à portée (reach_m), aucun poste occupé, souris visible : bulle _hover_key() au curseur.
## - Clic gauche sur la dalle : vue « assise » : l'œil glisse en transition_s face au centre de la dalle, à la distance
##   où elle occupe screen_fill de la vue (hauteur ou largeur selon les proportions de la fenêtre) ; l'observateur
##   (corps et tête : déplacements, rotation à la souris, roulis) est suspendu. Toute la souris est alors prise par
##   l'écran : mouvements et clics sur la dalle transmis à l'interface (ScreenInputForwarder), le reste ignoré, sauf
##   la barre de vitesse du temps du Hud, qui reste cliquable ; les touches passent par _handle_key. Indication de
##   sortie _exit_key() en bas de la vue.
## - Clic droit (ou stand_up() depuis l'interface) : retour à la position et à l'orientation d'avant.
## Groupe GROUP : la tablette se range (seated_changed) et les écoutilles ne se cliquent plus tant qu'un poste est
## occupé (any_seated). Pendant la transition (_moving), ni survol ni clic : la souris reste prise par l'écran.
## Crochets, en plus de ceux de ScreenConsole : _hover_key, _exit_key, _on_seated, _on_stood_up, _handle_key.

signal seated_changed(seated: bool)

const GROUP := &"screen_seat"

@export var observer_path: NodePath = ^"../Observer"
## Distance maximale (m) entre l'œil et l'écran pour le survol et le clic.
@export var reach_m := 2.5
## Part de la hauteur (ou de la largeur) de la vue occupée par l'écran en vue assise.
@export_range(0.5, 1.0) var screen_fill := 0.9
## Durée (s) du passage en vue assise et du retour.
@export var transition_s := 0.6

var _observer: CharacterBody3D
var _camera: Camera3D
var _input_forwarder: ScreenInputForwarder
var _bubble: HoverBubble
var _hud: Hud
var _seated := false
var _moving := false
## Dernière position du curseur reçue (repère de la vue du jeu).
var _mouse_position := Vector2.ZERO
var _return_position := Vector3.ZERO
var _return_rotation := Quaternion.IDENTITY
var _tween: Tween


## Un poste de la scène est occupé.
static func any_seated(tree: SceneTree) -> bool:
	for seat in tree.get_nodes_in_group(GROUP):
		if seat.is_seated():
			return true
	return false


func _ready() -> void:
	add_to_group(GROUP)
	_observer = get_node_or_null(observer_path) as CharacterBody3D
	_camera = _observer.get_node_or_null(^"Camera") as Camera3D if _observer else null
	if _camera == null:
		_fail("observateur %s introuvable" % observer_path)
		return
	super()
	if _viewport == null:
		return
	_input_forwarder = ScreenInputForwarder.new(_viewport)
	_bubble = HoverBubble.new(_hover_key(), _exit_key())
	add_child(_bubble)
	_hud = get_tree().get_first_node_in_group(Hud.GROUP) as Hud


func is_seated() -> bool:
	return _seated


func _process(delta: float) -> void:
	super(delta)
	var hovering := not _seated and not _moving and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and _screen.uv_at(_camera, _mouse_position, reach_m) != StationScreen.NONE and not any_seated(get_tree())
	_bubble.set_hover(hovering, _mouse_position)
	_bubble.set_exit_visible(_seated and not _moving)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving:
		return
	if _screen.uv_at(_camera, click.position, reach_m) != StationScreen.NONE and not any_seated(get_tree()):
		get_viewport().set_input_as_handled()
		_sit()


# En vue assise, la souris est entièrement prise par l'écran (avant l'interface 2D du jeu et avant la caméra) : clic
# droit pour quitter, le reste est transmis à l'interface quand le curseur est sur la dalle ; les touches vont à
# _handle_key.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse:
		_mouse_position = mouse.position
	if not _seated and not _moving:
		return
	var key := event as InputEventKey
	if key:
		if _seated and not _moving and _handle_key(key):
			get_viewport().set_input_as_handled()
		return
	if mouse == null:
		return
	# La barre de vitesse du temps reste utilisable au poste.
	if _hud and _hud.is_over_controls(mouse.position):
		return
	get_viewport().set_input_as_handled()
	if _moving:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		stand_up()
		return
	_input_forwarder.forward(mouse, _screen.uv_at(_camera, mouse.position))


## Quitter le poste (clic droit, ou commande de l'interface : F10 de COMM.EXE) ; sans effet en transition.
func stand_up() -> void:
	if not _seated or _moving:
		return
	_input_forwarder.leave()
	_seated = false
	_on_stood_up()
	_move_to(_return_position, _return_rotation, func() -> void:
		_moving = false
		_set_observer_active(true))
	seated_changed.emit(false)


func _sit() -> void:
	_return_position = _observer.global_position
	_return_rotation = _camera.quaternion
	# Œil face au centre de la dalle, à la distance où elle remplit screen_fill de la vue (hauteur et largeur).
	var pose := _screen.seat_pose(_camera, get_viewport().get_visible_rect().size.aspect(), screen_fill)
	var local_rotation := (_observer.global_basis.inverse() * (pose.look as Basis)).get_rotation_quaternion()
	_set_observer_active(false)
	_seated = true
	_on_seated()
	_move_to(pose.eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _move_to(eye: Vector3, rotation: Quaternion, done: Callable) -> void:
	if _tween:
		_tween.kill()
	_moving = true
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_observer, "global_position", eye, transition_s)
	_tween.tween_property(_camera, "quaternion", rotation, transition_s)
	_tween.chain().tween_callback(done)


## Corps et tête de l'observateur : déplacements, rotation à la souris et roulis suspendus au poste.
func _set_observer_active(active: bool) -> void:
	_observer.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if active:
		_observer.velocity = Vector3.ZERO


# --- Crochets ---------------------------------------------------------------------------------------------------------

## Clé de langue de la bulle de survol.
func _hover_key() -> String:
	return ""


## Clé de langue de l'indication de sortie, en bas de la vue assise.
func _exit_key() -> String:
	return ""


## On vient de s'installer (avant la transition).
func _on_seated() -> void:
	pass


## On quitte le poste (avant la transition de retour).
func _on_stood_up() -> void:
	pass


## Touche reçue en vue assise ; vrai si l'interface l'a utilisée (l'événement est alors consommé).
func _handle_key(_key: InputEventKey) -> bool:
	return false
