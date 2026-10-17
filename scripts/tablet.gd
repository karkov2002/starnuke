class_name Tablet
extends Node3D
## Tablette de l'observateur (nœud Observer/Camera/Tablet de scenes/orbit_view.tscn) : modèle Blender
## assets/tablet/tablet.glb (tools/blender/build_tablet.py), tenu en bas de la vue, écran tourné vers l'œil. Son écran
## (objet Ecran_Tablette, UV 0–1) affiche l'interface TabletDisplay, dessinée dans un SubViewport : date et heure,
## carte réduite, BURN, silos et tir.
## - Touche Tab (action tablet) : la tablette glisse depuis le bas de la vue (SLIDE_S) ou s'y range ; rangée, elle est
##   masquée. Ignorée pendant la saisie d'un texte et au poste de pilotage (la tablette s'y range d'elle-même).
## - Sortie, les clics et mouvements de la souris sur son écran sont transmis à l'interface (rayon de la caméra par le
##   curseur, intersecté avec la dalle) ; ailleurs, la souris garde son rôle (clic droit : tourner la tête).
## Position : écran occupant view_fill de la hauteur de la vue (selon le champ de la caméra), son bord bas à
## bottom_margin du bas de la vue, incliné pour faire face à l'œil. Éclairée par les lampes intérieures (calque
## Station.INTERIOR_LAYER) comme le reste de l'habitacle.

const MODEL := preload("res://assets/tablet/tablet.glb")
const SCREEN_NODE := "Ecran_Tablette"
const BODY_NODE := "Tablette_Coque"
## Hauteur de l'image de l'interface (pixels) : proche de la taille affichée, pour garder un texte lisible.
const VIEWPORT_HEIGHT := 560
const SLIDE_S := 0.35

@export var orbit_path: NodePath = ^"../../../Orbit"
@export var flight_computer_path: NodePath = ^"../../../FlightComputer"
@export var pilot_console_path: NodePath = ^"../../../PilotConsole"
## Part de la hauteur de la vue occupée par la tablette sortie.
## (Le haut de la tablette reste sous le centre de la vue : le réticule de tir reste visible.)
@export_range(0.2, 0.9) var view_fill := 0.38
## Marge entre le bas de la tablette et le bas de la vue (part de la hauteur de la vue).
@export var bottom_margin := 0.05
## Luminosité de l'écran (émission).
@export var screen_energy := 1.0

var _camera: Camera3D
var _model: Node3D
var _screen: MeshInstance3D
var _viewport: SubViewport
var _console: PilotConsole
## Dalle dans le repère du maillage de l'écran : coin haut gauche, côté vers la droite, côté vers le bas.
var _top_left := Vector3.ZERO
var _axis_u := Vector3.ZERO
var _axis_v := Vector3.ZERO
## Hauteur de la coque (m), pour le cadrage.
var _height := 0.19
## 0 : rangée (masquée), 1 : sortie.
var _out := 0.0
var _wanted := false
var _tween: Tween
## Bouton gauche tenu après un clic sur l'écran : le relâchement lui est transmis même hors de l'écran.
var _pressing := false
var _last_uv := Vector2(0.5, 0.5)


func _ready() -> void:
	_camera = get_parent() as Camera3D
	_console = get_node_or_null(pilot_console_path) as PilotConsole
	if _console:
		_console.seated_changed.connect(func(seated: bool) -> void:
			if seated:
				_set_wanted(false))
	_model = MODEL.instantiate()
	add_child(_model)
	for mesh_instance: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.layers |= Station.INTERIOR_LAYER
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := _model.find_child(BODY_NODE, true, false) as MeshInstance3D
	if body:
		_height = body.get_aabb().size.y
	_screen = _model.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	if _screen == null or not _measure_screen():
		push_error("Tablet : écran %s introuvable dans %s" % [SCREEN_NODE, MODEL.resource_path])
		return
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = Vector2i(roundi(VIEWPORT_HEIGHT * _axis_u.length() / _axis_v.length()), VIEWPORT_HEIGHT)
	_viewport.disable_3d = true
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var display := TabletDisplay.new()
	display.size = Vector2(_viewport.size)
	display.orbit = get_node(orbit_path) as OrbitSimulation
	display.flight_computer = get_node(flight_computer_path) as FlightComputer
	_viewport.add_child(display)
	# Même shader que l'écran du poste de pilotage : émission brute (un StandardMaterial3D émet en nits avec les
	# unités de lumière physiques du projet, 1 000 par défaut : écran tout blanc).
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/pilot_screen.gdshader")
	material.set_shader_parameter("screen_texture", _viewport.get_texture())
	material.set_shader_parameter("top_left", _top_left)
	material.set_shader_parameter("axis_u", _axis_u)
	material.set_shader_parameter("axis_v", _axis_v)
	material.set_shader_parameter("energy", screen_energy)
	_screen.material_override = material
	visible = false
	_update_pose()


func _process(_delta: float) -> void:
	if visible:
		_update_pose()
	# Rangée, l'interface n'est pas redessinée.
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tablet") and not event.is_echo() and not StationCamera.is_typing(self) \
			and not (_console and _console.is_seated()):
		get_viewport().set_input_as_handled()
		_set_wanted(not _wanted)


func is_out() -> bool:
	return _wanted


# Tablette sortie : la souris sur son écran est pour l'interface.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null or _viewport == null or not visible or _out < 1.0 or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		return
	var uv := _screen_uv(mouse.position)
	if uv == Vector2(-1, -1):
		if not (_pressing and button and not button.pressed):
			return
		uv = _last_uv
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_pressing = button.pressed
	_last_uv = uv
	get_viewport().set_input_as_handled()
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = uv * Vector2(_viewport.size)
	forwarded.global_position = forwarded.position
	_viewport.push_input(forwarded)


func _set_wanted(out: bool) -> void:
	if out == _wanted:
		return
	_wanted = out
	if _tween:
		_tween.kill()
	visible = true
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if out else Tween.EASE_IN)
	var target := 1.0 if out else 0.0
	_tween.tween_method(_set_out, _out, target, SLIDE_S * absf(target - _out))
	if not out:
		_tween.tween_callback(func() -> void: visible = false)


func _set_out(value: float) -> void:
	_out = value
	_update_pose()


## Position dans le repère de la caméra : sortie (_out = 1) en bas de la vue face à l'œil, rangée (_out = 0) sous la
## vue.
func _update_pose() -> void:
	if _camera == null:
		return
	var half_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var distance := _height / (view_fill * 2.0 * half_tan)
	var view_height := 2.0 * distance * half_tan
	var shown_y := (-0.5 + bottom_margin + view_fill * 0.5) * view_height
	var hidden_y := shown_y - (view_fill + bottom_margin + 0.1) * view_height
	var y := lerpf(hidden_y, shown_y, _out)
	# Écran (+Z du modèle) tourné vers l'œil.
	var facing := -atan2(-shown_y, distance)
	transform = Transform3D(Basis(Vector3.RIGHT, facing), Vector3(0.0, y, -distance))


## Point de l'écran (0–1) sous le curseur, (-1, -1) hors de l'écran.
func _screen_uv(mouse_position: Vector2) -> Vector2:
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
	if distance <= 0.0:
		return Vector2(-1, -1)
	var offset := origin + direction * distance - top_left
	var uv := Vector2(offset.dot(u) / u.length_squared(), offset.dot(v) / v.length_squared())
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


## Rectangle de la dalle d'après ses UV : coin (0, 0) en haut à gauche, (1, 0) en haut à droite, (0, 1) en bas à
## gauche.
func _measure_screen() -> bool:
	var arrays := _screen.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var corners := {}
	for k in vertices.size():
		corners[Vector2i(roundi(uvs[k].x), roundi(uvs[k].y))] = vertices[k]
	if not (corners.has(Vector2i(0, 0)) and corners.has(Vector2i(1, 0)) and corners.has(Vector2i(0, 1))):
		return false
	_top_left = corners[Vector2i(0, 0)]
	_axis_u = corners[Vector2i(1, 0)] - _top_left
	_axis_v = corners[Vector2i(0, 1)] - _top_left
	return true
