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
## Même mécanique de vue que TvConsole (scripts/tv_console.gd).

signal seated_changed(seated: bool)

const SCREEN_NODE := "Interactif_Ecran_08"
const VIEWPORT_HEIGHT := 600

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
var _screen: MeshInstance3D
var _viewport: SubViewport
var _display: CommDisplay
var _material: ShaderMaterial
## Dernière luminosité envoyée au shader (renvoyée seulement si elle change).
var _energy_applied := -1.0
## Dalle dans le repère du maillage : coin haut gauche (UV 0, 0), côté vers la droite, côté vers le bas.
var _top_left := Vector3.ZERO
var _axis_u := Vector3.ZERO
var _axis_v := Vector3.ZERO
var _seated := false
var _moving := false
var _mouse_position := Vector2.ZERO
var _last_uv := Vector2(0.5, 0.5)
var _mouse_inside := false
var _return_position := Vector3.ZERO
var _return_rotation := Quaternion.IDENTITY
var _tween: Tween
var _hover_label: Label
var _exit_hint: Label


func _ready() -> void:
	add_to_group(ScreenSeat.GROUP)
	_observer = get_node(observer_path)
	_camera = _observer.get_node("Camera") as Camera3D
	_station = get_node(station_path) as Station
	_radio = get_node_or_null(radio_path) as RadioComms
	_screen = _station.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	var surface := _measure_screen()
	if surface < 0 or _radio == null:
		push_error("CommConsole : écran %s ou radio introuvable" % SCREEN_NODE)
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = Vector2i(roundi(VIEWPORT_HEIGHT * _axis_u.length() / _axis_v.length()), VIEWPORT_HEIGHT)
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_display = CommDisplay.new()
	_display.name = "Display"
	_display.radio = _radio
	_display.size = Vector2(_viewport.size)
	_display.quit_requested.connect(func() -> void:
		if _seated and not _moving:
			_stand_up())
	_viewport.add_child(_display)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/tech_screen.gdshader")
	_material.set_shader_parameter("screen_texture", _viewport.get_texture())
	_material.set_shader_parameter("scan_depth", 0.08)
	_screen.set_surface_override_material(surface, _material)
	_build_hints()


func is_seated() -> bool:
	return _seated


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and _hover_label:
		_hover_label.visible = false
		_exit_hint.visible = false


func _set_energy(value: float) -> void:
	if is_equal_approx(value, _energy_applied):
		return
	_energy_applied = value
	_material.set_shader_parameter("energy", value)


func _process(_delta: float) -> void:
	_set_energy(screen_energy * (1.0 - _station.get_blackout()))
	var hovering := not _seated and not _moving and not ScreenSeat.any_seated(get_tree()) \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _screen_uv(_mouse_position, reach_m) != Vector2(-1, -1)
	_hover_label.visible = hovering
	if hovering:
		_hover_label.position = _mouse_position + Vector2(18, 14)
		_hover_label.reset_size()
	_exit_hint.visible = _seated and not _moving
	# Écran hors du module (loin) : l'image n'est plus rendue.
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(_screen.global_position) < 12.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	_display.set_process(near)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving \
			or ScreenSeat.any_seated(get_tree()):
		return
	if _screen_uv(click.position, reach_m) != Vector2(-1, -1):
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
		if button == null or button.pressed:
			return
		uv = _last_uv
	_mouse_inside = ScreenSeat.set_mouse_inside(_viewport, true, _mouse_inside)
	_last_uv = uv
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = uv * Vector2(_viewport.size)
	forwarded.global_position = forwarded.position
	_viewport.push_input(forwarded)


func _sit() -> void:
	_return_position = _observer.global_position
	_return_rotation = _camera.quaternion
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
	_observer.process_mode = Node.PROCESS_MODE_DISABLED
	_seated = true
	_display.mark_shown()
	_move_to(eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _stand_up() -> void:
	_mouse_inside = ScreenSeat.set_mouse_inside(_viewport, false, _mouse_inside)
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


## Dalle : la face du matériau d'écran (extras.materiau_ecran) tournée vers l'observateur ; coins repérés par leurs UV
## (0, 0 en haut à gauche de l'image). Rend l'indice de la surface, -1 sinon.
func _measure_screen() -> int:
	if _screen == null or _screen.mesh == null:
		return -1
	var wanted := String((_screen.get_meta("extras", {}) as Dictionary).get("materiau_ecran", ""))
	for s in _screen.mesh.get_surface_count():
		var material := _screen.mesh.surface_get_material(s)
		if material == null or material.resource_name != wanted:
			continue
		var arrays := _screen.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var corner := {}
		for k in vertices.size():
			corner[Vector2i(roundi(uvs[k].x), roundi(uvs[k].y))] = vertices[k]
		if not (corner.has(Vector2i(0, 0)) and corner.has(Vector2i(1, 0)) and corner.has(Vector2i(0, 1))):
			return -1
		_top_left = corner[Vector2i(0, 0)]
		_axis_u = corner[Vector2i(1, 0)] - _top_left
		_axis_v = corner[Vector2i(0, 1)] - _top_left
		return s
	return -1


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


func _build_hints() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hover_label = Label.new()
	_hover_label.text = "COMM_HOVER"
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.add_theme_stylebox_override("normal", _bubble_style())
	_hover_label.visible = false
	layer.add_child(_hover_label)
	_exit_hint = Label.new()
	_exit_hint.text = "COMM_EXIT_HINT"
	_exit_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_hint.add_theme_stylebox_override("normal", _bubble_style())
	_exit_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	_exit_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_exit_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_exit_hint.visible = false
	layer.add_child(_exit_hint)


func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.8)
	style.border_color = Color(0.55, 0.7, 0.9, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style
