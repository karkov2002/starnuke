class_name CommConsole
extends Node
## Écran de communication radio du module Commande (nœud CommConsole de scenes/orbit_view.tscn) : l'écran SCREEN_NODE
## (retiré des écrans d'ambiance TechScreens) affiche le programme COMM.EXE (CommDisplay, dans un SubViewport), façade
## de la radio de la station (RadioComms : canaux, liaison, messages).
## - Survol de l'écran à portée (reach_m) : bulle « Communications radio » ; clic gauche : « vue radio » (la vue se
##   cadre face à l'écran, comme pour la télévision ; déplacements et tête suspendus) ; la souris est transmise à
##   l'interface, et le clavier aussi (touches de fonction, flèches, chiffres, Entrée). Clic droit (ou F10) : on
##   quitte la vue.
## Groupe ScreenSeat.GROUP : la tablette se range et les écoutilles ne se cliquent plus pendant la vue radio.
## Même mécanique de vue que TvConsole (scripts/tv_console.gd). Dalle, viewport, souris et bulles : StationScreen,
## ScreenInputForwarder, HoverBubble (scripts/screens/). L'image n'est rendue qu'à moins de RENDER_DISTANCE.

signal seated_changed(seated: bool)

const SCREEN_NODE := "Interactif_Ecran_08"
const VIEWPORT_HEIGHT := 600
const RENDER_DISTANCE := 12.0

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
@export var radio_path: NodePath = ^"../Radio"
@export var reach_m := 2.5
@export_range(0.5, 1.0) var screen_fill := 0.9
@export var transition_s := 0.6
@export var screen_energy := 1.1

var _observer: Node3D
var _camera: Camera3D
var _station: Station
var _radio: RadioComms
var _screen: StationScreen
var _viewport: SubViewport
var _display: CommDisplay
var _input_forwarder: ScreenInputForwarder
var _bubble: HoverBubble
var _hud: Hud
var _seated := false
var _moving := false
var _mouse_position := Vector2.ZERO
var _return_position := Vector3.ZERO
var _return_rotation := Quaternion.IDENTITY
var _tween: Tween


func _ready() -> void:
	add_to_group(ScreenSeat.GROUP)
	_observer = get_node(observer_path)
	_camera = _observer.get_node("Camera") as Camera3D
	_station = get_node(station_path) as Station
	_radio = get_node_or_null(radio_path) as RadioComms
	_screen = StationScreen.find(_station, SCREEN_NODE)
	if _screen == null or _radio == null:
		push_error("CommConsole : écran %s ou radio introuvable" % SCREEN_NODE)
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_viewport = _screen.make_viewport(VIEWPORT_HEIGHT)
	add_child(_viewport)
	_input_forwarder = ScreenInputForwarder.new(_viewport)
	_display = CommDisplay.new()
	_display.name = "Display"
	_display.radio = _radio
	_display.size = Vector2(_viewport.size)
	_display.quit_requested.connect(func() -> void:
		if _seated and not _moving:
			_stand_up())
	_viewport.add_child(_display)
	_screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(), {"scan_depth": 0.08})
	_bubble = HoverBubble.new("COMM_HOVER", "COMM_EXIT_HINT")
	add_child(_bubble)
	_hud = get_tree().get_first_node_in_group(Hud.GROUP) as Hud


func is_seated() -> bool:
	return _seated


func _process(_delta: float) -> void:
	_screen.set_energy(screen_energy * (1.0 - _station.get_blackout()))
	var hovering := not _seated and not _moving and not ScreenSeat.any_seated(get_tree()) \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _screen.uv_at(_camera, _mouse_position, reach_m) != StationScreen.NONE
	_bubble.set_hover(hovering, _mouse_position)
	_bubble.set_exit_visible(_seated and not _moving)
	# Écran hors du module (loin) : l'image n'est plus rendue.
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(_screen.global_position()) < RENDER_DISTANCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	_display.set_process(near)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving \
			or ScreenSeat.any_seated(get_tree()):
		return
	if _screen.uv_at(_camera, click.position, reach_m) != StationScreen.NONE:
		get_viewport().set_input_as_handled()
		_sit()


# En vue radio, la souris et le clavier sont pris par l'écran : clic droit pour quitter, le reste est transmis.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse:
		_mouse_position = mouse.position
	if not _seated:
		return
	var key := event as InputEventKey
	if key:
		if not _moving and _display.handle_key(key):
			get_viewport().set_input_as_handled()
		return
	if mouse == null:
		return
	if _hud and _hud.is_over_controls(mouse.position):
		return
	get_viewport().set_input_as_handled()
	if _moving:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_stand_up()
		return
	_input_forwarder.forward(mouse, _screen.uv_at(_camera, mouse.position))


func _sit() -> void:
	_return_position = _observer.global_position
	_return_rotation = _camera.quaternion
	var pose := _screen.seat_pose(_camera, get_viewport().get_visible_rect().size.aspect(), screen_fill)
	var local_rotation := (_observer.global_basis.inverse() * (pose.look as Basis)).get_rotation_quaternion()
	_observer.process_mode = Node.PROCESS_MODE_DISABLED
	_seated = true
	_display.mark_shown()
	_move_to(pose.eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _stand_up() -> void:
	_input_forwarder.leave()
	_seated = false
	_move_to(_return_position, _return_rotation, func() -> void:
		_moving = false
		_observer.process_mode = Node.PROCESS_MODE_INHERIT
		(_observer as CharacterBody3D).velocity = Vector3.ZERO)
	seated_changed.emit(false)


func _move_to(eye: Vector3, rotation: Quaternion, done: Callable) -> void:
	if _tween:
		_tween.kill()
	_moving = true
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_observer, "global_position", eye, transition_s)
	_tween.tween_property(_camera, "quaternion", rotation, transition_s)
	_tween.chain().tween_callback(done)
