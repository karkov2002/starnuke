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

signal seated_changed(seated: bool)

const SCREEN_NODE := "Interactif_Ecran_Principal"
const SCREEN_MATERIAL := "Ecran_15"
## Hauteur de l'image de l'interface (pixels) ; la largeur suit les proportions de la dalle.
const VIEWPORT_HEIGHT := 1000

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
var _screen: MeshInstance3D
var _viewport: SubViewport
var _display: PilotDisplay
## Dalle dans le repère du maillage : coin haut gauche, côté vers la droite, côté vers le bas.
var _top_left := Vector3.ZERO
var _axis_u := Vector3.ZERO
var _axis_v := Vector3.ZERO
var _seated := false
var _moving := false
## Dernière position du curseur reçue (repère de la vue du jeu).
var _mouse_position := Vector2.ZERO
## Dernier point de l'écran (0–1) transmis à l'interface.
var _last_uv := Vector2(0.5, 0.5)
## Souris sur l'écran (entrée envoyée au SubViewport, cf. ScreenSeat.set_mouse_inside).
var _mouse_inside := false
var _return_position := Vector3.ZERO
var _return_rotation := Quaternion.IDENTITY
var _tween: Tween
var _hover_layer: CanvasLayer
var _hover_label: Label
var _exit_hint: Label


func _ready() -> void:
	add_to_group(ScreenSeat.GROUP)
	_observer = get_node(observer_path)
	_camera = _observer.get_node("Camera") as Camera3D
	var station := get_node(station_path)
	_screen = station.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	if _screen == null or not _measure_screen():
		push_error("PilotConsole : écran %s (matériau %s) introuvable" % [SCREEN_NODE, SCREEN_MATERIAL])
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = Vector2i(roundi(VIEWPORT_HEIGHT * _axis_u.length() / _axis_v.length()), VIEWPORT_HEIGHT)
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_embed_subwindows = true
	add_child(_viewport)
	_display = PilotDisplay.new()
	_display.size = Vector2(_viewport.size)
	_orbit = get_node(orbit_path) as OrbitSimulation
	_display.orbit = _orbit
	_flight_computer = get_node(flight_computer_path) as FlightComputer
	_display.flight_computer = _flight_computer
	_viewport.add_child(_display)
	_apply_screen_material()
	_build_hints()


func is_seated() -> bool:
	return _seated


# En pause (menu Échap), _process s'arrête : les indications ne doivent pas rester figées par-dessus le menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and _hover_label:
		_hover_label.visible = false
		_exit_hint.visible = false


func _process(_delta: float) -> void:
	var hovering := not _seated and not _moving and not ScreenSeat.any_seated(get_tree()) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and _screen_uv(_mouse_position, reach_m) != Vector2(-1, -1)
	_hover_label.visible = hovering
	if hovering:
		_hover_label.position = _mouse_position + Vector2(18, 14)
		_hover_label.reset_size()
	_exit_hint.visible = _seated and not _moving


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving:
		return
	if _screen_uv(click.position, reach_m) != Vector2(-1, -1):
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
	var hud := get_tree().get_first_node_in_group(Hud.GROUP) as Hud
	if hud and hud.is_over_controls(mouse.position):
		return
	get_viewport().set_input_as_handled()
	if _moving:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_stand_up()
		return
	var uv := _screen_uv(mouse.position, INF)
	if uv == Vector2(-1, -1):
		_mouse_inside = ScreenSeat.set_mouse_inside(_viewport, false, _mouse_inside)
		# Relâchement hors de l'écran : transmis quand même (au dernier point), sinon un bouton maintenu (BURN) ou un
		# curseur resterait tenu.
		if button == null or button.pressed:
			return
		uv = _last_uv
	_mouse_inside = ScreenSeat.set_mouse_inside(_viewport, true, _mouse_inside)
	_last_uv = uv
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = uv * Vector2(_viewport.size)
	forwarded.global_position = forwarded.position
	_viewport.push_input(forwarded)


## Position (0–1) du point de l'écran sous le curseur, (-1, -1) hors de l'écran ou au-delà de max_distance.
func _screen_uv(mouse_position: Vector2, max_distance: float) -> Vector2:
	var origin := _camera.project_ray_origin(mouse_position)
	var direction := _camera.project_ray_normal(mouse_position)
	var to_world := _screen.global_transform
	var top_left := to_world * _top_left
	var u := to_world.basis * _axis_u
	var v := to_world.basis * _axis_v
	var normal := u.cross(v).normalized()
	var facing := direction.dot(normal)
	if absf(facing) < 1e-4:
		return Vector2(-1, -1)
	var distance := (top_left - origin).dot(normal) / facing
	if distance <= 0.0 or distance > max_distance:
		return Vector2(-1, -1)
	var offset := origin + direction * distance - top_left
	var uv := Vector2(offset.dot(u) / u.length_squared(), offset.dot(v) / v.length_squared())
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


func _sit() -> void:
	_return_position = _observer.global_position
	_return_rotation = _camera.quaternion
	# Œil face au centre de la dalle, à la distance où elle remplit screen_fill de la vue (hauteur et largeur).
	var to_world := _screen.global_transform
	var u := to_world.basis * _axis_u
	var v := to_world.basis * _axis_v
	var center := to_world * (_top_left + (_axis_u + _axis_v) * 0.5)
	var toward_viewer := v.cross(u).normalized()
	var half_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var distance := maxf(v.length() / (2.0 * half_tan * screen_fill), u.length() / (2.0 * half_tan * aspect * screen_fill))
	var eye := center + toward_viewer * distance
	var look := Basis.looking_at(-toward_viewer, -v.normalized())
	var local_rotation := (_observer.global_basis.inverse() * look).get_rotation_quaternion()
	_set_observer_active(false)
	# Au poste, le temps repasse à ×1 (les manœuvres se jouent en temps réel).
	_orbit.time_scale = 1.0
	_seated = true
	_move_to(eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _stand_up() -> void:
	_mouse_inside = ScreenSeat.set_mouse_inside(_viewport, false, _mouse_inside)
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


## Rectangle de la dalle (faces du matériau Ecran_15 tournées vers l'observateur, normale −X du maillage), repère
## du maillage. La droite de l'image est à droite d'un observateur qui regarde la dalle, tête vers +Y.
func _measure_screen() -> bool:
	var mesh := _screen.mesh
	for s in mesh.get_surface_count():
		var material := mesh.surface_get_material(s)
		if material == null or material.resource_name != SCREEN_MATERIAL:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for k in vertices.size():
			if normals[k].x < -0.99:
				lo = lo.min(vertices[k])
				hi = hi.max(vertices[k])
		if lo == Vector3.INF:
			return false
		_top_left = Vector3(lo.x, hi.y, lo.z)
		_axis_u = Vector3(0.0, 0.0, hi.z - lo.z)
		_axis_v = Vector3(0.0, lo.y - hi.y, 0.0)
		return true
	return false


func _apply_screen_material() -> void:
	var original: BaseMaterial3D = null
	var surface := -1
	for s in _screen.mesh.get_surface_count():
		var candidate := _screen.mesh.surface_get_material(s)
		if candidate and candidate.resource_name == SCREEN_MATERIAL:
			original = candidate as BaseMaterial3D
			surface = s
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/pilot_screen.gdshader")
	material.set_shader_parameter("screen_texture", _viewport.get_texture())
	material.set_shader_parameter("top_left", _top_left)
	material.set_shader_parameter("axis_u", _axis_u)
	material.set_shader_parameter("axis_v", _axis_v)
	var base_energy := original.emission_energy_multiplier if original and original.emission_enabled else 1.0
	material.set_shader_parameter("energy", base_energy * screen_energy)
	_screen.set_surface_override_material(surface, material)


func _build_hints() -> void:
	_hover_layer = CanvasLayer.new()
	_hover_layer.layer = 5
	add_child(_hover_layer)
	_hover_label = Label.new()
	_hover_label.text = "PILOT_HOVER"
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.add_theme_stylebox_override("normal", _bubble_style())
	_hover_label.visible = false
	_hover_layer.add_child(_hover_label)
	_exit_hint = Label.new()
	_exit_hint.text = "PILOT_EXIT_HINT"
	_exit_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_hint.add_theme_stylebox_override("normal", _bubble_style())
	_exit_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	_exit_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_exit_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_exit_hint.visible = false
	_hover_layer.add_child(_exit_hint)


func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.8)
	style.border_color = Color(0.55, 0.7, 0.9, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style
