class_name PilotConsole
extends Node
## Poste de pilotage du module Commande (nœud PilotConsole de scenes/orbit_view.tscn). Le grand écran de la console
## (Interactif_Ecran_Principal, dalle au matériau Ecran_15) affiche l'interface de pilotage orbital (PilotDisplay,
## dessinée dans un SubViewport, shaders/pilot_screen.gdshader).
## - Survol de l'écran à portée (reach_m) : bulle « Contrôle orbital » au curseur.
## - Clic gauche sur l'écran : position « poste de pilotage » (la vue se cadre face à l'écran, déplacements et
##   rotation de la tête suspendus, temps ramené à ×1) ; les clics et mouvements de la souris sur l'écran sont transmis à l'interface.
##   L'interface ne réagit qu'en position « poste de pilotage ». La barre de vitesse du temps (Hud) reste cliquable.
##   La tablette se range d'elle-même (seated_changed).
## - Clic droit : on quitte le poste (retour à la position et à l'orientation d'avant).
## L'image n'est rendue que si la caméra est à moins de RENDER_DISTANCE de l'écran.
## Dalle, viewport, souris et bulles : StationScreen, ScreenInputForwarder, HoverBubble (scripts/screens/).

signal seated_changed(seated: bool)

const SCREEN_NODE := "Interactif_Ecran_Principal"
const SCREEN_MATERIAL := "Ecran_15"
const SCREEN_SHADER := preload("res://shaders/pilot_screen.gdshader")
## Hauteur de l'image de l'interface (pixels) ; la largeur suit les proportions de la dalle.
const VIEWPORT_HEIGHT := 1000
## Au-delà de cette distance (m) entre la caméra et l'écran, l'image n'est plus rendue (comme les autres écrans).
const RENDER_DISTANCE := 12.0

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"
## Distance maximale (m) entre l'œil et l'écran pour le survol et le clic.
@export var reach_m := 2.5
## Part de la hauteur (ou de la largeur) de la vue occupée par l'écran en position « poste de pilotage ».
@export_range(0.5, 1.0) var screen_fill := 0.9
## Durée (s) du passage en position « poste de pilotage » et du retour.
@export var transition_s := 0.6
## Luminosité de l'écran (multiplie l'émission d'origine du matériau Ecran_15).
@export var screen_energy := 1.0

var _observer: Node3D
var _orbit: OrbitSimulation
var _flight_computer: FlightComputer
var _camera: Camera3D
var _screen: StationScreen
var _viewport: SubViewport
var _display: PilotDisplay
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


func _ready() -> void:
	add_to_group(ScreenSeat.GROUP)
	_observer = get_node(observer_path)
	_camera = _observer.get_node("Camera") as Camera3D
	var station := get_node(station_path)
	var mesh := station.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	if mesh and mesh.mesh:
		_screen = StationScreen.new()
		_screen.mesh_instance = mesh
		# Dalle : faces du matériau Ecran_15 tournées vers l'observateur (normale −X du maillage ; ses UV ne servent pas).
		if not _screen.measure_by_normal(SCREEN_MATERIAL, Vector3.LEFT):
			_screen = null
	if _screen == null:
		push_error("PilotConsole : écran %s (matériau %s) introuvable" % [SCREEN_NODE, SCREEN_MATERIAL])
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_viewport = _screen.make_viewport(VIEWPORT_HEIGHT, true)
	add_child(_viewport)
	_input_forwarder = ScreenInputForwarder.new(_viewport)
	_display = PilotDisplay.new()
	_display.size = Vector2(_viewport.size)
	_orbit = get_node(orbit_path) as OrbitSimulation
	_display.orbit = _orbit
	_flight_computer = get_node(flight_computer_path) as FlightComputer
	_display.flight_computer = _flight_computer
	_viewport.add_child(_display)
	_screen.apply_shader(SCREEN_SHADER, _viewport.get_texture(), {"top_left": _screen.top_left,
			"axis_u": _screen.axis_u, "axis_v": _screen.axis_v, "energy": _screen.base_emission() * screen_energy})
	_bubble = HoverBubble.new("PILOT_HOVER", "PILOT_EXIT_HINT")
	add_child(_bubble)
	_hud = get_tree().get_first_node_in_group(Hud.GROUP) as Hud


func is_seated() -> bool:
	return _seated


func _process(_delta: float) -> void:
	var hovering := not _seated and not _moving and not ScreenSeat.any_seated(get_tree()) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and _screen.uv_at(_camera, _mouse_position, reach_m) != StationScreen.NONE
	_bubble.set_hover(hovering, _mouse_position)
	_bubble.set_exit_visible(_seated and not _moving)
	# Écran hors du module (loin) : l'image n'est plus rendue ni l'interface mise à jour.
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(_screen.global_position()) < RENDER_DISTANCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	_display.set_process(near)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving:
		return
	if _screen.uv_at(_camera, click.position, reach_m) != StationScreen.NONE:
		get_viewport().set_input_as_handled()
		_sit()


# En position « poste de pilotage », la souris est entièrement prise par l'écran (avant l'interface 2D du jeu et
# avant la caméra) : clic droit pour quitter, le reste est transmis à l'interface quand le curseur est sur l'écran.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	_mouse_position = mouse.position
	if not _seated and not _moving:
		return
	# La barre de vitesse du temps reste utilisable au poste.
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
	# Œil face au centre de la dalle, à la distance où elle remplit screen_fill de la vue (hauteur et largeur).
	var pose := _screen.seat_pose(_camera, get_viewport().get_visible_rect().size.aspect(), screen_fill)
	var local_rotation := (_observer.global_basis.inverse() * (pose.look as Basis)).get_rotation_quaternion()
	_set_observer_active(false)
	# Au poste, le temps repasse à ×1 (les manœuvres se jouent en temps réel).
	_orbit.time_scale = 1.0
	_seated = true
	_move_to(pose.eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _stand_up() -> void:
	_input_forwarder.leave()
	# Quitter le poste relâche BURN.
	_flight_computer.end_burn()
	_seated = false
	_move_to(_return_position, _return_rotation, func() -> void:
		_moving = false
		_set_observer_active(true))
	seated_changed.emit(false)


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
		(_observer as CharacterBody3D).velocity = Vector3.ZERO
